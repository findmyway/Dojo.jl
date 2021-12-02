# Utils
function module_dir()
    return joinpath(@__DIR__, "..", "..", "..")
end

# Activate package
using Pkg
Pkg.activate(module_dir())

using MeshCat
# Open visualizer
vis = Visualizer()
open(vis)

# Include new files
include(joinpath(module_dir(), "examples", "loader.jl"))

using IterativeLQR

# System
gravity = -9.81
Δt = 0.05
mech = getmechanism(:quadruped, Δt = Δt, g = gravity, cf = 1.5, damper = 10.0, spring = 0.0)
initialize!(mech, :quadruped, tran = [0,0,0.], v = [0.5,0,0.])
@elapsed storage = simulate!(mech, 0.05, record = true, solver = :mehrotra!, verbose = false)
visualize(mech, storage, vis = vis)


eqcs = collect(mech.eqconstraints)
eqcs
rot1 = eqcs[1].constraints[1]
rot1.spring_offset = srand(3)
length(rot1)

x0 = getMinState(mech)
setSpringOffset!(mech, x0)

# Dimensions
T = 20
n = minCoordDim(mech)
m = 12
d = 0
# Ref trajectory
xref = quadruped_trajectory(mech, r = 0.07, z = 0.26; Δx = -0.05, β = 1.0, N = Int(T/2), Ncycles = 40)
xref = quadruped_trajectory(mech, r = 0.08, z = 0.27; Δx = -0.08, β = 1.0, Δfront = 0.15, N = Int(T/2), Ncycles = 40)

zref = [min2max(mech, x) for x in xref]
storage = generate_storage(mech, zref)
visualize(mech, storage, vis = vis)
# visualizeMaxCoord(mech, min2max(mech, xref[1]), vis)



# PID control
Δt = 0.05
mech = getmechanism(:quadruped, Δt = Δt, g = -9.0, cf = 0.5, contact = true, spring = 100.0, damper = 2.0)
initialize!(mech, :quadruped)
setState!(mech, zref[1])

function controller!(mechanism, k)
	setSpringOffset!(mechanism, xref[k])
    return
end

@elapsed storage = simulate!(mech, 4.01, controller!, record = true, solver = :mehrotra!, verbose = false)
visualize(mech, storage, vis = vis)


mech = getmechanism(:pendulum, g = 0.0, spring = 20.0, damper = 1.0, spring_offset = -0.9*sones(1))
initialize!(mech, :pendulum, ϕ1 = pi/8)
function controller!(mechanism, k)
	setSpringOffset!(mechanism, [π])
    return
end
@elapsed storage = simulate!(mech, 8.0, controller!, record = true, solver = :mehrotra!, verbose = false)
visualize(mech, storage, vis = vis)




# qa = one(UnitQuaternion)
# qb = UnitQuaternion(RotX(π/8))
# joint = collect(mech.eqconstraints)[1].constraints[2]
# A = nullspacemat(joint)
# Aᵀ = zerodimstaticadjoint(A)
# joint.spring_offset = pi/8 * sones(1)
# distance = A * gc(joint, qa, qb) .- joint.spring_offset
#
# gc(joint, qa, qb)
# θ = rotation_vector(qb * inv(qa))[1]
# qr_ = UnitQuaternion(rand(4)...)
# Δ0 = Vmat(qr_) * qr_.w
# Δ1 = rotation_vector(qr_)
#
# aa = Aᵀ * joint.spring_offset # axis angle
# θ = norm(aa)
# qoff = UnitQuaternion(cos(θ/2), 1/2 * sinc(θ/(2π)) * aa) # quaternion
# offset = Vmat(qoff) * qoff.w
# distance = A * (gc(joint, qb) .- offset)
# gc(joint, qb)



# x0 = getMinState(mech)
# x0[1:12]
# x0[13:18]
# x0[1:12]
# x0[13:end] .= 0.0
# x0[13] = pi/4
# z0 = min2max(mech, x0)
# mech = getmechanism(:quadruped, Δt = 0.01, g = 0.0, spring = 10.0, damper = 1.0, contact = false)
# initialize!(mech, :quadruped)
# x1 = getMinState(mech)

mech = getmechanism(:quadruped, Δt = 0.01, g = 0.0, spring = 10.0, damper = 1.0, contact = true)
initialize!(mech, :quadruped)
z0 = min2max(mech, zref[1])
setState!(mech, z0)

visualizeMaxCoord(mech, z0, vis)
function controller!(mechanism, k)
	setSpringOffset!(mechanism, zref[1])
    return
end
@elapsed storage = simulate!(mech, 4.01, controller!, record = true, solver = :mehrotra!, verbose = false)
visualize(mech, storage, vis = vis)



a = 10
a = 10
a = 10
a = 10
a = 10
a = 10
a = 10

# Reference control
function gravity_compensation(mechanism::Mechanism)
    # only works with revolute joints for now
    nu = controldim(mechanism)
    u = zeros(nu)
    off  = 0
    for eqc in mechanism.eqconstraints
        nu = controldim(eqc)
        if eqc.parentid != nothing
            body = getbody(mechanism, eqc.parentid)
            rot = eqc.constraints[2]
            A = Matrix(nullspacemat(rot))
            Fτ = springforce(mechanism, eqc, body)
            F = Fτ[1:3]
            τ = Fτ[4:6]
            u[off .+ (1:nu)] = -A * τ
        else
            @warn "need to treat the joint to origin"
        end
        off += nu
    end
    return u
end

mech = getmechanism(:quadruped, Δt = Δt, g = gravity, cf = 1.5, damper = 1000.0, spring = 30.0)
initialize!(mech, :quadruped)
@elapsed storage = simulate!(mech, 0.05, record = true, solver = :mehrotra!, verbose = false)
visualize(mech, storage, vis = vis)
ugc = gravity_compensation(mech)

mech = getmechanism(:quadruped, Δt = Δt, g = gravity, cf = 1.5, damper = 5.0, spring = 0.0)
u_control = ugc[6 .+ (1:12)]
u_mask = [zeros(12,6) I(m)]

z = [copy(z1)]
for t = 1:5
    znext = max2min(mech, simon_step!(mech, min2max(mech, z[end]), 0u_mask'*u_control))
    push!(z, znext)
end
storage = generate_storage(mech, [min2max(mech, zi) for zi in z])
visualize(mech, storage, vis = vis)


# Model
function fd(y, x, u, w)
	z = simon_step!(mech, min2max(mech, x), u_mask'*u, ϵ = 3e-4, btol = 3e-4, undercut = 1.5, verbose = false)
	y .= copy(max2min(mech, z))
end

function fdx(fx, x, u, w)
	fx .= copy(getMinGradients!(mech, min2max(mech, x), u_mask'*u, ϵ = 3e-4, btol = 3e-4, undercut = 1.5, verbose = false)[1])
end

function fdu(fu, x, u, w)
	∇u = copy(getMinGradients!(mech, min2max(mech, x), u_mask'*u, ϵ = 3e-4, btol = 3e-4, undercut = 1.5, verbose = false)[2])
	fu .= ∇u * u_mask'
end


# Time
h = mech.Δt
dyn = Dynamics(fd, fdx, fdu, n, n, m, d)
model = [dyn for t = 1:T-1]

# Initial conditions, controls, disturbances
ū = [0.25u_control for t = 1:T-1]
w = [zeros(d) for t = 1:T-1]

# Rollout
x̄ = rollout(model, z1, ū, w)
storage = generate_storage(mech, [min2max(mech, x) for x in x̄])
visualize(mech, storage; vis = vis)

# Objective
qt = [0.3; 0.05; 0.05; 0.01 * ones(3); 0.01 * ones(3); 0.01 * ones(3); fill([0.2, 0.001], 12)...]

ots = [(x, u, w) -> transpose(x - zref[t]) * Diagonal(Δt * qt) * (x - zref[t]) + transpose(u) * Diagonal(Δt * 0.01 * ones(m)) * u for t = 1:T-1]
oT = (x, u, w) -> transpose(x - zref[end]) * Diagonal(Δt * qt) * (x - zref[end])

cts = Cost.(ots, n, m, d)
cT = Cost(oT, n, 0, 0)
obj = [cts..., cT]

# Constraints
function goal(x, u, w)
	# Δ = x - zT
    Δ = x - zref[end]
    return Δ[[1:3; 12 .+ (1:2:24)]]
end

cont = Constraint()
conT = Constraint(goal, n, 0)
cons = [[cont for t = 1:T-1]..., conT]

prob = problem_data(model, obj, cons)
initialize_controls!(prob, ū)
initialize_states!(prob, x̄)

# Solve
IterativeLQR.constrained_ilqr_solve!(prob,
    verbose = true,
	linesearch=:armijo,
    α_min=1.0e-5,
    obj_tol=1.0e-3,
    grad_tol=1.0e-3,
    max_iter=100,
    max_al_iter=5,
    ρ_init=1.0,
    ρ_scale=3.0)

x_sol, u_sol = get_trajectory(prob)
storage = generate_storage(mech, [min2max(mech, x) for x in x_sol])
visualize(mech, storage, vis = vis)





eqcs = collect(mech.eqconstraints)
rot1 = eqcs[1].constraints[2]
rot2 = eqcs[2].constraints[2]
A1 = nullspacemat(rot1)
A2 = nullspacemat(rot2)
A1 * srand(3)
A2 * srand(3)
