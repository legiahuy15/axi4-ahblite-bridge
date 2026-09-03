//==============================================================================
// File        : axi4_back_to_back_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test for back-to-back pipelined transactions.
//               Fires consecutive writes then reads without waiting for
//               individual completions. Tests bus throughput and handshake
//               pipelining. 8 transactions - ideal for waveform capture.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_BACK_TO_BACK_TEST_INCLUDED_
`define AXI4_BACK_TO_BACK_TEST_INCLUDED_

class axi4_back_to_back_test extends axi4_base_test;

    `uvm_component_utils(axi4_back_to_back_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_back_to_back_seq b2b_seq;
        phase.raise_objection(this, "axi4_back_to_back_test: starting");

        `uvm_info(get_type_name(),
                  "Starting back-to-back pipeline test (8 transactions)",
                  UVM_LOW)

        b2b_seq = axi4_back_to_back_seq::type_id::create("b2b_seq");
        b2b_seq.start(env.master_agent.sqr);

        // Drain time - allow last responses to propagate
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  "Back-to-back pipeline test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_back_to_back_test: complete");
    endtask : run_phase

endclass : axi4_back_to_back_test

`endif // AXI4_BACK_TO_BACK_TEST_INCLUDED_