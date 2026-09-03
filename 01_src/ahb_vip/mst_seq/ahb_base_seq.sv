//=============================================================================
// File        : ahb_base_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Base master sequence. Provides the send-and-wait helper that
//               all AHB-Lite master sequences use, plus a write/read-back
//               burst check shared by the burst sequences.
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_BASE_SEQ_INCLUDED_
`define AHB_BASE_SEQ_INCLUDED_

class ahb_base_seq extends uvm_sequence #(ahb_transaction);

    `uvm_object_utils(ahb_base_seq)

    //-------------------------------------------------------------------------
    // Beat-level statistics, accumulated by write_read_burst()
    //-------------------------------------------------------------------------
    int unsigned beats_checked;
    int unsigned beats_mismatch;

    //-------------------------------------------------------------------------
    // Set by a sequence that provokes resets on purpose: a flushed transaction
    // is then logged as info instead of a warning
    //-------------------------------------------------------------------------
    bit expect_reset_abort = 1'b0;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_base_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // send_and_wait - send one item and block until the transfer finishes.
    // The driver is pipelined: finish_item() returns early, rdata[]/resp[] are
    // valid only after tr.done. ok = 0 when a reset flushed the item
    //-------------------------------------------------------------------------
    virtual task send_and_wait(ahb_transaction tr, output bit ok);
        queue_item(tr);
        // Level-sensitive: passes immediately if already completed
        wait (tr.done);
        ok = !tr.aborted;
        if (!ok) begin
            if (expect_reset_abort)
                `uvm_info(get_type_name(),
                          $sformatf("Transaction aborted by reset: %s 0x%08h",
                                    tr.write.name(), tr.addr), UVM_MEDIUM)
            else
                `uvm_warning(get_type_name(),
                             $sformatf("Transaction aborted by reset: %s 0x%08h",
                                       tr.write.name(), tr.addr))
        end
    endtask : send_and_wait

    //-------------------------------------------------------------------------
    // queue_item - hand one item to the driver without blocking, so a caller
    // can stack transactions and let the driver run them back to back
    //-------------------------------------------------------------------------
    virtual task queue_item(ahb_transaction tr);
        start_item(tr);
        // Arm before the item reaches the driver
        tr.done    = 1'b0;
        tr.aborted = 1'b0;
        finish_item(tr);
    endtask : queue_item

    //-------------------------------------------------------------------------
    // beat_address - address of beat i (INCR increment / WRAP). Mirrors the
    // scoreboard
    //-------------------------------------------------------------------------
    function bit [AHB_ADDR_WIDTH-1:0] beat_address(ahb_transaction tr, int i);
        int unsigned bytes = 1 << tr.size;
        int unsigned len   = tr.get_num_beats();
        int unsigned wrap_bytes;
        bit [AHB_ADDR_WIDTH-1:0] base;

        case (tr.burst)
            AHB_BURST_WRAP4, AHB_BURST_WRAP8, AHB_BURST_WRAP16: begin
                wrap_bytes = len * bytes;
                base       = tr.addr - (tr.addr % wrap_bytes);
                return base + ((tr.addr + i * bytes) % wrap_bytes);
            end
            default: return tr.addr + i * bytes;
        endcase
    endfunction : beat_address

    //-------------------------------------------------------------------------
    // build_read_back - a READ transfer carrying the same control as wr, so the
    // burst can be read back beat for beat
    //-------------------------------------------------------------------------
    virtual function ahb_transaction build_read_back(ahb_transaction wr);
        ahb_transaction rd;

        rd = ahb_transaction::type_id::create("rd");
        if (!rd.randomize() with {
                write     == AHB_READ;
                burst     == wr.burst;
                size      == wr.size;
                addr      == wr.addr;
                num_beats == wr.num_beats;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Read randomization failed (%s @0x%08h)",
                                 wr.burst.name(), wr.addr))
        return rd;
    endfunction : build_read_back

    //-------------------------------------------------------------------------
    // compare_burst - check a completed read-back against the write that
    // produced it. Only the active byte lanes are compared; a narrow transfer
    // leaves the rest undefined. Both transfers must be done and not aborted
    //-------------------------------------------------------------------------
    virtual function void compare_burst(ahb_transaction wr, ahb_transaction rd);
        bit [AHB_ADDR_WIDTH-1:0] a;
        int unsigned             bytes;
        int unsigned             lane;
        bit [7:0]                exp_b, got_b;
        bit                      beat_bad;

        bytes = 1 << wr.size;
        foreach (rd.rdata[k]) begin
            a        = beat_address(rd, k);
            lane     = a % (AHB_DATA_WIDTH / 8);
            beat_bad = 0;
            beats_checked++;

            // No ERROR is requested here, so any non-OKAY is a failure
            if (wr.resp[k] != AHB_RESP_OKAY || rd.resp[k] != AHB_RESP_OKAY) begin
                beats_mismatch++;
                `uvm_error(get_type_name(),
                           $sformatf("%s %s beat %0d @0x%08h: unexpected response (wr=%s rd=%s)",
                                     wr.burst.name(), wr.size.name(), k, a,
                                     wr.resp[k].name(), rd.resp[k].name()))
                continue;
            end

            for (int b = 0; b < bytes; b++) begin
                exp_b = wr.wdata[k][(lane + b)*8 +: 8];
                got_b = rd.rdata[k][(lane + b)*8 +: 8];
                if (got_b !== exp_b) begin
                    beat_bad = 1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s %s beat %0d @0x%08h byte %0d: wrote 0x%02h, read 0x%02h",
                                         wr.burst.name(), wr.size.name(), k, a, b, exp_b, got_b))
                end
            end

            if (beat_bad) begin
                beats_mismatch++;
            end else begin
                `uvm_info(get_type_name(),
                          $sformatf("%s %s beat %0d @0x%08h ok",
                                    wr.burst.name(), wr.size.name(), k, a), UVM_HIGH)
            end
        end
    endfunction : compare_burst

    //-------------------------------------------------------------------------
    // write_read_burst - send a randomized write burst, read it back with
    // identical control and compare every beat.
    // pipelined = 1 queues both transfers before waiting (AHB is in order, so
    // the read still returns what the write committed)
    //-------------------------------------------------------------------------
    virtual task write_read_burst(ahb_transaction wr, bit pipelined = 0);
        ahb_transaction rd;
        bit             ok;

        // Built up front - pipelined mode queues it while the write is still
        // on the bus
        rd = build_read_back(wr);

        if (pipelined) begin
            queue_item(wr);
            queue_item(rd);
            wait (wr.done);
            wait (rd.done);
            if (wr.aborted || rd.aborted) begin
                if (expect_reset_abort)
                    `uvm_info(get_type_name(),
                              $sformatf("Pipelined pair aborted by reset: %s 0x%08h",
                                        wr.burst.name(), wr.addr), UVM_MEDIUM)
                else
                    `uvm_warning(get_type_name(),
                                 $sformatf("Pipelined pair aborted by reset: %s 0x%08h",
                                           wr.burst.name(), wr.addr))
                return;
            end
        end else begin
            send_and_wait(wr, ok);
            if (!ok) return;                // reset flush - skip the pair
            send_and_wait(rd, ok);
            if (!ok) return;
        end

        compare_burst(wr, rd);
    endtask : write_read_burst

endclass : ahb_base_seq

`endif // AHB_BASE_SEQ_INCLUDED_