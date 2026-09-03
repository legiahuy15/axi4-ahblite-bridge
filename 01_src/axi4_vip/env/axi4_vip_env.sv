//==============================================================================
// File        : axi4_vip_env.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 VIP environment.
//               Top-level UVM environment that instantiates and connects:
//                 - Master agent  (sequencer + driver + monitor)
//                 - Slave agent   (sequencer + driver + monitor)
//                 - Scoreboard    (master ↔ slave transaction comparison)
//                 - Coverage      (one collector per agent)
//
//               Scoreboard and coverage are optional - controlled via
//               axi4_vip_env_config::has_scoreboard / has_coverage.
//
//               Connection topology:
//                 master_agent.mon.ap -> scb.master_export
//                 slave_agent.mon.ap  -> scb.slave_export
//                 master_agent.mon.ap -> master_cov.analysis_export
//                 slave_agent.mon.ap  -> slave_cov.analysis_export
//
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_vip_env extends uvm_env;

    `uvm_component_utils(axi4_vip_env)

    // =========================================================================
    // Configuration
    // =========================================================================
    axi4_vip_env_config cfg;

    // =========================================================================
    // Sub-components
    // =========================================================================
    axi4_master_agent master_agent;
    axi4_slave_agent  slave_agent;
    axi4_scoreboard   scb;          // Created if cfg.has_scoreboard
    axi4_coverage     master_cov;   // Created if cfg.has_coverage
    axi4_coverage     slave_cov;    // Created if cfg.has_coverage

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase
    //   1. Get or create environment config
    //   2. Propagate agent configs and virtual interfaces via config_db
    //   3. Create agents (always)
    //   4. Create scoreboard and coverage (if enabled)
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Environment config
        if (!uvm_config_db#(axi4_vip_env_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info(get_type_name(),
                      "No env config found in config_db - using defaults", UVM_MEDIUM)
            cfg = axi4_vip_env_config::type_id::create("cfg");
        end

        // Propagate agent configs
        uvm_config_db#(axi4_agent_config)::set(this, "master_agent", "cfg", cfg.master_agent_cfg);
        uvm_config_db#(axi4_agent_config)::set(this, "slave_agent", "cfg", cfg.slave_agent_cfg);

        // Propagate virtual interfaces
        //   Master side (required)
        if (cfg.master_vif == null)
            `uvm_fatal(get_type_name(), "master_vif is null - set it in axi4_vip_env_config before build")

        uvm_config_db#(virtual axi4_if)::set(this, "master_agent", "vif", cfg.master_vif);

        //   Slave side: use slave_vif if provided, otherwise reuse master_vif
        //   (passthrough mode - both agents observe the same bus)
        if (cfg.slave_vif != null) begin
            uvm_config_db#(virtual axi4_if)::set(this, "slave_agent", "vif", cfg.slave_vif);
        end else begin
            uvm_config_db#(virtual axi4_if)::set(this, "slave_agent", "vif", cfg.master_vif);
            `uvm_info(get_type_name(), "slave_vif not set - reusing master_vif (passthrough mode)", UVM_MEDIUM)
        end

        // Create agents (always)
        master_agent = axi4_master_agent::type_id::create("master_agent", this);
        slave_agent  = axi4_slave_agent::type_id::create("slave_agent", this);

        // Create scoreboard (optional)
        if (cfg.has_scoreboard) begin
            scb = axi4_scoreboard::type_id::create("scb", this);
            `uvm_info(get_type_name(), "Scoreboard created", UVM_MEDIUM)
        end

        // Create coverage collectors (optional)
        if (cfg.has_coverage) begin
            master_cov = axi4_coverage::type_id::create("master_cov", this);
            slave_cov  = axi4_coverage::type_id::create("slave_cov", this);
            `uvm_info(get_type_name(), "Coverage collectors created", UVM_MEDIUM)
        end
    endfunction : build_phase

    // =========================================================================
    // Connect phase
    //   Wire monitor analysis ports to scoreboard and coverage collectors.
    // =========================================================================
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // Scoreboard connections
        if (cfg.has_scoreboard) begin
            master_agent.mon.ap.connect(scb.master_export);
            slave_agent.mon.ap.connect(scb.slave_export);
            `uvm_info(get_type_name(),
                      "Scoreboard connected: master_mon.ap -> scb, slave_mon.ap -> scb", UVM_HIGH)
        end

        // Coverage connections
        if (cfg.has_coverage) begin
            master_agent.mon.ap.connect(master_cov.analysis_export);
            slave_agent.mon.ap.connect(slave_cov.analysis_export);
            `uvm_info(get_type_name(),
                      "Coverage connected: master_mon.ap -> master_cov, slave_mon.ap -> slave_cov", UVM_HIGH)
        end
    endfunction : connect_phase

endclass : axi4_vip_env