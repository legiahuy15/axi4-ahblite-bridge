//=============================================================================
// File        : bridge_data_integrity_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates bridge data-integrity traffic.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_data_integrity_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_data_integrity_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    int unsigned              num_iter       = 5;
    int unsigned              narrow_cases  = 8;
    bit                       enable_narrow = 1'b0;
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h1000;
    bit [AXI4_ADDR_WIDTH-1:0] narrow_base   = 'h8000;
    int unsigned              case_stride   = 'h100;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_data_integrity_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_data_integrity_seq axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "Data-integrity sequence requires automatic AHB responses")
        // Without narrow support the DUT aligns HADDR to the full bus width,
        // so narrow cases at non-zero byte lanes cannot pass
        if (enable_narrow && !cfg.supports_narrow_burst)
            `uvm_fatal(get_type_name(),
                       {"Narrow cases require a DUT built with ",
                        "C_S_AXI_SUPPORTS_NARROW_BURST=1"})

        axi_seq = axi4_mst_data_integrity_seq::type_id::create("axi_seq");
        axi_seq.num_iter       = num_iter;
        axi_seq.narrow_cases   = narrow_cases;
        axi_seq.enable_narrow  = enable_narrow;
        axi_seq.base_addr      = base_addr;
        axi_seq.narrow_base    = narrow_base;
        axi_seq.case_stride    = case_stride;
        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_data_integrity_seq