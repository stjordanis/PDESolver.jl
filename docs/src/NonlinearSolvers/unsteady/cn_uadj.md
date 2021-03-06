# Crank-Nicolson Unsteady Adjoint -- EXPERIMENTAL, INCORRECT CODE 

## Current status

As of mid-September, 2017, development of PDESolver's unsteady adjoint has been tabled for the time being.
The code is preserved, and is accessible with the `run_flag` of 660.
It runs with no errors, and produces a solution that qualititatively demonstrates properties of the correct unsteady adjoint.
However, a test sensitivity check does not pass.

Notation for this section:

* R is the residual
* A is the design variable: the amplitude of a sin function that is an exact solution to the advection equation: 
    \begin{equation}
    u = A \sin(-x + \omega t)
    \end{equation}
* J is the objective function:
    \begin{equation}
    J = \int_{\Gamma_1} u^2 d\Gamma_1
    \end{equation}
* \Gamma_1 is the right domain boundary in a square domain

Some notes about current status that may be of assistance to further development or debugging:

* dRdA makes physical sense, and FD and CS methods match
* dJdu FD, CS, and analytical derivative match
* J is verified by setting a polynomial solution for which SBP should be exact.
* loaded checkpoints match forward solve
* norm of Jacobian calculated from loaded checkpoint matches forward solve's
* time stepping bookkeeping in forward and reverse appears correct 
* Adjoint initial condition equation appears to match the below derivation, as far as code-reading can show
* While the test sensitivity check is incorrect at all time steps, 
  the fact that it is incorrect at the adjoint initial condition indicates that the 
  bug manifests itself before the main reverse-sweep time-stepping loop.

The test sensitivity check being performed is the comparison between these two derivatives:

\begin{equation}
\frac{d J}{d A} &= \frac{\partial J}{\partial u} \frac{\partial u}{\partial A} \\
\end{equation}

\begin{equation}
\frac{d J}{d A} &= \psi^T \left( - \frac{\partial R}{\partial A}\right)
\end{equation}


For the above, note that:
\begin{equation}
\frac{\partial J}{\partial A} = 0
\end{equation}


## Unsteady adjoint derivation
The unsteady adjoint derivation starts with the generic Lagrangian equation:

\begin{equation}
\mathcal{L}(u, \psi) = \psi^T R(u) + J(u)
\end{equation}

In the discrete context of CN, all of these variables are global-in-time.
That is, the adjoint vector contains the adjoint at time step 1 concatenated with 
  the adjoint at time step 2, and so on, until time step $n$.
Therefore, in this document we will rewrite the Lagrangian using bolded symbols to indicate 
  that a vector or matrix is global-in-time, as there will also be corresponding variables
  specific to a particular time step:

\begin{equation}
\boldsymbol{\mathcal{L}}(\boldsymbol{u}, \boldsymbol{\psi}) = \boldsymbol{\psi}^T \boldsymbol{R}(\boldsymbol{u}) + \boldsymbol{J}(\boldsymbol{u})
\end{equation}

The global-in-time residual discretized according to the Crank-Nicolson method is:

$\boldsymbol{R(\boldsymbol{u})} = \begin{bmatrix} u_1 - u_0 - \frac{\Delta t}{2} R(u_1) - \frac{\Delta t}{2} R(u_0) \\ u_2 - u_1 - \frac{\Delta t}{2} R(u_2) - \frac{\Delta t}{2} R(u_1) \\ \vdots \\ u_i - u_{i-1} - \frac{\Delta t}{2} R(u_i) - \frac{\Delta t}{2} R(u_{i-1}) \\ u_{i+1} - u_{i} - \frac{\Delta t}{2} R(u_{i+1}) - \frac{\Delta t}{2} R(u_{i}) \\ \vdots \\ u_n - u_{n-1} - \frac{\Delta t}{2} R(u_n) - \frac{\Delta t}{2} R(u_{n-1}) \end{bmatrix}$

The global-in-time adjoint vector is:

$\boldsymbol{\psi}^T = [\psi_1^T, \psi_2^T, \dots, \psi_i^T, \psi_{i+1}^T, \dots, \psi_n^T]$

Note that each time step's adjoint variable is a vector of length equal to the number of degrees of freedom in the mesh.
And finally, the global-in-time objective function vector is:

$\boldsymbol{J}^T = [J_1, J_2, \dots, J_i, J_{i+1}, \dots, J_n]$

Therefore, the full discrete Lagrangian is:

$\boldsymbol{\mathcal{L}}(\boldsymbol{u}, \boldsymbol{\psi}) = \boldsymbol{\psi}^T \boldsymbol{R(\boldsymbol{u})} + \boldsymbol{J}(\boldsymbol{u}) = \begin{bmatrix} \psi_1^T \left( u_1 - u_0 - \frac{\Delta t}{2} R(u_1) - \frac{\Delta t}{2} R(u_0) \right) \\ \psi_2^T \left( u_2 - u_1 - \frac{\Delta t}{2} R(u_2) - \frac{\Delta t}{2} R(u_1) \right) \\ \vdots \\ \psi_i^T \left( u_i - u_{i-1} - \frac{\Delta t}{2} R(u_i) - \frac{\Delta t}{2} R(u_{i-1}) \right) \\ \psi_{i+1}^T \left( u_{i+1} - u_{i} - \frac{\Delta t}{2} R(u_{i+1}) - \frac{\Delta t}{2} R(u_{i}) \right) \\ \vdots \\ \psi_n^T \left( u_n - u_{n-1} - \frac{\Delta t}{2} R(u_n) - \frac{\Delta t}{2} R(u_{n-1}) \right) \end{bmatrix} + \begin{bmatrix} J(u_1) \\ J(u_2) \\ \vdots \\ J(u_i) \\ J(u_{i+1}) \\ \vdots \\ J(u_n) \end{bmatrix}$

Taking the derivative of the Lagrangian with respect to the state at step $i$ yields, for values of i not equal to 0 or n:

$\frac{\partial \boldsymbol{L}}{\partial u_i} = \underbrace{\psi_i^T - \psi_i^T \frac{\Delta t}{2} \frac{\partial R(u_i)}{\partial u_i}}_{\text{contribution from }\boldsymbol{R}(u_i)} - \underbrace{\psi_{i+1}^T - \psi_{i+1}^T \frac{\Delta t}{2} \frac{\partial R(u_i)}{\partial u}}_{\text{contribution from }\boldsymbol{R}(u_{i+1})} + \frac{\partial J(u_i)}{\partial u_i}= 0^T$

Or, rearranging:

$\frac{\partial \boldsymbol{L}}{\partial u_i} = (\psi_i - \psi_{i+1}) - \frac{\Delta t}{2} \left( \frac{\partial R(u_i)}{\partial u_i} \right)^T (\psi_i + \psi_{i+1}) + \frac{\partial J(u_i)}{\partial u_i} = 0$

### Initial Condition

The derivative of the Lagrangian with respect to the state at the final step $i = n$ is:

$\frac{\partial \boldsymbol{L}}{\partial u_n} = \psi_n - \frac{\Delta t}{2} \left( \frac{\partial R(u_n)}{\partial u_n} \right)^T \psi_n + \frac{\partial J(u_n)}{\partial u_n} = 0$

Therefore, the value of the adjoint at time step n, which is the initial condition for the reverse sweep, is:

$\psi_n = \left( \left(I - \frac{\Delta t}{2} \frac{\partial R(u_n)}{\partial u_n} \right)^T \right)^{-1} \left( - \frac{\partial J(u_n)}{\partial u_n} \right)^T$


### Direct Solve

The method of performing a direct solve to advance the CN reverse sweep (as opposed to using Newton's method to converge each time step) starts with the restatement of the derivative of the Lagrangian at time step $i$:

$\frac{\partial \boldsymbol{L}}{\partial u_i} = \underbrace{\psi_i^T - \psi_i^T \frac{\Delta t}{2} \frac{\partial R(u_i)}{\partial u_i}}_{\text{contribution from }\boldsymbol{R}(u_i)} - \underbrace{\psi_{i+1}^T - \psi_{i+1}^T \frac{\Delta t}{2} \frac{\partial R(u_i)}{\partial u}}_{\text{contribution from }\boldsymbol{R}(u_{i+1})} + \frac{\partial J(u_i)}{\partial u_i}= 0^T$

Rearranging:

$\left[ \psi_i - \frac{\Delta t}{2} \left( \frac{\partial R(u_i)}{\partial u_i} \right)^T \psi_i \right] - \left[ \psi_{i+1} + \frac{\Delta t}{2} \left( \frac{\partial R(u_i)}{\partial u_i} \right)^T \psi_{i+1} \right] + \frac{\partial J(u_i)}{\partial u_i} = 0$

Grouping terms to isolate $\psi_i$:

$\left[ I - \frac{\Delta t}{2} \left( \frac{\partial R(u_i)}{\partial u_i} \right)^T \right] \psi_i = \left[ \psi_{i+1} + \frac{\Delta t}{2} \left( \frac{\partial R(u_i)}{\partial u_i} \right)^T \psi_{i+1} \right] - \frac{\partial J(u_i)}{\partial u_i}$

Solving for $\psi_i$:

$\psi_i = \left[ I - \frac{\Delta t}{2} \left( \frac{\partial R(u_i)}{\partial u_i} \right)^T \right]^{-1} \left( \left[ \psi_{i+1} + \frac{\Delta t}{2} \left( \frac{\partial R(u_i)}{\partial u_i} \right)^T \psi_{i+1} \right] - \frac{\partial J(u_i)}{\partial u_i} \right)$

Therefore, $\psi_i$ is a function of 1) the Jacobian of the primal solution at step $i$, which is loaded from checkpointed data, 2) the derivative of the objective function with respect to the state, at step $i$, and 3) the adjoint solution at time step $i+1$. 
The adjoint solution sweep is thus stepped backwards in time, starting at time step $n$.

### Checkpointing

Currently, all time steps are checkpointed. 
Eventually, Revolve will be implemented, for which a separate Julia package has been developed. 
See [here](http://dl.acm.org/citation.cfm?id=347846) for the publication discussing the Revolve algorithm.


### Global-in-time Jacobian

For reference, the structure of the global-in-time Jacobian is shown here.
It should never be formed except in the course of debugging very simple use cases, 
  but it can be helpful for visualizing the matrix form of CN for all space and time.

(Work in progress)



