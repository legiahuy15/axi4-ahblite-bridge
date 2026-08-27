//=============================================================================
// File        : ahb_wrap_burst_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Wrapping bursts (WRAP4, WRAP8, WRAP16) over every legal size,
//               with start addresses both on and inside the wrap boundary.
//               Each iteration writes one burst and reads it back beat for
//               beat at the same address.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_WRAP_BURST_SEQ_INCLUDED_
`define AHB_WRAP_BURST_SEQ_INCLUDED_

class ahb_wrap_burst_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_wrap_burst_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 16;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_4000;

    // Slot holds the largest wrap region issued here (16 beats x 4 bytes). A
    // wrap region is a power of two and naturally aligned, so any region
    // containing an address in this slot lies wholly inside it - the start
    // address randomizes freely without aliasing the next slot
    localparam int unsigned SLOT_SIZE = 64;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_wrap_burst_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (WRAP write burst, WRAP read burst, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;

        `uvm_info(get_type_name(),
                  $sformatf("Starting WRAP bursts: %0d iterations from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            wr = ahb_transaction::type_id::create("wr");
            // Free offset inside the slot: start addresses land both on the
            // wrap boundary and part way through the region
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst inside {AHB_BURST_WRAP4, AHB_BURST_WRAP8, AHB_BURST_WRAP16};
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Write randomization failed @slot 0x%08h", slot))

            write_read_burst(wr);
        end

        `uvm_info(get_type_name(),
                  $sformatf("WRAP bursts done: beats=%0d mismatch=%0d",
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_wrap_burst_seq

`endif // AHB_WRAP_BURST_SEQ_INCLUDED_