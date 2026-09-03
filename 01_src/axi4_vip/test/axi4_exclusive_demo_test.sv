//==============================================================================
// File        : axi4_exclusive_demo_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Exclusive access demo test for waveform capture.
//               Runs axi4_exclusive_demo_seq: three transactions to a fixed
//               address/ID, phased sequentially (each waits for full
//               completion), so they never overlap:
//                 1. Exclusive read   -> RRESP = EXOKAY
//                 2. Exclusive write  -> BRESP = EXOKAY (reservation held)
//                 3. Exclusive write  -> BRESP = OKAY   (no reservation)
//               Slave ready/response delays are stretched so each phase is
//               easy to read on the waveform.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_EXCLUSIVE_DEMO_TEST_INCLUDED_
`define AXI4_EXCLUSIVE_DEMO_TEST_INCLUDED_

class axi4_exclusive_demo_test extends axi4_base_test;

    `uvm_component_utils(axi4_exclusive_demo_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase - stretch slave timing so each phase is easy to read
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_cfg.slave_agent_cfg.ready_delay_min = 2;
        env_cfg.slave_agent_cfg.ready_delay_max = 3;
        env_cfg.slave_agent_cfg.resp_delay_min  = 2;
        env_cfg.slave_agent_cfg.resp_delay_max  = 3;
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        axi4_exclusive_demo_seq excl_seq;
        phase.raise_objection(this, "axi4_exclusive_demo_test: starting");

        `uvm_info(get_type_name(),
                  "Starting exclusive demo test (3 phased transactions, fixed addr/ID)",
                  UVM_LOW)

        excl_seq = axi4_exclusive_demo_seq::type_id::create("excl_seq");
        excl_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (60) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Exclusive demo test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_exclusive_demo_test: complete");
    endtask : run_phase

endclass : axi4_exclusive_demo_test

`endif // AXI4_EXCLUSIVE_DEMO_TEST_INCLUDED_
