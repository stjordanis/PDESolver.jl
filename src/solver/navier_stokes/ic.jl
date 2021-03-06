# functions that populate the initial conditions
# List of functions:

@doc """
### EulerEquationMod.ICTrigonometric

Sets all components of the solution to the free stream condition according
to the angle of attack and and Mach number.

Inputs:
mesh
sbp
eqn
opts

Inputs/Outputs: 
u0: vector to populate with the solution

Aliasing restrictions: none.

"""->

function ICPolynomial(mesh::AbstractMesh{Tmsh}, 
                      sbp::AbstractOperator{Tsbp}, 
                      eqn::NSData{Tsol, Tsol, 3}, 
                      opts, 
                      u0::AbstractVector{Tsol}) where {Tmsh, Tsbp, Tsol}
  sigma = 0.01
  params = eqn.params
  gamma = params.euler_params.gamma
	gamma_1 = params.euler_params.gamma_1
	aoa = params.euler_params.aoa
  beta = eqn.params.sideslip_angle
	rhoInf = 1.0
  uInf = eqn.params.euler_params.Ma * cos(beta) * cos(aoa)
  vInf = eqn.params.euler_params.Ma * sin(beta) * -1
  wInf = eqn.params.euler_params.Ma * cos(beta) * sin(aoa)
	TInf = 1.0

  numEl = mesh.numEl
  nnodes = mesh.numNodesPerElement
  dofpernode = mesh.numDofPerNode
  sol = zeros(Tsol, 5)

  for i=1:numEl
    for j=1:nnodes
      coords_j = sview(mesh.coords, :, j, i)
      dofnums_j = sview(mesh.dofs, :, j, i)
      x = coords_j[1]
      y = coords_j[2]
      z = coords_j[3]

      rho = (x-x*x)*(y-y*y)* (z - z*z)
      u   = (x-x*x)*(y-y*y)* (z - z*z)
      v   = (x-x*x)*(y-y*y)* (z - z*z)
      w   = (x-x*x)*(y-y*y)* (z - z*z)
      T   = (x-x*x)*(y-y*y)* (z - z*z)
      rho = (sigma*rho + 1.0)*rhoInf 
      u   = (sigma*u + 1.0)*uInf
      v   = (sigma*v + 1.0)*vInf
      w   = (sigma*w + 1.0)*wInf
      T   = (sigma*T + 1.0)*TInf
      p   = rho*T/gamma
      E   = T/(gamma*gamma_1) + 0.5*(u*u + v*v + w*w)

      u0[dofnums_j[1]] = rho
      u0[dofnums_j[2]] = rho*u
      u0[dofnums_j[3]] = rho*v
      u0[dofnums_j[4]] = rho*v
      u0[dofnums_j[5]] = T/(gamma*gamma_1) + 0.5*(u*u + v*v + w*w)
      u0[dofnums_j[5]] *= rho
    end
  end
end

function ICPolynomial(mesh::AbstractMesh{Tmsh}, 
                      sbp::AbstractOperator{Tsbp}, 
                      eqn::NSData{Tsol, Tsol, 2}, 
                      opts, 
                      u0::AbstractVector{Tsol}) where {Tmsh, Tsbp, Tsol}
  # populate u0 with initial values
  # this is a template for all other initial conditions

  sigma   = 0.01
  Tdim    = 2
  params  = eqn.params
  gamma   = params.euler_params.gamma
  gamma_1 = gamma - 1.0
  aoa     = params.euler_params.aoa
  q       = zeros(Float64, Tdim+2)
  qRef    = zeros(Float64, Tdim+2)
  qRef[1] = 1.0
  qRef[2] = params.euler_params.Ma*cos(aoa)
  qRef[3] = params.euler_params.Ma*sin(aoa)
  qRef[4] = 1.0

  numEl = mesh.numEl
  nnodes = mesh.numNodesPerElement
  dofpernode = mesh.numDofPerNode

  for i=1:numEl
    for j=1:nnodes
      coords_j = sview(mesh.coords, :, j, i)
      dofnums_j = sview(mesh.dofs, :, j, i)

      x = coords_j[1]
      y = coords_j[2]

      # calcFreeStream(eqn.params, coords_j, sol)

      q[1] = (x-x*x)*(y-y*y) 
      q[2] = (x-x*x)*(y-y*y)
      q[3] = (x-x*x)*(y-y*y)
      q[4] = (x-x*x)*(y-y*y)
      q[1] = (sigma*q[1] + 1.0)*qRef[1] 
      q[2] = (sigma*q[2] + 1.0)*qRef[2]
      q[3] = (sigma*q[3] + 1.0)*qRef[3]
      q[4] = (sigma*q[4] + 1.0)*qRef[4]

      u0[dofnums_j[1]] = q[1]
      u0[dofnums_j[2]] = q[1]*q[2]
      u0[dofnums_j[3]] = q[1]*q[3]
      u0[dofnums_j[4]] = q[4]/(gamma*gamma_1) + 0.5*(q[2]*q[2] + q[3]*q[3])
      u0[dofnums_j[4]] *= q[1]
    end
  end

  return nothing

end

function ICChannel(mesh::AbstractMesh{Tmsh}, 
                   operator::AbstractOperator{Tsbp}, 
                   eqn::NSData{Tsol, Tsol, 3}, 
                   opts, 
                   u0::AbstractVector{Tsol}) where {Tmsh, Tsbp, Tsol}
  # populate u0 with initial values
  # this is a template for all other initial conditions
  Tdim = 3
  sigma = 0.01
  pi = 3.14159265358979323846264338
  params = eqn.params
  gamma = params.euler_params.gamma
	gamma_1 = params.euler_params.gamma_1
	aoa = params.euler_params.aoa
  beta = params.sideslip_angle
	rhoInf = 1.0
  uInf = params.euler_params.Ma * cos(beta) * cos(aoa)
  vInf = params.euler_params.Ma * sin(beta) * -1
  wInf = params.euler_params.Ma * cos(beta) * sin(aoa)
	TInf = 1.0

  numEl = mesh.numEl
  nnodes = mesh.numNodesPerElement

  for i=1:numEl
    for j=1:nnodes
      coords_j = sview(mesh.coords, :, j, i)
      dofnums_j = sview(mesh.dofs, :, j, i)

      x = coords_j[1]
      y = coords_j[2]
      z = coords_j[3]

      rho = rhoInf * (1 + sigma*x*y*z)
      ux = sin(pi*x) + 1
      uy = sin(pi*y) + 1
      uz = sin(pi*z) + 1
      u  = (1 + sigma*ux * uy * uz )* uInf
      vx = sin(pi*x) + 1
      vy = sin(pi*y) + 1
      vz = sin(pi*z) + 1
      v  = (1 + sigma*vx * vy * vz )* vInf
      wx = sin(pi*x) + 1
      wy = sin(pi*y) + 1
      wz = sin(pi*z) + 1
      w  = (1 + sigma*wx * wy * wz) * wInf
      T  = TInf 

      if !params.isViscous
        u += 0.2 * uInf
        v += 0.2 * vInf
        w += 0.2 * wInf
      end

      u0[dofnums_j[1]] = rho
      u0[dofnums_j[2]] = rho*u
      u0[dofnums_j[3]] = rho*v
      u0[dofnums_j[4]] = rho*w
      u0[dofnums_j[5]] = T/(gamma*gamma_1) + 0.5*(u*u + v*v + w*w)
      u0[dofnums_j[5]] *= rho
    end
  end

  return nothing

end  # end function

function ICChannel(mesh::AbstractMesh{Tmsh}, 
                   operator::AbstractOperator{Tsbp}, 
                   eqn::NSData{Tsol, Tsol, 2}, 
                   opts, 
                   u0::AbstractVector{Tsol}) where {Tmsh, Tsbp, Tsol}
  # populate u0 with initial values
  # this is a template for all other initial conditions
  dim = 2
  params = eqn.params
  sigma = 0.1
  pi = 3.14159265358979323846264338
  gamma = eqn.params.euler_params.gamma
  gamma_1 = gamma - 1.0
  aoa = eqn.params.euler_params.aoa
  qRef = zeros(Float64, dim+2)
  qRef[1] = 1.0
  qRef[2] = params.euler_params.Ma*cos(aoa)
  qRef[3] = params.euler_params.Ma*sin(aoa)
  qRef[4] = 1.0

  numEl = mesh.numEl
  nnodes = mesh.numNodesPerElement
  dofpernode = mesh.numDofPerNode

  for i=1 : numEl
    for j=1 : nnodes
      dofnums_j = sview(mesh.dofs, :, j, i)

      x = mesh.coords[1, j, i]
      y = mesh.coords[2, j, i]

      rho = qRef[1] * (sigma*exp(sin(0.5*pi*(x+y))) +  1.0)
      ux  = (exp(x) * sin(pi*x) * sigma + 1) * qRef[2]
      uy  = exp(y) * sin(pi*y)
      u   = ux * uy
      vx  = (exp(x) * sin(pi*x) * sigma + 1) * qRef[3]
      vy  = exp(y) * sin(pi*y)
      v   = vx * vy
      T   = (1 + sigma*exp(0.1*x+0.1*y)) * qRef[4]
      # T   = qRef[4]

      if !eqn.params.isViscous
        u += 0.2 * qRef[2]
      end

      u0[dofnums_j[1]] = rho
      u0[dofnums_j[2]] = rho*u
      u0[dofnums_j[3]] = rho*v
      u0[dofnums_j[4]] = T/(gamma*gamma_1) + 0.5*(u*u + v*v)
      u0[dofnums_j[4]] *= rho
    end
  end

  return nothing

end  # end function

function ICDoubleSquare(mesh::AbstractMesh{Tmsh}, 
                        operator::AbstractOperator{Tsbp}, 
                        eqn::NSData{Tsol, Tsol, 2}, 
                        opts, 
                        u0::AbstractVector{Tsol}) where {Tmsh, Tsbp, Tsol}
  # populate u0 with initial values
  # this is a template for all other initial conditions
  sigma = 0.01
  pi = 3.14159265358979323846264338
  gamma = 1.4
  gamma_1 = gamma - 1.0
  aoa = eqn.params.euler_params.aoa
  rhoInf = 1.0
  uInf = eqn.params.euler_params.Ma*cos(aoa)
  vInf = eqn.params.euler_params.Ma*sin(aoa)
  TInf = 1.0

  numEl = mesh.numEl
  nnodes = mesh.numNodesPerElement
  dofpernode = mesh.numDofPerNode
  sol = zeros(Tsol, 4)

  si = [0.5, 1.5]
  a = [-2.375, 16.875, -45.0, 55.0, -30.0, 6.0]
  # si = [0.5, 2.5]
  # a = [-0.220703125,1.46484375,-3.515625,3.59375,-1.40625,0.1875]
  # si = [0.5, 5.0]
  # a = [-0.01610526850581724,0.10161052685058161,-0.2235431590712794,0.19102779047909357,-0.04470863181425595,0.003251536859218615]
  for i=1:numEl
    for j=1:nnodes
      coords_j = sview(mesh.coords, :, j, i)
      dofnums_j = sview(mesh.dofs, :, j, i)

      x = coords_j[1]
      y = coords_j[2]

      calcFreeStream(eqn.params, coords_j, sol)
      E = sol[4]/sol[1]
      V2 = (sol[2]*sol[2] + sol[3]*sol[3]) / (sol[1]*sol[1])

      gx = 0.0
      gy = 0.0
      if x >= si[1] && x < si[2]
        gx = a[1] + a[2]*x + a[3]*x*x + a[4]*x^3 + a[5]*x^4 + a[6]*x^5
      elseif x >= si[2] 
        gx = 1.0
      elseif x <= -si[1] && x > -si[2]
        gx = a[1] - a[2]*x + a[3]*x*x - a[4]*x^3 + a[5]*x^4 - a[6]*x^5
      elseif x <= -si[2]
        gx = 1.0
      end  

      if y >= si[1] && y < si[2]
        gy = a[1] + a[2]*y + a[3]*y*y + a[4]*y^3 + a[5]*y^4 + a[6]*y^5
      elseif y >= si[2] 
        gy = 1.0
      elseif y <= -si[1] && y > -si[2]
        gy = a[1] - a[2]*y + a[3]*y*y - a[4]*y^3 + a[5]*y^4 - a[6]*y^5
      elseif y <= -si[2] 
        gy = 1.0
      end  

      rho = rhoInf
      u   = uInf * (gx + gy - gx*gy) 
      v   = vInf * (gx + gy - gx*gy) 
      T   = TInf 

      u0[dofnums_j[1]] = rho
      u0[dofnums_j[2]] = rho*u
      u0[dofnums_j[3]] = rho*v
      u0[dofnums_j[4]] = T/(gamma*gamma_1) + 0.5*(u*u + v*v)
      u0[dofnums_j[4]] *= rho
    end
  end

  return nothing

end  # end function

function ICTrigonometric(mesh::AbstractMesh{Tmsh}, 
                         operator::AbstractOperator{Tsbp}, 
                         eqn::NSData{Tsol, Tsol, 2}, 
                         opts, 
                         u0::AbstractVector{Tsol}) where {Tmsh, Tsbp, Tsol}
  # populate u0 with initial values
  # this is a template for all other initial conditions
  sigma = 0.01
  gamma = 1.4
  gamma_1 = gamma - 1.0
  aoa = eqn.params.euler_params.aoa
  rhoInf = 1.0
  uInf = eqn.params.euler_params.Ma*cos(aoa)
  vInf = eqn.params.euler_params.Ma*sin(aoa)
  TInf = 1.0

  numEl = mesh.numEl
  nnodes = mesh.numNodesPerElement
  dofpernode = mesh.numDofPerNode
  for i=1:numEl
    for j=1:nnodes
      coords_j = sview(mesh.coords, :, j, i)
      dofnums_j = sview(mesh.dofs, :, j, i)

      x = coords_j[1]
      y = coords_j[2]

      x2 = 2*x*pi
      y2 = 2*y*pi
      x3 = 3*x*pi
      y3 = 3*y*pi
      x4 = 4*x*pi
      y4 = 4*y*pi
      sx2 = sin(x2)
      sy2 = sin(y2)
      sx3 = sin(x3)
      sy3 = sin(y3)
      sx4 = sin(x4)
      sy4 = sin(y4)
      cx2 = cos(x2)
      cx3 = cos(x3)
      cx4 = cos(x4)
      cy2 = cos(y2)
      cy3 = cos(y3)
      cy4 = cos(y4)
      #
      # Exact solution in form of primitive variables
      #
      rho = sx2 * sy2
      u   = sx4 * sy4
      v   = sx3 * sy3
      T   = (1.0 - cx2) * (1.0 - cy2)
      rho = (sigma*rho + 1.0)*rhoInf 
      u   = (sigma*u + 1.0)*uInf
      v   = (sigma*v + 1.0)*vInf
      T   = (sigma*T + 1.0)*TInf

      u0[dofnums_j[1]] = rho
      u0[dofnums_j[2]] = rho*u
      u0[dofnums_j[3]] = rho*v
      u0[dofnums_j[4]] = T/(gamma*gamma_1) + 0.5*(u*u + v*v)
      u0[dofnums_j[4]] = u0[dofnums_j[4]] * rho
    end
  end

  return nothing

end  # end function

function ICTrigonometric(mesh::AbstractMesh{Tmsh}, 
                         operator::AbstractOperator{Tsbp}, 
                         eqn::NSData{Tsol, Tres, 3}, 
                         opts, 
                         u0::AbstractVector{Tsol}) where {Tmsh, Tsbp, Tsol, Tres}
  # populate u0 with initial values
  # this is a template for all other initial conditions
  sigma = 0.0001
  pi = 3.14159265358979323846264338
  gamma = 1.4
  gamma_1 = gamma - 1.0
  aoa = eqn.params.euler_params.aoa
  beta = eqn.params.sideslip_angle
  rhoInf = 1.0
  uInf = eqn.params.euler_params.Ma * cos(beta) * cos(aoa)
  vInf = eqn.params.euler_params.Ma * sin(beta) * -1
  wInf = eqn.params.euler_params.Ma * cos(beta) * sin(aoa)
  TInf = 1.0

  numEl = mesh.numEl
  nnodes = mesh.numNodesPerElement
  dofpernode = mesh.numDofPerNode
  sol = zeros(Tsol, 5)
  for i=1:numEl
    for j=1:nnodes
      xyz = sview(mesh.coords, :, j, i)
      dofnums_j = sview(mesh.dofs, :, j, i)

      calcFreeStream(eqn.params, xyz, sol)

      xyz1 = 1 * pi * xyz
      xyz2 = 2 * pi * xyz
      xyz4 = 4 * pi * xyz
      sin_val_1 = sin(xyz1)
      cos_val_1 = cos(xyz1)
      sin_val_2 = sin(xyz2)
      cos_val_2 = cos(xyz2)
      sin_val_4 = sin(xyz4)
      cos_val_4 = cos(xyz4)
      #
      # Exact solution in form of primitive variables
      #
      rho = sin_val_2[1] * sin_val_2[2] * sin_val_2[3] 
      u   = sin_val_4[1] * sin_val_4[2] * sin_val_4[3]
      v   = sin_val_2[1] * sin_val_2[2] * sin_val_2[3]
      w   = sin_val_1[1] * sin_val_1[2] * sin_val_1[3] 
      T   = (1.0 - cos_val_4[1]) * (1.0 - cos_val_4[2]) * (1.0 - cos_val_4[3])

      rho = (sigma*rho + 1.0)*rhoInf 
      u = (sigma*u + 1.0) * uInf
      v = (sigma*v + 1.0) * vInf
      w = (sigma*w + 1.0) * wInf
      T = (sigma*T + 1.0) * TInf
      vel2 = u*u + v*v + w*w

      u0[dofnums_j[1]] = rho
      u0[dofnums_j[2]] = rho*u
      u0[dofnums_j[3]] = rho*v
      u0[dofnums_j[4]] = rho*w
      u0[dofnums_j[5]] = rho*(T/(gamma*gamma_1) + 0.5*vel2)
    end
  end

  return nothing
end  # end function

global const ICDict = Dict{String, Function}(
  "ICTrigonometric" => ICTrigonometric,
  "ICPolynomial" => ICPolynomial,
  "ICChannel" => ICChannel,
  "ICDoubleSquare" => ICDoubleSquare,
)

