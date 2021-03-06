# run 2 processor tests

push!(LOAD_PATH, abspath(joinpath(pwd(), "..")))

using PDESolver
#using Base.Test
using Base.Test
using ODLCommonTools
using PdePumiInterface  # common mesh interface - pumi
using SummationByParts  # SBP operators
using AdvectionEquationMod
using LinearSolvers
using NonlinearSolvers   # non-linear solvers
using OptimizationInterface
using ArrayViews
import ArrayViews.view
using Utils
using Input

#------------------------------------------------------------------------------
# define tests and tags

#include("../TestSystem.jl")
using TestSystem
# define tags that will be used
include("../tags.jl")

# test list
global const AdvectionTests = TestList()


"""
  Run parallel tests and compare to serial results calculated as part of
  serial tests.
"""
function runtests_parallel()
  @testset "----- Testing Parallel -----" begin

    start_dir = pwd()
    cd("./rk4/parallel")
    fname = "input_vals_parallel_runp.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)

    datas = readdlm("../serial/error_calc.dat")
    datap = readdlm("error_calc.dat")

    @test isapprox( datas[1], datap[1]) atol=1e-13
    @test isapprox( datas[2], datap[2]) atol=1e-13
    cd("../../")

    cd("./newton/parallel")
    fname = "input_vals_parallel.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)

    datas = readdlm("../serial/error_calc.dat")
    datap = readdlm("./error_calc.dat")
    @test isapprox( datas[1], datap[1]) atol=1e-13

    cd(start_dir)

    cd("./rk4_3d/parallel")
    fname = "input_vals_parallel.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)

    datas = readdlm("../serial/error_calc.dat")
    datap = readdlm("error_calc.dat")
    @test isapprox( datas[1], datap[1]) atol=1e-13

    cd(start_dir)

    cd("./newton_3d/parallel")
    fname = "input_vals_parallel.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)
    datas = readdlm("../serial/error_calc.dat")
    datap = readdlm("error_calc.dat")
    @test isapprox( datas[1], datap[1]) atol=1e-13

    cd(start_dir)
  end  # end facts block

  return nothing
end

#runtests_parallel()
add_func1!(AdvectionTests, runtests_parallel, [TAG_SHORTTEST])

function test_precompute()
  @testset "----- testing non-precompute functions -----" begin
    start_dir = pwd()

    # test rk4
    cd("./rk4/parallel")
    fname = "input_vals_parallel_runp.jl"
    #TODO: set opts["solve"] = false before doing this
    mesh, sbp, eqn, opts = solvePDE(fname)

    fill!(eqn.res, 0.0)
    evalResidual(mesh, sbp, eqn, opts)

    res_orig = copy(eqn.res)

    opts["precompute_face_flux"] = false
    evalResidual(mesh, sbp, eqn, opts)

    @test isapprox( norm(vec(eqn.res - res_orig)), 0.0) atol=1e-13

    # test newton
    cd(start_dir)
    cd("./newton/parallel")
    fname = "input_vals_parallel.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)

    fill!(eqn.res, 0.0)
    evalResidual(mesh, sbp, eqn, opts)
    res_orig = copy(eqn.res)

    opts["precompute_face_flux"] = false
    evalResidual(mesh, sbp, eqn, opts)

    @test isapprox( norm(vec(eqn.res - res_orig)), 0.0) atol=1e-13

    cd(start_dir)
  end


  return nothing
end

add_func1!(AdvectionTests, test_precompute, [TAG_SHORTTEST])

function test_adjoint_parallel()

  @testset "--- Testing Adjoint Computation on a Geometric Boundary ---" begin

    fname = "input_vals_functional_DG_parallel.jl"
    mesh, sbp, eqn, opts = solvePDE(fname)

    objective = createFunctional(mesh, sbp, eqn, opts, 1)
    evalFunctional(mesh, sbp, eqn, opts, objective)
    pc, lo = getNewtonPCandLO(mesh, sbp, eqn, opts)
    ls = StandardLinearSolver(pc, lo, eqn.comm, opts)

    adjoint_vec = zeros(Complex{Float64}, mesh.numDof)
    calcAdjoint(mesh, sbp, eqn, opts, ls, objective, adjoint_vec, recalc_jac=true, recalc_pc=true)

    for i = 1:length(adjoint_vec)
      @test isapprox( real(adjoint_vec[i]), 1.0) atol=1e-10
    end
   
  end # End testset("--- Testing Functional Computation on a Geometric Boundary ---")

  return nothing
end

add_func1!(AdvectionTests, test_adjoint_parallel, [TAG_ADJOINT, TAG_LONGTEST])

#------------------------------------------------------------------------------
# run tests
@testset "----- Running Advection 2 processor tests -----" begin
  runTestSystem(AdvectionTests, solvePDE, ARGS)
end

#------------------------------------------------------------------------------
# cleanup
