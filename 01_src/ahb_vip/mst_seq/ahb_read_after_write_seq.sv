//=============================================================================
// File        : ahb_read_after_write_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Read-after-write data-integrity sequence. Each iteration does
//               a SINGLE write followed by a SINGLE read at the SAME address
//               and compares the returned data against the written data.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_READ_AFTER_WRITE_SEQ_INCLUDED_
`define AHB_READ_AFTER_WRITE_SEQ_INCLUDED_

class ahb_read_after_write_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_read_after_write_seq)

    //-------------------------------------------------------------------------
    // Knobs (settable from the test via uvm_config_db or direct assignment)
    //-------------------------------------------------------------------------
    int unsigned num_iter = 20;               // write/read pairs to run

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_0000;
    bit [AHB_ADDR_WIDTH-1:0] addr_span = 32'h0000_0400;   // 1KB window

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned num_checked;
    int unsigned num_mismatch;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_read_after_write_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Body - num_iter x (write @A, read @A, compare). Word-sized SINGLE
    // transfers only, so HRDATA compares directly against HWDATA
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_transaction wr_tr;
        ahb_transaction rd_tr;
        bit             ok;

        `uvm_info(get_type_name(),
                  $sformatf("Starting read-after-write: %0d iterations over [0x%08h : 0x%08h]",
                            num_iter, base_addr, base_addr + addr_span - 1), UVM_LOW)

        repeat (num_iter) begin

            // WRITE
            wr_tr = ahb_transaction::type_id::create("wr_tr");
            if (!wr_tr.randomize() with {
                    write == AHB_WRITE;
                    burst == AHB_BURST_SINGLE;
                    size  == AHB_SIZE_32B;
                    addr inside {[base_addr : base_addr + addr_span - 1]};
                })
                `uvm_fatal(get_type_name(), "Write transaction randomization failed")

            send_and_wait(wr_tr, ok);
            if (!ok) continue;                  // reset flush - skip the pair

            // READ (same address)
            rd_tr = ahb_transaction::type_id::create("rd_tr");
            if (!rd_tr.randomize() with {
                    write == AHB_READ;
                    burst == AHB_BURST_SINGLE;
                    size  == wr_tr.size;
                    addr  == wr_tr.addr;
                })
                `uvm_fatal(get_type_name(), "Read transaction randomization failed")

            send_and_wait(rd_tr, ok);
            if (!ok) continue;

            // CHECK
            // ERROR beats commit no data - nothing to compare
            if (wr_tr.resp[0] == AHB_RESP_ERROR || rd_tr.resp[0] == AHB_RESP_ERROR) begin
                `uvm_info(get_type_name(),
                          $sformatf("Skipping check @0x%08h (ERROR response)", wr_tr.addr),
                          UVM_MEDIUM)
                continue;
            end

            num_checked++;
            if (rd_tr.rdata[0] !== wr_tr.wdata[0]) begin
                num_mismatch++;
                `uvm_error(get_type_name(),
                           $sformatf("RAW mismatch @0x%08h: wrote 0x%08h, read 0x%08h",
                                     wr_tr.addr, wr_tr.wdata[0], rd_tr.rdata[0]))
            end else begin
                `uvm_info(get_type_name(),
                          $sformatf("RAW ok @0x%08h: 0x%08h", wr_tr.addr, rd_tr.rdata[0]),
                          UVM_MEDIUM)
            end
        end

        `uvm_info(get_type_name(),
                  $sformatf("Read-after-write done: checked=%0d mismatch=%0d",
                            num_checked, num_mismatch),
                  (num_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endtask : body

endclass : ahb_read_after_write_seq

`endif // AHB_READ_AFTER_WRITE_SEQ_INCLUDED_