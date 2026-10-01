//=============================================================================
// File        : bridge_illegal_narrow_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge unsupported-write test.
//               Two things AXI4 allows that this bridge cannot honour, and
//               that no other test showed on memory. Both are negative
//               cases: they match the reference design and the spec review,
//               and they are written down so they are not mistaken for
//               coverage holes.
//               WSTRB inside a burst is ignored. The bridge reads the
//               strobes only when AWLEN is zero; for a burst it takes HSIZE
//               from AWSIZE, and since AHB-Lite has no byte strobes every
//               beat writes a whole word. The lanes the master masked off
//               are overwritten. WSTRB of zero is the clearest case:
//               ordinary AXI asking for nothing to be written, and the word
//               changes anyway.
//               An unaligned write loses its offset. The bridge aligns each
//               beat address down to the transfer size, so the data lands in
//               the word below the one the master addressed.
//               Every case seeds its slot, sends the unsupported write, and
//               reads the whole slot back at full width to compare against a
//               model of what this bridge really does rather than of what
//               AXI asked for. The run fails if no masked lane was ever
//               overwritten or no offset was ever lost, so the findings
//               cannot be reported on the strength of the stimulus alone.
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
