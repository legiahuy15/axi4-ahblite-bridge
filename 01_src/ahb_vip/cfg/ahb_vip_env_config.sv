//=============================================================================
// File        : ahb_vip_env_config.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Configuration object for the AHB-Lite VIP environment. Holds
//               agent configs, virtual interfaces, and feature enables
//               (scoreboard, coverage).
//=============================================================================

class ahb_vip_env_config extends uvm_object;

    `uvm_object_utils(ahb_vip_env_config)

    //-------------------------------------------------------------------------
    // Agent configuration objects - defaulted in the constructor, overridable
    // by a test before the env build_phase
    //-------------------------------------------------------------------------
    ahb_agent_config master_agent_cfg;
    ahb_agent_config slave_agent_cfg;

    //-------------------------------------------------------------------------
    // Virtual interfaces
    //   master_vif : master side of the DUT (required)
    //   slave_vif  : slave side of the DUT (optional). Null -> master_vif
    //                serves both agents (passthrough, one shared bus)
    //-------------------------------------------------------------------------
    virtual ahb_if master_vif;
    virtual ahb_if slave_vif;

    //-------------------------------------------------------------------------
    // Environment feature enables
    //-------------------------------------------------------------------------
    bit has_scoreboard = 1;     // Create scoreboard (master-slave comparison)
    bit has_coverage   = 1;     // Create functional coverage collectors

    //-------------------------------------------------------------------------
    // Constructor - creates default agent configs
    //-------------------------------------------------------------------------
    function new(string name = "ahb_vip_env_config");
        super.new(name);
        master_agent_cfg = ahb_agent_config::type_id::create("master_agent_cfg");
        slave_agent_cfg  = ahb_agent_config::type_id::create("slave_agent_cfg");
    endfunction : new

endclass : ahb_vip_env_config