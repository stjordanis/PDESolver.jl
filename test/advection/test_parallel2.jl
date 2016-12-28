# run tests in parallel (np=4)

#=
include(joinpath(Pkg.dir("PDESolver"), "src/input/make_input.jl"))

using PDESolver
#using Base.Test
using FactCheck
using ODLCommonTools
using PdePumiInterface  # common mesh interface - pumi
using SummationByParts  # SBP operators
using AdvectionEquationMod
using Utils
using ForwardDiff
using NonlinearSolvers   # non-linear solvers
using ArrayViews

global const STARTUP_PATH = joinpath(Pkg.dir("PDESolver"), "src/solver/advection/startup.jl")

resize!(ARGS, 1)
=#

"""
  Test the parallel communication primatives in the Utils module
"""
function test_parallel2_comm()

  ARGS[1] = "input_vals_parallel2.jl"
  mesh, sbp, eqn, opts = run_advection(ARGS[1])

  myrank = mesh.myrank
  commsize = mesh.commsize
  function wrap(i, commsize)
    if i > (commsize-1)
      i = 0
    elseif i < 0
      i = commsize - 1
    end

    return i
  end

  facts("----- Testing Parallel Communication -----") do
    peer_up = wrap(myrank+1, commsize)
    peer_down = wrap(myrank-1, commsize)

    mesh.npeers = 2
    mesh.peer_parts = [peer_down, peer_up]
    mesh.send_reqs = Array(MPI.Request, mesh.npeers)
    mesh.recv_reqs = Array(MPI.Request, mesh.npeers)
    mesh.recv_waited= Array(Bool, mesh.npeers)
    mesh.send_waited = Array(Bool, mesh.npeers)

    initMPIStructures(mesh, opts)

    send_data = Array(Array{Float64, 1}, mesh.npeers)
    recv_data = Array(Array{Float64, 1}, mesh.npeers)
    for i=1:mesh.npeers
      send_data[i] = Float64[myrank + i, myrank + i + 1]
      recv_data[i] = Array(Float64, mesh.npeers)
    end

    exchangeFaceData(mesh, opts, send_data, recv_data, wait=true)

    # peer down: the sent to its peer up
    data = recv_data[1]
    @fact data[1] --> peer_down + 2
    @fact data[2] --> peer_down + 3

    # peer up: sent to its peer down
    data = recv_data[2]
    @fact data[1] --> peer_up + 1
    @fact data[2] --> peer_up + 2


    # test exchangeElementData
    send_buffs = Array(Array{Float64, 3}, mesh.npeers)
    recv_buffs = Array(Array{Float64, 3}, mesh.npeers)
  #  fill!(eqn.q, 42)
    for i=1:mesh.npeers
      mesh.local_element_lists[i] = [i]
      send_buffs[i] = zeros(Float64, mesh.numDofPerNode, mesh.numNodesPerElement, 1)
      recv_buffs[i] = zeros(Float64, mesh.numDofPerNode, mesh.numNodesPerElement, 1)
      
      eqn.q[:,:, i] = i + myrank
    end
    fill!(mesh.recv_waited, true)
    fill!(mesh.send_waited, true)

    exchangeElementData(mesh, opts, eqn.q, send_buffs, recv_buffs, wait=true)

    data = recv_buffs[1]
    for j in data
      @fact j --> peer_down + 2
    end
    data = recv_buffs[2]
    for j in data
      @fact j --> peer_up + 1
    end


  end  # end facts block

  return nothing
end

add_func1!(AdvectionTests, test_parallel2_comm)

