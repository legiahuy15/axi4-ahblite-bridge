//=============================================================================
// File        : ahb_slv_agent_cfg.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite slave agent configuration.
//               Included inside the bridge package.
//=============================================================================

typedef virtual ahb_if #(
    AHB_ADDR_WIDTH,
    AHB_DATA_WIDTH
) ahb_vif_t;

class ahb_slv_agent_cfg extends uvm_object;

    //-------------------------------------------------------------------------
    // Configuration fields
    //-------------------------------------------------------------------------

    // Agent controls
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit has_coverage                 = 1'b1;

    // Response source
    bit auto_gen_resp = 1'b1;

    // Auto-response timing
    int unsigned ready_delay_min = 0;
    int unsigned ready_delay_max = 0;

    // Memory controls
    bit [AHB_DATA_WIDTH-1:0] default_read_data = '0;
    bit                      clear_mem_on_reset = 1'b0;

    // Interface handle
    ahb_vif_t vif;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(ahb_slv_agent_cfg)
        `uvm_field_enum(uvm_active_passive_enum, is_active,          UVM_DEFAULT)
        `uvm_field_int(                         has_coverage,        UVM_DEFAULT)
        `uvm_field_int(                         auto_gen_resp,       UVM_DEFAULT)
        `uvm_field_int(                         ready_delay_min,     UVM_DEFAULT)
        `uvm_field_int(                         ready_delay_max,     UVM_DEFAULT)
        `uvm_field_int(                         default_read_data,   UVM_DEFAULT)
        `uvm_field_int(                         clear_mem_on_reset,  UVM_DEFAULT)
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_slv_agent_cfg");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Configuration validation
    //-------------------------------------------------------------------------
    function bit is_valid();
        if (vif == null) begin
            `uvm_error(get_type_name(), "AHB-Lite virtual interface is null")
            return 1'b0;
        end
        if (ready_delay_min > ready_delay_max) begin
            `uvm_error(get_type_name(), "ready_delay_min exceeds ready_delay_max")
            return 1'b0;
        end
        return 1'b1;
    endfunction : is_valid

endclass : ahb_slv_agent_cfg