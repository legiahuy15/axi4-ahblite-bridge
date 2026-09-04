//=============================================================================
// File        : ahb_slv_monitor.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite pipelined transfer monitor.
//               Included inside the bridge package.
//=============================================================================

class ahb_slv_monitor extends uvm_monitor;

    `uvm_component_utils(ahb_slv_monitor)

    //-------------------------------------------------------------------------
    // Configuration and interface
    //-------------------------------------------------------------------------
    ahb_slv_agent_cfg cfg;
    ahb_vif_t         vif;

    // Completed transfers and accepted HTRANS values
    uvm_analysis_port #(ahb_transfer) ap;
    uvm_analysis_port #(ahb_trans_e)  trans_ap;

    //-------------------------------------------------------------------------
    // Pipelined transfer state
    //-------------------------------------------------------------------------
    protected ahb_transfer pending_tr;
    protected bit          pending_valid;
    protected int unsigned pending_waits;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap       = new("ap", this);
        trans_ap = new("trans_ap", this);
        if (!uvm_config_db#(ahb_slv_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_type_name(), "AHB-Lite slave agent config not found")
        vif = cfg.vif;
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        forever begin
            flush_state();
            wait_reset_release();

            fork
                collect_loop();
                wait_reset_assertion();
            join_any
            disable fork;
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // Transfer collection
    //-------------------------------------------------------------------------
    protected task collect_loop();
        forever begin
            ahb_trans_e htrans;

            @(vif.monitor_cb);
            if (vif.monitor_cb.HREADY !== 1'b1) begin
                if (pending_valid)
                    pending_waits++;
                continue;
            end

            if (pending_valid)
                complete_pending();

            htrans = ahb_trans_e'(vif.monitor_cb.HTRANS);
            trans_ap.write(htrans);
            if (htrans inside {AHB_TRANS_NONSEQ, AHB_TRANS_SEQ})
                capture_address(htrans);
        end
    endtask : collect_loop

    protected function void capture_address(ahb_trans_e htrans);
        pending_tr          = ahb_transfer::type_id::create("mon_tr");
        pending_tr.addr     = vif.monitor_cb.HADDR;
        pending_tr.write    = ahb_dir_e'(vif.monitor_cb.HWRITE);
        pending_tr.trans    = htrans;
        pending_tr.burst    = ahb_burst_e'(vif.monitor_cb.HBURST);
        pending_tr.size     = ahb_size_e'(vif.monitor_cb.HSIZE);
        pending_tr.prot     = vif.monitor_cb.HPROT;
        pending_tr.mastlock = vif.monitor_cb.HMASTLOCK;
        pending_tr.wdata    = '0;
        pending_tr.rdata    = '0;
        pending_tr.resp     = AHB_RESP_OKAY;
        pending_tr.wait_cycles = 0;
        pending_waits = 0;
        pending_valid = 1'b1;
    endfunction : capture_address

    protected function void complete_pending();
        pending_tr.resp        = ahb_resp_e'(vif.monitor_cb.HRESP);
        pending_tr.wait_cycles = pending_waits;
        if (pending_tr.write == AHB_WRITE)
            pending_tr.wdata = vif.monitor_cb.HWDATA;
        else
            pending_tr.rdata = vif.monitor_cb.HRDATA;

        `uvm_info(get_type_name(),
                  $sformatf({"[MON][AHB][TR] %s | data=0x%0h"},
                            pending_tr.convert2string(),
                            (pending_tr.write == AHB_WRITE) ?
                                pending_tr.wdata : pending_tr.rdata),
                  UVM_HIGH)
        ap.write(pending_tr);
        pending_tr    = null;
        pending_valid = 1'b0;
        pending_waits = 0;
    endfunction : complete_pending

    //-------------------------------------------------------------------------
    // Reset handling
    //-------------------------------------------------------------------------
    protected task wait_reset_release();
        wait (vif.rst_n === 1'b1);
    endtask : wait_reset_release

    protected task wait_reset_assertion();
        forever begin
            @(vif.monitor_cb);
            if (vif.rst_n !== 1'b1)
                return;
        end
    endtask : wait_reset_assertion

    protected function void flush_state();
        pending_tr    = null;
        pending_valid = 1'b0;
        pending_waits = 0;
    endfunction : flush_state

endclass : ahb_slv_monitor