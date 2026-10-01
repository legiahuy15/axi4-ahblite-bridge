//=============================================================================
// File        : bridge_illegal_narrow_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge unsupported-write test (negative cases): burst WSTRB
//               is ignored and unaligned write addresses are aligned. Memory
//               is read back and compared with a model of the bridge.
//               Covers BRG_SIZ_006.
//               Included inside the bridge test package.
//=============================================================================

class bridge_illegal_narrow_test extends bridge_base_test;

    `uvm_component_utils(bridge_illegal_narrow_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'hA000;
    int unsigned              case_stride = 'h80;

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
        // The verdict is what the write left in memory, so the slave has to
        // answer from its model
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
        bridge_illegal_narrow_seq seq;

        phase.raise_objection(this, "Bridge illegal narrow test started");

        seq = bridge_illegal_narrow_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge illegal narrow test completed");
    endtask : run_phase

endclass : bridge_illegal_narrow_test
