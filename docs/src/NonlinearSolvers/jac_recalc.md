# Jacobian and Preconditioner Freezing

```@meta
  CurrentModule = NonlinearSolvers
```

It is often faster to reuse the Jacobian and/or preconditioner than calculate
a new one each major iteration.  The functions described here provide
a consistant API for doing so.

Each method in `NonlinearSolvers` should specify if it supports Jacobian
and PC freezing.  If it does, it should specify the `prefix` (see [Construction](@ref)).

Note that some methods use `newtonInner` internally.  It is sometimes
beneficial to have `newtonInner` recompute the Jacobian and PC.  In other
cases, using the same Jacobian and PC for several calls to `newtonInner`
is beneficial.  Both these use cases are supported. Both `newtonInner` and
the outer method can have their own [`RecalculationPolicy`](@ref) objects.
When the `newtonInner` `RecalculationPolicy` is [`RecalculateNever`](@ref), it
will never recalculate the Jacobian and PC and the outer method will be the
soley responsible for updaing the Jacobian and PC.  In the reverse case, the
outer method can use `RecalculateNever` and let `newtonInner` recalculate
the Jacobian and PC.

## API

```@docs
doRecalculation
decideRecalculation
resetRecalculationPolicy
RECALC_BOTH
```


## Construction

```@docs
getRecalculationPolicy
RecalculationPolicyDict
```

## Recalculation Policies

```@autodocs
Modules = [NonlinearSolvers]
Pages = ["jac_recalc.jl"]
Order = [:type]
```

