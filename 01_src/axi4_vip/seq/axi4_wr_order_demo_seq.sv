//==============================================================================
// File        : axi4_wr_order_demo_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Write Channel Ordering Demo Sequence.
//               Generates exactly 3 write transactions, one per AW/W ordering
//               mode: PARALLEL, AW_BEFORE_W, and W_BEFORE_AW.
//               Minimal transaction count, ideal for waveform capture and
//               report illustrations.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_WR_ORDER_DEMO_SEQ_INCLUDED_
`define AXI4_WR_ORDER_DEMO_SEQ_INCLUDED_

class axi4_wr_order_demo_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_wr_order_demo_seq)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_wr_order_demo_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - send one transaction per write ordering mode
    // =========================================================================
    virtual task body();
        axi4_transaction tr;

        `uvm_info(get_type_name(),
                  "Starting write channel ordering demo sequence (3 transactions)",
                  UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Transaction 1: AW and W in PARALLEL (default, most common)
        //   AW and W channels fire simultaneously.
        //   On waveform: AWVALID and WVALID assert on the same cycle.
        // -----------------------------------------------------------------
        tr = axi4_transaction::type_id::create("wr_parallel_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir      == AXI4_WRITE;
            wr_order == AXI4_WR_PARALLEL;
            addr     == 32'h0000_1000;
            len      == 3;              // 4-beat burst
            size     == AXI4_SIZE_4B;
            burst    == AXI4_BURST_INCR;
            lock     == AXI4_LOCK_NORMAL;
            id       == 4'h1;
            foreach (strb[i]) strb[i] == 4'b1111;
        }) `uvm_fatal(get_type_name(), "Randomization failed for PARALLEL write")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("TX1 [PARALLEL] done: ADDR=0x%08h LEN=%0d RESP=%s",
                            tr.addr, tr.len, tr.resp.name()),
                  UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Transaction 2: AW_BEFORE_W (address phase completes first)
        //   Master drives AW channel and waits for AWREADY handshake,
        //   then drives W data beats.
        //   On waveform: clear gap between AW handshake and first W beat.
        // -----------------------------------------------------------------
        tr = axi4_transaction::type_id::create("wr_aw_first_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir      == AXI4_WRITE;
            wr_order == AXI4_WR_AW_BEFORE_W;
            addr     == 32'h0000_2000;
            len      == 3;              // 4-beat burst
            size     == AXI4_SIZE_4B;
            burst    == AXI4_BURST_INCR;
            lock     == AXI4_LOCK_NORMAL;
            id       == 4'h2;
            foreach (strb[i]) strb[i] == 4'b1111;
        }) `uvm_fatal(get_type_name(), "Randomization failed for AW_BEFORE_W write")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("TX2 [AW_BEFORE_W] done: ADDR=0x%08h LEN=%0d RESP=%s",
                            tr.addr, tr.len, tr.resp.name()),
                  UVM_MEDIUM)

        // -----------------------------------------------------------------
        // Transaction 3: W_BEFORE_AW (data beats start before address)
        //   Master drives W data first, then sends AW address.
        //   On waveform: WVALID asserts before AWVALID - clearly visible.
        // -----------------------------------------------------------------
        tr = axi4_transaction::type_id::create("wr_w_first_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir      == AXI4_WRITE;
            wr_order == AXI4_WR_W_BEFORE_AW;
            addr     == 32'h0000_3000;
            len      == 3;              // 4-beat burst
            size     == AXI4_SIZE_4B;
            burst    == AXI4_BURST_INCR;
            lock     == AXI4_LOCK_NORMAL;
            id       == 4'h3;
            foreach (strb[i]) strb[i] == 4'b1111;
        }) `uvm_fatal(get_type_name(), "Randomization failed for W_BEFORE_AW write")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("TX3 [W_BEFORE_AW] done: ADDR=0x%08h LEN=%0d RESP=%s",
                            tr.addr, tr.len, tr.resp.name()),
                  UVM_MEDIUM)

        `uvm_info(get_type_name(),
                  "Write channel ordering demo complete (3/3 transactions sent)",
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_wr_order_demo_seq

`endif // AXI4_WR_ORDER_DEMO_SEQ_INCLUDED_