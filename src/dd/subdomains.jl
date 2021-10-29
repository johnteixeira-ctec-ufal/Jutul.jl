export subdomain, submap_cells, subforces, subforce

"Local face -> global face (full set)"
global_face(f, ::TrivialGlobalMap) = f
"Local cell -> global cell (full set)"
global_cell(c, ::TrivialGlobalMap) = c

"Global cell -> local cell (full set)"
local_cell(c, ::TrivialGlobalMap) = c
cell_is_boundary(c, ::TrivialGlobalMap) = false

"Global face -> local face (full set)"
local_face(f, ::TrivialGlobalMap) = f

interior_cell(c, ::TrivialGlobalMap) = c

interior_face(f, m) = f

map_to_active(V, domain, entity) = map_to_active(V, domain, domain.global_map, entity)
map_to_active(V, domain, m, entity) = V

function map_to_active(V, domain, m::FiniteVolumeGlobalMap, ::Cells)
    W = similar(V, 0)
    for i in V
        ix = interior_cell(i, m)
        if !isnothing(ix)
            push!(W, ix)
        end
    end
    return W
    # return filter(i -> m.cell_is_boundary[i], V)
end


global_face(f, m::FiniteVolumeGlobalMap) = m.faces[f]
global_cell(c, m::FiniteVolumeGlobalMap) = m.cells[c]

local_cell(c_global, m::FiniteVolumeGlobalMap) = only(indexin(c_global, m.cells))
local_face(f_global, m::FiniteVolumeGlobalMap) = only(indexin(f_global, m.faces))

cell_is_boundary(c, m::FiniteVolumeGlobalMap) = m.cell_is_boundary[c]


function interior_cell(c, m::FiniteVolumeGlobalMap)
    c_i = m.full_to_inner_cells[c]
    return c_i == 0 ? nothing : c_i
end
# interior_cell(c, m::FiniteVolumeGlobalMap) = only(indexin(c, m.inner_to_full_cells))

#global_map

# Specialize cells, leave faces be (probably already filtered)
active_cells(model) = active_entities(model.domain, Cells())

active_entities(d, m::FiniteVolumeGlobalMap, ::Cells) = m.inner_to_full_cells
active_entities(d, m::FiniteVolumeGlobalMap, f::Faces) = 1:count_entities(d, f)

active_entities(d::DiscretizedDomain, entity) = active_entities(d, d.global_map, entity)
active_entities(d::DiscretizedDomain, ::TrivialGlobalMap, entity) = 1:count_entities(d, entity)


# TODO: Probably a bit inefficient
count_active_entities(d, m, e) = length(active_entities(d, m, e))

subdiscretization(disc, ::TrivialGlobalMap) = disc

function subdomain(d::DiscretizedDomain, indices; entity = Cells(), buffer = 0)
    grid = d.grid
    disc = d.discretizations

    N = grid.neighborship
    cells, faces, is_boundary = submap_cells(N, indices, buffer = buffer)
    mapper = FiniteVolumeGlobalMap(cells, faces, is_boundary)
    sg = subgrid(grid, cells = cells, faces = faces)
    d = Dict()
    for k in keys(disc)
        d[k] = subdiscretization(disc[k], sg, mapper)
    end
    subdisc = convert_to_immutable_storage(d)
    return DiscretizedDomain(sg, subdisc, global_map = mapper)
end

function submap_cells(N, indices; nc = maximum(N), buffer = 0)
    @assert buffer == 0 || buffer == 1
    cells = Vector{Integer}()
    faces = Vector{Integer}()
    is_boundary = Vector{Bool}()

    facelist, facepos = get_facepos(N)

    insert_face!(f) = push!(faces, f)
    function insert_cell!(gc, is_bnd)
        push!(cells, gc)
        push!(is_boundary, is_bnd)
    end
    for (i, gc) in enumerate(indices)
        # Include global cell
        might_be_bound = false
        for fi in facepos[gc]:facepos[gc+1]-1
            face = facelist[fi]
            l, r = N[1, face], N[2, face]
            # If both cells are in the interior, we add it
            if in(l, indices) && in(r, indices)
                insert_face!(face)
            else
                might_be_bound = true
            end
        end
        is_bnd = might_be_bound && buffer == 0
        insert_cell!(gc, is_bnd)
        if buffer == 1
            # Also add the neighbors, if not already present
            for fi in facepos[gc]:facepos[gc+1]-1
                face = facelist[fi]
                l, r = N[1, face], N[2, face]
                if l == gc
                    other = r
                else
                    other = l
                end
                # If a bounded cell is not in the global list of interior cells and not in the current
                # set of processed cells, we add it and flag as a global boundary
                if !in(other, cells) && !in(other, indices)
                    insert_face!(face)
                    # This cell is now guaranteed to be on the boundary.
                    insert_cell!(other, true)
                end
            end
        end
    end
    return (cells = cells, faces = faces, is_boundary = is_boundary)
end

function subforces(forces, submodel)
    D = Dict{Symbol, Any}()
    for k in keys(forces)
        D[k] = subforce(forces[k], submodel)
    end
    return convert_to_immutable_storage(D)
end
