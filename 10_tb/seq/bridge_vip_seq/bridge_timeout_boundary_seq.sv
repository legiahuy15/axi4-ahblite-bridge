//=============================================================================
// File        : bridge_timeout_boundary_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the C_DPHASE_TIMEOUT threshold boundary sweep.
//               Starts the reactive AHB slave sequence that answers from the
//               shared plan, hands the AXI stimulus the timeout the build was
//               elaborated with, the scoreboard and the expected threshold
//               offset, then stops the slave sequence.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_timeout_boundary_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_timeout_boundary_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;
    bit                       has_expected_offset;
    int                       expected_offset_rd;
    int                       expected_offset_wr;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_timeout_boundary_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_response_policy            policy;
        ahb_slv_response_mapping_seq   ahb_seq;
        axi4_mst_timeout_boundary_seq  axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "Boundary sequence requires auto_gen_resp = 0")
        if (p_sequencer.scb == null)
            `uvm_fatal(get_type_name(),
                       "Boundary sequence requires the scoreboard")

        policy = ahb_response_policy::type_id::create("policy");

        ahb_seq        = ahb_slv_response_mapping_seq::type_id::create("ahb_seq");
        ahb_seq.policy = policy;

        axi_seq = axi4_mst_timeout_boundary_seq::type_id::create("axi_seq");
        axi_seq.policy              = policy;
        axi_seq.scb                 = p_sequencer.scb;
        axi_seq.base_addr           = base_addr;
        axi_seq.case_stride         = case_stride;
        axi_seq.dphase_timeout      = cfg.dphase_timeout;
        axi_seq.has_expected_offset = has_expected_offset;
        axi_seq.expected_offset_rd  = expected_offset_rd;
        axi_seq.expected_offset_wr  = expected_offset_wr;

        fork
            ahb_seq.start(p_sequencer.ahb_sqr);
        join_none

        axi_seq.start(p_sequencer.axi_sqr);
        ahb_seq.kill();
    endtask : body

endclass : bridge_timeout_boundary_seq