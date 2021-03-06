
@doc """
### NavierStokesMod.calcElemFurfaceArea
This function calculates the wet area of each element. A weight of 2 is given to
faces with Dirichlet boundary conditions.
Arguments:
mesh: AbstractMesh
sbp: SBP operator
eqn: an implementation of NSData. Does not have to be fully initialized.
"""->
# used by NSData Constructor
function calcElemSurfaceArea(mesh::AbstractMesh{Tmsh},
                             sbp::AbstractOperator,
                             eqn::NSData{Tsol, Tres, Tdim}) where {Tmsh, Tsol, Tres, Tdim}
  nfaces = length(mesh.interfaces)
  nrm = zeros(Tmsh, Tdim, mesh.numNodesPerFace)
  area = zeros(Tmsh, mesh.numNodesPerFace)
  face_area = zero(Tmsh)
  sbpface = mesh.sbpface

  #
  # Compute the wet area of each element
  #
  for f = 1:nfaces
    face = mesh.interfaces[f]
    eL = face.elementL
    eR = face.elementR
    fL = face.faceL
    fR = face.faceR
    #
    # Compute the size of face
    face_area = 0.0
    
    for n = 1 : mesh.numNodesPerFace
      nrm_xy = ro_sview(mesh.nrm_face, :, n, f)
      area[n] = norm(nrm_xy)
      face_area += sbpface.wface[n]*area[n]
    end

    eqn.area_sum[eL] += face_area
    eqn.area_sum[eR] += face_area
  end

  for bc = 1 : mesh.numBC
    indx0 = mesh.bndry_offsets[bc]
    indx1 = mesh.bndry_offsets[bc+1] - 1

    for f = indx0 : indx1
      face = mesh.bndryfaces[f].face
      elem = mesh.bndryfaces[f].element

      # Compute the size of face
      face_area = 0.0
      for n=1:mesh.numNodesPerFace
        nrm_xy = ro_sview(mesh.nrm_bndry, :, n, f)
        area[n] = norm(nrm_xy)
        face_area += sbpface.wface[n]*area[n]
      end
      eqn.area_sum[elem] += 2.0*face_area
    end
  end
  return nothing
end




@doc """

Compute the constant coefficent in inverse trace ineqality, i.e.,
the largest eigenvalue of 
B^{1/2} R H^{-1} R^{T} B^{1/2}

Input:
  sbp
Output:
  cont_tii
"""->

function calcTraceInverseInequalityConst(sbp::AbstractOperator{Tsbp},
                                         sbpface::AbstractFace{Tsbp}) where Tsbp
  R = sview(sbpface.interp, :,:)
  BsqrtRHinvRtBsqrt = Array{Tsbp}(sbpface.numnodes, sbpface.numnodes)
  perm = zeros(Tsbp, sbp.numnodes, sbpface.stencilsize)
  Hinv = zeros(Tsbp, sbp.numnodes, sbp.numnodes)
  Bsqrt = zeros(Tsbp, sbpface.numnodes, sbpface.numnodes)
  for s = 1:sbpface.stencilsize
    perm[sbpface.perm[s, 1], s] = 1.0
  end
  for i = 1:sbp.numnodes
    Hinv[i,i] = 1.0/sbp.w[i]
  end
  for i = 1:sbpface.numnodes
    Bsqrt[i,i] = sqrt(sbpface.wface[i])
  end

  BsqrtRHinvRtBsqrt = Bsqrt*R.'*perm.'*Hinv*perm*R*Bsqrt 
  const_tii = eigmax(BsqrtRHinvRtBsqrt)

  return const_tii

end


@doc """

Compute derivative operators

Input:
  mesh
  sbp
  dxidx : derivatives of mapping, i.e., Jacobian matrix
  jac   : determinant of Jacobian

Input/Output:
  Dx    : derivative operators in physical domain, incling Dx, Dy
"""->
function calcDx(sbp::AbstractOperator,
                dxidx::AbstractArray{Tmsh, 3},
                jac::AbstractArray{Tmsh, 1},
                Dx::AbstractArray{Tmsh, 3}) where Tmsh
  @assert(size(Dx, 1) == sbp.numnodes)
  @assert(size(Dx, 1) == size(dxidx, 3))
  @assert(size(Dx, 2) == size(Dx, 1))
  @assert(size(Dx, 3) == size(dxidx, 1))

  Dx[:,:,:] = 0.0
  dim = size(Dx, 3)
  numNodes = sbp.numnodes

  for d=1:dim            # loop over direction in which derivative is computing
    for dd=1:dim
      for n1 = 1:numNodes
        for n2 = 1:numNodes
          # Since dxidx is scaled by 1/|J|, we need to get it back,
          # that's why jac is here
          Dx[n1, n2, d] += dxidx[dd, d, n1]*jac[n1]*sbp.Q[n1, n2, dd]
        end
      end
    end

    # Until here Dx stores Qx, we need to left multiply H^(-1)
    for n2=1:numNodes
      for n1 = 1:numNodes
        Dx[n1, n2, d] /= sbp.w[n1]
      end
    end
  end
  return nothing
end

@doc """

Compute derivative operators

Input:
  mesh
  sbp
  elem    : index of element of which we are computing the derivatives

Input/Output:
  Dx    : derivative operators in physical domain, incling Dx, Dy
"""->
function calcDx(mesh::AbstractMesh{Tmsh},
                sbp::AbstractOperator,
                elem::Integer,
                Dx::AbstractArray{Tmsh, 3}) where Tmsh
  @assert(size(Dx, 1) == mesh.numNodesPerElement)
  @assert(size(Dx, 2) == mesh.numNodesPerElement)
  @assert(size(Dx, 3) == size(mesh.dxidx, 1))
  dxidx = sview(mesh.dxidx, :,:,:,elem) # (dim, dim, numNodesPerElement)
  jac = sview(mesh.jac, :, elem)
  dim = size(Dx, 3)

  for i = 1 : length(Dx)
    Dx[i] = 0.0
  end

  for d = 1 : dim            # loop over direction in which derivative is computing
    for dd = 1 : dim
      for n1 = 1 : mesh.numNodesPerElement
        for n2 = 1 : mesh.numNodesPerElement
          # Since dxidx is scaled by 1/|J|, we need to get it back,
          # that's why jac is here
          Dx[n1, n2, d] += dxidx[dd, d, n1] * jac[n1] * sbp.Q[n1, n2, dd]
        end
      end
    end

    # Until here Dx stores Qx, we need to left multiply H^(-1)
    for n2=1:mesh.numNodesPerElement
      for n1 = 1:mesh.numNodesPerElement
        Dx[n1, n2, d] /= sbp.w[n1]
      end
    end
  end

  return nothing
end

function calcQx(mesh::AbstractMesh{Tmsh},
                sbp::AbstractOperator,
                elem::Integer,
                Qx::AbstractArray{Tmsh, 3}) where Tmsh
  @assert(size(Qx, 1) == mesh.numNodesPerElement)
  @assert(size(Qx, 2) == mesh.numNodesPerElement)
  @assert(size(Qx, 3) == size(mesh.dxidx, 1))

  dxidx = sview(mesh.dxidx, :,:,:,elem) # (dim, dim, numNodesPerElement)
  jac = mesh.jac[:, elem]
  fill!(Qx, 0.0)
  dim = size(Qx, 3)

  for d = 1 : dim
    for dd = 1 : dim
      for l=1:mesh.numNodesPerElement
        # Since dxidx is scaled by 1/|J|, we need to get it back,
        # that's why jac is here
        for m = 1:mesh.numNodesPerElement
          Qx[l,m,d] += dxidx[dd,d,l] * jac[l] * sbp.Q[l,m,dd]
        end
      end
    end
  end
end

@doc """

Given variables q at element nodes, compute corresponding gradients

Input:
  sbp      : sbp operator
  dxidx    : derivatives of mapping, i.e., jacobian matrix
  jac      : determinant of jacobian
  q        : element node value
  q_grad   : gradient of q
Output:
  nothing
"""->
function calcGradient(sbp::AbstractOperator{Tsbp},
                      dxidx::AbstractArray{Tmsh, 3},
                      jac::AbstractArray{Tmsh, 1},
                      q::AbstractArray{Tsol, 2},
                      q_grad::AbstractArray{Tsol, 3}) where {Tmsh, Tsol, Tsbp}
  @assert(size(q, 2) == sbp.numnodes)

  @assert(size(dxidx, 1) == size(dxidx, 2))
  @assert(size(q_grad, 1) == size(dxidx, 1))
  @assert(size(q_grad, 2) == size(q, 1))
  @assert(size(q_grad, 3) == sbp.numnodes)

  numNodes = sbp.numnodes
  numDofs = size(q, 1)
  dim = size(q_grad, 1)

  Dx = Array{Tsbp}(numNodes, numNodes, dim)

  calcDx(sbp, dxidx, jac, Dx)

  for i = 1 : length(q_grad)
    q_grad[i] = 0.0
  end

  for n=1:numNodes
    for iDof=1:numDofs
      for d=1:dim
        for col=1:numNodes
          q_grad[d, iDof, n] += Dx[n,col,d] * q[iDof, col]
        end
      end
    end
  end
  return nothing
end

@doc """

Given variables q at element nodes, compute corresponding gradients

Input:
	mesh:
	sbp:
	q      : element node value
	elem   : index of element
Output :
	q_grad : (in/out) gradient of q
"""->
function calcGradient(mesh::AbstractDGMesh{Tmsh},
                      sbp::AbstractOperator{Tsbp},
                      elem::Integer,
                      q::AbstractArray{Tsol, 2},
                      q_grad::AbstractArray{Tsol, 3}) where {Tmsh, Tsol, Tsbp}
  @assert(size(q, 2) == mesh.numNodesPerElement)
  @assert(size(q, 1) == mesh.numDofPerNode)

  @assert(size(q_grad, 1) == size(mesh.coords, 1))
  @assert(size(q_grad, 3) == mesh.numNodesPerElement)
  @assert(size(q_grad, 2) == mesh.numDofPerNode)

  numNodes = mesh.numNodesPerElement
  numDofs = mesh.numDofPerNode
  dim = size(q_grad, 1)

  Dx = Array{Tsbp}(numNodes, numNodes, dim)
  # for e=1:numElems
  # First compute Dx for this element
  calcDx(mesh, sbp, elem, Dx)

  q_grad[:,:,:] = 0.0

  for n=1:numNodes
    for iDof=1:numDofs
      for d=1:dim
        for col=1:numNodes
          q_grad[d, iDof, n] += Dx[n,col,d]*q[iDof, col]
        end
      end
    end
  end
  return nothing
end

@doc """
Another(single face) version of interiorfaceintegrate.
Given Q on element L and element R, interpolate Q to interface shared by L and R

Input:
  sbpface     : face SBP operator
  face        : the interface which we are interpolating Q onto
  qvolL       : Q at nodes in element L, qvolL(idof, iNode)    
  qvolR       : Q at nodes in element R    
Output:
  qface       : Q at nodes on interface, qface(idof, L/R, ifacenode)

function call examples
"""->
function interiorfaceinterpolate(sbpface::AbstractFace{Tsbp},
                                 face::Interface,
                                 qvolL::AbstractArray{Tsol, 2},
                                 qvolR::AbstractArray{Tsol, 2},
                                 qface::AbstractArray{Tsol, 3}) where {Tsbp, Tsol}
  @assert(size(qvolR, 1) == size(qvolL, 1))
  @assert(size(qvolR, 2) == size(qvolL, 2))
  @assert(size(qvolR, 1) == size(qface, 1))
  @assert(size(sbpface.interp, 1) <= size(qvolL, 2))
  @assert(size(sbpface.interp, 2) == size(qface, 3))

  numDofs = size(qvolL, 1)    

  for n = 1 : sbpface.numnodes
    iR = sbpface.nbrperm[n, face.orient]

    for dof = 1 : numDofs
      qface[dof, 1, n] = zero(Tsol)
      qface[dof, 2, n] = zero(Tsol)
    end

    for j = 1 : sbpface.stencilsize
      permL = sbpface.perm[j, face.faceL]
      permR = sbpface.perm[j, face.faceR]

      for dof = 1 : numDofs
        qface[dof, 1, n] += sbpface.interp[j, n] * qvolL[dof, permL]
        qface[dof, 2, n] += sbpface.interp[j, iR]* qvolR[dof, permR]
      end
    end
  end

  return nothing
end

@doc """
Another version of boundaryinterpolate.
Given Q on the parent element, interpolate Q to boundary face owned by parent element

Input:
  sbpface     : face SBP operator
  bndface     : the interface which we are interpolating Q onto
  qvol        : Q at nodes in element L, qvolL(idof, iNode)    
Output:
  qface       : Q at nodes on interface, qface(idof, L/R, ifacenode)

"""->
function boundaryinterpolate(sbpface::AbstractFace{Tsbp},
                             bndface::Boundary,
                             qvol::AbstractArray{Tsol, 2},
                             qface::AbstractArray{Tsol, 2}) where {Tsbp, Tsol}

  @assert(size(qvol, 1) == size(qface, 1))            # dof
  @assert(size(qface,2) == sbpface.numnodes)
  @assert(size(sbpface.interp, 1) <= size(qvol, 2))    # stencilsize <= numNodesPerElem
  @assert(size(sbpface.interp, 2) == size(qface, 2))    # check number of face nodes

  numDofs = size(qvol, 1)    

  for n = 1 : sbpface.numnodes
    for dof = 1 : numDofs
      qface[dof, n] = zero(Tsol)
    end

    for j = 1 : sbpface.stencilsize
      perm = sbpface.perm[j, bndface.face]
      for dof = 1 : numDofs
        qface[dof, n] += sbpface.interp[j, n]*qvol[dof, perm]
      end
    end
  end
end

