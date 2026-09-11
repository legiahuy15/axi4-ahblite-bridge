//=============================================================================
// File        : axi4_mst_monitor.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 monitor and transaction assembler.
//               Included inside the bridge package.
//=============================================================================

class axi4_mst_monitor extends uvm_monitor;

    `uvm_component_utils(axi4_mst_monitor)

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct packed {
        bit [AXI4_DATA_WIDTH-1:0] data;
        bit [AXI4_STRB_WIDTH-1:0] strb;
        bit                       last;
    } axi4_w_beat_t;

    //-------------------------------------------------------------------------
    // Configuration and interface
    //-------------------------------------------------------------------------
    axi4_mst_agent_cfg cfg;
    axi4_vif_t         vif;

    // Accepted requests and completed transactions
    uvm_analysis_port #(axi4_transaction) req_ap;
    uvm_analysis_port #(axi4_transaction) ap;

    //-------------------------------------------------------------------------
    // Assembly queues
    //-------------------------------------------------------------------------
    protected axi4_transaction aw_queue[$];
    protected axi4_w_beat_t     w_queue[$];
    protected axi4_transaction pending_b[bit [AXI4_ID_WIDTH-1:0]][$];
    protected axi4_transaction pending_r[bit [AXI4_ID_WIDTH-1:0]][$];

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
        req_ap = new("req_ap", this);
        ap     = new("ap", this);
        if (!uvm_config_db#(axi4_mst_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_type_name(), "AXI4 master agent config not found")
        vif = cfg.vif;
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        forever begin
            wait_reset_release();

            fork
                monitor_aw();
                monitor_w();
                assemble_write();
                monitor_b();
                monitor_ar();
                monitor_r();
                wait_reset_assertion();
            join_any
            disable fork;

            flush_state();
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // Write channel monitoring
    //-------------------------------------------------------------------------
    protected task monitor_aw();
        forever begin
            @(vif.monitor_cb);
            if ((vif.monitor_cb.AWVALID === 1'b1) &&
                (vif.monitor_cb.AWREADY === 1'b1)) begin
                axi4_transaction tr;

                tr = axi4_transaction::type_id::create("aw_tr");
                tr.dir      = AXI4_WRITE;
                tr.id       = vif.monitor_cb.AWID;
                tr.addr     = vif.monitor_cb.AWADDR;
                tr.len      = vif.monitor_cb.AWLEN;
                tr.size     = axi4_size_e'(vif.monitor_cb.AWSIZE);
                tr.burst    = axi4_burst_e'(vif.monitor_cb.AWBURST);
                tr.lock     = axi4_lock_e'(vif.monitor_cb.AWLOCK);
                tr.cache    = vif.monitor_cb.AWCACHE;
                tr.prot     = vif.monitor_cb.AWPROT;
                tr.wr_order = AXI4_WR_PARALLEL;
                tr.data     = new[int'(tr.len) + 1];
                tr.strb     = new[int'(tr.len) + 1];
                tr.rresp    = new[0];
                aw_queue.push_back(tr);
            end
        end
    endtask : monitor_aw

    protected task monitor_w();
        forever begin
            @(vif.monitor_cb);
            if ((vif.monitor_cb.WVALID === 1'b1) &&
                (vif.monitor_cb.WREADY === 1'b1)) begin
                axi4_w_beat_t beat;

                beat.data = vif.monitor_cb.WDATA;
                beat.strb = vif.monitor_cb.WSTRB;
                beat.last = vif.monitor_cb.WLAST;
                w_queue.push_back(beat);
            end
        end
    endtask : monitor_w

    protected task assemble_write();
        forever begin
            axi4_transaction tr;
            int unsigned     beats;

            wait (aw_queue.size() > 0);
            tr    = aw_queue[0];
            beats = int'(tr.len) + 1;
            wait (w_queue.size() >= beats);
            void'(aw_queue.pop_front());

            for (int unsigned i = 0; i < beats; i++) begin
                axi4_w_beat_t beat;

                beat       = w_queue.pop_front();
                tr.data[i] = beat.data;
                tr.strb[i] = beat.strb;
                if (beat.last != (i == beats - 1))
                    `uvm_error(get_type_name(),
                               $sformatf("Incorrect WLAST on beat %0d, ID=0x%0h",
                                         i, tr.id))
            end

            `uvm_info(get_type_name(),
                      $sformatf("[MON][AXI][REQ] %s",
                                tr.convert2string()),
                      UVM_HIGH)
            write_clone(req_ap, tr);
            pending_b[tr.id].push_back(tr);
        end
    endtask : assemble_write

    protected task monitor_b();
        forever begin
            bit [AXI4_ID_WIDTH-1:0] bid;
            axi4_transaction        tr;

            @(vif.monitor_cb);
            if ((vif.monitor_cb.BVALID === 1'b1) &&
                (vif.monitor_cb.BREADY === 1'b1)) begin
                bid = vif.monitor_cb.BID;
                if (!pending_b.exists(bid) || pending_b[bid].size() == 0) begin
                    `uvm_error(get_type_name(),
                               $sformatf("Observed unexpected B response ID=0x%0h", bid))
                    continue;
                end

                tr       = pending_b[bid].pop_front();
                tr.bresp = axi4_resp_e'(vif.monitor_cb.BRESP);
                `uvm_info(get_type_name(),
                          $sformatf("[MON][AXI][RSP] WRITE id=0x%0h resp=%s",
                                    tr.id, tr.bresp.name()),
                          UVM_HIGH)
                write_clone(ap, tr);
            end
        end
    endtask : monitor_b

    //-------------------------------------------------------------------------
    // Read channel monitoring
    //-------------------------------------------------------------------------
    protected task monitor_ar();
        forever begin
            @(vif.monitor_cb);
            if ((vif.monitor_cb.ARVALID === 1'b1) &&
                (vif.monitor_cb.ARREADY === 1'b1)) begin
                axi4_transaction tr;

                tr = axi4_transaction::type_id::create("ar_tr");
                tr.dir      = AXI4_READ;
                tr.id       = vif.monitor_cb.ARID;
                tr.addr     = vif.monitor_cb.ARADDR;
                tr.len      = vif.monitor_cb.ARLEN;
                tr.size     = axi4_size_e'(vif.monitor_cb.ARSIZE);
                tr.burst    = axi4_burst_e'(vif.monitor_cb.ARBURST);
                tr.lock     = axi4_lock_e'(vif.monitor_cb.ARLOCK);
                tr.cache    = vif.monitor_cb.ARCACHE;
                tr.prot     = vif.monitor_cb.ARPROT;
                tr.wr_order = AXI4_WR_PARALLEL;
                tr.data     = new[int'(tr.len) + 1];
                tr.strb     = new[0];
                tr.rresp    = new[int'(tr.len) + 1];
                pending_r[tr.id].push_back(tr);
                `uvm_info(get_type_name(),
                          $sformatf("[MON][AXI][REQ] %s",
                                    tr.convert2string()),
                          UVM_HIGH)
                write_clone(req_ap, tr);
            end
        end
    endtask : monitor_ar

    protected task monitor_r();
        forever begin
            bit [AXI4_ID_WIDTH-1:0] rid;
            axi4_transaction        tr;

            do @(vif.monitor_cb);
            while (!((vif.monitor_cb.RVALID === 1'b1) &&
                     (vif.monitor_cb.RREADY === 1'b1)));

            rid = vif.monitor_cb.RID;
            if (!pending_r.exists(rid) || pending_r[rid].size() == 0) begin
                `uvm_error(get_type_name(),
                           $sformatf("Observed unexpected R response ID=0x%0h", rid))
                continue;
            end

            tr = pending_r[rid].pop_front();
            for (int unsigned i = 0; i < tr.data.size(); i++) begin
                if (i != 0) begin
                    do @(vif.monitor_cb);
                    while (!((vif.monitor_cb.RVALID === 1'b1) &&
                             (vif.monitor_cb.RREADY === 1'b1)));
                end

                if (vif.monitor_cb.RID != tr.id)
                    `uvm_error(get_type_name(),
                               $sformatf("RID changed within burst: expected 0x%0h, got 0x%0h",
                                         tr.id, vif.monitor_cb.RID))
                if (vif.monitor_cb.RLAST != (i == tr.data.size() - 1))
                    `uvm_error(get_type_name(),
                               $sformatf("Incorrect RLAST on beat %0d, ID=0x%0h", i, tr.id))

                tr.data[i]  = vif.monitor_cb.RDATA;
                tr.rresp[i] = axi4_resp_e'(vif.monitor_cb.RRESP);
                `uvm_info(get_type_name(),
                          $sformatf({"[MON][AXI][R] id=0x%0h beat=%0d/%0d ",
                                     "data=0x%0h resp=%s last=%0b"},
                                    tr.id, i + 1, tr.data.size(), tr.data[i],
                                    tr.rresp[i].name(), vif.monitor_cb.RLAST),
                          UVM_HIGH)
            end

            `uvm_info(get_type_name(),
                      $sformatf("[MON][AXI][RSP] READ id=0x%0h beats=%0d",
                                tr.id, tr.data.size()),
                      UVM_HIGH)
            write_clone(ap, tr);
        end
    endtask : monitor_r

    //-------------------------------------------------------------------------
    // Analysis helpers
    //-------------------------------------------------------------------------
    protected function void write_clone(
        uvm_analysis_port #(axi4_transaction) port_h,
        axi4_transaction                      tr
    );
        axi4_transaction copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "AXI4 monitor transaction clone failed")
        port_h.write(copy_tr);
    endfunction : write_clone

    //-------------------------------------------------------------------------
    // Reset handling
    //-------------------------------------------------------------------------
    protected task wait_reset_release();
        while (vif.rst_n !== 1'b1)
            @(vif.monitor_cb);
    endtask : wait_reset_release

    protected task wait_reset_assertion();
        forever begin
            @(vif.monitor_cb);
            if (vif.rst_n !== 1'b1)
                return;
        end
    endtask : wait_reset_assertion

    protected function void flush_state();
        aw_queue.delete();
        w_queue.delete();
        pending_b.delete();
        pending_r.delete();
    endfunction : flush_state

endclass : axi4_mst_monitor