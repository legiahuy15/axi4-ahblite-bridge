//=============================================================================
// File        : bridge_sanity_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Basic bridge write-read-back test.
//               Included inside the bridge test package.
//=============================================================================

class bridge_sanity_test extends bridge_base_test;

    `uvm_component_utils(bridge_sanity_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    int unsigned              num_iter    = 4;
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              addr_stride = AXI4_STRB_WIDTH;

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
        env_cfg.ahb_cfg.auto_gen_resp    = 1'b1;
        env_cfg.ahb_cfg.ready_delay_min  = 0;
        env_cfg.ahb_cfg.ready_delay_max  = 0;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("BASE_ADDR=%h", base_addr));
        void'($value$plusargs("ADDR_STRIDE=%d", addr_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_sanity_seq seq;

        phase.raise_objection(this, "Bridge sanity test started");

        seq = bridge_sanity_seq::type_id::create("seq");
        seq.num_iter    = num_iter;
        seq.base_addr   = base_addr;
        seq.addr_stride = addr_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge sanity test completed");
    endtask : run_phase

endclass : bridge_sanity_test