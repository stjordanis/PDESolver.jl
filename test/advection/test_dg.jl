# test advection discontinuous-Galerkin functions

global const test_dg_inputfile = "input_vals_channelDG.jl"

"""
  Test face flux for DG.
"""
function test_dg_flux(mesh, sbp, eqn, opts)
  facts("----- Testing DG Flux ------") do
    eqn.params.LFalpha = 1.0
    nrm_scaled = mesh.nrm_face[:, 1, 1]
    alpha = [eqn.params.alpha_x, eqn.params.alpha_y]
    alpha_n = sum(alpha.*nrm_scaled)
    qL = 1.0
    qR = 2.0
    flux_test = alpha_n*(qL + qR)/2

    flux_func = AdvectionEquationMod.FluxDict["LFFlux"]
    flux_code = flux_func(eqn.params, qL, qR, nrm_scaled)

    @fact flux_code --> roughly(flux_test, atol=1e-13)

    eqn.q_face[1, 1, :, 1] = 1.0
    eqn.q_face[1, 2, :, 1] = 2.0

    AdvectionEquationMod.calcFaceFlux(mesh, sbp, eqn, eqn.flux_func, mesh.interfaces, eqn.flux_face)

    for i=1:mesh.sbpface.numnodes
      @fact eqn.flux_face[1, i, 1] --> roughly(-flux_test, atol=1e-13)
    end

  end  # end facts block

  return nothing
end

#test_dg_flux(mesh, sbp, eqn, opts)
add_func2!(AdvectionTests, test_dg_flux, test_dg_inputfile, [TAG_FLUX, TAG_SHORTTEST])

"""
  Test boundary conditions for DG.
"""
function test_dg_bc(mesh, sbp, eqn, opts)
  facts("\n----- Testing DG Boundary Condition -----") do

    eqn.params.LFalpha = 1.0

    for i=1:mesh.sbpface.numnodes
      eqn.q_bndry[1, i, :] = 2.0
    end

    # test use of eqn.q_bndry for BC
    eqn.params.alpha_x = -1.0
    eqn.params.alpha_y = -1.0
    range_idx = 1:mesh.numBoundaryFaces
    AdvectionEquationMod.calcBoundaryFlux(mesh, sbp, eqn, mesh.bndry_funcs[1], range_idx, mesh.bndryfaces, eqn.bndryflux)

    val_code = 0.0
    for i=1:mesh.sbpface.numnodes
      val_code += mesh.sbpface.wface[i]*eqn.bndryflux[1, i, 1]
    end
    val_test = 4*eqn.q_bndry[1,1,1]*eqn.params.alpha_x
    @fact val_code --> roughly(val_test, atol=1e-13)


    # test use of the boundary condition value
    eqn.params.alpha_x = 1.0
    eqn.params.alpha_y = 1.0
    bndry_coords = mesh.coords_bndry[:, :, 1]

    AdvectionEquationMod.calcBoundaryFlux(mesh, sbp, eqn, mesh.bndry_funcs[1], range_idx, mesh.bndryfaces, eqn.bndryflux)
    val_code = 0.0
    for i=1:mesh.sbpface.numnodes
      val_code += mesh.sbpface.wface[i]*eqn.bndryflux[1, i, 1]
    end
    val_test = 12.0

    @fact val_code --> roughly(val_test, atol=1e-13)


    # check that the interpolation and coordinates match
    fill!(eqn.q_bndry, 0.0)
    AdvectionEquationMod.ICp1(mesh, sbp, eqn, opts, eqn.q_vec)
    mesh.bndry_funcs[1] = AdvectionEquationMod.BCDict["p1BC"]
    AdvectionEquationMod.evalBoundaryIntegrals(mesh, sbp, eqn, opts)

    for i=1:mesh.numBoundaryFaces
      for j=1:mesh.sbpface.numnodes
        coords = mesh.coords_bndry[:, j, i]
        q_test = AdvectionEquationMod.calc_p1(eqn.params, coords, 0.0)
        q_code = eqn.q_bndry[1, j, i]
        @fact q_code --> roughly(q_test, atol=1e-13)
      end
    end

  end  # end facts block

  return nothing
end  # end function

#test_dg_bc(mesh, sbp, eqn, opts)
add_func2!(AdvectionTests, test_dg_flux, test_dg_inputfile, [TAG_BC, TAG_SHORTTEST])

function test_precompute()
  mesh, sbp, eqn, opts = run_solver(test_dg_inputfile)

  facts("----- Testing non-precompute functions -----") do
    icfunc = AdvectionEquationMod.ICDict["ICexp_xplusy"]
    icfunc(mesh, sbp, eqn, opts, eqn.q_vec)
    calcResidual(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual)

    res_orig = copy(eqn.res)

    # test volume integrals
    fill!(eqn.res, 0.0)
    opts["precompute_volume_integrals"] = false
    calcResidual(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual)

    @fact norm(vec(res_orig - eqn.res)) --> roughly(0.0, atol=1e-13)

    # test face integrals
    fill!(eqn.res, 0.0)
    opts["precompute_face_integrals"] = false
    calcResidual(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual)

    @fact norm(vec(res_orig - eqn.res)) --> roughly(0.0, atol=1e-13)

    # test boundary integrals
    fill!(eqn.res, 0.0)
    opts["precompute_boundary_integrals"] = false
    calcResidual(mesh, sbp, eqn, opts, AdvectionEquationMod.evalResidual)

    @fact norm(vec(res_orig - eqn.res)) --> roughly(0.0, atol=1e-13)
  end

  return nothing
end

add_func1!(AdvectionTests, test_precompute, [TAG_SHORTTEST, TAG_TMP])