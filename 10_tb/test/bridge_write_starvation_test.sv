//=============================================================================
// File        : bridge_write_starvation_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge write-data starvation test. WVALID gaps mid-burst
//               and before the last beat (INCR, FIXED, WRAP2, 1 KB split);
//               data is read back and compared.
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