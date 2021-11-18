abstract type AbstractReservoirDeckTable end

export MuBTable, ConstMuBTable

abstract type AbstractTablePVT <: AbstractReservoirDeckTable end

struct MuBTable{V, I}
    pressure::V
    shrinkage::V
    shrinkage_interp::I
    viscosity::V
    viscosity_interp::I
    function MuBTable(p::T, b::T, mu::T; kwarg...) where T<:AbstractVector
        @assert length(p) == length(b) == length(mu)
        I_b = get_1d_interpolator(p, b; kwarg...)
        I_mu = get_1d_interpolator(p, mu; kwarg...)
        new{T, typeof(I_b)}(p, b, I_b, mu, I_mu)
    end
end

function MuBTable(pvtx::T; kwarg...) where T<:AbstractMatrix
    p = vec(pvtx[:, 1])
    b = vec(pvtx[:, 2])
    mu = vec(pvtx[:, 3])
    MuBTable(p, b, mu; kwarg...)
end

function viscosity(tbl::MuBTable, p)
    return tbl.viscosity_interp(p)
end

function shrinkage(tbl::MuBTable, p)
    return tbl.shrinkage_interp(p)
end

struct ConstMuBTable{R}
    p_ref::R
    b_ref::R
    b_c::R
    mu_ref::R
    mu_c::R
end

function ConstMuBTable(pvtw::M) where M<:AbstractVector
    return ConstMuBTable(pvtw[1], pvtw[2], pvtw[3], pvtw[4], pvtw[5])
end

function viscosity(tbl::ConstMuBTable, p)
    p_r = tbl.p_ref
    μ_r = tbl.mu_ref
    c = tbl.mu_c

    F = -c*(p - p_r)
    return μ_r/(1 + F + 0.5*F^2)
end

function shrinkage(tbl::ConstMuBTable, p)
    p_r = tbl.p_ref
    b_r = tbl.b_ref
    c = tbl.b_c

    F = c*(p - p_r)
    return b_r*(1 + F + 0.5*F^2)
end

struct PVDO <: AbstractTablePVT
    tab::NTuple
end

function PVDO(pvdo::AbstractArray)
    c = map(MuBTable, pvdo)
    PVDO(Tuple(c))
end

struct PVDG <: AbstractTablePVT
    tab::NTuple
end

function PVDG(pvdo::AbstractArray)
    c = map(MuBTable, pvdo)
    PVDG(Tuple(c))
end

struct PVTW <: AbstractTablePVT
    tab::NTuple
end

function PVTW(pvdo::AbstractArray)
    c = map(x -> ConstMuBTable(vec(x)), pvdo)
    PVTW(Tuple(c))
end

# abstract type AbstractTableSaturation <: AbstractTableDeck end

# struct RelativePermeabilityTable <: AbstractTableSaturation

# end

# struct CapillaryPressureTable <: AbstractTableSaturation

# end

# Regions go in the outer part

