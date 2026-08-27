//==============================================================================
// File        : axi4_vip_env_config.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Configuration object for the AXI4 VIP environment.
//               Holds agent-level configs, virtual interface handles,
//               and feature enables (scoreboard, coverage).
//
//               Usage from test:
//                 axi4_vip_env_config env_cfg;
//                 env_cfg = axi4_vip_env_config::type_id::create("env_cfg");
//                 env_cfg.master_vif = ...; // assign from config_db or direct
//                 env_cfg.master_agent_cfg.is_active = UVM_ACTIVE;
//                 uvm_config_db#(axi4_vip_env_config)::set(..., "cfg", env_cfg);
//
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_vip_env_config extends uvm_object;

    `uvm_object_utils(axi4_vip_env_config)

    // =========================================================================
    // Agent configuration objects
    //   Created with defaults in constructor (both ACTIVE, coverage ON).
    //   Tests can override individual fields before env build_phase.
    // =========================================================================
    axi4_agent_config master_agent_cfg;
    axi4_agent_config slave_agent_cfg;

    // =========================================================================
    // Virtual interfaces
    //   master_vif : AXI4 interface on master side of DUT (required)
    //   slave_vif  : AXI4 interface on slave side of DUT (optional)
    //
    //   If slave_vif is null, master_vif is used for both agents.
    //   This is the "passthrough mode" - both agents observe the same bus.
    // =========================================================================
    virtual axi4_if master_vif;
    virtual axi4_if slave_vif;

    // =========================================================================
    // Environment feature enables
    // =========================================================================
    bit has_scoreboard = 1;     // Create scoreboard (master ↔ slave comparison)
    bit has_coverage   = 1;     // Create functional coverage collectors

    // =========================================================================
    // Constructor - creates default agent configs
    // =========================================================================
    function new(string name = "axi4_vip_env_config");
        super.new(name);
        master_agent_cfg = axi4_agent_config::type_id::create("master_agent_cfg");
        slave_agent_cfg  = axi4_agent_config::type_id::create("slave_agent_cfg");
    endfunction : new

endclass : axi4_vip_env_config