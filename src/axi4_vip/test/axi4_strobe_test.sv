//==============================================================================
// File        : axi4_strobe_test.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : Test for AXI4 write strobe patterns (full, sparse, partial).
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_STROBE_TEST_INCLUDED_
`define AXI4_STROBE_TEST_INCLUDED_

class axi4_strobe_test extends axi4_base_test;

    `uvm_component_utils(axi4_strobe_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_strobe_pattern_seq strb_seq;
        phase.raise_objection(this, "axi4_strobe_test: starting");

        `uvm_info(get_type_name(), "Starting write strobe patterns test", UVM_LOW)

        strb_seq = axi4_strobe_pattern_seq::type_id::create("strb_seq");
        // Pin address and ID so every pattern writes to the SAME location:
        // on the waveform AWADDR/AWID stay constant while WSTRB steps through
        // 1111 -> 0000 -> walking-ones -> half-words. Deterministic and
        // reproducible for report screenshots. Strobe-pattern coverage is
        // unaffected (all patterns are still exercised).
        strb_seq.addr_lo = 32'h0000_9000;
        strb_seq.addr_hi = 32'h0000_9000;
        strb_seq.id_lo   = 4'h9;
        strb_seq.id_hi   = 4'h9;
        strb_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Write strobe patterns test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_strobe_test: complete");
    endtask : run_phase

endclass : axi4_strobe_test

`endif // AXI4_STROBE_TEST_INCLUDED_