//==============================================================================
// File        : axi4_illegal_exclusive_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Negative sequence - issues ILLEGAL exclusive accesses to verify
//               the slave flags them per AXI4 spec (A7.2).
//
//               A legal exclusive access must span a power-of-two number of
//               bytes (<=128), use at most 16 beats, and start at an address
//               aligned to the total byte count. The master transaction
//               normally enforces this via constraint `c_exclusive_legal`.
//               This sequence deliberately DISABLES that constraint and drives
//               each of the reachable violation categories (on a 32-bit bus),
//               as both a read and a write:
//                 V1 : non-power-of-two beat count   (3 beats)
//                 V2 : too many beats                (18 beats > 16)
//                 V3 : address not aligned to burst  (8 bytes @ addr%8 != 0)
//
//               `num_illegal` reports how many illegal transactions were sent,
//               so the test can check the slave raised exactly that many errors.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_ILLEGAL_EXCLUSIVE_SEQ_INCLUDED_
`define AXI4_ILLEGAL_EXCLUSIVE_SEQ_INCLUDED_

class axi4_illegal_exclusive_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_illegal_exclusive_seq)

    // Number of illegal exclusive transactions actually sent (set by body()).
    int unsigned num_illegal = 0;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_illegal_exclusive_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // send_illegal - drive one exclusive transaction with illegal parameters.
    //   c_exclusive_legal is disabled so the (otherwise blocked) illegal values
    //   can be built. All other constraints (data/strb sizing, size<=bus) stay
    //   active. INCR burst is used so no unrelated WRAP/FIXED SVA fires.
    // =========================================================================
    task send_illegal(axi4_dir_e   t_dir,
                      bit [7:0]     t_len,
                      axi4_size_e   t_size,
                      bit [AXI4_ADDR_WIDTH-1:0] t_addr,
                      string        tag);
        axi4_transaction tr;
        tr = axi4_transaction::type_id::create("illegal_excl_tr");
        tr.c_exclusive_legal.constraint_mode(0);   // permit illegal exclusive params

        start_item(tr);
        if (!tr.randomize() with {
            dir   == t_dir;
            lock  == AXI4_LOCK_EXCLUSIVE;
            burst == AXI4_BURST_INCR;
            size  == t_size;
            len   == t_len;
            addr  == t_addr;
        }) `uvm_fatal(get_type_name(),
                      $sformatf("Randomization failed for illegal exclusive (%s)", tag))
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        num_illegal++;
        `uvm_info(get_type_name(),
                  $sformatf("Sent illegal exclusive %s [%s]: ADDR=0x%08h SIZE=%0d LEN=%0d (expect slave UVM_ERROR)",
                            t_dir.name(), tag, t_addr, t_size, t_len),
                  UVM_MEDIUM)
    endtask : send_illegal

    // =========================================================================
    // body - send each violation category as a read and as a write.
    // =========================================================================
    virtual task body();
        `uvm_info(get_type_name(),
                  "Starting illegal-exclusive negative sequence (expect slave protocol errors)",
                  UVM_MEDIUM)

        // V1: non-power-of-two beats (3 beats * 4B = 12 bytes, not pow2)
        send_illegal(AXI4_READ,  8'd2, AXI4_SIZE_4B, 32'h0000_1000, "V1_non_pow2_beats");
        send_illegal(AXI4_WRITE, 8'd2, AXI4_SIZE_4B, 32'h0000_1000, "V1_non_pow2_beats");

        // V2: too many beats (18 beats > 16 max for exclusive)
        send_illegal(AXI4_READ,  8'd17, AXI4_SIZE_4B, 32'h0000_2000, "V2_too_many_beats");
        send_illegal(AXI4_WRITE, 8'd17, AXI4_SIZE_4B, 32'h0000_2000, "V2_too_many_beats");

        // V3: address not aligned to total bytes (2 beats * 4B = 8 bytes, addr%8=4)
        send_illegal(AXI4_READ,  8'd1, AXI4_SIZE_4B, 32'h0000_3004, "V3_unaligned");
        send_illegal(AXI4_WRITE, 8'd1, AXI4_SIZE_4B, 32'h0000_3004, "V3_unaligned");

        `uvm_info(get_type_name(),
                  $sformatf("Illegal-exclusive sequence complete: %0d illegal transactions sent",
                            num_illegal),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_illegal_exclusive_seq

`endif // AXI4_ILLEGAL_EXCLUSIVE_SEQ_INCLUDED_