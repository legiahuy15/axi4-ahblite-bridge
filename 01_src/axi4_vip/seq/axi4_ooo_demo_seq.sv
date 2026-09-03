//==============================================================================
// File        : axi4_ooo_demo_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Out-of-order demo sequence for waveform capture.
//               Fires exactly 6 SINGLE-BEAT reads with distinct IDs (0..5) to
//               fixed addresses, back-to-back (no wait between), so all six
//               are outstanding together. With a reorder-enabled slave the R
//               responses return out of order (RID order != ARID order), while
//               each burst stays non-interleaved. Six in-flight reads make an
//               accidental in-order return negligibly unlikely on any seed.
//               Minimal, deterministic, compact - ideal for report waveforms.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_OOO_DEMO_SEQ_INCLUDED_
`define AXI4_OOO_DEMO_SEQ_INCLUDED_

class axi4_ooo_demo_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_ooo_demo_seq)

    function new(string name = "axi4_ooo_demo_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        `uvm_info(get_type_name(),
                  "Starting OOO demo sequence (6 single-beat reads, IDs 0-5)",
                  UVM_MEDIUM)

        // One thread per read: each waits on its OWN done_event immediately
        // after finish_item (same-thread, no event-race). All six are
        // outstanding together, so the reorder-enabled slave returns their
        // R responses out of order.
        for (int i = 0; i < 6; i++) begin
            automatic int idx = i;
            fork
                begin
                    axi4_transaction tr;
                    tr = axi4_transaction::type_id::create($sformatf("ooo_rd_%0d", idx));
                    start_item(tr);
                    if (!tr.randomize() with {
                        dir   == AXI4_READ;
                        addr  == 32'h0000_1000 + (idx * 32'h100);  // 0x1000..0x1500
                        id    == idx[3:0];                         // distinct IDs 0..5
                        len   == 0;                                // single beat
                        size  == AXI4_SIZE_4B;
                        burst == AXI4_BURST_INCR;
                        lock  == AXI4_LOCK_NORMAL;
                    }) `uvm_fatal(get_type_name(),
                                  $sformatf("Randomization failed for OOO demo read #%0d", idx))
                    finish_item(tr);
                    wait(tr.done_event.ev.triggered);   // wait in-thread -> no race
                end
            join_none
        end

        wait fork;   // all six reads have returned (possibly out of order)

        `uvm_info(get_type_name(),
                  "OOO demo sequence complete (6/6 reads returned)", UVM_MEDIUM)
    endtask : body

endclass : axi4_ooo_demo_seq

`endif // AXI4_OOO_DEMO_SEQ_INCLUDED_
