mutable struct JointConstraint{T,N,Nc,Cs} <: Constraint{T,N}
    id::Int64
    name::Symbol
    isspring::Bool
    isdamper::Bool

    constraints::Cs
    parentid::Union{Int64,Nothing}
    childids::SVector{Nc,Int64}
    inds::SVector{Nc,SVector{2,Int64}} # indices for minimal coordinates, assumes joints # Nc = 2 THIS IS SPECIAL CASED

    λsol::Vector{SVector{N,T}}

    function JointConstraint(data; name::Symbol=Symbol("joint_" * randstring(4)))
        jointdata = Tuple{Joint,Int64,Int64}[]
        for info in data
            push!(jointdata, info)
        end

        T = getT(jointdata[1][1])

        isspring = false
        isdamper = false
        parentid = jointdata[1][2]
        childids = Int64[]
        constraints = Joint{T}[]
        inds = Vector{Int64}[]
        N = 0
        for set in jointdata
            set[1].spring != 0 && (isspring = true)
            set[1].damper != 0 && (isdamper = true)

            push!(constraints, set[1])
            @assert set[2] == parentid
            push!(childids, set[3])

            Nλ = λlength(set[1])
            Nset = ηlength(set[1])
            if isempty(inds)
                push!(inds, [1;3-Nλ])
            else
                push!(inds, [last(inds)[2]+1; last(inds)[2]+3-Nλ])
            end
            N += Nset
        end
        constraints = Tuple(constraints)
        Nc = length(constraints)
        λsol = [zeros(T, N) for i=1:2]
        return new{T,N,Nc,typeof(constraints)}(getGlobalID(), name, isspring, isdamper, constraints, parentid, childids, inds, λsol)
    end
end

function set_position(mechanism, joint::JointConstraint, xθ; iter::Bool=true)
    if !iter
        _set_position(mechanism, joint, xθ)
    else
        currentvals = minimal_coordinates(mechanism)
        _set_position(mechanism, joint, xθ)
        for id in recursivedirectchildren!(mechanism.system, joint.id)
            node = get_node(mechanism, id)
            if node isa JointConstraint
                _set_position(mechanism, node, currentvals[id])
            end
        end
    end

    return
end
# TODO currently assumed constraints are in order and only joints which is the case unless very low level constraint setting
function _set_position(mechanism, joint::JointConstraint{T,N,Nc}, xθ) where {T,N,Nc}
    Nλ = 0
    for (i, element) in enumerate(joint.constraints)
        Nλ += λlength(element)
    end
    @assert length(xθ)==3*Nc-Nλ
    n = Int64(Nc/2)
    # @show Nc
    body1 = get_body(mechanism, joint.parentid)
    for i = 1:n
        body2 = get_body(mechanism, joint.childids[i])
        Δx = get_position_delta(joint.constraints[i], body1, body2, xθ[SUnitRange(joint.inds[i][1], joint.inds[i][2])]) # in body1's frame
        Δq = get_position_delta(joint.constraints[i+1], body1, body2, xθ[SUnitRange(joint.inds[i+1][1], joint.inds[i+1][2])]) # in body1's frame

        p1, p2 = joint.constraints[i].vertices
        set_position(body1, body2; p1=p1, p2=p2, Δx=Δx, Δq=Δq)
    end
    return
end

function set_velocity!(mechanism, joint::JointConstraint{T,N,Nc}, vω) where {T,N,Nc}
    Nλ = 0
    for (i, element) in enumerate(joint.constraints)
        Nλ += λlength(element)
    end
    # vω is already in body1 frame
    @assert length(vω)==3*Nc-Nλ
    n = Int64(Nc/2)
    body1 = get_body(mechanism, joint.parentid)
    for i = 1:n
        body2 = get_body(mechanism, joint.childids[i])
        Δv = get_velocity_delta(joint.constraints[i], body1, body2, vω[SUnitRange(joint.inds[i][1], joint.inds[i][2])]) # projection in body1 frame
        Δω = get_velocity_delta(joint.constraints[i+1], body1, body2, vω[SUnitRange(joint.inds[i+1][1], joint.inds[i+1][2])]) # projection in body1 frame
        p1, p2 = joint.constraints[i].vertices
        set_velocity!(body1, body2; p1=p1, p2=p2, Δv=Δv, Δω=Δω)
    end
    return
end

function set_input!(joint::JointConstraint{T,N,Nc}, Fτ::AbstractVector) where {T,N,Nc}
    @assert length(Fτ)==control_dimension(joint)
    for i = 1:Nc
        r_idx = SUnitRange(joint.inds[i][1], joint.inds[i][2])
        length(r_idx) == 0 && continue
        set_input!(joint.constraints[i], Fτ[SUnitRange(joint.inds[i][1], joint.inds[i][2])])
    end
    return
end

function add_force!(joint::JointConstraint{T,N,Nc}, Fτ::AbstractVector) where {T,N,Nc}
    @assert length(Fτ)==control_dimension(joint)
    for i = 1:Nc
        add_force!(joint.constraints[i], Fτ[SUnitRange(joint.inds[i][1], joint.inds[i][2])])
    end
    return
end

"""
    minimal_coordinates(mechanism, jointonstraint)

Gets the minimal coordinates of joint `jointonstraint`.
"""
@generated function minimal_coordinates(mechanism, joint::JointConstraint{T,N,Nc}) where {T,N,Nc}
    vec = [:(minimal_coordinates(joint.constraints[$i], get_body(mechanism, joint.parentid), get_body(mechanism, joint.childids[$i]))) for i = 1:Nc]
    return :(svcat($(vec...)))
end

@generated function minimal_velocities(mechanism, joint::JointConstraint{T,N,Nc}) where {T,N,Nc}
    vec = [:(minimal_velocities(joint.constraints[$i], get_body(mechanism, joint.parentid), get_body(mechanism, joint.childids[$i]))) for i = 1:Nc]
    return :(svcat($(vec...)))
end

@inline function impulses!(mechanism, body::Body, joint::JointConstraint)
    body.state.d -= impulse_map(mechanism, joint, body) * joint.λsol[2]
    joint.isspring && (body.state.d -= apply_spring(mechanism, joint, body))
    joint.isdamper && (body.state.d -= apply_damper(mechanism, joint, body))
    return
end

@inline function impulses_jacobian_velocity!(mechanism, body::Body, joint::JointConstraint{T,N,Nc}) where {T,N,Nc}
    # @warn "maybe need some work"
    if body.id == joint.parentid
        impulses_jacobian_parent!(mechanism, body, joint)
    elseif body.id ∈ joint.childids
        impulses_jacobian_child!(mechanism, body, joint)
    else
        error()
    end
    return
end

function impulses_jacobian_parent!(mechanism, pbody::Body, joint::JointConstraint{T,N,Nc}) where {T,N,Nc}
    timestep = mechanism.timestep
    _, _, q2, ω2 = current_configuration_velocity(pbody.state)
    M = integrator_jacobian_velocity(q2, ω2, timestep)

    off = 0
    for i in 1:Nc
        element = joint.constraints[i]
        Aᵀ = zerodimstaticadjoint(constraint_mask(element))
        Nj = length(element)
        cbody = get_body(mechanism, joint.childids[i])
        joint.isspring && (pbody.state.D -= spring_parent_jacobian_velocity_parent(element, pbody, cbody, timestep))
        joint.isdamper && (pbody.state.D -= damper_parent_jacobian_velocity_parent(element, pbody, cbody, timestep))
        off += Nj
    end
    return nothing
end

function impulses_jacobian_child!(mechanism, cbody::Body, joint::JointConstraint{T,N,Nc}) where {T,N,Nc}
    timestep = mechanism.timestep
    x2, v2, q2, ω2 = current_configuration_velocity(cbody.state)
    M = integrator_jacobian_velocity(q2, ω2, timestep)

    off = 0
    for i in 1:Nc
        if joint.childids[i] == cbody.id
            element = joint.constraints[i]
            Aᵀ = zerodimstaticadjoint(constraint_mask(element))
            Nj = length(element)
            pbody = get_body(mechanism, joint.parentid)
            joint.isspring && (cbody.state.D -= spring_child_jacobian_velocity_child(element, pbody, cbody, timestep))
            joint.isdamper && (cbody.state.D -= damper_child_configuration_velocity_child(element, pbody, cbody, timestep))
        end
    end
    return nothing
end

@generated function constraint(mechanism, joint::JointConstraint{T,N,Nc,Cs}) where {T,N,Nc,Cs}
    vec = [:(constraint(joint.constraints[$i], get_body(mechanism, joint.parentid), get_body(mechanism, joint.childids[$i]), joint.λsol[2][λindex(joint,$i)], mechanism.timestep)) for i = 1:Nc]
    return :(svcat($(vec...)))
end

@inline function apply_spring(mechanism, joint::JointConstraint, body::Body; unitary::Bool=false)
    body.id == joint.parentid ? (return spring_parent(mechanism, joint, body, unitary=unitary)) : (return spring_child(mechanism, joint, body, unitary=unitary))
end

@inline function apply_damper(mechanism, joint::JointConstraint, body::Body; unitary::Bool=false)
    body.id == joint.parentid ? (return damper_parent(mechanism, joint, body, unitary=unitary)) : (return damper_child(mechanism, joint, body, unitary=unitary))
end

@inline function off_diagonal_jacobians(mechanism, body::Body{T}, joint::JointConstraint{T,N}) where {T,N}
    return -impulse_map(mechanism, joint, body), constraint_jacobian_configuration(mechanism, joint, body) * integrator_jacobian_velocity(body, mechanism.timestep)
end

@inline function off_diagonal_jacobians(mechanism, joint::JointConstraint{T,N}, body::Body{T}) where {T,N}
    return constraint_jacobian_configuration(mechanism, joint, body) * integrator_jacobian_velocity(body, mechanism.timestep), -impulse_map(mechanism, joint, body)
end

@generated function impulse_map_parent(mechanism, joint::JointConstraint{T,N,Nc}, body::Body) where {T,N,Nc}
    vec = [:(impulse_map_parent(joint.constraints[$i], body, get_body(mechanism, joint.childids[$i]), joint.childids[$i], joint.λsol[2][λindex(joint,$i)], mechanism.timestep)) for i = 1:Nc]
    return :(hcat($(vec...)))
end

@generated function impulse_map_child(mechanism, joint::JointConstraint{T,N,Nc}, body::Body) where {T,N,Nc}
    vec = [:(impulse_map_child(joint.constraints[$i], get_body(mechanism, joint.parentid), body, joint.childids[$i], joint.λsol[2][λindex(joint,$i)], mechanism.timestep)) for i = 1:Nc]
    return :(hcat($(vec...)))
end

@generated function constraint_jacobian_configuration(mechanism, joint::JointConstraint{T,N,Nc}) where {T,N,Nc}
    vec = [:(constraint_jacobian_configuration(joint.constraints[$i], joint.λsol[2][λindex(joint,$i)])) for i = 1:Nc]
    return :(cat($(vec...), dims=(1,2)))
end

@generated function constraint_jacobian_parent(mechanism, joint::JointConstraint{T,N,Nc}, body::Body) where {T,N,Nc}
    vec = [:(constraint_jacobian_parent(joint.constraints[$i], body, get_body(mechanism, joint.childids[$i]), joint.childids[$i], joint.λsol[2][λindex(joint,$i)], mechanism.timestep)) for i = 1:Nc]
    return :(vcat($(vec...)))
end

@generated function constraint_jacobian_child(mechanism, joint::JointConstraint{T,N,Nc,Cs}, body::Body) where {T,N,Nc,Cs}
    vec = [:(constraint_jacobian_child(joint.constraints[$i], get_body(mechanism, joint.parentid), body, joint.childids[$i], joint.λsol[2][λindex(joint,$i)], mechanism.timestep)) for i = 1:Nc]
    return :(vcat($(vec...)))
end

@inline function spring_parent(mechanism, joint::JointConstraint{T,N,Nc}, body::Body; unitary::Bool=false) where {T,N,Nc}
    vec = szeros(T,6)
    for i=1:Nc
        vec += spring_parent(joint.constraints[i], body, get_body(mechanism, joint.childids[i]), mechanism.timestep, joint.childids[i], unitary=unitary)
    end
    return vec
end

@inline function spring_child(mechanism, joint::JointConstraint{T,N,Nc}, body::Body; unitary::Bool=false) where {T,N,Nc}
    vec = szeros(T,6)
    for i=1:Nc
        vec += spring_child(joint.constraints[i], get_body(mechanism, joint.parentid), body, mechanism.timestep, joint.childids[i], unitary=unitary)
    end
    return vec
end

@inline function damper_parent(mechanism, joint::JointConstraint{T,N,Nc}, body::Body; unitary::Bool=false) where {T,N,Nc}
    vec = szeros(T,6)
    for i=1:Nc
        vec += damper_parent(joint.constraints[i], body, get_body(mechanism, joint.childids[i]), mechanism.timestep, joint.childids[i], unitary=unitary)
    end
    return vec
end

@inline function damper_child(mechanism, joint::JointConstraint{T,N,Nc}, body::Body; unitary::Bool=false) where {T,N,Nc}
    vec = szeros(T,6)
    for i=1:Nc
        vec += damper_child(joint.constraints[i], get_body(mechanism, joint.parentid), body, mechanism.timestep, joint.childids[i], unitary=unitary)
    end
    return vec
end

@inline function input_jacobian_control(mechanism, joint::JointConstraint{T,N,Nc}, body::Body) where {T,N,Nc}
    body.id == joint.parentid ? (return input_jacobian_control_parent(mechanism, joint, body)) : (return input_jacobian_control_child(mechanism, joint, body))
end

@generated function input_jacobian_control_parent(mechanism, joint::JointConstraint{T,N,Nc}, body::Body) where {T,N,Nc}
    vec = [:(input_jacobian_control_parent(joint.constraints[$i], body, get_body(mechanism, joint.childids[$i]), mechanism.timestep, joint.childids[$i])) for i = 1:Nc]
    return :(hcat($(vec...)))
end

@generated function input_jacobian_control_child(mechanism, joint::JointConstraint{T,N,Nc}, body::Body) where {T,N,Nc}
    vec = [:(input_jacobian_control_child(joint.constraints[$i], get_body(mechanism, joint.parentid), body, mechanism.timestep, joint.childids[$i])) for i = 1:Nc]
    return :(hcat($(vec...)))
end

@inline function apply_input!(joint::JointConstraint{T,N,Nc}, mechanism, clear::Bool=true) where {T,N,Nc}
    for i=1:Nc
        apply_input!(joint.constraints[i], get_body(mechanism, joint.parentid), get_body(mechanism, joint.childids[i]), mechanism.timestep, clear)
    end
    return
end

function set_spring_damper_values!(joints, spring, damper)
    i = 1
    for joint in joints
        joint.parentid === nothing && continue
        k = (length(spring) > 1) ? spring[i] : spring
        b = (length(damper) > 1) ? damper[i] : damper
        joint.isspring = k > 0.0
        joint.isdamper = b > 0.0
        for element in joint.constraints
            element.spring = max(0.0, k)
            element.damper = max(0.0, b)
        end
        i += 1
    end
    return joints
end

@inline function impulse_map(mechanism, constraint::Constraint, body::Body)
    if body.id == constraint.parentid
        return impulse_map_parent(mechanism, constraint, body)
    else
        return impulse_map_child(mechanism, constraint, body)
    end
end

@inline function constraint_jacobian_configuration(mechanism, constraint::Constraint, body::Body)
    body.id == constraint.parentid ? (return constraint_jacobian_parent(mechanism, constraint, body)) : (return constraint_jacobian_child(mechanism, constraint, body))
end

function λindex(joint::JointConstraint{T,N,Nc,Cs}, i::Int) where {T,N,Nc,Cs}
    s = 0
    for j = 1:i-1
        element = joint.constraints[j]
        s += ηlength(element)
    end
    λindex(joint.constraints[i], s) # to be allocation free
end

function reset!(joint::JointConstraint{T,N,Nc,Cs}; scale::T=1.0) where {T,N,Nc,Cs}
    λ = []
    for (i, element) in enumerate(joint.constraints)
        Nλ = λlength(element)
        Nb = blength(element)
        push!(λ, [scale * sones(2Nb); szeros(Nλ)])
    end
    joint.λsol[1] = vcat(λ...)
    joint.λsol[2] = vcat(λ...)
    return
end
