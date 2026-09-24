//=============================================================================
// File        : bridge_axi_backpressure_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge AXI response-channel backpressure test.
//               The master delays BREADY and RREADY by a known number of
//               cycles on every response, so a stalled B or R response has to
//               be held by the bridge. B_STABLE and R_STABLE check the held
//               payload, C_B_STALL and C_R_STALL cover the stall, and the
//               sequence checks the stall cycle by cycle and measures it, so a
//               window that never took effect fails the case.
//               The B and R windows are set independently and swept over 1, 2,
//               3, 8 and 16 cycles on every burst shape, with AHB wait states,
//               with SLVERR and across a 1 KB split.
//               Covers BRG_WAI_002 and BRG_WAI_003.
//               Included inside the bridge test package.
//=============================================================================

class bridge_axi_backpressure_test extends bridge_base_test;

    `uvm_component_utils(bridge_axi_backpressure_test)

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
        env_cfg.axi_cfg.max_outstanding  = 1;
        // The driver chooses the delayed-ready path once, when it starts
        // waiting for a response, so both windows must already be non-zero
        // here. The sequence then sets the window of every case.
        env_cfg.axi_cfg.bready_delay_min = 1;
        env_cfg.axi_cfg.bready_delay_max = 1;
        env_cfg.axi_cfg.rready_delay_min = 1;
        env_cfg.axi_cfg.rready_delay_max = 1;
        // Responses come from the plan in bridge_backpressure_seq
        env_cfg.ahb_cfg.auto_gen_resp      = 1'b0;
        env_cfg.ahb_cfg.clear_mem_on_reset = 1'b1;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_backpressure_seq seq;

        phase.raise_objection(this, "Bridge AXI backpressure test started");

        seq = bridge_backpressure_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge AXI backpressure test completed");
    endtask : run_phase

endclass : bridge_axi_backpressure_test