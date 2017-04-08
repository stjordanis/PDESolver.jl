# this file contains all the flux solvers for weakly imposed boundary conditions

"""
  A wrapper for the Roe Solver that computes the scaled normal vector
  in parametric coordinates from the the face normal and the scaled
  mapping jacobian.

  Useful for boundary conditions.

"""
function RoeSolver{Tmsh, Tsol, Tres}(params::ParamType,
                                     q::AbstractArray{Tsol,1},
                                     qg::AbstractArray{Tsol, 1},
                                     aux_vars::AbstractArray{Tres, 1},
                                     dxidx::AbstractArray{Tmsh,2},
                                     nrm::AbstractArray{Tmsh,1},
                                     flux::AbstractArray{Tres, 1})

  nrm2 = params.nrm2
  calcBCNormal(params, dxidx, nrm, nrm2)
  RoeSolver(params, q, qg, aux_vars, nrm2, flux)

  return nothing
end

function RoeSolver_revm{Tmsh, Tsol, Tres}(params::ParamType,
                                     q::AbstractArray{Tsol,1},
                                     qg::AbstractArray{Tsol, 1},
                                     aux_vars::AbstractArray{Tres, 1},
                                     dxidx::AbstractArray{Tmsh,2},
                                     nrm::AbstractArray{Tmsh,1},
                                     flux_bar::AbstractArray{Tres, 1})

  # Forward sweep
  nrm2 = params.nrm2
  calcBCNormal(params, dxidx, nrm, nrm2)

  # Reverse sweep
  nrm2_bar = zeros(params.nrm2)
  # RoeSolver(params, q, qg, aux_vars, nrm2, flux)
  RoeSolver_revm(params, q, qg, aux_vars, nrm2, flux_bar, nrm2_bar)
  calcBCNormal_revm(params, nrm, nrm2_bar, dxidx_bar)



  return nothing
end



@doc """
### EulerEquationMod.RoeSolver
  This calculates the Roe flux for boundary conditions at a node. The inputs
  must be in *conservative* variables.

  Inputs:
  q  : conservative variables of the fluid
  qg : conservative variables of the boundary
  aux_vars : vector of all auxiliary variables at this node
  dxidx : dxidx matrix at the node
  nrm : sbp face normal vector
  params : ParamType

  Outputs:
    flux : vector to populate with solution

  Aliasing restrictions:  none of the inputs can alias params.res_vals1,
                          params.res_vals2, params.q_vals, params.flux_vals1, or                          params.sat


"""->
function RoeSolver{Tmsh, Tsol, Tres}(params::ParamType{2},
                                     q::AbstractArray{Tsol,1},
                                     qg::AbstractArray{Tsol, 1},
                                     aux_vars::AbstractArray{Tres, 1},
                                     nrm::AbstractArray{Tmsh,1},
                                     flux::AbstractArray{Tres, 1})

  # SAT terms are used for ensuring consistency with the physical problem. Its
  # similar to upwinding which adds dissipation to the problem. SATs on the
  # boundary can be thought of as having two overlapping nodes and because of
  # the discontinuous nature of SBP adds some dissipation.

  # Declaring constants
  d1_0 = 1.0
  d0_0 = 0.0
  d0_5 = 0.5
  tau = 1.0
  gamma = params.gamma
  gami = params.gamma_1
  sat_fac = 1  # multiplier for SAT term

  # Begin main executuion
  nx = nrm[1]
  ny = nrm[2]

  # Compute the Roe Averaged states
  # The left state of Roe are the actual solution variables
  fac = d1_0/q[1]
  uL = q[2]*fac; vL = q[3]*fac;
  phi = d0_5*(uL*uL + vL*vL)
  HL = gamma*q[4]*fac - gami*phi # Total enthalpy, H = e + 0.5*(u^2 + v^2) + p/rho,
                                 # where e is the internal energy per unit mass

  # The right side of the Roe solver comprises the boundary conditions
  fac = d1_0/qg[1]
  uR = qg[2]*fac; vR = qg[3]*fac;
  phi = d0_5*(uR*uR + vR*vR)
  HR = gamma*qg[4]*fac - gami*phi # Total Enthalpy

  # Averaged states
  sqL = sqrt(q[1])
  sqR = sqrt(qg[1])
  fac = d1_0/(sqL + sqR)
  u = (sqL*uL + sqR*uR)*fac
  v = (sqL*vL + sqR*vR)*fac

  H = (sqL*HL + sqR*HR)*fac


  dq = params.v_vals2 # zeros(Tsol, 4)
  dq[:] = q[:] - qg[:]
  sat = params.sat_vals
  calcSAT(params, nrm, dq, sat, [u, v], H)

  euler_flux = params.flux_vals1
  # calculate Euler flux in wall normal directiona
  # because edge numbering is rather arbitary, any memory access is likely to
  # be a cache miss, so we recalculate the Euler flux
  v_vals = params.q_vals
  nrm2 = params.nrm
  nrm2[1] = nx
  nrm2[2] = ny

  convertFromNaturalToWorkingVars(params, q, v_vals)
  calcEulerFlux(params, v_vals, aux_vars, nrm2, euler_flux)

  for i=1:4  # ArrayViews does not support flux[:] = .
    flux[i] = (sat_fac*sat[i] + euler_flux[i])
  end

  return nothing

end # ends the function eulerRoeSAT

function RoeSolver_revm{Tmsh, Tsol, Tres}(params::ParamType{2},
                                     q::AbstractArray{Tsol,1},
                                     qg::AbstractArray{Tsol, 1},
                                     aux_vars::AbstractArray{Tres, 1},
                                     nrm::AbstractArray{Tmsh,1},
                                     flux_bar, nrm_bar)

  # Forward sweep
  tau = 1.0
  gamma = params.gamma
  gami = params.gamma_1
  sat_fac = 1  # multiplier for SAT term

  # Begin main executuion
  nx = nrm[1]
  ny = nrm[2]

  # Compute the Roe Averaged states
  # The left state of Roe are the actual solution variables
  fac = 1.0/q[1]
  uL = q[2]*fac; vL = q[3]*fac;
  phi = 0.5*(uL*uL + vL*vL)
  HL = gamma*q[4]*fac - gami*phi # Total enthalpy, H = e + 0.5*(u^2 + v^2) + p/rho,
                                 # where e is the internal energy per unit mass

  # The right side of the Roe solver comprises the boundary conditions
  fac = 1.0/qg[1]
  uR = qg[2]*fac
  vR = qg[3]*fac
  phi = 0.5*(uR*uR + vR*vR)
  HR = gamma*qg[4]*fac - gami*phi # Total Enthalpy

  # Averaged states
  sqL = sqrt(q[1])
  sqR = sqrt(qg[1])
  fac = 1.0/(sqL + sqR)
  u = (sqL*uL + sqR*uR)*fac
  v = (sqL*vL + sqR*vR)*fac

  H = (sqL*HL + sqR*HR)*fac


  dq = params.v_vals2 # zeros(Tsol, 4)
  dq[:] = q[:] - qg[:]
  sat = params.sat_vals
  calcSAT(params, nrm, dq, sat, [u, v], H)

  euler_flux = params.flux_vals1
  # calculate Euler flux in wall normal directiona
  # because edge numbering is rather arbitary, any memory access is likely to
  # be a cache miss, so we recalculate the Euler flux
  v_vals = params.q_vals
  nrm2 = params.nrm
  nrm2[1] = nx
  nrm2[2] = ny

  convertFromNaturalToWorkingVars(params, q, v_vals)
  calcEulerFlux(params, v_vals, aux_vars, nrm2, euler_flux)

  # Reverse Sweep
  # for i=1:4  # ArrayViews does not support flux[:] = .
  #   flux[i] = (sat_fac*sat[i] + euler_flux[i])
  # end
  euler_flux_bar = zeros(Tsol, 4)
  for i = 4:-1:1
    euler_flux_bar[i] += flux_bar[i]
    sat_bar[i] += sat_fac*flux_bar[i]
  end

  # calcEulerFlux(params, v_vals, aux_vars, nrm2, euler_flux)
  calcEulerFlux_revm(params, v_vals, aux_vars, nrm2, euler_flux_bar, nrm2_bar)
  calcEulerFlux_revq(params, v_vals, aux_vars, nrm2, euler_flux_bar, v_vals_bar)

  # TODO: convertFromNaturalToWorkingVars(params, q, v_vals)
  # For now,
  q_bar[:] += v_vals_bar[:]

  # nrm2[2] = ny
  ny_bar = nrm2_bar[2]
  # nrm2[1] = nx
  nx_bar = nrm2_bar[1]

  #  calcSAT(params, nrm, dq, sat, [u, v], H)
  H_bar = calcSAT_revm(params, nrm, dq, sat, [u, v], H, sat_bar, nrm_bar, vel_bar, dq_bar)

  # No more dependence on mesh metrics so no point reversing anything else

  return nothing
end


"""
  The main Roe solver.  Populates `flux` with the computed flux.
"""
function RoeSolver{Tmsh, Tsol, Tres}(params::ParamType{3},
                                     q::AbstractArray{Tsol,1},
                                     qg::AbstractArray{Tsol, 1},
                                     aux_vars::AbstractArray{Tres, 1},
                                     nrm::AbstractArray{Tmsh,1},
                                     flux::AbstractArray{Tres, 1})


  # SAT terms are used for ensuring consistency with the physical problem. Its
  # similar to upwinding which adds dissipation to the problem. SATs on the
  # boundary can be thought of as having two overlapping nodes and because of
  # the discontinuous nature of SBP adds some dissipation.

  E1dq = params.res_vals1
  E2dq = params.res_vals2

  # Declaring constants
  d1_0 = 1.0
  d0_0 = 0.0
  d0_5 = 0.5
  tau = 1.0
#  sgn = -1.0
  gamma = params.gamma
  gami = params.gamma_1
  sat_Vn = convert(Tsol, 0.025)
  sat_Vl = convert(Tsol, 0.025)
  sat_fac = 1  # multiplier for SAT term

  # Begin main executuion
  nx = nrm[1]
  ny = nrm[2]
  nz = nrm[3]

  dA = sqrt(nx*nx + ny*ny + nz*nz)

  fac = d1_0/q[1]
  uL = q[2]*fac; vL = q[3]*fac; wL = q[4]*fac
  phi = d0_5*(uL*uL + vL*vL + wL*wL)

  HL = gamma*q[5]*fac - gami*phi

  fac = d1_0/qg[1]
  uR = qg[2]*fac; vR = qg[3]*fac; wR = qg[4]*fac
  phi = d0_5*(uR*uR + vR*vR + wR*wR)
  HR = gamma*qg[5]*fac - gami*phi
  sqL = sqrt(q[1])
  sqR = sqrt(qg[1])
  fac = d1_0/(sqL + sqR)
  u = (sqL*uL + sqR*uR)*fac
  v = (sqL*vL + sqR*vR)*fac
  w = (sqL*wL + sqR*wR)*fac

  H = (sqL*HL + sqR*HR)*fac
  phi = d0_5*(u*u + v*v + w*w)
#  println("H = ", H)
#  println("phi = ", phi)
  a = sqrt(gami*(H - phi))
  Un = u*nx + v*ny + w*nz


  lambda1 = Un + dA*a
  lambda2 = Un - dA*a
  lambda3 = Un
  rhoA = absvalue(Un) + dA*a

  lambda1 = d0_5*(tau*max(absvalue(lambda1),sat_Vn *rhoA) - lambda1)
  lambda2 = d0_5*(tau*max(absvalue(lambda2),sat_Vn *rhoA) - lambda2)
  lambda3 = d0_5*(tau*max(absvalue(lambda3),sat_Vl *rhoA) - lambda3)

  dq1 = q[1] - qg[1]
  dq2 = q[2] - qg[2]
  dq3 = q[3] - qg[3]
  dq4 = q[4] - qg[4]
  dq5 = q[5] - qg[5]

  #-- diagonal matrix multiply
#  sat = zeros(Tres, 4)
  sat = params.sat_vals
  sat[1] = lambda3*dq1
  sat[2] = lambda3*dq2
  sat[3] = lambda3*dq3
  sat[4] = lambda3*dq4
  sat[5] = lambda3*dq5

  #-- get E1*dq
  E1dq[1] = phi*dq1 - u*dq2 - v*dq3 - w*dq4 + dq5
  E1dq[2] = E1dq[1]*u
  E1dq[3] = E1dq[1]*v
  E1dq[4] = E1dq[1]*w
  E1dq[5] = E1dq[1]*H

  #-- get E2*dq
  E2dq[1] = d0_0
  E2dq[2] = -Un*dq1 + nx*dq2 + ny*dq3 + nz*dq4
  E2dq[3] = E2dq[2]*ny
  E2dq[4] = E2dq[2]*nz
  E2dq[5] = E2dq[2]*Un
  E2dq[2] = E2dq[2]*nx

  #-- add to sat
  tmp1 = d0_5*(lambda1 + lambda2) - lambda3
  tmp2 = gami/(a*a)
  tmp3 = d1_0/(dA*dA)

  for i=1:5
    sat[i] = sat[i] + tmp1*(tmp2*E1dq[i] + tmp3*E2dq[i])
  end

  #-- get E3*dq
  E1dq[1] = -Un*dq1 + nx*dq2 + ny*dq3 + nz*dq4
  E1dq[2] = E1dq[1]*u
  E1dq[3] = E1dq[1]*v
  E1dq[4] = E1dq[1]*w
  E1dq[5] = E1dq[1]*H

  #-- get E4*dq
  E2dq[1] = d0_0
  E2dq[2] = phi*dq1 - u*dq2 - v*dq3 - w*dq4 + dq5
  E2dq[3] = E2dq[2]*ny
  E1dq[4] = E2dq[2]*nz
  E2dq[5] = E2dq[2]*Un
  E2dq[2] = E2dq[2]*nx

  #-- add to sat
  tmp1 = d0_5*(lambda1 - lambda2)/(dA*a)
  for i=1:5
    sat[i] = sat[i] + tmp1*(E1dq[i] + gami*E2dq[i])
  end

  euler_flux = params.flux_vals1


  # calculate Euler flux in wall normal directiona
  # because edge numbering is rather arbitary, any memory access is likely to
  # be a cache miss, so we recalculate the Euler flux
  v_vals = params.q_vals

  convertFromNaturalToWorkingVars(params, q, v_vals)
  calcEulerFlux(params, v_vals, aux_vars, nrm, euler_flux)

  for i=1:5  # ArrayViews does not support flux[:] = .
    flux[i] = (sat_fac*sat[i] + euler_flux[i])
    # when weak differentiate has transpose = true
  end

  return nothing

end # ends the function eulerRoeSAT

@doc """
###EulerEquationMod.calcSAT

Computes the simultaneous approximation term for use in computing the numerical
flux

**Arguments**

* `params` : Parameter object of type ParamType
* `nrm` : Normal to face in the physical space
* `dq`  : Boundary condition penalty variable
* `sat` : Simultaneous approximation Term
* `u`   : Velocity in the X-direction in physical space
* `v`   : Velocity in the Y-direction in physical space
* `H`   : Total enthalpy

"""->

function calcSAT{Tmsh, Tsol}(params::ParamType{2}, nrm::AbstractArray{Tmsh,1},
                 dq::AbstractArray{Tsol,1}, sat::AbstractArray{Tsol,1},
                 vel::AbstractArray{Tsol, 1}, H::Tsol)


  # SAT parameters
  sat_Vn = convert(Tsol, 0.025)
  sat_Vl = convert(Tsol, 0.025)

  u = vel[1]
  v = vel[2]

  gami = params.gamma_1

  # Begin main executuion
  nx = nrm[1]
  ny = nrm[2]

  dA = sqrt(nx*nx + ny*ny)

  Un = u*nx + v*ny # Normal Velocity

  phi = 0.5*(u*u + v*v)
  a = sqrt(gami*(H - phi)) # speed of sound

  lambda1 = Un + dA*a
  lambda2 = Un - dA*a
  lambda3 = Un

  rhoA = absvalue(Un) + dA*a

  # Compute Eigen Values of the Flux Jacobian
  # The eigen values calculated above cannot be used directly. Near stagnation
  # points lambda3 approaches zero while near sonic lines lambda1 and lambda2
  # approach zero. This has a possibility of creating numerical difficulties.
  # As a result, the eigen values are limited by the following expressions.
#=
  lambda1 = 0.5*(max(absvalue(lambda1),sat_Vn *rhoA) - lambda1)
  lambda2 = 0.5*(max(absvalue(lambda2),sat_Vn *rhoA) - lambda2)
  lambda3 = 0.5*(max(absvalue(lambda3),sat_Vl *rhoA) - lambda3)=#

  dq1 = dq[1]
  dq2 = dq[2]
  dq3 = dq[3]
  dq4 = dq[4]

  sat[1] = lambda3*dq1
  sat[2] = lambda3*dq2
  sat[3] = lambda3*dq3
  sat[4] = lambda3*dq4

  E1dq = zeros(Tsol,4) # params.res_vals1
  E2dq = zeros(Tsol,4) # params.res_vals2

  #=
  #-- get E1*dq
  E1dq[1] = phi*dq1 - u*dq2 - v*dq3 + dq4
  E1dq[2] = E1dq[1]*u
  E1dq[3] = E1dq[1]*v
  E1dq[4] = E1dq[1]*H

  #-- get E2*dq
  E2dq[1] = 0.0
  E2dq[2] = -Un*dq1 + nx*dq2 + ny*dq3
  E2dq[3] = E2dq[2]*ny
  E2dq[4] = E2dq[2]*Un
  E2dq[2] = E2dq[2]*nx

  #-- add to sat
  tmp1 = 0.5*(lambda1 + lambda2) - lambda3
  tmp2 = gami/(a*a)
  tmp3 = 1.0/(dA*dA)
  for i=1:length(sat)
    sat[i] = sat[i] + tmp1*(tmp2*E1dq[i] + tmp3*E2dq[i])
  end

  #-- get E3*dq
  E1dq[1] = -Un*dq1 + nx*dq2 + ny*dq3
  E1dq[2] = E1dq[1]*u
  E1dq[3] = E1dq[1]*v
  E1dq[4] = E1dq[1]*H

  #-- get E4*dq
  E2dq[1] = 0.0=#
  E2dq[2] = phi*dq1 - u*dq2 - v*dq3 + dq4
  E2dq[3] = E2dq[2]*ny
  E2dq[4] = E2dq[2]*Un
  E2dq[2] = E2dq[2]*nx


  #-- add to sat
  tmp1 = 0.5*(lambda1 - lambda2)/(dA*a)
  for i=1:length(sat)
    sat[i] = sat[i] + tmp1*(E1dq[i] + gami*E2dq[i])
  end
  
  return nothing
end  # End function calcSAT

function calcSAT_revm{Tmsh, Tsol}(params::ParamType{2}, nrm::AbstractArray{Tmsh,1},
                 dq::AbstractArray{Tsol,1}, vel::AbstractArray{Tsol, 1},
                 H::Tsol, sat_bar, nrm_bar, vel_bar, dq_bar)

  # Define reverse sweep variables
  E1dq_bar = zeros(Tsol, 4)
  E2dq_bar = zeros(Tsol, 4)
  lambda1_bar = zero(Tsol)
  lambda2_bar = zero(Tsol)
  lambda3_bar = zero(Tsol)
  dA_bar = zero(Tsol)
  a_bar = zero(Tsol)
  nx_bar = zero(Tsol)
  ny_bar = zero(Tsol)
  Un_bar = zero(Tsol)
  phi_bar = zero(Tsol)
  dq_bar = zeros(Tsol, 4) # For 2D
  u_bar = zero(Tsol)
  v_bar = zero(Tsol)
  H_bar = zero(Tsol)
  tmp1_bar = zero(Tsol)
  tmp2_bar = zero(Tsol)
  tmp3_bar = zero(Tsol)
  rhoA_bar = zero(Tsol)

  # Forward Sweep
  sat_Vn = convert(Tsol, 0.025)
  sat_Vl = convert(Tsol, 0.025)

  u = vel[1]
  v = vel[2]

  gami = params.gamma_1

  # Begin main executuion
  nx = nrm[1]
  ny = nrm[2]

  dA = sqrt(nx*nx + ny*ny)

  Un = u*nx + v*ny # Normal Velocity

  phi = 0.5*(u*u + v*v)
  a = sqrt(gami*(H - phi)) # speed of sound

  lambda1 = Un + dA*a
  lambda2 = Un - dA*a
  lambda3 = Un

  rhoA = absvalue(Un) + dA*a

  dq1 = dq[1]
  dq2 = dq[2]
  dq3 = dq[3]
  dq4 = dq[4]

  sat = params.sat_vals
  sat[1] = lambda3*dq1
  sat[2] = lambda3*dq2
  sat[3] = lambda3*dq3
  sat[4] = lambda3*dq4

  E1dq = zeros(Tsol,4) # params.res_vals1
  E2dq = zeros(Tsol,4) # params.res_vals2

  E2dq[2] = phi*dq1 - u*dq2 - v*dq3 + dq4
  E2dq[3] = E2dq[2]*ny
  E2dq[4] = E2dq[2]*Un
  E2dq[2] = E2dq[2]*nx

  #-- add to sat
  tmp1 = 0.5*(lambda1 - lambda2)/(dA*a)
  for i=1:length(sat)
    sat[i] = sat[i] + tmp1*(E1dq[i] + gami*E2dq[i])
  end
  
  # Reverse Sweep
  # for i=1:length(sat)
  #   sat[i] = sat[i] + tmp1*(E1dq[i] + gami*E2dq[i])
  # end
  for i = length(sat_bar):-1:1
    E1dq_bar[i] += tmp1*sat_bar[i]
    E2dq_bar[i] += tmp1*gami*sat_bar[i]
    tmp1_bar += sat_bar[i]*(E1dq[i] + gami*E2dq[i])
    sat_bar[i] += sat_bar[i]
  end

  # tmp1 = 0.5*(lambda1 - lambda2)/(dA*a)
  lambda1_bar += 0.5*tmp1_bar/(dA*a)
  lambda2_bar += -0.5*tmp1_bar/(dA*a)
  dA_bar += -0.5*(lambda1 - lambda2)*tmp1_bar/(dA*dA*a)
  a_bar += -0.5*(lambda1 - lambda2)*tmp1_bar/(dA*a*a)

  # E2dq[2] = E2dq[2]*nx
  nx_bar += E2dq_bar[2]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[2]*nx

  # E2dq[4] = E2dq[2]*Un
  Un_bar += E2dq_bar[4]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[4]*Un

  # E2dq[3] = E2dq[2]*ny
  ny_bar += E2dq_bar[3]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[3]*ny

  # E2dq[2] = phi*dq1 - u*dq2 - v*dq3 + dq4
  phi_bar += E2dq_bar[2]*dq1
  dq_bar[1] += E2dq_bar[2]*phi
  u_bar -= E2dq_bar[2]*dq2
  dq_bar[2] -= E2dq_bar[2]*u
  v_bar -= E2dq_bar[2]*dq3
  dq_bar[3] -= E2dq_bar[2]*v
  dq_bar[4] += E2dq_bar[2]

  # sat[4] = lambda3*dq4
  lambda3_bar += sat_bar[4]*dq4
  dq_bar[4] += sat_bar[4]*lambda3

  # sat[3] = lambda3*dq3
  lambda3_bar += sat_bar[3]*dq3
  dq_bar[3] += sat_bar[3]*lambda3

  # sat[2] = lambda3*dq2
  lambda3_bar += sat_bar[2]*dq2
  dq_bar[2] += sat_bar[2]*lambda3

  # sat[1] = lambda3*dq1
  lambda3_bar += sat_bar[1]*dq1
  dq_bar[1] += sat_bar[1]*lambda3
#=
  # rhoA = absvalue(Un) + dA*a
  dA_bar += rhoA_bar*a
  a_bar += rhoA_bar*dA
  Un_bar += rhoA_bar*absvalue_deriv(Un)
=#
  # lambda3 = Un
  Un_bar += lambda3_bar

  # lambda2 = Un - dA*a
  Un_bar += lambda2_bar
  dA_bar -= lambda2_bar*a
  a_bar -= lambda2_bar*dA

  # lambda1 = Un + dA*a
  Un_bar += lambda1_bar
  dA_bar += lambda1_bar*a
  a_bar += lambda1_bar*dA

  # a = sqrt(gami*(H - phi))
  H_bar +=  0.5*a_bar*gami/a # a_bar*gami/sqrt(gami*(H - phi))
  phi_bar -=  0.5*a_bar*gami/a # a_bar*gami/sqrt(gami*(H - phi))

  # phi = 0.5*(u*u + v*v)
  u_bar += phi_bar*u
  v_bar += phi_bar*v

  # Un = u*nx + v*ny
  u_bar += Un_bar*nx
  nx_bar += Un_bar*u
  v_bar += Un_bar*ny
  ny_bar += Un_bar*v

  # dA = sqrt(nx*nx + ny*ny)
  nx_bar += dA_bar*nx/dA # dA_bar*2*nx/sqrt(nx*nx + ny*ny)
  ny_bar += dA_bar*ny/dA

  # ny = nrm[2]
  nrm_bar[2] += ny_bar

  # nx = nrm[1]
  nrm_bar[1] += nx_bar

  return H_bar
end

#=
function calcSAT_revm{Tmsh, Tsol}(params::ParamType{2}, nrm::AbstractArray{Tmsh,1},
                 dq::AbstractArray{Tsol,1}, vel::AbstractArray{Tsol, 1},
                 H::Tsol, sat_bar, nrm_bar, vel_bar, dq_bar)

  # nrm_bar is the output

  # Reverse mode data initialization
  E1dq_bar = zeros(Tsol, 4) # This is for E3 & E4 matrices. Will be reused for E1 & E2
  E2dq_bar = zeros(Tsol, 4)
  lambda1_bar = zero(Tsol)
  lambda2_bar = zero(Tsol)
  lambda3_bar = zero(Tsol)
  dA_bar = zero(Tsol)
  a_bar = zero(Tsol)
  nx_bar = zero(Tsol)
  ny_bar = zero(Tsol)
  Un_bar = zero(Tsol)
  phi_bar = zero(Tsol)
  dq_bar = zeros(Tsol, 4) # For 2D
  u_bar = zero(Tsol)
  v_bar = zero(Tsol)
  H_bar = zero(Tsol)
  tmp1_bar = zero(Tsol)
  tmp2_bar = zero(Tsol)
  tmp3_bar = zero(Tsol)
  rhoA_bar = zero(Tsol)


  # Forward Sweep
  u = vel[1]
  v = vel[2]

  gami = params.gamma_1

  # Begin main executuion
  nx = nrm[1]
  ny = nrm[2]

  dA = sqrt(nx*nx + ny*ny)

  Un = u*nx + v*ny # Normal Velocity

  phi = 0.5*(u*u + v*v)
  a = sqrt(gami*(H - phi)) # speed of sound

  lambda1 = Un + dA*a
  lambda2 = Un - dA*a
  lambda3 = Un

  rhoA = absvalue(Un) + dA*a

  # Compute Eigen Values of the Flux Jacobian
#=
  lambda1 = 0.5*(max(absvalue(lambda1),sat_Vn *rhoA) - lambda1)
  lambda2 = 0.5*(max(absvalue(lambda2),sat_Vn *rhoA) - lambda2)
  lambda3 = 0.5*(max(absvalue(lambda3),sat_Vl *rhoA) - lambda3)
=#
  dq1 = dq[1]
  dq2 = dq[2]
  dq3 = dq[3]
  dq4 = dq[4]

  sat = params.sat_vals
  sat[1] = lambda3*dq1
  sat[2] = lambda3*dq2
  sat[3] = lambda3*dq3
  sat[4] = lambda3*dq4

  E1dq = zeros(Tsol,4) # params.res_vals1
  E2dq = zeros(Tsol,4) # params.res_vals2

  E1dq = zeros(Tsol,4) # params.res_vals1
  E2dq = zeros(Tsol,4) # params.res_vals2
#=
  #-- get E3*dq
  E1dq[1] = -Un*dq1 + nx*dq2 + ny*dq3
  E1dq[2] = E1dq[1]*u
  E1dq[3] = E1dq[1]*v
  E1dq[4] = E1dq[1]*H

  #-- get E4*dq
  E2dq[1] = 0.0=#
  E2dq[2] = dq4 # phi*dq1 - u*dq2 - v*dq3 + dq4
  E2dq[3] = E2dq[2]*ny
  E2dq[4] = E2dq[2]*Un
  E2dq[2] = E2dq[2]*nx

  #-- add to sat
  tmp1 = 0.5*(lambda1 - lambda2)/(dA*a)
  for i=1:length(sat)
    sat[i] = sat[i] + tmp1*(E1dq[i] + gami*E2dq[i])
  end

  #-----------------------------------------------------------------------------

  # Reverse Sweep
  # for i=1:length(sat)
  #   sat[i] = sat[i] + tmp1*(E1dq[i] + gami*E2dq[i])
  # end
  for i = length(sat_bar):-1:1
    E1dq_bar[i] += tmp1*sat_bar[i]
    E2dq_bar[i] += tmp1*gami*sat_bar[i]
    tmp1_bar += sat_bar[i]*(E1dq[i] + gami*E2dq[i])
    sat_bar[i] += sat_bar[i]
  end

  # tmp1 = 0.5*(lambda1 - lambda2)/(dA*a)
  lambda1_bar += 0.5*tmp1_bar/(dA*a)
  lambda2_bar += -0.5*tmp1_bar/(dA*a)
  dA_bar += -0.5*(lambda1 - lambda2)*tmp1_bar/(dA*dA*a)
  a_bar += -0.5*(lambda1 - lambda2)*tmp1_bar/(dA*a*a)

  # E2dq[2] = E2dq[2]*nx
  nx_bar += E2dq_bar[2]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[2]*nx

  # E2dq[4] = E2dq[2]*Un
  Un_bar += E2dq_bar[4]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[4]*Un

  # E2dq[3] = E2dq[2]*ny
  ny_bar += E2dq_bar[3]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[3]*ny

  # E2dq[2] = phi*dq1 - u*dq2 - v*dq3 + dq4
  phi_bar += E2dq_bar[2]*dq1
  dq_bar[1] += E2dq_bar[2]*phi
  u_bar -= E2dq_bar[2]*dq2
  dq_bar[2] -= E2dq_bar[2]*u
  v_bar -= E2dq_bar[2]*dq3
  dq_bar[3] -= E2dq_bar[2]*v
  dq_bar[4] += E2dq_bar[2]
  #=
  # No need for reversing E2dq[1] = 0.0
  # E1dq[4] = E1dq[1]*H
  H_bar += E1dq_bar[4]*E1dq[1]
  E1dq_bar[1] += E1dq_bar[4]*H

  # E1dq[3] = E1dq[1]*v
  v_bar += E1dq_bar[3]*E1dq[1]
  E1dq_bar[1] += E1dq_bar[3]*v

  # E1dq[2] = E1dq[1]*u
  u_bar += E1dq_bar[2]*E1dq[1]
  E1dq_bar[1] + E1dq_bar[2]*u

  # E1dq[1] = -Un*dq1 + nx*dq2 + ny*dq3
  Un_bar -= E1dq_bar[1]*dq1
  dq_bar[1] -= E1dq_bar[1]*Un
  nx_bar += E1dq_bar[1]*dq2
  dq_bar[2] += E1dq_bar[1]*nx
  ny_bar += E1dq_bar[1]*dq3
  dq_bar[3] += E1dq_bar[1]*ny

  #-----------------------------------------------------------------------------

  # Portion of Forward sweep due to resue of variables
  #-- get E1*dq
  E1dq[1] = phi*dq1 - u*dq2 - v*dq3 + dq4
  E1dq[2] = E1dq[1]*u
  E1dq[3] = E1dq[1]*v
  E1dq[4] = E1dq[1]*H

  #-- get E2*dq
  E2dq[1] = 0.0
  E2dq[2] = -Un*dq1 + nx*dq2 + ny*dq3
  E2dq[3] = E2dq[2]*ny
  E2dq[4] = E2dq[2]*Un
  E2dq[2] = E2dq[2]*nx

  #-- add to sat
  tmp1 = 0.5*(lambda1 + lambda2) - lambda3
  tmp2 = gami/(a*a)
  tmp3 = 1.0/(dA*dA)

  #-----------------------------------------------------------------------------
  # Continuing Reverse sweep
  # for i=1:length(sat)
  #   sat[i] = sat[i] + tmp1*(tmp2*E1dq[i] + tmp3*E2dq[i])
  # end
  tmp1_bar = zero(Tsol)
  fill!(E1dq_bar, 0.0) # Reset them to zero since E3*dq_bar and E4*dq_bar have
  fill!(E2dq_bar, 0.0) # been taken care of.
  for i = length(sat_bar):-1:1
    tmp1_bar += sat_bar[i]*(tmp2*E1dq[i] + tmp3*E2dq[i])
    tmp2_bar += tmp1*sat_bar[i]*E1dq[i]
    tmp3_bar += tmp1*sat_bar[i]*E2dq[i]
    E1dq_bar[i] += tmp1*tmp2*sat_bar[i]
    E2dq_bar[i] += tmp1*tmp3*sat_bar[i]
    sat_bar[i] += sat_bar[i]
  end

  # tmp3 = 1.0/(dA*dA)
  dA_bar -= 2.0*tmp3_bar/(dA^3)

  # tmp2 = gami/(a*a)
  a_bar -= 2.0*gami*tmp2_bar/(a^3)

  # tmp1 = 0.5*(lambda1 + lambda2) - lambda3
  lambda1_bar += 0.5*tmp1_bar
  lambda2_bar += 0.5*tmp1_bar
  lambda3_bar -= tmp1_bar

  # E2dq[2] = E2dq[2]*nx
  nx_bar += E2dq_bar[2]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[2]*nx

  # E2dq[4] = E2dq[2]*Un
  Un_bar += E2dq_bar[4]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[4]*Un

  # E2dq[3] = E2dq[2]*ny
  ny_bar += E2dq_bar[3]*E2dq[2]
  E2dq_bar[2] += E2dq_bar[3]*ny

  # E2dq[2] = -Un*dq1 + nx*dq2 + ny*dq3
  Un_bar -= E2dq_bar[2]*dq1
  dq_bar[1] -= E2dq_bar[2]*Un
  nx_bar += E2dq_bar[2]*dq2
  dq_bar[2] += E2dq_bar[2]*nx
  ny_bar += E2dq_bar[2]*dq3
  dq_bar[3] += E2dq_bar[2]*ny

  # No need to do E2dq[1] = 0.0
  # E1dq[4] = E1dq[1]*H
  H_bar += E1dq_bar[4]*E1dq[1]
  E1dq_bar[1] += E1dq_bar[4]*H

  # E1dq[3] = E1dq[1]*v
  v_bar += E1dq_bar[3]*E1dq[1]
  E1dq_bar[1] += E1dq_bar[3]*v

  # E1dq[2] = E1dq[1]*u
  u_bar += E1dq_bar[2]*E1dq[1]
  E1dq_bar[1] += E1dq_bar[2]*u

  # E1dq[1] = phi*dq1 - u*dq2 - v*dq3 + dq4
  phi_bar += E1dq_bar[1]*dq1
  dq_bar[1] += E1dq_bar[1]*phi
  u_bar -= E1dq_bar[1]*dq2
  dq_bar[2] -= E1dq_bar[1]*u
  v_bar -= E1dq_bar[1]*dq3
  dq_bar[3] -= E1dq_bar[1]*v
  dq_bar[4] += E1dq_bar[1]
  =#

  # sat[4] = lambda3*dq4
  lambda3_bar += sat_bar[4]*dq4
  dq_bar[4] += sat_bar[4]*lambda3

  # sat[3] = lambda3*dq3
  lambda3_bar += sat_bar[3]*dq3
  dq_bar[3] += sat_bar[3]*lambda3

  # sat[2] = lambda3*dq2
  lambda3_bar += sat_bar[2]*dq2
  dq_bar[2] += sat_bar[2]*lambda3

  # sat[1] = lambda3*dq1
  lambda3_bar += sat_bar[1]*dq1
  dq_bar[1] += sat_bar[1]*lambda3
#=
  # Redo Forward sweep for lambda3
  # lambda3 = 0.5*(max(absvalue(lambda3),sat_Vl *rhoA) - lambda3)
  # Breaking the above down.
  # v1 = absvalue(lambda3)
  # v2 = sat_Vl*rhoA
  # v3 = max(v1, v2)
  # lambda3 = 0.5*(v3 - lambda3)
  v3_bar = 0.5*lambda3_bar
  lambda3_bar -= 0.5*lambda3_bar
  v1_bar, v2_bar = max_deriv_rev(absvalue(lambda3), sat_Vl*rhoA, v3_bar)
  rhoA_bar += sat_Vl*v2_bar
  lambda3_bar += v1_bar*absvalue_deriv(lambda3)

  # lambda2 = 0.5*(max(absvalue(lambda2),sat_Vn *rhoA) - lambda2)
  # v1 = absvalue(lambda2)
  # v2 = sat_Vn*rhoA
  # v3 = max(v1, v2)
  # lambda2 = 0.5*(v3 - lambda2)
  v3_bar = 0.5*lambda3_bar
  lambda2_bar -= 0.5*lambda2_bar
  v1_bar, v2_bar = max_deriv_rev(absvalue(lambda2), sat_Vn*rhoA, v3_bar)
  rhoA_bar += sat_Vn*v2_bar
  lambda2_bar += v1_bar*absvalue_deriv(lambda2)

  # lambda1 = 0.5*(max(absvalue(lambda1),sat_Vn *rhoA) - lambda1)
  # v1 = absvalue(lambda1)
  # v2 = sat_Vn*rhoA
  # v3 = max(v1, v2)
  # lambda1 = 0.5*(v3 - lambda1)
  v3_bar = 0.5*lambda1_bar
  lambda1_bar -= 0.5*lambda3_bar
  v1_bar, v2_bar = max_deriv_rev(absvalue(lambda1), sat_Vn*rhoA, v3_bar)
  rhoA_bar += sat_Vn*v2_bar
  lambda1_bar += v1_bar*absvalue_deriv(lambda1)
=#
  # rhoA = absvalue(Un) + dA*a
  dA_bar += rhoA_bar*a
  a_bar += rhoA_bar*dA
  Un_bar += rhoA_bar*absvalue_deriv(Un)

  # lambda3 = Un
  Un_bar += lambda3_bar

  # lambda2 = Un - dA*a
  Un_bar += lambda2_bar
  dA_bar -= lambda2_bar*a
  a_bar -= lambda2_bar*dA

  # lambda1 = Un + dA*a
  Un_bar += lambda1_bar
  dA_bar += lambda1_bar*a
  a_bar += lambda1_bar*dA

  # a = sqrt(gami*(H - phi))
  H_bar +=  0.5*a_bar*gami/a # a_bar*gami/sqrt(gami*(H - phi))
  phi_bar -=  0.5*a_bar*gami/a # a_bar*gami/sqrt(gami*(H - phi))
  println("phi_bar = $phi_bar")
  # phi = 0.5*(u*u + v*v)
  u_bar += phi_bar*u
  v_bar += phi_bar*v

  # Un = u*nx + v*ny
  u_bar += Un_bar*nx
  nx_bar += Un_bar*u
  v_bar += Un_bar*ny
  ny_bar += Un_bar*v

  # dA = sqrt(nx*nx + ny*ny)
  nx_bar += dA_bar*nx/dA # dA_bar*2*nx/sqrt(nx*nx + ny*ny)
  ny_bar += dA_bar*ny/dA

  # ny = nrm[2]
  nrm_bar[2] += ny_bar

  # nx = nrm[1]
  nrm_bar[1] += nx_bar

  return H_bar
end # End function calcSAT_revm
=#
function calcEulerFlux_standard{Tmsh, Tsol, Tres}(params::ParamType,
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dxidx::AbstractMatrix{Tmsh},
                      nrm::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})

  nrm2 = params.nrm2
  calcBCNormal(params, dxidx, nrm, nrm2)
  calcEulerFlux_standard(params, qL, qR, aux_vars, nrm2, F)
  return nothing
end



function calcEulerFlux_standard{Tmsh, Tsol, Tres}(
                      params::ParamType{2, :conservative},
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tsol, 1},
                      dir::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})
# calculate the split form numerical flux function corresponding to the standard DG flux

  pL = calcPressure(params, qL); pR = calcPressure(params, qR)
  rho_avg = 0.5*(qL[1] + qR[1])
  rhou_avg = 0.5*(qL[2] + qR[2])
  rhov_avg = 0.5*(qL[3] + qR[3])
  p_avg = 0.5*(pL + pR)
  rhoLinv = 1/qL[1]; rhoRinv = 1/qR[1]



  F[1] = dir[1]*(rhou_avg) + dir[2]*rhov_avg

  tmp1 = 0.5*(qL[2]*qL[2]*rhoLinv + qR[2]*qR[2]*rhoRinv)
  tmp2 = 0.5*(qL[2]*qL[3]*rhoLinv + qR[2]*qR[3]*rhoRinv)
  F[2] = dir[1]*(tmp1 + p_avg) + dir[2]*tmp2

  tmp1 = 0.5*(qL[2]*qL[3]*rhoLinv + qR[2]*qR[3]*rhoRinv)
  tmp2 = 0.5*(qL[3]*qL[3]*rhoLinv + qR[3]*qR[3]*rhoRinv)
  F[3] = dir[1]*tmp1 + dir[2]*(tmp2 + p_avg)


  tmp1 = 0.5*( (qL[4] + pL)*qL[2]*rhoLinv + (qR[4] + pR)*qR[2]*rhoRinv)
  tmp2 = 0.5*( (qL[4] + pL)*qL[3]*rhoLinv + (qR[4] + pR)*qR[3]*rhoRinv)
  F[4] = dir[1]*tmp1 + dir[2]*tmp2

  return nothing
end

function calcEulerFlux_standard{Tmsh, Tsol, Tres}(
                      params::ParamType{3, :conservative},
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres, 1},
                      dir::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})
# calculate the split form numerical flux function corresponding to the standard DG flux
#TODO: pre-calculate 1/qL[1], 1/qR[1]

  pL = calcPressure(params, qL); pR = calcPressure(params, qR)
  rho_avg = 0.5*(qL[1] + qR[1])
  rhou_avg = 0.5*(qL[2] + qR[2])
  rhov_avg = 0.5*(qL[3] + qR[3])
  rhow_avg = 0.5*(qL[4] + qR[4])
  p_avg = 0.5*(pL + pR)
  rhoLinv = 1/qL[1]; rhoRinv = 1/qR[1]

  F[1] = dir[1]*(rhou_avg) + dir[2]*rhov_avg + dir[3]*rhow_avg

  tmp1 = 0.5*(qL[2]*qL[2]*rhoLinv + qR[2]*qR[2]*rhoRinv)
  tmp2 = 0.5*(qL[2]*qL[3]*rhoLinv + qR[2]*qR[3]*rhoRinv)
  tmp3 = 0.5*(qL[2]*qL[4]*rhoLinv + qR[2]*qR[4]*rhoRinv)
  F[2] = dir[1]*(tmp1 + p_avg) + dir[2]*tmp2 + dir[3]*tmp3

  tmp1 = 0.5*(qL[2]*qL[3]*rhoLinv + qR[2]*qR[3]*rhoRinv)
  tmp2 = 0.5*(qL[3]*qL[3]*rhoLinv + qR[3]*qR[3]*rhoRinv)
  tmp3 = 0.5*(qL[4]*qL[3]*rhoLinv + qR[4]*qR[3]*rhoRinv)
  F[3] = dir[1]*tmp1 + dir[2]*(tmp2 + p_avg) + dir[3]*tmp3

  tmp1 = 0.5*(qL[2]*qL[4]*rhoLinv + qR[2]*qR[4]*rhoRinv)
  tmp2 = 0.5*(qL[3]*qL[4]*rhoLinv + qR[3]*qR[4]*rhoRinv)
  tmp3 = 0.5*(qL[4]*qL[4]*rhoLinv + qR[4]*qR[4]*rhoRinv)
  F[4] = dir[1]*tmp1 + dir[2]*tmp2 + dir[3]*(tmp3 + p_avg)


  tmp1 = 0.5*( (qL[5] + pL)*qL[2]*rhoLinv + (qR[5] + pR)*qR[2]*rhoRinv)
  tmp2 = 0.5*( (qL[5] + pL)*qL[3]*rhoLinv + (qR[5] + pR)*qR[3]*rhoRinv)
  tmp3 = 0.5*( (qL[5] + pL)*qL[4]*rhoLinv + (qR[5] + pR)*qR[4]*rhoRinv)
  F[5] = dir[1]*tmp1 + dir[2]*tmp2 + dir[3]*tmp3

  return nothing
end



function calcEulerFlux_Ducros{Tmsh, Tsol, Tres}(
                      params::ParamType,
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dxidx::AbstractMatrix{Tmsh},
                      nrm::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})

  nrm2 = params.nrm2
  calcBCNormal(params, dxidx, nrm, nrm2)
  calcEulerFlux_Ducros(params, qL, qR, aux_vars, nrm2, F)
  return nothing
end



function calcEulerFlux_Ducros{Tmsh, Tsol, Tres}(params::ParamType{2, :conservative},
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dir::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})
# calculate the split form numerical flux function proposed by Ducros et al.

  pL = calcPressure(params, qL); pR = calcPressure(params, qR)
  uL = qL[2]/qL[1]; uR = qR[2]/qR[1]
  vL = qL[3]/qL[1]; vR = qR[3]/qR[1]

  u_avg = 0.5*(uL + uR)
  v_avg = 0.5*(vL + vR)

  rho_avg = 0.5*(qL[1] + qR[1])
  rhou_avg = 0.5*(qL[2] + qR[2])
  rhov_avg = 0.5*(qL[3] + qR[3])
  E_avg = 0.5*(qL[4] + qR[4])
  p_avg = 0.5*(pL + pR)

  F[1] = dir[1]*rho_avg*u_avg + dir[2]*rho_avg*v_avg
  F[2] = dir[1]*(rhou_avg*u_avg + p_avg) + dir[2]*(rhou_avg*v_avg)
  F[3] = dir[1]*(rhov_avg*u_avg) + dir[2]*(rhov_avg*v_avg + p_avg)
  F[4] = dir[1]*(E_avg + p_avg)*u_avg + dir[2]*(E_avg + p_avg)*v_avg

  return nothing
end

function calcEulerFlux_Ducros{Tmsh, Tsol, Tres}(params::ParamType{3, :conservative},
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dir::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})
# calculate the split form numerical flux function proposed by Ducros et al.

  pL = calcPressure(params, qL); pR = calcPressure(params, qR)
  uL = qL[2]/qL[1]; uR = qR[2]/qR[1]
  vL = qL[3]/qL[1]; vR = qR[3]/qR[1]
  wL = qL[4]/qL[1]; wR = qR[4]/qR[1]

  u_avg = 0.5*(uL + uR)
  v_avg = 0.5*(vL + vR)
  w_avg = 0.5*(wL + wR)

  rho_avg = 0.5*(qL[1] + qR[1])
  rhou_avg = 0.5*(qL[2] + qR[2])
  rhov_avg = 0.5*(qL[3] + qR[3])
  rhow_avg = 0.5*(qL[4] + qR[4])
  E_avg = 0.5*(qL[5] + qR[5])
  p_avg = 0.5*(pL + pR)

  F[1] = dir[1]*rho_avg*u_avg + dir[2]*rho_avg*v_avg + dir[3]*rho_avg*w_avg
  F[2] = dir[1]*(rhou_avg*u_avg + p_avg) + dir[2]*(rhou_avg*v_avg) +
         dir[3]rhou_avg*w_avg
  F[3] = dir[1]*(rhov_avg*u_avg) + dir[2]*(rhov_avg*v_avg + p_avg) +
         dir[3]*rhov_avg*w_avg
  F[4] = dir[1]*rhow_avg*u_avg + dir[2]*rhow_avg*v_avg +
         dir[3]*(rhow_avg*w_avg + p_avg)
  F[5] = dir[1]*(E_avg + p_avg)*u_avg + dir[2]*(E_avg + p_avg)*v_avg +
         dir[3]*( (E_avg + p_avg)*w_avg)

  return nothing
end


function calcEulerFlux_IR{Tmsh, Tsol, Tres}(params::ParamType,
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dxidx::AbstractMatrix{Tmsh},
                      nrm::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})

  nrm2 = params.nrm2
  calcBCNormal(params, dxidx, nrm, nrm2)
  calcEulerFlux_IR(params, qL, qR, aux_vars, nrm2, F)
  return nothing
end


# IR flux
function calcEulerFlux_IR{Tmsh, Tsol, Tres}(params::ParamType{2, :conservative},
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dir::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})

  gamma = params.gamma
  gamma_1 = params.gamma_1
  pL = calcPressure(params, qL); pR = calcPressure(params, qR)
  z1L = sqrt(qL[1]/pL); z1R = sqrt(qR[1]/pR)
  z2L = z1L*qL[2]/qL[1]; z2R = z1R*qR[2]/qR[1]
  z3L = z1L*qL[3]/qL[1]; z3R = z1R*qR[3]/qR[1]
  z4L = sqrt(qL[1]*pL); z4R = sqrt(qR[1]*pR)

  rho_hat = 0.5*(z1L + z1R)*logavg(z4L, z4R)
  u_hat = (z2L + z2R)/(z1L + z1R)
  v_hat = (z3L + z3R)/(z1L + z1R)
  p1_hat = (z4L + z4R)/(z1L + z1R)
  p2_hat = ((gamma + 1)/(2*gamma) )*logavg(z4L, z4R)/logavg(z1L, z1R) + ( gamma_1/(2*gamma) )*(z4L + z4R)/(z1L + z1R)
  h_hat = gamma*p2_hat/(rho_hat*gamma_1) + 0.5*(u_hat*u_hat + v_hat*v_hat)


  Un = dir[1]*u_hat + dir[2]*v_hat
  F[1] = rho_hat*Un
  F[2] = rho_hat*u_hat*Un + dir[1]*p1_hat
  F[3] = rho_hat*v_hat*Un + dir[2]*p1_hat
  F[4] = rho_hat*h_hat*Un
  #=
  F[1] = dir[1]*rho_hat*u_hat + dir[2]*rho_hat*v_hat
  F[2] = dir[1]*(rho_hat*u_hat*u_hat + p1_hat) + dir[2]*rho_hat*u_hat*v_hat
  F[3] = dir[1]*rho_hat*u_hat*v_hat + dir[2]*(rho_hat*v_hat*v_hat + p1_hat)
  F[4] = dir[1]*rho_hat*u_hat*h_hat + dir[2]*rho_hat*v_hat*h_hat
  =#
  return nothing
end

function calcEulerFlux_IR{Tmsh, Tsol, Tres}(params::ParamType{3, :conservative},
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dir::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})

  gamma = params.gamma
  gamma_1 = params.gamma_1
  pL = calcPressure(params, qL); pR = calcPressure(params, qR)
  z1L = sqrt(qL[1]/pL); z1R = sqrt(qR[1]/pR)
  z2L = z1L*qL[2]/qL[1]; z2R = z1R*qR[2]/qR[1]
  z3L = z1L*qL[3]/qL[1]; z3R = z1R*qR[3]/qR[1]
  z4L = z1L*qL[4]/qL[1]; z4R = z1R*qR[4]/qR[1]
  z5L = sqrt(qL[1]*pL); z5R = sqrt(qR[1]*pR)

  rho_hat = 0.5*(z1L + z1R)*logavg(z5L, z5R)
  u_hat = (z2L + z2R)/(z1L + z1R)
  v_hat = (z3L + z3R)/(z1L + z1R)
  w_hat = (z4L + z4R)/(z1L + z1R)
  p1_hat = (z5L + z5R)/(z1L + z1R)
  p2_hat = ((gamma + 1)/(2*gamma) )*logavg(z5L, z5R)/logavg(z1L, z1R) + ( gamma_1/(2*gamma) )*(z5L + z5R)/(z1L + z1R)
  h_hat = gamma*p2_hat/(rho_hat*gamma_1) + 0.5*(u_hat*u_hat + v_hat*v_hat + w_hat*w_hat)

  F[1] = dir[1]*rho_hat*u_hat + dir[2]*rho_hat*v_hat + dir[3]*rho_hat*w_hat
  F[2] = dir[1]*(rho_hat*u_hat*u_hat + p1_hat) + dir[2]*rho_hat*u_hat*v_hat +
         dir[3]*rho_hat*u_hat*w_hat
  F[3] = dir[1]*rho_hat*u_hat*v_hat + dir[2]*(rho_hat*v_hat*v_hat + p1_hat) +
         dir[3]*rho_hat*v_hat*w_hat
  F[4] = dir[1]*rho_hat*u_hat*w_hat + dir[2]*rho_hat*v_hat*w_hat +
         dir[3]*(rho_hat*w_hat*w_hat + p1_hat)
  F[5] = dir[1]*rho_hat*u_hat*h_hat + dir[2]*rho_hat*v_hat*h_hat + dir[3]*rho_hat*w_hat*h_hat

  return nothing
end

# stabilized IR flux
"""
  This function calculates the flux across an interface using the IR
  numerical flux function and a Lax-Friedrich type of entropy dissipation.

  Currently this is implemented for conservative variables only.

  Methods are available that take in dxidx and a normal vector in parametric
  space and compute and normal vector xy space and that take in a
  normal vector directly.

  Inputs:
    qL, qR: vectors conservative variables at left and right states
    aux_vars: aux_vars for qL
    dxidx: scaled mapping jacobian (2x2 or 3x3 in 3d)
    nrm: normal vector in parametric space

  Inputs/Outputs:
    F: vector to be updated with the result

  Aliasing restrictions:
    nothing may alias params.nrm2.  See also getEntropyLFStab
"""
function calcEulerFlux_IRSLF{Tmsh, Tsol, Tres}(params::ParamType,
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dxidx::AbstractMatrix{Tmsh},
                      nrm::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})

  nrm2 = params.nrm2
  calcBCNormal(params, dxidx, nrm, nrm2)
  calcEulerFlux_IRSLF(params, qL, qR, aux_vars, nrm2, F)
  return nothing
end

"""
  This is the second method that takes in a normal vector directly.
  See the first method for a description of what this function does.

  Inputs
    qL, qR: vectors conservative variables at left and right states
    aux_vars: aux_vars for qL
    nrm: a normal vector in xy space

  Inputs/Outputs
    F: vector to be updated with the result

  Alising restrictions:
    See getEntropyLFStab

"""
function calcEulerFlux_IRSLF{Tmsh, Tsol, Tres, Tdim}(
                      params::ParamType{Tdim, :conservative},
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractVector{Tres},
                      dir::AbstractVector{Tmsh},  F::AbstractArray{Tres,1})

  calcEulerFlux_IR(params, qL, qR, aux_vars, dir, F)
  getEntropyLFStab(params, qL, qR, aux_vars, dir, F)

  return nothing
end

"""
  This function is similar to calcEulerFlux_IRSLF, but uses Lax-Wendroff
  dissipation rather than Lax-Friedrich.

  Aliasing restrictions: see getEntropyLWStab
"""
function calcEulerFlux_IRSLW{Tmsh, Tsol, Tres}(params::ParamType,
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractArray{Tres},
                      dxidx::AbstractMatrix{Tmsh},
                      nrm::AbstractArray{Tmsh},  F::AbstractArray{Tres,1})

  nrm2 = params.nrm2
  calcBCNormal(params, dxidx, nrm, nrm2)
  calcEulerFlux_IRSLW(params, qL, qR, aux_vars, nrm2, F)
  return nothing
end

function calcEulerFlux_IRSWF{Tmsh, Tsol, Tres, Tdim}(
                      params::ParamType{Tdim, :conservative},
                      qL::AbstractArray{Tsol,1}, qR::AbstractArray{Tsol, 1},
                      aux_vars::AbstractVector{Tres},
                      dir::AbstractVector{Tmsh},  F::AbstractArray{Tres,1})

  calcEulerFlux_IR(params, qL, qR, aux_vars, dir, F)
  getEntropyLWStab(params, qL, qR, aux_vars, dir, F)

  return nothing
end




function logavg(aL, aR)
# calculate the logarithmic average needed by the IR flux
  xi = aL/aR
  f = (xi - 1)/(xi + 1)
  u = f*f
  eps = 1e-2
  if u < eps
    F = @evalpoly( u, 1, 1/3, 1/5, 1/7, 1/9)
#    F = 1.0 + u/3.0 + u*u/5.0 + u*u*u/7.0 + u*u*u*u/9.0
  else
    F = (log(xi)/2.0)/f
  end

  return (aL + aR)/(2*F)
end
