# functions that do face integral-like operations, but operate on data from
# the entire element

"""
  Abstract type for all kernel operations used with entropy penatly functions
  (ie. given the state at the interface, apply a symmetric semi-definite
  operation).
"""
abstract type AbstractEntropyKernel end


include("IR_stab.jl")  # stabilization for the IR flux

# naming convention
# EC -> entropy conservative
# ES -> entropy stable (ie. dissipative)
# LF -> Lax-Friedrich
# LW -> Lax-Wendroff
#
# so for example, ESLFFaceIntegral is an entropy stable face integral function
# that uses Lax-Friedrich type dissipation

#-----------------------------------------------------------------------------
# entry point functions
"""
  Calculate the face integrals in an entropy conservative manner for a given
  interface.  Unlike standard face integrals, this requires data from
  the entirety of both elements, not just data interpolated to the face

  resL and resR are updated with the results of the computation for the 
  left and right elements, respectively.

  Note that nrm_xy must contains the normal vector in x-y space at the
  face nodes.

  The flux function must be symmetric!

  Aliasing restrictions: none, although its unclear what the meaning of this
                         function would be if resL and resR alias

  Performance note: the version in the tests is the same speed as this one
                    for p=1 Omega elements and about 10% faster for 
                    p=4 elements, but would not be able to take advantage of 
                    the sparsity of R for SBP Gamma elements
"""
function calcECFaceIntegral(
     params::AbstractParamType{Tdim}, 
     sbpface::DenseFace, 
     iface::Interface,
     qL::AbstractMatrix{Tsol}, 
     qR::AbstractMatrix{Tsol}, 
     aux_vars::AbstractMatrix{Tres}, 
     nrm_xy::AbstractMatrix{Tmsh},
     functor::FluxType, 
     resL::AbstractMatrix{Tres}, 
     resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}


#  Flux_tmp = params.flux_vals1
  fluxD = params.flux_valsD
  numDofPerNode = size(fluxD, 1)
#  numDofPerNode = length(Flux_tmp)
#  nrm = params.nrm

  nrmD = params.nrmD
  fill!(nrmD, 0.0)
  for d=1:Tdim
    nrmD[d, d] = 1
  end

    # loop over the nodes of "left" element that are in the stencil of interp
  for i = 1:sbpface.stencilsize
    p_i = sbpface.perm[i, iface.faceL]
    qi = ro_sview(qL, :, p_i)
    aux_vars_i = ro_sview(aux_vars, :, p_i)  # !!!! why no aux_vars_j???

    # loop over the nodes of "right" element that are in the stencil of interp
    for j = 1:sbpface.stencilsize
      p_j = sbpface.perm[j, iface.faceR]
      qj = ro_sview(qR, :, p_j)

      # compute flux and add contribution to left and right elements
      functor(params, qi, qj, aux_vars_i, nrmD, fluxD)

      @simd for dim = 1:Tdim  # move this inside the j loop, at least
        # accumulate entry p_i, p_j of E
        Eij = zero(Tres)  # should be Tres
        @simd for k = 1:sbpface.numnodes
          # the computation of nrm_k could be moved outside i,j loops and saved
          # in an array of size [3, sbp.numnodes]
          nrm_k = nrm_xy[dim, k]
          kR = sbpface.nbrperm[k, iface.orient]
          Eij += sbpface.interp[i,k]*sbpface.interp[j,kR]*sbpface.wface[k]*nrm_k
        end  # end loop k
 
       
        @simd for p=1:numDofPerNode
          resL[p, p_i] -= Eij*fluxD[p, dim]
          resR[p, p_j] += Eij*fluxD[p, dim]
        end

      end  # end loop dim
    end  # end loop j
  end  # end loop i


  return nothing
end

"""
  Method for sparse faces.  See other method for details

  Aliasing restrictions: params.flux_vals1 must not be in use
"""
function calcECFaceIntegral(
     params::AbstractParamType{Tdim}, 
     sbpface::SparseFace, 
     iface::Interface,
     qL::AbstractMatrix{Tsol}, 
     qR::AbstractMatrix{Tsol}, 
     aux_vars::AbstractMatrix{Tres}, 
     nrm_xy::AbstractMatrix{Tmsh},
     functor::FluxType, 
     resL::AbstractMatrix{Tres}, 
     resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

  flux_tmp = params.flux_vals1

  for i=1:sbpface.numnodes
    p_i = sbpface.perm[i, iface.faceL]
    q_i = ro_sview(qL, :, p_i)
    aux_vars_i = ro_sview(aux_vars, :, p_i)

    # get the corresponding node on faceR
    pnbr = sbpface.nbrperm[i, iface.orient]
    p_j = sbpface.perm[pnbr, iface.faceR]
#    p_j = sbpface.nbrperm[sbpface.perm[i, iface.faceR], iface.orient]
    q_j = ro_sview(qR, :, p_j)

    # compute flux in face normal direction
    nrm_i = ro_sview(nrm_xy, :, i)
    functor(params, q_i, q_j, aux_vars_i, nrm_i, flux_tmp)

    w_i = sbpface.wface[i]
    for p=1:size(resL, 1)
      resL[p, p_i] -= w_i*flux_tmp[p]
      resR[p, p_j] += w_i*flux_tmp[p]
    end

  end  # end loop i

  return nothing
end



"""
  Calculate the face integral in an entropy stable manner using Lax-Friedrich
  type dissipation.  
  This uses calcECFaceIntegral and calcLFEntropyPenaltyIntegral internally, 
  see those functions for details.
"""
function calcESLFFaceIntegral(
     params::AbstractParamType{Tdim}, 
     sbpface::AbstractFace, 
     iface::Interface,
     qL::AbstractMatrix{Tsol}, 
     qR::AbstractMatrix{Tsol}, 
     aux_vars::AbstractMatrix{Tres}, 
     nrm_face::AbstractMatrix{Tmsh},
     functor::FluxType, 
     resL::AbstractMatrix{Tres}, 
     resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

  calcECFaceIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, 
                     functor, resL, resR)
  calcLFEntropyPenaltyIntegral(params, sbpface, iface, qL, qR, aux_vars, 
                               nrm_face, resL, resR)

  return nothing
end

"""
  Calculate the face integral in an entropy stable manner using approximate
  Lax-Wendroff type dissipation.  
  This uses calcECFaceIntegral and calcLWEntropyPenaltyIntegral internally, 
  see those functions for details.
"""
function calcESLWFaceIntegral(
     params::AbstractParamType{Tdim}, 
     sbpface::AbstractFace, 
     iface::Interface,
     qL::AbstractMatrix{Tsol}, 
     qR::AbstractMatrix{Tsol}, 
     aux_vars::AbstractMatrix{Tres}, 
     nrm_face::AbstractMatrix{Tmsh},  # dxidx or nrm
     functor::FluxType, 
     resL::AbstractMatrix{Tres}, 
     resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

  calcECFaceIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, 
                     functor, resL, resR)
  calcLWEntropyPenaltyIntegral(params, sbpface, iface, qL, qR, aux_vars, 
                               nrm_face, resL, resR)

  return nothing
end

"""
  Calculate the face integral in an entropy stable manner using
  Lax-Wendroff type dissipation.  
  This uses calcECFaceIntegral and calcLW2EntropyPenaltyIntegral internally, 
  see those functions for details.
"""
function calcESLW2FaceIntegral(
                             params::AbstractParamType{Tdim}, 
                             sbpface::AbstractFace, 
                             iface::Interface,
                             qL::AbstractMatrix{Tsol}, 
                             qR::AbstractMatrix{Tsol}, 
                             aux_vars::AbstractMatrix{Tres}, 
                             nrm_face::AbstractMatrix{Tmsh}, # dxidx or nrm
                             functor::FluxType, 
                             resL::AbstractMatrix{Tres}, 
                             resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

  calcECFaceIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, 
                     functor, resL, resR)
  calcLW2EntropyPenaltyIntegral(params, sbpface, iface, qL, qR, aux_vars, 
                                nrm_face, resL, resR)

  return nothing
end

#-----------------------------------------------------------------------------
# Internal functions that calculate the penalties

"""
  Calculate a term that provably dissipates (mathematical) entropy using a 
  Lax-Friedrich type of dissipation.  
  This
  requires data from the left and right element volume nodes, rather than
  face nodes for a regular face integral.

  Note that nrm_face must contain the scaled face normal vector in x-y space
  at the face nodes, and qL, qR, resL, and resR are the arrays for the
  entire element, not just the face.


  Aliasing restrictions: params.nrm2, params.A0, w_vals_stencil, w_vals2_stencil
"""
function calcLFEntropyPenaltyIntegral(
             params::ParamType{Tdim, :conservative, Tsol, Tres, Tmsh},
             sbpface::DenseFace, iface::Interface, 
             qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
             aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractArray{Tmsh, 2},
             resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

  numDofPerNode = size(qL, 1)

  # convert qL and qR to entropy variables (only the nodes that will be used)
  wL = params.w_vals_stencil
  wR = params.w_vals2_stencil

  for i=1:sbpface.stencilsize
    # apply sbpface.perm here
    p_iL = sbpface.perm[i, iface.faceL]
    p_iR = sbpface.perm[i, iface.faceR]
    # these need to have different names from qL_i etc. below to avoid type
    # instability
    qL_itmp = ro_sview(qL, :, p_iL)
    qR_itmp = ro_sview(qR, :, p_iR)
    wL_itmp = sview(wL, :, i)
    wR_itmp = sview(wR, :, i)
    convertToIR(params, qL_itmp, wL_itmp)
    convertToIR(params, qR_itmp, wR_itmp)
  end

  # convert to IR entropy variables

  # accumulate wL at the node
  wL_i = params.v_vals
  wR_i = params.v_vals2
  qL_i = params.q_vals
  qR_i = params.q_vals2

  A0 = params.A0
  fastzero!(A0)

  @simd for i=1:sbpface.numnodes  # loop over face nodes
    ni = sbpface.nbrperm[i, iface.orient]
    dir = ro_sview(nrm_face, :, i)
    fastzero!(wL_i)
    fastzero!(wR_i)

    # interpolate wL and wR to this node
    @simd for j=1:sbpface.stencilsize
      interpL = sbpface.interp[j, i]
      interpR = sbpface.interp[j, ni]

      @simd for k=1:numDofPerNode
        wL_i[k] += interpL*wL[k, j]
        wR_i[k] += interpR*wR[k, j]
      end
    end

    #TODO: write getLambdaMaxSimple and getIRA0 in terms of the entropy
    #      variables to avoid the conversion
    convertToConservativeFromIR_(params, wL_i, qL_i)
    convertToConservativeFromIR_(params, wR_i, qR_i)
    # get lambda * IRA0
    lambda_max = getLambdaMaxSimple(params, qL_i, qR_i, dir)
    
    # compute average qL
    # also delta w (used later)
    @simd for j=1:numDofPerNode
      qL_i[j] = 0.5*(qL_i[j] + qR_i[j])
      wL_i[j] -= wR_i[j]
    end

    getIRA0(params, qL_i, A0)
    #for j=1:size(A0, 1)
    #  A0[j, j] = 1
    #end

    # wface[i] * lambda_max * A0 * delta w
    smallmatvec!(A0, wL_i, wR_i)
    fastscale!(wR_i, sbpface.wface[i]*lambda_max)

    # interpolate back to volume nodes
    @simd for j=1:sbpface.stencilsize
      j_pL = sbpface.perm[j, iface.faceL]
      j_pR = sbpface.perm[j, iface.faceR]

      @simd for p=1:numDofPerNode
        resL[p, j_pL] -= sbpface.interp[j, i]*wR_i[p]
        resR[p, j_pR] += sbpface.interp[j, ni]*wR_i[p]
      end
    end

  end  # end loop i

  return nothing
end

"""
  Method for sparse faces.  See other method for details

  Aliasing restrictions: params: v_vals, v_vals2, q_vals, A0, res_vals1, res_vals2
"""
function calcLFEntropyPenaltyIntegral(
             params::ParamType{Tdim, :conservative, Tsol, Tres, Tmsh},
             sbpface::SparseFace, iface::Interface, 
             qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
             aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractArray{Tmsh, 2},
             resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

  numDofPerNode = size(qL, 1)

  # convert qL and qR to entropy variables (only the nodes that will be used)
#  wL = params.w_vals_stencil
#  wR = params.w_vals2_stencil
  wL_i = params.v_vals
  wR_i = params.v_vals2
  q_avg = params.q_vals
  res_vals = params.res_vals1
  res_vals2 = params.res_vals2
  A0 = params.A0
  fastzero!(A0)


  @simd for i=1:sbpface.numnodes
    # convert to entropy variables at the nodes
    p_iL = sbpface.perm[i, iface.faceL]
    pnbr = sbpface.nbrperm[i, iface.orient]
    p_iR = sbpface.perm[pnbr, iface.faceR]
    # these need to have different names from qL_i etc. below to avoid type
    # instability
    qL_i = ro_sview(qL, :, p_iL)
    qR_i = ro_sview(qR, :, p_iR)
    convertToIR(params, qL_i, wL_i)
    convertToIR(params, qR_i, wR_i)

    dir = ro_sview(nrm_face, :, i)

    # get lambda * IRA0
    lambda_max = getLambdaMaxSimple(params, qL_i, qR_i, dir)
 
    # compute average qL
    # also delta w (used later)
    @simd for j=1:numDofPerNode
      q_avg[j] = 0.5*(qL_i[j] + qR_i[j])
      res_vals[j] = sbpface.wface[i]*lambda_max*(wL_i[j] - wR_i[j])
    end

    getIRA0(params, qL_i, A0)

    # wface[i] * lambda_max * A0 * delta w
    smallmatvec!(A0, res_vals, res_vals2)
#    fastscale!(wR_i, sbpface.wface[i]*lambda_max)

    @simd for p=1:numDofPerNode
      resL[p, p_iL] -= res_vals2[p]
      resR[p, p_iR] += res_vals2[p]
    end
  end  # end loop i

  return nothing
end


"""
  Calculate a term that provably dissipates (mathematical) entropy using a 
  an approximation to Lax-Wendroff type of dissipation.  
  This requires data from the left and right element volume nodes, rather than
  face nodes for a regular face integral.

  Note that nrm_face must contain the scaled normal vector in x-y space
  at the face nodes, and qL, qR, resL, and resR are the arrays for the
  entire element, not just the face.

  The approximation to Lax-Wendroff is the computation of

  for i=1:Tdim
    abs(ni*Y_i*S2_i*Lambda_i*Y_i.')
  end

  rather than computing the flux jacobian in the normal direction.

  Aliasing restrictions: from params the following fields are used:
    Y, S2, Lambda, res_vals1, res_vals2, res_vals3,  w_vals_stencil, 
    w_vals2_stencil, v_vals, v_vals2, q_vals, q_vals2
"""
function calcLWEntropyPenaltyIntegral(
             params::ParamType{Tdim, :conservative, Tsol, Tres, Tmsh},
             sbpface::DenseFace, iface::Interface, 
             qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
             aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractArray{Tmsh, 2},
             resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

#  println("----- entered calcEntropyLWEntropyPenaltyIntegral -----")

  numDofPerNode = size(qL, 1)

  # convert qL and qR to entropy variables (only the nodes that will be used)
  wL = params.w_vals_stencil
  wR = params.w_vals2_stencil

  Y = params.A0  # eigenvectors of flux jacobian
  S2 = params.S2  # diagonal scaling matrix squared
                       # S is defined s.t. (YS)*(YS).' = A0
  Lambda = params.Lambda  # diagonal matrix of eigenvalues
  tmp1 = params.res_vals1  # work vectors
  tmp2 = params.res_vals2
  tmp3 = params.res_vals3  # accumulate result vector

  for i=1:sbpface.stencilsize
    # apply sbpface.perm here
    p_iL = sbpface.perm[i, iface.faceL]
    p_iR = sbpface.perm[i, iface.faceR]
    # these need to have different names from qL_i etc. below to avoid type
    # instability
    qL_itmp = ro_sview(qL, :, p_iL)
    qR_itmp = ro_sview(qR, :, p_iR)
    wL_itmp = sview(wL, :, i)
    wR_itmp = sview(wR, :, i)
    convertToIR(params, qL_itmp, wL_itmp)
    convertToIR(params, qR_itmp, wR_itmp)
  end

  # convert to IR entropy variables

  # accumulate wL at the node
  wL_i = params.v_vals
  wR_i = params.v_vals2
  qL_i = params.q_vals
  qR_i = params.q_vals2

  for i=1:sbpface.numnodes  # loop over face nodes
    ni = sbpface.nbrperm[i, iface.orient]
    fill!(wL_i, 0.0)
    fill!(wR_i, 0.0)
    fill!(tmp3, 0.0)
    # interpolate wL and wR to this node
    for j=1:sbpface.stencilsize
      interpL = sbpface.interp[j, i]
      interpR = sbpface.interp[j, ni]

      for k=1:numDofPerNode
        wL_i[k] += interpL*wL[k, j]
        wR_i[k] += interpR*wR[k, j]
      end
    end

    # need conservative variables for flux jacobian calculation
    convertToConservativeFromIR_(params, wL_i, qL_i)
    convertToConservativeFromIR_(params, wR_i, qR_i)

    for j=1:numDofPerNode
      # use flux jacobian at arithmetic average state
      qL_i[j] = 0.5*( qL_i[j] + qR_i[j])
      # put delta w into wL_i
      wL_i[j] -= wR_i[j]
    end


    # get the normal vector (scaled)

    for dim =1:Tdim
      nrm_dim = nrm_face[dim, i]

      # get the eigensystem in the current direction
      if dim == 1
        calcEvecsx(params, qL_i, Y)
        calcEvalsx(params, qL_i, Lambda)
        calcEScalingx(params, qL_i, S2)
      elseif dim == 2
        calcEvecsy(params, qL_i, Y)
        calcEvalsy(params, qL_i, Lambda)
        calcEScalingy(params, qL_i, S2)
      elseif dim == 3
        calcEvecsz(params, qL_i, Y)
        calcEvalsz(params, qL_i, Lambda)
        calcEScalingz(params, qL_i, S2)
      end

      # DEBUGGING: turn this into Lax-Friedrich
#      lambda_max = maximum(absvalue(Lambda))
#      fill!(Lambda, lambda_max)

      # compute the Lax-Wendroff term, returned in tmp2
      applyEntropyLWUpdate(Y, Lambda, S2, wL_i, absvalue(nrm_dim), tmp1, tmp2)
      # accumulate result
      for j=1:length(tmp3)
        tmp3[j] += tmp2[j]
      end
    end

    # scale by wface[i]
    for j=1:length(tmp3)
      tmp3[j] *= sbpface.wface[i]
    end

    # interpolate back to volume nodes
    for j=1:sbpface.stencilsize
      j_pL = sbpface.perm[j, iface.faceL]
      j_pR = sbpface.perm[j, iface.faceR]

      for p=1:numDofPerNode
        resL[p, j_pL] -= sbpface.interp[j, i]*tmp3[p]
        resR[p, j_pR] += sbpface.interp[j, ni]*tmp3[p]
      end
    end

  end  # end loop i

  return nothing
end

@inline function applyEntropyLWUpdate(Y::AbstractMatrix, 
           Lambda::AbstractVector, S2::AbstractVector, delta_v::AbstractVector, 
           ni::Number, tmp1::AbstractVector, tmp2::AbstractVector)
# this is the computation kernel Lax-Wendroff entropy dissipation
# the result is returned in tmp2

  # multiply delta_v by Y.'
  smallmatTvec!(Y, delta_v, tmp1)
  # multiply by diagonal terms, normal vector component
  for i=1:length(delta_v)
    tmp1[i] *= ni*S2[i]*absvalue(Lambda[i])
  end
  # multiply by Y
  smallmatvec!(Y, tmp1, tmp2)

  return nothing
end

"""
  Calculate a term that provably dissipates (mathematical) entropy using a 
  Lax-Wendroff type of dissipation.  
  This requires data from the left and right element volume nodes, rather than
  face nodes for a regular face integral.

  Note nrm_face must contain the scaled normal vector in x-y space
  at the face nodes, and qL, qR, resL, and resR are the arrays for the
  entire element, not just the face.

  Implementation Detail:
    Because the scaling does not exist in arbitrary directions for 3D, 
    the function projects q into n-t coordinates, computes the
    eigendecomposition there, and then rotates back

  Aliasing restrictions: from params the following fields are used:
    Y, S2, Lambda, res_vals1, res_vals2,  w_vals_stencil, 
    w_vals2_stencil, v_vals, v_vals2, q_vals, q_vals2, nrm2, P

"""
function calcLW2EntropyPenaltyIntegral(
             params::ParamType{Tdim, :conservative, Tsol, Tres, Tmsh},
             sbpface::DenseFace, iface::Interface, 
             kernel::AbstractEntropyKernel,
             qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
             aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractArray{Tmsh, 2},
             resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

  println("----- entered calcLW2EntropyPenaltyIntegral -----")
  numDofPerNode = size(qL, 1)

  # convert qL and qR to entropy variables (only the nodes that will be used)
  wL = params.w_vals_stencil
  wR = params.w_vals2_stencil

  Y = params.A0  # eigenvectors of flux jacobian
  S2 = params.S2  # diagonal scaling matrix squared
                       # S is defined s.t. (YS)*(YS).' = A0
  Lambda = params.Lambda  # diagonal matrix of eigenvalues
  tmp1 = params.res_vals1  # work vectors
  tmp2 = params.res_vals2

  for i=1:sbpface.stencilsize
    # apply sbpface.perm here
    p_iL = sbpface.perm[i, iface.faceL]
    p_iR = sbpface.perm[i, iface.faceR]
    # these need to have different names from qL_i etc. below to avoid type
    # instability
    qL_itmp = ro_sview(qL, :, p_iL)
    qR_itmp = ro_sview(qR, :, p_iR)
    wL_itmp = sview(wL, :, i)
    wR_itmp = sview(wR, :, i)
    convertToIR(params, qL_itmp, wL_itmp)
    convertToIR(params, qR_itmp, wR_itmp)
  end

  # convert to IR entropy variables

  # accumulate wL at the node
  wL_i = params.v_vals
  wR_i = params.v_vals2
  qL_i = params.q_vals
  qR_i = params.q_vals2
  nrm = params.nrm2
  P = params.P  # projection matrix

  for i=1:sbpface.numnodes  # loop over face nodes
    ni = sbpface.nbrperm[i, iface.orient]
    fill!(wL_i, 0.0)
    fill!(wR_i, 0.0)
    # interpolate wL and wR to this node
    for j=1:sbpface.stencilsize
      interpL = sbpface.interp[j, i]
      interpR = sbpface.interp[j, ni]

      for k=1:numDofPerNode
        wL_i[k] += interpL*wL[k, j]
        wR_i[k] += interpR*wR[k, j]
      end
    end

    # need conservative variables for flux jacobian calculation
    convertToConservativeFromIR_(params, wL_i, qL_i)
    convertToConservativeFromIR_(params, wR_i, qR_i)

    for j=1:numDofPerNode
      # use flux jacobian at arithmetic average state
      qL_i[j] = 0.5*( qL_i[j] + qR_i[j])
      # put delta w into wL_i
      wL_i[j] -= wR_i[j]
    end

    nrm_i = ro_sview(nrm_face, :, i)
    applyEntropyKernel(kernel, params, qL_i, wL_i, nrm_i, tmp2)

    # apply integration weight
    for j=1:numDofPerNode
      tmp2[j] *= sbpface.wface[i]
    end

    # interpolate back to volume nodes
    for j=1:sbpface.stencilsize
      j_pL = sbpface.perm[j, iface.faceL]
      j_pR = sbpface.perm[j, iface.faceR]

      for p=1:numDofPerNode
        res_old = resL[p, j_pL]  # DEBUGGING
        resL[p, j_pL] -= sbpface.interp[j, i]*tmp2[p]
        resR[p, j_pR] += sbpface.interp[j, ni]*tmp2[p]
      end
    end

  end  # end loop i

  return nothing
end

"""
  Method for sparse faces.  See other method for details

  Aliasing restrictions: params: v_vals, v_vals2, q_vals, q_vals2, A0, res_vals1, res_vals2
                         A0, S2, Lambda, nrm2, P
"""
function calcLW2EntropyPenaltyIntegral(
             params::ParamType{Tdim, :conservative, Tsol, Tres, Tmsh},
             sbpface::SparseFace, iface::Interface, 
             kernel::AbstractEntropyKernel, #TODO: not used yet
             qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
             aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractArray{Tmsh, 2},
             resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tdim, Tsol, Tres, Tmsh}

  numDofPerNode = size(qL, 1)

  # convert qL and qR to entropy variables (only the nodes that will be used)
#  wL = params.w_vals_stencil
#  wR = params.w_vals2_stencil
  wL_i = params.v_vals
  wR_i = params.v_vals2
  delta_w = params.v_vals3
  q_avg = params.q_vals
  qprime = params.q_vals2
  res_vals = params.res_vals1
  res_vals2 = params.res_vals2
  A0 = params.A0
  fastzero!(A0)

  Y = params.A0  # eigenvectors of flux jacobian
  S2 = params.S2  # diagonal scaling matrix squared
                       # S is defined s.t. (YS)*(YS).' = A0
  Lambda = params.Lambda  # diagonal matrix of eigenvalues
  nrm = params.nrm2
  P = params.P  # projection matrix


  @simd for i=1:sbpface.numnodes
    # convert to entropy variables at the nodes
    p_iL = sbpface.perm[i, iface.faceL]
    pnbr = sbpface.nbrperm[i, iface.orient]
    p_iR = sbpface.perm[pnbr, iface.faceR]
    # these need to have different names from qL_i etc. below to avoid type
    # instability
    qL_i = ro_sview(qL, :, p_iL)
    qR_i = ro_sview(qR, :, p_iR)
    convertToIR(params, qL_i, wL_i)
    convertToIR(params, qR_i, wR_i)

    # compute average qL
    # also delta w (used later)
    @simd for j=1:numDofPerNode
      q_avg[j] = 0.5*(qL_i[j] + qR_i[j])
      delta_w[j] = sbpface.wface[i]*(wL_i[j] - wR_i[j])
    end

    # get the normal vector (scaled)
    for dim=1:Tdim
      nrm[dim] = nrm_face[dim, i]
    end
    
    nrm_i = ro_sview(nrm_face, :, i)
    applyEntropyKernel(kernel, q_avg, w_avg, nrm_i, res_vals)

    @simd for p=1:numDofPerNode
      resL[p, p_iL] -= res_vals[p]
      resR[p, p_iR] += res_vals[p]
    end
  end  # end loop i

  return nothing
end



"""
  This function modifies the eigenvalues of the euler flux jacobian such
  that if any value is zero, a little dissipation is still added.  The
  absolute values of the eigenvalues modified eigenvalues are calculated.

  Methods are available for 2 and 3 dimensions

  This function depends on the ordering of the eigenvalues produced by
  calcEvals.

  Inputs:
    params: ParamType, used to dispatch to 2 or 3D method

  Inputs/Outputs:
    Lambda: vector of eigenvalues to be modified

  Aliasing restrictions: none
"""
function calcEntropyFix(params::ParamType{2}, Lambda::AbstractVector)
  
  # entropy fix parameters
  sat_Vn = 0.025
  sat_Vl = 0.05


  # this is dependent on the ordering of the eigenvalues produced
  # by calcEvals
  lambda3 = Lambda[2]  # Un
  lambda4 = Lambda[3]  # Un + a
  lambda5 = Lambda[4]  # Un - a


  # if any eigenvalue is zero, introduce dissipation that is a small
  # fraction of the maximum eigenvalue
  rhoA = max(absvalue(lambda4), absvalue(lambda5))  # absvalue(Un) + a
  lambda3 = max( absvalue(lambda3), sat_Vl*rhoA)
  lambda4 = max( absvalue(lambda4), sat_Vn*rhoA)
  lambda5 = max( absvalue(lambda5), sat_Vn*rhoA)

  Lambda[1] = lambda3
  Lambda[2] = lambda3
  Lambda[3] = lambda4
  Lambda[4] = lambda5
  
  return nothing
end

function calcEntropyFix(params::ParamType{3}, Lambda::AbstractVector)
  
  # entropy fix parameters
  sat_Vn = 0.025
  sat_Vl = 0.05


  # this is dependent on the ordering of the eigenvalues produced
  # by calcEvals
  lambda3 = Lambda[3]  # Un
  lambda4 = Lambda[4]  # Un + a
  lambda5 = Lambda[5]  # Un - a


  # if any eigenvalue is zero, introduce dissipation that is a small
  # fraction of the maximum eigenvalue
  rhoA = max(absvalue(lambda4), absvalue(lambda5))  # absvalue(Un) + a
  lambda3 = max( absvalue(lambda3), sat_Vl*rhoA)
  lambda4 = max( absvalue(lambda4), sat_Vn*rhoA)
  lambda5 = max( absvalue(lambda5), sat_Vn*rhoA)

  Lambda[1] = lambda3
  Lambda[2] = lambda3
  Lambda[3] = lambda3
  Lambda[4] = lambda4
  Lambda[5] = lambda5
  
  return nothing
end


#------------------------------------------------------------------------------
# Create separate kernel functions for each entropy penatly (LF, LW, etc)


struct LW2Kernel{Tsol, Tres, Tmsh} <: AbstractEntropyKernel
  nrm::Array{Tmsh, 1}
  P::Array{Tmsh, 2}
  Y::Array{Tsol, 2}  # eigenvectors
  Lambda::Array{Tsol, 1}  # eigenvalues
  S2::Array{Tsol, 1}  # scaling for the eigensystem
  q_tmp::Array{Tsol, 1}
  tmp1::Array{Tres, 1}
  tmp2::Array{Tres, 1}
end

function LW2Kernel(mesh::AbstractMesh{Tmsh}, eqn::EulerData{Tsol, Tres}) where {Tsol, Tres, Tmsh}

  ncomp = mesh.dim + 2  # = mesh.numDofPerNode?
  nrm = zeros(Tmsh, mesh.dim)
  P = zeros(Tmsh, ncomp, ncomp)
  Y = zeros(Tsol, ncomp, ncomp)
  Lambda = zeros(Tsol, ncomp)
  S2 = zeros(Tsol, ncomp)
  q_tmp = zeros(Tsol, ncomp)
  tmp1 = zeros(Tres, ncomp)
  tmp2 = zeros(Tres, ncomp)

  return LW2Kernel{Tsol, Tres, Tmsh}(nrm, P, Y, Lambda, S2, q_tmp, tmp1, tmp2)
end

"""
  Applies a Lax-Wendroff type dissipation kernel.  The intend is to apply

  Y^T |Lambda| Y delta_w
"""
function applyEntropyKernel(obj::LW2Kernel, params::ParamType, 
                            q_avg::AbstractVector, delta_w::AbstractVector,
                            nrm_in::AbstractVector, flux::AbstractVector)

  # unpack fields
  nrm = obj.nrm
  P = obj.P
  Y = obj.Y
  Lambda = obj.Lambda
  S2 = obj.S2
  q_tmp = obj.q_tmp
  tmp1 = obj.tmp1
  tmp2 = obj.tmp2

  Tdim = length(nrm_in)
  numDofPerNode = length(q_avg)

  # normalize direction vector
  len_fac = calcLength(params, nrm_in)
  for dim=1:Tdim
    nrm[dim] = nrm_in[dim]/len_fac
  end

  # project q into n-t coordinate system
  #TODO: verify this is equivalent to computing the eigensystem in the
  #      face normal direction (including a non-unit direction vector)
  getProjectionMatrix(params, nrm, P)
  projectToNT(params, P, q_avg, q_tmp)  # q_tmp is qprime

  # get eigensystem in the normal direction, which is equivalent to
  # the x direction now that q has been rotated
  calcEvecsx(params, q_tmp, Y)
  calcEvalsx(params, q_tmp, Lambda)
  calcEScalingx(params, q_tmp, S2)

#    calcEntropyFix(params, Lambda)

  # compute LF term in n-t coordinates, then rotate back to x-y
  projectToNT(params, P, delta_w, tmp1)
  smallmatTvec!(Y, tmp1, tmp2)
  # multiply by diagonal Lambda and S2, also include the scalar
  # wface and len_fac components
  for j=1:length(tmp2)
    tmp2[j] *= len_fac*absvalue(Lambda[j])*S2[j]
  end
  smallmatvec!(Y, tmp2, tmp1)
  projectToXY(params, P, tmp1, flux)

  return nothing
end




#-----------------------------------------------------------------------------
# do the functor song and dance


"""
  Entropy conservative term only
"""
mutable struct ECFaceIntegral <: FaceElementIntegralType
  function ECFaceIntegral(mesh::AbstractMesh, eqn::EulerData)
    return new()
  end
end

function (obj::ECFaceIntegral)(
              params::AbstractParamType{Tdim}, 
              sbpface::AbstractFace, iface::Interface,
              qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
              aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractMatrix{Tmsh},
              functor::FluxType, 
              resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tsol, Tres, Tmsh, Tdim}


  calcECFaceIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, 
                      functor, resL, resR)

end


"""
  Entropy conservative integral + Lax-Friedrich penalty
"""
mutable struct ESLFFaceIntegral <: FaceElementIntegralType
  function ESLFFaceIntegral(mesh::AbstractMesh, eqn::EulerData)
    return new()
  end
end

function (obj::ESLFFaceIntegral)(
              params::AbstractParamType{Tdim}, 
              sbpface::AbstractFace, iface::Interface,
              qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
              aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractMatrix{Tmsh},
              functor::FluxType, 
              resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tsol, Tres, Tmsh, Tdim}


  calcESLFFaceIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, functor, resL, resR)

end

"""
  Lax-Friedrich entropy penalty term only
"""
mutable struct ELFPenaltyFaceIntegral <: FaceElementIntegralType
  function ELFPenaltyFaceIntegral(mesh::AbstractMesh, eqn::EulerData)
    return new()
  end
end

function (obj::ELFPenaltyFaceIntegral)(
              params::AbstractParamType{Tdim}, 
              sbpface::AbstractFace, iface::Interface,
              qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
              aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractMatrix{Tmsh},
              functor::FluxType, 
              resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tsol, Tres, Tmsh, Tdim}


  calcLFEntropyPenaltyIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, resL, resR)

end

"""
  Entropy conservative integral + approximate Lax-Wendroff penalty
"""
mutable struct ESLWFaceIntegral <: FaceElementIntegralType

  function ESLWFaceIntegral(mesh::AbstractMesh, eqn::EulerData)
    return new()
  end
end

function (obj::ESLWFaceIntegral)(
              params::AbstractParamType{Tdim}, 
              sbpface::AbstractFace, iface::Interface,
              qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
              aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractMatrix{Tmsh},
              functor::FluxType, 
              resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tsol, Tres, Tmsh, Tdim}


  calcESLWFaceIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, functor, resL, resR)

end

"""
  Approximate Lax-Wendroff entropy penalty term only
"""
mutable struct ELWPenaltyFaceIntegral <: FaceElementIntegralType
  function ELWPenaltyFaceIntegral(mesh::AbstractMesh, eqn::EulerData)
    return new()
  end
end

function (obj::ELWPenaltyFaceIntegral)(
              params::AbstractParamType{Tdim}, 
              sbpface::AbstractFace, iface::Interface,
              qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
              aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractMatrix{Tmsh},
              functor::FluxType, 
              resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tsol, Tres, Tmsh, Tdim}


  calcLWEntropyPenaltyIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, resL, resR)

end

"""
  Entropy conservative integral + Lax-Wendroff penalty
"""
mutable struct ESLW2FaceIntegral <: FaceElementIntegralType
  kernel::LW2Kernel

  function ESLW2FaceIntegral(mesh::AbstractMesh, eqn::EulerData)
    kernel = LW2Kernel(mesh, eqn)
    return new(kernel)
  end
end

function (obj::ESLW2FaceIntegral)(
              params::AbstractParamType{Tdim}, 
              sbpface::AbstractFace, iface::Interface,
              qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
              aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractMatrix{Tmsh},
              functor::FluxType, 
              resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tsol, Tres, Tmsh, Tdim}

  calcESLW2FaceIntegral(params, sbpface, iface, qL, qR, aux_vars, nrm_face, functor, resL, resR)

end

"""
  Lax-Wendroff entropy penalty term only
"""
mutable struct ELW2PenaltyFaceIntegral <: FaceElementIntegralType
  kernel::LW2Kernel

  function ELW2PenaltyFaceIntegral(mesh::AbstractMesh, eqn::EulerData)
    kernel = LW2Kernel(mesh, eqn)
    return new(kernel)
  end
end

function (obj::ELW2PenaltyFaceIntegral)(
              params::AbstractParamType{Tdim}, 
              sbpface::AbstractFace, iface::Interface,
              qL::AbstractMatrix{Tsol}, qR::AbstractMatrix{Tsol}, 
              aux_vars::AbstractMatrix{Tres}, nrm_face::AbstractMatrix{Tmsh},
              functor::FluxType, 
              resL::AbstractMatrix{Tres}, resR::AbstractMatrix{Tres}) where {Tsol, Tres, Tmsh, Tdim}


  calcLW2EntropyPenaltyIntegral(params, sbpface, iface, obj.kernel, qL, qR, aux_vars, nrm_face, resL, resR)

end



global const FaceElementDict = Dict{String, Type{T} where T <: FaceElementIntegralType}(
"ECFaceIntegral" => ECFaceIntegral,
"ESLFFaceIntegral" => ESLFFaceIntegral,
"ELFPenaltyFaceIntegral" => ELFPenaltyFaceIntegral,
"ESLWFaceIntegral" => ESLWFaceIntegral,
"ELWPenaltyFaceIntegral" => ELWPenaltyFaceIntegral,
"ESLW2FaceIntegral" => ESLW2FaceIntegral,
"ELW2PenaltyFaceIntegral" => ELW2PenaltyFaceIntegral,


)

"""
  Populates the field(s) of the EulerData object with
  [`FaceElementIntegralType`](@ref) functors as specified by the options
  dictionary

  **Inputs**

   * mesh: an AbstractMesh
   * sbp: an SBP operator
   * opts: the options dictionary

  **Inputs/Outputs**

   * eqn: the EulerData object
"""
function getFaceElementFunctors(mesh, sbp, eqn::AbstractEulerData, opts)

  objname = opts["FaceElementIntegral_name"]
  Tobj = FaceElementDict[objname]
  eqn.face_element_integral_func = Tobj(mesh, eqn)

  return nothing
end
