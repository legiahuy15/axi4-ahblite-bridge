//=============================================================================
// File        : bridge_read_priority_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge simultaneous read/write arbitration test.
//               Presents a read and a write together and checks that the read
//               reaches AHB first and that the write then follows, over
//               repeated collisions and with the write channels in both
//               orders the bridge accepts.
//               This is the first test with two requests outstanding at once,
//               so max_outstanding is 2; every other test runs with one. The
//               scoreboard matches AHB beats to requests by first-beat
//               direction and address and AXI completions by direction and
//               ID, so it does not depend on the order the two were predicted
//               in, and the write and read of a pair sit in different halves
//               of their region to keep the addresses apart.
//               Covers BRG_ARB_001 and BRG_ARB_002.
//               Included inside the bridge test package.
//=============================================================================

class bridge_read_priority_test extends bridge_base_test;

    `uvm_component_utils(bridge_read_priority_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.axi_cfg.return_responses = 1'b1;
        // A read and a write must be asking at the same time, which is the
        // whole point of the test
        env_cfg.axi_cfg.max_outstanding  = 2;
        // The AHB wait of every beat comes from the plan in the sequence
        env_cfg.ahb_cfg.auto_gen_resp      = 1'b0;
        env_cfg.ahb_cfg.clear_mem_on_reset = 1'b1;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_read_priority_seq seq;

        phase.raise_objection(this, "Bridge read priority test started");

        seq = bridge_read_priority_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge read priority test completed");
    endtask : run_phase

endclass : bridge_read_priority_test