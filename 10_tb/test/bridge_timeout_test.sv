//=============================================================================
// File        : bridge_timeout_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge timeout test on every C_DPHASE_TIMEOUT build:
//               - 0: a long AHB wait still completes with OKAY
//               - non-zero: a wait below the threshold completes, above it
//                 returns SLVERR (single and INCR4, read and write)
//               Covers BRG_TMO_001 and BRG_TMO_002.
//               Included inside the bridge test package.
//=============================================================================

class bridge_timeout_test extends bridge_base_test;

    `uvm_component_utils(bridge_timeout_test)

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
        // The wait of every beat comes from the plan in bridge_timeout_seq
        env_cfg.ahb_cfg.auto_gen_resp      = 1'b0;
        env_cfg.ahb_cfg.clear_mem_on_reset = 1'b1;

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
        bridge_timeout_seq seq;

        phase.raise_objection(this, "Bridge timeout test started");

        seq = bridge_timeout_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge timeout test completed");
    endtask : run_phase

endclass : bridge_timeout_test