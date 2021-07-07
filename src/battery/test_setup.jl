using Terv

export get_test_setup_battery, get_cc_grid, get_bc

function get_test_setup_battery(name="square_current_collector")
    domain, exported = get_cc_grid(name, extraout=true)
    timesteps = [1.,]
    G = exported["G"]

    sys = CurrentCollector()
    model = SimulationModel(domain, sys, context = DefaultContext())

    # State is dict with pressure in each cell
    phi = 1.
    init = Dict(:Phi => phi)
    state0 = setup_state(model, init)
    state0[:Phi][1] = 2  # Endrer startverdien, skal ikke endre svaret
    
    # set up boundary conditions
    nc = length(domain.grid.volumes)
    
    dirichlet = DirichletBC([1, 1], [1, -1], [2, 2])
    neumann = vonNeumannBC([1, nc], [-1, 1])
    forces = (neumann=neumann, dirichlet= dirichlet,)
    
    # Model parameters
    parameters = setup_parameters(model)

    return (state0, model, parameters, forces, timesteps, G)
end

function test_mixed_boundary_conditions()
    domain = get_cc_grid("square_current_collector")
    timesteps = [1.,]

    sys = CurrentCollector()
    model = SimulationModel(domain, sys, context = DefaultContext())

    # State is dict with pressure in each cell
    phi = 1.
    init = Dict(:Phi => phi)
    state0 = setup_state(model, init)
    
    # set up boundary conditions
    nc = length(domain.grid.volumes)
    
    boundary_cells_righ = 1:10:nc
    boundary_cells_left = 10:10:nc
    boundary_values = ones(size(boundary_cells_righ))
    T_hfs = 2 * ones(size(boundary_cells_righ))
    dirichlet = DirichletBC(boundary_cells_righ, 0*boundary_values, T_hfs)
    neumann = vonNeumannBC(boundary_cells_left, boundary_values)
    forces = (neumann=neumann, dirichlet= dirichlet,)
    
    # Model parameters
    parameters = setup_parameters(model)

    sim = Simulator(model, state0=state0, parameters=parameters)
    cfg = simulator_config(sim)
    cfg[:linear_solver] = nothing
    states = simulate(sim, timesteps, forces = forces, config = cfg)

    # Check if the field value increments by one
    @assert sum(isapprox.(diff(states[1].Phi[1:10]), 1)) == 9
end


function get_bccc_struct(name)
    fn = string(dirname(pathof(Terv)), "/../data/testgrids/", name, ".mat")
    @debug "Reading MAT file $fn..."
    exported = MAT.matread(fn)
    @debug "File read complete. Unpacking data..."

    bccells = copy((exported["bccells"])')
    bcfaces = copy((exported["bcfaces"])')

    bccells = Int64.(bccells)
    bcfaces = Int64.(bcfaces)
    return (bccells, bcfaces)
end


function get_bc(name)
    fn = string(dirname(pathof(Terv)), "/../data/testgrids/", name, "_T.mat")
    exported = MAT.matread(fn)
    return exported
end


function get_cc_grid(name="square_current_collector"; extraout = false)
    fn = string(dirname(pathof(Terv)), "/../data/testgrids/", name, ".mat")
    @debug "Reading MAT file $fn..."
    exported = MAT.matread(fn)
    @debug "File read complete. Unpacking data..."

    N = exported["G"]["faces"]["neighbors"]
    N = Int64.(N)
    internal_faces = (N[:, 2] .> 0) .& (N[:, 1] .> 0)
    N = copy(N[internal_faces, :]')
        
    # Cells
    cell_centroids = copy((exported["G"]["cells"]["centroids"])')

    # Faces
    face_centroids = copy((exported["G"]["faces"]["centroids"][internal_faces, :])')
    face_areas = vec(exported["G"]["faces"]["areas"][internal_faces])
    face_normals = exported["G"]["faces"]["normals"][internal_faces, :]./face_areas
    face_normals = copy(face_normals')
    cond = ones(size((exported["rock"]["perm"])')) # Conductivity σ, corresponding to permeability

    volumes = vec(exported["G"]["cells"]["volumes"])

    @debug "Data unpack complete. Starting transmissibility calculations."
    # Deal with face data
    T_hf = compute_half_face_trans(cell_centroids, face_centroids, face_normals, face_areas, cond, N)
    T = compute_face_trans(T_hf, N)

    G = MinimalECTPFAGrid(volumes, N)
    z = nothing
    g = nothing

    ft = ChargeFlow()
    # ??Hva gjør SPU og TPFA??
    flow = TwoPointPotentialFlow(SPU(), TPFA(), ft, G, T, z, g)
    disc = (charge_flow = flow,)
    D = DiscretizedDomain(G, disc)

    if extraout
        return (D, exported)
    else
        return D
    end
end
