//==============================================================================
// File        : axi4_slave_agent.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 slave agent.
//               Encapsulates sequencer, driver, and monitor for the slave
//               side of an AXI4 interface. Supports active and passive modes.
//               In active mode, the slave driver operates reactively -
//               responding to incoming master requests with configurable
//               back-pressure and response delays.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_slave_agent extends uvm_agent;

    `uvm_component_utils(axi4_slave_agent)

    // =========================================================================
    // Sub-components
    // =========================================================================
    axi4_agent_config    cfg;
    axi4_slave_sequencer sqr;       // Created only in ACTIVE mode (future use)
    axi4_slave_driver    drv;       // Created only in ACTIVE mode
    axi4_slave_monitor   mon;       // Always created

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
    //   4. Forward delay config to slave driver
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
        mon = axi4_slave_monitor::type_id::create("mon", this);

        // Driver + Sequencer (ACTIVE mode only)
        if (cfg.is_active == UVM_ACTIVE) begin
            // Propagate vif and delay config to driver
            uvm_config_db#(virtual axi4_if)::set(this, "drv", "vif", vif);
            uvm_config_db#(int unsigned)::set(this, "drv", "ready_delay_min", cfg.ready_delay_min);
            uvm_config_db#(int unsigned)::set(this, "drv", "ready_delay_max", cfg.ready_delay_max);
            uvm_config_db#(int unsigned)::set(this, "drv", "resp_delay_min",  cfg.resp_delay_min);
            uvm_config_db#(int unsigned)::set(this, "drv", "resp_delay_max",  cfg.resp_delay_max);

            drv = axi4_slave_driver::type_id::create("drv", this);
            sqr = axi4_slave_sequencer::type_id::create("sqr", this);

            `uvm_info(get_type_name(),
                      $sformatf("ACTIVE mode - ready_delay=[%0d:%0d] resp_delay=[%0d:%0d]",
                                cfg.ready_delay_min, cfg.ready_delay_max,
                                cfg.resp_delay_min,  cfg.resp_delay_max), UVM_MEDIUM)
        end else begin
            `uvm_info(get_type_name(), "PASSIVE mode - monitor only", UVM_MEDIUM)
        end
    endfunction : build_phase

    // =========================================================================
    // Connect phase
    //   Note: Slave driver is currently reactive (does not use sequencer).
    //   The sequencer is created for future sequence-driven responses.
    //   Connection will be added when the driver supports seq_item_port.
    // =========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Future: when slave driver supports sequence-driven mode:
        // if (cfg.is_active == UVM_ACTIVE)
        //     drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction : connect_phase

endclass : axi4_slave_agent