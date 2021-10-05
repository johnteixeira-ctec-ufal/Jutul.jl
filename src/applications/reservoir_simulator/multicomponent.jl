using MultiComponentFlash
export TwoPhaseCompositionalSystem

abstract type MultiComponentSystem <: MultiPhaseSystem end
abstract type CompositionalSystem <: MultiComponentSystem end

struct TwoPhaseCompositionalSystem <: CompositionalSystem
    phases
    components
    equation_of_state
    flash_method
    function TwoPhaseCompositionalSystem(phases, equation_of_state; flash_method = SSIFlash())
        c = equation_of_state.mixture.component_names
        new(phases, c, equation_of_state, flash_method)
    end
end

get_components(sys::MultiComponentSystem) = sys.components
number_of_components(sys::MultiComponentSystem) = length(get_components(sys))

function degrees_of_freedom_per_entity(model::SimulationModel{G, S}, v::TotalMasses) where {G<:Any, S<:MultiComponentSystem}
    number_of_components(model.system)
end

function select_primary_variables_system!(S, domain, system::CompositionalSystem, formulation)
    S[:Pressure] = Pressure()
    S[:OverallCompositions] = OverallCompositions()
end

function select_equations_system!(eqs, domain, system::MultiComponentSystem, formulation)
    nc = number_of_components(system)
    eqs[:mass_conservation] = (ConservationLaw, nc)
end

function setup_storage_system!(storage, model, system::TwoPhaseCompositionalSystem)
    eos = model.system.equation_of_state
    n = number_of_components(eos)
    c = (p = 101325, T = 273.15 + 20, z = zeros(n))
    m = model.flash_method
    np = number_of_partials_per_entity(model, Cells())
    storage[:flash] = flash_storage(eos, c, m, inc_jac = true, diff_externals = true, npartials = np)
end
