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
mech = getmechanism(:pendulum, Δt = 0.01, g = -9.81)
initialize!(mech, :pendulum, ϕ1 = 0.7)

jointid = mech.joints[1].id
angles = zeros(1)
function controller!(mechanism, k)
    j1 = get_joint_constraint(mechanism, jointid)
    θ1 = minimal_coordinates(mechanism, j1)[1]
    dθ1 = minimal_velocities(mechanism, j1)[1]
    u1 = (100.0*(angles[1]-θ1) + 5.0*(0-dθ1)) * mechanism.Δt
    set_input!(j1, SA[u1])
    return
end

j1 = mech.joints[1]
jt1 = j1.constraints[1]
jr1 = j1.constraints[2]
j1.isdamper = false
j1.isspring = false

jr1.spring = 0.0 * 1e4
jr1.damper = 0.0 * 1e4
mech.joints[1].isdamper
mech.joints[1].constraints[2].damper

storage = simulate!(mech, 10.0, record = true, solver = :mehrotra!)
# forcedstorage = simulate!(mech, 0.1, controller!, record = true, solver = :mehrotra!)
# plot(hcat(Vector.(storage.x[1])...)')
# plot(hcat(Vector.(forcedstorage.x[1])...)')
# plot(hcat([[q.w, q.x, q.y, q.z] for q in storage.q[1]]...)')
# plot(hcat([[q.w, q.x, q.y, q.z] for q in forcedstorage.q[1]]...)')
# plot(hcat(Vector.(storage.v[1])...)')
# plot(hcat(Vector.(forcedstorage.v[1])...)')
# plot(hcat(Vector.(storage.ω[1])...)')
# plot(hcat(Vector.(forcedstorage.ω[1])...)')

visualize(mech, storage, vis = vis)
# visualize(mech, forcedstorage, vis = vis)

################################################################################
# Differentiation
################################################################################

# Set data
data = get_data(mech)
set_data!(mech, data)
sol = get_solution(mech)
Nb = length(collect(mech.bodies))
attjac = attitude_jacobian(data, Nb)

# IFT
datamat = full_data_matrix(deepcopy(mech))
datamat_ = full_data_matrix(deepcopy(mech), attjac=false)
solmat = full_matrix(mech.system)
sensi = - (solmat \ datamat)

# finite diff
fd_datamat = finitediff_data_matrix(deepcopy(mech), data, sol, δ = 1e-5) * attjac
fd_datamat_ = finitediff_data_matrix(deepcopy(mech), data, sol, δ = 1e-5)
@test norm(fd_datamat + datamat, Inf) < 1e-8
@test norm(fd_datamat_ + datamat_, Inf) < 1e-8


norm((fd_datamat_ + datamat_)[6:11, 1:3], Inf)
norm((fd_datamat_ + datamat_)[6:11, 7:10], Inf)
norm((fd_datamat_ + datamat_)[6:11, 11:13], Inf)
norm((fd_datamat_ + datamat_)[6:11, 14:14], Inf)

(fd_datamat_)[6:11, 7:10]
-(datamat_)[6:11, 7:10]

# plot(Gray.(abs.(datamat)))
# plot(Gray.(abs.(fd_datamat)))

norm(datamat[1:5, 1:13] + fd_datamat[1:5, 1:13])
norm(datamat_[1:5, 1:14] + fd_datamat_[1:5, 1:14])

norm(datamat_[6:11, 1:14] + fd_datamat_[6:11, 1:14])

datamat[6:11, 1:13]
-fd_datamat[6:11, 1:13]
norm(datamat[6:11, 1:3] + fd_datamat[6:11, 1:3])
norm(datamat[6:11, 4:6] + fd_datamat[6:11, 4:6])
norm(datamat[6:11, 7:9] + fd_datamat[6:11, 7:9])
norm(datamat[6:11, 10:12] + fd_datamat[6:11, 10:12])
norm(datamat[6:11, 13] + fd_datamat[6:11, 13])

datamat[6:11, 10:12]
fd_datamat[6:11, 10:12]

fd_solmat = finitediff_sol_matrix(mech, data, sol, δ = 1e-5)
@test norm(fd_solmat + solmat, Inf) < 1e-8
# plot(Gray.(abs.(solmat)))
# plot(Gray.(abs.(fd_solmat)))
norm(fd_solmat + solmat, Inf)


fd_sensi = finitediff_sensitivity(mech, data, δ = 1e-5, ϵr = 1e-14, ϵb = 1e-14) * attjac
@test norm(fd_sensi - sensi) / norm(fd_sensi) < 3e-3
plot(Gray.(sensi))
plot(Gray.(fd_sensi))
