//==============================================================================
// File        : axi4_master_driver.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 master driver.
//               Receives transactions from the sequencer and drives them
//               onto the AXI4 bus via the master clocking block.
//               Write flow : AW + W (parallel) -> wait B
//               Read flow  : AR -> wait R (all beats)
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_master_driver extends uvm_driver #(axi4_transaction);

    `uvm_component_utils(axi4_master_driver)

    // Virtual interface handle
    virtual axi4_if vif;

    // Drive queues for channel ordering
    protected axi4_transaction aw_drive_queue[$];
    protected axi4_transaction w_drive_queue[$];
    protected axi4_transaction ar_drive_queue[$];

    // Queues and tables for tracking outstanding transactions
    protected axi4_transaction pending_b_tr[bit[AXI4_ID_WIDTH-1:0]][$];
    protected axi4_transaction pending_r_tr[bit[AXI4_ID_WIDTH-1:0]][$];

    // Inter-channel synchronization flags for wr_order constraints
    protected bit aw_done[axi4_transaction];
    protected bit w_started[axi4_transaction];

    // Phase handle for simulation objection control
    protected uvm_phase run_phase_handle;
    protected int unsigned active_objections_cnt = 0;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase - get virtual interface from config_db
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
    endfunction : build_phase

    // =========================================================================
    // Run phase - main driver loop (supports parallel/pipelined outstanding transactions)
    // =========================================================================
    task run_phase(uvm_phase phase);
        run_phase_handle = phase;
        // Outer loop: recover from reset at any time during operation.
        // If reset is asserted mid-transaction, the fork is killed and
        // the driver re-initialises cleanly.
        forever begin
            reset_signals();
            @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - master driver active", UVM_MEDIUM)

            fork
                begin : drive_loop
                    forever begin
                        axi4_transaction tr;
                        seq_item_port.get_next_item(tr);
                        `uvm_info(get_type_name(),
                                  $sformatf("Driving %s  ID=0x%0h  ADDR=0x%08h  LEN=%0d",
                                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_MEDIUM)

                        if (tr.dir == AXI4_WRITE) begin
                            raise_driver_objection("Pending write transaction");
                            pending_b_tr[tr.id].push_back(tr);
                            aw_drive_queue.push_back(tr);
                            w_drive_queue.push_back(tr);
                        end else begin
                            raise_driver_objection("Pending read transaction");
                            pending_r_tr[tr.id].push_back(tr);
                            ar_drive_queue.push_back(tr);
                        end

                        seq_item_port.item_done();
                    end
                end
                aw_drive_loop();
                w_drive_loop();
                ar_drive_loop();
                receive_b_responses();
                receive_r_responses();
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(), "Reset asserted - aborting", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    // =========================================================================
    // Reset - deassert all master-driven VALID / READY signals
    // =========================================================================
    task reset_signals();
        @(vif.master_cb);
        vif.master_cb.AWVALID <= 1'b0;
        vif.master_cb.WVALID  <= 1'b0;
        vif.master_cb.BREADY  <= 1'b0;
        vif.master_cb.ARVALID <= 1'b0;
        vif.master_cb.RREADY  <= 1'b0;
        vif.master_cb.WLAST   <= 1'b0;

        aw_drive_queue.delete();
        w_drive_queue.delete();
        ar_drive_queue.delete();
        pending_b_tr.delete();
        pending_r_tr.delete();
        aw_done.delete();
        w_started.delete();
        clear_objections();
    endtask : reset_signals

    // =========================================================================
    // Objection helpers
    // =========================================================================
    function void raise_driver_objection(string desc = "");
        if (run_phase_handle != null) begin
            run_phase_handle.raise_objection(this, desc);
            active_objections_cnt++;
        end
    endfunction

    function void drop_driver_objection(string desc = "");
        if (run_phase_handle != null && active_objections_cnt > 0) begin
            run_phase_handle.drop_objection(this, desc);
            active_objections_cnt--;
        end
    endfunction

    function void clear_objections();
        if (run_phase_handle != null) begin
            repeat (active_objections_cnt) begin
                run_phase_handle.drop_objection(this, "Reset cleanup");
            end
        end
        active_objections_cnt = 0;
    endfunction

    // =========================================================================
    // Channel drive loops - process transactions in FIFO order from the queues
    // =========================================================================
    task aw_drive_loop();
        forever begin
            axi4_transaction tr;
            wait(aw_drive_queue.size() > 0);
            tr = aw_drive_queue[0];

            if (tr.wr_order == AXI4_WR_W_BEFORE_AW) begin
                wait(w_started.exists(tr) && w_started[tr] == 1);
                repeat ($urandom_range(5, 2)) @(vif.master_cb);
            end

            void'(aw_drive_queue.pop_front());
            drive_aw_channel(tr);
            aw_done[tr] = 1;
        end
    endtask : aw_drive_loop

    task w_drive_loop();
        forever begin
            axi4_transaction tr;
            wait(w_drive_queue.size() > 0);
            tr = w_drive_queue[0];

            if (tr.wr_order == AXI4_WR_AW_BEFORE_W) begin
                wait(aw_done.exists(tr) && aw_done[tr] == 1);
            end

            void'(w_drive_queue.pop_front());
            w_started[tr] = 1;
            drive_w_channel(tr);
        end
    endtask : w_drive_loop

    task ar_drive_loop();
        forever begin
            axi4_transaction tr;
            wait(ar_drive_queue.size() > 0);
            tr = ar_drive_queue.pop_front();
            drive_ar_channel(tr);
        end
    endtask : ar_drive_loop

    // =========================================================================
    // AW Channel - Write Address phase
    // =========================================================================
    task drive_aw_channel(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.AWVALID  <= 1'b1;
        vif.master_cb.AWID     <= tr.id;
        vif.master_cb.AWADDR   <= tr.addr;
        vif.master_cb.AWLEN    <= tr.len;
        vif.master_cb.AWSIZE   <= tr.size;
        vif.master_cb.AWBURST  <= tr.burst;
        vif.master_cb.AWLOCK   <= tr.lock;
        vif.master_cb.AWCACHE  <= tr.cache;
        vif.master_cb.AWPROT   <= tr.prot;
        vif.master_cb.AWQOS    <= tr.qos;
        vif.master_cb.AWREGION <= tr.region;

        // Wait for AWREADY handshake
        do @(vif.master_cb);
        while (!vif.master_cb.AWREADY);

        // Handshake complete - deassert VALID
        vif.master_cb.AWVALID <= 1'b0;
    endtask : drive_aw_channel

    // =========================================================================
    // W Channel - Write Data phase
    // =========================================================================
    task drive_w_channel(axi4_transaction tr);
        for (int i = 0; i <= tr.len; i++) begin
            @(vif.master_cb);
            vif.master_cb.WVALID <= 1'b1;
            vif.master_cb.WDATA  <= tr.data[i];
            vif.master_cb.WSTRB  <= tr.strb[i];
            vif.master_cb.WLAST   <= (i == tr.len) ? 1'b1 : 1'b0;

            // Wait for WREADY handshake
            do @(vif.master_cb);
            while (!vif.master_cb.WREADY);
        end

        // All beats sent - deassert
        vif.master_cb.WVALID <= 1'b0;
        vif.master_cb.WLAST  <= 1'b0;
    endtask : drive_w_channel

    // =========================================================================
    // AR Channel - Read Address phase
    // =========================================================================
    task drive_ar_channel(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.ARVALID  <= 1'b1;
        vif.master_cb.ARID     <= tr.id;
        vif.master_cb.ARADDR   <= tr.addr;
        vif.master_cb.ARLEN    <= tr.len;
        vif.master_cb.ARSIZE   <= tr.size;
        vif.master_cb.ARBURST  <= tr.burst;
        vif.master_cb.ARLOCK   <= tr.lock;
        vif.master_cb.ARCACHE  <= tr.cache;
        vif.master_cb.ARPROT   <= tr.prot;
        vif.master_cb.ARQOS    <= tr.qos;
        vif.master_cb.ARREGION <= tr.region;

        // Wait for ARREADY handshake
        do @(vif.master_cb);
        while (!vif.master_cb.ARREADY);

        // Handshake complete - deassert VALID
        vif.master_cb.ARVALID <= 1'b0;
    endtask : drive_ar_channel

    // =========================================================================
    // B Channel response receiver (kept active in parallel)
    // =========================================================================
    task receive_b_responses();
        vif.master_cb.BREADY <= 1'b1;
        forever begin
            @(vif.master_cb);
            if (vif.master_cb.BVALID) begin
                bit [AXI4_ID_WIDTH-1:0] bid;
                bid = vif.master_cb.BID;
                if (pending_b_tr.exists(bid) && pending_b_tr[bid].size() > 0) begin
                    axi4_transaction tr;
                    tr = pending_b_tr[bid].pop_front();
                    tr.resp = axi4_resp_e'(vif.master_cb.BRESP);
                    
                    w_started.delete(tr);
                    aw_done.delete(tr);
                    
                    drop_driver_objection("Write response received");
                    ->tr.done_event.ev;
                    `uvm_info(get_type_name(),
                              $sformatf("Master driver received B response: ID=0x%0h RESP=%s",
                                        tr.id, tr.resp.name()), UVM_HIGH)
                end else begin
                    `uvm_error(get_type_name(),
                               $sformatf("Master driver received unexpected B response ID=0x%0h", bid))
                end
            end
        end
    endtask : receive_b_responses

    // =========================================================================
    // R Channel response receiver (kept active in parallel)
    // =========================================================================
    task receive_r_responses();
        vif.master_cb.RREADY <= 1'b1;
        forever begin
            bit [AXI4_ID_WIDTH-1:0] rid;
            axi4_transaction tr;

            do @(vif.master_cb);
            while (!vif.master_cb.RVALID);

            rid = vif.master_cb.RID;

            if (pending_r_tr.exists(rid) && pending_r_tr[rid].size() > 0) begin
                tr = pending_r_tr[rid].pop_front();
                tr.data[0]  = vif.master_cb.RDATA;
                tr.rresp[0] = axi4_resp_e'(vif.master_cb.RRESP);

                if (tr.len == 0) begin
                    if (!vif.master_cb.RLAST)
                        `uvm_error(get_type_name(),
                                   $sformatf("RLAST not asserted on single-beat read (ID=0x%0h)", rid))
                end else begin
                    for (int i = 1; i <= tr.len; i++) begin
                        do @(vif.master_cb);
                        while (!vif.master_cb.RVALID);

                        // AXI4: no read data interleaving - verify RID is
                        // consistent across all beats within a burst.
                        if (vif.master_cb.RID !== rid)
                            `uvm_error(get_type_name(),
                                       $sformatf("RID changed mid-burst: expected 0x%0h, got 0x%0h on beat %0d (ADDR=0x%08h)",
                                                 rid, vif.master_cb.RID, i, tr.addr))

                        tr.data[i]  = vif.master_cb.RDATA;
                        tr.rresp[i] = axi4_resp_e'(vif.master_cb.RRESP);

                        if (i == tr.len && !vif.master_cb.RLAST)
                            `uvm_error(get_type_name(),
                                       $sformatf("RLAST not asserted on final beat %0d (ID=0x%0h)", i, rid))
                        if (i != tr.len && vif.master_cb.RLAST)
                            `uvm_error(get_type_name(),
                                       $sformatf("Unexpected RLAST on beat %0d of %0d (ID=0x%0h)", i, tr.len, rid))
                    end
                end
                
                drop_driver_objection("Read completed");
                ->tr.done_event.ev;
                `uvm_info(get_type_name(),
                          $sformatf("Master driver received all R beats for ID=0x%0h", tr.id), UVM_HIGH)
            end else begin
                `uvm_error(get_type_name(),
                           $sformatf("Master driver received unexpected R response ID=0x%0h", rid))
                while (!vif.master_cb.RLAST) begin
                    do @(vif.master_cb);
                    while (!vif.master_cb.RVALID);
                end
            end
        end
    endtask : receive_r_responses

endclass : axi4_master_driver