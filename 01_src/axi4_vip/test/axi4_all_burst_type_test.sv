//==============================================================================
// File        : axi4_all_burst_type_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test for all AXI4 burst types (FIXED, INCR, WRAP).
//               Runs the all-burst-type sequence with one write+read pair
//               per burst type. Total 6 transactions - ideal for waveform
//               comparison of address calculation across burst modes.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_ALL_BURST_TYPE_TEST_INCLUDED_
`define AXI4_ALL_BURST_TYPE_TEST_INCLUDED_

class axi4_all_burst_type_test extends axi4_base_test;

    `uvm_component_utils(axi4_all_burst_type_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_all_burst_type_seq burst_seq;
        phase.raise_objection(this, "axi4_all_burst_type_test: starting");

        `uvm_info(get_type_name(),
                  "Starting all burst types test (FIXED + INCR + WRAP, 6 transactions)",
                  UVM_LOW)

        burst_seq = axi4_all_burst_type_seq::type_id::create("burst_seq");
        burst_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (50) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  "All burst types test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_all_burst_type_test: complete");
    endtask : run_phase

endclass : axi4_all_burst_type_test

`endif // AXI4_ALL_BURST_TYPE_TEST_INCLUDED_