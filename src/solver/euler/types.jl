# declare the concrete subtypes of AbstractParamType and AbstractSolutionData
@doc """
### EulerEquationMod.ParamType

  This type holds the values of any constants or parameters needed during the
  computation.  These parameters can be specified in the opts dictionary or
  have default values set here.  If there is no reasonable default, values
  are initialized to -1
  
  There are also a bunch of arrays that are used as temporaries by low
  level functions (to avoid having to allocate arrays themselves, which is
  a performance trap).  In general, this Type is used as a container to pass
  around values.


  gamma and R are the independent themodynamic variables

  Whether this type should be immutable or not is an open question

  This type is paramaterized on the dimension of the equation for purposes
  of multiple dispatch

  **Static Parameters**:

   * Tdim : dimensionality of the equation, integer, (used for dispatch)
   * var_type : type of variables used used in the weak form, symbol, (used for
             dispatch), currently supported values: :conservative, :entropy
   * Tsol : datatype of solution variables q
   * Tres : datatype of residual
   * Tmsh : datatype of mesh related quantities (mapping jacobian etc.)

  **Fields (with default values)**:

   * cv  : specific heat constant
   * R : specific gas constant (J/(Kg*K))
   * gamma : ratio of specific heats
   * gamma_1 : gamma - 1

  **Fields (without default values)**:

   * Ma  : free stream Mach number
   * Re  : free stream Reynolds number
   * aoa : angle of attack (radians)

"""->
type ParamType{Tdim, var_type, Tsol, Tres, Tmsh} <: AbstractParamType{Tdim}
  f::BufferedIO
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

  # temporary storage for element level solution
  q_el1::Array{Tsol, 2}
  q_el2::Array{Tsol, 2}
  q_el3::Array{Tsol, 2}
  q_el4::Array{Tsol, 2}

  # temporary storage for solution interpolated to face
  q_faceL::Array{Tsol, 2}
  q_faceR::Array{Tsol, 2}

  res_el1::Array{Tsol, 2}
  res_el2::Array{Tsol, 2}

  # solution grid temporaries
  qs_el1::Array{Tsol, 2}
  qs_el2::Array{Tsol, 2}

  ress_el1::Array{Tsol, 2}
  ress_el2::Array{Tsol, 2}

  # numDofPerNode x stencilsize arrays for entropy variables
  w_vals_stencil::Array{Tsol, 2}
  w_vals2_stencil::Array{Tsol, 2}

  res_vals1::Array{Tres, 1}  # reusable residual type storage
  res_vals2::Array{Tres, 1}  # reusable residual type storage
  res_vals3::Array{Tres, 1}

  flux_vals1::Array{Tres, 1}  # reusable storage for flux values
  flux_vals2::Array{Tres, 1}  # reusable storage for flux values
  flux_valsD::Array{Tres, 2}  # numDofPerNode x Tdim for flux vals 3 directions

  lambda_dotL::Array{Tres, 1}
  lambda_dotR::Array{Tres, 1}

  # Roe solver storage
  sat_vals::Array{Tres, 1}  # reusable storage for SAT term
  euler_fluxjac::Array{Tres, 2}  # euler flux jacobian
  p_dot::Array{Tsol, 1}  # derivative of pressure wrt q
  roe_vars::Array{Tres, 1}  # Roe average state
  roe_vars_dot::Array{Tres, 1}  # derivatives of Roe vars wrt q, packed


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
  nrmD::Array{Tmsh, 2}  # Tdim x Tdim array for Tdim normal vectors
                        # (one per column)
  nrm_face::Array{Tmsh, 2}  # sbpface.numnodes x Tdim array for normal vectors
                            # of all face nodes on an element
  nrm_face2::Array{Tmsh, 2}  # like nrm_face, but transposed

  dxidx_element::Array{Tmsh, 3}  # Tdim x Tdim x numNodesPerElement array for
                                 # dxidx of an entire element
  velocities::Array{Tsol, 2}  # Tdim x numNodesPerElement array of velocities
                              # at each node of an element
  velocity_deriv::Array{Tsol, 3}  # Tdim x numNodesPerElement x Tdim for
                                  # derivative of velocities.  First two
                                  # dimensions are same as velocities array,
                                  # 3rd dimensions is direction of
                                  # differentiation
  velocity_deriv_xy::Array{Tres, 3} # Tdim x Tdim x numNodesPerElement array
                                    # for velocity derivatives in x-y-z
                                    # first dim is velocity direction, second
                                    # dim is derivative direction, 3rd is node


  # volume term jacobian arrays
  flux_jac::Array{Tres, 4}
  res_jac::Array{Tres, 4}

  # face term jacobian arrays
  flux_dotL::Array{Tres, 3}
  flux_dotR::Array{Tres, 3}
  res_jacLL::Array{Tres, 4}
  res_jacLR::Array{Tres, 4}
  res_jacRL::Array{Tres, 4}
  res_jacRR::Array{Tres, 4}

  h::Float64 # temporary: mesh size metric
  cv::Float64  # specific heat constant
  R::Float64  # specific gas constant used in ideal gas law (J/(Kg * K))
  R_ND::Float64  # specific gas constant, nondimensionalized
  gamma::Float64 # ratio of specific heats
  gamma_1::Float64 # = gamma - 1

  Ma::Float64  # free stream Mach number
  Re::Float64  # free stream Reynolds number

  # these quantities are dimensional (ie. used for non-dimensionalization)
  aoa::Tsol  # angle of attack (radians)
  sideslip_angle::Tsol
  rho_free::Float64  # free stream density
  p_free::Float64  # free stream pressure
  T_free::Float64 # free stream temperature
  E_free::Float64 # free stream energy (4th conservative variable)
  a_free::Float64 # free stream speed of sound (computed from p_free and rho_free)

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

  use_Minv::Int  # apply Minv to explicit jacobian calculation, 0 = do not
                 # apply, 1 = do apply
  vortex_x0::Float64  # vortex center x coordinate at t=0
  vortex_strength::Float64  # strength of the vortex

  #TODO: get rid of these, move to NewtonData
  krylov_itr::Int  # Krylov iteration number for iterative solve
  krylov_type::Int # 1 = explicit jacobian, 2 = jac-vec prod

  Rprime::Array{Float64, 2}  # numfaceNodes x numNodesPerElement interpolation matrix
                             # this should live in sbpface instead
  # temporary storage for calcECFaceIntegrals
  A::Array{Tres, 2}
  B::Array{Tres, 3}
  iperm::Array{Int, 1}

  S::Array{Float64, 3}  # SBP S matrix

  x_design::Array{Tsol, 1}  # design variables

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
  isViscous::Bool
  penalty_relaxation::Float64
  const_tii::Float64

  function ParamType(mesh, sbp, opts, order::Integer)
  # create values, apply defaults

    # all the spatial computations happen on the *flux* grid when using
    # the staggered grid algorithm, so make the temporary vectors the
    # right size
    if opts["use_staggered_grid"]
      numNodesPerElement = mesh.mesh2.numNodesPerElement
      stencilsize = size(mesh.mesh2.sbpface.perm, 1)
    else
      numNodesPerElement = mesh.numNodesPerElement
      stencilsize = size(mesh.sbpface.perm, 1)
    end

    t = 0.0
    myrank = mesh.myrank
    #TODO: don't open a file in non-debug mode
    if DB_LEVEL >= 1
      f = BufferedIO("log_$myrank.dat", "w")
    else
      f = BufferedIO(DevNull)
    end
    q_vals = zeros(Tsol, Tdim + 2)
    q_vals2 = zeros(Tsol, Tdim + 2)
    q_vals3 = zeros(Tsol, Tdim + 2)
    qg = zeros(Tsol, Tdim + 2)
    v_vals = zeros(Tsol, Tdim + 2)
    v_vals2 = zeros(Tsol, Tdim + 2)
    Lambda = zeros(Tsol, Tdim + 2)

    q_el1 = zeros(Tsol, mesh.numDofPerNode, numNodesPerElement)
    q_el2 = zeros(Tsol, mesh.numDofPerNode, numNodesPerElement)
    q_el3 = zeros(Tsol, mesh.numDofPerNode, numNodesPerElement)
    q_el4 = zeros(Tsol, mesh.numDofPerNode, numNodesPerElement)

    q_faceL = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerFace)
    q_faceR = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerFace)

    res_el1 = zeros(Tres, mesh.numDofPerNode, numNodesPerElement)
    res_el2 = zeros(Tres, mesh.numDofPerNode, numNodesPerElement)

    qs_el1 = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerElement)
    qs_el2 = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerElement)

    ress_el1 = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerElement)
    ress_el2 = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerElement)

    w_vals_stencil = zeros(Tsol, Tdim + 2, stencilsize)
    w_vals2_stencil = zeros(Tsol, Tdim + 2, stencilsize)

    res_vals1 = zeros(Tres, Tdim + 2)
    res_vals2 = zeros(Tres, Tdim + 2)
    res_vals3 = zeros(Tres, Tdim + 2)

    flux_vals1 = zeros(Tres, Tdim + 2)
    flux_vals2 = zeros(Tres, Tdim + 2)
    flux_valsD = zeros(Tres, Tdim + 2, Tdim)

    lambda_dotL = zeros(Tres, Tdim + 2)
    lambda_dotR = zeros(Tres, Tdim + 2)

    # Roe solver storage
    sat_vals = zeros(Tres, Tdim + 2)
    euler_fluxjac = zeros(Tres, mesh.numDofPerNode, mesh.numDofPerNode)
    p_dot = zeros(Tsol, mesh.numDofPerNode)
    roe_vars = zeros(Tres, Tdim + 1)
    roe_vars_dot = zeros(Tres, 22)  # number needed in 3D

    A0 = zeros(Tsol, Tdim + 2, Tdim + 2)
    A0inv = zeros(Tsol, Tdim + 2, Tdim + 2)
    A1 = zeros(Tsol, Tdim + 2, Tdim + 2)
    A2 = zeros(Tsol, Tdim + 2, Tdim + 2)
    A_mats = zeros(Tsol, Tdim + 2, Tdim + 2, Tdim)
    S2 = zeros(Tsol, Tdim + 2)

    Rmat1 = zeros(Tres, Tdim + 2, Tdim + 2)
    Rmat2 = zeros(Tres, Tdim + 2, Tdim + 2)

    P = zeros(Tmsh, Tdim + 2, Tdim + 2)

    nrm = zeros(Tmsh, Tdim)
    nrm2 = zeros(nrm)
    nrm3 = zeros(nrm)
    nrmD = zeros(Tmsh, Tdim, Tdim)
    nrm_face = zeros(Tmsh, mesh.sbpface.numnodes, Tdim)
    nrm_face2 = zeros(Tmsh, Tdim, mesh.sbpface.numnodes)

    dxidx_element = zeros(Tmsh, Tdim, Tdim, mesh.numNodesPerElement)
    velocities = zeros(Tsol, Tdim, mesh.numNodesPerElement)
    velocity_deriv = zeros(Tsol, Tdim, mesh.numNodesPerElement, Tdim)
    velocity_deriv_xy = zeros(Tres, Tdim, Tdim, mesh.numNodesPerElement)

    # volume term jacobian storage
    flux_jac = zeros(Tres, mesh.numDofPerNode, mesh.numDofPerNode,
                           mesh.numNodesPerElement, Tdim)
    res_jac = zeros(Tres, mesh.numDofPerNode, mesh.numDofPerNode,
                          mesh.numNodesPerElement, mesh.numNodesPerElement)

    # face term jacobian storage
    flux_dotL = zeros(Tres, mesh.numDofPerNode, mesh.numDofPerNode, mesh.numNodesPerFace)
    flux_dotR = zeros(Tres, mesh.numDofPerNode, mesh.numDofPerNode, mesh.numNodesPerFace)
    res_jacLL = zeros(Tres, mesh.numDofPerNode, mesh.numDofPerNode, mesh.numNodesPerElement, mesh.numNodesPerElement)
    res_jacLR = zeros(res_jacLL)
    res_jacRL = zeros(res_jacLL)
    res_jacRR = zeros(res_jacLL)

    h = maximum(mesh.jac)

    gamma = opts["gamma"]
    gamma_1 = gamma - 1
    R = opts["R"]
    cv = R/gamma_1

    Ma = opts["Ma"]
    Re = opts["Re"]
    aoa = opts[ "aoa"]*pi/180
    sideslip_angle = opts["sideslip_angle"]
    E_free = 1/(gamma*gamma_1) + 0.5*Ma*Ma
    rho_free = 1.0
    p_free = opts["p_free"]
    T_free = opts["T_free"]
    E_free = 1/(gamma*gamma_1) + 0.5*Ma*Ma
    a_free = sqrt(p_free/rho_free)  # free stream speed of sound
    R_ND = R*a_free*a_free/T_free

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
      filter_mat = zeros(Float64, 0,0)
    end

    use_dissipation = opts["use_dissipation"]
    if use_dissipation println("artificial dissipation enabled") end

    dissipation_const = opts["dissipation_const"]

    tau_type = opts["tau_type"]

    use_Minv = opts["use_Minv"] ? 1 : 0

    vortex_x0 = opts["vortex_x0"]
    vortex_strength = opts["vortex_strength"]

    krylov_itr = 0
    krylov_type = 1 # 1 = explicit jacobian, 2 = jac-vec prod

    sbpface = mesh.sbpface

    if typeof(sbpface) <: SparseFace
      Rprime = zeros(0, 0)
    else
      Rprime = zeros(size(sbpface.interp, 2), numNodesPerElement)
      # expand into right size (used in SBP Gamma case)
      for i=1:size(sbpface.interp, 1)
        for j=1:size(sbpface.interp, 2)
          Rprime[j, i] = sbpface.interp[i, j]
        end
      end
    end  # end if

    A = zeros(Tres, size(Rprime))
    B = zeros(Tres, numNodesPerElement, numNodesPerElement, 2)
    iperm = zeros(Int, size(sbpface.perm, 1))

    stencil_size = size(sbp.Q, 1)
    S = zeros(Float64, stencil_size, stencil_size, Tdim)
    for i=1:Tdim
      S[:, :, i] = 0.5*(sbp.Q[:, :, i] - sbp.Q[:, :, i].')
    end

    x_design = zeros(Tsol, 0)  # this can be resized later

    time = Timings()

    penalty_relaxation = 1.0
    if haskey(opts, "Cip")
      penalty_relaxation = opts["Cip"]
    end
    isViscous = false
    if haskey(opts, "isViscous")
      isViscous = opts["isViscous"]
    end

    const_tii = 0.0
    if isViscous
      const_tii = calcTraceInverseInequalityConst(sbp, sbpface)
    end

    return new(f, t, order, q_vals, q_vals2, q_vals3,  qg, v_vals, v_vals2,
               Lambda, q_el1, q_el2, q_el3, q_el4, q_faceL, q_faceR,
               res_el1, res_el2,
               qs_el1, qs_el2, ress_el1, ress_el2,
               w_vals_stencil, w_vals2_stencil, res_vals1, 
               res_vals2, res_vals3,  flux_vals1, 
               flux_vals2, flux_valsD, lambda_dotL, lambda_dotR,
               sat_vals, euler_fluxjac, p_dot, roe_vars, roe_vars_dot,
               A0, A0inv, A1, A2, S2, 
               A_mats, Rmat1, Rmat2, P,
               nrm, nrm2, nrm3, nrmD, nrm_face, nrm_face2, dxidx_element, velocities,
               velocity_deriv, velocity_deriv_xy,
               flux_jac, res_jac,
               flux_dotL, flux_dotR, res_jacLL, res_jacLR, res_jacRL, res_jacRR,
               h, cv, R, R_ND, gamma, gamma_1, Ma, Re, aoa, sideslip_angle,
               rho_free, p_free, T_free, E_free, a_free,
               edgestab_gamma, writeflux, writeboundary,
               writeq, use_edgestab, use_filter, use_res_filter, filter_mat,
               use_dissipation, dissipation_const, tau_type, use_Minv, vortex_x0,
               vortex_strength,
               krylov_itr, krylov_type,
               Rprime, A, B, iperm,
               S, x_design, time,
               isViscous, penalty_relaxation, const_tii)

    end   # end of ParamType function

end  # end type declaration

# now that EulerData is declared, include other files that use it
@doc """
### EulerEquationMod.EulerData_

  This type is an implementation of the abstract EulerData.  It is
  parameterized by the residual datatype Tres and the mesh datatype Tmsh
  because it stores some arrays of those types.  Tres is the 'maximum' type of
  Tsol and Tmsh, where Tsol is the type of the solution variables.
  It is also paramterized by `var_type`, which should be a symbol describing
  the set of variables stored in eqn.q.  Currently supported values are
  `:conservative` and `:entropy`, which indicate the conservative variables and
  the entropy variables described in:
  
  'A New Finite Element Formulation for
  Computational Fluid Dynamics: Part I' by Hughes et al.`

  *Note*: this constructor does not fully populate all fields.  The
          [`init`])@ref) function must be called to finish initialization.

  **Static Parameters**:

   * Tsol : datatype of variables solution variables, ie. the
           q vector and array
   * Tres : datatype of residual. ie. eltype(res_vec)
   * Tdim : dimensionality of equation, integer, (2 or 3, currently only 2 is
           supported).
   * Tmsh : datatype of mesh related quantities
   * var_type : symbol describing variables used in weak form, (:conservative
               or :entropy)


  **Fields**

  This type has many fields, not all of them are documented here.  A few
  of the most important ones are:

   * comm: MPI communicator
   * commsize: size of MPI communicator
   * myrank: MPI rank of this process


  When computing the jacobian explicitly (options key `calc_jac_explicit`),
  Tsol and Tres are typically `Float64`, however node-level operations 
  sometime use complex numbers or dual numbers.  Also, some operations on
  entropy variables require doing parts of the computation with
  conservative variables.  To support these use-cases, the fields

   * params: ParamType object with `Tsol`, `Tres`, `Tmsh`, and `var_type` matching the equation object
   * params_conservative: ParamType object with `Tsol, Tres`, and `Tmsh` matching the `EulerData_` object, but `var_type = :conservative`
   * params_entropy: similar to `param_conservative`, but `var_type = :entropy`
   * params_complex: ParamType object with `Tmsh` and `var_type` matching the `EulerData_` object, but `Tsol = Tres = Complex128` 

 exist.
"""->
type EulerData_{Tsol, Tres, Tdim, Tmsh, var_type} <: EulerData{Tsol, Tres, Tdim, var_type}
# hold any constants needed for euler equation, as well as solution and data
#   needed to calculate it
# Formats of all arrays are documented in SBP.
# Only the constants are initialized here, the arrays are not.

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

  # used for complex-stepping the boundary conditions
  # this should really be Complex{Tsol}, but that isn't allowed
  # once we switch to dual number this can be improved
  params_complex::ParamType{Tdim, :conservative, Complex128, Complex128, Tmsh}

  # the following arrays hold data for all nodes
  q::Array{Tsol,3}  # holds conservative variables for all nodes
  q_bar::Array{Tsol, 3}  # adjoint part of q
  q_face::Array{Tsol, 4}  # store solution values interpolated to faces
  q_face_bar::Array{Tsol, 4}  # adjoint part of q_face
  q_bndry::Array{Tsol, 3}  # store solution variables interpolated to
  q_bndry_bar::Array{Tsol, 3}  # adjoint part

  q_flux::Array{Tsol, 3}  # flux variable solution

  q_vec::Array{Tres,1}            # initial condition in vector form

  aux_vars::Array{Tres, 3}        # storage for auxiliary variables
  aux_vars_bar::Array{Tres, 3}    # adjoint part
  aux_vars_face::Array{Tres, 3}    # storage for aux variables interpolated
                                  # to interior faces
  aux_vars_face_bar::Array{Tres, 3}  # adjoint part
  aux_vars_sharedface::Array{Array{Tres, 3}, 1}  # storage for aux varables interpolate
                                       # to shared faces
  aux_vars_sharedface_bar::Array{Array{Tres, 3}} # adjoint part
  aux_vars_bndry::Array{Tres,3}   # storage for aux variables interpolated
                                  # to the boundaries
  aux_vars_bndry_bar::Array{Tres, 3}  # adjoint part

  # hold fluxes in all directions
  # [ndof per node by nnodes per element by num element by num dimensions]
  flux_parametric::Array{Tsol,4}  # flux in xi and eta direction
  flux_parametric_bar::Array{Tsol, 4}  # adjoint part
  shared_data::Array{SharedFaceData{Tsol}, 1}  # MPI send and receive buffers
  shared_data_bar::Array{SharedFaceData{Tsol}, 1} # adjoint part

  flux_face::Array{Tres, 3}  # flux for each interface, scaled by jacobian
  flux_face_bar::Array{Tres, 3}  # adjoint part
  flux_sharedface::Array{Array{Tres, 3}, 1}  # hold shared face flux
  flux_sharedface_bar::Array{Array{Tres, 3}, 1}  # adjoint part
  res::Array{Tres, 3}             # result of computation
  res_bar::Array{Tres, 3}         # adjoint part

  res_vec::Array{Tres, 1}         # result of computation in vector form
  Axi::Array{Tsol,4}               # Flux Jacobian in the xi-direction
  Aeta::Array{Tsol,4}               # Flux Jacobian in the eta-direction
  res_edge::Array{Tres, 4}       # edge based residual used for stabilization
                           # numdof per node x nnodes per element x numEl x num edges per element

  edgestab_alpha::Array{Tmsh, 4}  # alpha needed by edgestabilization
                                  # Tdim x Tdim x nnodesPerElement x numEl
  bndryflux::Array{Tsol, 3}       # boundary flux
  bndryflux_bar::Array{Tsol, 3}   # adjoint part
  stabscale::Array{Tsol, 2}       # stabilization scale factor

  # artificial dissipation operator:
  #   a square numnodes x numnodes matrix for every element
  dissipation_mat::Array{Tmsh, 3}

  Minv3D::Array{Float64, 3}       # inverse mass matrix for application to res, not res_vec
  Minv::Array{Float64, 1}         # inverse mass matrix
  M::Array{Float64, 1}            # mass matrix

  # TODO: consider overloading getField instead of having function as
  #       fields
  multiplyA0inv::Function         # multiply an array by inv(A0), where A0
                                  # is the coefficient matrix of the time derivative
  majorIterationCallback::Function # called before every major (Newton/RK) itr

  src_func::SRCType  # functor for the source term
  flux_func::FluxType  # functor for the face flux
  flux_func_bar::FluxType_revm # Functor for the reverse mode of face flux
  flux_func_diff::FluxType_diff
  volume_flux_func::FluxType  # functor for the volume flux numerical flux
                              # function
  viscous_flux_func::FluxType  # functor for the viscous flux numerical flux function
  face_element_integral_func::FaceElementIntegralType  # function for face
                                                       # integrals that use
                                                       # volume data
# minorIterationCallback::Function # called before every residual evaluation

  assembler::AssembleElementData  # temporary place to stash the assembler

  file_dict::Dict{ASCIIString, IO}  # dictionary of all files used for logging

  #
  # variables for viscous terms
  #
  area_sum::Array{Tmsh, 1}			    # the wet area of each element
	# vecflux_face::Array{Tres, 4}    # stores (u+ - u-)nx*, (numDofs, numNodes, numFaces)
	vecflux_faceL::Array{Tres, 4}     # stores (u+ - u-)nx*, (numDofs, numNodes, numFaces)
	vecflux_faceR::Array{Tres, 4}     # stores (u+ - u-)nx*, (numDofs, numNodes, numFaces)
	vecflux_bndry::Array{Tres, 4}     # stores (u+ - u-)nx*, (numDofs, numNodes, numFaces)

  # inner constructor
  function EulerData_(mesh::AbstractMesh, sbp::AbstractSBP, opts; open_files=true)

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
      println(BSTDERR, "Warning: variable_type not recognized")
    end

    eqn.params_complex = ParamType{Tdim, :conservative, Complex128, Complex128, Tmsh}(
                                       mesh, sbp, opts, mesh.order)


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
      eqn.dissipation_mat = zeros(Tmsh, 0, 0, 0)
    end

    # Must initialize them because some datatypes (BigFloat)
    #   don't automatically initialize them
    # Taking a sview(A,...) of undefined values is illegal
    # I think its a bug that Array(Float64, ...) initializes values
    eqn.q = zeros(Tsol, mesh.numDofPerNode, sbp.numnodes, mesh.numEl)

    if opts["use_staggered_grid"]
      eqn.q_flux = zeros(Tsol, mesh.numDofPerNode, mesh.mesh2.numNodesPerElement, mesh.numEl)
    else
      eqn.q_flux = zeros(Tsol, 0, 0, 0)
    end

    #TODO: don't store these, recalculate as needed
    eqn.Axi = zeros(Tsol, mesh.numDofPerNode, mesh.numDofPerNode, sbp.numnodes,
                    mesh.numEl)
    eqn.Aeta = zeros(eqn.Axi)
    eqn.aux_vars = zeros(Tsol, 1, sbp.numnodes, mesh.numEl)

    if opts["precompute_volume_flux"]
      eqn.flux_parametric = zeros(Tsol, mesh.numDofPerNode, sbp.numnodes,
                                  mesh.numEl, Tdim)
    else
      eqn.flux_parametric = zeros(Tsol, 0, 0, 0, 0)
    end

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

    if opts["precompute_q_bndry"]
      eqn.q_bndry = zeros(Tsol, mesh.numDofPerNode, numfacenodes,
                                mesh.numBoundaryFaces)
    else
      eqn.q_bndry = zeros(Tsol, 0, 0, 0)
    end


    if opts["precompute_q_face"]
      eqn.q_face = zeros(Tsol, mesh.numDofPerNode, 2, numfacenodes, mesh.numInterfaces)
    else
      eqn.q_face = zeros(Tsol, 0, 0, 0, 0)
    end

    #TODO: why are there 2 if mesh.isDG blocks?
    if mesh.isDG
     if opts["precompute_face_flux"]
        eqn.flux_face = zeros(Tres, mesh.numDofPerNode, numfacenodes,
                                    mesh.numInterfaces)
      else
        eqn.flux_face = zeros(Tres, 0, 0, 0)
      end


      eqn.aux_vars_face = zeros(Tres, 1, numfacenodes, mesh.numInterfaces)
      eqn.aux_vars_bndry = zeros(Tres, 1, numfacenodes, mesh.numBoundaryFaces)
    else
      eqn.q_face = zeros(Tres, 0, 0, 0, 0)
      eqn.flux_face = zeros(Tres, 0, 0, 0)
      eqn.aux_vars_face = zeros(Tres, 0, 0, 0)
      eqn.aux_vars_bndry = zeros(Tres, 0, 0, 0)
    end

    if opts["precompute_boundary_flux"]
      eqn.bndryflux = zeros(Tsol, mesh.numDofPerNode, numfacenodes,
                            mesh.numBoundaryFaces)
    else
      eqn.bndryflux = zeros(Tsol, 0, 0, 0)
    end

    # send and receive buffers
    if opts["precompute_face_flux"]
      eqn.flux_sharedface = Array(Array{Tres, 3}, mesh.npeers)
    else
      eqn.flux_sharedface = Array(Array{Tres, 3}, 0)
    end

    eqn.aux_vars_sharedface = Array(Array{Tres, 3}, mesh.npeers)
    if mesh.isDG
      for i=1:mesh.npeers
        if opts["precompute_face_flux"]
          eqn.flux_sharedface[i] = zeros(Tres, mesh.numDofPerNode, numfacenodes,
                                         mesh.peer_face_counts[i])
        end
        eqn.aux_vars_sharedface[i] = zeros(Tres, mesh.numDofPerNode,
                                        numfacenodes, mesh.peer_face_counts[i])
      end
      eqn.shared_data = getSharedFaceData(Tsol, mesh, sbp, opts)
    else
      eqn.shared_data = Array(SharedFaceData, 0)
    end

    if eqn.params.use_edgestab
      eqn.stabscale = zeros(Tres, sbp.numnodes, mesh.numInterfaces)
      eqn.edgestab_alpha = zeros(Tmsh,Tdim,Tdim,sbp.numnodes, mesh.numEl)
      calcEdgeStabAlpha(mesh, sbp, eqn)
    else
      eqn.stabscale = zeros(Tres, 0, 0)
      eqn.edgestab_alpha = zeros(Tmsh, 0, 0, 0, 0)
    end

    # functor defaults. functorThatErrors() is defined in ODLCommonTools
    eqn.flux_func = functorThatErrors()
    eqn.flux_func_bar = functorThatErrors_revm()
    eqn.volume_flux_func = functorThatErrors()
    eqn.viscous_flux_func = functorThatErrors()

    if opts["need_adjoint"]
      eqn.q_bar = zeros(eqn.q)
      eqn.q_face_bar = zeros(eqn.q_face)
      eqn.q_bndry_bar = zeros(eqn.q_bndry)
      eqn.flux_parametric_bar = zeros(eqn.flux_parametric)

      eqn.aux_vars_bar = zeros(eqn.aux_vars)
      eqn.aux_vars_face_bar = zeros(eqn.aux_vars_face)
      eqn.aux_vars_bndry_bar = zeros(eqn.aux_vars_bndry)

      eqn.flux_sharedface_bar = Array(Array{Tsol, 3}, mesh.npeers)
      eqn.aux_vars_sharedface_bar = Array(Array{Tsol, 3}, mesh.npeers)

      if mesh.isDG
        for i=1:mesh.npeers
          eqn.flux_shareface_bar[i] = zeros(eqn.flux_sharedface[i])
          eqn.aux_vars_sharedface_bar[i] = zeros(eqn.aux_vars_sharedface[i])
        end

      eqn.shared_data_bar = getSharedFaceData(Tsol, mesh, sbp, opts)
      else
        eqn.shared_data_bar = zeros(SharedFaceData, 0)
      end

      eqn.flux_face_bar = zeros(eqn.flux_face)
      eqn.bndryflux_bar = zeros(eqn.bndryflux)
      eqn.res_bar = zeros(eqn.res)
    else  # don't allocate arrays if they are not needed
      eqn.q_bar = zeros(Tsol, 0, 0, 0)
      eqn.q_face_bar = zeros(Tsol, 0, 0, 0, 0)
      eqn.q_bndry_bar = zeros(Tsol, 0, 0, 0)
      eqn.flux_parametric_bar = zeros(Tsol, 0, 0, 0, 0)

      eqn.aux_vars_bar = zeros(Tres, 0, 0, 0)
      eqn.aux_vars_face_bar = zeros(Tres, 0, 0, 0)
      eqn.aux_vars_bndry_bar = zeros(Tres, 0, 0, 0)

      eqn.shared_data_bar = Array(SharedFaceData, 0)
      eqn.flux_sharedface_bar = Array(Array{Tsol, 3}, 0)
      eqn.aux_vars_sharedface_bar = Array(Array{Tsol, 3}, 0)

      eqn.flux_face_bar = zeros(Tres, 0, 0, 0)
      eqn.bndryflux_bar = zeros(Tres, 0, 0, 0)
      eqn.res_bar = zeros(Tres, 0, 0, 0)
   end

   eqn.assembler = NullAssembleElementData
   if open_files
     eqn.file_dict = openLoggingFiles(mesh, opts)
   else
     eqn.file_dict = Dict{ASCIIString, IO}()
   end

   if eqn.params.isViscous
     numfacenodes = mesh.numNodesPerFace
     numfaces = mesh.numInterfaces
     numBndFaces = mesh.numBoundaryFaces
     numvars  = mesh.numDofPerNode
     # eqn.vecflux_face = zeros(Tsol, Tdim, numvars, numfacenodes, numfaces)
     eqn.vecflux_faceL = zeros(Tsol, Tdim, numvars, numfacenodes, numfaces)
     eqn.vecflux_faceR = zeros(Tsol, Tdim, numvars, numfacenodes, numfaces)
     eqn.vecflux_bndry = zeros(Tsol, Tdim, numvars, numfacenodes, numBndFaces)
     eqn.area_sum = zeros(Tmsh, mesh.numEl)
     calcElemSurfaceArea(mesh, sbp, eqn)
   else
     # eqn.vecflux_face  = Array(Tsol, 0, 0, 0, 0)
     eqn.vecflux_faceL = Array(Tsol, 0, 0, 0, 0)
     eqn.vecflux_faceR = Array(Tsol, 0, 0, 0, 0)
     eqn.vecflux_bndry = Array(Tsol, 0, 0, 0, 0)
     eqn.area_sum = Array(Tsol, 0)
   end
   return eqn

  end  # end of constructor

end  # end of type declaration

"""
  Useful alias for 2D ParamType
"""
typealias ParamType2 ParamType{2}

"""
  Useful alias for 3D ParamType
"""
typealias ParamType3 ParamType{3}


"""
  This function opens all used for logging data.  In particular, every data
  file that has data appended to it in majorIterationCallback should be
  opened here.  Most files are of type BufferedIO, so they must be flushed
  periodically.

  This function requires each output to have two keys: "write_outname"
  and "write_outname_fname", where the first has a boolean value that
  controls whether or not to write the output, and the second is the
  file name (including extension) to write.

  This function contains a list of all possible log files.  Every new
  log file must be added to the list

  **Inputs**:

   * mesh: an AbstractMesh (needed for MPI Communicator)
   * opts: options dictionary

  **Outputs**:

   * file_dict: dictionary mapping names of files to the file object
                 ie. opts["write_entropy_fname"] => f

  Exceptions: this function will throw an exception if any two file names
              are the same

  Implementation notes:
    When restarting, all files must be appended to.  Currently, files
    are appended to in all cases.
"""
function openLoggingFiles(mesh, opts)

  # comm rank
  myrank = mesh.myrank

  # output dictionary
  file_dict = Dict{AbstractString, IO}()

  # map output file names to the key name that specified them
  used_names = Dict{AbstractString, AbstractString}()


  # use the fact that the key names are formulaic
  names = ["entropy", "integralq", "kinetic_energy", "kinetic_energydt", "enstrophy", "drag"]
  @mpi_master for name in names  # only open files on the master process
    keyname = string("write_", name)
    if opts[keyname]  # if this file is being written
      fname_key = string("write_", name, "_fname")
      fname = opts[fname_key]

      if fname_key in keys(used_names)
        other_keyname = used_names[fname]
        throw(ErrorException("data file name $fname used for key $keyname is already used for key $other_keyname"))
      end

      used_names[fname] = keyname  # record this fname as used

      f = BufferedIO(opts[fname_key], "a")  # append to files (safe default)

      file_dict[fname] = f

    end  # end if
  end  # end

  return file_dict
end

"""
  This function performs all cleanup activities before the run_physics()
  function returns.  The mesh, sbp, eqn, opts are returned by run_physics()
  so there is not much cleanup that needs to be done, mostly closing files.

  **Inputs/Outputs**:

   * mesh: an AbstractMesh object
   * sbp: an SBP operator
   * eqn: the EulerData object
   * opts: the options dictionary

"""
function cleanup(mesh::AbstractMesh, sbp::AbstractSBP, eqn::EulerData, opts)

  for f in values(eqn.file_dict)
    close(f)
  end

  return nothing
end

@doc """
### EulerEquationMod.getTypeParameters

Gets the type parameters for mesh and equation objects.

**Input**

* `mesh` : Object of abstract meshing type.
* `eqn`  : Euler Equation object.

**Output**

* `Tmsh` : Type parameter of the mesh.
* `Tsol` : Type parameter of the solution array.
* `Tres` : Type parameter of the residual array.
"""->

function getTypeParameters{Tmsh, Tsol, Tres}(mesh::AbstractMesh{Tmsh}, eqn::EulerData{Tsol, Tres})
  return Tmsh, Tsol, Tres
end

import ODLCommonTools.getAllTypeParams

@doc """
### EulerEquationMod.getAllTypeParameters

Gets the type parameters for mesh and equation objects.

**Input**

* `mesh` : Object of abstract meshing type.
* `eqn`  : Euler Equation object.
* `opts` : Options dictionary

**Output**

* `tuple` : Tuple of type parameters. Ordering is same as that of the concrete eqn object within this physics module.

"""->
function getAllTypeParams{Tmsh, Tsol, Tres, Tdim, var_type}(mesh::AbstractMesh{Tmsh}, eqn::EulerData_{Tsol, Tres, Tdim, Tmsh, var_type}, opts)

  tuple = (Tsol, Tres, Tdim, Tmsh, var_type)

  return tuple
end

import PDESolver.updateMetricDependents

function updateMetricDependents(mesh::AbstractMesh, sbp::AbstractSBP,
                                 eqn::EulerData, opts)

  #TODO: don't reallocate the arrays, update in place
  eqn.Minv = calcMassMatrixInverse(mesh, sbp, eqn)
  eqn.Minv3D = calcMassMatrixInverse3D(mesh, sbp, eqn)
  eqn.M = calcMassMatrix(mesh, sbp, eqn)


  if eqn.params.use_edgestab
    calcEdgeStabAlpha(mesh, sbp, eqn)
  end

  return nothing
end

@doc """
### EulerEquationMod.calcElemFurfaceArea
This function calculates the wet area of each element. A weight of 2 is given to
faces with Dirichlet boundary conditions.
Arguments:
mesh: AbstractMesh
sbp: SBP operator
eqn: an implementation of EulerData. Does not have to be fully initialized.
"""->
# used by EulerData Constructor
function calcElemSurfaceArea{Tmsh, Tsol, Tres, Tdim}(mesh::AbstractMesh{Tmsh},
                                                     sbp::AbstractSBP,
                                                     eqn::EulerData{Tsol, Tres, Tdim})
  nfaces = length(mesh.interfaces)
  nrm = zeros(Tmsh, Tdim, mesh.numNodesPerFace)
  area = zeros(Tmsh, mesh.numNodesPerFace)
  face_area::Tmsh
  face_area = 0.0
  sbpface = mesh.sbpface

  #
  # Compute the wet area of each element
  #
  for f = 1:nfaces
    face = mesh.interfaces[f]
    eL = face.elementL
    eR = face.elementR
    fL = face.faceL
    fR = face.faceR
    #
    # Compute the size of face
    face_area = 0.0
    
    for n = 1 : mesh.numNodesPerFace
      nrm_xy = ro_sview(mesh.nrm_face, :, n, f)
      area[n] = norm(nrm_xy)
      face_area += sbpface.wface[n]*area[n]
    end

    eqn.area_sum[eL] += face_area
    eqn.area_sum[eR] += face_area
  end

  for bc = 1 : mesh.numBC
    indx0 = mesh.bndry_offsets[bc]
    indx1 = mesh.bndry_offsets[bc+1] - 1

    for f = indx0 : indx1
      face = mesh.bndryfaces[f].face
      elem = mesh.bndryfaces[f].element

      # Compute the size of face
      face_area = 0.0
      for n=1:mesh.numNodesPerFace
        nrm_xy = ro_sview(mesh.nrm_bndry, :, n, f)
        area[n] = norm(nrm_xy)
        face_area += sbpface.wface[n]*area[n]
      end
      eqn.area_sum[elem] += 2.0*face_area
    end
  end
  return nothing
end

@doc """

Compute the constant coefficent in inverse trace ineqality, i.e.,
the largest eigenvalue of 
B^{1/2} R H^{-1} R^{T} B^{1/2}

Input:
  sbp
Output:
  cont_tii
"""->

function calcTraceInverseInequalityConst{Tsbp}(sbp::AbstractSBP{Tsbp},
                                               sbpface::AbstractFace{Tsbp})
  R = sview(sbpface.interp, :,:)
  BsqrtRHinvRtBsqrt = Array(Tsbp, sbpface.numnodes, sbpface.numnodes)
  perm = zeros(Tsbp, sbp.numnodes, sbpface.stencilsize)
  Hinv = zeros(Tsbp, sbp.numnodes, sbp.numnodes)
  Bsqrt = zeros(Tsbp, sbpface.numnodes, sbpface.numnodes)
  for s = 1:sbpface.stencilsize
    perm[sbpface.perm[s, 1], s] = 1.0
  end
  for i = 1:sbp.numnodes
    Hinv[i,i] = 1.0/sbp.w[i]
  end
  for i = 1:sbpface.numnodes
    Bsqrt[i,i] = sqrt(sbpface.wface[i])
  end

  BsqrtRHinvRtBsqrt = Bsqrt*R.'*perm.'*Hinv*perm*R*Bsqrt 
  const_tii = eigmax(BsqrtRHinvRtBsqrt)

  return const_tii

end

