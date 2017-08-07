# parallel communication primatives

# MPI tags
"""
  Default MPI tag used for sending and receiving solution variables.
"""
global const TAG_DEFAULT = 1


"""
  This function is a thin wrapper around exchangeData().  It is used for the
  common case of sending and receiving the solution variables to other processes.
  It uses eqn.shared_data to do the parallel communication.
  eqn.shared_data *must* be passed into the corresponding finishDataExchange
  call.

  Inputs:
    mesh: an AbstractMesh
    sbp: an SBP operator
    eqn: an AbstractSolutionData
    opts: options dictionary

  Keyword arguments:
    tag: MPI tag to use for communication, defaults to TAG_DEFAULT
    wait: wait for sends and receives to finish before exiting
"""
function startSolutionExchange(mesh::AbstractMesh, sbp::AbstractSBP,
                                  eqn::AbstractSolutionData, opts;
                                  tag=TAG_DEFAULT, wait=false)

  if opts["parallel_data"] == "face"
    populate_buffer = getSendDataFace
  elseif opts["parallel_data"] == "element"
    populate_buffer = getSendDataElement
  else
    throw(ErrorException("unsupported parallel_type = $(opts["parallel_data"])"))
  end

  exchangeData(mesh, sbp, eqn, opts, eqn.shared_data, populate_buffer, tag=tag, wait=wait)

  return nothing
end


"""
  This function posts the MPI sends and receives for a vector of SharedFaceData.  It works for both opts["parallel_data"] == "face" or "element".  The only
  difference between these two cases is the populate_buffer() function.

  The previous receives using these SharedFaceData objects should have
  completed by the time this function is called.  An exception is throw
  if this is not the case.

  The previous sends are likely to have completed by the time this function
  is called, but they are waited on if not.  This function might not perform
  well if the previous sends have not completed.
  #TODO: fix this using WaitAny

  Inputs:
    mesh: an AbstractMesh
    sbp: an SBPOperator
    eqn: an AbstractSolutionData
    opts: the options dictionary
    populate_buffer: function with the signature:
                     populate_buffer(mesh, sbp, eqn, opts, data::SharedFaceData)
                     that populates data.q_send
  Inputs/Outputs:
    shared_data: vector of SharedFaceData objects representing the parallel
                 communication to be done

  Keyword Arguments:
    tag: MPI tag to use for this communication, defaults to TAG_DEFAULT
         This tag is typically used by the communication of the solution
         variables to other processes.  Other users of this function should
         provide their own tag

    wait: wait for the sends and receives to finish before returning.  This
          is a debugging option only.  It will kill parallel performance.
"""
function exchangeData{T}(mesh::AbstractMesh, sbp::AbstractSBP,
                         eqn::AbstractSolutionData, opts,
                         shared_data::Vector{SharedFaceData{T}},
                         populate_buffer::Function;
                         tag=TAG_DEFAULT, wait=false)

  npeers = length(shared_data)

  # bail out early if there is no communication to do
  # not sure if the rest of this function runs correctly if npeers == 0
  if npeers == 0
    return nothing
  end

  # this should already have happened.  If it hasn't something else has
  # gone wrong in the solver.  Throw an exception
  assertReceivesWaited(shared_data)

  # post the receives first
  for i=1:npeers
    data_i = shared_data[i]
    peer_i = data_i.peernum
    recv_buff = data_i.q_recv
    data_i.recv_req = MPI.Irecv!(recv_buff, peer_i, tag, data_i.comm)
    data_i.recv_waited = false
  end

  # verify the sends are consistent
  assertSendsConsistent(shared_data)

  for i=1:npeers
    # wait for these in order because doing the waitany trick doesn't work
    # these should have completed long ago, so it shouldn't be a performance
    # problem

    # the waitany trick doesn't work because this loop posts new sends, reusing
    # the same array of MPI_Requests.

    # TODO: use 2 arrays for the Requests: old and new, so the WaitAny trick
    #       works


    idx = i
    data_i = shared_data[idx]

    # wait on the previous send if it hasn't been waited on yet
    if !data_i.send_waited
      MPI.Wait!(data_i.send_req)
      data_i.send_waited = true
    end

    # move data to send buffer
    populate_buffer(mesh, sbp, eqn, opts, data_i)

    # post the send
    peer_i = data_i.peernum
    send_buff = data_i.q_send
    data_i.send_req = MPI.Isend(send_buff, peer_i, tag, data_i.comm)
    data_i.send_waited = false
  end


  if wait
    waitAllSends(shared_data)
    waitAllReceives(shared_data)
  end

  return nothing
end

"""
  This is the counterpart of exchangeData.  This function finishes the
  receives started in exchangeData.

  This function (efficiently) waits for a receive to finish and calls
  a function to do calculations for on that data. If opts["parallel_data"]
  == "face", it also permutes the data in the receive buffers to agree
  with the ordering of elementL.  For opts["parallel_data"] == "element",
  users should call SummationByParts.interiorFaceInterpolate to interpolate
  the data to the face while ensuring proper permutation.

  Inputs:
    mesh: an AbstractMesh
    sbp: an SBPOperator
    eqn: an AbstractSolutionData
    opts: the options dictonary
    calc_func: function that does calculations for a set of shared faces
               described by a single SharedFaceData.  It must have the signature
               calc_func(mesh, sbp, eqn, opts, data::SharedFaceData)

  Inputs/Outputs:
    shared_data: vector of SharedFaceData, one for each peer process that
                 needs to be communicated with.  By the time calc_func is
                 called, the SharedFaceData passed to it has its q_recv field
                 populated.  See note above about data permutation.
"""
function finishExchangeData{T}(mesh, sbp, eqn, opts,
                               shared_data::Vector{SharedFaceData{T}},
                               calc_func::Function)

  npeers = length(shared_data)
  val = assertReceivesConsistent(shared_data)
  
  for i=1:npeers
    if val == 0  # request have not been waited on previously
      eqn.params.time.t_wait += @elapsed idx = waitAnyReceive(shared_data)
    else
      idx = i
    end

    data_idx = shared_data[idx]
    if opts["parallel_data"] == "face"
      # permute the received nodes to be in the elementR orientation
      permuteinterface!(mesh.sbpface, data_idx.interfaces, data_idx.q_recv)
    end

    calc_func(mesh, sbp, eqn, opts, data_idx)

  end

  return nothing
end

@doc """
### Utils.verifyCommunication

  This function checks the data provided by the Status object to verify a 
  communication completed successfully.  The sender's rank and the number of
  elements is checked agains the expected sender and the buffer size

  Inputs:
    data: a SharedFaceData
"""->
function verifyReceiveCommunication{T}(data::SharedFaceData{T})
# verify a communication occured correctly by checking the fields of the 
# Status object
# if the Status came from a send, then peer should be comm_rank ?

  sender = MPI.Get_source(data.recv_status)
  @assert sender == data.peernum

  ndata = MPI.Get_count(data.recv_status, T)
  @assert ndata == length(data.q_recv)

  return nothing
end

"""
  This function populates the send buffer from eqn.q for 
  opts["parallle_data"]  == "face"

  Inputs:
    mesh: a mesh
    sbp: an SBP operator
    eqn: an AbstractSolutionData
    opts: options dictonary

  Inputs/Outputs:
    data: a SharedFaceData.  data.q_send will be overwritten
"""
function getSendDataFace(mesh::AbstractMesh, sbp::AbstractSBP,
                         eqn::AbstractSolutionData, opts, data::SharedFaceData)


  idx = data.peeridx
  bndryfaces = data.bndries_local
  boundaryinterpolate!(mesh.sbpface, bndryfaces, eqn.q, data.q_send)

  return nothing
end

"""
  This function populates the send buffer from eqn.q for 
  opts["parallle_data"]  == "element"

  Inputs:

    mesh: a mesh
    sbp: an SBP operator
    eqn: an AbstractSolutionData
    opts: options dictonary

  Inputs/Outputs:

    data: a SharedFaceData.  data.q_send will be overwritten
"""
function getSendDataElement(mesh::AbstractMesh, sbp::AbstractSBP,
                         eqn::AbstractSolutionData, opts, data::SharedFaceData)

  # copy data into send buffer
  idx = data.peeridx
  local_els = mesh.local_element_lists[idx]
  send_buff = data.q_send
  for j=1:length(local_els)
    el_j = local_els[j]
    for k=1:size(eqn.q, 2)
      for p=1:size(eqn.q, 1)
        send_buff[p, k, j] = eqn.q[p, k, el_j]
      end
    end
  end

  return nothing
end


@doc """
### Utils.mpi_master

  This macro introduces an if statement that causes the expression to be 
  executed only if the variable myrank is equal to zero.  myrank must exist
  in the scope of the caller

"""->
macro mpi_master(ex)
  return quote
#    println("myrank = ", esc(myrank))
    if $(esc(:(myrank == 0)))
      $(esc(ex))
    end
  end
end

@doc """
### Utils.time_all 

  This macro returns the value produced by the expression as well as 
  the execution time, the GC time, and the amount of memory allocated
"""->
macro time_all(ex)
  quote
    local stats = Base.gc_num()
    local elapsedtime = time_ns()
    local val = $(esc(ex))
    elapsedtime = time_ns() - elapsedtime
    local diff = Base.GC_Diff(Base.gc_num(), stats)
    (val, elapsedtime/1e9, diff.total_time/1e9, diff.allocd)
  end
end

function print_time_all(f, t_elapsed, t_gc, alloc)
    println(f, t_elapsed, " seconds, ", t_gc, " GC seconds, ", alloc, " bytes allocated")
end