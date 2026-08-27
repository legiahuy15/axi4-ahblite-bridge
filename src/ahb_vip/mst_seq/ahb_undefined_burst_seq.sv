//=============================================================================
// File        : ahb_undefined_burst_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Undefined-length INCR bursts from 1 to 256 beats, with BUSY
//               inserted mid-burst and, on half the iterations, trailing BUSY
//               so the burst ends out of a BUSY transfer.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_UNDEFINED_BURST_SEQ_INCLUDED_
`define AHB_UNDEFINED_BURST_SEQ_INCLUDED_

class ahb_undefined_burst_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_undefined_burst_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 8;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_5000;

    // A 256-beat word burst spans a full 1KB, so the slot is 1KB and 1KB
    // aligned: the burst always fits and never crosses a page boundary
    localparam int unsigned SLOT_SIZE = 1024;

    // BUSY inserted before every Nth beat. Sparse - a BUSY run on every beat
    // of a 256-beat burst would dominate the runtime
    localparam int unsigned BUSY_EVERY = 8;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_undefined_burst_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (INCR write burst, INCR read burst, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        int unsigned             pin_beats;
        bit                      want_trailing;
        bit                      want_retract;
        bit                      want_pipeline;
        bit                      pipe_toggle;

        `uvm_info(get_type_name(),
                  $sformatf("Starting undefined-length INCR bursts: %0d iterations from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            // Pin both ends of the legal length range so every run covers them
            case (i)
                0:       pin_beats = 1;
                1:       pin_beats = 256;
                default: pin_beats = 0;     // free length
            endcase

            // Every other burst ends out of a BUSY transfer - legal for
            // undefined-length bursts only
            want_trailing = ((i % 2) == 1);

            // Different period than the trailing BUSY, so all four combinations
            // occur. Retraction withdraws a waited BUSY for SEQ (mid-burst) or
            // IDLE/NONSEQ (end of burst); without it the BUSY is only held
            want_retract = (((i / 2) % 2) == 1);

            // A retracted trailing BUSY hands its slot to the queued transfer
            // (NONSEQ) or closes with IDLE. Alternate pipelining across those
            // bursts to produce both endings
            want_pipeline = 1'b0;
            if (want_trailing && want_retract) begin
                want_pipeline = pipe_toggle;
                pipe_toggle   = !pipe_toggle;
            end

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst == AHB_BURST_INCR;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};

                    // Pinned at the extremes, else a moderate range
                    (pin_beats != 0) -> (num_beats == pin_beats);
                    (pin_beats == 0) -> (num_beats inside {[2:64]});

                    // Burst fits inside its own 1KB slot. The inside range
                    // bounds addr; without it the solver can satisfy the span
                    // constraint by letting addr + span wrap past 32 bits
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    addr + num_beats * (1 << size) <= slot + SLOT_SIZE;

                    // BUSY between beats, and trailing BUSY on demand
                    foreach (busy_cycles[k]) {
                        if (k > 0 && (k % BUSY_EVERY) == 0) busy_cycles[k] inside {[1:2]};
                        else                                busy_cycles[k] == 0;
                    }
                    want_trailing  -> (trailing_busy_cycles inside {[1:3]});
                    !want_trailing -> (trailing_busy_cycles == 0);

                    busy_retract_in_wait == want_retract;
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Write randomization failed @slot 0x%08h", slot))

            `uvm_info(get_type_name(),
                      $sformatf("INCR %0d beats, %s @0x%08h, trailing_busy=%0d, retract=%0b, pipelined=%0b",
                                wr.num_beats, wr.size.name(), wr.addr,
                                wr.trailing_busy_cycles, wr.busy_retract_in_wait,
                                want_pipeline),
                      UVM_MEDIUM)

            write_read_burst(wr, want_pipeline);
        end

        `uvm_info(get_type_name(),
                  $sformatf("Undefined-length INCR bursts done: beats=%0d mismatch=%0d",
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_undefined_burst_seq

`endif // AHB_UNDEFINED_BURST_SEQ_INCLUDED_
