//=============================================================================
// File        : bridge_parameter_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the configuration compliance profile. The AHB
//               slave answers automatically from its memory model here, so no
//               reactive slave sequence is started; the response policy is
//               handed over only for its read-data pattern, which is the same
//               one the slave returns for an untouched word.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_parameter_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_parameter_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_parameter_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_response_policy     pattern;
        axi4_mst_parameter_seq  axi_seq;

        require_axi_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       {"The narrow read-back needs the slave memory model; ",
                        "auto_gen_resp must be set"})
        if (!cfg.ahb_cfg.addr_pattern_read)
            `uvm_fatal(get_type_name(),
                       {"The expected data of an untouched word is the ",
                        "address pattern; addr_pattern_read must be set"})
        if (!cfg.is_valid())
            `uvm_fatal(get_type_name(),
                       "The environment configuration is not valid")

        pattern = ahb_response_policy::type_id::create("pattern");

        axi_seq                 = axi4_mst_parameter_seq::type_id::create("axi_seq");
        axi_seq.pattern         = pattern;
        axi_seq.base_addr       = base_addr;
        axi_seq.case_stride     = case_stride;
        axi_seq.supports_narrow = cfg.supports_narrow_burst;

        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_parameter_seq
