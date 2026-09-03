//==============================================================================
// File        : axi4_exclusive_test.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : Test for AXI4 exclusive locks and EXOKAY responses.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_EXCLUSIVE_TEST_INCLUDED_
`define AXI4_EXCLUSIVE_TEST_INCLUDED_

class axi4_exclusive_test extends axi4_base_test;

    `uvm_component_utils(axi4_exclusive_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_exclusive_seq excl_seq;
        phase.raise_objection(this, "axi4_exclusive_test: starting");

        `uvm_info(get_type_name(), "Starting exclusive access test", UVM_LOW)

        excl_seq = axi4_exclusive_seq::type_id::create("excl_seq");
        excl_seq.num_iterations = 10;
        excl_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Exclusive access test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_exclusive_test: complete");
    endtask : run_phase

endclass : axi4_exclusive_test

`endif // AXI4_EXCLUSIVE_TEST_INCLUDED_