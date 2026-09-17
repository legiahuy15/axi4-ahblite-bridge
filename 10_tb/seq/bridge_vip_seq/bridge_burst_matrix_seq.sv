//=============================================================================
// File        : bridge_burst_matrix_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the bridge burst-matrix sweep scenario.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_burst_matrix_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_burst_matrix_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr    = 'h1000;
    int unsigned              case_stride  = 256 * AXI4_STRB_WIDTH;
    bit                       enable_write = 1'b1;
    bit                       enable_read  = 1'b1;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_burst_matrix_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_burst_matrix_seq axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "Burst-matrix sequence requires automatic AHB responses")

        axi_seq = axi4_mst_burst_matrix_seq::type_id::create("axi_seq");
        axi_seq.base_addr    = base_addr;
        axi_seq.case_stride  = case_stride;
        axi_seq.enable_write = enable_write;
        axi_seq.enable_read  = enable_read;
        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_burst_matrix_seq