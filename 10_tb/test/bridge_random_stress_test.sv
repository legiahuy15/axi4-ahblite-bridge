//=============================================================================
// File        : bridge_random_stress_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge constrained-random regression.
//               The one test in the regression whose traffic is not a case
//               list. Direction, burst, length, address, ID, cache and
//               protection are left to the constraint set of
//               axi4_transaction, and the AHB answer for each beat is drawn
//               on its own without looking at the request it answers, so a
//               seed changes the whole run rather than only the AXI IDs and
//               the FIXED lengths.
//               Both oracles are active and independent: the sequence knows
//               the plan it drew, so it checks every read word and every
//               per-beat response against it, while the scoreboard rebuilds
//               the AXI completion from the AHB beats it observed. The run
//               also has to be varied to pass: it fails if a direction, a
//               burst type, an injected error, a wait state or a SLVERR
//               never appeared.
//               It runs on three build axes: the default build, the narrow
//               build and all five C_DPHASE_TIMEOUT builds.
//               On the narrow build the size is drawn per request instead of
//               being fixed at the bus width, so the burst carries narrow
//               beats. That is the point of adding it there: the only narrow
//               traffic the regression had was the single writes of
//               bridge_parameter_test, and a single write never increments an
//               address, so gen_32_data_width_narrow in ahb_mstr_if, which
//               holds the whole per-size increment and wrap path for narrow
//               bursts, had never been driven.
//               On a watchdog build the policy cannot simply draw waits at
//               random, because a wait that tripped the watchdog would not
//               have been declared and the scoreboard would rightly call it
//               a fault. Ordinary requests are therefore capped two cycles
//               below C_DPHASE_TIMEOUT, and every eighth request after the
//               seeded head is turned into a deliberate timeout instead: all
//               its beats are answered OKAY so SLVERR can only mean the
//               watchdog, one beat is held well past the threshold, and the
//               request is declared with expect_timeout so the watchdog is
//               required to fire rather than merely allowed to.
//               Covers BRG_ENV_008, and drives both supported responses on
//               both channels for BRG_UNS_003.
//               Included inside the bridge test package.
//=============================================================================

class bridge_random_stress_test extends bridge_base_test;

    `uvm_component_utils(bridge_random_stress_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h4000;
    int unsigned              window_bytes  = 'h4000;
    int unsigned              num_requests  = 64;
    int unsigned              error_percent = 12;
    int unsigned              max_wait      = 4;

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
        // Independent backpressure on the AXI response channels as well,
        // randomized per beat by the driver
        env_cfg.axi_cfg.bready_delay_min = 0;
        env_cfg.axi_cfg.bready_delay_max = 2;
        env_cfg.axi_cfg.rready_delay_min = 0;
        env_cfg.axi_cfg.rready_delay_max = 2;
        // Every AHB beat is answered from the plan the sequence drew
        env_cfg.ahb_cfg.auto_gen_resp = 1'b0;

        void'($value$plusargs("BASE_ADDR=%h",     base_addr));
        void'($value$plusargs("WINDOW_BYTES=%d",  window_bytes));
        void'($value$plusargs("NUM_REQUESTS=%d",  num_requests));
        void'($value$plusargs("ERROR_PERCENT=%d", error_percent));
        void'($value$plusargs("MAX_WAIT=%d",      max_wait));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Start of simulation
    //-------------------------------------------------------------------------
    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        `uvm_info(get_type_name(),
                  $sformatf({"Built configuration: data=%0d narrow=%0b ",
                             "C_DPHASE_TIMEOUT=%0d"},
                            AXI4_DATA_WIDTH, env_cfg.supports_narrow_burst,
                            env_cfg.dphase_timeout), UVM_LOW)
    endfunction : start_of_simulation_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_random_stress_seq seq;

        phase.raise_objection(this, "Bridge random stress test started");

        seq = bridge_random_stress_seq::type_id::create("seq");
        seq.base_addr     = base_addr;
        seq.window_bytes  = window_bytes;
        seq.num_requests  = num_requests;
        seq.error_percent = error_percent;
        seq.max_wait      = max_wait;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge random stress test completed");
    endtask : run_phase

endclass : bridge_random_stress_test