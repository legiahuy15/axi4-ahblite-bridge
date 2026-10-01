//=============================================================================
// File        : bridge_parameter_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge configuration compliance test on the 32/64-bit,
//               narrow off/on builds: full-width bursts plus narrow writes,
//               read back at full width.
//               Covers BRG_CFG_001 and BRG_CFG_002.
//               Included inside the bridge test package.
//=============================================================================

class bridge_parameter_test extends bridge_base_test;

    `uvm_component_utils(bridge_parameter_test)

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
        // Reads come from the slave memory model, so a narrow write is
        // visible in the word that is read back afterwards
        env_cfg.ahb_cfg.auto_gen_resp     = 1'b1;
        env_cfg.ahb_cfg.ready_delay_min   = 0;
        env_cfg.ahb_cfg.ready_delay_max   = 0;
        env_cfg.ahb_cfg.addr_pattern_read = 1'b1;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Start of simulation
    //-------------------------------------------------------------------------
    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        `uvm_info(get_type_name(),
                  $sformatf({"Built configuration: AXI data=%0d addr=%0d ",
                             "id=%0d, AHB data=%0d addr=%0d, narrow=%0b, ",
                             "C_DPHASE_TIMEOUT=%0d"},
                            AXI4_DATA_WIDTH, AXI4_ADDR_WIDTH, AXI4_ID_WIDTH,
                            AHB_DATA_WIDTH, AHB_ADDR_WIDTH,
                            env_cfg.supports_narrow_burst,
                            env_cfg.dphase_timeout), UVM_LOW)
    endfunction : start_of_simulation_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_parameter_seq seq;

        phase.raise_objection(this, "Bridge parameter test started");

        seq = bridge_parameter_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge parameter test completed");
    endtask : run_phase

endclass : bridge_parameter_test
