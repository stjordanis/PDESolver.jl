# globalization.jl
# this file contains the methods for applying differnent globalizations
# to Newtons method



# Inexact-Newton-Krylov
# updates krylov reltol by a factor of (residual_norm_i/residual_norm_i_1)^gamma
#------------------------------------------------------------------------------
function updateKrylov(newton_data::NewtonData)

  norm_i = newton_data.res_norm_i
  norm_i_1 = newton_data.res_norm_i_1
  gamma = newton_data.krylov_gamma
  newton_data.reltol = newton_data.reltol*(norm_i/norm_i_1)^gamma
  println("updating krylov reltol to ", newton_data.reltol)

  return nothing
end

#------------------------------------------------------------------------------


# Psuedo-Transient Continuation (aka. Implicit Euler)
# updates the jacobian with a diagonal term, as though the jac was the 
# jacobian of this function:
# (u - u_i_1)/tau + f(u)
# where f is the original residual
#------------------------------------------------------------------------------
function initEuler(mesh, sbp, eqn, opts)

  tau_l = opts["euler_tau"]  # initailize tau to something
  tau_vec = zeros(mesh.numDof)
  calcTauVec(mesh, sbp, eqn, opts, tau_l, tau_vec)

  return tau_l, tau_vec
end

function calcTauVec(mesh, sbp, eqn, opts, tau, tau_vec)
# calculate the spatially varying pseudo-timestep
  #TODO: make tau_vec = 1/tau_vec, so we don't have to do fp division when
  #      applying it
  for i=1:mesh.numEl
    for j=1:mesh.numNodesPerElement
      for k=1:mesh.numDofPerNode
	dof = mesh.dofs[k, j, i]
	tau_vec[dof] = tau/(1 + sqrt(real(mesh.jac[j, i])))
#        tau_vec[dof] = tau
      end
    end
  end

  return nothing

end



function updateEuler(newton_data)
  # updates the tau parameter for the Implicit Euler globalization
  # norm_i is the residual step norm, norm_i_1 is the previous residual norm


  println("updating tau")

  tau_l_old = newton_data.tau_l

  # update tau
  newton_data.tau_l = newton_data.tau_l * newton_data.res_norm_i_1/newton_data.res_norm_i
  
  tau_update = newton_data.tau_l/tau_l_old
  println("tau_update factor = ", tau_update)
  for i=1:length(newton_data.tau_vec)
    newton_data.tau_vec[i] *= tau_update
  end

  return nothing
end

function applyEuler(mesh, sbp, eqn, opts, newton_data, jac::Union(Array, SparseMatrixCSC))
# updates the jacobian with a diagonal term, as though the jac was the 
  println("applying Euler globalization to julia jacobian, tau = ", newton_data.tau_l)

  for i=1:mesh.numDof
    jac[i,i] -= eqn.M[i]/newton_data.tau_vec[i]
  end

  return nothing
end

function applyEuler(mesh, sbp, eqn, opts, newton_data::NewtonData, jac::PetscMat)
# this allocations memory every time
# should there be a reusable array for this?
# maybe something in newton_data?
# for explicitly stored jacobian only

  mat_type = MatGetType(jac)
  @assert mat_type != PETSc.MATSHELL

#  println("euler globalization tau = ", newton_data.tau_l)
  # create the indices

  val = [1/newton_data.tau_l]
  idx = PetscInt[0]
  idy = PetscInt[0]
  for i=1:mesh.numDof
    idx[1] = i-1
    idy[1] = i-1
    val[1] = -eqn.M[i]/newton_data.tau_vec[i]
    PetscMatSetValues(jac, idx, idy, val, PETSC_ADD_VALUES)
  end


  return nothing
end

function applyEuler(mesh, sbp, eqn, opts, vec::AbstractArray, newton_data::NewtonData, b::AbstractArray)
# apply the diagonal update term to the jacobian vector product

  println("applying matrix free Euler gloablization, tau = ", newton_data.tau_l)
  for i=1:mesh.numDof
    b[i] -= eqn.M[i]*(1/newton_data.tau_vec[i])*vec[i]
  end

  return nothing
end

#------------------------------------------------------------------------------
  

