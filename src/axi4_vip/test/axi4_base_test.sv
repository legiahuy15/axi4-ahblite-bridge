//==============================================================================
// File        : axi4_base_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Base UVM test for AXI4 VIP.
//               Sets up the environment with a shared interface (passthrough
//               mode - master drives, slave responds on the same bus).
//               Only provides build, end_of_elaboration, and report phases.
//               Derived tests implement their own run_phase with specific
//               sequences and test scenarios.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_BASE_TEST_INCLUDED_
`define AXI4_BASE_TEST_INCLUDED_

class axi4_base_test extends uvm_test;

    `uvm_component_utils(axi4_base_test)

    // =========================================================================
    // Environment and configuration
    // =========================================================================
    axi4_vip_env        env;
    axi4_vip_env_config env_cfg;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase
    //   1. Create environment config
    //   2. Get virtual interface from tb_top
    //   3. Push config to environment
    //   4. Create environment
    //
    //   Derived tests can override build_phase to customise env_cfg
    //   AFTER calling super.build_phase() but BEFORE env is built:
    //
    //     function void build_phase(uvm_phase phase);
    //         super.build_phase(phase);
    //         env_cfg.slave_agent_cfg.ready_delay_max = 5;
    //         env_cfg.has_coverage = 0;
    //     endfunction
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Create env config (default: both agents ACTIVE, scoreboard ON, coverage ON)
        env_cfg = axi4_vip_env_config::type_id::create("env_cfg");

        // Get virtual interface set by tb_top
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", env_cfg.master_vif))
            `uvm_fatal(get_type_name(),
                       "Virtual interface 'vif' not found - must be set by tb_top")

        // slave_vif remains null -> passthrough mode (both agents on same bus)

        // Push config to environment
        uvm_config_db#(axi4_vip_env_config)::set(this, "env", "cfg", env_cfg);

        // Create environment
        env = axi4_vip_env::type_id::create("env", this);
    endfunction : build_phase

    // =========================================================================
    // End of elaboration - print UVM component topology
    // =========================================================================
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction : end_of_elaboration_phase

    // =========================================================================
    // Report phase - print final test result
    // =========================================================================
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

endclass : axi4_base_test

`endif // AXI4_BASE_TEST_INCLUDED_