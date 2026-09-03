//=============================================================================
// File        : ahb_base_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Base UVM test for the AHB-Lite VIP. Builds the environment in
//               passthrough mode (master drives, slave responds on the same
//               bus) and provides build, end_of_elaboration and report phases.
//               Derived tests supply their own run_phase.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_BASE_TEST_INCLUDED_
`define AHB_BASE_TEST_INCLUDED_

class ahb_base_test extends uvm_test;

    `uvm_component_utils(ahb_base_test)

    //-------------------------------------------------------------------------
    // Environment and configuration
    //-------------------------------------------------------------------------
    ahb_vip_env        env;
    ahb_vip_env_config env_cfg;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - create env_cfg, fetch the vif from tb_top, build the env.
    // Derived tests customise env_cfg after calling super.build_phase()
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Defaults: both agents ACTIVE, scoreboard ON, coverage ON
        env_cfg = ahb_vip_env_config::type_id::create("env_cfg");

        if (!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", env_cfg.master_vif))
            `uvm_fatal(get_type_name(),
                       "Virtual interface 'vif' not found - must be set by tb_top")

        // slave_vif remains null -> passthrough mode (both agents on same bus)

        uvm_config_db#(ahb_vip_env_config)::set(this, "env", "cfg", env_cfg);

        env = ahb_vip_env::type_id::create("env", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // End of elaboration - print UVM component topology
    //-------------------------------------------------------------------------
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction : end_of_elaboration_phase

    //-------------------------------------------------------------------------
    // Report phase - print final test result
    //-------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        uvm_report_server srv;
        int unsigned err_count;

        super.report_phase(phase);

        srv = uvm_report_server::get_server();
        err_count = srv.get_severity_count(UVM_ERROR) + srv.get_severity_count(UVM_FATAL);

        if (err_count == 0)
            `uvm_info(get_type_name(), "\n=== TEST PASSED ===\n", UVM_NONE)
        else
            `uvm_info(get_type_name(), $sformatf("\n=== TEST FAILED === (%0d errors)\n", err_count), UVM_NONE)
    endfunction : report_phase

endclass : ahb_base_test

`endif // AHB_BASE_TEST_INCLUDED_