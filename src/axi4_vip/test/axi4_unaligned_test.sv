//==============================================================================
// File        : axi4_unaligned_test.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : Test for AXI4 unaligned access transactions.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_UNALIGNED_TEST_INCLUDED_
`define AXI4_UNALIGNED_TEST_INCLUDED_

class axi4_unaligned_test extends axi4_base_test;

    `uvm_component_utils(axi4_unaligned_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_unaligned_seq unalign_seq;
        phase.raise_objection(this, "axi4_unaligned_test: starting");

        `uvm_info(get_type_name(), "Starting unaligned access test", UVM_LOW)

        unalign_seq = axi4_unaligned_seq::type_id::create("unalign_seq");
        unalign_seq.num_txns = 40;
        unalign_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Unaligned access test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_unaligned_test: complete");
    endtask : run_phase

endclass : axi4_unaligned_test

`endif // AXI4_UNALIGNED_TEST_INCLUDED_