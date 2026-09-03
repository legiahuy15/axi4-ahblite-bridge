//=============================================================================
// File        : ahb_single_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Randomized SINGLE transfers over every legal size, address
//               alignment and direction. Each iteration writes one beat and
//               reads it back at the same address.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_SINGLE_SEQ_INCLUDED_
`define AHB_SINGLE_SEQ_INCLUDED_

class ahb_single_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_single_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    int unsigned num_iter = 20;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_2000;

    // One word-sized slot per iteration, at a random aligned offset so narrow
    // transfers hit every byte lane. Slots are never reused, so transfers of
    // different sizes cannot alias in the scoreboard reference memory
    localparam int unsigned SLOT_SIZE = 4;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_single_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (SINGLE write, SINGLE read-back, compare)
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;

        `uvm_info(get_type_name(),
                  $sformatf("Starting SINGLE transfers: %0d iterations from 0x%08h",
                            num_iter, base_addr), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            wr = ahb_transaction::type_id::create("wr");
            // c_addr_align pairs a legal offset with the chosen size
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    burst == AHB_BURST_SINGLE;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Write randomization failed @slot 0x%08h", slot))

            write_read_burst(wr);
        end

        `uvm_info(get_type_name(),
                  $sformatf("SINGLE transfers done: beats=%0d mismatch=%0d",
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_single_seq

`endif // AHB_SINGLE_SEQ_INCLUDED_