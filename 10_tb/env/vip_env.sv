//=============================================================================
// File        : vip_env.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Top-level bridge verification environment.
//               Included inside the bridge package.
//=============================================================================

class vip_env extends uvm_env;

    `uvm_component_utils(vip_env)

    //-------------------------------------------------------------------------
    // Configuration handles
    //-------------------------------------------------------------------------
    axi4_mst_agent_cfg axi_cfg;
    ahb_slv_agent_cfg  ahb_cfg;

    //-------------------------------------------------------------------------
    // Environment components
    //-------------------------------------------------------------------------
    axi4_mst_agent   axi_agent;
    ahb_slv_agent    ahb_agent;
    virtual_sequencer vseqr;
    predictor         pred;
    scoreboard        scb;
    e2e_cov           cov;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(axi4_mst_agent_cfg)::get(this, "", "axi_cfg",
                                                     axi_cfg))
            `uvm_fatal(get_type_name(), "AXI4 master agent config not found")
        if (!uvm_config_db#(ahb_slv_agent_cfg)::get(this, "", "ahb_cfg",
                                                    ahb_cfg))
            `uvm_fatal(get_type_name(), "AHB-Lite slave agent config not found")

        uvm_config_db#(axi4_mst_agent_cfg)::set(this, "axi_agent", "cfg",
                                                axi_cfg);
        uvm_config_db#(ahb_slv_agent_cfg)::set(this, "ahb_agent", "cfg",
                                               ahb_cfg);

        axi_agent = axi4_mst_agent::type_id::create("axi_agent", this);
        ahb_agent = ahb_slv_agent::type_id::create("ahb_agent", this);
        vseqr     = virtual_sequencer::type_id::create("vseqr", this);
        pred      = predictor::type_id::create("pred", this);
        scb       = scoreboard::type_id::create("scb", this);
        cov       = e2e_cov::type_id::create("cov", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Connect phase
    //-------------------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        axi_agent.req_ap.connect(pred.axi_request_export);

        pred.expected_ahb_ap.connect(scb.expected_ahb_export);
        ahb_agent.ap.connect(scb.actual_ahb_export);
        pred.expected_axi_ap.connect(scb.expected_axi_export);
        axi_agent.ap.connect(scb.actual_axi_export);

        pred.expected_axi_ap.connect(cov.axi_req_export);
        pred.expected_ahb_ap.connect(cov.expected_ahb_export);
        ahb_agent.ap.connect(cov.actual_ahb_export);
        axi_agent.ap.connect(cov.axi_rsp_export);

        if (axi_cfg.is_active == UVM_ACTIVE)
            vseqr.axi_sqr = axi_agent.sqr;
        if (ahb_cfg.is_active == UVM_ACTIVE)
            vseqr.ahb_sqr = ahb_agent.sqr;
    endfunction : connect_phase

    //-------------------------------------------------------------------------
    // Reset handling
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        forever begin
            @(negedge axi_cfg.vif.rst_n);
            @(posedge axi_cfg.vif.clk);
            if (axi_cfg.vif.rst_n !== 1'b0)
                continue;

            pred.reset_state();
            scb.reset_state();
            cov.reset_state();
            wait (axi_cfg.vif.rst_n === 1'b1);
        end
    endtask : run_phase

endclass : vip_env