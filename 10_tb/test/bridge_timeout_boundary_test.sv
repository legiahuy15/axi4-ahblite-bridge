//=============================================================================
// File        : bridge_timeout_boundary_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge data-phase timeout threshold boundary test.
//               Sweeps the AHB wait of a single transfer across a window
//               around C_DPHASE_TIMEOUT, read and write, and measures the
//               smallest wait the watchdog terminates. The three cases
//               BRG_TMO_003 names, one clock before the threshold, on it and
//               one clock after, are the measured value and its neighbours.
//               The test runs only on a build with a watchdog, so it belongs
//               to TIMEOUT_TEST_LIST and not to TEST_LIST; on the default
//               build the sequence stops with a message saying which TIMEOUT
//               to use.
//               The thresholds are required, not just reported: read must be
//               C_DPHASE_TIMEOUT+2 and write C_DPHASE_TIMEOUT+1. Read and
//               write have their own offset because they share the counter
//               but not the pipeline that feeds it, and both offsets come
//               from that pipeline rather than from the value, so they hold
//               on every build. EXPECT_OFFSET_RD/WR change what is required
//               and +MEASURE_ONLY reports the measurement instead, for
//               re-characterising a changed design.
//               Covers BRG_TMO_003.
//               Included inside the bridge test package.
//=============================================================================

class bridge_timeout_boundary_test extends bridge_base_test;

    `uvm_component_utils(bridge_timeout_boundary_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;
    // Measured on every supported build in regression 14 and identical on all
    // of them, as a pipeline offset must be. Read costs one cycle more than
    // write because the beat travels back through the read path before the
    // watchdog sees it complete.
    bit                       has_expected_offset = 1'b1;
    int                       expected_offset_rd  = 2;
    int                       expected_offset_wr  = 1;

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
        // The wait of the swept beat comes from the plan in the sequence, and
        // the slave answers OKAY throughout, so SLVERR can only be the watchdog
        env_cfg.ahb_cfg.auto_gen_resp      = 1'b0;
        env_cfg.ahb_cfg.clear_mem_on_reset = 1'b1;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
        // Both must be given together, since read and write have their own
        // boundary; either one alone is a mistake rather than a partial check
        void'($value$plusargs("EXPECT_OFFSET_RD=%d", expected_offset_rd));
        void'($value$plusargs("EXPECT_OFFSET_WR=%d", expected_offset_wr));
        // For re-characterising the watchdog on a changed design: report the
        // thresholds instead of requiring them
        if ($test$plusargs("MEASURE_ONLY"))
            has_expected_offset = 1'b0;
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Start of simulation
    //-------------------------------------------------------------------------
    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        `uvm_info(get_type_name(),
                  $sformatf("Elaborated C_DPHASE_TIMEOUT = %0d",
                            env_cfg.dphase_timeout), UVM_LOW)
    endfunction : start_of_simulation_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_timeout_boundary_seq seq;

        phase.raise_objection(this, "Bridge timeout boundary test started");

        seq = bridge_timeout_boundary_seq::type_id::create("seq");
        seq.base_addr           = base_addr;
        seq.case_stride         = case_stride;
        seq.has_expected_offset = has_expected_offset;
        seq.expected_offset_rd  = expected_offset_rd;
        seq.expected_offset_wr  = expected_offset_wr;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge timeout boundary test completed");
    endtask : run_phase

endclass : bridge_timeout_boundary_test