# test functional calculation

"""
  Tests for functional computations.  The input file loads a 2 element mesh,
  square, -1 to 1,
  with a uniform flow (ICRho1E2U3).  The functional calculation should be exact
  in this case, so we can test against an analytical value.  The entire
  boundary is on BC 1
"""
function test_functionals()

  @testset "Testing functionals" begin


  # test all functional derivatives
  opts = Dict{String, Any}(
    "physics" => "Euler",
    "operator_type" => "SBPOmega",
    "dimensions" => 2,
    "run_type" => 5,
    "jac_method" => 2,
    "jac_type" => 2,
    "order" => 1,
    "IC_name" => "ICIsentropicVortex",
    "use_DG" => true,
    "volume_integral_type" => 2,
    "Volume_flux_name" => "IRFlux",
    "face_integral_type" => 2,
    "FaceElementIntegral_name" => "ESLFFaceIntegral",
    "Flux_name" => "IRFlux",
    "numBC" => 3,
    "BC1" => [0],
    "BC1_name" => "isentropicVortexBC",  # outlet
    "BC2" => [2],
    "BC2_name" => "isentropicVortexBC", # inlet
    "BC3" => [1, 3],
    "BC3_name" => "noPenetrationBC",  # was noPenetrationBC
    "aoa" => 0.0,
    "smb_name" => "SRCMESHES/vortex_3x3_.smb",
    "dmg_name" => ".null",
    "itermax" => 20,
    "res_abstol" => 1e-9,
    "res_reltol" => 1e-9,
    "do_postproc" => true,
    "exact_soln_func" => "ICIsentropicVortex",
    "force_solution_complex" => true,
    "force_mesh_complex" => true,
    "need_adjoint" => true,
    )

  # make second sets of 2D objects with Diagonal E (to test LPS)
  opts2 = copy(opts)
  opts2["operator_type"] = "SBPDiagonalE"
  delete!(opts2, "face_integral_type")
  delete!(opts2, "FaceElementIntegral_name")
  opts2["Flux_name"] = "IRSLFFlux"
  opts2["use_lps"] = true

  mesh, sbp, eqn, opts = solvePDE(opts)
  mesh2, sbp2, eqn2, opts2 = solvePDE(opts2)
  mesh3, sbp3, eqn3, opts3 = solvePDE("input_vals_jac3d.jl")

  testEntropyDissFunctional(mesh, sbp, eqn, opts)
  testEntropyDissFunctional2(mesh2, sbp2, eqn2, opts2)

  # test derivative of all functionals

  funcs_diage = ["negboundaryentropydiss", "entropydissipation", "negentropydissipation", "totalentropydissipation", "negtotalentropydissipation"]
  funcs_skip_zero = ["totalentropydissipation", "negtotalentropydissipation"]
  for funcname in keys(EulerEquationMod.FunctionalDict)
    println("testing functional ", funcname)
    obj = createFunctional(mesh, sbp, eqn, opts, funcname, [1, 3])
    if !(funcname in funcs_skip_zero) &&
        typeof(obj) <: EulerEquationMod.EntropyPenaltyFunctional ||
        funcname == "solutiondeviation"

      test_functional_zero(mesh, sbp, eqn, opts, obj)
    end

    test_functional_deriv_q(mesh, sbp, eqn, opts, obj, shock=true)

    if funcname in funcs_diage
      obj = createFunctional(mesh2, sbp2, eqn2, opts2, funcname, [1, 3])
      test_functional_deriv_q(mesh2, sbp2, eqn2, opts2, obj)
    end
  end


 
  func1 = createFunctional(mesh, sbp, eqn, opts, "massflow", [1, 3])
  func2 = createFunctional(mesh, sbp, eqn, opts, "lift", [1, 3])
  test_compositefunctional(mesh, sbp, eqn, opts, func1, func2)
 
  func1 = createFunctional(mesh, sbp, eqn, opts, "entropydissipation", [0])
  func2 = createFunctional(mesh, sbp, eqn, opts, "entropyjump", [0])
  test_compositefunctional(mesh, sbp, eqn, opts, func1, func2, test_revm=true)
 
#=
  obj = createFunctional(mesh3, sbp3, eqn3, opts3, "entropydissipation", [1])
  test_functional_zero(mesh3, sbp3, eqn3, opts3, obj)
  test_functional_deriv_q(mesh3, sbp3, eqn3, opts3, obj)
=#
  functional_revm_names = ["boundaryentropydiss",
                           "negboundaryentropydiss",
                           "entropydissipation",
                           "lpsdissipation",
                           "scdissipation",
                           "entropydissipation2",
                           "totalentropydissipation",
                           "negentropydissipation",
                           "neglpsdissipation",
                           "negscdissipation",
                           "negentropydissipation2",
                           "negtotalentropydissipation",
                           "lift", "liftCoefficient",
                           "drag", "dragCoefficient",
                           "solutiondeviation"]

  for funcname in functional_revm_names
    println("testing revm of functional ", funcname)
    
    obj = createFunctional(mesh, sbp, eqn, opts, funcname, [1, 3])
    test_functional_deriv_m(mesh, sbp, eqn, opts, obj)

    if funcname in funcs_diage
      obj = createFunctional(mesh2, sbp2, eqn2, opts2, funcname, [1, 3])
      test_functional_deriv_m(mesh2, sbp2, eqn2, opts2, obj)
    end

    obj3 = createFunctional(mesh3, sbp3, eqn3, opts3, funcname, [1])
    test_functional_deriv_m(mesh3, sbp3, eqn3, opts3, obj3, shock=true)
  end

  end  # end testset

  return nothing
end


"""
  Test the entropy dissipation functional.  This function is defined over all
  faces, rather than a boundary, so it is a bit special
"""
function testEntropyDissFunctional(mesh, sbp, eqn, _opts)

  opts = copy(_opts)
  opts2 = read_input_file("input_vals_channel.jl")
  opts2["Flux_name"] = "RoeFlux"
  opts2["use_DG"] = true
  opts2["solve"] = false

  mesh2, sbp2, eqn2, opts2 = solvePDE(opts2)

  obj = createFunctional(mesh2, sbp2, eqn2, opts2, "entropyflux", [1])
  val = evalFunctional(mesh2, sbp2, eqn2, opts2, obj)
  # the functional is u_i * U dot n_i, so for a constant field around a closed
  # curve it is zero
  @test isapprox(val, 0.0) atol=1e-13


  # compute the functional the regular way
  func = createFunctional(mesh, sbp, eqn, opts, "entropydissipation", Int[])
  J1 = evalFunctional(mesh, sbp, eqn, opts, func)

  # compute the functional using evalResidual
  opts["addVolumeIntegrals"] = false
  opts["addBoundaryIntegrals"] = false
  eqn.face_element_integral_func = EulerEquationMod.ELFPenaltyFaceIntegral(mesh, eqn)
  array3DTo1D(mesh, sbp, eqn, opts, eqn.res, eqn.res_vec)
  w_vec = copy(eqn.q_vec)
  EulerEquationMod.convertToIR(mesh, sbp, eqn, opts, w_vec)

  J2 = dot(w_vec, eqn.res_vec)

  @test isapprox(J1, J2) atol=1e-13

  return nothing
end

function testEntropyDissFunctional2(mesh, sbp, eqn, opts)

  # test that the two methods of computing the entropy dissipation give the
  # same answer
  # This depends on the eqn object using the IRSLF flux with diagonal E
  # operators

  func1 = createFunctional(mesh, sbp, eqn, opts, "entropydissipation", [1])
  func2 = createFunctional(mesh, sbp, eqn, opts, "entropydissipation2", [2])

  val1 = evalFunctional(mesh, sbp, eqn, opts, func1)
  val2 = evalFunctional(mesh, sbp, eqn, opts, func2)
  println("first functional value = ", val1)
  println("second functional value = ", val2)

  @test abs(val1 - val2) < 1e-13

  return nothing
end


"""
  Test that a constant state -> functional value = 0
"""
function test_functional_zero(mesh, sbp, eqn, opts, func)

  icfunc = EulerEquationMod.ICDict["ICRho1E2U3"]
  icfunc(mesh, sbp, eqn, opts, eqn.q_vec)
  array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)

  f = evalFunctional(mesh, sbp, eqn, opts, func)

  @test abs(f) < 1e-13

  return nothing
end


"""
  Test the derivative of a boundary functional wrt to q

  The eqn object must have been created with Tsol = Complex128 for this to work
"""
function test_functional_deriv_q(mesh, sbp, eqn, opts, func; shock=false)

  println("testing functional deriv q for functional ", typeof(func))
  h = 1e-20
  pert = Complex128(0, h)

  # use a spatially varying solution
  icfunc = EulerEquationMod.ICDict["ICRho1E2U3"]
  icfunc(mesh, sbp, eqn, opts, eqn.q_vec)
  eqn.q_vec .+= 0.01*rand(length(eqn.q_vec))
  if shock
    for i=1:div(mesh.numEl, 2)
      eqn.q[1, 1, i] += 1
    end
  end
  array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)

  q_dot = rand(size(eqn.q))
  q_bar = zeros(eqn.q)

  evalFunctionalDeriv_q(mesh, sbp, eqn, opts, func, q_bar)
  val = sum(q_bar .* q_dot)

  eqn.q_vec .+= pert*vec(q_dot)
  f = evalFunctional(mesh, sbp, eqn, opts, func)
  val2 = imag(f)/h
  eqn.q_vec .-= pert*vec(q_dot)

  println("val1 = ", val)
  println("val2 = ", val2)
  @test abs(val - val2) < 1e-12

  return nothing
end


function test_functional_deriv_m(mesh, sbp, eqn, opts, func; shock=false)

  h = 1e-20
  pert = Complex128(0, h)

  # use a spatially varying solution
  if mesh.dim == 3
    icfunc = EulerEquationMod.ICDict["ICExp"]
  else
    icfunc = EulerEquationMod.ICDict["ICIsentropicVortex"]
  end  
  icfunc(mesh, sbp, eqn, opts, eqn.q_vec)
  eqn.q_vec .+= 0.1*rand(length(eqn.q_vec))
  if shock
    for i=1:div(mesh.numEl, 2)
      eqn.q[1, 1, i] += 1
    end
  end
  array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)

  zeroBarArrays(mesh)
  func_bar = rand_realpart(mesh.numDof)

  dxidx_dot       = rand_realpart(size(mesh.dxidx))
  jac_dot         = rand_realpart(size(mesh.jac))
  nrm_bndry_dot   = rand_realpart(size(mesh.nrm_bndry))
  nrm_face_dot    = rand_realpart(size(mesh.nrm_face_bar))
  coords_bndry_dot = rand_realpart(size(mesh.coords_bndry))


  mesh.dxidx        .+= pert*dxidx_dot
  mesh.jac          .+= pert*jac_dot
  mesh.nrm_bndry    .+= pert*nrm_bndry_dot
  mesh.nrm_face     .+= pert*nrm_face_dot
  mesh.coords_bndry .+= pert*coords_bndry_dot

  val = evalFunctional(mesh, sbp, eqn, opts, func)
  println("functional value = ", val)
  val = imag(val/h)

  mesh.dxidx        .-= pert*dxidx_dot
  mesh.jac          .-= pert*jac_dot
  mesh.nrm_bndry    .-= pert*nrm_bndry_dot
  mesh.nrm_face     .-= pert*nrm_face_dot
  mesh.coords_bndry .-= pert*coords_bndry_dot


  evalFunctionalDeriv_m(mesh, sbp, eqn, opts, func)

  val2 = sum(mesh.dxidx_bar .* dxidx_dot)              +
         sum(mesh.jac_bar .* jac_dot)                  +
         sum(mesh.nrm_bndry_bar .* nrm_bndry_dot)      +
         sum(mesh.nrm_face_bar .* nrm_face_dot)        +
         sum(mesh.coords_bndry_bar .* coords_bndry_dot)

#  println("val = ", real(val))
#  println("val2 = ", real(val2))
#  println("max dxidx_bar = ", maximum(abs.(mesh.dxidx_bar)))
#  println("max jac_bar = ", maximum(abs.(mesh.jac_bar)))
#  println("max nrm_bndry_bar = ", maximum(abs.(mesh.nrm_bndry_bar)))
#  println("max nrm_face_bar = ", maximum(abs.(mesh.nrm_face_bar)))
#  println("max coords_bndry_bar = ", maximum(abs.(mesh.coords_bndry_bar)))
  @test abs(val - val2) < 1e-12

  # test val_bar != 1
  zeroBarArrays(mesh)
  evalFunctionalDeriv_m(mesh, sbp, eqn, opts, func, 2)

  val3 = sum(mesh.dxidx_bar .* dxidx_dot)              +
         sum(mesh.jac_bar .* jac_dot)                  +
         sum(mesh.nrm_bndry_bar .* nrm_bndry_dot)      +
         sum(mesh.nrm_face_bar .* nrm_face_dot)        +
         sum(mesh.coords_bndry_bar .* coords_bndry_dot)

  @test abs(val3 - 2*val2) < 1e-12


  # test accumulation
  evalFunctionalDeriv_m(mesh, sbp, eqn, opts, func, 2)

  val4 = sum(mesh.dxidx_bar .* dxidx_dot)              +
         sum(mesh.jac_bar .* jac_dot)                  +
         sum(mesh.nrm_bndry_bar .* nrm_bndry_dot)      +
         sum(mesh.nrm_face_bar .* nrm_face_dot)        +
         sum(mesh.coords_bndry_bar .* coords_bndry_dot)

  @test abs(val4 - 2*val3) < 1e-12

  return nothing
end


function test_compositefunctional(mesh, sbp, eqn, opts,
                      func1::AbstractFunctional, func2::AbstractFunctional;
                      test_revm=false)
  println("testing CompositeFunctional")

  icfunc = EulerEquationMod.ICDict["ICRho1E2U3"]
  icfunc(mesh, sbp, eqn, opts, eqn.q_vec)
  eqn.q_vec .+= 0.1*rand_realpart(length(eqn.q_vec))
  array1DTo3D(mesh, sbp, eqn, opts, eqn.q_vec, eqn.q)


  func3 = CompositeFunctional(func1, func2)
  J1 = evalFunctional(mesh, sbp, eqn, opts, func1)
  J2 = evalFunctional(mesh, sbp, eqn, opts, func2)
  J3 = evalFunctional(mesh, sbp, eqn, opts, func3)

  @test abs(J3 - (J1 + J2)) < 1e-13

  dJdq1 = zeros(eqn.q)
  dJdq2 = zeros(eqn.q)
  dJdq3 = zeros(eqn.q)

  evalFunctionalDeriv_q(mesh, sbp, eqn, opts, func1, dJdq1)
  evalFunctionalDeriv_q(mesh, sbp, eqn, opts, func2, dJdq2)
  evalFunctionalDeriv_q(mesh, sbp, eqn, opts, func3, dJdq3)

  @test maximum(abs.(dJdq3 - (dJdq1 + dJdq2))) < 1e-13

  if test_revm
    zeroBarArrays(mesh)
    evalFunctionalDeriv_m(mesh, sbp, eqn, opts, func1)
    evalFunctionalDeriv_m(mesh, sbp, eqn, opts, func2)

    dxidx_bar = copy(mesh.dxidx_bar)
    jac_bar = copy(mesh.jac_bar)
    nrm_face_bar = copy(mesh.nrm_face_bar)
    nrm_bndry_bar = copy(mesh.nrm_bndry_bar)
    coords_bndry_bar = copy(mesh.coords_bndry_bar)

    zeroBarArrays(mesh)
    evalFunctionalDeriv_m(mesh, sbp, eqn, opts, func3)

    @test maximum(abs.(mesh.dxidx_bar - dxidx_bar)) < 1e-13
    @test maximum(abs.(mesh.jac_bar - jac_bar)) < 1e-13
    @test maximum(abs.(mesh.nrm_face_bar - nrm_face_bar)) < 1e-13
    @test maximum(abs.(mesh.nrm_bndry_bar - nrm_bndry_bar)) < 1e-13
    @test maximum(abs.(mesh.coords_bndry_bar - coords_bndry_bar)) < 1e-13
  end
end

add_func1!(EulerTests, test_functionals, [TAG_FUNCTIONAL, TAG_SHORTTEST])
