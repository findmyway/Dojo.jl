using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

# ## setup
using Dojo
using IterativeLQR
using LinearAlgebra

# ## system
timestep = 0.05
gravity = -9.81
env = get_environment(:raiberthopper,
    representation=:maximal,
    timestep=timestep,
    gravity=gravity);

# ## visualizer
open(env.vis)

# ## dimensions
n = env.num_states
m = env.num_inputs

# ## states
z1 = raiberthopper_nominal_max()
zM = raiberthopper_offset_max(0.5, 0.5, 0.5)
zT = raiberthopper_offset_max(0.5, 0.5, 0.0)

# ## horizon
T = 21
Tm = convert(Int, floor((T - 1) / 2))

# ## model
dyn = IterativeLQR.Dynamics(
    (y, x, u, w) -> dynamics(y, env, x, u, w),
    (dx, x, u, w) -> dynamics_jacobian_state(dx, env, x, u, w, attitude_decompress=true),
    (du, x, u, w) -> dynamics_jacobian_input(du, env, x, u, w, attitude_decompress=true),
    n, n, m)

model = [dyn for t = 1:T-1]

# ## rollout
ū = [[0.0; 0.0; env.mechanism.bodies[1].m * env.mechanism.gravity * env.mechanism.timestep + 0.0 * randn(1)[1]] for t = 1:T-1]
x̄ = IterativeLQR.rollout(model, z1, ū)
open(env.vis)
visualize(env, x̄)

# ## objective
ot1 = (x, u, w) -> 1 * (transpose(x - zM) * Diagonal(vcat([[1.0 * ones(3); 0.01 * ones(3); 0.1 * ones(4); 0.01 * ones(3)] for i=1:2]...)) * (x - zM) + transpose(u) * Diagonal(1.0e-2 * [1.0; 1.0; 1.0]) * u)
ot2 = (x, u, w) -> 1 * (transpose(x - zT) * Diagonal(vcat([[1.0 * ones(3); 0.01 * ones(3); 0.1 * ones(4); 0.01 * ones(3)] for i=1:2]...)) * (x - zT) + transpose(u) * Diagonal(1.0e-2 * [1.0; 1.0; 1.0]) * u)
oT = (x, u, w) -> transpose(x - zT) * Diagonal(vcat([[1.0 * ones(3); 0.01 * ones(3); 0.1 * ones(4); 0.01 * ones(3)] for i=1:2]...)) * (x - zT)

ct1 = IterativeLQR.Cost(ot1, n, m)
ct2 = IterativeLQR.Cost(ot2, n, m)
cT = IterativeLQR.Cost(oT, n, 0)
obj = [[ct1 for t = 1:Tm]..., [ct2 for t = 1:Tm]..., cT]

# ## constraints
function goal(x, u, w)
    Δ = x - zT
    return [Δ[collect(1:6)]; Δ[collect(13 .+ (1:6))]]
end

cont = IterativeLQR.Constraint()
conT = IterativeLQR.Constraint(goal, n, 0)
cons = [[cont for t = 1:T-1]..., conT]

# ## solver
s = IterativeLQR.solver(model, obj, cons, 
    opts=IterativeLQR.Options(
        linesearch=:armijo,
        α_min=1.0e-5,
        obj_tol=1.0e-3,
        grad_tol=1.0e-3,
        con_tol=0.005,
        max_iter=100,
        max_al_iter=10,
        ρ_init=1.0,
        ρ_scale=10.0,
        verbose=true))

IterativeLQR.initialize_controls!(s, ū)
IterativeLQR.initialize_states!(s, x̄)

# ## solve
@time IterativeLQR.solve!(s)

# ## solution
x_sol, u_sol = IterativeLQR.get_trajectory(s)
@show IterativeLQR.eval_obj(s.m_data.obj.costs, s.m_data.x, s.m_data.u, s.m_data.w)
@show s.s_data.iter[1]
@show norm(goal(s.m_data.x[T], zeros(0), zeros(0)), Inf)

# ## visualize
visualize(env, [[x_sol[1] for t = 1:10]..., x_sol..., [x_sol[end] for t = 1:10]...])
