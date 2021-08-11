# Primary variables

"""
Number of units (e.g. Cells, Faces) a variable is defined on.
"""
function number_of_units(model, pv::TervVariables)
    # By default, each primary variable exists on all cells of a discretized domain
    return count_units(model.domain, associated_unit(pv))
end

"""
The unit a variable is associated with, and can hold partial derivatives with respect to.
"""
function associated_unit(::TervVariables)
    # The default unit for all primary variables is Cells()
    return Cells()
end

"""
Total number of degrees of freedom for a model, over all primary variables and all units.
"""
function number_of_degrees_of_freedom(model::TervModel)
    ndof = 0
    for (pkey, pvar) in get_primary_variables(model)
        ndof += number_of_degrees_of_freedom(model, pvar)
    end
    return ndof
end

function number_of_degrees_of_freedom(model::TervModel, u::TervUnit)
    ndof = degrees_of_freedom_per_unit(model, u)*count_units(model.domain, u)
    return ndof
end

function degrees_of_freedom_per_unit(model::TervModel, u::TervUnit)
    ndof = 0
    for pvar in values(get_primary_variables(model))
        if associated_unit(pvar) == u
            ndof += degrees_of_freedom_per_unit(model, pvar)
        end
    end
    return ndof
end

function number_of_degrees_of_freedom(model, pvars::TervVariables)
    return number_of_units(model, pvars)*degrees_of_freedom_per_unit(model, pvars)
end

function value_dim(model, pvars::TervVariables)
    return (values_per_unit(model, pvars), number_of_units(model, pvars))
end

"""
Number of independent primary variables / degrees of freedom per computational unit.
"""
function degrees_of_freedom_per_unit(model, ::ScalarVariable)
    return 1
end

"""
Constant variables hold no degrees of freedom.
"""
function degrees_of_freedom_per_unit(model, ::ConstantVariables)
    return 0 # A constant has no freedom
end

"""
Number of values held by a primary variable. Normally this is equal to the number of degrees of freedom,
but some special primary variables are most conveniently defined by having N values and N-1 independent variables.
"""
function values_per_unit(model, u::TervVariables)
    return degrees_of_freedom_per_unit(model, u)
end

## Update functions
"Absolute allowable change for variable during a nonlinear update."
function absolute_increment_limit(::TervVariables) nothing end

"""
Relative allowable change for variable during a nonlinear update.
A variable with value |x| and relative limit 0.2 cannot change more
than |x|*0.2.
"""
function relative_increment_limit(::TervVariables) nothing end

"""
Upper (inclusive) limit for variable.
"""
function maximum_value(::TervVariables) nothing end

"""
Lower (inclusive) limit for variable.
"""
function minimum_value(::TervVariables) nothing end

function update_primary_variable!(state, p::TervVariables, state_symbol, model, dx)
    names = get_names(p)
    nu = number_of_units(model, p)
    abs_max = absolute_increment_limit(p)
    rel_max = relative_increment_limit(p)
    maxval = maximum_value(p)
    minval = minimum_value(p)
    scale = variable_scale(p)

    for (index, nm) in enumerate(names)
        offset = nu*(index-1)
        v = state[state_symbol]
        dv = view(dx, (1:nu) .+ offset)
        @tullio v[i] = update_value(v[i], dv[i], abs_max, rel_max, minval, maxval, scale)
    end
end

@inline function choose_increment(v::F, dv::F, abs_change = nothing, rel_change = nothing, minval = nothing, maxval = nothing, scale = nothing) where {F<:AbstractFloat}
    dv = scale_increment(dv, scale)
    dv = limit_abs(dv, abs_change)
    dv = limit_rel(v, dv, rel_change)
    dv = limit_lower(v, dv, minval)
    dv = limit_upper(v, dv, maxval)
    return dv
end


# Limit absolute
@inline function limit_abs(dv, abs_change)
    dv = sign(dv)*min(abs(dv), abs_change)
end

@inline function limit_abs(dv, ::Nothing) dv end

# Limit relative 
@inline function limit_rel(v, dv, rel_change)
    dv = limit_abs(dv, rel_change*abs(v))
end

@inline function limit_rel(v, dv, ::Nothing) dv end
# Lower bounds
function limit_upper(v, dv, maxval)
    if dv > 0 && v + dv > maxval
        dv = maxval - v
    end
    return dv
end

@inline function limit_upper(v, dv, maxval::Nothing) dv end

# Upper bounds
@inline function limit_lower(v, dv, minval)
    if dv < 0 && v + dv < minval
        dv = minval - v
    end
    return dv
end

@inline function limit_lower(v, dv, minval::Nothing) dv end

# Scaling
@inline function scale_increment(dv, scale)
    return dv*scale
end

@inline scale_increment(dv, ::Nothing) = dv

@inline function update_value(v, dv, arg...)
    return v + choose_increment(value(v), dv, arg...)
end


function get_names(v::TervVariables)
    return [get_name(v)]
end

function get_symbol(v::TervVariables)
    return Symbol(typeof(v))
end

function get_name(v::TervVariables)
    return String(get_symbol(v))
end

variable_scale(::TervVariables) = nothing

## Initialization
function initialize_primary_variable_ad!(state, model, pvar, arg...; offset = 0, kwarg...)
    diag_value = variable_scale(pvar)
    if isnothing(diag_value)
        diag_value = 1.0
    end
    initialize_variable_ad(state, model, pvar, arg..., offset + 1; diag_value = diag_value, kwarg...)
end

function initialize_secondary_variable_ad!(state, model, pvar, arg...; kwarg...)
    initialize_variable_ad(state, model, pvar, arg..., NaN; kwarg...)
end

function initialize_variable_ad(state, model, pvar, symb, npartials, diag_pos; kwarg...)
    state[symb] = allocate_array_ad(state[symb], diag_pos = diag_pos, context = model.context, npartials = npartials; kwarg...)
    return state
end

function initialize_variable_value(model, pvar, val; perform_copy = true)
    nu = number_of_units(model, pvar)
    nv = values_per_unit(model, pvar)
    
    if isa(pvar, ScalarVariable)
        @assert length(val) == nu
        # Type-assert that this should be scalar, with a vector input
        val::AbstractVector
    else
        nm = length(val)
        @assert length(val) == nm "Passed value had $nm entries, expected $(nu*nv)"
        n, m, = size(val)
        @assert n == nv "Passed value had $n rows, expected $nv"
        @assert m == nu "Passed value had $m rows, expected $nu"
    end
    if perform_copy
        val = deepcopy(val)
    end
    return transfer(model.context, val)
end

function default_value(v)
    return 0.0
end

function initialize_variable_value!(state, model, pvar, symb, val; kwarg...)
    state[symb] = initialize_variable_value(model, pvar, val; kwarg...)
    return state
end

function initialize_variable_value!(state, model, pvar, symb, val::AbstractDict; need_value = true)
    if haskey(val, symb)
        value = val[symb]
    elseif need_value
        k = keys(val)
        error("The key $symb must be present to initialize the state. Found symbols: $k")
    else
        # We do not really need to initialize this, as it will be updated elsewhere.
        value = default_value(pvar)
    end
    return initialize_variable_value!(state, model, pvar, symb, value)
end

# Scalar primary variables
function initialize_variable_value!(state, model, pvar::ScalarVariable, symb::Symbol, val::Number)
    V = repeat([val], number_of_units(model, pvar))
    return initialize_variable_value!(state, model, pvar, symb, V)
end

"""
Initializer for the value of non-scalar primary variables
"""
function initialize_variable_value!(state, model, pvar::GroupedVariables, symb::Symbol, val::AbstractVector)
    n = values_per_unit(model, pvar)
    t = typeof(pvar)
    @assert length(val) == n "Variable $t should have initializer of length $n"
    V = repeat(val, 1, number_of_units(model, pvar))
    return initialize_variable_value!(state, model, pvar, symb, V)
end

function initialize_variable_value!(state, model, pvar::GroupedVariables, symb::Symbol, val::Number)
    n = values_per_unit(model, pvar)
    return initialize_variable_value!(state, model, pvar, symb, repeat([val], n))
end

# Specific variable implementations that are generic for many types of system follow


function values_per_unit(model, var::ConstantVariables)
    c = var.constants
    if var.single_unit
        n = length(c)
    else
        n = size(c, 1)
    end
end
associated_unit(model, var::ConstantVariables) = var.unit

function transfer(context, v::ConstantVariables)
    constants = transfer(context, v.constants)
    return ConstantVariables(constants, v.unit, v.single_unit)
end

function initialize_variable_value(model, var::ConstantVariables, val; perform_copy = true)
    # Ignore initializer since we already know the constants
    nu = number_of_units(model, var)
    if var.single_unit
        it = index_type(model.context)
        # use instance as view to avoid allocating lots of copies
        var_val = view(var.constants, :, ones(it, nu))
    else
        # We have all the values we need ready.
        var_val = var.constants
    end
    return var_val
end

function initialize_secondary_variable_ad!(state, model, var::ConstantVariables, arg...; kwarg...)
    # Do nothing. There is no need to add AD.
    return state
end

function initialize_primary_variable_ad!(state, model, var::ConstantVariables, sym, arg...; kwarg...)
    error("$sym is declared to be constants - cannot be primary variables.")
end

