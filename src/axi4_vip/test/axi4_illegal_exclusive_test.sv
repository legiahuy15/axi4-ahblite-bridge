//==============================================================================
// File        : axi4_illegal_exclusive_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Negative test for illegal exclusive accesses.
//               Drives exclusive transactions that violate the AXI4 exclusive
//               rules (A7.2) and checks that the slave flags EXACTLY one
//               protocol error per illegal transaction.
//
//               Because these errors are EXPECTED, a uvm_report_catcher demotes
//               the slave's "Illegal exclusive" UVM_ERRORs to UVM_INFO (and
//               counts them). The test then verifies the count matches the
//               number of illegal transactions sent - so the run passes only
//               when the checker behaved correctly. Any OTHER error (including
//               a missing/extra illegal-exclusive report) fails the test.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_ILLEGAL_EXCLUSIVE_TEST_INCLUDED_
`define AXI4_ILLEGAL_EXCLUSIVE_TEST_INCLUDED_

// =============================================================================
// Report catcher - demotes the slave's expected illegal-exclusive protocol
// errors to INFO so this negative test can pass, while counting them.
// =============================================================================
class axi4_illegal_excl_catcher extends uvm_report_catcher;

    int unsigned caught = 0;

    function new(string name = "axi4_illegal_excl_catcher");
        super.new(name);
    endfunction : new

    virtual function action_e catch();
        if (get_severity() == UVM_ERROR &&
            get_id()       == "axi4_slave_driver" &&
            str_contains(get_message(), "Illegal exclusive")) begin
            caught++;
            set_severity(UVM_INFO);   // expected -> demote so it does not fail the test
        end
        return THROW;                 // still report (now as INFO)
    endfunction : catch

    // Simple substring search (SV has no built-in contains()).
    function bit str_contains(string s, string sub);
        int ls = s.len();
        int lb = sub.len();
        if (lb == 0)  return 1'b1;
        if (lb > ls)  return 1'b0;
        for (int i = 0; i <= ls - lb; i++)
            if (s.substr(i, i + lb - 1) == sub) return 1'b1;
        return 1'b0;
    endfunction : str_contains

endclass : axi4_illegal_excl_catcher

// =============================================================================
// The test
// =============================================================================
class axi4_illegal_exclusive_test extends axi4_base_test;

    `uvm_component_utils(axi4_illegal_exclusive_test)

    axi4_illegal_excl_catcher catcher;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        catcher = new("illegal_excl_catcher");
        uvm_report_cb::add(null, catcher);   // install globally
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        axi4_illegal_exclusive_seq seq;
        phase.raise_objection(this, "axi4_illegal_exclusive_test: starting");

        `uvm_info(get_type_name(), "Starting illegal-exclusive negative test", UVM_LOW)

        seq = axi4_illegal_exclusive_seq::type_id::create("illegal_excl_seq");
        seq.start(env.master_agent.sqr);

        // Drain time for the last responses to settle
        repeat (100) @(posedge env_cfg.master_vif.clk);

        // Check: the slave must have flagged exactly one error per illegal txn
        if (catcher.caught != seq.num_illegal)
            `uvm_error(get_type_name(),
                       $sformatf("Slave flagged %0d illegal-exclusive errors, expected %0d",
                                 catcher.caught, seq.num_illegal))
        else
            `uvm_info(get_type_name(),
                      $sformatf("PASS: slave correctly flagged all %0d illegal exclusive accesses",
                                catcher.caught), UVM_LOW)

        `uvm_info(get_type_name(), "Illegal-exclusive negative test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_illegal_exclusive_test: complete");
    endtask : run_phase

endclass : axi4_illegal_exclusive_test

`endif // AXI4_ILLEGAL_EXCLUSIVE_TEST_INCLUDED_