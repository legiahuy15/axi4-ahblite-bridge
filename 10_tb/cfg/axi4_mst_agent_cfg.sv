//=============================================================================
// File        : axi4_mst_agent_cfg.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 master agent configuration.
//               Included inside the bridge package.
//=============================================================================

typedef virtual axi4_if #(
    AXI4_ADDR_WIDTH,
    AXI4_DATA_WIDTH,
    AXI4_ID_WIDTH
) axi4_vif_t;

class axi4_mst_agent_cfg extends uvm_object;

    //-------------------------------------------------------------------------
    // Configuration fields
    //-------------------------------------------------------------------------

    // Agent controls
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    bit has_coverage                  = 1'b1;
    bit return_responses              = 1'b0;

    // Master response backpressure
    int unsigned bready_delay_min = 0;
    int unsigned bready_delay_max = 0;
    int unsigned rready_delay_min = 0;
    int unsigned rready_delay_max = 0;

    // Request scheduling
    int unsigned max_outstanding   = 0;
    int unsigned w_before_aw_delay = 1;

    // Write-data starvation: cycles WVALID is held low between the beats of
    // a burst, drawn per gap. 0/0 sends the beats back to back, which is
    // what every test did before this knob existed. A transaction can ask
    // for one gap at a chosen beat instead, which is what the directed
    // starvation test uses; that takes precedence over this range.
    int unsigned wvalid_gap_min = 0;
    int unsigned wvalid_gap_max = 0;

    // Interface handle
    axi4_vif_t vif;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(axi4_mst_agent_cfg)
        `uvm_field_enum(uvm_active_passive_enum, is_active,         UVM_DEFAULT)
        `uvm_field_int(                          has_coverage,      UVM_DEFAULT)
        `uvm_field_int(                          return_responses,  UVM_DEFAULT)
        `uvm_field_int(                          bready_delay_min,  UVM_DEFAULT)
        `uvm_field_int(                          bready_delay_max,  UVM_DEFAULT)
        `uvm_field_int(                          rready_delay_min,  UVM_DEFAULT)
        `uvm_field_int(                          rready_delay_max,  UVM_DEFAULT)
        `uvm_field_int(                          max_outstanding,   UVM_DEFAULT)
        `uvm_field_int(                          w_before_aw_delay, UVM_DEFAULT)
        `uvm_field_int(                          wvalid_gap_min,    UVM_DEFAULT)
        `uvm_field_int(                          wvalid_gap_max,    UVM_DEFAULT)
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_agent_cfg");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Configuration validation
    //-------------------------------------------------------------------------
    function bit is_valid();
        if (vif == null) begin
            `uvm_error(get_type_name(), "AXI4 virtual interface is null")
            return 1'b0;
        end
        if (bready_delay_min > bready_delay_max) begin
            `uvm_error(get_type_name(), "bready_delay_min exceeds bready_delay_max")
            return 1'b0;
        end
        if (rready_delay_min > rready_delay_max) begin
            `uvm_error(get_type_name(), "rready_delay_min exceeds rready_delay_max")
            return 1'b0;
        end
        if (wvalid_gap_min > wvalid_gap_max) begin
            `uvm_error(get_type_name(), "wvalid_gap_min exceeds wvalid_gap_max")
            return 1'b0;
        end
        return 1'b1;
    endfunction : is_valid

endclass : axi4_mst_agent_cfg