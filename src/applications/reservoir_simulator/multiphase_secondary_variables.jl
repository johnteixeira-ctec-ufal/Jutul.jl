export PhaseMassDensities, PhaseMobilities, MassMobilities

abstract type PhaseVariables <: GroupedVariables end
abstract type ComponentVariable <: GroupedVariables end
abstract type PhaseAndComponentVariable <: GroupedVariables end

function degrees_of_freedom_per_unit(model, sf::PhaseVariables) number_of_phases(model.system) end

# Single-phase specialization
function degrees_of_freedom_per_unit(model::SimulationModel{D, S}, sf::ComponentVariable) where {D, S<:SinglePhaseSystem} 1 end
function degrees_of_freedom_per_unit(model::SimulationModel{D, S}, sf::PhaseAndComponentVariable) where {D, S<:SinglePhaseSystem} 1 end

# Immiscible specialization
function degrees_of_freedom_per_unit(model::SimulationModel{D, S}, sf::ComponentVariable) where {D, S<:ImmiscibleSystem}
    number_of_phases(model.system)
end
function degrees_of_freedom_per_unit(model::SimulationModel{D, S}, sf::PhaseAndComponentVariable) where {D, S<:ImmiscibleSystem}
    number_of_phases(model.system)
end

function select_secondary_variables_system!(S, domain, system::MultiPhaseSystem, formulation)
    S[:PhaseMassDensities] = PhaseMassDensities()
    S[:TotalMasses] = TotalMasses()
end

function minimum_output_variables(system::MultiPhaseSystem, primary_variables)
    [:TotalMasses]
end

abstract type RelativePermeabilities <: PhaseVariables end

struct BrooksCoreyRelPerm <: RelativePermeabilities
    exponents
    residuals
    endpoints
    residual_total
    function BrooksCoreyRelPerm(system::MultiPhaseSystem, exponents = 1, residuals = 0, endpoints = 1)
        nph = number_of_phases(system)

        expand(v::Real) = [v for i in 1:nph]
        function expand(v::AbstractVector)
            @assert length(v) == nph
            return v
        end
        e = expand(exponents)
        r = expand(residuals)
        epts = expand(endpoints)
        
        total = sum(residuals)
        new(e, r, epts, total)
    end
end

@terv_secondary function update_as_secondary!(kr, kr_def::BrooksCoreyRelPerm, model, param, Saturations)
    n, sr, kwm, sr_tot = kr_def.exponents, kr_def.residuals, kr_def.endpoints, kr_def.residual_total
    @tullio kr[ph, i] = brooks_corey_relperm(Saturations[ph, i], n[ph], sr[ph], kwm[ph], sr_tot)
end

function brooks_corey_relperm(s, n, sr, kwm, sr_tot)
    den = 1 - sr_tot;
    sat = ((s - sr)./den);
    sat = max(min(sat, 1), 0);
    return kwm*sat^n;
end

"""
Mass density of each phase
"""
struct PhaseMassDensities <: PhaseVariables end

@terv_secondary function update_as_secondary!(rho, tv::PhaseMassDensities, model, param, Pressure)
    rho_input = param.Density
    p = Pressure
    @sync begin
        @async for i in 1:number_of_phases(model.system)
            rho_i = view(rho, i, :)
            r = rho_input[i]
            if isa(r, NamedTuple)
                f_rho = (p) -> r.rhoS*exp((p - r.pRef)*r.c)
            else
                # Function handle
                f_rho = r
            end
            fapply!(rho_i, f_rho, p)
        end
    end
end

"""
Mobility of the mass of each component, in each phase (TBD how to represent this in general)
"""
struct MassMobilities <: PhaseAndComponentVariable end

@terv_secondary function update_as_secondary!(ρλ_i, tv::MassMobilities, model, param, PhaseMassDensities, PhaseViscosities, RelativePermeabilities)
    kr, μ, ρ = RelativePermeabilities, PhaseViscosities, PhaseMassDensities
    @tullio ρλ_i[ph, i] = kr[ph, i]*ρ[ph, i]/μ[ph, i]
end

@terv_secondary function update_as_secondary!(ρλ_i, tv::MassMobilities, model::SimulationModel{D, S}, param, PhaseMassDensities, PhaseViscosities) where {D, S<:SinglePhaseSystem}
    μ, ρ = PhaseViscosities, PhaseMassDensities
    @tullio ρλ_i[i] = ρ[i]/μ[i]
end

# Total masses
@terv_secondary function update_as_secondary!(totmass, tv::TotalMasses, model::SimulationModel{G, S}, param, PhaseMassDensities) where {G, S<:SinglePhaseSystem}
    pv = get_pore_volume(model)
    @tullio totmass[i] = PhaseMassDensities[i]*pv[i]
end

@terv_secondary function update_as_secondary!(totmass, tv::TotalMasses, model::SimulationModel{G, S}, param, PhaseMassDensities, Saturations) where {G, S<:ImmiscibleSystem}
    pv = get_pore_volume(model)
    rho = PhaseMassDensities
    s = Saturations
    @tullio totmass[ph, i] = rho[ph, i]*pv[i]*s[ph, i]
end

# Total mass
@terv_secondary function update_as_secondary!(totmass, tv::TotalMass, model::SimulationModel{G, S}, param, TotalMasses) where {G, S<:MultiPhaseSystem}
    @tullio totmass[i] = TotalMasses[ph, i]
end
