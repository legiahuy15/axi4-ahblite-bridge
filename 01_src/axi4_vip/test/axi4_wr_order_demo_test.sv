//==============================================================================
// File        : axi4_wr_order_demo_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test for AXI4 write channel ordering demo.
//               Runs the write ordering demo sequence to demonstrate
//               PARALLEL, AW_BEFORE_W, and W_BEFORE_AW modes.
//               Only 3 transactions - ideal for waveform capture.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_WR_ORDER_DEMO_TEST_INCLUDED_
`define AXI4_WR_ORDER_DEMO_TEST_INCLUDED_

class axi4_wr_order_demo_test extends axi4_base_test;

    `uvm_component_utils(axi4_wr_order_demo_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_wr_order_demo_seq wr_order_seq;
        phase.raise_objection(this, "axi4_wr_order_demo_test: starting");

        `uvm_info(get_type_name(),
                  "Starting write channel ordering demo test (3 transactions)",
                  UVM_LOW)

        wr_order_seq = axi4_wr_order_demo_seq::type_id::create("wr_order_seq");
        wr_order_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (50) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  "Write channel ordering demo test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_wr_order_demo_test: complete");
    endtask : run_phase

endclass : axi4_wr_order_demo_test

`endif // AXI4_WR_ORDER_DEMO_TEST_INCLUDED_