//=============================================================================
// File        : bridge_single_wstrb_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge single-write (AWLEN=0) WSTRB decoding test.
//               Exhaustively applies every WSTRB value with full-width AWSIZE
//               and every legal narrow pattern with a matching AWSIZE, and
//               checks the resulting HSIZE/HADDR and the written byte lanes.
//               Legal narrow patterns run only on a DUT built with
//               C_S_AXI_SUPPORTS_NARROW_BURST=1. Zero, sparse and misdirected
//               strobes are unsupported (negative) cases; ENABLE_NEGATIVE=0
//               removes them.
//               Covers BRG_SIZ_004 and BRG_SIZ_006.
//               Included inside the bridge test package.
//=============================================================================

class bridge_single_wstrb_test extends bridge_base_test;

    `uvm_component_utils(bridge_single_wstrb_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr       = 'h1000;
    int unsigned              case_stride     = 'h10;
    bit                       enable_narrow;  // follows DUT narrow support
    bit                       enable_negative = 1'b1;

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
        env_cfg.ahb_cfg.auto_gen_resp    = 1'b1;
        env_cfg.ahb_cfg.ready_delay_min  = 0;
        env_cfg.ahb_cfg.ready_delay_max  = 0;
        env_cfg.ahb_cfg.clear_mem_on_reset = 1'b1;

        enable_narrow = env_cfg.supports_narrow_burst;
        void'($value$plusargs("BASE_ADDR=%h",       base_addr));
        void'($value$plusargs("CASE_STRIDE=%d",     case_stride));
        void'($value$plusargs("ENABLE_NARROW=%d",   enable_narrow));
        void'($value$plusargs("ENABLE_NEGATIVE=%d", enable_negative));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_single_wstrb_seq seq;

        phase.raise_objection(this, "Bridge single-WSTRB test started");

        seq = bridge_single_wstrb_seq::type_id::create("seq");
        seq.base_addr       = base_addr;
        seq.case_stride     = case_stride;
        seq.enable_narrow   = enable_narrow;
        seq.enable_negative = enable_negative;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge single-WSTRB test completed");
    endtask : run_phase

endclass : bridge_single_wstrb_test