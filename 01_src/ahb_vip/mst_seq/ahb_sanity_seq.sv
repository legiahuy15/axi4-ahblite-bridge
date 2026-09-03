//=============================================================================
// File        : ahb_sanity_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Smoke sequence. Directed SINGLE word pair and INCR4 word burst
//               pair, writing a known pattern and reading it straight back.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_SANITY_SEQ_INCLUDED_
`define AHB_SANITY_SEQ_INCLUDED_

class ahb_sanity_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_sanity_seq)

    //-------------------------------------------------------------------------
    // Knobs (settable from the test via direct assignment)
    //-------------------------------------------------------------------------
    int unsigned num_iter = 4;                            // slots to walk

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_1000;   // 1KB-aligned

    // Slot layout: SINGLE word at slot+0, INCR4 burst at slot+32. Slots never
    // overlap and every burst stays clear of a 1KB boundary
    localparam int unsigned SLOT_SIZE  = 64;
    localparam int unsigned BURST_OFFS = 32;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned num_checked;
    int unsigned num_mismatch;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_sanity_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (SINGLE write/read pair, INCR4 write/read pair)
    //-------------------------------------------------------------------------
    virtual task body();
        bit [AHB_ADDR_WIDTH-1:0] slot;

        `uvm_info(get_type_name(),
                  $sformatf("Starting sanity: %0d slots over [0x%08h : 0x%08h]",
                            num_iter, base_addr,
                            base_addr + num_iter * SLOT_SIZE - 1), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            // SINGLE word: one address cycle, one data cycle
            write_read_check(AHB_BURST_SINGLE, slot, 32'hA5A5_0000 + i);

            // INCR4 word burst: NONSEQ beat then three SEQ beats
            write_read_check(AHB_BURST_INCR4, slot + BURST_OFFS,
                             32'h5A5A_0000 + (i << 8));
        end

        `uvm_info(get_type_name(),
                  $sformatf("Sanity done: checked=%0d mismatch=%0d",
                            num_checked, num_mismatch),
                  (num_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

    //-------------------------------------------------------------------------
    // One write/read pair at the same address and burst type. Word-sized beats
    // only, so HRDATA compares directly against HWDATA. Beat k carries
    // tgt_data + k, so a beat-ordering bug shows up as a shifted pattern
    //-------------------------------------------------------------------------
    protected task write_read_check(ahb_burst_e              burst_type,
                                    bit [AHB_ADDR_WIDTH-1:0] tgt_addr,
                                    bit [AHB_DATA_WIDTH-1:0] tgt_data);
        ahb_transaction wr;
        ahb_transaction rd;
        bit             ok;

        // WRITE
        wr = ahb_transaction::type_id::create("wr");
        if (!wr.randomize() with {
                write == AHB_WRITE;
                burst == burst_type;
                size  == AHB_SIZE_32B;
                addr  == tgt_addr;
                foreach (wdata[k]) wdata[k] == tgt_data + k;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Write randomization failed (%s @0x%08h)",
                                 burst_type.name(), tgt_addr))

        send_and_wait(wr, ok);
        if (!ok) return;                    // reset flush - skip the pair

        // READ (same address, same burst)
        rd = ahb_transaction::type_id::create("rd");
        if (!rd.randomize() with {
                write == AHB_READ;
                burst == burst_type;
                size  == AHB_SIZE_32B;
                addr  == tgt_addr;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Read randomization failed (%s @0x%08h)",
                                 burst_type.name(), tgt_addr))

        send_and_wait(rd, ok);
        if (!ok) return;

        // CHECK - beat k of the read must return beat k of the write. No ERROR
        // is requested here, so any non-OKAY response is a failure
        foreach (rd.rdata[k]) begin
            num_checked++;

            if (wr.resp[k] != AHB_RESP_OKAY || rd.resp[k] != AHB_RESP_OKAY) begin
                num_mismatch++;
                `uvm_error(get_type_name(),
                           $sformatf("%s beat %0d @0x%08h: unexpected response (wr=%s rd=%s)",
                                     burst_type.name(), k, tgt_addr + k * 4,
                                     wr.resp[k].name(), rd.resp[k].name()))
                continue;
            end

            if (rd.rdata[k] !== wr.wdata[k]) begin
                num_mismatch++;
                `uvm_error(get_type_name(),
                           $sformatf("%s beat %0d @0x%08h: wrote 0x%08h, read 0x%08h",
                                     burst_type.name(), k, tgt_addr + k * 4,
                                     wr.wdata[k], rd.rdata[k]))
            end else begin
                `uvm_info(get_type_name(),
                          $sformatf("%s beat %0d @0x%08h: 0x%08h ok",
                                    burst_type.name(), k, tgt_addr + k * 4,
                                    rd.rdata[k]), UVM_MEDIUM)
            end
        end
    endtask : write_read_check

endclass : ahb_sanity_seq

`endif // AHB_SANITY_SEQ_INCLUDED_