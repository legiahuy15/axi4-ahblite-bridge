//=============================================================================
// File        : bridge_burst_matrix_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge burst-matrix sweep test.
//               Exercises FIXED, INCR and WRAP conversion-sensitive
//               lengths for read and write through the bridge.
//               Covers BRG_BST_001 to BRG_BST_011.
//               Included inside the bridge test package.
//=============================================================================

class bridge_burst_matrix_test extends bridge_base_test;

    `uvm_component_utils(bridge_burst_matrix_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr    = 'h1000;
    int unsigned              case_stride  = 'h200;
    bit                       enable_write = 1'b1;
    bit                       enable_read  = 1'b1;

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

        void'($value$plusargs("BASE_ADDR=%h",    base_addr));
        void'($value$plusargs("CASE_STRIDE=%d",  case_stride));
        void'($value$plusargs("ENABLE_WRITE=%d", enable_write));
        void'($value$plusargs("ENABLE_READ=%d",  enable_read));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_burst_matrix_seq seq;

        phase.raise_objection(this, "Bridge burst-matrix test started");

        seq = bridge_burst_matrix_seq::type_id::create("seq");
        seq.base_addr    = base_addr;
        seq.case_stride  = case_stride;
        seq.enable_write = enable_write;
        seq.enable_read  = enable_read;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge burst-matrix test completed");
    endtask : run_phase

endclass : bridge_burst_matrix_test