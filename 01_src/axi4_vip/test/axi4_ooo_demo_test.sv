//==============================================================================
// File        : axi4_ooo_demo_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Out-of-order demo test for waveform capture.
//               Issues exactly 6 concurrent reads with distinct IDs (0..5)
//               into a reorder-enabled slave, with enough outstanding depth
//               that all six are in flight together. The R channel returns
//               responses out-of-order (RID order != ARID order), while each
//               burst stays non-interleaved (RID constant until RLAST).
//               Minimal, deterministic traffic - ideal for report/slide
//               waveform illustration of ID-based out-of-order return.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_OOO_DEMO_TEST_INCLUDED_
`define AXI4_OOO_DEMO_TEST_INCLUDED_

class axi4_ooo_demo_test extends axi4_base_test;

    `uvm_component_utils(axi4_ooo_demo_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // Small, fixed knobs for a clean waveform
    int unsigned depth = 6;   // all 6 reads outstanding together

    // =========================================================================
    // Build phase - enable slave read reordering BEFORE env/agent/drv build
    // =========================================================================
    function void build_phase(uvm_phase phase);
        uvm_config_db#(bit)::set(this, "env.slave_agent.drv",
                                 "r_reorder_enable", 1'b1);
        uvm_config_db#(int unsigned)::set(this, "env.slave_agent.drv",
                                          "r_outstanding_max", depth);
        super.build_phase(phase);
    endfunction : build_phase

    // =========================================================================
    // Run phase - 6 single-beat reads, IDs 0..5, no writes
    // =========================================================================
    task run_phase(uvm_phase phase);
        axi4_ooo_demo_seq ooo_seq;
        phase.raise_objection(this, "axi4_ooo_demo_test: starting");

        `uvm_info(get_type_name(),
                  "Starting OOO demo test (6 single-beat reads, IDs 0..5)",
                  UVM_LOW)

        ooo_seq = axi4_ooo_demo_seq::type_id::create("ooo_seq");
        ooo_seq.start(env.master_agent.sqr);

        // Drain time - wait for all outstanding reads to complete
        repeat (60) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "OOO demo test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_ooo_demo_test: complete");
    endtask : run_phase

endclass : axi4_ooo_demo_test

`endif // AXI4_OOO_DEMO_TEST_INCLUDED_
