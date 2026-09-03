//==============================================================================
// File        : axi4_master_agent.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 master agent.
//               Encapsulates sequencer, driver, and monitor for the master
//               side of an AXI4 interface. Supports active (driver + sequencer
//               + monitor) and passive (monitor only) modes via config.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_master_agent extends uvm_agent;

    `uvm_component_utils(axi4_master_agent)

    // =========================================================================
    // Sub-components
    // =========================================================================
    axi4_agent_config     cfg;
    axi4_master_sequencer sqr;      // Created only in ACTIVE mode
    axi4_master_driver    drv;      // Created only in ACTIVE mode
    axi4_master_monitor   mon;      // Always created

    // Virtual interface handle
    virtual axi4_if vif;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase
    //   1. Get or create agent config
    //   2. Get virtual interface and propagate to children
    //   3. Create sub-components based on active/passive mode
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Config
        if (!uvm_config_db#(axi4_agent_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info(get_type_name(),
                      "No agent config found - using defaults (ACTIVE, coverage ON)",
                      UVM_MEDIUM)
            cfg = axi4_agent_config::type_id::create("cfg");
        end

        // Sync UVM built-in is_active field with our config
        is_active = cfg.is_active;

        // Virtual Interface
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")

        // Propagate vif to children via config_db
        uvm_config_db#(virtual axi4_if)::set(this, "mon", "vif", vif);

        // Monitor (always created)
        mon = axi4_master_monitor::type_id::create("mon", this);

        // Driver + Sequencer (ACTIVE mode only)
        if (cfg.is_active == UVM_ACTIVE) begin
            uvm_config_db#(virtual axi4_if)::set(this, "drv", "vif", vif);
            drv = axi4_master_driver::type_id::create("drv", this);
            sqr = axi4_master_sequencer::type_id::create("sqr", this);
            `uvm_info(get_type_name(), "ACTIVE mode - driver + sequencer created", UVM_MEDIUM)
        end else begin
            `uvm_info(get_type_name(), "PASSIVE mode - monitor only", UVM_MEDIUM)
        end
    endfunction : build_phase

    // =========================================================================
    // Connect phase
    //   Connect sequencer -> driver (ACTIVE mode only)
    // =========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (cfg.is_active == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction : connect_phase

endclass : axi4_master_agent