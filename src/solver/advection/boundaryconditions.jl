# boundaryconditions.jl

@doc """
### AdvectionEquationMod.getBCFunctors

This function uses the opts dictionary to populate mesh.bndry_funcs with
the the functors

This is a high level function.

**Inputs**

*  `mesh` : Abstract mesh type
*  `sbp`  : Summation-by-parts operator
*  `eqn`  : Advection equation object
*  `opts` : Input dictionary options

**Outputs**

*  None

"""->
# use this function to populate access the needed values in BCDict
function getBCFunctors{Tmsh, Tsol, Tdim}(mesh::AbstractMesh{Tmsh}, sbp::SBPOperator, 
                       eqn::AdvectionData{Tsol, Tdim}, opts)
# populate the array mesh.bndry_funcs with the functors for the boundary condition types

#  println("Entered getBCFunctors")

  for i=1:mesh.numBC
    key_i = string("BC", i, "_name")
    val = opts[key_i]
    println("BCDict[val] = ", BCDict[val])
    mesh.bndry_funcs[i] = BCDict[val]
  end

  return nothing
end

@doc """
flux1

Calculates the boundary flux for the advection equation. It works at the nodal
level.

**Inputs**

*  `u_sbp_`: The entry from u_sbp for this node
*  `dxidx` : The jacobian for this node
*  `nrm`   : nrm is the normal vector
*  `net_flux`:
*  `alpha_x` & `alpha_y`: advection velocities in x & y directions

**Outputs**

*  None
"""->

function flux1(u_sbp_, dxidx, nrm, net_flux, alpha_x, alpha_y)
  # This function works at the nodal level  
  # u_sbp_ is the entry from u_sbp for this node
  # dxi_dx is the jacobian for this node
  # nrm is the normal vector

  u_xi = dxidx[1,1]*alpha_x + dxidx[1,2]*alpha_y
  u_eta = dxidx[2,1]*alpha_x + dxidx[2,2]*alpha_y
  mag_x = u_xi*nrm[1]  # x flow magnitude
  mag_y = u_eta*nrm[2]  # y flow magnitude
  mag = mag_x + mag_y
  
  u_bc = sin(-1)  # boundary condition (for all sides)
  # println("u_bc = ", u_bc)

  # because mag is scalar,not vector, can combine these if statements
  if mag < 0  # inflow condition, added factor of nrm[2]
    flx_xi = u_xi*u_bc
  else
    flx_xi = u_xi*u_sbp_
  end

  if mag < 0  # inflow condition, added factor of nrm[1]
    flx_eta = u_eta*u_bc
  else
    flx_eta = u_eta*u_sbp_
  end

  net_flux = flx_xi*nrm[1] + flx_eta*nrm[2]
  # cntr += 1
  
  return nothing
end # end function flux1