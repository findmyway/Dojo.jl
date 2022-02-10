# Utils
function module_dir()
    return joinpath(@__DIR__, "..", "..")
end

# Activate package
using Pkg
Pkg.activate(module_dir())

# Load packages
using Plots
using Random
using MeshCat

# Open visualizer
vis = Visualizer()
open(vis)

# Include new files
include(joinpath(module_dir(), "examples", "loader.jl"))

# Build mechanism
mech = getmechanism(:atlas, timestep = 0.01, g = -9.81, cf = 0.8, contact = true)
initialize!(mech, :atlas, tran = [0,0,0.99], rot = [0.,0,0])
for (i,joint) in enumerate(mech.joints)
    jt = joint.translational
    jr = joint.rotational
    joint.isdamper = true #false
    joint.isspring = false #false

    jt.spring = 1/i * 0.0 * 1e-0 .* sones(3)[1]# 1e4
    jt.damper = 1/i * 0.0 * 1e-0 .* sones(3)[1]# 1e4
    jr.spring = 1/i * 0.0 * 1e-0 .* sones(3)[1]# 1e4
    jr.damper = 1/i * 1.0 * 1e+2 .* sones(3)[1]# 1e4

    mech.joints[1].isspring
    mech.joints[1].isdamper
    mech.joints[1].constraints[2].damper
end

bodies = collect(Body, mech.bodies)
eqcs = collect(JointConstraint, mech.joints)
contacts = collect(ContactConstraint, mech.contacts)
bodies = [mech.bodies[i] for i = 32:62]
eqcs = [mech.joints[i] for i = 1:31]
teqcs = [eqcs[1]; [addtorque(mech, eqc, spring = 1e2, damper = 1e2) for eqc in eqcs[2:end]]]
contacts = [mech.contacts[i] for i = 63:70]

tmech = Mechanism(mech.origin, bodies, teqcs, contacts, timestep = 0.01, g = -9.81)

function addtorque(mech::Mechanism, eqc::JointConstraint; spring = 0.0, damper = 0.0)
    pbody = get_body(mech, eqc.parentid)
    cbody = get_body(mech, eqc.childids[1]) # TODO assume onyly one children
    tid = findfirst(x -> typeof(x) <: Translational, eqc.constraints)
    rid = findfirst(x -> typeof(x) <: Rotational, eqc.constraints)
    tra = eqc.constraints[tid] # get translational joint
    rot = eqc.constraints[rid] # get rotational joint
    p1, p2 = tra.vertices
    axis = [rot.V3[1], rot.V3[2], rot.V3[3]]
    eqct = JointConstraint(TorqueRevolute(pbody, cbody, axis; spring = spring, damper = damper, p1 = p1, p2 = p2))
    return eqct
end


# PD control law
nu = sum([control_dimension(eqc, floatingbase = false) for eqc in collect(mech.joints)])
angles = [minimal_coordinates(mech, joint)[1] for joint in collect(mech.joints)[2:end]]
δangles = zeros(nu)
ind = 23
# δangles[ind] += π/2
angles += δangles

function controller!(mechanism, k)
    for (i,joint) in enumerate(collect(mechanism.joints)[2:end])
        if control_dimension(joint) == 1
            # θ = minimal_coordinates(mechanism, joint)[1]
            # dθ = minimal_velocities(mechanism, joint)[1]
            # u = 3e+2 * (angles[i] - θ) #+ 5e-2 * (0 - dθ)
            # u = clamp(u, -150.0, 150.0) * mechanism.timestep
            # if joint.name ∈ ("r_leg_akx", "r_leg_aky", "l_leg_akx", "l_leg_aky", "back_bkx", "back_bky", "back_bkz")
            #     u = 1e+2 * (angles[i] - θ) #+ 5e-2 * (0 - dθ)
            #     u = clamp(u, -100.0, 100.0) * mechanism.timestep
            # end
            u = 0.0
            set_input!(joint, SA[u])
        end
    end
    return
end

# forcedstorage = simulate!(tmech, 2.5, controller!, record = true, solver = :mehrotra!)
# @elapsed forcedstorage = simulate!(tmech, 2.5, controller!, record = true, solver = :mehrotra!)
# @elapsed forcedstorage = simulate!(mech, 1.5, controller!, record = true, solver = :mehrotra!)
# @profiler forcedstorage = simulate!(tmech, 0.5, controller!, record = true, solver = :mehrotra!)
# visualize(tmech, forcedstorage, vis = vis)

@elapsed forcedstorage = simulate!(mech, 0.4, controller!, record = true, solver = :mehrotra!, verbose = true)
visualize(mech, forcedstorage, vis = vis)



gains = zeros(30, 2)
gains[23,:] = [1e-1, 5e-2]

nams = [eqc.name for eqc in mech.joints]

nams[1:10]
nams[11:20]
nams[21:30]

# Set data
Nb = length(mech.bodies)
data = get_data(mech)
set_data!(mech, data)
sol = get_solution(mech)
attjac = attitude_jacobian(data, Nb)

# IFT
datamat = full_data_matrix(mech)
solmat = full_matrix(mech.system)
sensi = - (solmat \ datamat)

# finite diff
fd_datamat = finitediff_data_matrix(mech, data, sol, δ = 1e-5) * attjac
@test norm(fd_datamat + datamat, Inf) < 1e-6
plot(Gray.(abs.(1e10 .* datamat)))
plot(Gray.(abs.(fd_datamat)))

fd_solmat = finitediff_sol_matrix(mech, data, sol, δ = 1e-5)
@test norm(fd_solmat + solmat, Inf) < 1e-8
plot(Gray.(abs.(1e10 * solmat)))
plot(Gray.(abs.(fd_solmat)))

fd_sensi = finitediff_sensitivity(mech, data, δ = 1e-5, ϵ = 1e-14) * attjac
@test norm(fd_sensi - sensi) / norm(fd_sensi) < 8e-3
plot(Gray.(1e10 .* sensi))
plot(Gray.(fd_sensi))
