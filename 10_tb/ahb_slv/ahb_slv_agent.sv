//=============================================================================
// File        : ahb_slv_agent.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite slave agent.
//               Included inside the bridge package.
//=============================================================================

class ahb_slv_agent extends uvm_agent;

    `uvm_component_utils(ahb_slv_agent)

    //-------------------------------------------------------------------------
    // Agent components
    //-------------------------------------------------------------------------
    ahb_slv_agent_cfg cfg;
    ahb_slv_sequencer sqr;
    ahb_slv_driver    drv;
    ahb_slv_monitor   mon;
    ahb_slv_coverage  cov;

    // Agent-level analysis ports
    uvm_analysis_port #(ahb_transfer) ap;
    uvm_analysis_port #(ahb_trans_e)  trans_ap;

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

        ap       = new("ap", this);
        trans_ap = new("trans_ap", this);

        if (!uvm_config_db#(ahb_slv_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_type_name(), "AHB-Lite slave agent config not found")
        if (!cfg.is_valid())
            `uvm_fatal(get_type_name(), "Invalid AHB-Lite slave agent config")

        is_active = cfg.is_active;
        uvm_config_db#(ahb_slv_agent_cfg)::set(this, "mon", "cfg", cfg);
        mon = ahb_slv_monitor::type_id::create("mon", this);

        if (cfg.has_coverage)
            cov = ahb_slv_coverage::type_id::create("cov", this);

        if (is_active == UVM_ACTIVE) begin
            uvm_config_db#(ahb_slv_agent_cfg)::set(this, "drv", "cfg", cfg);
            sqr = ahb_slv_sequencer::type_id::create("sqr", this);
            drv = ahb_slv_driver::type_id::create("drv", this);
        end
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Connect phase
    //-------------------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        mon.ap.connect(ap);
        mon.trans_ap.connect(trans_ap);

        if (cfg.has_coverage) begin
            mon.ap.connect(cov.analysis_export);
            mon.trans_ap.connect(cov.trans_export);
        end

        if (is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
            drv.sqr = sqr;
        end
    endfunction : connect_phase

endclass : ahb_slv_agent