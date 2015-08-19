# this user supplied file creates a dictionary of arguments
# if a key is repeated, the last use of the key is used
# it is a little bit dangerous letting the user run arbitrary code
# as part of the solver
# now that this file is read inside a function, it is better encapsulated

arg_dict = Dict{Any, Any} (
"var1" => 1,
"var2" => "a",
"var3" => 3.5,
"var4" => [1,2,3],
"var3" => 4,
"run_type" => 5,
"jac_type" => 2,
"order" => 3,
"IC_name" => "ICIsentropicVortex",
"numBC" => 2,
"BC1" => [ 7, 13],
"BC1_name" => "isentropicVortexBC",
"BC2" => [4, 10],
"BC2_name" => "noPenetrationBC",
#"BC2_name" => "isentropicVortexBC",
"delta_t" => 0.005,
"t_max" => 500000.000,
"smb_name" => "src/mesh_files/vortex.smb",
"dmg_name" => "src/mesh_files/vortex.dmg",
"res_tol" => 1e-10,
"step_tol" => 1e-10,
"itermax" => 30,
"edgestab_gamma" => -0.9,
"writeq" => true,
#"perturb_ic" => true,
#"perturb_mag" => 0.001,
#"write_sparsity" => true,
#"write_jac" => true,
"write_edge_vertnums" => true,
"write_face_vertnums" => true,
"write_qic" => true,
"writeboundary" => true,
"write_res" => true,
#"write_counts" => true,
"solve" => true,
)
