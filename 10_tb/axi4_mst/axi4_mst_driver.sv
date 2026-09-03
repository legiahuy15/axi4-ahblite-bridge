//=============================================================================
// File        : axi4_mst_driver.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 master driver with independent channel processing.
//               Included inside the bridge package.
//=============================================================================

//-----------------------------------------------------------------------------
// Internal request context
//-----------------------------------------------------------------------------
class axi4_mst_req_ctx;
    axi4_transaction tr;
    bit aw_done;
    bit w_started;

    function new(axi4_transaction tr);
        this.tr = tr;
    endfunction : new
endclass : axi4_mst_req_ctx

class axi4_mst_driver extends uvm_driver #(axi4_transaction);

    `uvm_component_utils(axi4_mst_driver)

    //-------------------------------------------------------------------------
    // Configuration and interface
    //-------------------------------------------------------------------------
    axi4_mst_agent_cfg cfg;
    axi4_vif_t         vif;

    //-------------------------------------------------------------------------
    // Channel and outstanding queues
    //-------------------------------------------------------------------------
    protected axi4_mst_req_ctx aw_queue[$];
    protected axi4_mst_req_ctx w_queue[$];
    protected axi4_mst_req_ctx ar_queue[$];
    protected axi4_mst_req_ctx pending_b[bit [AXI4_ID_WIDTH-1:0]][$];
    protected axi4_mst_req_ctx pending_r[bit [AXI4_ID_WIDTH-1:0]][$];
    protected int unsigned     outstanding_count;

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
        if (!uvm_config_db#(axi4_mst_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_type_name(), "AXI4 master agent config not found")
        vif = cfg.vif;
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        forever begin
            drive_idle();
            wait_reset_release();

            fork
                dispatch_items();
                drive_aw_loop();
                drive_w_loop();
                drive_ar_loop();
                receive_b_loop();
                receive_r_loop();
                wait_reset_assertion();
            join_any
            disable fork;

            flush_state();
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // Request dispatcher
    //-------------------------------------------------------------------------
    protected task dispatch_items();
        forever begin
            axi4_transaction req;
            axi4_transaction tr;
            axi4_mst_req_ctx ctx;

            wait ((cfg.max_outstanding == 0) ||
                  (outstanding_count < cfg.max_outstanding));
            seq_item_port.get_next_item(req);

            if (!request_is_valid(req)) begin
                seq_item_port.item_done();
                continue;
            end

            if (!$cast(tr, req.clone()))
                `uvm_fatal(get_type_name(), "AXI4 request clone failed")
            tr.set_id_info(req);
            ctx = new(tr);

            if (tr.dir == AXI4_WRITE) begin
                pending_b[tr.id].push_back(ctx);
                aw_queue.push_back(ctx);
                w_queue.push_back(ctx);
            end else begin
                pending_r[tr.id].push_back(ctx);
                ar_queue.push_back(ctx);
            end

            outstanding_count++;
            seq_item_port.item_done();
        end
    endtask : dispatch_items

    //-------------------------------------------------------------------------
    // Channel schedulers
    //-------------------------------------------------------------------------
    protected task drive_aw_loop();
        forever begin
            axi4_mst_req_ctx ctx;

            wait (aw_queue.size() > 0);
            ctx = aw_queue.pop_front();

            if (ctx.tr.wr_order == AXI4_WR_W_BEFORE_AW) begin
                wait (ctx.w_started);
                repeat (cfg.w_before_aw_delay) @(vif.master_cb);
            end

            drive_aw(ctx.tr);
            ctx.aw_done = 1'b1;
        end
    endtask : drive_aw_loop

    protected task drive_w_loop();
        forever begin
            axi4_mst_req_ctx ctx;

            wait (w_queue.size() > 0);
            ctx = w_queue.pop_front();

            if (ctx.tr.wr_order == AXI4_WR_AW_BEFORE_W)
                wait (ctx.aw_done);

            ctx.w_started = 1'b1;
            drive_w(ctx.tr);
        end
    endtask : drive_w_loop

    protected task drive_ar_loop();
        forever begin
            axi4_mst_req_ctx ctx;

            wait (ar_queue.size() > 0);
            ctx = ar_queue.pop_front();
            drive_ar(ctx.tr);
        end
    endtask : drive_ar_loop

    //-------------------------------------------------------------------------
    // Request channel drivers
    //-------------------------------------------------------------------------
    protected task drive_aw(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.AWID    <= tr.id;
        vif.master_cb.AWADDR  <= tr.addr;
        vif.master_cb.AWLEN   <= tr.len;
        vif.master_cb.AWSIZE  <= tr.size;
        vif.master_cb.AWBURST <= tr.burst;
        vif.master_cb.AWLOCK  <= tr.lock;
        vif.master_cb.AWCACHE <= tr.cache;
        vif.master_cb.AWPROT  <= tr.prot;
        vif.master_cb.AWVALID <= 1'b1;

        do @(vif.master_cb);
        while (vif.master_cb.AWREADY !== 1'b1);

        vif.master_cb.AWVALID <= 1'b0;
    endtask : drive_aw

    protected task drive_w(axi4_transaction tr);
        foreach (tr.data[i]) begin
            @(vif.master_cb);
            vif.master_cb.WDATA  <= tr.data[i];
            vif.master_cb.WSTRB  <= tr.strb[i];
            vif.master_cb.WLAST  <= (i == tr.data.size() - 1);
            vif.master_cb.WVALID <= 1'b1;

            do @(vif.master_cb);
            while (vif.master_cb.WREADY !== 1'b1);
        end

        vif.master_cb.WVALID <= 1'b0;
        vif.master_cb.WLAST  <= 1'b0;
    endtask : drive_w

    protected task drive_ar(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.ARID    <= tr.id;
        vif.master_cb.ARADDR  <= tr.addr;
        vif.master_cb.ARLEN   <= tr.len;
        vif.master_cb.ARSIZE  <= tr.size;
        vif.master_cb.ARBURST <= tr.burst;
        vif.master_cb.ARLOCK  <= tr.lock;
        vif.master_cb.ARCACHE <= tr.cache;
        vif.master_cb.ARPROT  <= tr.prot;
        vif.master_cb.ARVALID <= 1'b1;

        do @(vif.master_cb);
        while (vif.master_cb.ARREADY !== 1'b1);

        vif.master_cb.ARVALID <= 1'b0;
    endtask : drive_ar

    //-------------------------------------------------------------------------
    // Response channel receivers
    //-------------------------------------------------------------------------
    protected task receive_b_loop();
        forever begin
            bit [AXI4_ID_WIDTH-1:0] bid;
            bit [1:0]               bresp;
            axi4_mst_req_ctx        ctx;

            get_b_response(bid, bresp);
            if (!pending_b.exists(bid) || pending_b[bid].size() == 0) begin
                `uvm_error(get_type_name(),
                           $sformatf("Unexpected B response ID=0x%0h", bid))
                continue;
            end

            ctx = pending_b[bid].pop_front();
            ctx.tr.bresp = axi4_resp_e'(bresp);
            complete_item(ctx.tr);
        end
    endtask : receive_b_loop

    protected task receive_r_loop();
        forever begin
            bit [AXI4_ID_WIDTH-1:0]   rid;
            bit [AXI4_DATA_WIDTH-1:0] rdata;
            bit [1:0]                 rresp;
            bit                       rlast;
            axi4_mst_req_ctx          ctx;

            get_r_beat(rid, rdata, rresp, rlast);
            if (!pending_r.exists(rid) || pending_r[rid].size() == 0) begin
                `uvm_error(get_type_name(),
                           $sformatf("Unexpected R response ID=0x%0h", rid))
                continue;
            end

            ctx = pending_r[rid].pop_front();
            for (int unsigned i = 0; i < ctx.tr.data.size(); i++) begin
                if (i != 0)
                    get_r_beat(rid, rdata, rresp, rlast);

                if (rid != ctx.tr.id)
                    `uvm_error(get_type_name(),
                               $sformatf("RID changed within burst: expected 0x%0h, got 0x%0h",
                                         ctx.tr.id, rid))
                if (rlast != (i == ctx.tr.data.size() - 1))
                    `uvm_error(get_type_name(),
                               $sformatf("Incorrect RLAST on beat %0d, ID=0x%0h", i, rid))

                ctx.tr.data[i]  = rdata;
                ctx.tr.rresp[i] = axi4_resp_e'(rresp);
            end

            complete_item(ctx.tr);
        end
    endtask : receive_r_loop

    //-------------------------------------------------------------------------
    // Response handshake helpers
    //-------------------------------------------------------------------------
    protected task get_b_response(
        output bit [AXI4_ID_WIDTH-1:0] bid,
        output bit [1:0]               bresp
    );
        int unsigned delay_cycles;

        if ((cfg.bready_delay_min == 0) && (cfg.bready_delay_max == 0)) begin
            vif.master_cb.BREADY <= 1'b1;
            do @(vif.master_cb);
            while (vif.master_cb.BVALID !== 1'b1);
        end else begin
            vif.master_cb.BREADY <= 1'b0;
            do @(vif.master_cb);
            while (vif.master_cb.BVALID !== 1'b1);
            delay_cycles = $urandom_range(cfg.bready_delay_max,
                                          cfg.bready_delay_min);
            repeat (delay_cycles) @(vif.master_cb);
            vif.master_cb.BREADY <= 1'b1;
            do @(vif.master_cb);
            while (vif.master_cb.BVALID !== 1'b1);
            vif.master_cb.BREADY <= 1'b0;
        end

        bid   = vif.master_cb.BID;
        bresp = vif.master_cb.BRESP;
    endtask : get_b_response

    protected task get_r_beat(
        output bit [AXI4_ID_WIDTH-1:0]   rid,
        output bit [AXI4_DATA_WIDTH-1:0] rdata,
        output bit [1:0]                 rresp,
        output bit                       rlast
    );
        int unsigned delay_cycles;

        if ((cfg.rready_delay_min == 0) && (cfg.rready_delay_max == 0)) begin
            vif.master_cb.RREADY <= 1'b1;
            do @(vif.master_cb);
            while (vif.master_cb.RVALID !== 1'b1);
        end else begin
            vif.master_cb.RREADY <= 1'b0;
            do @(vif.master_cb);
            while (vif.master_cb.RVALID !== 1'b1);
            delay_cycles = $urandom_range(cfg.rready_delay_max,
                                          cfg.rready_delay_min);
            repeat (delay_cycles) @(vif.master_cb);
            vif.master_cb.RREADY <= 1'b1;
            do @(vif.master_cb);
            while (vif.master_cb.RVALID !== 1'b1);
            vif.master_cb.RREADY <= 1'b0;
        end

        rid   = vif.master_cb.RID;
        rdata = vif.master_cb.RDATA;
        rresp = vif.master_cb.RRESP;
        rlast = vif.master_cb.RLAST;
    endtask : get_r_beat

    //-------------------------------------------------------------------------
    // Transaction completion and validation
    //-------------------------------------------------------------------------
    protected task complete_item(axi4_transaction tr);
        axi4_transaction rsp;

        if (outstanding_count > 0)
            outstanding_count--;

        if (cfg.return_responses) begin
            if (!$cast(rsp, tr.clone()))
                `uvm_fatal(get_type_name(), "AXI4 response clone failed")
            rsp.set_id_info(tr);
            seq_item_port.put_response(rsp);
        end
    endtask : complete_item

    protected function bit request_is_valid(axi4_transaction tr);
        int unsigned beats;

        beats = int'(tr.len) + 1;
        if (tr.data.size() != beats) begin
            `uvm_error(get_type_name(), "AXI4 data array size does not match AxLEN")
            return 1'b0;
        end
        if ((tr.dir == AXI4_WRITE) && (tr.strb.size() != beats)) begin
            `uvm_error(get_type_name(), "AXI4 strobe array size does not match AWLEN")
            return 1'b0;
        end
        if ((tr.dir == AXI4_READ) && (tr.rresp.size() != beats)) begin
            `uvm_error(get_type_name(), "AXI4 response array size does not match ARLEN")
            return 1'b0;
        end
        return 1'b1;
    endfunction : request_is_valid

    //-------------------------------------------------------------------------
    // Reset handling
    //-------------------------------------------------------------------------
    protected task drive_idle();
        @(vif.master_cb);
        vif.master_cb.AWID    <= '0;
        vif.master_cb.AWADDR  <= '0;
        vif.master_cb.AWLEN   <= '0;
        vif.master_cb.AWSIZE  <= '0;
        vif.master_cb.AWBURST <= '0;
        vif.master_cb.AWLOCK  <= '0;
        vif.master_cb.AWCACHE <= '0;
        vif.master_cb.AWPROT  <= '0;
        vif.master_cb.AWVALID <= 1'b0;
        vif.master_cb.WDATA   <= '0;
        vif.master_cb.WSTRB   <= '0;
        vif.master_cb.WLAST   <= 1'b0;
        vif.master_cb.WVALID  <= 1'b0;
        vif.master_cb.BREADY  <= 1'b0;
        vif.master_cb.ARID    <= '0;
        vif.master_cb.ARADDR  <= '0;
        vif.master_cb.ARLEN   <= '0;
        vif.master_cb.ARSIZE  <= '0;
        vif.master_cb.ARBURST <= '0;
        vif.master_cb.ARLOCK  <= '0;
        vif.master_cb.ARCACHE <= '0;
        vif.master_cb.ARPROT  <= '0;
        vif.master_cb.ARVALID <= 1'b0;
        vif.master_cb.RREADY  <= 1'b0;
    endtask : drive_idle

    protected task wait_reset_release();
        while (vif.rst_n !== 1'b1)
            @(vif.master_cb);
    endtask : wait_reset_release

    protected task wait_reset_assertion();
        forever begin
            @(vif.master_cb);
            if (vif.rst_n !== 1'b1)
                return;
        end
    endtask : wait_reset_assertion

    protected function void flush_state();
        if (outstanding_count != 0)
            `uvm_info(get_type_name(),
                      $sformatf("Reset discarded %0d outstanding AXI4 transaction(s)",
                                outstanding_count), UVM_MEDIUM)
        aw_queue.delete();
        w_queue.delete();
        ar_queue.delete();
        pending_b.delete();
        pending_r.delete();
        outstanding_count = 0;
    endfunction : flush_state

endclass : axi4_mst_driver