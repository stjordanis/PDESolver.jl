 # SUPG implementation
function SUPG{Tmsh, Tsol, Tdim}(mesh::AbstractMesh{Tmsh}, sbp::SBPOperator, 
	                            eqn::EulerData{Tsol, Tdim})

  FluxJacobian(mesh, sbp, eqn) # Calculate the euler flux jacobian  
  tau = zeros(Tsol, mesh.numNodesPerElement, mesh.numEl) # Stabilization term
  calcStabilizationTerm(mesh, sbp, eqn, tau)
  # println("tau = \n", tau)
  #=
  counter = 0
  for i = 1:mesh.numEl
    for j = 1:mesh.numNodesPerElement
      if tau[j,i] == 0.0
        counter += 1
      end
    end
  end
  if counter > 0
    println("0 tau in use")
  else
    println("No 0 tau")
  end 
  =#

  #=
  # Calculate strong residual
  strong_res = zeros(eqn.res)
  for i = 1:Tdim
    flux_parametric_i = view(eqn.flux_parametric,:,:,:,i)
    differentiate!(sbp, i, flux_parametric_i, strong_res)
  end
  =#
  supg_res = zeros(eqn.res)
  intvec = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerElement, mesh.numEl, 
                 Tdim) # intermediate vector for calculating integral 

  # SUPG works at the element level so we need to do do a loop over elements
  # get the strong residual from the weak residual. since it also includes the 
  # boundary conditions
  
  for i = 1:mesh.numEl  
    for j = 1:mesh.numNodesPerElement
      strong_res = zeros(Tsol, mesh.numDofPerNode)
      JHinverse = mesh.jac[j,i]/sbp.w[j]
      for k = 1:mesh.numDofPerNode
        strong_res[k] = JHinverse*eqn.res[k,j,i]
      end
      Axi = view(eqn.Axi,:,:,j,i)
      Aeta = view(eqn.Aeta,:,:,j,i)
      intvec[:,j,i,1] = (tau[j,i]*Axi).'*strong_res # [:,j,i]
      intvec[:,j,i,2] = (tau[j,i]*Aeta).'*strong_res # [:,j,i]
    end # end for j = 1:mesh.numNodesPerElement
  end   # end for i = 1:mesh.numEl
    
  # calculate the SUPG residual  
  for i = 1:Tdim
    intvec_i = view(intvec,:,:,:,i)
    weakdifferentiate!(sbp, i, intvec_i,supg_res, trans=true)
  end
  
  
  #=
  supg_res_vec = zeros(eqn.res_vec)
  for i=1:mesh.numEl  # loop over elements
    for j=1:mesh.numNodesPerElement
      for k=1:4  # loop over dofs on the node
        dofnum_k = mesh.dofs[k, j, i]
        supg_res_vec[dofnum_k] += supg_res[k,j,i]
      end
    end
  end
  =# 
  # Add tthe SUPG residual to the weak residual
  for i = 1:mesh.numEl
    for j = 1:mesh.numNodesPerElement
      for k = 1:mesh.numDofPerNode
        eqn.res[k,j,i] += supg_res[k,j,i] # because the negative sign is 
      end                                 # already incorporated in the weak 
    end                                   # residual.
  end
  
  # innerprod_supg = eqn.q_vec.'*supg_res_vec
  # println("innerprod_SUPG = ", innerprod_supg)
  
  #  println("eqn.res = \n", eqn.res)
  #  println("eqn.q = \n", eqn.q)
  return nothing
end # end function SUPG


function FluxJacobian{Tmsh, Tsol, Tdim}(mesh::AbstractMesh{Tmsh}, 
	                                      sbp::SBPOperator, 
	                                      eqn::EulerData{Tsol, Tdim})

  # global function that calculates the flux jacobian for all the nodes in the
  # mesh. Its only for 2D
  
  fill!(eqn.Axi, 0.0)   # Reset Axi & Aeta to zero before calculating flux-
  fill!(eqn.Aeta, 0.0)  # jacobaian

  gamma_1 = eqn.params.gamma_1
  gamma = eqn.params.gamma
  R = eqn.params.R     # Gas constant
  cv = eqn.params.cv   # Specific heat at constant volume
  for i = 1:mesh.numEl
    for j = 1:mesh.numNodesPerElement
      q = view(eqn.q,:, j, i)
      dxidx = view(mesh.dxidx,:,:,j,i)
      u = q[2]/q[1] # Get velocity in the x-direction 
      v = q[3]/q[1] # Get velocity in the x-direction
      intvar = (R/cv)*(q[4]/q[1] - 0.5*(u*u + v*v)) # intermediate variable
      Ax= zeros(Tsol, 4, 4) # Flux jacobian in the x direction
      Ay = zeros(Ax)        # Flux jacobian in the y direction

      # Populating Ax
      Ax[1,1] = 0
      Ax[1,2] = 1
      Ax[1,3] = 0
      Ax[1,4] = 0
      Ax[2,1] = -u*u + 0.5*R*(u*u + v*v)/cv 
      Ax[2,2] = 2*u - R*u/cv
      Ax[2,3] = -R*v/cv
      Ax[2,4] = R/cv
      Ax[3,1] = -u*v
      Ax[3,2] = v
      Ax[3,3] = u
      Ax[3,4] = 0
      Ax[4,1] = -q[2]*q[4]/(q[1]*q[1]) - u*intvar + 0.5*u*R*(u*u + v*v)/cv
      Ax[4,2] = q[4]/q[1] + intvar - R*u*u/cv
      Ax[4,3] = -R*u*v/cv
      Ax[4,4] = u + R*u/cv

      # Populating Ay
      Ay[1,1] = 0
      Ay[1,2] = 0
      Ay[1,3] = 1
      Ay[1,4] = 0
      Ay[2,1] = -v*u 
      Ay[2,2] = v
      Ay[2,3] = u
      Ay[2,4] = 0
      Ay[3,1] = -v*v + 0.5*R*(u*u + v*v)/cv
      Ay[3,2] = -R*u/cv
      Ay[3,3] = 2*v - R*v/cv
      Ay[3,4] = R/cv
      Ay[4,1] = -q[3]*q[4]/(q[1]*q[1]) - v*intvar + v*(R/cv)*0.5*(u*u + v*v)
      Ay[4,2] = -R*v*u/cv
      Ay[4,3] = q[4]/q[1] + intvar - R*v*v/cv
      Ay[4,4] = v + R*v/cv

      eqn.Axi[:,:,j,i] = Ax*dxidx[1,1] + Ay*dxidx[1,2]
      eqn.Aeta[:,:,j,i] = Ax*dxidx[2,1] + Ay*dxidx[2,2]
    end  # end for j = 1:mesh.numNodesPerElement
  end    # end for i = 1:mesh.numEL	
                                      
  return nothing
end # end function FluxJacobian

# Stabilization Term 3
function calcStabilizationTerm{Tmsh, Tsol, Tdim}(mesh::AbstractMesh{Tmsh}, 
                               sbp::SBPOperator, eqn::EulerData{Tsol, Tdim},
                               tau::AbstractArray{Tsol,2})
  
  # Reference: http://enu.kz/repository/2010/AIAA-2010-1183.pdf, eqn 15

  # Get shape function derivatives
  Hinv = 1./sbp.w
  # println(Hinv)
  
  shapefuncderiv = zeros(sbp.numnodes, sbp.numnodes, Tdim)
  for k = 1:Tdim
    for i = 1:sbp.numnodes
      for j = 1:sbp.numnodes
        shapefuncderiv[j,i,k] = Hinv[i]*sbp.Q[j,i,k]
      end
    end
  end
  # println(eqn.Axi)
  
  
  for i = 1:mesh.numEl
    for j = 1:mesh.numNodesPerElement
      q = view(eqn.q,:,j,i)
      T = (q[4] - 0.5*(q[2]*q[2] + q[3]*q[3])/q[1])*(1/(q[1]*eqn.params.cv))
      c = sqrt(eqn.params.gamma*eqn.params.R*T)  # Speed of sound
      ux = q[2]/q[1]
      uy = q[3]/q[1]
      h_supg = 0.0
      for k = 1:sbp.numnodes
        h_supg += abs(ux*shapefuncderiv[j,k,1] + uy*shapefuncderiv[j,k,2])
      end
      h_supg = 2/h_supg
      tau[j,i] = 0.5*h_supg/(c + sqrt(ux*ux + uy*uy))
    end
  end


  return nothing
end # end calcStabilizationTerm

#=
# Stabilization Term 1
function calcStabilizationTerm{Tmsh, Tsol, Tdim}(mesh::AbstractMesh{Tmsh}, 
                               sbp::SBPOperator, eqn::EulerData{Tsol, Tdim},
                               tau::AbstractArray{Tsol,2})
  
  # q in the parametric space. Since everything happens in this space
  q_param = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerElement, mesh.numEl)
  
  for i = 1:mesh.numEl
    for j = 1:mesh.numNodesPerElement
      q = view(eqn.q,:,j,i)
      dxidx = view(mesh.dxidx,:,:,j,i)
      rhoe = q[4] -0.5*(q[2]*q[2] + q[3]*q[3])/(q[1]*q[1]) 
      uxi = (q[2]*dxidx[1,1] + q[3]*dxidx[1,2])/q[1]
      ueta = (q[2]*dxidx[2,1] + q[3]*dxidx[2,2])/q[1]
      q_param[1,j,i] = q[1]
      q_param[2,j,i] = q[1]*uxi
      q_param[3,j,i] = q[1]*ueta
      q_param[4,j,i] = rhoe
    end # end for j = 1:mesh.numNodesPerElement
  end   # end for i = 1:mesh.numEl

  beta = zeros(Tsol,2, mesh.numNodesPerElement, mesh.numEl)
  
  for k = 1:Tdim
    res = zeros(q_param)
    differentiate!(sbp, k, q_param, res)
    for i = 1:mesh.numEl
      for j = 1:mesh.numNodesPerElement
        for l = 1:mesh.numDofPerNode
          beta[k,j,i] += q_param[l,j,i]*res[l,j,i]
        end # end for l = 1:mesh.numDofPerNode
      end   # end for j = 1:mesh.numNodesPerElement
    end     # end for i = 1:mesh.numEl
  end       # end for k = 1:Tdim

  for i = 1:mesh.numEl
    elem_area = calcElementArea(mesh.coords[:,:,i])
    h = sqrt(2*elem_area)
    for j = 1:mesh.numNodesPerElement
      beta[:,j,i] = beta[:,j,i]/norm(beta[:,j,i],2)
      q = view(eqn.q,:,j,i)
      T = (q[4] - 0.5*(q[2]*q[2] + q[3]*q[3])/q[1])*(1/(q[1]*eqn.params.cv))
      c = sqrt(eqn.params.gamma*eqn.params.R*T)  # Speed of sound
      uxi = zeros(Tsol,2) # Array of velocities in the xi & eta direction
      uxi[1] = q_param[2,j,i]/q_param[1,j,i]
      uxi[2] = q_param[3,j,i]/q_param[1,j,i]
      # Advective stabilization term
      tau_a = 0.5*h/(c + norm(uxi.'*beta[:,j,i], 1))
      # tau[j,i] = 0.005*max(0.0, tau_a)
      tau[j,i] = max(0.0, tau_a)
    end # end for j = 1:mesh.numNodesPerElement
  end   # for i = 1:mesh.numEl

  return nothing
end # end calcStabilizationTerm
=#

#=
# Stabilization term 2
function calcStabilizationTerm{Tmsh, Tsol, Tdim}(mesh::AbstractMesh{Tmsh}, 
                               sbp::SBPOperator, eqn::EulerData{Tsol, Tdim},
                               tau::AbstractArray{Tsol,2})
  
  # Reference for stabilization: http://enu.kz/repository/2010/AIAA-2010-1183.pdf

  for i = 1:mesh.numEl
    for j = 1:mesh.numNodesPerElement
      C = 2 # for 2D quad with ref. coord [-1,1] 
            # for 2D tri with ref coord [0,1], C = 1
      q = view(eqn.q,:,j,i)
      T = (q[4] - 0.5*(q[2]*q[2] + q[3]*q[3])/q[1])*(1/(q[1]*eqn.params.cv))
      c = sqrt(eqn.params.gamma*eqn.params.R*T)  # Speed of sound
      ux = q[2]/q[1]
      uy = q[3]/q[1]
      dxidx = view(mesh.dxidx,:,:, j, i)
      if abs(ux) < 1e-13 || abs(uy) < 1e-13
        tau[j,i] = 0.0
      else
        g_ij = dxidx[1,1]*dxidx[1,2] + dxidx[2,1]*dxidx[2,2]
        if abs(g_ij) < 1e-13
          tau[j,i] = 0.0
        else
          elem_area = calcElementArea(mesh.coords[:,:,i])
          # h_supg = sqrt(2*elem_area)
          h_supg = C*sqrt((ux*ux + uy*uy)/(ux*g_ij*uy))
          tau[j,i] = 0.5*h_supg/(c + sqrt(ux*ux + uy*uy))
        end # end if
      end   # end if
    end # end for j = 1:mesh.numNodesPerElement
  end   # end for i = 1:mesh.numEl

  return nothing
end # end calcStabilizationTerm
=#
#=
# Stabilization term 4
function calcStabilizationTerm{Tmsh, Tsol, Tdim}(mesh::AbstractMesh{Tmsh}, 
                               sbp::SBPOperator, eqn::EulerData{Tsol, Tdim},
                               tau::AbstractArray{Tsol,2})

  # Reference: Three-Dimensional Stabilized Finite Elements for Compressible 
  #            Navier–Stokes, T. Taylor Erwin, AIAA Journal Vol 51, No. 6,
  #            June 2013

  # Get shape function derivatives
  Hinv = 1./sbp.w
  # println(Hinv)
  
  shapefuncderiv = zeros(sbp.numnodes, sbp.numnodes, Tdim)
  for k = 1:Tdim
    for i = 1:sbp.numnodes
      for j = 1:sbp.numnodes
        shapefuncderiv[j,i,k] = Hinv[i]*sbp.Q[j,i,k]
      end
    end
  end

  for i = 1:mesh.numEl
    for j = 1:mesh.numNodesPerElement
      Axi = view(eqn.Axi,:,:,j,i)
      Aeta = view(eqn.Aeta,:,:,j,i)
      invtau = zeros(mesh.numDofPerNode, mesh.numDofPerNode)
      for k = 1:sbp.numnodes
        invtau += shapefuncderiv[j,k,1]*Axi + shapefuncderiv[j,k,2]*Aeta
        #println("invtau = ", invtau)
      end
      T = inv(invtau)
      println("T = \n", T)
    end
  end
  

  return nothing
end # end calcStabilizationTerm
=#

function calcElementArea{Tmsh}(coords::AbstractArray{Tmsh, 2})
  # Calculates the element area using coordinates
  # 2D function for linear mapping

  A = coords[:,1]
  B = coords[:,2]
  C = coords[:,3]
  area = 0.5*(A[1]*(B[2] - C[2]) + B[1]*(C[2] - A[2]) + C[1]*(A[2] - B[2]))
  
  return area
end # end function calcElementArea

#------------------------------------------------------------------------------
# Debugging code
# calculate the boundary integral using the actual euler flux

function getPhysBCFluxes(mesh, sbp, eqn, opts, bndryfluxPhysical)
  # Calculate the physical BC flux

  #println("mesh.bndry_funcs = ", mesh.bndry_funcs)
  
  functor_i = BCDict["isentropicVortexBC_physical"]
  for i=1:mesh.numBC
  #  println("computing flux for boundary condition ", i)
    # functor_i = mesh.bndry_funcs[i]
    start_index = mesh.bndry_offsets[i]
    end_index = mesh.bndry_offsets[i+1]
    bndry_facenums_i = view(mesh.bndryfaces, start_index:(end_index - 1))
    bndryflux_i = view(bndryfluxPhysical, :, :, start_index:(end_index - 1))
    #functor_i(q, flux_parametric, aux_vars, x, dxidx, nrm, bndryflux_i, eqn.params)

    calcBoundaryFlux(mesh, sbp, eqn, functor_i, bndry_facenums_i, bndryflux_i)
  end


  return nothing
end


function residualComparison(mesh, sbp, eqn, opts)

 # Get strong residual by differentiating
  differentiation_strong_res = zeros(eqn.res)
  
  for i = 1:Tdim
    flux_parametric_i = view(eqn.flux_parametric,:,:,:,i)
    differentiate!(sbp, i, flux_parametric_i, differentiation_strong_res)
  end
  

  # Get strong residual from the weak form
  strong_res_from_weak = zeros(eqn.res)
  for i = 1:mesh.numEl  
    for j = 1:mesh.numNodesPerElement
      JHinverse = mesh.jac[j,i]/sbp.w[j]
      for k = 1:mesh.numDofPerNode
        strong_res_from_weak[k,j,i] = JHinverse*eqn.res[k,j,i]
      end # end for k = 1:mesh.numDofPerNode
    end # end for i = 1:mesh.numEl 
  end   # end for j = 1:mesh.numNodesPerElement

  println("differentiation_strong_res = \n", differentiation_strong_res)
  println("strong_res_from_weak = \n", strong_res_from_weak)
  # println("\n eqn.res = \n", eqn.res)
  Error = zeros(eqn.res)
  for i = 1:mesh.numEl
    Error[:,:,i] = differentiation_strong_res[:,:,i] + strong_res_from_weak[:,:,i]
  end
  println("\nError = \n", Error)

  return nothing
end # end function residualComparison


#----------------------------------------------------------------------------