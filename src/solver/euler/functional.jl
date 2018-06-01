abstract AbstractFunctional

type volumeAverage <: AbstractFunctional
end
function call{Tmsh, Tsol, Tres, Tdim}(obj::volumeAverage,
                                      mesh::AbstractMesh{Tmsh},
                                      sbp::AbstractSBP,
                                      eqn::EulerData{Tsol, Tres, Tdim},
                                      opts,
                                      val::Array{Tsol, 1})
  @assert(length(val) == mesh.numDofPerNode)
  val[:] = 0.0

  w = sview(sbp.w, :)
  for elem = 1 : mesh.numEl
    jac = sview(mesh.jac, :, elem)
    q = sview(eqn.q, :, :, elem)
    for n = 1 : mesh.numNodesPerElement
      for dof = 1 : mesh.numDofPerNode
        val[dof] += w[n]/jac[n]*q[dof, n]
      end
    end

  end
  println(val)

  return nothing
end

global const VolumeFunctionalDict = Dict{ASCIIString, AbstractFunctional}(    
  "volumeAverage" => volumeAverage(),
)
