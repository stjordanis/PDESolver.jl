# shock capturing using Local-Discontinuous Galerkin

function calcShockCapturing(mesh::AbstractMesh, sbp::AbstractOperator,
                             eqn::EulerData, opts,
                             capture::LDGShockCapturing{Tsol, Tres},
                             shockmesh::ShockedElements) where {Tsol, Tres}

  # shockmesh should be updated before this function is called
  #TODO: need to get entropy variables conversion function from somewhere

  entropy_vars = capture.entropy_vars
  flux = capture.flux
  diffusion = capture.diffusion

  computeEntropyVariables(mesh, eqn, capture, shockmesh, entropy_vars)

  computeThetaVolumeContribution(mesh, sbp, eqn, opts, capture, shockmesh)
  #TODO: need to get flux_func from somewhere
  computeThetaFaceContribution(mesh, sbp, eqn, opts, capture, shockmesh, flux)
  # this needs to apply Minv too
  # TODO: need to get diffusion func that computes matrix-vector products
  #       with the Cji matrices
  computeQFromTheta(mesh, sbp, eqn, opts, capture, shockmesh, diffusion)

  # update the residual
  computeQVolumeTerm(mesh, sbp, eqn, opts, capture, shockmesh)
  # TODO: need to get flux_func_q from somewhere
  computeQFaceTerm(mesh, sbp, eqn, opts, capture, shockmesh, flux)

  return nothing
end


"""
  Gets the entropy variables at the volume nodes of the elements that have
  a shock in them and their neighbors.

  **Inputs**

   * eqn

  **Inputs/Outputs**

   * capture: an [`LDGShockCapturing`](@ref) object, `capture.w_el` is
              overwritten (and possibly re-allocated)
"""
function computeEntropyVariables(mesh, eqn, capture::LDGShockCapturing{Tsol, Tres},
                                 shockmesh::ShockedElements,
                                 entropy_vars::AbstractVariables
                                ) where {Tsol, Tres}

  @simd for i=1:shockmesh.numEl
    i_full = shockmesh.elnums_all[i]
    @simd for j=1:mesh.numNodesPerElement
      q_i = sview(eqn.q, :, j, i_full)
      w_i = sview(capture.w_el, :, j, i)
      convertToEntropy(entropy_vars, eqn.params, q_i, w_i)
    end
  end

  return nothing
end


#------------------------------------------------------------------------------
# Volume contribution to Theta

function computeThetaVolumeContribution(mesh, sbp, eqn, opts,
                capture::LDGShockCapturing{Tsol, Tres},
                shockmesh::ShockedElements)  where {Tsol, Tres}

  # q_j stores theta_j in this function
  fill!(capture.q_j, 0)

  # temporary storage
  wxi_i = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerElement, mesh.dim)
  op = SummationByParts.Subtract()

  for i=1:shockmesh.numShock
    i_full = shockmesh.elnums_all[i]
    w_i = ro_sview(capture.w_el, :, :, i)

    # compute Qx^T w
    dxidx_i = ro_sview(mesh.dxidx, :, :, :, i_full)
    theta_i = sview(capture.q_j, :, :, :, i)
    applyQxTransposed(sbp, w_i, dxidx_i,  wxi_i, theta_i, op)
  end

  return nothing
end


#------------------------------------------------------------------------------
# Face contribution to Theta



function computeThetaFaceContribution(mesh::AbstractMesh{Tmsh}, sbp, eqn, opts,
          capture::LDGShockCapturing{Tsol, Tres}, shockmesh::ShockedElements,
          flux::AbstractLDGFlux) where {Tsol, Tres, Tmsh}

  w_faceL = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerFace)
  w_faceR = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerFace)
  flux_j = zeros(Tres, mesh.numDofPerNode)
  fluxD = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerFace, mesh.dim)
  nrm = zeros(Tmsh, mesh.dim)
  aux_vars = Tres[]
  for i=1:shockmesh.numInterfaces
    iface_i = shockmesh.ifaces[i]
    iface_red = iface_i.iface  # iface in reduced numbering scheme
    iface_idx = shockmesh.ifaces[i].idx_orig
    wL = sview(capture.w_el, :, :, iface_red.elementL)
    wR = sview(capture.w_el, :, :, iface_red.elementR)

    # interpolate v to faces
    interiorFaceInterpolate!(mesh.sbpface, iface_red, wL, wR, w_faceL,
                             w_faceR)

    # apply flux function
    for j=1:mesh.numNodesPerFace
      wL_j = ro_sview(w_faceL, :, j)
      wR_j = ro_sview(w_faceR, :, j)

      # get the normalized unit vector
      for d=1:mesh.dim
        nrm[d] = mesh.nrm_face[d, j, iface_idx]
      end
      normalize_vec(eqn.params, nrm)

      applyFlux(eqn.params, flux, wL_j, wR_j, aux_vars, nrm, flux_j)
      
      # apply normal vector components here because SBP only applied R^T B
      for d=1:mesh.dim
        for k=1:mesh.numDofPerNode
          fluxD[k, j, d] = mesh.nrm_face[d, j, iface_idx]*flux_j[k]
        end
      end
    end  # end j

    # apply R^T B
    for d=1:mesh.dim
      flux_d = ro_sview(fluxD, :, :, d)
      resL = sview(capture.q_j, :, :, d, iface_red.elementL)
      resR = sview(capture.q_j, :, :, d, iface_red.elementR)
      interiorFaceIntegrate!(mesh.sbpface, iface_red, flux_d, resL, resR)
    end

  end  # end i

  return nothing
end


#------------------------------------------------------------------------------
# Computing q_j


function computeQFromTheta(mesh, sbp, eqn, opts,
                           capture::LDGShockCapturing{Tsol, Tres},
                           shockmesh::ShockedElements, diffusion_func) where {Tsol, Tres}

  # epsilon = 0 for neighbor elements, so q = 0 there, only do shocked elements
  theta_i = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerElement, mesh.dim)
  for i=1:shockmesh.numShock
    i_full = shockmesh.elnums_all[i]

    # this copy is unfortunate, but the alternative is allocating 2 q_j arrays.
    # also apply the inverse mass matrix
    @simd for d=1:mesh.dim
      @simd for j=1:mesh.numNodesPerElement
        val = mesh.jac[j, i_full]/sbp.w[j]
        @simd for k=1:mesh.numDofPerNode
          theta_i[k, j, d] = val*capture.q_j[k, j, d, i]
        end
      end
    end

    w_i = ro_sview(capture.w_el, :, :, i)
    q_i = sview(capture.q_j, :, :, :, i)
    applyDiffusionTensor(diffusion_func, w_i, i, theta_i, q_i)
  end

  # zero out the rest of q_i because epsilon is zero there
  q_neighbor = sview(capture.q_j, :, :, :, (shockmesh.numShock+1):shockmesh.numEl)
  fill!(q_neighbor, 0)
  return nothing
end



#------------------------------------------------------------------------------
# volume contribution to residual


function computeQVolumeTerm(mesh, sbp, eqn, opts, capture::LDGShockCapturing{Tsol, Tres},
                            shockmesh::ShockedElements) where {Tsol, Tres}

  op = SummationByParts.Subtract()
  qxi_i = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerElement, mesh.dim)
  for i=1:shockmesh.numShock
    i_full = shockmesh.elnums_all[i]
    # compute Qx^T q_x
    q_i = ro_sview(capture.q_j, :, :, :, i)
    dxidx_i = ro_sview(mesh.dxidx, :, :, :, i_full)
    res_i = sview(eqn.res, :, :, i_full)
    applyQxTransposed(sbp, q_i, dxidx_i,  qxi_i, res_i, op)
  end

  return nothing
end

#------------------------------------------------------------------------------
# face contribution to res




function computeQFaceTerm(mesh::AbstractMesh{Tmsh}, sbp, eqn, opts,
                          capture::LDGShockCapturing{Tsol, Tres},
                          shockmesh::ShockedElements, flux::AbstractLDGFlux
                         ) where {Tsol, Tres, Tmsh}

  w_faceL = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerFace)
  w_faceR = zeros(Tsol, mesh.numDofPerNode, mesh.numNodesPerFace)
  q_faceL = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerFace, mesh.dim)
  q_faceR = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerFace, mesh.dim)
  qL_j = zeros(Tres, mesh.numDofPerNode, mesh.dim)
  qR_j = zeros(Tres, mesh.numDofPerNode, mesh.dim)
  fluxD = zeros(Tres, mesh.numDofPerNode, mesh.dim)
  flux_scaled = zeros(Tres, mesh.numDofPerNode, mesh.numNodesPerFace)
  aux_vars = Tres[]
  nrm = zeros(Tmsh, mesh.dim)
  for i=1:shockmesh.numInterfaces
    iface_red = shockmesh.ifaces[i].iface
    idx_orig = shockmesh.ifaces[i].idx_orig

    # interpolate v to face
    wL = ro_sview(capture.w_el, :, :, iface_red.elementL)
    wR = ro_sview(capture.w_el, :, :, iface_red.elementR)
    interiorFaceInterpolate!(mesh.sbpface, iface_red, wL, wR, w_faceL,
                             w_faceR)

    # interpolate q_j to face
    for d=1:mesh.dim
      #TODO: make sure q_j has enough space, and is zeroed out, for all the
      #      neighbor elements
      qL = ro_sview(capture.q_j, :, :, d, iface_red.elementL)
      qR = ro_sview(capture.q_j, :, :, d, iface_red.elementR)
      q_faceL_d = sview(q_faceL, :, :, d)
      q_faceR_d = sview(q_faceR, :, :, d)
      interiorFaceInterpolate!(mesh.sbpface, iface_red, qL, qR, q_faceL_d,
                               q_faceR_d)
    end

    # apply flux function
    fill!(flux_scaled, 0)
    for j=1:mesh.numNodesPerFace
      wL_j = ro_sview(w_faceL, :, j)
      wR_j = ro_sview(w_faceR, :, j)
      # get q_j in all directions at this node
      # TODO: make type-stable strided view
      @simd for d=1:mesh.dim
        @simd for k=1:mesh.numDofPerNode
          qL_j[k, d] = q_faceL[k, j, d]
          qR_j[k, d] = q_faceR[k, j, d]
        end
      end

      # get the normalized unit vector
      for d=1:mesh.dim
        nrm[d] = mesh.nrm_face[d, j, idx_orig]
      end
      normalize_vec(eqn.params, nrm)

      applyFlux(eqn.params, flux, qL_j, qR_j, wL_j, wR_j, aux_vars, nrm, fluxD)
    
      # multiply by N because SBP doesn't, also do sum over dimensions
      @simd for d=1:mesh.dim
        N_d = mesh.nrm_face[d, j, idx_orig]
        @simd for k=1:mesh.numDofPerNode
          flux_scaled[k, j] += N_d*fluxD[k, d]
        end
      end

    end  # end j

    # apply R^T B
    resL = sview(eqn.res, :, :, shockmesh.elnums_all[iface_red.elementL])
    resR = sview(eqn.res, :, :, shockmesh.elnums_all[iface_red.elementR])
    interiorFaceIntegrate!(mesh.sbpface, iface_red, flux_scaled, resL, resR)
  end  # end i

  return nothing
end


#------------------------------------------------------------------------------
# Flux functions

"""
  Flux function for w, used to compute theta for LDG

  Note that this is different from a regular 2 point flux function becaues
  it operates on the entropy variables.
"""
function applyFlux(params::ParamType, obj::LDG_ESFlux, wL::AbstractVector,
                   wR::AbstractVector,
                   aux_vars, nrm::AbstractVector{Tmsh}, flux::AbstractVector
                  ) where {Tmsh}

  dim = length(nrm)

  # compute the factor in front of the jump term
  fac = zero(Tmsh)
  for d=1:dim
    fac += nrm[d]
  end
  fac *= obj.beta

  for i=1:size(flux, 1)
    flux[i] = 0.5*(wL[i] + wR[i]) + fac*(wL[i] - wR[i])
  end

  return nothing
end

"""
  This method computes the numerical flux function for q, which is used to
  update the residual.  This function computes the flux in all three
  directions at the same time.
"""
function applyFlux(params::ParamType, flux::LDG_ESFlux, qL::AbstractMatrix, qR::AbstractMatrix,
                   wL::AbstractVector, wR::AbstractVector, aux_vars,
                   nrm::AbstractVector, fluxD::AbstractMatrix{Tres}) where {Tres}

  numDofPerNode, dim = size(qL)


  @simd for d1=1:dim
    # do average and jumpt in v terms
    @simd for k=1:numDofPerNode
      fluxD[k, d1] = 0.5*(qL[k, d1] + qR[k, d1]) - flux.alpha*nrm[d1]*(wL[k] - wR[k])
    end

    # do the jump in Q term (which has unusual structure)
    @simd for d2=1:dim
      @simd for k=1:numDofPerNode
        fluxD[k, d1] -= flux.beta*nrm[d2]*(qL[k, d2] - qR[k, d2])
      end
    end
  end

  return nothing
end


