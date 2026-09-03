//=============================================================================
// File        : ahb_busy_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : BUSY insertion sequence. Puts a BUSY run before every beat of
//               fixed-length and undefined-length bursts, and on some of them
//               withdraws the BUSY for SEQ while the previous data phase is
//               still waited. No burst ever ends out of a BUSY transfer.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_BUSY_SEQ_INCLUDED_
`define AHB_BUSY_SEQ_INCLUDED_

class ahb_busy_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_busy_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 16;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_C000;

    localparam int unsigned SLOT_SIZE = 64;   // 16 beats x 4 bytes

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned num_fixed;      // fixed-length bursts issued
    int unsigned num_undef;      // undefined-length bursts issued
    int unsigned num_retract;    // bursts allowed to withdraw a waited BUSY

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_busy_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (burst with BUSY, read-back, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        bit                      fixed_len;
        bit                      retract;

        `uvm_info(get_type_name(),
                  $sformatf("Starting BUSY traffic: %0d bursts from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            // 3 of every 4 bursts fixed length - the case
            // BUSY_FIXED_LEN_NO_TERMINATE and AHB_WAI_005 apply to
            fixed_len = ((i % 4) != 3);

            // Longer period, so both withdrawn and held BUSY occur for each
            // burst kind
            retract = (((i / 2) % 2) == 1);

            if (fixed_len) num_fixed++; else num_undef++;
            if (retract)   num_retract++;

            wr = ahb_transaction::type_id::create("wr");
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};

                    // SINGLE has no inter-beat gap, so it cannot carry BUSY
                    fixed_len  -> (burst inside {AHB_BURST_INCR4,  AHB_BURST_INCR8,
                                                 AHB_BURST_INCR16, AHB_BURST_WRAP4,
                                                 AHB_BURST_WRAP8,  AHB_BURST_WRAP16});
                    !fixed_len -> (burst == AHB_BURST_INCR && num_beats inside {[2:16]});

                    // BUSY run before every beat except the first
                    foreach (busy_cycles[k]) {
                        if (k > 0) busy_cycles[k] inside {[1:3]};
                        else       busy_cycles[k] == 0;
                    }

                    // Every burst finishes on a SEQ beat; ending out of BUSY
                    // belongs to the undefined-burst test
                    trailing_busy_cycles == 0;

                    busy_retract_in_wait == retract;

                    // inside range bounds addr so the span sum cannot wrap
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR,  AHB_BURST_INCR4,
                                   AHB_BURST_INCR8, AHB_BURST_INCR16}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Randomization failed @slot 0x%08h", slot))

            `uvm_info(get_type_name(),
                      $sformatf("%s %s @0x%08h, %0d beats, retract=%0b",
                                wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats, wr.busy_retract_in_wait), UVM_MEDIUM)

            write_read_burst(wr);
        end

        `uvm_info(get_type_name(),
                  $sformatf("BUSY traffic done: fixed=%0d undefined=%0d retract=%0d beats=%0d mismatch=%0d",
                            num_fixed, num_undef, num_retract,
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_busy_seq

`endif // AHB_BUSY_SEQ_INCLUDED_
