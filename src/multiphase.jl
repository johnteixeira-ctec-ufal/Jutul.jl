export MultiPhaseSystem, ImmiscibleMultiPhaseSystem, SinglePhaseSystem
export LiquidPhase, VaporPhase
export number_of_phases, get_short_name, get_name

export allocate_storage, update_equations!
# Abstract multiphase system
abstract type MultiPhaseSystem <: TervSystem end


function get_phases(sys::MultiPhaseSystem)
    return sys.phases
end

function number_of_phases(sys::MultiPhaseSystem)
    return length(get_phases(sys))
end

## 
#function init_state(model)
#    d = dict()
#    init_state!(d, model)
#    return d
#end
#
#function init_state!(model)
#    sys = model.system
#    sys::MultiPhaseSystem
#    d = dict()
#    init_state!(d, model)
#end


function allocate_storage!(d, G, sys::MultiPhaseSystem)
    nph = number_of_phases(sys)
    phases = get_phases(sys)
    npartials = nph
    nc = number_of_cells(G)
    nhf = number_of_half_faces(G)

    A_p = get_incomp_matrix(G)
    jac = repeat(A_p, nph, nph)

    n_dof = nc*nph
    dx = zeros(n_dof)
    r = zeros(n_dof)
    lsys = LinearizedSystem(jac, r, dx)
    d["LinearizedSystem"] = lsys
    # hasAcc = !isa(sys, SinglePhaseSystem) # and also incompressible!!
    for phaseNo in eachindex(phases)
        ph = phases[phaseNo]
        sname = get_short_name(ph)
        law = ConservationLaw(G, lsys, npartials)
        d[string("ConservationLaw_", sname)] = law
        d[string("Mobility_", sname)] = allocate_vector_ad(nc, npartials)
        # d[string("Accmulation_", sname)] = allocate_vector_ad(nc, npartials)
        # d[string("Flux_", sname)] = allocate_vector_ad(nhf, npartials)
    end
end

function update_equations!(model, storage; dt = nothing)
    sys = model.system;
    sys::MultiPhaseSystem

    state = storage["state"]
    state0 = storage["state0"]
    

    p = state["Pressure"]
    p0 = state0["Pressure"]
    pv = model.G.pv

    phases = get_phases(sys)
    for phase in phases
        sname = get_short_name(phase)

        rho = storage["parameters"][string("Density_", sname)]
        law = storage[string("ConservationLaw_", sname)]
        mob = storage[string("Mobility_", sname)]
        half_face_flux!(law.half_face_flux, mob, p, model.G)
        law.accumulation .= pv.*(rho.(p) - rho.(p0))./dt
    end
end

## Systems
# Immiscible multiphase system
struct ImmiscibleSystem <: MultiPhaseSystem
    phases::AbstractVector
end

# Single-phase
struct SinglePhaseSystem <: MultiPhaseSystem
    phase
end

function get_phases(sys::SinglePhaseSystem)
    return [sys.phase]
end

function number_of_phases(::SinglePhaseSystem)
    return 1
end

## Phases
# Abstract phase
abstract type AbstractPhase end

function get_short_name(phase::AbstractPhase)
    return get_name(phase)[1:1]
end

# Liquid phase
struct LiquidPhase <: AbstractPhase end

function get_name(::LiquidPhase)
    return "Liquid"
end

# Vapor phases
struct VaporPhase <: AbstractPhase end

function get_name(::VaporPhase)
    return "Vapor"
end

