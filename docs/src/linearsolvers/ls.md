# [Linear Solvers](@id sec:linearsolvers)

```@meta
  CurrentModule = LinearSolvers
```

This section describes the interface for a linear solver.  This also provides
a means to access some of the functions implemented by [`AbstractPC`](@ref)
and [`AbstractLO`](@ref).
Whenever a linear solver is used, the linear solver API should be used rather
than accessing the [`AbstractPC`](@ref) and [`AbstractLO`](@ref)


## Type Hierarchy

```@docs
LinearSolver
StandardLinearSolver
StandardLinearSolver(::Any, ::Any, ::MPI.Comm)
```

## API

```@docs
calcPC(::StandardLinearSolver, ::AbstractMesh, ::AbstractSBP, ::AbstractSolutionData, ::Dict, ::Any, ::Any)
calcLinearOperator(::StandardLinearSolver, ::AbstractMesh, ::AbstractSBP, ::AbstractSolutionData, ::Dict, ::Any, ::Any)
calcPCandLO(::StandardLinearSolver, ::AbstractMesh, ::AbstractSBP, ::AbstractSolutionData, ::Dict, ::Any, ::Any)
applyPC(::StandardLinearSolver, ::AbstractMesh, ::AbstractSBP, ::AbstractSolutionData, ::Dict, ::Any, ::AbstractVector, ::AbstractVector)
applyPCTranspose(::StandardLinearSolver, ::AbstractMesh, ::AbstractSBP, ::AbstractSolutionData, ::Dict, ::Any, ::AbstractVector, ::AbstractVector)
linearSolve
linearSolveTranspose
isLOMatFree
isPCMatFree
setTolerances
free(::StandardLinearSolver)
```


