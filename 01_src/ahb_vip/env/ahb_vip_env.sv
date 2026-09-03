//=============================================================================
// File        : ahb_vip_env.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite VIP environment. Instantiates and connects the master
//               agent, slave agent, scoreboard, and per-agent coverage. Monitor
//               analysis ports feed the scoreboard and coverage collectors.
//               Scoreboard and coverage are optional (ahb_vip_env_config).
//=============================================================================

class ahb_vip_env extends uvm_env;

    `uvm_component_utils(ahb_vip_env)

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    ahb_vip_env_config cfg;

    //-------------------------------------------------------------------------
    // Sub-components
    //-------------------------------------------------------------------------
    ahb_master_agent master_agent;
    ahb_slave_agent  slave_agent;
    ahb_scoreboard   scb;          // Created if cfg.has_scoreboard
    ahb_coverage     master_cov;   // Created if cfg.has_coverage
    ahb_coverage     slave_cov;    // Created if cfg.has_coverage

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - propagate agent configs and virtual interfaces via
    // config_db, then create the agents and the optional checkers
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(ahb_vip_env_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info(get_type_name(),
                      "No env config found in config_db - using defaults", UVM_MEDIUM)
            cfg = ahb_vip_env_config::type_id::create("cfg");
        end

        uvm_config_db#(ahb_agent_config)::set(this, "master_agent", "cfg", cfg.master_agent_cfg);
        uvm_config_db#(ahb_agent_config)::set(this, "slave_agent", "cfg", cfg.slave_agent_cfg);

        // Master vif is required
        if (cfg.master_vif == null)
            `uvm_fatal(get_type_name(), "master_vif is null - set it in ahb_vip_env_config before build")

        uvm_config_db#(virtual ahb_if)::set(this, "master_agent", "vif", cfg.master_vif);

        // Slave side: slave_vif if provided, otherwise reuse master_vif
        // (passthrough mode - both agents observe the same bus)
        if (cfg.slave_vif != null) begin
            uvm_config_db#(virtual ahb_if)::set(this, "slave_agent", "vif", cfg.slave_vif);
        end else begin
            uvm_config_db#(virtual ahb_if)::set(this, "slave_agent", "vif", cfg.master_vif);
            `uvm_info(get_type_name(), "slave_vif not set - reusing master_vif (passthrough mode)", UVM_MEDIUM)
        end

        master_agent = ahb_master_agent::type_id::create("master_agent", this);
        slave_agent  = ahb_slave_agent::type_id::create("slave_agent", this);

        if (cfg.has_scoreboard) begin
            scb = ahb_scoreboard::type_id::create("scb", this);
            `uvm_info(get_type_name(), "Scoreboard created", UVM_MEDIUM)
        end

        if (cfg.has_coverage) begin
            master_cov = ahb_coverage::type_id::create("master_cov", this);
            slave_cov  = ahb_coverage::type_id::create("slave_cov", this);
            `uvm_info(get_type_name(), "Coverage collectors created", UVM_MEDIUM)
        end
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Connect phase - monitor analysis ports to scoreboard and coverage
    //-------------------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (cfg.has_scoreboard) begin
            master_agent.mon.ap.connect(scb.master_export);
            slave_agent.mon.ap.connect(scb.slave_export);
            `uvm_info(get_type_name(),
                      "Scoreboard connected: master_mon.ap -> scb, slave_mon.ap -> scb", UVM_HIGH)
        end

        if (cfg.has_coverage) begin
            master_agent.mon.ap.connect(master_cov.analysis_export);
            slave_agent.mon.ap.connect(slave_cov.analysis_export);
            // Raw HTRANS stream - the only source of IDLE coverage
            master_agent.mon.trans_ap.connect(master_cov.trans_export);
            slave_agent.mon.trans_ap.connect(slave_cov.trans_export);
            `uvm_info(get_type_name(),
                      "Coverage connected: master_mon.ap/trans_ap -> master_cov, slave_mon.ap/trans_ap -> slave_cov", UVM_HIGH)
        end
    endfunction : connect_phase

endclass : ahb_vip_env