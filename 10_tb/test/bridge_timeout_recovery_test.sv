//=============================================================================
// File        : bridge_timeout_recovery_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge data-phase timeout termination and recovery test.
//               Checks the three things BRG_TMO_004 asks for: the watchdog
//               returns the AHB bus to IDLE, the AXI side gets SLVERR, and
//               the bridge recovers cleanly after a reset.
//               Termination is observed on the AHB interface, not inferred
//               from the response: the sequence counts the address phases the
//               bridge issues and watches HTRANS once the watchdog has fired,
//               so a burst that kept running after being abandoned is caught.
//               Recovery is driven through the bridge_reset_req event that
//               bridge_tb_top listens on, and the traffic that follows each
//               reset is compared by the scoreboard in full.
//               The test needs a build with a watchdog, so it belongs to
//               TIMEOUT_TEST_LIST and not to TEST_LIST; on the default build
//               the sequence stops with a message naming the TIMEOUT to use.
//               Covers BRG_TMO_004.
//               Included inside the bridge test package.
//=============================================================================

class bridge_timeout_recovery_test extends bridge_base_test;

    `uvm_component_utils(bridge_timeout_recovery_test)

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
        // The wait of every beat comes from the plan, and the slave answers
        // OKAY throughout, so SLVERR can only be the watchdog
        env_cfg.ahb_cfg.auto_gen_resp      = 1'b0;
        env_cfg.ahb_cfg.clear_mem_on_reset = 1'b1;
        // The test resets mid-run, so the predictor, scoreboard and coverage
        // must drop what belonged to the run before it
        env_cfg.clear_queues_on_reset      = 1'b1;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
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
        bridge_timeout_recovery_seq seq;

        phase.raise_objection(this, "Bridge timeout recovery test started");

        seq = bridge_timeout_recovery_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge timeout recovery test completed");
    endtask : run_phase

endclass : bridge_timeout_recovery_test