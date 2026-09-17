//=============================================================================
// File        : axi4_mst_base_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Base sequence for AXI4 master stimulus.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_base_seq extends uvm_sequence #(axi4_transaction);

    `uvm_object_utils(axi4_mst_base_seq)
    `uvm_declare_p_sequencer(axi4_mst_sequencer)

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    axi4_mst_agent_cfg cfg;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] addr_lo = '0;
    bit [AXI4_ADDR_WIDTH-1:0] addr_hi = '1;
    bit [AXI4_ID_WIDTH-1:0]   id_lo   = '0;
    bit [AXI4_ID_WIDTH-1:0]   id_hi   = '1;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_base_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence setup
    //-------------------------------------------------------------------------
    virtual task pre_start();
        super.pre_start();

        if (p_sequencer == null)
            `uvm_fatal(get_type_name(), "AXI4 master sequencer is null")
        if (p_sequencer.cfg == null)
            `uvm_fatal(get_type_name(), "AXI4 master agent config is null")

        cfg = p_sequencer.cfg;
        if (cfg.is_active != UVM_ACTIVE)
            `uvm_fatal(get_type_name(), "AXI4 master agent is not active")
    endtask : pre_start

    //-------------------------------------------------------------------------
    // Request helpers
    //-------------------------------------------------------------------------
    virtual task send_axi_request(axi4_transaction req);
        if (req == null)
            `uvm_fatal(get_type_name(), "AXI4 request is null")

        start_item(req);
        finish_item(req);
    endtask : send_axi_request

    virtual task send_axi_request_wait(
        axi4_transaction req,
        output axi4_transaction rsp
    );
        if (!cfg.return_responses)
            `uvm_fatal(get_type_name(),
                       "AXI4 return_responses must be enabled")

        send_axi_request(req);
        get_response(rsp, req.get_transaction_id());
        if (rsp == null)
            `uvm_fatal(get_type_name(), "AXI4 response is null")
    endtask : send_axi_request_wait

    //-------------------------------------------------------------------------
    // Clock and reset helpers
    //-------------------------------------------------------------------------
    virtual task wait_reset_release();
        wait (cfg.vif.rst_n === 1'b1);
        @(cfg.vif.master_cb);
    endtask : wait_reset_release

    virtual task wait_cycles(int unsigned cycles);
        repeat (cycles) @(cfg.vif.master_cb);
    endtask : wait_cycles

endclass : axi4_mst_base_seq