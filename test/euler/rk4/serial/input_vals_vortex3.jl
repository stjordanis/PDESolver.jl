# this user supplied file creates a dictionary of arguments
# if a key is repeated, the last use of the key is used
# it is a little bit dangerous letting the user run arbitrary code
# as part of the solver
# now that this file is read inside a function, it is better encapsulated

arg_dict = Dict{String, Any}(
"physics" => "Euler",
"var1" => 1,
"var2" => "a",
"var3" => 3.5,
"var4" => [1,2,3],
"var3" => 4,
"run_type" => 1,
"jac_type" => 2,
"order" => 1,
"use_DG" => true,
"Flux_name" => "RoeFlux",
"IC_name" => "ICIsentropicVortex",
#"variable_type" => :entropy,
#"IC_name" => "ICFile",
#"ICfname" => "start.dat",
"Relfunc_name" => "ICRho1E2U3",
"numBC" => 1,
"BC1" => [ 0, 1, 2, 3],
"BC1_name" => "isentropicVortexBC",
#"BC2" => [4, 10],
#"BC2_name" => "noPenetrationBC",
#"BC2_name" => "isentropicVortexBC",
"delta_t" => 0.1,
"t_max" => 500.000,
"smb_name" => "SRCMESHES/serial2.smb",
#"dmg_name" => "/users/creanj/fasttmp/meshfiles/psquare4_1_.dmg",
"dmg_name" => ".null",
"res_abstol" => 1e-10,
"res_reltol" => 1e-10,
"step_tol" => 1e-10,
"itermax" => 12000,
"output_freq" => 100,
#"calc_error" => true,
#"calc_error_infname" => "solution_final.dat",
#"writeq" => true,
#"perturb_ic" => true,
#"perturb_mag" => 0.001,
#"write_sparsity" => true,
#"write_jac" => true,
#"write_edge_vertnums" => true,
#"write_face_vertnums" => true,
#"write_qic" => true,
#"writeboundary" => true,
#"write_res" => true,
"write_counts" => true,
"write_rhs" => false,
"do_postproc" => true,
"checkpoint" => true,
"exact_soln_func" => "ICIsentropicVortex",
"use_checkpointing" => true,
"solve" => true,
)
