//=============================================================================
// File        : bridge_random_stress_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge constrained-random test: random requests and
//               independent random AHB waits/errors. Runs on the default,
//               narrow (random size) and timeout builds (every eighth
//               request is a declared timeout).
//               Covers BRG_ENV_008 and BRG_UNS_003.
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