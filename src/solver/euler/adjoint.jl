# Adjoint for Euler Equations

@doc """
### EulerEquationMod.calcAdjoint

Calculates the adjoint vector for a single functional

**Inputs**

*  `mesh` : Abstract DG mesh type
*  `sbp`  : Summation-By-parts operator
*  `eqn`  : Euler equation object
*  `functor` : functional to be evaluated
*  `functional_number` : Numerical identifier to obtain geometric edges on
                         which a functional acts
*  `adjoint_vec` : Resulting adjoint vector. In the parallel case, the adjoint
                   vector has the same size as eqn.q_vec, i.e. every rank has its
                   share of the adjoint vector corresponding to the dofs on the
                   rank.

**Outputs**

*  None

"""->

function calcAdjoint{Tmsh, Tsol, Tres, Tdim}(mesh::AbstractDGMesh{Tmsh},
	                sbp::AbstractSBP, eqn::EulerData{Tsol, Tres, Tdim}, opts,
                  functionalData::AbstractOptimizationData,
                  adjoint_vec::Array{Tsol,1}; functional_number::Int=1)
                  #functor, functional_number, adjoint_vec::Array{Tsol, 1})

  # Check if PETSc is initialized
  if PetscInitialized() == 0 # PETSc Not initialized before
    PetscInitialize(["-malloc", "-malloc_debug", "-ksp_monitor",  "-pc_type",
      "bjacobi", "-sub_pc_type", "ilu", "-sub_pc_factor_levels", "4",
      "ksp_gmres_modifiedgramschmidt", "-ksp_pc_side", "right",
      "-ksp_gmres_restart", "30" ])
  end

  if opts["parallel_type"] == 1
    startSolutionExchange(mesh, sbp, eqn, opts, wait=true)
  end

  # Allocate space for adjoint solve
  jacData, res_jac, rhs_vec = NonlinearSolvers.setupNewton(mesh, mesh, sbp, eqn,
                                             opts, evalResidual, alloc_rhs=true)

  # Get the residual jacobian
  ctx_residual = (evalResidual,)
  NonlinearSolvers.physicsJac(jacData, mesh, sbp, eqn, opts, res_jac, ctx_residual)

  # Re-interpolate interior q to q_bndry. This is done because the above step
  # pollutes the existing eqn.q_bndry with complex values.
  boundaryinterpolate!(mesh.sbpface, mesh.bndryfaces, eqn.q, eqn.q_bndry)
  # calculate the derivative of the function w.r.t q_vec
  func_deriv = zeros(Tsol, mesh.numDof)

  # 3D array into which func_deriv_arr gets interpolated
  func_deriv_arr = zeros(eqn.q)

  # Calculate df/dq_bndry on edges where the functional is calculated and put
  # it back in func_deriv_arr
  calcFunctionalDeriv(mesh, sbp, eqn, opts, functionalData, func_deriv_arr)

  # Assemble func_deriv
  assembleSolution(mesh, sbp, eqn, opts, func_deriv_arr, func_deriv)
  func_deriv[:] = -func_deriv[:]

  # Solve for adjoint vector. residual jacobian needs to be transposed first.
  jac_type = typeof(res_jac)
  if jac_type <: Array || jac_type <: SparseMatrixCSC
    res_jac = res_jac.'
  elseif  jac_type <: PetscMat
    PetscMatAssemblyBegin(res_jac) # Assemble residual jacobian
    PetscMatAssemblyEnd(res_jac)
    res_jac = MatTranspose(res_jac, inplace=true)
  else
    error("Unsupported jacobian type")
  end
  step_norm = NonlinearSolvers.matrixSolve(jacData, eqn, mesh, opts, res_jac,
                                         adjoint_vec, real(func_deriv), BSTDOUT)

  saveSolutionToMesh(mesh, adjoint_vec)
  fname = "adjoint_field"
  writeVisFiles(mesh, fname)

  return nothing
end

@doc """
### EulerEquationMod. calcFunctionalDeriv

Computes a 3D array of the derivative of a functional w.r.t eqn.q on all
mesh nodes.

**Inputs**

*  `mesh` : Abstract DG mesh type
*  `sbp`  : Summation-By-parts operator
*  `eqn`  : Euler equation object
*  `opts` : Options dictionary
*  `functionalData` : Functional object of super-type AbstractOptimizationData
                      that is needed for computing the adjoint vector.
                      Depending on the functional being computed, a different
                      method based on functional type may be needed to be
                      defined.
*  `func_deriv_arr` : 3D array that stores the derivative of the functional
                      w.r.t. eqn.q. The array is the same size as eqn.q

**Outputs**

*  None

"""->

function calcFunctionalDeriv{Tmsh, Tsol}(mesh::AbstractDGMesh{Tmsh}, sbp::AbstractSBP,
	                         eqn::EulerData{Tsol}, opts,
	                         functionalData::AbstractOptimizationData, func_deriv_arr)

  integrand = zeros(eqn.q_bndry)
  functional_edges = functionalData.geom_faces_functional

  # Populate integrand
  for itr = 1:length(functional_edges)
    g_edge_number = functional_edges[itr] # Extract geometric edge number
    # get the boundary array associated with the geometric edge
    itr2 = 0
    for itr2 = 1:mesh.numBC
      if findfirst(mesh.bndry_geo_nums[itr2],g_edge_number) > 0
        break
      end
    end
    start_index = mesh.bndry_offsets[itr2]
    end_index = mesh.bndry_offsets[itr2+1]
    idx_range = start_index:(end_index-1)
    bndry_facenums = sview(mesh.bndryfaces, idx_range) # faces on geometric edge i

    nfaces = length(bndry_facenums)
    q2 = zeros(Tsol, mesh.numDofPerNode)
    for i = 1:nfaces
      bndry_i = bndry_facenums[i]
      global_facenum = idx_range[i]
      for j = 1:mesh.sbpface.numnodes
        vtx_arr = mesh.topo.face_verts[:,bndry_i.face]
        q = ro_sview(eqn.q_bndry, :, j, global_facenum)
        convertToConservative(eqn.params, q, q2)
        aux_vars = ro_sview(eqn.aux_vars_bndry, :, j, global_facenum)
        x = ro_sview(mesh.coords_bndry, :, j, global_facenum)
        nrm = ro_sview(mesh.nrm_bndry, :, j, global_facenum)
        node_info = Int[itr,j,i]
        integrand_i = sview(integrand, :, j, global_facenum)

        calcIntegrandDeriv(opts, eqn.params, q2, aux_vars, nrm, integrand_i, node_info,
                           functionalData)
      end  # End for j = 1:mesh.sbpface.numnodes
    end    # End for i = 1:nfaces
  end      # End for itr = 1:length(functional_edges)

  boundaryintegrate!(mesh.sbpface, mesh.bndryfaces, integrand, func_deriv_arr)

  return nothing
end  # End function calcFunctionalDeriv


@doc """
### EulerEquationMod.calcIntegrandDeriv

Compute the derivative of the functional Integrand at a node w.r.t all the
degrees of freedom at the node.

**Inputs**

*  `opts`   : Options dictionary
*  `params` : parameter type
*  `q`      : Solution variable at a node
*  `aux_vars` : Auxiliary variables
*  `nrm`    : normal vector in the physical space
*  `integrand_deriv` : Derivative of the integrand at that particular node
*  `node_info` : Tuple containing information about the node
*  `functionalData` : Functional object that is a subtype of AbstractOptimizationData.

**Outputs**

*  None

"""->

function calcIntegrandDeriv{Tsol, Tres, Tmsh}(opts, params::ParamType{2},
                            q::AbstractArray{Tsol,1},
	                        aux_vars::AbstractArray{Tres, 1}, nrm::AbstractArray{Tmsh},
	                        integrand_deriv::AbstractArray{Tsol, 1}, node_info,
                          functionalData::BoundaryForceData{Tsol,:lift})

  pert = complex(0, 1e-20)
  aoa = params.aoa
  momentum = zeros(Tsol,2)

  for i = 1:length(q)
    q[i] += pert
    calcBoundaryFunctionalIntegrand(params, q, aux_vars, nrm, node_info, functionalData, momentum)
    val = -momentum[1]*sin(aoa) + momentum[2]*cos(aoa)
    integrand_deriv[i] = imag(val)/norm(pert)
    q[i] -= pert
  end # End for i = 1:length(q)

  return nothing
end

function calcIntegrandDeriv{Tsol, Tres, Tmsh}(opts, params::ParamType{2},
                            q::AbstractArray{Tsol,1},
	                        aux_vars::AbstractArray{Tres, 1}, nrm::AbstractArray{Tmsh},
	                        integrand_deriv::AbstractArray{Tsol, 1}, node_info,
                          functionalData::BoundaryForceData{Tsol,:drag})

  pert = complex(0, 1e-20)
  aoa = params.aoa
  momentum = zeros(Tsol,2)

  for i = 1:length(q)
    q[i] += pert
    calcBoundaryFunctionalIntegrand(params, q, aux_vars, nrm, node_info, functionalData, momentum)
    val = momentum[1]*cos(aoa) + momentum[2]*sin(aoa)
    integrand_deriv[i] = imag(val)/norm(pert)
    q[i] -= pert
  end # End for i = 1:length(q)

  return nothing
end
#=
function calcIntegrandDeriv{Tsol, Tres, Tmsh}(opts, params, q::AbstractArray{Tsol,1},
	                        aux_vars::AbstractArray{Tres, 1}, nrm::AbstractArray{Tmsh},
	                        integrand_deriv::AbstractArray{Tsol, 1}, node_info,
                          functor, functionalData)


  pert = complex(0, opts["epsilon"])

  for i = 1:length(q)
    q[i] += pert
    val = functor(params, q, aux_vars, nrm, node_info, functionalData)
    integrand_deriv[i] = imag(val)/norm(pert)
    q[i] -= pert
  end

  return nothing
end  # End function calcIntegrandDeriv
=#
