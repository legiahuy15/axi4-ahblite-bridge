//=============================================================================
// File        : axi4_mst_agent.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 master agent.
//               Included inside the bridge package.
//=============================================================================

class axi4_mst_agent extends uvm_agent;

    `uvm_component_utils(axi4_mst_agent)

    //-------------------------------------------------------------------------
    // Agent components
    //-------------------------------------------------------------------------
    axi4_mst_agent_cfg cfg;
    axi4_mst_sequencer sqr;
    axi4_mst_driver    drv;
    axi4_mst_monitor   mon;
    axi4_mst_coverage  cov;

    // Agent-level analysis ports
    uvm_analysis_port #(axi4_transaction) req_ap;
    uvm_analysis_port #(axi4_transaction) ap;

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

        req_ap = new("req_ap", this);
        ap     = new("ap", this);

        if (!uvm_config_db#(axi4_mst_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_type_name(), "AXI4 master agent config not found")
        if (!cfg.is_valid())
            `uvm_fatal(get_type_name(), "Invalid AXI4 master agent config")

        is_active = cfg.is_active;
        uvm_config_db#(axi4_mst_agent_cfg)::set(this, "mon", "cfg", cfg);
        mon = axi4_mst_monitor::type_id::create("mon", this);

        if (cfg.has_coverage)
            cov = axi4_mst_coverage::type_id::create("cov", this);

        if (is_active == UVM_ACTIVE) begin
            uvm_config_db#(axi4_mst_agent_cfg)::set(this, "drv", "cfg", cfg);
            sqr = axi4_mst_sequencer::type_id::create("sqr", this);
            sqr.cfg = cfg;
            drv = axi4_mst_driver::type_id::create("drv", this);
        end
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Connect phase
    //-------------------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        mon.req_ap.connect(req_ap);
        mon.ap.connect(ap);

        if (cfg.has_coverage)
            mon.ap.connect(cov.analysis_export);

        if (is_active == UVM_ACTIVE)
            drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction : connect_phase

endclass : axi4_mst_agent