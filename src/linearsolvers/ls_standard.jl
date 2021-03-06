# implementation of the StandardLinearSolver
# This is the interface algorithms should use for doing linear solves

"""
  Calculates the preconditioner for the linear solver.  Thsi preconditioner
  will be used for all linear solves until this function is called again.

  For direct solvers, this function calculates the linear operator itself.
  Prefer [`calcPCandLO`](@ref) whenever possible.

  **Inputs**

   * ls: StandardLinearSolver
   * mesh
   * sbp
   * eqn
   * opts
   * ctx_residual: the ctx required by [`physicsRhs`](@ref) like functions
   * t: current time

  **Keyword Arguments**

   * start_comm: start parallel communication (if required by the PC), default
                  false.  This means the user is generally required to make sure
                  parallel communication is started before calling this
                  function.
"""
function calcPC(ls::StandardLinearSolver, mesh::AbstractMesh, sbp::AbstractOperator,
                eqn::AbstractSolutionData, opts::Dict, ctx_residual, t; start_comm=false)

  if typeof(ls.pc) <: PCNone
    if start_comm && needParallelData(ls.lo)
      startSolutionExchange(mesh, sbp, eqn, opts)
    end
    calcLinearOperator(ls.lo, mesh, sbp, eqn, opts, ctx_residual, t)
  else
    if start_comm && needParallelData(ls.pc)
      startSolutionExchange(mesh, sbp, eqn, opts)
    end
    calcPC(ls.pc, mesh, sbp, eqn, opts, ctx_residual, t)
  end

  return nothing
end

"""
  Calculates the linear operator.  Use this function only if you want to
  calculate the linear operator and not the preconditioner.
  Prefer [`calcPCandLO`](@ref), which avoids calculating the matrix twice if
  the preconditioner and linear operator share the same matrix

  **Inputs**

   * ls: StandardLinearSolver
   * mesh
   * sbp
   * eqn
   * opts
   * ctx_residual: the ctx required by [`physicsRhs`](@ref) like functions
   * t: current time

  **Keyword Arguments**

   * start_comm: start parallel communication (if required by the lo), default
                  false.  This means the user is generally required to make sure
                  parallel communication is started before calling this
                  function.

"""
function calcLinearOperator(ls::StandardLinearSolver, mesh::AbstractMesh,
                         sbp::AbstractOperator,
                         eqn::AbstractSolutionData, opts::Dict, ctx_residual, t;
                         start_comm=false)


  if start_comm && needParallelData(ls.lo)
    startSolutionExchange(mesh, sbp, eqn, opts)
  end
  calcLinearOperator(ls.lo, mesh, sbp, eqn, opts, ctx_residual, t)

end


"""
  Calculates both the preconditioner and linear operator.  In the case where
  they share the matrix, the calculation is only performed once.  This function
  should be preferred to calling [`calcPC`](@ref) and [`calcLinearOperator`](@ref) one
  after the other

  **Inputs**

   * ls: StandardLinearSolver
   * mesh
   * sbp
   * eqn
   * opts
   * ctx_residual: the ctx required by [`physicsRhs`](@ref) like functions
   * t: current time

  **Keyword Arguments**

   * start_comm: start parallel communication (if required by the lo), default
                  false.  This means the user is generally required to make sure
                  parallel communication is started before calling this
                  function.  Note that it is not possible to interleave
                  communication and computation in this case, so performing
                  communication will be very expensive.


"""
function calcPCandLO(ls::StandardLinearSolver, mesh::AbstractMesh,
                     sbp::AbstractOperator,
                     eqn::AbstractSolutionData, opts::Dict, ctx_residual, t;
                     start_comm=false)


  #TODO: why is wait=true here? shouldn't the physics module wait if it hasn't
  #      been done yet?
  if typeof(ls.pc) <: PCNone
    if start_comm && needParallelData(ls.lo)
      startSolutionExchange(mesh, sbp, eqn, opts, wait=true)
    end
    calcLinearOperator(ls.lo, mesh, sbp, eqn, opts, ctx_residual, t)
  elseif ls.shared_mat
    if start_comm && needParallelData(ls.lo)
      startSolutionExchange(mesh, sbp, eqn, opts, wait=true)
    end
    calcLinearOperator(ls.lo, mesh, sbp, eqn, opts, ctx_residual, t)
    pc2 = getBasePC(ls.pc)
    pc2.is_setup = false  # we don't call calcPC but this flag still needs to
                          # be set
  else
    if start_comm && ( needParallelData(ls.lo) || needParallelData(ls.pc))
      startSolutionExchange(mesh, sbp, eqn, opts, wait=true)
    end
    calcPC(ls.pc, mesh, sbp, eqn, opts, ctx_residual, t)
    calcLinearOperator(ls.lo, mesh, sbp, eqn, opts, ctx_residual, t)
  end

  return nothing
end

"""
  Apply the preconditioner, ie. x = inv(Ap)*b, where Ap is an approximation
  to the linear operator used for preconditioner.  This function also works
  for matrix-free methods.

  Note that [`calcPC`](@ref) or [`calcPCandLO`](@ref) must be called before
  this function can be used.

  For direct methods, a linear solve is performed because there is no
  preconditioner.
"""
function applyPC(ls::StandardLinearSolver, mesh::AbstractMesh, sbp::AbstractOperator,
                 eqn::AbstractSolutionData, opts::Dict, t, b::AbstractVector, 
                 x::AbstractVector)

  if typeof(ls.pc) <: PCNone
    # apply the most recent linear operator
    linearSolve(ls, b, x)
  else
    applyPC(ls.pc, mesh, sbp, eqn, opts, t, b, x)
  end

  return nothing
end

"""
  Like [`applyPC`](@ref), but applies the transpose (if possible, otherwise
  throws an error).
"""
function applyPCTranspose(ls::StandardLinearSolver, mesh::AbstractMesh,
                          sbp::AbstractOperator,
                          eqn::AbstractSolutionData, opts::Dict, t,
                          b::AbstractVector, x::AbstractVector)
  if typeof(ls.pc) <: PCNone
    linearSolveTranspose(ls, b, x)
  else
    applyPCTranspose(ls.pc, mesh, sbp, eqn, opts, t, b, x)
  end

  return nothing
end


"""
  Solves the linear system Ax = b for x. This function does not recompute the
  precondtioner or linear operator,  The preconditioner and linear operator
  used are the ones calculated by the most recent call to
  [`calcPC`](@ref), [`calcLinearOperator`](@ref) (or [`calcPCandLO`](@ref).

  For Petsc matrices, this function does the final matrix assembly.

  **Inputs**

   * ls: the [`StandardLinearSolver`](@ref) object.
   * b: the right hand side vector (local process portion only)
   * verbose: verbosity level, default 5, < 4 indicates no output
  
  **Inputs/Outputs**

   * x: vector overwritten with result (local process portion only)

  Implementation Notes:

  The preconditioner and matrix factorization (for direct solves) might
  be computed during this function, but they will be computed at the state
  correspondong to the last call to the functions that calculate them.
"""
function linearSolve(ls::StandardLinearSolver, b::AbstractVector,
                     x::AbstractVector, verbose=5)

  # call the specific solver

  #TODO: have time_all return a struct
  tmp, t_solve, t_gc, alloc = @time_all _linearSolve(ls, b, x)

  @verbose5 if ls.myrank == 0
    println(BSTDOUT, "matrix solve:")
    print_time_all(BSTDOUT, t_solve, t_gc, alloc)
  end

  return nothing
end

"""
  Similar to [`linearSolve`](@ref), but solves A.'x = b.  See that function
  for details.
"""
function linearSolveTranspose(ls::StandardLinearSolver, b::AbstractVector,
                     x::AbstractVector, verbose=5)

  # call the specific solver

  #TODO: have time_all return a struct
  tmp, t_solve, t_gc, alloc = @time_all _linearSolve(ls, b, x, trans=true)

  @verbose5 if ls.myrank == 0
    println(BSTDOUT, "matrix transpose solve:")
    print_time_all(BSTDOUT, t_solve, t_gc, alloc)
  end

  return nothing
end

function _linearSolve(
ls::StandardLinearSolver{Tpc, Tlo},
b::AbstractVector, x::AbstractVector; trans=false) where {Tlo <: AbstractDenseLO, Tpc}

  @assert typeof(ls.pc) <: PCNone

  lo2 = getBaseLO(ls.lo)

  # factor if needed
  if !getIsSetup(lo2)
    getrf!(lo2.A, lo2.ipiv)
    setIsSetup(lo2, true)
    lo2.nfactorizations += 1
  end

  tchar = trans ? 'T' : 'N'

  # solve
  copy!(x, b)
  info = getrs2!(tchar, lo2.A, lo2.ipiv, x)
  @assert info == 0

  if trans
    lo2.ntsolves += 1
  else
    lo2.nsolves += 1
  end


  return nothing
end

"""
  On Skylake, there is a problem with reusing the symbolic factorization
  with UMFPACK.  If this constant is true, it will recalculate the the
  symbolic factorization each time.  On other systems, this constant should
  be set to false.
"""
global const SKYLAKE_STACKSMASH=true

function _linearSolve(ls::StandardLinearSolver{Tpc, Tlo},
                      b::AbstractVector, x::AbstractVector;
                      trans=false) where {Tlo <: AbstractSparseDirectLO, Tpc}

  @assert typeof(ls.pc) <: PCNone

  lo2 = getBaseLO(ls.lo)

  make_zerobased(lo2.A)
  # compute factorization if needed
  if !getIsSetup(lo2)
    umfpack_free_numeric(lo2.fac)  # free old factorization
    if SKYLAKE_STACKSMASH
      umfpack_free_symbolic(lo2.fac)  # DEBUGGING
    end
    # note: the matrix stored in the factorization object must alias. lo2.A
    umfpack_numeric!(lo2.fac)
    setIsSetup(lo2, true)
    lo2.nfactorizations += 1
  end

  tchar = trans ? UMFPACK_At : UMFPACK_A

  solve_suitesparse(lo2.fac, b, tchar, x)
  make_onebased(lo2.A)
  if trans
    lo2.ntsolves += 1
  else
    lo2.nsolves += 1
  end

  return nothing
end


function _linearSolve(
ls::StandardLinearSolver{Tpc, Tlo},
b::AbstractVector, x::AbstractVector; trans=false) where {Tlo <: PetscLO , Tpc}

  myrank = ls.myrank
  pc2 = getBasePC(ls.pc)
  lo2 = getBaseLO(ls.lo)
  @assert !(typeof(pc2) <: PCNone)
  
  # prepare the data structures
  #TODO: copy x into xtmp to support initial guess non-zero
  t_assem = @elapsed assemblePetscData(ls, b, lo2.btmp, x, lo2.xtmp)
  @mpi_master println(BSTDOUT, "Final matrix assembly time = ", t_assem)

  if !isPCMatFree(ls) && !pc2.is_setup
    setupPC(pc2)
  end

  # do the solve
  ksp = ls.ksp
  SetTolerances(ksp, ls.reltol, ls.abstol, ls.dtol, PetscInt(ls.itermax))

  if trans
    KSPSolveTranspose(ksp, lo2.btmp, lo2.xtmp)
    lo2.ntsolves += 1
  else
    KSPSolve(ksp, lo2.btmp, lo2.xtmp)
    lo2.nsolves += 1
  end

  # print convergence info
  @mpi_master begin
    reason = GetConvergedReason(ksp)
    println(BSTDOUT, "KSP converged reason = ", KSPConvergedReasonDict[reason])
    rnorm = GetResidualNorm(ksp)
    println("Linear residual = ", rnorm)
  end

  # copy result back to x
  xtmp = VecGetArrayRead(lo2.xtmp)
  copy!(x, xtmp)
  VecRestoreArrayRead(lo2.xtmp, xtmp)

  # Reuse preconditionre until next time setupPC() is called
  PCSetReusePreconditioner(pc2.pc, PETSC_TRUE)
  

  return nothing
end

"""
  Helper function for doing linear solves with Petsc matrices.  It assembles
  A, and Ap, and copies b into the local part of the petsc vector for b.
"""
function assemblePetscData(ls::StandardLinearSolver, b::AbstractVector,
                           b_petsc::PetscVec, x::AbstractVector,
                           x_petsc::PetscVec)

  lo_matfree = isLOMatFree(ls)
  pc_matfree = isPCMatFree(ls)

  pc2 = getBasePC(ls.pc)
  lo2 = getBaseLO(ls.lo)
  myrank = ls.myrank

  # assemble things
  if !lo_matfree && !getIsSetup(lo2)
    MatAssemblyBegin(lo2.A, MAT_FINAL_ASSEMBLY)
  end

  if !pc_matfree && !ls.shared_mat
    MatAssemblyBegin(pc2.A, MAT_FINAL_ASSEMBLY)
  end

  # copy values into the vector
  btmp = VecGetArray(b_petsc)
  copy!(btmp, b)
  VecRestoreArray(b_petsc, btmp)
  
  xtmp = VecGetArray(x_petsc)
  copy!(xtmp, x)
  VecRestoreArray(x_petsc, xtmp)



  # end assembly
  if !lo_matfree && !getIsSetup(lo2)
    MatAssemblyEnd(lo2.A, MAT_FINAL_ASSEMBLY)
    setIsSetup(lo2, true)
    lo2.nassemblies[1] += 1
    matinfo = MatGetInfo(lo2.A, PETSc2.MAT_LOCAL)
    if matinfo.mallocs > 0.5  # if any mallocs
      println(BSTDERR, "Warning: non-zero number of mallocs for A on process $myrank: $(matinfo.mallocs) mallocs")
    end
  end

  if !pc_matfree && !ls.shared_mat
    MatAssemblyEnd(pc2.A, MAT_FINAL_ASSEMBLY)
    setIsAssembled(pc2, true)
    pc2.nassemblies[1] += 1
    matinfo = MatGetInfo(pc2.A, PETSc2.MAT_LOCAL)
    if matinfo.mallocs > 0.5  # if any mallocs
      println(BSTDERR, "Warning: non-zero number of mallocs for Ap on process $myrank: $(matinfo.mallocs) mallocs")
    end
  end

#  pc2.is_setup = true

  return nothing
end



"""
  Returns true if the linear operator is matrix free, false otherwise
"""
function isLOMatFree(ls::StandardLinearSolver)

  return typeof(ls.lo) <: AbstractPetscMatFreeLO
end

"""
  Returns true if the preconditioner is matrix free, false otherwise
"""
function isPCMatFree(ls::StandardLinearSolver)

  return typeof(ls.pc) <: AbstractPetscMatFreePC
end

"""
  Set the tolerances for iterative solves.  Has no effect for direct solves.
  Supplying a negative value results in retaining the original value.

  **Inputs**
  
   * ls: StandardLinearSolver
   * reltol: relative residual tolerance
   * abstol: absolute residual tolerance
   * dtol: divergence tolerance
   * itermax: maximum number of iterations
"""
function setTolerances(ls::StandardLinearSolver, reltol::Number, abstol::Number,
                       dtol::Number, itermax::Integer)


  if reltol > 0
    ls.reltol = reltol
  end

  if abstol > 0
    ls.abstol = abstol
  end

  if dtol > 0
    ls.dtol = dtol
  end

  if itermax > 0
    ls.itermax = itermax
  end

  return nothing
end

"""
  This function frees any memory owned by external libraries, both in the 
  StandardLinearSolver object itself and in the pc and lo objects.
  Therefore, at the end of a run, all you need to do is free the
  StandardLinearSolver and everything will be taken care of.

  It is safe to call this function multiple times.
"""
function free(ls::StandardLinearSolver)

  if !ls.is_finalized
    if ls.ksp.pobj != C_NULL
      PetscDestroy(ls.ksp)
      ls.ksp.pobj = C_NULL
    end

    free(ls.pc)
    free(ls.lo)

  end

  ls.is_finalized = true

  return nothing
end


