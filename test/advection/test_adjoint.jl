# test boundary forces
@doc """
Advection Equation -- test_adjoint

The function tests for the correctness functional
computation and then tests if the adjoint vector is being computed correctly.
This is a serial test and uses the input file called

`input_vals_functional_DG.jl`

"""->
function test_adjoint()
  #= TODO: Uncomment when CG meshes support mesh.bndry_geo_nums

  facts("--- Testing Boundary Functional Computation on CG Mesh ---") do
    clean_dict(arg_dict)
    ARGS[1] = "input_vals_functional_CG.jl"
    include("../../src/solver/advection/startup_advection.jl")  # initialization and construction
    println("use_DG = ", arg_dict["use_DG"])


    @fact mesh.isDG --> false
    @fact opts["functional_name1"] --> "qflux"
    @fact opts["analytical_functional_val"] --> roughly(2*(exp(1) - 1), atol=1e-12)
    @fact opts["geom_edges_functional1"] --> [2,3]

    fname = "./functional_error1.dat"
    error = readdlm(fname)

    @fact error[1] --> roughly(0.0060826244541961885, atol=1e-6)

    rm("./functional_error1.dat") # Delete the file
  end
  =#

  facts("--- Testing Boundary Functional & Adjoint Computation On DG Mesh ---") do

    ARGS[1] = "input_vals_functional_DG.jl"
    mesh, sbp, eqn, opts, pmesh = createObjects(ARGS[1])

    @assert mesh.isDG == true
    @assert opts["jac_method"] == 2
    @assert opts["run_type"] == 5

    functional = createFunctional(mesh, sbp, eqn,
                                  opts, opts["num_functionals"])


    context("Checking Functional Object Creation") do

      @fact functional.bcnums --> [2,3]
      @fact functional.val --> zero(Complex{Float64})
      @fact functional.target_qflux --> zero(Complex{Float64})

    end # End context("Checking Functional Object Creation")

    solvePDE(mesh, sbp, eqn, opts, pmesh)
    evalFunctional(mesh, sbp, eqn, opts, functional)

    context("Checking Functional Computation") do

      analytical_val = 3.0
      functional_error = norm(real(functional.val) - analytical_val,2)
      @fact functional_error --> roughly(0.0, atol=1e-12)

      # test another functional
      func = AdvectionEquationMod.IntegralQDataConstructor(Complex128, mesh, sbp, eqn, opts, opts["functional_bcs1"])
      AdvectionEquationMod.calcBndryFunctional(mesh, sbp, eqn, opts, func)
      @fact func.val --> roughly(analytical_val, atol=1e-13)


    end # End context("Checking Functional Computation")

    context("Checking Adjoint Computation on DG mesh") do

      adjoint_vec = zeros(Complex{Float64}, mesh.numDof)
      pc, lo = getNewtonPCandLO(mesh, sbp, eqn, opts)
      ls = StandardLinearSolver(pc, lo, eqn.comm, opts)
      calcAdjoint(mesh, sbp, eqn, opts, ls, functional, adjoint_vec, recalc_jac=true, recalc_pc=true)

      for i = 1:length(adjoint_vec)
        @fact real(adjoint_vec[i]) --> roughly(1.0 , atol=1e-10)
      end

    end # End context("Checking Adjoint Computation on DG mesh")

  end # End facts("--- Testing Boundary Functional Computation On DG Mesh ---")

end # End function test_adjoint

add_func1!(AdvectionTests, test_adjoint, [TAG_ADJOINT, TAG_SHORTTEST])
