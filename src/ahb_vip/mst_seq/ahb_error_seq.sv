//=============================================================================
// File        : ahb_error_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Master traffic for the ERROR response test. Walks every burst
//               type with abort_on_error alternating between cancel and
//               continue, while the slave sequence injects ERROR responses.
//               Writes and reads use disjoint address regions so the
//               scoreboard reference memory never checks read data that the
//               slave sequence made up.
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_ERROR_SEQ_INCLUDED_
`define AHB_ERROR_SEQ_INCLUDED_

class ahb_error_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_error_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 16;

    // Disjoint: in sequence mode the slave answers reads from the response
    // item, not its memory model, so reads target a never-written region where
    // the scoreboard reference memory skips the beat
    bit [AHB_ADDR_WIDTH-1:0] wr_base = 32'h0000_7000;
    bit [AHB_ADDR_WIDTH-1:0] rd_base = 32'h0000_8000;

    // Region the slave sequence answers as a default slave would: every beat
    // returns ERROR, so the reference memory skips the whole burst
    bit [AHB_ADDR_WIDTH-1:0] unmapped_base = 32'h0000_9000;

    localparam int unsigned SLOT_SIZE = 64;   // 16 beats x 4 bytes

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned num_bursts;
    int unsigned num_with_error;     // bursts that saw at least one ERROR beat
    int unsigned num_cancelled;      // of those, the ones told to cancel
    int unsigned num_unmapped;       // bursts aimed at the unmapped region

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_error_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - alternate direction and ERROR policy across every burst type
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          tr;
        ahb_dir_e                dir;
        bit                      cancel;
        bit                      unmapped;
        bit                      move_addr;
        bit                      addr_toggle;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        bit                      ok;
        int                      err_beat;
        int unsigned             exp_beats;

        `uvm_info(get_type_name(),
                  $sformatf("Starting ERROR response traffic: %0d bursts", num_iter), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            dir    = ((i % 2) == 0) ? AHB_WRITE : AHB_READ;
            cancel = (((i / 2) % 2) == 0);      // alternate on a longer period

            // Only a cancelling burst may move its address; alternate so the
            // address-held case is covered too
            move_addr = 1'b0;
            if (cancel) begin
                move_addr   = addr_toggle;
                addr_toggle = !addr_toggle;
            end

            // Period 3 keeps unmapped bursts out of step with the direction
            // and policy patterns, so both combinations reach the region
            unmapped = ((i % 3) == 2);
            if (unmapped) begin
                slot = unmapped_base + (i / 3) * SLOT_SIZE;
                num_unmapped++;
            end else begin
                slot = ((dir == AHB_WRITE) ? wr_base : rd_base) + (i / 2) * SLOT_SIZE;
            end

            tr = ahb_transaction::type_id::create("tr");
            if (!tr.randomize() with {
                    write == dir;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    // Cap INCR so an undefined-length burst fits the slot
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[1:16]});
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    addr + num_beats * (1 << size) <= slot + SLOT_SIZE;
                    abort_on_error       == cancel;
                    addr_change_on_error == move_addr;
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Randomization failed @slot 0x%08h", slot))

            send_and_wait(tr, ok);
            if (!ok) continue;                  // reset flush

            num_bursts++;

            // resp[] holds only completed beats, so the first ERROR marks
            // where a cancelling burst stopped
            err_beat = -1;
            foreach (tr.resp[k]) begin
                if (tr.resp[k] == AHB_RESP_ERROR) begin
                    err_beat = k;
                    break;
                end
            end

            if (err_beat >= 0) begin
                num_with_error++;
                if (tr.abort_on_error) num_cancelled++;
                `uvm_info(get_type_name(),
                          $sformatf("%s %s @0x%08h: ERROR on beat %0d of %0d, policy=%s, drove %0d",
                                    tr.write.name(), tr.burst.name(), tr.addr,
                                    err_beat, tr.get_num_beats(),
                                    tr.abort_on_error ? "cancel" : "continue",
                                    tr.beats_done),
                          UVM_MEDIUM)
            end

            // Cancel stops on the ERROR beat; continue (and any error-free
            // burst) drives every beat
            exp_beats = (err_beat >= 0 && tr.abort_on_error)
                        ? (err_beat + 1) : tr.get_num_beats();

            if (tr.beats_done != exp_beats)
                `uvm_error(get_type_name(),
                           $sformatf("%s %s @0x%08h (%s): drove %0d beats, expected %0d (first ERROR beat %0d of %0d)",
                                     tr.write.name(), tr.burst.name(), tr.addr,
                                     tr.abort_on_error ? "cancel" : "continue",
                                     tr.beats_done, exp_beats,
                                     err_beat, tr.get_num_beats()))
        end

        `uvm_info(get_type_name(),
                  $sformatf("ERROR response traffic done: bursts=%0d with_error=%0d cancelled=%0d unmapped=%0d",
                            num_bursts, num_with_error, num_cancelled, num_unmapped), UVM_LOW)

        if (num_with_error == 0)
            `uvm_error(get_type_name(),
                       "No ERROR response was observed - the slave error sequence did not run")
    endtask : body

endclass : ahb_error_seq

`endif // AHB_ERROR_SEQ_INCLUDED_
