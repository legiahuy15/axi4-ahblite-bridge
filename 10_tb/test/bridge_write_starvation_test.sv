//=============================================================================
// File        : bridge_write_starvation_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge write-data starvation test.
//               Written to close a gap the code coverage review of
//               regression 24 found: no test had ever dropped WVALID in the
//               middle of a write burst, because the AXI master driver
//               streamed the beats of a burst back to back and the agent had
//               no knob for a gap. That single hole left four states of the
//               AHB write FSM unreached, AHB_WR_WAIT, AHB_LAST_WAIT,
//               AHB_LAST and AHB_ONEKB_LAST, which is 24 of the 26
//               unexecuted statements in ahb_mstr_if, and AXI_WVALID_WAIT
//               unreached in axi_slv_if.
//               Each of those states needs a different shape of gap, so the
//               cases are directed: a gap in the middle of a plain INCR, a
//               gap before its last beat, the same on a FIXED burst and a
//               WRAP2, and both again on a burst already split at a 1 KB
//               boundary. What the bridge does in reply is counted rather
//               than assumed: the run fails unless it issued AHB BUSY
//               transfers and drove IDLE inside a burst.
//               The AHB slave answers from its memory model with no wait
//               states, so nothing but the gap holds the bridge up, and
//               every burst is read back and compared beat by beat: a gap
//               must change the timing of a write and nothing else.
//               Covers BRG_ENV_005.
//               Included inside the bridge test package.
//=============================================================================

class bridge_write_starvation_test extends bridge_base_test;

    `uvm_component_utils(bridge_write_starvation_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h8000;
    int unsigned              case_stride = 'h40;

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
        env_cfg.axi_cfg.max_outstanding  = 1;
        // The gap is placed per transaction, not drawn from the agent range
        env_cfg.axi_cfg.wvalid_gap_min = 0;
        env_cfg.axi_cfg.wvalid_gap_max = 0;
        // Read back what each starved write left behind, with the AHB side
        // never the thing that stalls
        env_cfg.ahb_cfg.auto_gen_resp     = 1'b1;
        env_cfg.ahb_cfg.addr_pattern_read = 1'b1;
        env_cfg.ahb_cfg.ready_delay_min   = 0;
        env_cfg.ahb_cfg.ready_delay_max   = 0;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_write_starvation_seq seq;

        phase.raise_objection(this, "Bridge write starvation test started");

        seq = bridge_write_starvation_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge write starvation test completed");
    endtask : run_phase

endclass : bridge_write_starvation_test