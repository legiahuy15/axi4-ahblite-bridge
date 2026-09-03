//==============================================================================
// File        : axi4_reset_mid_burst_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Mid-burst reset recovery test.
//               Drives continuous multi-beat traffic, asserts rst_n WHILE
//               bursts are in flight, then verifies the master/slave drivers
//               recover cleanly:
//                 - the simulation does not hang (watchdog would otherwise fire),
//                 - a fresh write->read-back after reset returns correct data.
//
//               The scoreboard is disabled for this test because a mid-burst
//               reset intentionally abandons partial transactions (which would
//               otherwise appear as harmless "unmatched" warnings). Recovery is
//               proven functionally by the self-checking data-integrity
//               sequence, whose own compare raises UVM_ERROR on any mismatch.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_RESET_MID_BURST_TEST_INCLUDED_
`define AXI4_RESET_MID_BURST_TEST_INCLUDED_

class axi4_reset_mid_burst_test extends axi4_base_test;

    `uvm_component_utils(axi4_reset_mid_burst_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Mid-burst reset leaves partial transactions -> disable the scoreboard to
        // avoid unmatched-warning noise. Recovery is checked functionally below.
        env_cfg.has_scoreboard = 0;
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        uvm_event               reset_ev = uvm_event_pool::get_global("axi4_reset_req");
        axi4_reset_traffic_seq  traffic_seq;
        axi4_data_integrity_seq recover_seq;
        virtual axi4_if         vif = env_cfg.master_vif;

        phase.raise_objection(this, "reset_mid_burst: starting");
        `uvm_info(get_type_name(), "Starting mid-burst reset recovery test", UVM_LOW)

        // ---- Phase 1: launch background traffic so bursts are in flight ----
        traffic_seq = axi4_reset_traffic_seq::type_id::create("traffic_seq");
        fork : traffic_blk
            traffic_seq.start(env.master_agent.sqr);
        join_none

        repeat (40) @(posedge vif.clk);   // let several bursts get onto the bus

        // ---- Phase 2: assert reset mid-burst ----
        `uvm_info(get_type_name(), "Asserting mid-burst reset now", UVM_LOW)
        reset_ev.trigger();

        wait (vif.rst_n == 1'b0);
        `uvm_info(get_type_name(), "rst_n asserted (mid-burst)", UVM_MEDIUM)
        wait (vif.rst_n == 1'b1);
        `uvm_info(get_type_name(), "rst_n deasserted - verifying recovery", UVM_MEDIUM)

        // Kill any stuck pre-reset traffic and clear the sequencer state
        disable traffic_blk;
        env.master_agent.sqr.stop_sequences();

        repeat (10) @(posedge vif.clk);   // let drivers re-initialise

        // ---- Phase 3: recovery proof - self-checking write->read-back ----
        // If the driver failed to recover, this hangs (watchdog fires -> fail).
        // If read-back data is wrong, the sequence raises UVM_ERROR.
        recover_seq = axi4_data_integrity_seq::type_id::create("recover_seq");
        recover_seq.start(env.master_agent.sqr);

        repeat (50) @(posedge vif.clk);
        `uvm_info(get_type_name(),
                  "Recovery verified - driver processed clean transactions after mid-burst reset",
                  UVM_LOW)

        phase.drop_objection(this, "reset_mid_burst: complete");
    endtask : run_phase

endclass : axi4_reset_mid_burst_test

`endif // AXI4_RESET_MID_BURST_TEST_INCLUDED_