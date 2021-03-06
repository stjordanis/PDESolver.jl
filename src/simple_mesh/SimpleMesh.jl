module SimpleMesh

include("SimpleMeshFunction2.jl")
include("../../../SummationByParts/src/SummationByParts.jl")

using SummationByParts

export simpleMesh

@doc """
### SimpleMesh

simpleMesh is a mesh type which generates a rectangular mesh in 2D with triangular elements. It has the following fields

**Fields**

*  `lengthx` : Length of domain on the X-axis
*  `lengthy` : Length of domain on the Y-axis
*  `nedx`    : Number of element edges along X-axis
*  `nedy`    : Number of element edges along Y-axis
*  `nnpe`    : Number of nodes per element edge (Same for all edges)
*  `order`   : Order of elements (linear, quadratic, cubic etc.)
*  `numNodes`  : Number of nodal points
*  `numVert`   : Total number of vertices in the mesh
*  `numEdge    : Total number of edges in the mesh
*  `numEl`     : Number of elements mesh
*  `numDof`    : Total degrees of freedom in the system
*  `numDofPerNode` : number of DOFs per node. Can be thought of number of equations being solved at a node
*  `numNodesPerElement` : Number of nodes per element
*  `numBoundaryEdges`   : Number of element edges on the boundary
*  `dofs`     : Element information matrix.
*  `vtxCoord` : Location coordinates of the vertices
*  `elemEdgeLengthx` : Length of element edge along the X-axis
*  `elemEdgeLengthy` : Length of element edge along the Y-axis
*  `bndryfaces` : An array of boundaries lying on the grid. It is of the type Boundary
*  `interfaces` : An array of all interior edges on the grid. It is of the type Interface

"""->

mutable struct simpleMesh{T <: FloatingPoint}

  lengthx::FloatingPoint
  lengthy::FloatingPoint
  nedx::Int
  nedy::Int
  nnpe::Int
  order::Int
  numNodes::Int
  numVert::Int
  numEdge::Int
  numEl::Int
  numDof::Int
  numDofPerNode::Int
  numNodesPerElement::Int
  numBoundaryEdges::Int
  dofs::Array{Int}
  vtxCoord::Array{T}
  elemEdgeLengthx::FloatingPoint
  elemEdgeLengthy::FloatingPoint
  bndryfaces::Array{Boundary}
  interfaces::Array{Interface}

  # dofs::Array{Int,3} # Store dof numbers of solution array for speedy assembly

  # numBC::Int  # number of boundary conditions
  

  function simpleMesh{T <: FloatingPoint}(lengthx,lengthy,nedx,nedy,nnpe,numDofPerNode) where T <: FloatingPoint
  order = nnpe-1 # Calculate the mesh order

  # calculating the members of the type using functions
    (dofs,numNodes,numEl,numNodesPerElement) = createMesh(lengthx,lengthy,nedx,nedy,nnpe,numDofPerNode)

  numVert = (nedx+1)*(nedy+1)
  numDof = numNodes * numDofPerNode
  numBoundaryEdges = 2*(nedx+nedy)

  (vtxCoord, elemEdgeLengthx, elemEdgeLengthy) = vtxLocation(lengthx, lengthy, nedx, nedy, numEl)
        
    (bndryfaces, numEdge) = boundaryEdges(nedx, nedy, numEl)
    interfaces = interiorEdgeinfo(nedx,nedy,numEl)
  


  new(lengthx,lengthy,nedx,nedy,nnpe,order,numNodes,numVert,numEdge,numEl,
    numDof,numDofPerNode,numNodesPerElement,numBoundaryEdges,dofs,vtxCoord,
    elemEdgeLengthx,elemEdgeLengthy,bndryfaces,interfaces)

  end # Ends the function simpleMesh
end # Ends the type simpleMesh

end # Ends the module
