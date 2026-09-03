//==============================================================================
// File        : axi4_slave_monitor.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 slave-side monitor.
//               Passively observes AXI4 bus activity on the slave side of
//               the DUT. Functionally identical to axi4_master_monitor but
//               placed on the slave-side interface. Log messages reflect the
//               slave perspective (requests "received", responses "sent").
//
//               Write path: AW -> W beats -> B response -> ap.write()
//               Read path:  AR -> R beats (until RLAST) -> ap.write()
//
//               Supports outstanding AW transactions and out-of-order
//               B/R responses (matched by ID).
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_slave_monitor extends uvm_monitor;

    `uvm_component_utils(axi4_slave_monitor)

    // Virtual interface handle
    virtual axi4_if vif;

    // Analysis port - broadcasts completed transactions to scoreboard/coverage
    uvm_analysis_port #(axi4_transaction) ap;

    // =========================================================================
    // Internal types and queues
    // =========================================================================

    // W beat storage - collected independently of AW to avoid timing issues
    typedef struct {
        bit [AXI4_DATA_WIDTH-1:0] data;
        bit [AXI4_STRB_WIDTH-1:0] strb;
        bit                       last;
    } w_beat_t;

    // Write path queues
    axi4_transaction aw_queue[$];
    w_beat_t         w_beat_queue[$];
    axi4_transaction pending_b[bit[AXI4_ID_WIDTH-1:0]][$];

    // Read path queues
    axi4_transaction pending_r[bit[AXI4_ID_WIDTH-1:0]][$];

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase - create analysis port, get virtual interface
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
    endfunction : build_phase

    // =========================================================================
    // Run phase - fork all channel monitors with reset handling
    // =========================================================================
    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - monitor active", UVM_MEDIUM)

            fork
                monitor_aw_channel();
                monitor_w_beats();
                assemble_write_data();
                monitor_b_channel();
                monitor_ar_channel();
                monitor_r_channel();
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(), "Reset asserted - flushing state", UVM_MEDIUM)
                end
            join_any
            disable fork;
            flush_queues();
        end
    endtask : run_phase

    // =========================================================================
    // AW Channel - Capture write address received by slave
    // =========================================================================
    task monitor_aw_channel();
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.AWVALID && vif.monitor_cb.AWREADY) begin
                axi4_transaction tr;
                tr = axi4_transaction::type_id::create("wr_mon");
                tr.dir    = AXI4_WRITE;
                tr.id     = vif.monitor_cb.AWID;
                tr.addr   = vif.monitor_cb.AWADDR;
                tr.len    = vif.monitor_cb.AWLEN;
                tr.size   = axi4_size_e'(vif.monitor_cb.AWSIZE);
                tr.burst  = axi4_burst_type_e'(vif.monitor_cb.AWBURST);
                tr.lock   = axi4_lock_e'(vif.monitor_cb.AWLOCK);
                tr.cache  = vif.monitor_cb.AWCACHE;
                tr.prot   = vif.monitor_cb.AWPROT;
                tr.qos    = vif.monitor_cb.AWQOS;
                tr.region = vif.monitor_cb.AWREGION;
                tr.data   = new[tr.len + 1];
                tr.strb   = new[tr.len + 1];
                tr.rresp  = new[0];
                aw_queue.push_back(tr);
                `uvm_info(get_type_name(),
                          $sformatf("AW received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                    tr.id, tr.addr, tr.len), UVM_HIGH)
            end
        end
    endtask : monitor_aw_channel

    // =========================================================================
    // W Channel - Collect raw W beats received by slave
    //   Collected independently of AW to handle same-cycle handshakes.
    // =========================================================================
    task monitor_w_beats();
        forever begin
            w_beat_t beat;

            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.WVALID && vif.monitor_cb.WREADY));

            beat.data = vif.monitor_cb.WDATA;
            beat.strb = vif.monitor_cb.WSTRB;
            beat.last = vif.monitor_cb.WLAST;
            w_beat_queue.push_back(beat);
        end
    endtask : monitor_w_beats

    // =========================================================================
    // Assemble Write Data - Match AW with W beats, push to pending_b
    // =========================================================================
    task assemble_write_data();
        forever begin
            axi4_transaction tr;

            wait (aw_queue.size() > 0);
            tr = aw_queue.pop_front();

            for (int beat = 0; beat <= tr.len; beat++) begin
                w_beat_t w;
                wait (w_beat_queue.size() > 0);
                w = w_beat_queue.pop_front();
                tr.data[beat] = w.data;
                tr.strb[beat] = w.strb;

                if (beat == tr.len && !w.last)
                    `uvm_error(get_type_name(),
                               $sformatf("WLAST not asserted on final beat %0d", beat))
                if (beat != tr.len && w.last)
                    `uvm_error(get_type_name(),
                               $sformatf("Unexpected WLAST on beat %0d of %0d", beat, tr.len))
            end

            pending_b[tr.id].push_back(tr);
            `uvm_info(get_type_name(),
                      $sformatf("W data assembled: ID=0x%0h ADDR=0x%08h %0d beats",
                                tr.id, tr.addr, tr.len + 1), UVM_HIGH)
        end
    endtask : assemble_write_data

    // =========================================================================
    // B Channel - Capture write response sent by slave
    // =========================================================================
    task monitor_b_channel();
        forever begin
            bit [AXI4_ID_WIDTH-1:0] bid;

            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.BVALID && vif.monitor_cb.BREADY));

            bid = vif.monitor_cb.BID;

            if (pending_b.exists(bid) && pending_b[bid].size() > 0) begin
                axi4_transaction tr;
                tr = pending_b[bid].pop_front();
                tr.resp = axi4_resp_e'(vif.monitor_cb.BRESP);
                `uvm_info(get_type_name(),
                          $sformatf("Write response sent: ID=0x%0h ADDR=0x%08h RESP=%s",
                                    tr.id, tr.addr, tr.resp.name()), UVM_MEDIUM)
                ap.write(tr);
            end else begin
                `uvm_error(get_type_name(),
                           $sformatf("B response ID=0x%0h - no matching write pending", bid))
            end
        end
    endtask : monitor_b_channel

    // =========================================================================
    // AR Channel - Capture read address received by slave
    // =========================================================================
    task monitor_ar_channel();
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.ARVALID && vif.monitor_cb.ARREADY) begin
                axi4_transaction tr;
                tr = axi4_transaction::type_id::create("rd_mon");
                tr.dir    = AXI4_READ;
                tr.id     = vif.monitor_cb.ARID;
                tr.addr   = vif.monitor_cb.ARADDR;
                tr.len    = vif.monitor_cb.ARLEN;
                tr.size   = axi4_size_e'(vif.monitor_cb.ARSIZE);
                tr.burst  = axi4_burst_type_e'(vif.monitor_cb.ARBURST);
                tr.lock   = axi4_lock_e'(vif.monitor_cb.ARLOCK);
                tr.cache  = vif.monitor_cb.ARCACHE;
                tr.prot   = vif.monitor_cb.ARPROT;
                tr.qos    = vif.monitor_cb.ARQOS;
                tr.region = vif.monitor_cb.ARREGION;
                tr.data   = new[tr.len + 1];
                tr.rresp  = new[tr.len + 1];
                tr.strb   = new[0];
                pending_r[tr.id].push_back(tr);
                `uvm_info(get_type_name(),
                          $sformatf("AR received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                    tr.id, tr.addr, tr.len), UVM_HIGH)
            end
        end
    endtask : monitor_ar_channel

    // =========================================================================
    // R Channel - Collect read data beats sent by slave
    //   AXI4: no interleaving. Beats for one transaction arrive contiguously.
    //   Matched by RID against pending_r queues.
    // =========================================================================
    task monitor_r_channel();
        forever begin
            axi4_transaction tr;
            bit [AXI4_ID_WIDTH-1:0] rid;

            // Wait for first R beat
            do @(vif.monitor_cb);
            while (!(vif.monitor_cb.RVALID && vif.monitor_cb.RREADY));

            rid = vif.monitor_cb.RID;

            if (!pending_r.exists(rid) || pending_r[rid].size() == 0) begin
                `uvm_error(get_type_name(),
                           $sformatf("R data ID=0x%0h - no matching AR pending", rid))
                // Drain until RLAST
                while (!vif.monitor_cb.RLAST) begin
                    do @(vif.monitor_cb);
                    while (!(vif.monitor_cb.RVALID && vif.monitor_cb.RREADY));
                end
                continue;
            end

            tr = pending_r[rid].pop_front();

            // Capture first beat
            tr.data[0]  = vif.monitor_cb.RDATA;
            tr.rresp[0] = axi4_resp_e'(vif.monitor_cb.RRESP);

            if (tr.len == 0) begin
                if (!vif.monitor_cb.RLAST)
                    `uvm_error(get_type_name(),
                               $sformatf("RLAST not asserted on single-beat read (ID=0x%0h)", rid))
            end else begin
                for (int beat = 1; beat <= tr.len; beat++) begin
                    do @(vif.monitor_cb);
                    while (!(vif.monitor_cb.RVALID && vif.monitor_cb.RREADY));

                    tr.data[beat]  = vif.monitor_cb.RDATA;
                    tr.rresp[beat] = axi4_resp_e'(vif.monitor_cb.RRESP);

                    if (beat == tr.len && !vif.monitor_cb.RLAST)
                        `uvm_error(get_type_name(),
                                   $sformatf("RLAST not asserted on final beat %0d (ID=0x%0h)",
                                             beat, rid))
                    if (beat != tr.len && vif.monitor_cb.RLAST)
                        `uvm_error(get_type_name(),
                                   $sformatf("Unexpected RLAST on beat %0d of %0d (ID=0x%0h)",
                                             beat, tr.len, rid))
                end
            end

            `uvm_info(get_type_name(),
                      $sformatf("Read data sent: ID=0x%0h ADDR=0x%08h %0d beats",
                                tr.id, tr.addr, tr.len + 1), UVM_MEDIUM)
            ap.write(tr);
        end
    endtask : monitor_r_channel

    // =========================================================================
    // flush_queues - clear all internal state (called on reset)
    // =========================================================================
    function void flush_queues();
        aw_queue.delete();
        w_beat_queue.delete();
        pending_b.delete();
        pending_r.delete();
    endfunction : flush_queues

    // =========================================================================
    // report_phase - warn about incomplete transactions at end of simulation
    // =========================================================================
    function void report_phase(uvm_phase phase);
        if (aw_queue.size() > 0)
            `uvm_warning(get_type_name(),
                         $sformatf("%0d unmatched AW transactions at end of sim",
                                   aw_queue.size()))
        if (w_beat_queue.size() > 0)
            `uvm_warning(get_type_name(),
                         $sformatf("%0d orphan W beats at end of sim",
                                   w_beat_queue.size()))
        foreach (pending_b[id])
            if (pending_b[id].size() > 0)
                `uvm_warning(get_type_name(),
                             $sformatf("%0d writes ID=0x%0h pending B response",
                                       pending_b[id].size(), id))
        foreach (pending_r[id])
            if (pending_r[id].size() > 0)
                `uvm_warning(get_type_name(),
                             $sformatf("%0d reads ID=0x%0h pending R data",
                                       pending_r[id].size(), id))
    endfunction : report_phase

endclass : axi4_slave_monitor