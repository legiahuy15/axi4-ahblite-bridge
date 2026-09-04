//=============================================================================
// File        : bridge_base_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Base UVM test for bridge-level verification.
//               Included inside the bridge test package.
//=============================================================================

class bridge_base_test extends uvm_test;

    `uvm_component_utils(bridge_base_test)

    //-------------------------------------------------------------------------
    // Environment and configuration
    //-------------------------------------------------------------------------
    vip_env     env;
    vip_env_cfg env_cfg;

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

        env_cfg = vip_env_cfg::type_id::create("env_cfg");

        if (!uvm_config_db#(axi4_vif_t)::get(this, "", "axi_vif",
                                             env_cfg.axi_cfg.vif) &&
            !uvm_config_db#(axi4_vif_t)::get(this, "", "vif",
                                             env_cfg.axi_cfg.vif))
            `uvm_fatal(get_type_name(),
                       "AXI4 virtual interface 'axi_vif' not found")

        if (!uvm_config_db#(ahb_vif_t)::get(this, "", "ahb_vif",
                                            env_cfg.ahb_cfg.vif) &&
            !uvm_config_db#(ahb_vif_t)::get(this, "", "vif",
                                            env_cfg.ahb_cfg.vif))
            `uvm_fatal(get_type_name(),
                       "AHB-Lite virtual interface 'ahb_vif' not found")

        void'(uvm_config_db#(bit)::get(this, "", "supports_narrow_burst",
                                       env_cfg.supports_narrow_burst));
        void'(uvm_config_db#(int unsigned)::get(this, "", "dphase_timeout",
                                                env_cfg.dphase_timeout));

        uvm_config_db#(vip_env_cfg)::set(this, "env", "cfg", env_cfg);
        env = vip_env::type_id::create("env", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // End of elaboration phase
    //-------------------------------------------------------------------------
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction : end_of_elaboration_phase

    //-------------------------------------------------------------------------
    // Report phase
    //-------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        uvm_report_server server;
        int unsigned      error_count;

        super.report_phase(phase);
        server = uvm_report_server::get_server();
        error_count = server.get_severity_count(UVM_ERROR) +
                      server.get_severity_count(UVM_FATAL);

        if (error_count == 0)
            `uvm_info(get_type_name(), "=== TEST PASSED ===", UVM_NONE)
        else
            `uvm_info(get_type_name(),
                      $sformatf("=== TEST FAILED === (%0d errors)",
                                error_count), UVM_NONE)
    endfunction : report_phase

endclass : bridge_base_test