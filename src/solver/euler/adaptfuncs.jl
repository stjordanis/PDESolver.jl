function func3{T}(entity_ptr, r_::Ptr{T}, h_::Ptr{T}, m_ptr, u_::Ptr{T})
# an anisotropic function
# populates h with the desired mesh size in all three dimension

#  println("entered func3")
  # load arrays from C pointers
  r = pointer_to_array(r_, (3,3))  # REMEMBER: r is transposed when it is passed back to C
#  println("r = \n", r)
  h = pointer_to_array(h_, 3)
#  println("h = \n", h)
  u = pointer_to_array(u_, 9)
#  println("u = \n", u)


  # get vertex coords
  coords = zeros(3,1)
  getVertCoords(entity_ptr, coords, 3, 1)
  x = coords[1]
  y = coords[2]
  z = coords[3]

  # use xyz frame
  r[1,1] = 1.0
  r[2,2] = 1.0
  r[3,3] = 1.0

#  println("in julia, r = ", r)

  # calculate derivative of rho here

  drho_dx = smoothHeavisideder(x)
  h[1] = abs(0.5/drho_dx)  # make mesh size proportional to 1/drho/dx (larger gradient -> smaller mesh)
     # 2 is an emperical things with weird units


  ubound = 0.50
  lbound = 0.001
  # upper and lower bounds
  if h[1] < lbound
    h[1] = lbound
  elseif h[1] > ubound
    h[1] = ubound
  end


#  h[1] = 0.5
  h[2] = h[1]
  h[3] = 2.0


  println("x = ", x, " h = ", h, " drho_dx = ", drho_dx)
return nothing
end

# smooth heaviside function
function smoothHeavisideder(x)
# calculate the value of the smooth heaviside function at a location x
# x0 is specified within this function

  x0 = 0
  L = 5
  k = 5

#  return (L/(1 + e^(-k*(x-x0))))
  return L*(2*k*e^(-2*k*x))/(e^(-2*k*x) +1 )^2
end



function shockRefine{T}(entity_ptr, r_::Ptr{T}, h_::Ptr{T}, m_ptr, f_ptr)
# an anisotropic function
# populates h with the desired mesh size in all three dimension
# f_ptr is a pointer to a solution field (apf::Field)

#  println("entered func3")
  # load arrays from C pointers
  r = pointer_to_array(r_, (3,3))  # REMEMBER: r is transposed when it is passed back to C
#  println("r = \n", r)
  h = pointer_to_array(h_, 3)
#  println("h = \n", h)


  # get vertex coords
  coords = zeros(3,1)
  getVertCoords(entity_ptr, coords, 3, 1)
  x = coords[1]
  y = coords[2]
  z = coords[3]

  # use xyz frame
  r[1,1] = 1.0
  r[2,2] = 1.0
  r[3,3] = 1.0

#  println("in julia, r = ", r)

  u_node = zeros(4)
  retrieveNodeSolution(f_ptr, entity_ptr, u_node)
  # calculate derivative of rho here

  drho_dx = u_node[1]  # rho  value
#  drho_dx = smoothHeavisideder(x)
  
  h[1] = abs(0.5/drho_dx)  # make mesh size proportional to 1/drho/dx (larger gradient -> smaller mesh)
     # 2 is an emperical things with weird units


  ubound = 0.50
  lbound = 0.001
  # upper and lower bounds
  if h[1] < lbound
    h[1] = lbound
  elseif h[1] > ubound
    h[1] = ubound
  end


#  h[1] = 0.5
  h[2] = h[1]
  h[3] = 2.0


  println("x = ", x, " h = ", h, " drho_dx = ", drho_dx)
return nothing
end

function shockRefine2{T}(entity_ptr, r_::Ptr{T}, h_::Ptr{T}, m_ptr, f_ptr, operator_ptr)
# an anisotropic function
# populates h with the desired mesh size in all three dimension
# f_ptr is a pointer to a solution field (apf::Field)
# operator_ptr = pointer to SBP operator

#  println("entered func3")
  # load arrays from C pointers
  r = pointer_to_array(r_, (3,3))  # REMEMBER: r is transposed when it is passed back to C
#  println("r = \n", r)
  h = pointer_to_array(h_, 3)
#  println("h = \n", h)

#  println("typeof(operator_ptr) = ", typeof(operator_ptr))
  println("operator_ptr = ", operator_ptr)
  sbp = unsafe_pointer_to_objref(operator_ptr)
#  sbp = unsafe_load(operator_ptr)
#  println("typeof(sbp) = ", typeof(sbp))
  println("sbp.numnodes = ", sbp.numnodes)
  # get vertex coords
  coords = zeros(3,1)
  getVertCoords(entity_ptr, coords, 3, 1)
  x = coords[1]
  y = coords[2]
  z = coords[3]

  # use xyz frame
  r[1,1] = 1.0
  r[2,2] = 1.0
  r[3,3] = 1.0

#  println("in julia, r = ", r)

  u_node = zeros(4,3)
  
  num_elements = countAdjacent(m_ptr, entity_ptr, 2)  # get adjacnet elements
  elements = getAdjacent(num_elements)

  # choose first element (arbitrary)
  el_ptr = elements[1]
  verts, tmp = getDownward(m_ptr, el_ptr, 0)

  # get coordinates
  coords = zeros(3,3)
  getFaceCoords(el_ptr, coords, 3, 3)
  x_coords = coords[1,:]

  # get solution for vertices
  u_vals = zeros(4,3)
  vert_index = 0
  for j=1:3  # get solution value of each node, figure out which vertex is original
    subarray = sub(u_vals, :, j)
    retrieveNodeSolution(f_ptr, verts[j], subarray)

    if (entity_ptr == verts[j])
      vert_index = j
    end
  end

  # find max diff
  x_vert = x_coords[vert_index]
  max_diff = [abs(x_coords[1] - x_vert), abs(x_coords[2] - x_vert), abs(x_coords[3] - x_vert)]
  p = sortperm(max_diff)  # sort in ascending order
  max_index = p[3]  # index of maximum difference in x_coords

  rho_1 = u_vals[1, vert_index]
  rho_2 = u_vals[1, max_index]
  x_max = x_coords[max_index]

  drho_dx = abs( (rho_1 - rho_2)/(x_vert - x_max))
#=
  u_singlenode = zeros(4)
  retrieveNodeSolution(f_ptr, entity_ptr, u_singlenode)
  # calculate derivative of rho here

  drho_dx = u_singlenode[1]  # rho  value
#  drho_dx = smoothHeavisideder(x)
=#

  h[1] = abs(0.25/drho_dx)  # make mesh size proportional to 1/drho/dx (larger gradient -> smaller mesh)
     # 2 is an emperical things with weird units


  ubound = 0.50
  lbound = 0.0001
  # upper and lower bounds
  if h[1] < lbound
    h[1] = lbound
  elseif h[1] > ubound
    h[1] = ubound
  end


#  h[1] = 0.5
  h[2] = h[1]
  h[3] = 2.0


  println("x = ", x, " h = ", h, " drho_dx = ", drho_dx)
return nothing
end


