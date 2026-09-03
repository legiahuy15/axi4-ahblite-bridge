//=============================================================================
// File        : vip_env_cfg.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Top-level VIP environment configuration.
//               Included inside the bridge package.
//=============================================================================

class vip_env_cfg extends uvm_object;

    //-------------------------------------------------------------------------
    // Agent configurations
    //-------------------------------------------------------------------------
    axi4_mst_agent_cfg axi_cfg;
    ahb_slv_agent_cfg  ahb_cfg;

    //-------------------------------------------------------------------------
    // Environment controls
    //-------------------------------------------------------------------------
    bit has_scoreboard         = 1'b1;
    bit has_e2e_cov            = 1'b1;
    bit clear_queues_on_reset  = 1'b1;

    //-------------------------------------------------------------------------
    // DUT configuration
    //-------------------------------------------------------------------------
    bit          supports_narrow_burst = 1'b0;
    int unsigned dphase_timeout        = 0;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(vip_env_cfg)
        `uvm_field_object(axi_cfg, UVM_DEFAULT | UVM_REFERENCE)
        `uvm_field_object(ahb_cfg, UVM_DEFAULT | UVM_REFERENCE)
        `uvm_field_int(has_scoreboard,        UVM_DEFAULT)
        `uvm_field_int(has_e2e_cov,           UVM_DEFAULT)
        `uvm_field_int(clear_queues_on_reset, UVM_DEFAULT)
        `uvm_field_int(supports_narrow_burst, UVM_DEFAULT)
        `uvm_field_int(dphase_timeout,        UVM_DEFAULT)
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "vip_env_cfg");
        super.new(name);
        axi_cfg = axi4_mst_agent_cfg::type_id::create("axi_cfg");
        ahb_cfg = ahb_slv_agent_cfg::type_id::create("ahb_cfg");
    endfunction : new

    //-------------------------------------------------------------------------
    // Configuration validation
    //-------------------------------------------------------------------------
    function bit is_valid();
        bit valid;

        valid = 1'b1;
        if (axi_cfg == null) begin
            `uvm_error(get_type_name(), "AXI4 master agent config is null")
            valid = 1'b0;
        end else begin
            valid &= axi_cfg.is_valid();
        end

        if (ahb_cfg == null) begin
            `uvm_error(get_type_name(), "AHB-Lite slave agent config is null")
            valid = 1'b0;
        end else begin
            valid &= ahb_cfg.is_valid();
        end

        if (AXI4_ADDR_WIDTH != AHB_ADDR_WIDTH) begin
            `uvm_error(get_type_name(), "AXI4 and AHB-Lite address widths differ")
            valid = 1'b0;
        end
        if (AXI4_DATA_WIDTH != AHB_DATA_WIDTH) begin
            `uvm_error(get_type_name(), "AXI4 and AHB-Lite data widths differ")
            valid = 1'b0;
        end
        if (!(dphase_timeout inside {0, 16, 32, 64, 128, 256})) begin
            `uvm_error(get_type_name(),
                       $sformatf("Illegal dphase_timeout=%0d", dphase_timeout))
            valid = 1'b0;
        end
        return valid;
    endfunction : is_valid

endclass : vip_env_cfg