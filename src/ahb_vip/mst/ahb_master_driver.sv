//=============================================================================
// File        : ahb_master_driver.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite master driver.
//               Drives sequencer transactions onto the bus.
//=============================================================================

class ahb_master_driver extends uvm_driver #(ahb_transaction);

    `uvm_component_utils(ahb_master_driver)

    // Virtual interface handle
    virtual ahb_if vif;

    // Back-to-back: overlap next txn's addr phase into the last data phase
    bit en_back_to_back = 1;

    // Defer that overlap: slot opens as IDLE, upgraded to NONSEQ during the
    // wait state (IHI0033A 3.6.1)
    bit en_idle_to_nonseq_in_wait = 0;

    // Backpressure: max accepted-but-not-completed txns (0 = unlimited)
    int unsigned max_outstanding = 0;

    // FIFO of accepted-but-not-yet-driven transactions (outstanding)
    protected ahb_transaction drive_queue[$];

    // Next txn whose beat-0 addr phase is already in flight (overlap slot)
    protected ahb_transaction next_tr;

    // Txn currently being driven on the bus (for reset flush)
    protected ahb_transaction active_tr;

    // Objection tracking
    protected uvm_phase run_phase_handle;
    protected int unsigned active_objections_cnt = 0;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - get virtual interface from config_db
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        ahb_agent_config cfg;
        super.build_phase(phase);
        if(!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
        // Optional - defaults kept when absent
        if (uvm_config_db#(ahb_agent_config)::get(this, "", "cfg", cfg)) begin
            en_back_to_back           = cfg.en_back_to_back;
            en_idle_to_nonseq_in_wait = cfg.en_idle_to_nonseq_in_wait;
            max_outstanding           = cfg.max_outstanding;
        end
    endfunction: build_phase

    //-------------------------------------------------------------------------
    // Run phase - accept loop and bus loop run in parallel (outstanding txns)
    //-------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        run_phase_handle = phase;
        // Reset recovery: rst_watch kills the fork, reset_signals() re-inits
        forever begin
            reset_signals();
            // Wait until reset is de-asserted
            if (!vif.rst_n) @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - master driver active", UVM_MEDIUM)

            fork
                begin : accept_loop
                    forever begin
                        ahb_transaction tr;
                        // Backpressure: stall at max_outstanding in flight
                        if (max_outstanding != 0)
                            wait (active_objections_cnt < max_outstanding);
                        seq_item_port.get_next_item(tr);
                        `uvm_info(get_type_name(),
                                  $sformatf("Queueing [%s]: HADDR=0x%08h, HBURST=%s, HSIZE=%s, %0d beats",
                                            tr.write.name(), tr.addr, tr.burst.name(),
                                            tr.size.name(), tr.get_num_beats()), UVM_MEDIUM)

                        raise_driver_objection("Pending AHB transaction");
                        drive_queue.push_back(tr);

                        seq_item_port.item_done();
                    end
                end
                bus_drive_loop();
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(),
                              "Reset asserted - aborting transaction", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // Bus drive loop - drive queued txns FIFO. A txn from the overlap slot
    // (next_tr) already has its beat-0 address phase in flight
    //-------------------------------------------------------------------------
    task bus_drive_loop();
        forever begin
            ahb_transaction tr;
            bit addr_in_flight;

            if (next_tr != null) begin
                tr = next_tr;
                next_tr = null;
                addr_in_flight = 1;
            end else begin
                wait(drive_queue.size() > 0);
                tr = drive_queue.pop_front();
                addr_in_flight = 0;
            end

            `uvm_info(get_type_name(),
                      $sformatf("Driving [%s]: HADDR=0x%08h, HBURST=%s, HSIZE=%s, %0d beats%s",
                                 tr.write.name(), tr.addr, tr.burst.name(),
                                 tr.size.name(), tr.get_num_beats(),
                                 addr_in_flight ? " (back-to-back)" : ""), UVM_MEDIUM)

            active_tr = tr;
            drive_transaction(tr, addr_in_flight);
            active_tr = null;

            drop_driver_objection("AHB transaction completed");
            complete_txn(tr, 1'b0);
        end
    endtask : bus_drive_loop

    //-------------------------------------------------------------------------
    // Release a waiting sequence. Function, so aborted/done are set in the
    // same time step
    //-------------------------------------------------------------------------
    function void complete_txn(ahb_transaction tr, bit is_aborted);
        tr.aborted = is_aborted;
        tr.done    = 1'b1;
    endfunction : complete_txn

    //-------------------------------------------------------------------------
    // Objection helpers
    //-------------------------------------------------------------------------
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

    //-------------------------------------------------------------------------
    // Flush on reset - mark in-flight txn, overlap slot and queue as aborted
    //-------------------------------------------------------------------------
    function void flush_pending(string reason = "");
        ahb_transaction tr;
        if (active_tr != null) begin
            complete_txn(active_tr, 1'b1);
            active_tr = null;
        end
        if (next_tr != null) begin
            complete_txn(next_tr, 1'b1);
            next_tr = null;
        end
        while (drive_queue.size() > 0) begin
            tr = drive_queue.pop_front();
            complete_txn(tr, 1'b1);
        end
        if (reason != "")
            `uvm_info(get_type_name(),
                      $sformatf("Flushed pending transactions (%s)", reason), UVM_MEDIUM)
    endfunction

    function void clear_objections();
        if (run_phase_handle != null) begin
            repeat (active_objections_cnt) begin
                run_phase_handle.drop_objection(this, "Reset cleanup");
            end
        end
        active_objections_cnt = 0;
    endfunction

    //-------------------------------------------------------------------------
    // Drive one transaction, pipelined: addr[i+1] overlaps data[i]. Handles
    // BUSY insertion, INCR termination out of BUSY, ERROR policy, back-to-back
    // overlap. addr_in_flight=1: beat 0 accepted by the previous overlap slot
    //-------------------------------------------------------------------------
    task drive_transaction(ahb_transaction tr, bit addr_in_flight = 0);
        int num_beats;
        int n_busy;
        bit pipelined_own;   // overlap slot belongs to this burst (cancel on ERROR)
        bit busy_retracted;  // BUSY already withdrawn during this wait
        bit idle_slot;       // slot holds an IDLE that may still become NONSEQ
        bit [AHB_ADDR_WIDTH-1:0] beat_addr[];

        num_beats     = tr.get_num_beats();
        tr.beats_done = 0;

        // Pre-compute beat addresses
        beat_addr = new[num_beats];
        beat_addr[0] = tr.addr;
        for (int i = 1; i < num_beats; i++)
            beat_addr[i] = calc_next_addr(tr, beat_addr[i-1]);

        if (!addr_in_flight) begin
            // Beat 0 address phase (burst starts with NONSEQ)
            @(vif.master_cb);
            drive_addr_phase0(tr);

            // Wait until the address phase is accepted
            do begin
                @(vif.master_cb);
            end while (vif.master_cb.HREADY !== 1'b1);
        end
        // else: beat 0 accepted at the previous txn's last data-phase edge

        // Per beat: drive data[i], then the pipelined addr phase
        // (BUSY and/or addr[i+1]; overlap or IDLE after the last beat)
        for (int i = 0; i < num_beats; i++) begin

            // Write data for beat i
            if (tr.write == AHB_WRITE)
                vif.master_cb.HWDATA <= tr.wdata[i];

            // BUSY count: before beat i+1, or trailing (INCR) after the last beat
            if (i < num_beats - 1)
                n_busy = (i+1 < tr.busy_cycles.size()) ? tr.busy_cycles[i+1] : 0;
            else
                n_busy = tr.trailing_busy_cycles;

            // Pipelined addr phase; during BUSY the bus holds the next transfer
            pipelined_own = 1'b1;
            idle_slot     = 1'b0;
            if (n_busy > 0) begin
                vif.master_cb.HTRANS <= AHB_TRANS_BUSY;
                vif.master_cb.HADDR  <= (i < num_beats - 1)
                                        ? beat_addr[i+1]
                                        : calc_next_addr(tr, beat_addr[i]);
            end else if (i < num_beats - 1) begin
                vif.master_cb.HADDR  <= beat_addr[i+1];
                vif.master_cb.HTRANS <= tr.trans[i+1];
            end else begin
                // Last beat: overlap the next queued txn's beat-0 addr phase,
                // else IDLE. That NONSEQ is a new burst - never cancelled here.
                // en_idle_to_nonseq_in_wait defers it to the wait loop below
                if (en_back_to_back && !en_idle_to_nonseq_in_wait &&
                    drive_queue.size() > 0)
                    next_tr = drive_queue.pop_front();
                if (next_tr != null) begin
                    drive_addr_phase0(next_tr);
                    pipelined_own = 1'b0;
                end else begin
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                    idle_slot = en_back_to_back && en_idle_to_nonseq_in_wait;
                end
            end

            // Wait HREADY; on the ERROR first cycle cancel the overlapped
            // transfer to IDLE (own slot only, only when aborting)
            busy_retracted = 1'b0;
            forever begin
                @(vif.master_cb);
                if (vif.master_cb.HREADY === 1'b1) break;

                if (vif.master_cb.HRESP === AHB_RESP_ERROR &&
                    tr.abort_on_error && pipelined_own) begin
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                    // ERROR cancel may move the address with HREADY low
                    // (IHI0033A 3.6.2); ignored while HTRANS is IDLE
                    if (tr.addr_change_on_error)
                        vif.master_cb.HADDR <= (drive_queue.size() > 0)
                                               ? drive_queue[0].addr : '0;
                end
                // Withdraw the presented BUSY for the transfer that ends the
                // run. Once only - the replacement must hold until HREADY
                else if (tr.busy_retract_in_wait && n_busy > 0 && !busy_retracted) begin
                    busy_retracted = 1'b1;
                    n_busy         = 0;             // BUSY run is over
                    if (i < num_beats - 1) begin
                        // BUSY -> SEQ, address already presented with the BUSY
                        vif.master_cb.HTRANS <= tr.trans[i+1];
                    end else begin
                        // End of INCR burst: hand the slot to the next txn,
                        // else close with IDLE
                        if (en_back_to_back && drive_queue.size() > 0)
                            next_tr = drive_queue.pop_front();
                        if (next_tr != null) begin
                            drive_addr_phase0(next_tr);     // BUSY -> NONSEQ
                            pipelined_own = 1'b0;
                        end else begin
                            vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                        end
                    end
                end
                // IDLE in the pipelined slot may become NONSEQ while HREADY is
                // low; this loop then holds it until accepted. Once only, and
                // skipped on ERROR, where IDLE cancels the pipeline instead
                else if (idle_slot && drive_queue.size() > 0 &&
                         vif.master_cb.HRESP === AHB_RESP_OKAY) begin
                    idle_slot     = 1'b0;
                    next_tr       = drive_queue.pop_front();
                    drive_addr_phase0(next_tr);
                    pipelined_own = 1'b0;
                end
            end

            // Sample response (valid on the HREADY=1 cycle)
            if (tr.write == AHB_READ)
                tr.rdata[i] = vif.master_cb.HRDATA;
            tr.resp[i]    = ahb_resp_e'(vif.master_cb.HRESP);
            tr.beats_done = i + 1;

            `uvm_info(get_type_name(),
                      $sformatf("Beat[%0d/%0d] addr=0x%08h trans=%s resp=%s %s=0x%08h",
                                i, num_beats, beat_addr[i],
                                tr.trans[i].name(),
                                tr.resp[i].name(),
                                (tr.write == AHB_WRITE) ? "wdata" : "rdata",
                                (tr.write == AHB_WRITE) ? tr.wdata[i] : tr.rdata[i]),
                      UVM_HIGH)

            // ERROR: abort=1 -> abandon burst (own slot forced IDLE);
            // abort=0 -> continue. Both spec-legal
            if (tr.resp[i] == AHB_RESP_ERROR) begin
                if (tr.abort_on_error) begin
                    `uvm_info(get_type_name(),
                              $sformatf("ERROR response on beat %0d/%0d%s",
                                        i, num_beats,
                                        (i < num_beats - 1) ? " - cancelling remaining burst" : ""),
                              UVM_MEDIUM)
                    if (pipelined_own)
                        vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                    break;
                end
                `uvm_info(get_type_name(),
                          $sformatf("ERROR response on beat %0d/%0d - continuing burst (abort_on_error=0)",
                                    i, num_beats), UVM_MEDIUM)
            end

            // Remaining BUSY cycles (BUSY completes zero-wait OKAY), then
            // present the ending transfer
            if (n_busy > 0) begin
                repeat (n_busy - 1) begin
                    do @(vif.master_cb); while (vif.master_cb.HREADY !== 1'b1);
                end
                if (i < num_beats - 1) begin
                    vif.master_cb.HADDR  <= beat_addr[i+1];
                    vif.master_cb.HTRANS <= tr.trans[i+1];
                end else begin
                    // INCR ends out of BUSY -> IDLE (no overlap on this path)
                    vif.master_cb.HTRANS <= AHB_TRANS_IDLE;
                end
                do @(vif.master_cb); while (vif.master_cb.HREADY !== 1'b1);
            end
        end

        // Clear stale HWDATA unless the next txn's beat-0 was overlapped in
        if (next_tr == null)
            vif.master_cb.HWDATA <= '0;

        `uvm_info(get_type_name(),
                  $sformatf("Transaction complete: %s 0x%08h, %0d beats, burst=%s",
                            tr.write.name(), tr.addr, num_beats, tr.burst.name()),
                  UVM_MEDIUM)
    endtask : drive_transaction

    //-------------------------------------------------------------------------
    // Beat-0 address phase - at transaction start and in the overlap slot
    //-------------------------------------------------------------------------
    task drive_addr_phase0(ahb_transaction tr);
        vif.master_cb.HADDR     <= tr.addr;
        vif.master_cb.HBURST    <= tr.burst;
        vif.master_cb.HMASTLOCK <= tr.lock;
        vif.master_cb.HPROT     <= tr.prot;
        vif.master_cb.HSIZE     <= tr.size;
        vif.master_cb.HTRANS    <= tr.trans[0];
        vif.master_cb.HWRITE    <= tr.write;
    endtask : drive_addr_phase0

    //-------------------------------------------------------------------------
    // Next beat address (beats 1...N-1 only; SINGLE never reaches here)
    //   INCR: addr + 2^HSIZE
    //   WRAP: wraps at num_beats * 2^HSIZE
    //-------------------------------------------------------------------------
    function bit [AHB_ADDR_WIDTH-1:0] calc_next_addr(
        ahb_transaction tr,
        bit [AHB_ADDR_WIDTH-1:0] current_addr
    );
        int unsigned bytes_per_beat;
        int unsigned wrap_boundary;
        bit [AHB_ADDR_WIDTH-1:0] next_addr;
        bit [AHB_ADDR_WIDTH-1:0] wrap_mask;

        bytes_per_beat = 1 << tr.size;
        next_addr = current_addr + bytes_per_beat;

        case (tr.burst)
            AHB_BURST_INCR,
            AHB_BURST_INCR4,
            AHB_BURST_INCR8,
            AHB_BURST_INCR16: begin
                return next_addr;
            end

            AHB_BURST_WRAP4,
            AHB_BURST_WRAP8,
            AHB_BURST_WRAP16: begin
                wrap_boundary = tr.get_num_beats() * bytes_per_beat;
                wrap_mask = wrap_boundary - 1;
                // Keep upper bits, wrap lower bits
                return (current_addr & ~wrap_mask) | (next_addr & wrap_mask);
            end

            default: return next_addr;
        endcase
    endfunction : calc_next_addr

    //-------------------------------------------------------------------------
    // Reset - deassert all master-driven signals and flush pipeline state
    //-------------------------------------------------------------------------
    task reset_signals();
        @(vif.master_cb);
        vif.master_cb.HTRANS    <= AHB_TRANS_IDLE;
        vif.master_cb.HMASTLOCK <= 1'b0;
        vif.master_cb.HADDR     <= '0;
        vif.master_cb.HBURST    <= '0;
        vif.master_cb.HPROT     <= '0;
        vif.master_cb.HSIZE     <= '0;
        vif.master_cb.HWRITE    <= 1'b0;
        vif.master_cb.HWDATA    <= '0;

        // Unblock waiting sequences, then release objections
        flush_pending("reset");
        clear_objections();
    endtask : reset_signals

endclass : ahb_master_driver