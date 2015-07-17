using ArrayViews
using Debug


function newton_fd(func, mesh, sbp, eqn, opts; itermax=200, step_tol=1e-6, res_tol =1e-6)
  # this function drives the non-linear residual to some specified tolerance
  # using Newton's Method
  # the jacobian is formed using finite differences
  # the initial condition is stored in eqn.SL0
  # itermax is the maximum number of iterations

  println("\nEntered newton_fd")
  println("step_tol = ", step_tol)
  println("res_tol = ", res_tol)
  println("itermax = ", itermax)

  step_fac = 0.5  # step size limiter
  m = length(eqn.SL)
  Tsol = typeof(eqn.SL[1])
  jac = zeros(Tsol, m, m)  # storage of the jacobian matrix
  res_0 = zeros(eqn.SL0)  # function evaluated at u0
  delta_SL = zeros(eqn.SL0)  # newton update
  step_norm = zero(Tsol)  # norm of newton update
  step_norm_1 = zero(Tsol) # norm of previous newton update

  for i=1:itermax
  println("Newton iteration: ", i)
  # compute residual at initial condition
  func(mesh, sbp, eqn, opts, eqn.SL0, eqn.SL)
  res_0[:] = eqn.SL
  res_0_norm = norm(eqn.SL)/m
  println("residual norm = ", res_0_norm)
#  println("SL0 = ", res_0)

   if res_0_norm < res_tol
     println("Newton iteration converged with residual norm ", res_0_norm)
     return nothing
   end

    epsilon = 1e-6  # finite difference perturbation
    # calculate jacobian
    for j=1:m
      println("  jacobian iteration ", j)
      if j==1
	eqn.SL0[j] +=  epsilon
      else
	eqn.SL0[j-1] -= epsilon # undo previous iteration pertubation
	eqn.SL0[j] += epsilon
      end

      # evaluate residual
      fill!(eqn.SL, 0.0)
      func(mesh, sbp, eqn, opts, eqn.SL0, eqn.SL)
 #     println("column ", j, " of jacobian, SL = ", eqn.SL)
      calcJacRow(unsafe_view(jac, :, j), res_0, eqn.SL, epsilon)
#      println("SL norm = ", norm(SL)/m)
      
    end


    # jacobian is complete
    jac_cond = cond(jac)  # get condition number
    println("  jacobian condition number = ", jac_cond)

#    println("first row of jacobian is: ")
#    for j=1:m
#      println(j, "   ", jac[1,i])
#    end



#    @bp
    # now jac is complete
    delta_SL[:] = jac\(-res_0)  #  calculate Newton update
    eqn.SL0[:] += step_fac*delta_SL  # update SL0

    step_norm = norm(delta_SL)/m


#    println("delta_SL = ", delta_SL)
#=
    println("delta_sl = ")
    for i=1:m
      println(i, "   ", delta_SL[i])
    end
=#
    println("step_norm = ", step_norm)
#    println("jac = ", jac)

    print("\n")

    # check stopping criteria
    if (step_norm < step_tol)
      println("Newton iteration converged with step_norm = ", step_norm)

      # compute residual at final SL0
      func(mesh, sbp, eqn, eqn.SL0, eqn.SL)
      return nothing
    end

    # adjust step size limiter
    if (step_norm < step_norm_1)  # decreasing step size
      step_fac *= 1.1

      if step_fac > 1.0
	step_fac = 1.0
      end
    end


    step_norm_1 = step_norm
  end  # end loop over newton iterations

  println("Warning: Newton iteration did not converge in ", itermax, " iterations")
  println("  Final step size: ", step_norm)
  return nothing
end


function calcJacRow{T <: Real}(jac_row, res_0, res::AbstractArray{T,1}, epsilon)
# calculate a row of the jacobian from res_0, the function evaluated 
# at the original point, and res, the function evaluated at a perturbed point

m = length(res_0)

for i=1:m
  jac_row[i] = (res[i] - res_0[i])/epsilon
end

return nothing

end



@debug function newton_complex(func, mesh, sbp, eqn, opts; itermax=200, step_tol=1e-6, res_tol=1e-6)
  # this function drives the non-linear residual to some specified tolerance
  # using Newton's Method
  # the jacobian is formed using finite differences
  # the initial condition is stored in eqn.SL0
  # itermax is the maximum number of iterations

  step_fac = 0.5  # step size limiter
  m = length(eqn.SL)
  Tsol = typeof(eqn.SL[1])
  Tjac = typeof(real(eqn.SL[1]))  # type of jacobian, residual
  jac = zeros(Tjac, m, m)  # storage of the jacobian matrix
  res_0 = zeros(Tjac, m)  # function evaluated at u0
  res_0_norm = 0.0  # norm of res_0
  delta_SL = zeros(Tjac, m)  # newton update
  step_norm = zero(Tjac)  # norm of newton update
  step_norm_1 = zero(Tjac) # norm of previous newton update

  for i=1:itermax
  println("Newton iteration: ", i)
  println("step_fac = ", step_fac)
  # compute residual at initial condition
  func(mesh, sbp, eqn, opts, eqn.SL0, eqn.SL)
  println("evaluated residual")
  res_0[:] = real(eqn.SL)  # is there an unnecessary copy here?

#
#  println("SL0 = ", res_0)

  res_0_norm = norm(eqn.SL)/m
  println("residual norm = ", res_0_norm)
#  println("SL0 = ", res_0)

   if res_0_norm < res_tol
     println("Newton iteration converged with residual norm ", res_0_norm)
     return nothing
   end

 


    epsilon = 1e-20  # complex step perturbation
    # calculate jacobian
    for j=1:m
      if j==1
	eqn.SL0[j] +=  complex(0, epsilon)
      else
	eqn.SL0[j-1] -= complex(0, epsilon) # undo previous iteration pertubation
	eqn.SL0[j] += complex(0, epsilon)
      end

      # evaluate residual
      fill!(eqn.SL, zero(Tsol))
      func(mesh, sbp, eqn, opts, eqn.SL0, eqn.SL)
 #     println("column ", j, " of jacobian, SL = ", eqn.SL)
      calcJacRow(unsafe_view(jac, :, j), eqn.SL, epsilon)
#      println("SL norm = ", norm(SL)/m)
      
    end  # end loop over rows of jacobian

#    println("first row of jacobian is: ")
#    for j=1:m
#      println(j, "   ", jac[1,i])
#    end

#    @bp
    # now jac is complete

    fname = string("jacobian", i, ".dat")
    printMatrix(fname, jac)
    println("finished printing jacobian")

    cond_j = cond(jac)
    println("Condition number of jacobian = ", cond_j)


    delta_SL[:] = jac\(-res_0)  #  calculate Newton update
    eqn.SL0[:] += step_fac*delta_SL  # update SL0

    step_norm = norm(delta_SL)/m


#    println("delta_SL = ", delta_SL)
#=
    println("delta_sl = ")
    for i=1:m
      println(i, "   ", delta_SL[i])
    end
=#
    println("step_norm = ", step_norm)
#    println("jac = ", jac)

    print("\n")

    # check stopping criteria
    if (step_norm < step_tol)
      println("Newton iteration converged with step_norm = ", step_norm)

      # compute residual at final SL0
      func(mesh, sbp, eqn, eqn.SL0, eqn.SL)
      # do some cleanup here to provide real residual?
      return nothing
    end

    # adjust step size limiter
    if (step_norm < step_norm_1)  # decreasing step size
      step_fac *= 1.2

      if step_fac > 1.0
	step_fac = 1.0
      end
    end

#    if (step_norm > step_norm_1)
#      step_fac /= 1.1
#    end


    step_norm_1 = step_norm
  end  # end loop over newton iterations

  println("Warning: Newton iteration did not converge in ", itermax, " iterations")
  println("  Final step size: ", step_norm)
  println("  Final residual: ", res_0_norm)
  return nothing
end



function calcJacRow{T <: Complex}(jac_row, res::AbstractArray{T, 1}, epsilon)
# calculate a row of the jacobian from res_0, the function evaluated 
# at the original point, and res, the function evaluated at a perturbed point

m = length(res)

for i=1:m
  jac_row[i] = imag(res[i])/epsilon
end

return nothing

end

