//=============================================================================
// File        : bridge_base_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Base virtual sequence for bridge-level scenarios.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_base_seq extends uvm_sequence #(uvm_sequence_item);

    `uvm_object_utils(bridge_base_seq)
    `uvm_declare_p_sequencer(virtual_sequencer)

    //-------------------------------------------------------------------------
    // Configuration
    //-------------------------------------------------------------------------
    vip_env_cfg cfg;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_base_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence setup
    //-------------------------------------------------------------------------
    virtual task pre_start();
        super.pre_start();

        if (p_sequencer == null)
            `uvm_fatal(get_type_name(), "Virtual sequencer is null")
        if (p_sequencer.cfg == null)
            `uvm_fatal(get_type_name(), "VIP environment config is null")

        cfg = p_sequencer.cfg;
    endtask : pre_start

    //-------------------------------------------------------------------------
    // Child sequencer checks
    //-------------------------------------------------------------------------
    protected function void require_axi_sequencer();
        if ((cfg.axi_cfg.is_active != UVM_ACTIVE) ||
            (p_sequencer.axi_sqr == null))
            `uvm_fatal(get_type_name(), "AXI4 master sequencer is unavailable")
    endfunction : require_axi_sequencer

    protected function void require_ahb_sequencer();
        if ((cfg.ahb_cfg.is_active != UVM_ACTIVE) ||
            (p_sequencer.ahb_sqr == null))
            `uvm_fatal(get_type_name(),
                       "AHB-Lite slave sequencer is unavailable")
    endfunction : require_ahb_sequencer

    //-------------------------------------------------------------------------
    // Clock and reset helpers
    //-------------------------------------------------------------------------
    virtual task wait_reset_release();
        wait (cfg.axi_cfg.vif.rst_n === 1'b1);
        @(cfg.axi_cfg.vif.master_cb);
    endtask : wait_reset_release

    virtual task wait_cycles(int unsigned cycles);
        repeat (cycles) @(cfg.axi_cfg.vif.master_cb);
    endtask : wait_cycles

endclass : bridge_base_seq