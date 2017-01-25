# declare the concrete subtypes of AbstractParamType and AbstractSolutionData

@doc """
### EulerEquationMod.ParamType

  This type holds the values of any constants or paramters needed during the
  computation.  These paramters can be specified in the opts dictionary or
  have default values set here.  If there is no reasonable default, values
  are initialized to -1

  gamma and R are the independent themodynamic variables

  Whether this type should be immutable or not is an open question

  This type is paramaterized on the dimension of the equation for purposes
  of multiple dispatch

  Static Parameters:
  Tdim : dimensionality of the equation, integer, (used for dispatch)
  var_type : type of variables used used in the weak form, symbol, (used for
             dispatch), currently supported values: :conservative, :entropy
  Tsol : datatype of solution variables q
  Tres : datatype of residual
  Tmsh : datatype of mesh related quantities (mapping jacobian etc.)

  **Fields**
    # these fields have defaults:
    * cv  : specific heat constant
    * R : specific gas constant (J/(Kg*K))
    * gamma : ratio of specific heats
    * gamma_1 : gamma - 1
    # these fields do not have defaults:
    * Ma  : free stream Mach number
    * Re  : free stream Reynolds number
    * aoa : angle of attack (radians)

"""->
type ParamType{Tdim, var_type, Tsol, Tres, Tmsh} <: AbstractParamType{Tdim}
  f::IOStream
  t::Float64  # current time value
  order::Int  # accuracy of elements (p=1,2,3...)

  #TODO: consider making these vectors views of a matrix, to guarantee
  #      spatial locality
  q_vals::Array{Tsol, 1}  # resuable temporary storage for q variables at a node
  q_vals2::Array{Tsol, 1}
  q_vals3::Array{Tsol, 1}
  qg::Array{Tsol, 1}  # reusable temporary storage for boundary condition
  v_vals::Array{Tsol, 1}  # reusable storage for convert back to entropy vars.
  v_vals2::Array{Tsol, 1}
  Lambda::Array{Tsol, 1}  # diagonal matrix of eigenvalues

  # numDofPerNode x stencilsize arrays for entropy variables
  w_vals_stencil::Array{Tsol, 2}
  w_vals2_stencil::Array{Tsol, 2}

  res_vals1::Array{Tres, 1}  # reusable residual type storage
  res_vals2::Array{Tres, 1}  # reusable residual type storage
  res_vals3::Array{Tres, 1}

  flux_vals1::Array{Tres, 1}  # reusable storage for flux values
  flux_vals2::Array{Tres, 1}  # reusable storage for flux values

  sat_vals::Array{Tres, 1}  # reusable storage for SAT term

  A0::Array{Tsol, 2}  # reusable storage for the A0 matrix
  A0inv::Array{Tsol, 2}  # reusable storage for inv(A0)
  A1::Array{Tsol, 2}  # reusable storage for a flux jacobian
  A2::Array{Tsol, 2}  # reusable storage for a flux jacobian
  S2::Array{Tsol, 1}  # diagonal matrix of eigenvector scaling

  A_mats::Array{Tsol, 3}  # reusable storage for flux jacobians

  Rmat1::Array{Tres, 2}  # reusable storage for a matrix of type Tres
  Rmat2::Array{Tres, 2}

  P::Array{Tmsh, 2}  # projection matrix

  nrm::Array{Tmsh, 1}  # a normal vector
  nrm2::Array{Tmsh, 1}
  nrm3::Array{Tmsh, 1}

  h::Float64 # temporary: mesh size metric

  cv::Float64  # specific heat constant
  R::Float64  # specific gas constant used in ideal gas law (J/(Kg * K))
  gamma::Float64 # ratio of specific heats
  gamma_1::Float64 # = gamma - 1

  Ma::Float64  # free stream Mach number
  Re::Float64  # free stream Reynolds number
  aoa::Tsol  # angle of attack
  rho_free::Float64  # free stream density
  E_free::Float64 # free stream energy (4th conservative variable)

  edgestab_gamma::Float64  # edge stabilization parameter
  # debugging options
  writeflux::Bool  # write Euler flux
  writeboundary::Bool  # write boundary data
  writeq::Bool # write solution variables
  use_edgestab::Bool  # use edge stabilization
  use_filter::Bool  # use filtering
  use_res_filter::Bool # use residual filtering

  filter_mat::Array{Float64, 2}  # matrix that performs filtering operation
                                 # includes transformations to/from modal representation

  use_dissipation::Bool  # use artificial dissipation
  dissipation_const::Float64  # constant used for dissipation filter matrix

  tau_type::Int  # type of tau to use for GLS stabilization

  vortex_x0::Float64  # vortex center x coordinate at t=0
  vortex_strength::Float64  # strength of the vortex

  krylov_itr::Int  # Krylov iteration number for iterative solve
  krylov_type::Int # 1 = explicit jacobian, 2 = jac-vec prod

  Rprime::Array{Float64, 2}  # numfaceNodes x numNodesPerElement interpolation matrix
                             # this should live in sbpface instead
  # temporary storage for calcECFaceIntegrals
  A::Array{Tres, 2}
  B::Array{Tres, 3}
  iperm::Array{Int, 1}
  #=
  # timings
  t_volume::Float64  # time for volume integrals
  t_face::Float64 # time for surface integrals (interior)
  t_source::Float64  # time spent doing source term
  t_sharedface::Float64  # time for shared face integrals
  t_bndry::Float64  # time spent doing boundary integrals
  t_send::Float64  # time spent sending data
  t_wait::Float64  # time spent in MPI_Wait
  t_allreduce::Float64 # time spent in allreduce
  t_barrier::Float64  # time spent in MPI_Barrier
  t_jacobian::Float64 # time spend computing Jacobian
  t_solve::Float64 # linear solve time
  =#
  time::Timings

  function ParamType(mesh, sbp, opts, order::Integer)
  # create values, apply defaults

    t = 0.0
    myrank = mesh.myrank
    #TODO: don't open a file in non-debug mode
    f = open("log_$myrank.dat", "w")
    q_vals = Array(Tsol, Tdim + 2)
    q_vals2 = Array(Tsol, Tdim + 2)
    q_vals3 = Array(Tsol, Tdim + 2)
    qg = Array(Tsol, Tdim + 2)
    v_vals = Array(Tsol, Tdim + 2)
    v_vals2 = Array(Tsol, Tdim + 2)
    Lambda = Array(Tsol, Tdim + 2)

    w_vals_stencil = Array(Tsol, Tdim + 2, mesh.sbpface.stencilsize)
    w_vals2_stencil = Array(Tsol, Tdim + 2, mesh.sbpface.stencilsize)

    res_vals1 = Array(Tres, Tdim + 2)
    res_vals2 = Array(Tres, Tdim + 2)
    res_vals3 = Array(Tres, Tdim + 2)

    flux_vals1 = Array(Tres, Tdim + 2)
    flux_vals2 = Array(Tres, Tdim + 2)

    sat_vals = Array(Tres, Tdim + 2)

    A0 = zeros(Tsol, Tdim + 2, Tdim + 2)
    A0inv = zeros(Tsol, Tdim + 2, Tdim + 2)
    A1 = zeros(Tsol, Tdim + 2, Tdim + 2)
    A2 = zeros(Tsol, Tdim + 2, Tdim + 2)
    A_mats = zeros(Tsol, Tdim + 2, Tdim + 2, Tdim)
    S2 = Array(Tsol, Tdim + 2)

    Rmat1 = zeros(Tres, Tdim + 2, Tdim + 2)
    Rmat2 = zeros(Tres, Tdim + 2, Tdim + 2)

    P = zeros(Tmsh, Tdim + 2, Tdim + 2)

    nrm = zeros(Tmsh, Tdim)
    nrm2 = zeros(nrm)
    nrm3 = zeros(nrm)

    h = maximum(mesh.jac)

    gamma = opts[ "gamma"]
    gamma_1 = gamma - 1
    R = opts[ "R"]
    cv = R/gamma_1

    Ma = opts[ "Ma"]
    Re = opts[ "Re"]
    aoa = opts[ "aoa"]
    E_free = 1/(gamma*gamma_1) + 0.5*Ma*Ma
    rho_free = 1.0

    edgestab_gamma = opts["edgestab_gamma"]

    # debugging options
    writeflux = opts[ "writeflux"]
    writeboundary = opts[ "writeboundary"]
    writeq = opts["writeq"]
    use_edgestab = opts["use_edgestab"]
    if use_edgestab println("edge stabilization enabled") end

    use_filter = opts["use_filter"]
    if use_filter println("solution variables filter enabled") end


    use_res_filter = opts["use_res_filter"]
    if use_res_filter println("residual filter enabled") end

    if use_filter || use_res_filter || opts["use_filter_prec"]
      filter_fname = opts["filter_name"]
      filter_mat = calcFilter(sbp, filter_fname, opts)
    else
      filter_mat = Array(Float64, 0,0)
    end

    use_dissipation = opts["use_dissipation"]
    if use_dissipation println("artificial dissipation enabled") end

    dissipation_const = opts["dissipation_const"]

    tau_type = opts["tau_type"]

    vortex_x0 = opts["vortex_x0"]
    vortex_strength = opts["vortex_strength"]

    krylov_itr = 0
    krylov_type = 1 # 1 = explicit jacobian, 2 = jac-vec prod

    sbpface = mesh.sbpface

    numNodesPerElement = mesh.numNodesPerElement
    Rprime = zeros(size(sbpface.interp, 2), numNodesPerElement)
    # expand into right size (used in SBP Gamma case)
    for i=1:size(sbpface.interp, 1)
      for j=1:size(sbpface.interp, 2)
        Rprime[j, i] = sbpface.interp[i, j]
      end
    end

    A = zeros(Tres, size(Rprime))
    B = zeros(Tres, numNodesPerElement, numNodesPerElement, 2)
    iperm = zeros(Int, size(sbpface.perm, 1))



    time = Timings()
    return new(f, t, order, q_vals, q_vals2, q_vals3,  qg, v_vals, v_vals2,
               Lambda, w_vals_stencil, w_vals2_stencil, res_vals1,
               res_vals2, res_vals3, sat_vals, flux_vals1,
               flux_vals2, A0, A0inv, A1, A2, S2, A_mats, Rmat1, Rmat2, P,
               nrm, nrm2, nrm3, h, cv, R,
               gamma, gamma_1, Ma, Re, aoa,
               rho_free, E_free,
               edgestab_gamma, writeflux, writeboundary,
               writeq, use_edgestab, use_filter, use_res_filter, filter_mat,
               use_dissipation, dissipation_const, tau_type, vortex_x0,
               vortex_strength,
               krylov_itr, krylov_type,
               Rprime, A, B, iperm,
               time)

    end   # end of ParamType function

end  # end type declaration

# now that EulerData is declared, include other files that use it
@doc """
### EulerEquationMod.EulerData_

  This type is an implimentation of the abstract EulerData.  It is
  paramterized by the residual datatype Tres and the mesh datatype Tmsh
  because it stores some arrays of those types.  Tres is the 'maximum' type of
  Tsol and Tmsh, where Tsol is the type of the conservative variables.
  It is also paremterized by var_type, which should be a symbol describing
  the set of variables stored in eqn.q.  Currently supported values are
  :conservative and :entropy, which indicate the conservative variables and
  the entropy variables described in 'A New Finite Element Formulation for
  Computational Fluid Dynamics: Part I' by Hughes et al.

  Eventually there will be additional implimentations of EulerData,
  specifically a 3D one.

  Static Parameters:
    Tsol : datatype of variables solution variables, ie. the
           q vector and array
    Tres : datatype of residual. ie. eltype(res_vec)
    Tdim : dimensionality of equation, integer, (2 or 3, currently only 2 is
           supported).
    Tmsh : datatype of mesh related quantities
    var_type : symbol describing variables used in weak form, (:conservative
               or :entropy)


"""->
type EulerData_{Tsol, Tres, Tdim, Tmsh, var_type} <: EulerData{Tsol, Tres, Tdim, var_type}
# hold any constants needed for euler equation, as well as solution and data
#   needed to calculate it
# Formats of all arrays are documented in SBP.
# Only the constants are initilized here, the arrays are not.

  # this is the ParamType object that uses the same variables as
  # the EulerData_ object
  params::ParamType{Tdim, var_type, Tsol, Tres, Tmsh}
  comm::MPI.Comm
  commsize::Int
  myrank::Int

  # we include a ParamType object of all variable types, because occasionally
  # we need to do a calculation in  variables other than var_type
  # params (above) typically points to the same object as one of these
  params_conservative::ParamType{Tdim, :conservative, Tsol, Tres, Tmsh}
  params_entropy::ParamType{Tdim, :entropy, Tsol, Tres, Tmsh}

  # the following arrays hold data for all nodes
  q::Array{Tsol,3}  # holds conservative variables for all nodes
  q_face::Array{Tsol, 4}  # store solution values interpolated to faces
  q_bndry::Array{Tsol, 3}  # store solution variables interpolated to
  q_vec::Array{Tres,1}            # initial condition in vector form
  # hold fluxes in all directions
  # [ndof per node by nnodes per element by num element by num dimensions]
  aux_vars::Array{Tres, 3}        # storage for auxiliary variables
  aux_vars_face::Array{Tres,3}    # storage for aux variables interpolated
                                  # to interior faces
  aux_vars_sharedface::Array{Array{Tres, 3}, 1}  # storage for aux varables interpolate
                                       # to shared faces
  aux_vars_bndry::Array{Tres,3}   # storage for aux variables interpolated
                                  # to the boundaries
  flux_parametric::Array{Tsol,4}  # flux in xi and eta direction
  q_face_send::Array{Array{Tsol, 3}, 1}  # send buffers for sending q values
                                         # to other processes
  q_face_recv::Array{Array{Tsol, 3}, 1}  # recieve buffers for q values

  flux_face::Array{Tres, 3}  # flux for each interface, scaled by jacobian
  flux_sharedface::Array{Array{Tres, 3}, 1}  # hold shared face flux
  res::Array{Tres, 3}             # result of computation
  res_vec::Array{Tres, 1}         # result of computation in vector form
  Axi::Array{Tsol,4}               # Flux Jacobian in the xi-direction
  Aeta::Array{Tsol,4}               # Flux Jacobian in the eta-direction
  res_edge::Array{Tres, 4}       # edge based residual used for stabilization
                                  # numdof per node x nnodes per element x
				  # numEl x num edges per element

  edgestab_alpha::Array{Tmsh, 4}  # alpha needed by edgestabilization
                                  # Tdim x Tdim x nnodesPerElement x numEl
  bndryflux::Array{Tsol, 3}       # boundary flux
  stabscale::Array{Tsol, 2}       # stabilization scale factor

  # artificial dissipation operator:
  #   a square numnodes x numnodes matrix for every element
  dissipation_mat::Array{Tmsh, 3}

  Minv3D::Array{Float64, 3}       # inverse mass matrix for application to res, not res_vec
  Minv::Array{Float64, 1}         # inverse mass matrix
  M::Array{Float64, 1}            # mass matrix

  # TODO: consider overloading getField instead of having function as
  #       fields
  disassembleSolution::Function   # function: q_vec -> eqn.q
  assembleSolution::Function      # function : eqn.res -> res_vec
  multiplyA0inv::Function         # multiply an array by inv(A0), where A0
                                  # is the coefficient matrix of the time
				  # derivative
  majorIterationCallback::Function # called before every major (Newton/RK) itr

  src_func::SRCType  # functor for the source term
  flux_func::FluxType  # functor for the face flux
  volume_flux_func::FluxType  # functor for the volume flux numerical flux
                              # function
  face_element_integral_func::FaceElementIntegralType  # function for face
                                                       # integrals that use
                                                       # volume data
# minorIterationCallback::Function # called before every residual evaluation

  # inner constructor
  function EulerData_(mesh::AbstractMesh, sbp::AbstractSBP, opts)

    println("\nConstruction EulerData object")
    println("  Tsol = ", Tsol)
    println("  Tres = ", Tres)
    println("  Tdim = ", Tdim)
    println("  Tmsh = ", Tmsh)
    eqn = new()  # incomplete initialization

    eqn.comm = mesh.comm
    eqn.commsize = mesh.commsize
    eqn.myrank = mesh.myrank

    numfacenodes = mesh.numNodesPerFace

    vars_orig = opts["variable_type"]
    opts["variable_type"] = :conservative
    eqn.params_conservative = ParamType{Tdim, :conservative, Tsol, Tres, Tmsh}(
                                       mesh, sbp, opts, mesh.order)
    opts["variable_type"] = :entropy
    eqn.params_entropy = ParamType{Tdim, :entropy, Tsol, Tres, Tmsh}(
                                       mesh, sbp, opts, mesh.order)

    opts["variable_type"] = vars_orig
    if vars_orig == :conservative
      eqn.params = eqn.params_conservative
    elseif vars_orig == :entropy
      eqn.params = eqn.params_entropy
    else
      println(STDERR, "Warning: variable_type not recognized")
    end
    eqn.disassembleSolution = disassembleSolution
    eqn.assembleSolution = assembleSolution
    eqn.multiplyA0inv = matVecA0inv
    eqn.majorIterationCallback = majorIterationCallback

    eqn.Minv = calcMassMatrixInverse(mesh, sbp, eqn)
    eqn.Minv3D = calcMassMatrixInverse3D(mesh, sbp, eqn)
    eqn.M = calcMassMatrix(mesh, sbp, eqn)


    jac_type = opts["jac_type"]::Int
    if opts["use_dissipation"] || opts["use_dissipation_prec"]
      dissipation_name = opts["dissipation_name"]
      eqn.dissipation_mat = calcDissipationOperator(mesh, sbp, eqn, opts,
                                                    dissipation_name)
    else
      eqn.dissipation_mat = Array(Tmsh, 0, 0, 0)
    end

    # Must initialize them because some datatypes (BigFloat)
    #   don't automatically initialize them
    # Taking a sview(A,...) of undefined values is illegal
    # I think its a bug that Array(Float64, ...) initializes values
    eqn.q = zeros(Tsol, mesh.numDofPerNode, sbp.numnodes, mesh.numEl)

    #TODO: don't store these, recalculate as needed
    eqn.Axi = zeros(Tsol, mesh.numDofPerNode, mesh.numDofPerNode, sbp.numnodes,
                    mesh.numEl)
    eqn.Aeta = zeros(eqn.Axi)
    eqn.aux_vars = zeros(Tsol, 1, sbp.numnodes, mesh.numEl)
    eqn.flux_parametric = zeros(Tsol, mesh.numDofPerNode, sbp.numnodes,
                                mesh.numEl, Tdim)
    eqn.res = zeros(Tres, mesh.numDofPerNode, sbp.numnodes, mesh.numEl)

    if opts["use_edge_res"]
      eqn.res_edge = zeros(Tres, mesh.numDofPerNode, sbp.numnodes, mesh.numEl,
                           mesh.numTypePerElement[2])
    else
      eqn.res_edge = zeros(Tres, 0, 0, 0, 0)
    end

    if mesh.isDG
      eqn.q_vec = reshape(eqn.q, mesh.numDof)
      eqn.res_vec = reshape(eqn.res, mesh.numDof)
    else
      eqn.q_vec = zeros(Tres, mesh.numDof)
      eqn.res_vec = zeros(Tres, mesh.numDof)
    end

    eqn.edgestab_alpha = zeros(Tmsh,Tdim,Tdim,sbp.numnodes, mesh.numEl)
    if mesh.isDG
      eqn.q_face = zeros(Tsol, mesh.numDofPerNode, 2, numfacenodes, mesh.numInterfaces)
      eqn.flux_face = zeros(Tres, mesh.numDofPerNode, numfacenodes, mesh.numInterfaces)
      eqn.q_bndry = zeros(Tsol, mesh.numDofPerNode, numfacenodes, mesh.numBoundaryFaces)
      eqn.aux_vars_face = zeros(Tres, 1, numfacenodes, mesh.numInterfaces)
      eqn.aux_vars_bndry = zeros(Tres, 1, numfacenodes, mesh.numBoundaryFaces)
    else
      eqn.q_face = Array(Tres, 0, 0, 0, 0)
      eqn.flux_face = Array(Tres, 0, 0, 0)
      eqn.q_bndry = Array(Tsol, 0, 0, 0)
      eqn.aux_vars_face = zeros(Tres, 0, 0, 0)
      eqn.aux_vars_bndry = zeros(Tres, 0, 0, 0)
    end
    eqn.bndryflux = zeros(Tsol, mesh.numDofPerNode, numfacenodes,
                          mesh.numBoundaryFaces)

    # send and receive buffers
    #TODO: rename buffers to not include face
    eqn.q_face_send = Array(Array{Tsol, 3}, mesh.npeers)
    eqn.q_face_recv = Array(Array{Tsol, 3}, mesh.npeers)
    eqn.flux_sharedface = Array(Array{Tres, 3}, mesh.npeers)
    eqn.aux_vars_sharedface = Array(Array{Tres, 3}, mesh.npeers)
    if mesh.isDG
      if opts["parallel_data"] == "face"
        dim2 = numfacenodes
        dim3_send = mesh.peer_face_counts
        dim3_recv = mesh.peer_face_counts
      elseif opts["parallel_data"] == "element"
        dim2 = mesh.numNodesPerElement
        dim3_send = mesh.local_element_counts
        dim3_recv = mesh.remote_element_counts
      else
        ptype = opts["parallel_type"]
        throw(ErrorException("Unsupported parallel type requested: $ptype"))
      end
      for i=1:mesh.npeers
        eqn.q_face_send[i] = Array(Tsol, mesh.numDofPerNode, dim2,
                                         dim3_send[i])
        eqn.q_face_recv[i] = Array(Tsol,mesh.numDofPerNode, dim2,
                                        dim3_recv[i])
        eqn.flux_sharedface[i] = Array(Tres, mesh.numDofPerNode, numfacenodes,
                                       mesh.peer_face_counts[i])
        eqn.aux_vars_sharedface[i] = Array(Tres, mesh.numDofPerNode,
                                        numfacenodes, mesh.peer_face_counts[i])
      end
    end

    if eqn.params.use_edgestab
      eqn.stabscale = zeros(Tres, sbp.numnodes, mesh.numInterfaces)
      calcEdgeStabAlpha(mesh, sbp, eqn)
    else
      eqn.stabscale = Array(Tres, 0, 0)
      eqn.edgestab_alpha = Array(Tmsh, 0, 0, 0, 0)
    end

    println("Tres = ", Tres)

    return eqn

  end  # end of constructor

end  # end of type declaration

@doc """
###EulerEquationMod.BoundaryForceData

Composite data type for storing data pertaining to the boundaryForce. It holds
lift and drag values

"""->

type BoundaryForceData{Topt, fname} <: AbstractOptimizationData
  is_objective_fn::Bool
  geom_faces_functional::AbstractArray{Int,1}
  ndof::Int
  bndry_force::AbstractArray{Topt,1}
  lift_val::Topt
  drag_val::Topt
  dLiftdAlpha::Topt # Partial derivative of lift w.r.t. alpha
  dDragdAlpha::Topt # Partial derivative of drag w.r.t. alpha

  function BoundaryForceData(mesh, sbp, eqn, opts, geom_faces_functional)

    functional = new()
    functional.is_objective_fn = false
    functional.geom_faces_functional = geom_faces_functional
    functional.ndof = mesh.dim
    functional.bndry_force = zeros(Topt, mesh.dim)
    functional.lift_val = 0.0
    functional.drag_val = 0.0
    functional.dLiftdAlpha = 0.0
    functional.dDragdAlpha = 0.0

    return functional
  end
end
