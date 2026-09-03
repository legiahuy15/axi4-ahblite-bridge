//==============================================================================
// File        : axi4_burst_sweep_test.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : Test to sweep all AXI4 burst configurations and sizes.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_BURST_SWEEP_TEST_INCLUDED_
`define AXI4_BURST_SWEEP_TEST_INCLUDED_

class axi4_burst_sweep_test extends axi4_base_test;

    `uvm_component_utils(axi4_burst_sweep_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_burst_sweep_seq sweep_seq;
        phase.raise_objection(this, "axi4_burst_sweep_test: starting");

        `uvm_info(get_type_name(), "Starting burst parameters sweep test (including error injection)", UVM_LOW)

        sweep_seq = axi4_burst_sweep_seq::type_id::create("sweep_seq");
        sweep_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Burst sweep test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_burst_sweep_test: complete");
    endtask : run_phase

endclass : axi4_burst_sweep_test

`endif // AXI4_BURST_SWEEP_TEST_INCLUDED_