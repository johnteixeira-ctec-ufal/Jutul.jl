function unpack_tag(v::Type{ForwardDiff.Dual{T, F, N}}) where {T, F, N}
    return T[2]
end
unpack_tag(A::AbstractArray) = unpack_tag(eltype(A))
unpack_tag(::Any) = nothing

function create_mock_state(state, tag, entities = ad_entities(state))
    mock_state = Dict()
    n = entities[tag].n
    tracer = ST.create_advec(ones(n));
    for k in keys(state)
        v = state[k]
        if unpack_tag(v) == tag
            # Assign mock value with tracer
            new_v = as_tracer(v, tracer)
        else
            # Assign mock value as doubles
            new_v = as_value(v)
        end
        mock_state[k] = new_v
    end
    return (NamedTuple(pairs(mock_state)), tracer)
end

function as_tracer(x::AbstractVector, tracer)
    out = ST.create_advec(value(x))
    @assert eltype(out) == eltype(tracer)
    return out
end

function as_tracer(x::AbstractMatrix, tracer)
    # Repeat the process for each row - in Jutul, each row corresponds to the same entity
    tmp = map(i -> as_tracer(vec(x[i, :]), tracer)', 1:size(x, 1))
    return vcat(tmp...)
end

function as_tracer(x, tracer)
    # A bit dangerous - should be overloaded for complicated types that can contain AD!
    return x
end

function ad_entities(state)
    entity_count(x::AbstractVector) = length(x)
    entity_count(x::AbstractMatrix) = size(x, 2)

    out = Dict()
    for k in keys(state)
        v = state[k]
        tag = unpack_tag(v)
        if !isnothing(tag)
            n = entity_count(v)
            T = eltype(v)
            if haskey(out, tag)
                old = out[tag]
                @assert old.n == n && old.T == T "Inconsistent numbering for $k"
            else
                out[tag] = (n = n, T = T)
            end
        end
    end
    return out
end


# tag = :Cells
# determine_sparsity(state, tag);
##
function determine_sparsity(F!, n, state, state0, tag, entities, N = entities[tag].n)
    mstate, tracer = create_mock_state(state, tag, entities)
    mstate0, = create_mock_state(state0, tag, entities)

    out = similar(tracer, n)
    J = [Vector{Int64}() for i in 1:N]
    # @batch threadlocal = similar(tracer, n) for i = 1:N
    #    out = threadlocal
    for i in 1:N
        @inbounds F!(out, mstate, mstate0, i)
        # Take the sum over all return values to reduce to scalar.
        # This should accumulate the full "entity" pattern if some
        # equations have a different stencil.
        V = sum(out)
        D = ST.deriv(V)
        J[i] = D.nzind
    end
    return J
end
