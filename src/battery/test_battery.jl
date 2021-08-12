#=
Electro-Chemical component
A component with electric potential, concentration and temperature
The different potentials are independent (diagonal onsager matrix),
and conductivity, diffusivity is constant.
=#
@time using Terv
using MAT
using Plots
ENV["JULIA_DEBUG"] = Terv;


##
function make_system(exported,sys,bcfaces,srccells)
    #name="model1d"
    #fn = string(dirname(pathof(Terv)), "/../data/models/", name, ".mat")
    #exported_all = MAT.matread(fn)
    #exported = exported_all["model"]["NegativeElectrode"]["CurrentCollector"];
    ## for boundary
    # bcfaces = [1]
    # bcfaces = Int64.(bfaces)
    T_all = exported["operators"]["T_all"]
    N_all = Int64.(exported["G"]["faces"]["neighbors"])
    isboundary = (N_all[bcfaces,1].==0) .| (N_all[bcfaces,2].==0)
    @assert all(isboundary)
    bccells = N_all[bcfaces,1] + N_all[bcfaces,2]
    T_hf   = T_all[bcfaces]
    bcvaluesrc = ones(size(srccells))
    bcvaluephi = ones(size(bccells)).*0.0

    domain = exported_model_to_domain(exported, bc = bccells, b_T_hf = T_hf)  
    G = exported["G"]    
    model = SimulationModel(domain, sys, context = DefaultContext())
    parameters = setup_parameters(model)
    parameters[:boundary_currents] = (:BCCharge, :BCMass)

    # State is dict with pressure in each cell
    phi0 = 1.0
    C0 = 1.
    T0 = 1.
    D = 1e-9 # ???   
    if isa("EffectiveElectricalConductivity",Matrix)
        σ = exported["EffectiveElectricalConductivity"][1]
    else
        σ = 1.0
    end
    λ = exported["thermalConductivity"][1]

    S = model.secondary_variables
    S[:BoundaryPhi] = BoundaryPotential{Phi}()
    S[:BoundaryC] = BoundaryPotential{Phi}()
    S[:BoundaryT] = BoundaryPotential{T}()

    S[:BCCharge] = BoundaryCurrent{ChargeAcc}(srccells)
    S[:BCMass] = BoundaryCurrent{MassAcc}(srccells)
    S[:BCEnergy] = BoundaryCurrent{EnergyAcc}(srccells)

    phi0 = 0.
    init = Dict(
        :Phi                    => phi0,
        :C                      => C0,
        :T                      => T0,
        :Conductivity           => σ,
        :Diffusivity            => D,
        :ThermalConductivity    => λ,
        :BoundaryPhi            => bcvaluephi, 
        :BoundaryC              => bcvaluephi, 
        :BoundaryT              => bcvaluephi,
        :BCCharge               => -bcvaluesrc.*9.4575,
        :BCMass                 => bcvaluesrc,
        :BCEnergy               => bcvaluesrc,
        )

    state0 = setup_state(model, init)
    return model, G, state0, parameters, init
end

# function update_cross_term!(ct::InjectiveCrossTerm, eq::ScalarTestEquation, target_storage, source_storage, target_model, source_model, target, source, dt)
#    X_T = target_storage.state.XVar
#    X_S = source_storage.state.XVar
#    function f(X_S, X_T)
#        X_T - X_S
#    end
#    # Source term with AD context from source model - will end up as off-diagonal block
#    @. ct.crossterm_source = f(X_S, value(X_T))
#    # Source term with AD context from target model - will be inserted into equation
#    @. ct.crossterm_target = f(value(X_S), X_T)
#end


function test_ac()
    name="model1d"
    fn = string(dirname(pathof(Terv)), "/../data/models/", name, ".mat")
    exported_all = MAT.matread(fn)
    exported_cc = exported_all["model"]["NegativeElectrode"]["CurrentCollector"];
    # sys = ECComponent()
    # sys = ACMaterial();
    #sys = Grafite()
    sys_cc = CurrentCollector()
    bcfaces=[1]
    srccells = []
    (model_cc, G_cc, state0_cc, parm_cc,init_cc) = make_system(exported_cc,sys_cc, bcfaces, srccells)
    #sys_nam = CurrentCollector()
    sys_nam = Grafite()
    exported_nam = exported_all["model"]["NegativeElectrode"]["ElectrodeActiveComponent"];
    # sys = ECComponent()
    bcfaces=[]
    srccells = []
    (model_nam, G_nam, state0_nam, parm_nam, init_nam) = 
        make_system(exported_nam,sys_nam,bcfaces,srccells)

    #sys_elyte = CurrentCollector()#
    sys_elyte = SimpleElyte()
    exported_elyte = exported_all["model"]["Electrolyte"]
    bcfaces=[]
    srccells = []
    (model_elyte, G_elyte, state0_elyte, parm_elyte, init_elyte) = 
        make_system(exported_elyte,sys_elyte,bcfaces,srccells)

    sys_pam = Grafite()
    exported_pam = exported_all["model"]["PositiveElectrode"]["ElectrodeActiveComponent"];
    # sys = ECComponent()
    bcfaces=[]
    srccells = []
    (model_pam, G_pam, state0_pam, parm_pam, init_pam) = 
        make_system(exported_pam,sys_pam,bcfaces,srccells)   
   
    exported_pp = exported_all["model"]["PositiveElectrode"]["CurrentCollector"];
        # sys = ECComponent()
        # sys = ACMaterial();
        #sys = Grafite()
        sys_pp = CurrentCollector()
        bcfaces=[]
        srccells = [10]
        (model_pp, G_pp, state0_pp, parm_pp,init_pp) = 
        make_system(exported_pp,sys_pp, bcfaces, srccells)
        #sys_nam = CurrentCollector()

    groups = nothing
    model = MultiModel((CC = model_cc, NAM = model_nam, 
                        ELYTE = model_elyte, 
                        PAM = model_pam, PP = model_pp), groups = groups)
    #init_cc[:BCCharge]  = 0.0
    init_cc[:Phi] = state0["NegativeElectrode"]["CurrentCollector"]["phi"][1]
    init_pp[:Phi] = state0["PositiveElectrode"]["CurrentCollector"]["phi"][1]
    init_nam[:Phi] = state0["NegativeElectrode"]["ElectrodeActiveComponent"]["phi"][1]
    init_nam[:C] = state0["NegativeElectrode"]["ElectrodeActiveComponent"]["c"][1] 
    init_nam[:Phi] = state0["PositiveElectrode"]["ElectrodeActiveComponent"]["phi"][1]
    init_pam[:C] = state0["PositiveElectrode"]["ElectrodeActiveComponent"]["c"][1]
    init_elyte[:Phi] = state0["Electolyte"]["phi"][1]
    init_elyte[:C] = state0["Electrolyte"]["c"][1]

    init = Dict(
        :CC => init_cc,
        :NAM => init_nam,
        :ELYTE => init_elyte,
        :PAM => init_pam,
        :PP => init_pp
    )
    # state0 = setup_state(model, Dict(:CC => state0_cc, :NAM => state0_nam))
    state0 = setup_state(model, init)
    forces = Dict(
        :CC => nothing,
        :NAM => nothing,
        :ELYTE => nothing,
        :PAM => nothing,
        :PP => nothing
    )
    parameters = Dict(
        :CC => parm_cc,
        :NAM => parm_nam,
        :ELYTE => parm_elyte,
        :PAM => parm_pam,
        :PP => parm_pp
    )

    # setup coupling CC <-> NAM
    target = Dict( :model => :NAM,
                   :equation => :charge_conservation
    )
    source = Dict( :model => :CC,
                :equation => :charge_conservation)
    srange = Int64.(exported_all["model"]["NegativeElectrode"]["couplingTerm"]["couplingcells"][:,1])          
    trange = Int64.(exported_all["model"]["NegativeElectrode"]["couplingTerm"]["couplingcells"][:,2])
    intersection = ( srange, trange, Cells(), Cells())
    crosstermtype = InjectiveCrossTerm
    issym = true
    coupling = MultiModelCoupling(source,target, intersection; crosstype = crosstermtype, issym = issym)
    push!(model.couplings,coupling)

    # setup coupling NAM <-> ELYTE
    target = Dict( :model => :ELYTE,
                   :equation => :charge_conservation
    )
    source = Dict( :model => :NAM,
                :equation => :charge_conservation)

    srange=Int64.(exported_all["model"]["couplingTerms"][1]["couplingcells"][:,1])
    trange=Int64.(exported_all["model"]["couplingTerms"][1]["couplingcells"][:,2])
    intersection = ( srange, trange, Cells(), Cells())
    crosstermtype = InjectiveCrossTerm
    issym = true
    coupling = MultiModelCoupling(source,target, intersection; crosstype = crosstermtype, issym = issym)
    push!(model.couplings,coupling)

     # setup coupling PAM <-> ELYTE
    target = Dict( :model => :ELYTE,
        :equation => :charge_conservation
        )
    source = Dict( :model => :PAM,
        :equation => :charge_conservation)
    srange=Int64.(exported_all["model"]["couplingTerms"][2]["couplingcells"][:,1])
    trange=Int64.(exported_all["model"]["couplingTerms"][2]["couplingcells"][:,2])
    intersection = ( srange, trange, Cells(), Cells())
    crosstermtype = InjectiveCrossTerm
    issym = true
    coupling = MultiModelCoupling(source,target, intersection; crosstype = crosstermtype, issym = issym)
    push!(model.couplings,coupling)

    # setup coupling PP <-> PAM
    target = Dict( :model => :PAM,
            :equation => :charge_conservation
    )
    source = Dict( :model => :PP,
         :equation => :charge_conservation)
    srange = Int64.(exported_all["model"]["PositiveElectrode"]["couplingTerm"]["couplingcells"][:,1])          
    trange = Int64.(exported_all["model"]["PositiveElectrode"]["couplingTerm"]["couplingcells"][:,2])
    intersection = ( srange, trange, Cells(), Cells())
    crosstermtype = InjectiveCrossTerm
    issym = true
    coupling = MultiModelCoupling(source,target, intersection; crosstype = crosstermtype, issym = issym)
    push!(model.couplings,coupling)

 #########################

    #parameters = setup_parameters(model) # Dict(:CC => parm_cc, :NAM => parm_cc))
    #forces = Dict(:CC => state0_cc, :NAM => state0_nam)
    sim = Simulator(model, state0 = state0, parameters = parameters, copy_state = true)
    #timesteps = diff(LinRange(0, 10, 10)[2:end])
    timesteps = exported_all["schedule"]["step"]["val"][1:4]
    cfg = simulator_config(sim)
    cfg[:linear_solver] = nothing
    states = simulate(sim, timesteps, forces = forces, config = cfg)
    stateref = exported_all["states"]
    grids = Dict(:CC => G_cc,
                :NAM =>G_nam,
                :ELYTE => G_elyte,
                :PAM => G_pam,
                :PP => G_pp
                )
    return states, grids, state0, stateref, parameters, init, exported_all
end


@time states, grids, state0, stateref, parameters, init, exported_all = test_ac();
states = states[1]
refstep=1
## f= plot_interactive(G, states);
#fields = ["CurrentCollector","ElectrodeActiveMaterial"]

#phi_ref = stateref[10]["NegativeElectrode"]["CurrentCollector"]["phi"]
#j_ref = stateref[10]["NegativeElectrode"]["CurrentCollector"]["j"]
## set up for current collector first
G = grids[:CC]
x = G["cells"]["centroids"]
xf= G["faces"]["centroids"][end]
xfi= G["faces"]["centroids"][2:end-1]
#state0=states[1]
p1 = Plots.plot(x,state0[:CC][:Phi];title="Phi")
#Plots.plot!(p1,x,phi_ref;linecolor="red")
p2 = Plots.plot(xfi,states[1][:CC].TPkGrad_Phi[1:2:end-1];title="Flux",markershape=:circle)
p3 = Plots.plot(;title="C")
    #p2 = Plots.plot([xf[end]],[state0[:BCCharge][1]];title="Flux")
    #Plots.plot!(p2,xfi,j_ref;linecolor="red")
fields = ["CurrentCollector","ElectrodeActiveComponent"]
components = ["NegativeElectrode","PositiveElectrode"]
for component = components
    for field in fields
        G = exported_all["model"]["NegativeElectrode"][field]["G"]
        x = G["cells"]["centroids"]
        xf= G["faces"]["centroids"][end]
        xfi= G["faces"]["centroids"][2:end-1]
        #state0=states[1]
        state = stateref[refstep]["NegativeElectrode"]
        phi_ref = state[field]["phi"]
        j_ref = state[field]["j"]
        Plots.plot!(p1,x,phi_ref;linecolor="red")
        Plots.plot!(p2,xfi,j_ref;title="Flux",linecolor="red")
        if haskey(state[field],"c")
            c = state[field]["c"]
            Plots.plot!(p3,x,c;title="Flux",linecolor="red")
        end
    end
end
fields = ["Electrolyte"]
for field in fields
    G = exported_all["model"][field]["G"]
    x = G["cells"]["centroids"]
    xf= G["faces"]["centroids"][end]
    xfi= G["faces"]["centroids"][2:end-1]
    #state0=states[1]
    state = stateref[refstep]
    phi_ref = state[field]["phi"]
    j_ref = state[field]["j"]
    Plots.plot!(p1,x,phi_ref;linecolor="red")
    Plots.plot!(p2,xfi,j_ref;title="Flux",linecolor="red")
    if haskey(state[field],"c")
        c = state[field]["c"]
        Plots.plot!(p3,x,c;title="Flux",linecolor="red")
    end
end
#display(plot!(p1, p2, layout = (1, 2), legend = false))
##
for key in keys(grids)
    G = grids[key]
    x = G["cells"]["centroids"]
    xf= G["faces"]["centroids"][end]
    xfi= G["faces"]["centroids"][2:end-1]     
    p=plot(p1, p2, layout = (1, 2), legend = false)
    Plots.plot!(p1,x,states[end][key].Phi;markershape=:circle,linestyle=:dot, seriestype = :scatter)
    Plots.plot!(p2,xfi,states[end][key].TPkGrad_Phi[1:2:end-1];markershape=:circle,linestyle=:dot, seriestype = :scatter)
    if(haskey(states[end][key],:C))
        cc=states[end][key].C
        Plots.plot!(p3,x,cc;markershape=:circle,linestyle=:dot, seriestype = :scatter)
    end
    display(plot!(p1, p2,p3,layout = (3, 1), legend = false))
end
##
#for (n,state) in enumerate(states)
#        println(n)
#        Plots.plot!(p1,x,states[n].Phi)
#        Plots.plot!(p2,xfi,states[n].TPkGrad_Phi[1:2:end-1])
#        display(plot!(p1, p2, layout = (1, 2), legend = false))
#end
##