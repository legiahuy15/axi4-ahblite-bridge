//=============================================================================
// File        : ahb_back_to_back_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Continuous traffic with no IDLE between transfers. Whole
//               batches of write/read-back bursts are queued without waiting,
//               so the driver always holds a successor and overlaps its beat-0
//               address phase into the previous data phase (IHI0033A 3.1).
//               The master's outstanding limit is swept across the batches,
//               from unlimited down to a fully serialized single transfer.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_BACK_TO_BACK_SEQ_INCLUDED_
`define AHB_BACK_TO_BACK_SEQ_INCLUDED_

class ahb_back_to_back_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_back_to_back_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 32;                 // write/read pairs to run

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0001_0000;

    // Pairs queued before the batch is drained and checked. Two transfers per
    // pair, so a batch offers up to 2 x batch_pairs transfers to the driver
    int unsigned batch_pairs = 4;

    // Master driver whose outstanding limit is swept, set by the test. The
    // driver latches max_outstanding in build_phase, so the field must be poked
    // directly. Null: traffic runs at the configured limit
    ahb_master_driver mst_drv;

    localparam int unsigned NUM_WINDOWS = 4;

    // One slot per pair, 64-byte aligned and twice the longest burst issued
    // here (8 beats x 4 bytes), so a WRAP region falls wholly inside it and
    // slots never alias in the scoreboard reference memory
    localparam int unsigned SLOT_SIZE = 64;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned num_queued;                        // transfers handed over
    int unsigned deepest_outstanding;               // over the whole run
    int unsigned deepest_per_window[NUM_WINDOWS];   // per swept limit
    int unsigned limit_violations;                  // accepted beyond the limit

    //-------------------------------------------------------------------------
    // Transfers accepted but not yet complete, oldest first. The driver runs
    // its queue FIFO, so the front always retires first
    //-------------------------------------------------------------------------
    protected ahb_transaction pend[$];

    // Set in body(): the limit is ours to sweep and therefore ours to check
    protected bit sweep_on;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_back_to_back_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // The outstanding limits, swept in order (AHB_ENV_004):
    //   0 - unlimited, the whole batch sits in the driver queue
    //   4 - deep enough that a successor is always waiting
    //   2 - exactly one successor, the minimum for an overlap
    //   1 - fully serialized: the accept loop stalls until the bus is free, so
    //       no successor exists and every transfer opens after an IDLE
    //-------------------------------------------------------------------------
    function int unsigned get_limit(int unsigned idx);
        case (idx % NUM_WINDOWS)
            0:       return 0;
            1:       return 4;
            2:       return 2;
            default: return 1;
        endcase
    endfunction : get_limit

    //-------------------------------------------------------------------------
    // Hand the limit to the driver. Called between batches only, with the
    // pipeline drained, so no accepted transfer outlives its limit
    //-------------------------------------------------------------------------
    function void apply_limit(int unsigned lim);
        if (mst_drv == null) return;
        mst_drv.max_outstanding = lim;
    endfunction : apply_limit

    //-------------------------------------------------------------------------
    // Limit as it reads in a log line
    //-------------------------------------------------------------------------
    function string limit_str(int unsigned lim);
        if (lim == 0) return "unlimited";
        return $sformatf("%0d", lim);
    endfunction : limit_str

    //-------------------------------------------------------------------------
    // queue_tracked - hand one transfer over without waiting for the bus, and
    // record how deep the pipeline got. queue_item() returns once the driver
    // has accepted the item, so the depth measured here is exactly what the
    // accept loop is holding: with a limit in force it must never exceed it
    //-------------------------------------------------------------------------
    task queue_tracked(ahb_transaction tr, int unsigned lim, int unsigned win);
        queue_item(tr);
        pend.push_back(tr);
        num_queued++;

        // Retire everything the driver has finished
        while (pend.size() > 0 && pend[0].done)
            void'(pend.pop_front());

        if (pend.size() > deepest_outstanding)
            deepest_outstanding = pend.size();
        if (pend.size() > deepest_per_window[win])
            deepest_per_window[win] = pend.size();

        // Only meaningful for a limit this sequence put in force itself
        if (sweep_on && lim != 0 && pend.size() > lim) begin
            limit_violations++;
            `uvm_error(get_type_name(),
                       $sformatf("Outstanding limit exceeded: %0d transfers in flight, max_outstanding=%0d",
                                 pend.size(), lim))
        end
    endtask : queue_tracked

    //-------------------------------------------------------------------------
    // Body - batches of write/read-back pairs queued without a gap, under a
    // swept outstanding limit
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr_q[$];
        ahb_transaction          rd_q[$];
        ahb_transaction          wr, rd;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        int unsigned             pair_idx;
        int unsigned             num_batches;
        int unsigned             this_batch;
        int unsigned             win;
        int unsigned             lim;

        if (batch_pairs == 0) batch_pairs = 1;

        sweep_on = (mst_drv != null);
        if (!sweep_on)
            `uvm_warning(get_type_name(),
                         "No master driver handle - the outstanding limit is not swept, traffic runs at the configured limit")

        num_batches = (num_iter + batch_pairs - 1) / batch_pairs;

        `uvm_info(get_type_name(),
                  $sformatf("Starting back-to-back traffic: %0d pairs from 0x%08h, %0d batches of %0d",
                            num_iter, base_addr, num_batches, batch_pairs), UVM_LOW)

        pair_idx = 0;
        for (int unsigned b = 0; b < num_batches; b++) begin
            win = b % NUM_WINDOWS;
            lim = get_limit(win);
            apply_limit(lim);

            this_batch = num_iter - pair_idx;
            if (this_batch > batch_pairs) this_batch = batch_pairs;

            `uvm_info(get_type_name(),
                      $sformatf("Batch %0d/%0d: %0d pairs, max_outstanding=%s",
                                b + 1, num_batches, this_batch,
                                limit_str(lim)), UVM_MEDIUM)

            wr_q.delete();
            rd_q.delete();

            //-----------------------------------------------------------------
            // Queue the whole batch without waiting: every transfer is already
            // in the driver queue when its predecessor reaches the last data
            // phase, which is what opens the overlap slot
            //-----------------------------------------------------------------
            for (int unsigned k = 0; k < this_batch; k++) begin
                slot = base_addr + pair_idx * SLOT_SIZE;

                wr = ahb_transaction::type_id::create("wr");
                if (!wr.randomize() with {
                        write == AHB_WRITE;
                        burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR,
                                      AHB_BURST_INCR4,  AHB_BURST_INCR8,
                                      AHB_BURST_WRAP4,  AHB_BURST_WRAP8};
                        size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                        (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                        // No BUSY - a master stall would open exactly the
                        // bubble this sequence is out to avoid
                        foreach (busy_cycles[i]) busy_cycles[i] == 0;
                        trailing_busy_cycles == 0;

                        // inside range bounds addr so the span sum cannot wrap
                        addr inside {[slot : slot + SLOT_SIZE - 1]};
                        (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                       AHB_BURST_INCR8}) ->
                            (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                    })
                    `uvm_fatal(get_type_name(),
                               $sformatf("Write randomization failed @slot 0x%08h", slot))

                // Same control, same address - AHB is in order, so the read
                // returns what the write ahead of it committed
                rd = build_read_back(wr);

                wr_q.push_back(wr);
                rd_q.push_back(rd);

                queue_tracked(wr, lim, win);
                queue_tracked(rd, lim, win);

                pair_idx++;
            end

            //-----------------------------------------------------------------
            // Drain and check. The batch is compared only once every transfer
            // in it has left the bus
            //-----------------------------------------------------------------
            foreach (rd_q[k]) begin
                wr = wr_q[k];
                rd = rd_q[k];
                wait (wr.done);
                wait (rd.done);

                if (wr.aborted || rd.aborted) begin
                    `uvm_warning(get_type_name(),
                                 $sformatf("Pair aborted by reset: %s 0x%08h",
                                           wr.burst.name(), wr.addr))
                    continue;
                end

                compare_burst(wr, rd);
            end

            pend.delete();      // batch drained
        end

        //---------------------------------------------------------------------
        // A limit of 2 or more, or none at all, must leave a successor waiting
        // while a transfer is on the bus - otherwise the driver never had the
        // chance to overlap and the run proves nothing about AHB_BAS_004
        //---------------------------------------------------------------------
        for (int unsigned w = 0; w < NUM_WINDOWS; w++) begin
            lim = get_limit(w);
            if (deepest_per_window[w] == 0) continue;       // window never ran

            `uvm_info(get_type_name(),
                      $sformatf("  max_outstanding=%s -> deepest pipeline %0d transfers",
                                limit_str(lim), deepest_per_window[w]), UVM_MEDIUM)

            if (sweep_on && lim != 1 && deepest_per_window[w] < 2)
                `uvm_error(get_type_name(),
                           $sformatf("max_outstanding=%0d never held more than %0d transfer(s) - no overlap was possible",
                                     lim, deepest_per_window[w]))
        end

        `uvm_info(get_type_name(),
                  $sformatf("Back-to-back done: pairs=%0d transfers=%0d deepest=%0d limit_violations=%0d beats=%0d mismatch=%0d",
                            num_iter, num_queued, deepest_outstanding,
                            limit_violations, beats_checked, beats_mismatch),
                  (beats_mismatch == 0 && limit_violations == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_back_to_back_seq

`endif // AHB_BACK_TO_BACK_SEQ_INCLUDED_
