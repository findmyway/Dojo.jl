################################################################################
# Dimension
################################################################################
# Mechanism
data_dim(mechanism::Mechanism) = sum(data_dim.(mechanism.joints)) +
    sum(data_dim.(mechanism.bodies)) + sum(data_dim.(mechanism.contacts))
# Eqconstraints
data_dim(eqc::JointConstraint) = 2 + sum(data_dim.(eqc.constraints)) # [utra, urot, spring, damper, traapply_springoffset, rotapply_springoffset]
data_dim(joint::Rotational{T,Nλ,Nb,N,Nb½,N̄λ}) where {T,Nλ,Nb,N,Nb½,N̄λ} = 2N̄λ # [u, spring, damper, spring_offset]
data_dim(joint::Translational{T,Nλ,Nb,N,Nb½,N̄λ}) where {T,Nλ,Nb,N,Nb½,N̄λ} = 2N̄λ # [u, spring, damper, spring_offset]
# Body
data_dim(body::Body) = 19 # 1+6+6+6 [m,flat(J),x1,q1,x2,q2] with attjac
# Injoints
data_dim(ineqc::ContactConstraint) = sum(data_dim.(ineqc.constraints))
data_dim(bound::NonlinearContact) = 7 # [cf, p, offset]
data_dim(bound::LinearContact) = 7 # [cf, p, offset]
data_dim(bound::ImpactContact) = 6 # [p, offset]


################################################################################
# Attitude Jacobian
################################################################################
# Mechanism
function data_attitude_jacobian(mechanism::Mechanism)
	attjacs = [data_attitude_jacobian.(mechanism.joints);
		data_attitude_jacobian.(mechanism.bodies);
		data_attitude_jacobian.(mechanism.contacts)]
	attjac = cat(attjacs..., dims=(1,2))
	return attjac
end
# Eqconstraints
function data_attitude_jacobian(eqc::JointConstraint)
	return I(data_dim(eqc))
end
# Body
function data_attitude_jacobian(body::Body)
	# [m,flat(J),x1,q1,x2,q2]
	x1, q1 = previous_configuration(body.state)
	x2, q2 = current_configuration(body.state)
	attjac = cat(I(1+6+3), G(vector(q1)), I(3), G(vector(q2)), dims=(1,2))
	return attjac
end
# Injoints
function data_attitude_jacobian(ineqc::ContactConstraint)
	return I(data_dim(ineqc))
end


################################################################################
# Get Data
################################################################################
# Mechanism
get_data(mechanism::Mechanism) = vcat([get_data.(mechanism.joints);
	get_data.(mechanism.bodies); get_data.(mechanism.contacts)]...)
# Eqconstraints
function get_data(eqc::JointConstraint)
	joints = eqc.constraints
	u = vcat(nullspace_mask.(joints) .* getfield.(joints, :Fτ)...)
	spring = joints[1].spring # assumes we have the same spring and dampers for translational and rotational joint.
	damper = joints[1].damper # assumes we have the same spring and dampers for translational and rotational joint.
	spring_offset = vcat(getfield.(joints, :spring_offset)...)
	return [u; spring; damper; spring_offset]
end
# Body
function get_data(body::Body)
	m = body.m
	j = flatten_inertia(body.J)
	x1, q1 = previous_configuration(body.state)
	x2, q2 = current_configuration(body.state)
	return [m; j; x1; vector(q1); x2; vector(q2)]
end
# Injoints
get_data(bound::NonlinearContact) = [bound.cf; bound.offset; bound.p]
get_data(boundset::LinearContact) = [bound.cf; bound.off; bound.p]
get_data(bound::ImpactContact) = [bound.offset; bound.p]
get_data(ineqc::ContactConstraint) = vcat(get_data.(ineqc.constraints)...)


################################################################################
# Set Data
################################################################################
# Mechanism
function set_data!(mechanism::Mechanism, data::AbstractVector)
	c = 0
	for eqc in mechanism.joints
		Nd = data_dim(eqc)
		set_data!(eqc, data[c .+ (1:Nd)]); c += Nd
	end
	for body in mechanism.bodies
		Nd = data_dim(body)
		set_data!(body, data[c .+ (1:Nd)]); c += Nd
	end
	for ineqc in mechanism.contacts
		Nd = data_dim(ineqc)
		set_data!(ineqc, data[c .+ (1:Nd)]); c += Nd
	end
	return nothing
end
 # Eqconstraints
function set_data!(eqc::JointConstraint, data::AbstractVector)
	nu = control_dimension(eqc)
	u = data[SUnitRange(1,nu)]
	spring = data[nu+1]
	damper = data[nu+2]
	spring_offset = data[nu+2 .+ (1:nu)]

	set_input!(eqc, u)
	c = 0
	for joint in eqc.constraints
		nu = control_dimension(joint)
		joint.spring = spring
		joint.damper = damper
		joint.spring_offset = spring_offset[SUnitRange(c+1,c+nu)]; c += nu
	end
	return nothing
end
# Body
function set_data!(body::Body, data::AbstractVector)
	# [m,flat(J),x1,q1,x2,q2]
	m = data[1]
	J = lift_inertia(data[2:7])
	x1 = data[SUnitRange(8,10)]
	q1 = UnitQuaternion(data[11:14]..., false)
	x2 = data[SUnitRange(15,17)]
	q2 = UnitQuaternion(data[18:21]..., false)
	body.m = m
	body.J = J
	body.state.x1 = x1
	body.state.q1 = q1
	body.state.x2[1] = x2
	body.state.q2[1] = q2
	return nothing
end
# Injoints
function set_data!(bound::NonlinearContact, data::AbstractVector)
	bound.cf = data[1]
    bound.offset = data[SVector{3,Int}(2:4)]
    bound.p = data[SVector{3,Int}(5:7)]
    return nothing
end
function set_data!(bound::LinearContact, data::AbstractVector)
	bound.cf = data[1]
    bound.offset = data[SVector{3,Int}(2:4)]
    bound.p = data[SVector{3,Int}(5:7)]
    return nothing
end
function set_data!(bound::ImpactContact, data::AbstractVector)
    bound.offset = data[SVector{3,Int}(1:3)]
    bound.p = data[SVector{3,Int}(4:6)]
    return nothing
end
function set_data!(ineqc::ContactConstraint, data::AbstractVector)
    c = 0
	for bound in ineqc.constraints
		N = data_dim(bound)
        set_data!(bound, data[c .+ (1:N)]); c += N
    end
    return nothing
end
