function getant(; Δt::T=0.05, g::T=-9.81, cf::T=1.0,
    spring=25.0, damper=25.0, contact::Bool=true, contact_body=true) where T

    path = joinpath(@__DIR__, "../deps/ant.urdf")
    mech = Mechanism(path, true, T, g=g, Δt=Δt, spring=spring, damper=damper)

    # joint spring offsets
    θ_offset = 0.25 * π
    ankle1 = geteqconstraint(mech, "ankle_1")
    ankle1.constraints[2].spring_offset = θ_offset * sones(T,1)

    ankle2 = geteqconstraint(mech, "ankle_2")
    ankle2.constraints[2].spring_offset = -θ_offset * sones(T,1)

    ankle3 = geteqconstraint(mech, "ankle_3")
    ankle3.constraints[2].spring_offset = -θ_offset * sones(T,1)

    ankle4 = geteqconstraint(mech, "ankle_4")
    ankle4.constraints[2].spring_offset = θ_offset * sones(T,1)

    for body in mech.bodies 
        body.m *= 10.0 
        body.J *= 10.0^2 
    end

    if contact
        origin = Origin{T}()
        bodies = Vector{Body{T}}(collect(mech.bodies))
        eqs = Vector{EqualityConstraint{T}}(collect(mech.eqconstraints))

        # foot contact
        normal = [0.0; 0.0; 1.0]
        foot_names = ["front_left_foot", "front_right_foot", "left_back_foot", "right_back_foot"]
        foot = [getbody(mech, name) for name in foot_names]
        p = [[0.2; 0.2; 0.0], [-0.2; 0.2; 0.0], [-0.2; -0.2; 0.0], [0.2; -0.2; 0.0]]
        o = [[0.0; 0.0; f.shape.rh[1]] for f in foot]
        contineqcs = [contactconstraint(foot[i], normal, cf, p=p[i], offset=o[i]) for i = 1:length(foot_names)]

        if contact_body 
            # torso contact
            torso = getbody(mech, "torso")
            p = [0.0; 0.0; 0.0]
            o = [0.0; 0.0; torso.shape.r]
            torso_ineqcs = contactconstraint(torso, normal, cf, p=p, offset=o)

            # elbow contact 
            elbow_names = ["aux_1", "aux_2", "aux_3", "aux_4"]
            elbow = [getbody(mech, e) for e in elbow_names]
            p = [-[0.1; 0.1; 0.0], -[-0.1; 0.1; 0.0], -[-0.1; -0.1; 0.0], -[0.1; -0.1; 0.0]]
            o = [[0.0; 0.0; e.shape.rh[1]] for e in elbow]
            elbow_ineqcs = [contactconstraint(elbow[i], normal, cf, p=p[i], offset=o[i]) for i = 1:length(elbow_names)]

            contineqcs = [contineqcs..., torso_ineqcs, elbow_ineqcs...]
        end 

        mech = Mechanism(origin, bodies, eqs, contineqcs, g=g, Δt=Δt, spring=spring, damper=damper)
    end

    return mech
end

function initializeant!(mechanism::Mechanism; alt=0.15, pos=[0.0; 0.0; 0.48 + alt], rot=[0.0; 0.0; 0.25 * π]) where {T}
    setPosition!(mechanism, geteqconstraint(mechanism, "auto_generated_floating_joint"), [pos; rot])

    for i in [1,4]
        setPosition!(mechanism, geteqconstraint(mechanism, "hip_$i"), [0.0 * π])
        setPosition!(mechanism, geteqconstraint(mechanism, "ankle_$i"), [0.25 * π])
    end

    for i in [2,3]
        setPosition!(mechanism, geteqconstraint(mechanism, "hip_$i"), [0.0 * π])
        setPosition!(mechanism, geteqconstraint(mechanism, "ankle_$i"), [-0.25 * π])
    end
    
    zeroVelocity!(mechanism)
end

