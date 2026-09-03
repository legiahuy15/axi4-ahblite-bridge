//==============================================================================
// File        : axi4_all_burst_type_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : All Burst Types Demo Sequence.
//               Generates one write + one read for each AXI4 burst type:
//               FIXED, INCR, and WRAP. Total of 6 transactions.
//               Uses identical burst length (4 beats) across all three so
//               waveform comparison of address behaviour is straightforward.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_ALL_BURST_TYPE_SEQ_INCLUDED_
`define AXI4_ALL_BURST_TYPE_SEQ_INCLUDED_

class axi4_all_burst_type_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_all_burst_type_seq)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_all_burst_type_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - one write+read pair per burst type
    // =========================================================================
    virtual task body();
        axi4_transaction wr_tr, rd_tr;

        `uvm_info(get_type_name(),
                  "Starting all burst types demo (FIXED, INCR, WRAP × Write+Read = 6 txns)",
                  UVM_MEDIUM)

        // =================================================================
        // Pair 1: FIXED burst (address stays the same for all beats)
        //   Typical use: FIFO access.
        //   On waveform: AWADDR/ARADDR constant across beats.
        // =================================================================
        wr_tr = axi4_transaction::type_id::create("fixed_wr_tr");
        start_item(wr_tr);
        if (!wr_tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_6000;
            len   == 3;              // 4 beats
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_FIXED;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h6;
            foreach (strb[i]) strb[i] == 4'b1111;
        }) `uvm_fatal(get_type_name(), "Randomization failed for FIXED write")
        finish_item(wr_tr);
        wait(wr_tr.done_event.ev.triggered);

        rd_tr = axi4_transaction::type_id::create("fixed_rd_tr");
        start_item(rd_tr);
        if (!rd_tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_6000;
            len   == 3;
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_FIXED;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h6;
        }) `uvm_fatal(get_type_name(), "Randomization failed for FIXED read")
        finish_item(rd_tr);
        wait(rd_tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("FIXED pair done: ADDR=0x%08h BRESP=%s",
                            wr_tr.addr, wr_tr.resp.name()), UVM_MEDIUM)

        // =================================================================
        // Pair 2: INCR burst (address increments by transfer size each beat)
        //   Most common burst type in practice.
        //   On waveform: address increments by 4 each beat (SIZE=4B).
        // =================================================================
        wr_tr = axi4_transaction::type_id::create("incr_wr_tr");
        start_item(wr_tr);
        if (!wr_tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_7000;
            len   == 3;              // 4 beats
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h7;
            foreach (strb[i]) strb[i] == 4'b1111;
        }) `uvm_fatal(get_type_name(), "Randomization failed for INCR write")
        finish_item(wr_tr);
        wait(wr_tr.done_event.ev.triggered);

        rd_tr = axi4_transaction::type_id::create("incr_rd_tr");
        start_item(rd_tr);
        if (!rd_tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_7000;
            len   == 3;
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h7;
        }) `uvm_fatal(get_type_name(), "Randomization failed for INCR read")
        finish_item(rd_tr);
        wait(rd_tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("INCR pair done: ADDR=0x%08h BRESP=%s",
                            wr_tr.addr, wr_tr.resp.name()), UVM_MEDIUM)

        // =================================================================
        // Pair 3: WRAP burst (address wraps at boundary)
        //   Typical use: cache-line fills.
        //   On waveform: address wraps around at (len+1)×size boundary.
        //   Start address must be aligned to transfer size.
        // =================================================================
        wr_tr = axi4_transaction::type_id::create("wrap_wr_tr");
        start_item(wr_tr);
        if (!wr_tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_8004;    // Aligned to 4B, mid-wrap boundary
            len   == 3;                // 4 beats (valid for WRAP)
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_WRAP;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h8;
            foreach (strb[i]) strb[i] == 4'b1111;
        }) `uvm_fatal(get_type_name(), "Randomization failed for WRAP write")
        finish_item(wr_tr);
        wait(wr_tr.done_event.ev.triggered);

        rd_tr = axi4_transaction::type_id::create("wrap_rd_tr");
        start_item(rd_tr);
        if (!rd_tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_8004;
            len   == 3;
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_WRAP;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h8;
        }) `uvm_fatal(get_type_name(), "Randomization failed for WRAP read")
        finish_item(rd_tr);
        wait(rd_tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("WRAP pair done: ADDR=0x%08h BRESP=%s",
                            wr_tr.addr, wr_tr.resp.name()), UVM_MEDIUM)

        `uvm_info(get_type_name(),
                  "All burst types demo complete (6/6 transactions sent)",
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_all_burst_type_seq

`endif // AXI4_ALL_BURST_TYPE_SEQ_INCLUDED_