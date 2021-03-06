# tests for the global system jacobian

"""
  Compare finite difference and complex step jacobians
"""
function test_jac_res()
# check that finite differencing and complex stepping the residual agree

  @testset "----- Testing Jacobian -----" begin
    fname = "input_vals_8el.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)

    jac_fd = zeros(Float64, 3, 3, mesh.numEl)
    for el = 1:mesh.numEl
      println("----- Doing Finite Differences -----")
  #    jac_fd = zeros(Float64, 3,3)
      eps_fd = 1e-7
      # calculate jacobian of the first element

      fill!(eqn.res, 0.0)
      AdvectionEquationMod.evalResidual(mesh, sbp, eqn, opts)
      res_0 = copy(reshape(eqn.res[1, :, el], 3))
      for i=1:3
        eqn.q[1, i, el] += eps_fd
        fill!(eqn.res, 0.0)
        AdvectionEquationMod.evalResidual(mesh, sbp, eqn, opts)
        res_i = reshape(eqn.res[1, :, el], 3)
        for j=1:3
          jac_fd[j, i, el] = (res_i[j] - res_0[j])/eps_fd
        end

        #undo perturbation
        eqn.q[1, i, el] -= eps_fd
      end
    end

    # now do complex step
    println("----- Doing Complex step -----")
    include(fname)
    arg_dict["jac_method"] = 2
    f = open("input_vals_8elc.jl", "w")
    println(f, arg_dict)
    close(f)
    fname = "input_vals_8elc.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)


    jac_c = zeros(Float64, 3,3, mesh.numEl)
    eps_c = complex(0, 1e-20)
    for el=1:mesh.numEl
      for i=1:3
        eqn.q[1, i, el] += eps_c
        fill!(eqn.res, 0.0)
        AdvectionEquationMod.evalResidual(mesh, sbp, eqn, opts)
        res_i = reshape(eqn.res[1, :, el], 3)
        for j=1:3
          jac_c[j, i, el] = imag(res_i[j])/abs(eps_c)
        end

        #undo perturbation
        eqn.q[1, i, el] -= eps_c
      end

      @test isapprox( jac_c[:, :, el], jac_fd[:, :, el]) atol=1e-6
    end

    @test isapprox( jac_c, jac_fd) atol=1e-6

    # back to finite differences
    println("----- Testing Finite Difference Jacobian -----")
    fname = "input_vals_8el.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)
    array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)

    # needed for calls to NewtonData below
    Tsol = eltype(eqn.q)
    Tres = eltype(eqn.res)

    # now test full jacobian
    fill!(eqn.res, 0.0)
    AdvectionEquationMod.evalResidual(mesh, sbp, eqn, opts)
    array3DTo1D(mesh, sbp, eqn, opts, eqn.res, eqn.res_vec)
    res_3d0 = copy(eqn.res)
    res_0 = copy(eqn.res_vec)
    jac = zeros(Float64, mesh.numDof, mesh.numDof)
    eps_fd = 1e-7
    fill!(eqn.res, 0.0)
    Jacobian.calcJacFD(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual, res_0, eps_fd, jac)

  #  jac_sparse = SparseMatrixCSC(mesh.sparsity_bounds, Float64)
    jac_sparse = SparseMatrixCSC(mesh.sparsity_bnds, Float64)
    println("create jac_sparse")
    fill!(eqn.res, 0.0)
    array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)
    Jacobian.calcJacobianSparse(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual, res_3d0, eps_fd, jac_sparse)

    jac_sparsefull = full(jac_sparse)
    jac_diff = jac - jac_sparsefull
    for i=1:mesh.numDof
      for j=1:mesh.numDof
        @test isapprox( abs(jac_diff[j, i]), 0.0) atol=1e-6
      end
    end

    # back to complex step
    println("----- Testing Complex Step Jacobian -----")
    fname = "input_vals_8elc.jl"
    arg_dict["jac_method"] = 2  # something screwy is going on because this is necessary
    mesh, sbp, eqn, opts = solvePDE(fname)
    array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)

    # now test full jacobian
    jac_c = zeros(Complex128, mesh.numDof, mesh.numDof)
    eps_c = complex(0, 1e-20)
    fill!(eqn.res, 0.0)
    Jacobian.calcJacobianComplex(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual, eps_c, jac_c)

  #  jac_csparse = SparseMatrixCSC(mesh.sparsity_bounds, Float64)
    jac_csparse = SparseMatrixCSC(mesh.sparsity_bnds, Float64)
    fill!(eqn.res, 0.0)
    res_3d0 = Array{Float64}(0, 0, 0)
    array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)
    Jacobian.calcJacobianSparse(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual, res_3d0, eps_c, jac_csparse)


    jac_csparsefull = full(jac_csparse)
    jac_diff = jac_c - jac_csparsefull
    for i=1:mesh.numDof
      for j=1:mesh.numDof
        @test isapprox( abs(jac_diff[j, i]), 0.0) atol=1e-12
      end
    end

  end  # end facts block

  return nothing
end

#test_jac_res()
add_func1!(AdvectionTests, test_jac_res, [TAG_SHORTTEST])

"""
  Test the various methods of calculating the jacobian
"""
function test_jac_calc()
  @testset "----- Testing Jacobian calculation -----" begin
    # back to finite differences
    println("----- Testing Finite Difference Jacobian -----")
    fname = "input_vals_8el.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)
    array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)

    # needed for calls to NewtonData below
    Tsol = eltype(eqn.q)
    Tres = eltype(eqn.res)

    # now test full jacobian
    fill!(eqn.res, 0.0)
    AdvectionEquationMod.evalResidual(mesh, sbp, eqn, opts)
    array3DTo1D(mesh, sbp, eqn, opts, eqn.res, eqn.res_vec)
    res_3d0 = copy(eqn.res)
    res_0 = copy(eqn.res_vec)
    jac = zeros(Float64, mesh.numDof, mesh.numDof)
    eps_fd = 1e-7
    fill!(eqn.res, 0.0)
    Jacobian.calcJacFD(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual, res_0, eps_fd, jac)

  #  jac_sparse = SparseMatrixCSC(mesh.sparsity_bounds, Float64)
    jac_sparse = SparseMatrixCSC(mesh.sparsity_bnds, Float64)
    fill!(eqn.res, 0.0)
    array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)
    Jacobian.calcJacobianSparse(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual, res_3d0, eps_fd, jac_sparse)

    jac_sparsefull = full(jac_sparse)
    jac_diff = jac - jac_sparsefull
    for i=1:mesh.numDof
      for j=1:mesh.numDof
        @test isapprox( abs(jac_diff[j, i]), 0.0) atol=1e-6
      end
    end

    # back to complex step
    println("----- Testing Complex Step Jacobian -----")
    fname = "input_vals_8elc.jl"
    arg_dict["run_type"] = 5  # something screwy is going on because this is necessary
    arg_dict["jac_method"] = 2
    mesh, sbp, eqn, opts = solvePDE(fname)
    array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)

    # now test full jacobian
    jac_c = zeros(Complex128, mesh.numDof, mesh.numDof)
    eps_c = complex(0, 1e-20)
    fill!(eqn.res, 0.0)
    Jacobian.calcJacobianComplex(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual, eps_c, jac_c)

  #  jac_csparse = SparseMatrixCSC(mesh.sparsity_bounds, Float64)
    jac_csparse = SparseMatrixCSC(mesh.sparsity_bnds, Float64)
    fill!(eqn.res, 0.0)
    res_3d0 = Array{Float64}(0, 0, 0)
    array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)
    Jacobian.calcJacobianSparse(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual, res_3d0, eps_c, jac_csparse)


    jac_csparsefull = full(jac_csparse)
    jac_diff = jac_c - jac_csparsefull
    for i=1:mesh.numDof
      for j=1:mesh.numDof
        @test isapprox( abs(jac_diff[j, i]), 0.0) atol=1e-12
      end
    end


    # now check FD vs Complex step
    for i=1:mesh.numDof
      for j=1:mesh.numDof
        @test isapprox( abs(jac_c[i, j] - jac[i,j]), 0.0) atol=1e-6
      end
    end

  end  # end facts block

  return nothing
end

#test_jac_calc()
add_func1!(AdvectionTests, test_jac_calc, [TAG_SHORTTEST])
