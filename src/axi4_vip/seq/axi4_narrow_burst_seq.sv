//==============================================================================
// File        : axi4_narrow_burst_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Narrow Burst Transfer Demo Sequence.
//               Generates transactions where transfer size (AxSIZE) is smaller
//               than the data bus width - known as "narrow transfers" in AXI4.
//               Only 4 transactions: 1B-write, 1B-read, 2B-write, 2B-read
//               on a 32-bit (4B) bus.
//               Ideal for waveform capture showing partial byte-lane usage.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_NARROW_BURST_SEQ_INCLUDED_
`define AXI4_NARROW_BURST_SEQ_INCLUDED_

class axi4_narrow_burst_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_narrow_burst_seq)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_narrow_burst_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - send narrow write/read pairs at 1B and 2B sizes
    // =========================================================================
    virtual task body();
        axi4_transaction tr;

        `uvm_info(get_type_name(),
                  "Starting narrow burst demo sequence (4 transactions)",
                  UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Transaction 1: 1-byte WRITE (SIZE=1B on 32-bit bus)
        //   Each beat transfers only 1 byte. On waveform WSTRB shows
        //   only one active byte lane per beat, rotating through lanes.
        // -----------------------------------------------------------------
        tr = axi4_transaction::type_id::create("narrow_1b_wr_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_4000;
            len   == 3;              // 4-beat burst
            size  == AXI4_SIZE_1B;   // 1 byte per transfer (narrow)
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h4;
        }) `uvm_fatal(get_type_name(), "Randomization failed for 1B narrow write")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("TX1 [1B-WRITE] done: ADDR=0x%08h LEN=%0d",
                            tr.addr, tr.len), UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Transaction 2: 1-byte READ (SIZE=1B)
        //   Read-back from same address. On waveform RDATA shows valid
        //   data on only one byte lane per beat.
        // -----------------------------------------------------------------
        tr = axi4_transaction::type_id::create("narrow_1b_rd_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_4000;
            len   == 3;
            size  == AXI4_SIZE_1B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h4;
        }) `uvm_fatal(get_type_name(), "Randomization failed for 1B narrow read")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("TX2 [1B-READ] done: ADDR=0x%08h LEN=%0d",
                            tr.addr, tr.len), UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Transaction 3: 2-byte WRITE (SIZE=2B on 32-bit bus)
        //   Each beat transfers a half-word. WSTRB alternates between
        //   lower half-word (2'b0011) and upper half-word (2'b1100).
        // -----------------------------------------------------------------
        tr = axi4_transaction::type_id::create("narrow_2b_wr_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_5000;
            len   == 3;              // 4-beat burst
            size  == AXI4_SIZE_2B;   // 2 bytes per transfer (narrow)
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h5;
        }) `uvm_fatal(get_type_name(), "Randomization failed for 2B narrow write")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("TX3 [2B-WRITE] done: ADDR=0x%08h LEN=%0d",
                            tr.addr, tr.len), UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Transaction 4: 2-byte READ (SIZE=2B)
        //   Read-back from same address to verify narrow access integrity.
        // -----------------------------------------------------------------
        tr = axi4_transaction::type_id::create("narrow_2b_rd_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_5000;
            len   == 3;
            size  == AXI4_SIZE_2B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h5;
        }) `uvm_fatal(get_type_name(), "Randomization failed for 2B narrow read")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("TX4 [2B-READ] done: ADDR=0x%08h LEN=%0d",
                            tr.addr, tr.len), UVM_MEDIUM)

        `uvm_info(get_type_name(),
                  "Narrow burst demo complete (4/4 transactions sent)",
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_narrow_burst_seq

`endif // AXI4_NARROW_BURST_SEQ_INCLUDED_