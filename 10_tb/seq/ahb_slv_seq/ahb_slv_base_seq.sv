//=============================================================================
// File        : ahb_slv_base_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Base sequence for reactive AHB-Lite slave responses.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class ahb_slv_base_seq extends uvm_sequence #(ahb_slave_response);

    `uvm_object_utils(ahb_slv_base_seq)
    `uvm_declare_p_sequencer(ahb_slv_sequencer)

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    ahb_slv_agent_cfg cfg;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_slv_base_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence setup
    //-------------------------------------------------------------------------
    virtual task pre_start();
        super.pre_start();

        if (p_sequencer == null)
            `uvm_fatal(get_type_name(), "AHB-Lite slave sequencer is null")
        if (p_sequencer.cfg == null)
            `uvm_fatal(get_type_name(), "AHB-Lite slave agent config is null")

        cfg = p_sequencer.cfg;
        if (cfg.is_active != UVM_ACTIVE)
            `uvm_fatal(get_type_name(), "AHB-Lite slave agent is not active")
        if (cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "Disable auto_gen_resp for sequenced AHB responses")
    endtask : pre_start

    //-------------------------------------------------------------------------
    // Reactive response helpers
    //-------------------------------------------------------------------------
    virtual task wait_ahb_request(output ahb_transfer req);
        wait (p_sequencer.req != null);
        req = p_sequencer.req;
    endtask : wait_ahb_request

    virtual task send_ahb_response(ahb_slave_response rsp);
        if (rsp == null)
            `uvm_fatal(get_type_name(), "AHB-Lite response is null")

        wait (p_sequencer.req != null);
        start_item(rsp);
        finish_item(rsp);
    endtask : send_ahb_response

    //-------------------------------------------------------------------------
    // Clock and reset helpers
    //-------------------------------------------------------------------------
    virtual task wait_reset_release();
        wait (cfg.vif.rst_n === 1'b1);
        @(cfg.vif.slave_cb);
    endtask : wait_reset_release

    virtual task wait_cycles(int unsigned cycles);
        repeat (cycles) @(cfg.vif.slave_cb);
    endtask : wait_cycles

endclass : ahb_slv_base_seq
