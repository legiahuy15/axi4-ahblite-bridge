//==============================================================================
// File        : axi4_exclusive_fail_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test for exclusive-reservation invalidation corner cases.
//               Runs axi4_exclusive_fail_seq, which drives legal exclusive
//               accesses interleaved with stores and checks that the slave
//               returns EXOKAY / OKAY exactly as the AXI4 spec requires. Any
//               wrong response is a UVM_ERROR (raised inside the sequence).
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_EXCLUSIVE_FAIL_TEST_INCLUDED_
`define AXI4_EXCLUSIVE_FAIL_TEST_INCLUDED_

class axi4_exclusive_fail_test extends axi4_base_test;

    `uvm_component_utils(axi4_exclusive_fail_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_exclusive_fail_seq seq;
        phase.raise_objection(this, "axi4_exclusive_fail_test: starting");

        `uvm_info(get_type_name(), "Starting exclusive reservation corner-case test", UVM_LOW)

        seq = axi4_exclusive_fail_seq::type_id::create("excl_fail_seq");
        seq.start(env.master_agent.sqr);

        // Drain time for the last response to settle
        repeat (100) @(posedge env_cfg.master_vif.clk);

        if (seq.errors == 0)
            `uvm_info(get_type_name(),
                      "PASS: all exclusive reservation corner cases behaved per AXI4 spec", UVM_LOW)
        else
            `uvm_error(get_type_name(),
                       $sformatf("%0d exclusive responses did not match the AXI4-required value",
                                 seq.errors))

        `uvm_info(get_type_name(), "Exclusive reservation corner-case test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_exclusive_fail_test: complete");
    endtask : run_phase

endclass : axi4_exclusive_fail_test

`endif // AXI4_EXCLUSIVE_FAIL_TEST_INCLUDED_