//==============================================================================
// File        : axi4_addr_integrity_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Known-answer address/data integrity test.
//               Runs axi4_addr_data_integrity_seq, which seeds memory with an
//               address-encoded pattern and reads it back with WRAP / unaligned
//               / narrow / FIXED bursts, checking each beat against an
//               INDEPENDENTLY-computed reference. Catches burst-address and
//               byte-lane math bugs that the scoreboard's duplicated logic
//               cannot. Any mismatch is a UVM_ERROR (raised in the sequence).
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_ADDR_INTEGRITY_TEST_INCLUDED_
`define AXI4_ADDR_INTEGRITY_TEST_INCLUDED_

class axi4_addr_integrity_test extends axi4_base_test;

    `uvm_component_utils(axi4_addr_integrity_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_addr_data_integrity_seq seq;
        phase.raise_objection(this, "axi4_addr_integrity_test: starting");

        `uvm_info(get_type_name(), "Starting known-answer address/data integrity test", UVM_LOW)

        seq = axi4_addr_data_integrity_seq::type_id::create("addr_int_seq");
        seq.start(env.master_agent.sqr);

        repeat (50) @(posedge env_cfg.master_vif.clk);

        if (seq.errors == 0)
            `uvm_info(get_type_name(),
                      "PASS: WRAP/unaligned/narrow/FIXED read-back matched the independent reference",
                      UVM_LOW)
        else
            `uvm_error(get_type_name(),
                       $sformatf("%0d beat(s) mismatched the independent address/data reference",
                                 seq.errors))

        `uvm_info(get_type_name(), "Address/data integrity test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_addr_integrity_test: complete");
    endtask : run_phase

endclass : axi4_addr_integrity_test

`endif // AXI4_ADDR_INTEGRITY_TEST_INCLUDED_