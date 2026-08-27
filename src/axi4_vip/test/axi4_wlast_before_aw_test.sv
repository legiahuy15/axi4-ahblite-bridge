//==============================================================================
// File        : axi4_wlast_before_aw_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test for the "W before AW, burst in progress" (Case B) scenario.
//               Runs axi4_wlast_before_aw_seq. On legal traffic the SVA check
//               WLAST_MISSING_W_BEFORE_AW must NOT fire, so a clean run
//               (0 UVM_ERROR / 0 SVA error) confirms the fix does not report
//               false positives while the new path is exercised.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_WLAST_BEFORE_AW_TEST_INCLUDED_
`define AXI4_WLAST_BEFORE_AW_TEST_INCLUDED_

class axi4_wlast_before_aw_test extends axi4_base_test;

    `uvm_component_utils(axi4_wlast_before_aw_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_wlast_before_aw_seq seq;
        phase.raise_objection(this, "axi4_wlast_before_aw_test: starting");

        `uvm_info(get_type_name(),
                  "Starting W-before-AW partial-overlap test (Case B)", UVM_LOW)

        seq = axi4_wlast_before_aw_seq::type_id::create("seq");
        seq.start(env.master_agent.sqr);

        // Drain time
        repeat (50) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  "W-before-AW partial-overlap test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_wlast_before_aw_test: complete");
    endtask : run_phase

endclass : axi4_wlast_before_aw_test

`endif // AXI4_WLAST_BEFORE_AW_TEST_INCLUDED_
