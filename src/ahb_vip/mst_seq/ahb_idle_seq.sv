//=============================================================================
// File        : ahb_idle_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : IDLE transfer sequence. Deliberately leaves the bus IDLE, in
//               runs of one to max_gap cycles, before a burst, between a write
//               and its read-back, and after the burst has closed. Runs in
//               three phases so every shape of IDLE the spec allows appears:
//                 1) gap     - zero-wait traffic separated by IDLE runs, the
//                              plain accepted IDLE transfer (AHB_TRN_001,
//                              AHB_TRN_006)
//                 2) busy    - the same with BUSY runs inside the bursts, so
//                              IDLE and BUSY are both answered zero-wait OKAY
//                              (AHB_WAI_010)
//                 3) in-wait - pipelined pairs against a slave that always
//                              waits, so the pipelined slot is presented as
//                              IDLE with HREADY low and the address moves
//                              underneath it (AHB_WAI_007)
//               The read-back compare proves the slave ignored every IDLE it
//               was given: no IDLE may disturb the memory model.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_IDLE_SEQ_INCLUDED_
`define AHB_IDLE_SEQ_INCLUDED_

class ahb_idle_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_idle_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 24;                 // write/read pairs, all phases

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_F000;

    // Longest IDLE run requested between two transfers. The driver closes every
    // burst with an IDLE of its own, so the run observed on the bus is longer
    int unsigned max_gap = 4;

    //-------------------------------------------------------------------------
    // Handles supplied by the test
    //-------------------------------------------------------------------------

    // Bus clock, used to count out the IDLE runs. Null: the gaps collapse to
    // the single IDLE the driver inserts on its own
    virtual ahb_if vif;

    // Slave driver whose wait-state window is set per phase. The driver latches
    // ready_delay_min/max in build_phase, so the fields must be poked directly.
    // Null: traffic runs at the configured window
    ahb_slave_driver slv_drv;

    localparam int unsigned NUM_PHASES = 3;

    // One slot per pair, 64-byte aligned and twice the longest burst issued
    // here (8 beats x 4 bytes), so a WRAP region falls wholly inside it and
    // slots never alias in the scoreboard reference memory
    localparam int unsigned SLOT_SIZE = 64;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned iter_per_phase[NUM_PHASES];    // pairs issued in each phase
    int unsigned num_gaps;                      // IDLE runs requested
    int unsigned num_gap_cycles;                // ... totalling this many cycles
    int unsigned longest_gap;                   // longest run requested

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_idle_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Hand a wait-state window to the slave. Called between transfers only, so
    // no beat sees its wait count change underneath it
    //-------------------------------------------------------------------------
    function void apply_window(int unsigned lo, int unsigned hi);
        if (slv_drv == null) return;
        slv_drv.ready_delay_min = lo;
        slv_drv.ready_delay_max = hi;
    endfunction : apply_window

    //-------------------------------------------------------------------------
    // idle_gap - hold the sequence off the sequencer for n bus cycles. The
    // driver queue is empty while this runs, so its pipelined slot stays IDLE
    // and the bus idles for the whole window
    //-------------------------------------------------------------------------
    task idle_gap(int unsigned n);
        if (n == 0) return;

        num_gaps++;
        num_gap_cycles += n;
        if (n > longest_gap) longest_gap = n;

        if (vif == null) return;        // no clock handle - nothing to count
        repeat (n) @(vif.monitor_cb);
    endtask : idle_gap

    //-------------------------------------------------------------------------
    // random_gap - 1 to max_gap cycles, never zero: an IDLE run is the point
    //-------------------------------------------------------------------------
    function int unsigned random_gap();
        if (max_gap == 0) return 1;
        return $urandom_range(max_gap, 1);
    endfunction : random_gap

    //-------------------------------------------------------------------------
    // Body - the three phases, each over its own address range
    //-------------------------------------------------------------------------
    virtual task body();
        int unsigned n_gap, n_busy, n_wait;

        if (num_iter < NUM_PHASES) num_iter = NUM_PHASES;   // one pair per phase

        if (vif == null)
            `uvm_warning(get_type_name(),
                         "No bus interface handle - IDLE runs are not extended, the bus only idles for the cycle the driver inserts itself")
        if (slv_drv == null)
            `uvm_warning(get_type_name(),
                         "No slave driver handle - the wait-state window is not set per phase, traffic runs at the configured back-pressure")

        n_gap  = (num_iter + 2) / NUM_PHASES;
        n_busy = (num_iter + 1) / NUM_PHASES;
        n_wait = num_iter - n_gap - n_busy;

        `uvm_info(get_type_name(),
                  $sformatf("Starting IDLE traffic: %0d pairs from 0x%08h, IDLE runs up to %0d cycles (gap=%0d busy=%0d in-wait=%0d)",
                            num_iter, base_addr, max_gap, n_gap, n_busy, n_wait),
                  UVM_LOW)

        run_gap_phase    (n_gap,  base_addr);
        run_busy_phase   (n_busy, base_addr + n_gap  * SLOT_SIZE);
        run_in_wait_phase(n_wait, base_addr + (n_gap + n_busy) * SLOT_SIZE);

        `uvm_info(get_type_name(),
                  $sformatf("IDLE traffic done: pairs=%0d gaps=%0d idle_cycles_requested=%0d longest=%0d beats=%0d mismatch=%0d",
                            num_iter, num_gaps, num_gap_cycles, longest_gap,
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)

        for (int unsigned p = 0; p < NUM_PHASES; p++) begin
            `uvm_info(get_type_name(),
                      $sformatf("  phase %0d -> %0d pairs", p, iter_per_phase[p]),
                      UVM_MEDIUM)
        end
    endtask : body

    //-------------------------------------------------------------------------
    // Phase 1 - zero-wait traffic with an IDLE run before the write, between
    // the write and its read-back, and after the read-back. Every IDLE here is
    // accepted on the cycle it is presented, which is the transfer AHB_TRN_001
    // and AHB_TRN_006 are about
    //-------------------------------------------------------------------------
    task run_gap_phase(int unsigned n, bit [AHB_ADDR_WIDTH-1:0] base);
        ahb_transaction          wr, rd;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        bit                      ok;

        apply_window(0, 0);     // zero wait: HTRANS is the only variable

        for (int unsigned i = 0; i < n; i++) begin
            slot = base + i * SLOT_SIZE;
            iter_per_phase[0]++;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR,
                                  AHB_BURST_INCR4,  AHB_BURST_INCR8,
                                  AHB_BURST_WRAP4,  AHB_BURST_WRAP8};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                    // No BUSY - phase 2 owns that
                    foreach (busy_cycles[k]) busy_cycles[k] == 0;
                    trailing_busy_cycles == 0;

                    // inside range bounds addr so the span sum cannot wrap
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                   AHB_BURST_INCR8}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Gap-phase randomization failed @slot 0x%08h", slot))

            rd = build_read_back(wr);

            // Three IDLE runs per pair: before, between and after. The one
            // between the write and the read is the interesting one - the read
            // must still return what the write committed across it
            idle_gap(random_gap());
            send_and_wait(wr, ok);
            if (!ok) continue;

            idle_gap(random_gap());
            send_and_wait(rd, ok);
            if (!ok) continue;

            idle_gap(random_gap());

            `uvm_info(get_type_name(),
                      $sformatf("[gap] %s %s @0x%08h, %0d beats",
                                wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats), UVM_MEDIUM)

            compare_burst(wr, rd);
        end
    endtask : run_gap_phase

    //-------------------------------------------------------------------------
    // Phase 2 - the same IDLE runs, but the bursts now stall on BUSY as well.
    // IDLE and BUSY must both come back zero-wait OKAY (AHB_WAI_010), and no
    // BUSY may appear after an accepted IDLE (AHB_TRN_006)
    //-------------------------------------------------------------------------
    task run_busy_phase(int unsigned n, bit [AHB_ADDR_WIDTH-1:0] base);
        ahb_transaction          wr, rd;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        bit                      ok;

        apply_window(0, 2);     // BUSY answered zero-wait even when beats wait

        for (int unsigned i = 0; i < n; i++) begin
            slot = base + i * SLOT_SIZE;
            iter_per_phase[1]++;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    // Multi-beat only: SINGLE has no inter-beat gap to stall in
                    burst inside {AHB_BURST_INCR,  AHB_BURST_INCR4,
                                  AHB_BURST_INCR8, AHB_BURST_WRAP4,
                                  AHB_BURST_WRAP8};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                    // A BUSY run before every beat except the first
                    foreach (busy_cycles[k]) {
                        if (k > 0) busy_cycles[k] inside {[1:2]};
                        else       busy_cycles[k] == 0;
                    }

                    // Ending out of BUSY belongs to the undefined-burst test
                    trailing_busy_cycles == 0;

                    // inside range bounds addr so the span sum cannot wrap
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                   AHB_BURST_INCR8}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Busy-phase randomization failed @slot 0x%08h", slot))

            rd = build_read_back(wr);

            idle_gap(random_gap());
            send_and_wait(wr, ok);
            if (!ok) continue;

            idle_gap(random_gap());
            send_and_wait(rd, ok);
            if (!ok) continue;

            `uvm_info(get_type_name(),
                      $sformatf("[busy] %s %s @0x%08h, %0d beats",
                                wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats), UVM_MEDIUM)

            compare_burst(wr, rd);
        end
    endtask : run_busy_phase

    //-------------------------------------------------------------------------
    // Phase 3 - IDLE inside a wait state. The pair is queued together, so the
    // driver holds the read while the write is still on the bus. With
    // en_idle_to_nonseq_in_wait the pipelined slot opens as IDLE rather than
    // taking the read straight away, and the slave always waits, so that IDLE
    // is presented with HREADY low. Upgrading it to the read's NONSEQ then
    // moves HADDR off the write's last beat while the wait is still running -
    // the address change of AHB_WAI_007. Multi-beat bursts only: on a SINGLE
    // the read-back address equals the write address and HADDR would not move
    //-------------------------------------------------------------------------
    task run_in_wait_phase(int unsigned n, bit [AHB_ADDR_WIDTH-1:0] base);
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;

        apply_window(1, 3);     // every beat waited, so the slot always idles

        for (int unsigned i = 0; i < n; i++) begin
            slot = base + i * SLOT_SIZE;
            iter_per_phase[2]++;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst inside {AHB_BURST_INCR,  AHB_BURST_INCR4,
                                  AHB_BURST_INCR8, AHB_BURST_WRAP4,
                                  AHB_BURST_WRAP8};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[2:8]});

                    // No BUSY - a master stall would blur the slot under test
                    foreach (busy_cycles[k]) busy_cycles[k] == 0;
                    trailing_busy_cycles == 0;

                    // inside range bounds addr so the span sum cannot wrap
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                   AHB_BURST_INCR8}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("In-wait-phase randomization failed @slot 0x%08h", slot))

            `uvm_info(get_type_name(),
                      $sformatf("[in-wait] %s %s @0x%08h, %0d beats",
                                wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats), UVM_MEDIUM)

            write_read_burst(wr, 1'b1);

            // Back to a quiet bus before the next pair is queued
            idle_gap(random_gap());
        end
    endtask : run_in_wait_phase

endclass : ahb_idle_seq

`endif // AHB_IDLE_SEQ_INCLUDED_
