//==============================================================================
// File        : axi4_write_read_back_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Write-then-read-back sequence.
//               Writes data to a given address, then reads back from the
//               same address with matching burst parameters. Useful for
//               verifying data integrity through the slave memory model.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_write_read_back_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_write_read_back_seq)

    // =========================================================================
    // Configurable fields
    // =========================================================================
    rand bit [AXI4_ADDR_WIDTH-1:0] addr;
    rand bit [AXI4_LEN_WIDTH-1:0]  len;
    rand axi4_size_e               size;
    rand axi4_burst_type_e         burst;

    constraint c_addr_range { addr inside {[addr_lo : addr_hi]}; }
    constraint c_len_default { soft len inside {[0:15]}; }
    constraint c_size_default { soft size == AXI4_SIZE_4B; }
    constraint c_burst_default { soft burst == AXI4_BURST_INCR; }

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_write_read_back_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - write then read-back with matching parameters
    // =========================================================================
    virtual task body();
        axi4_transaction wr_tr, rd_tr;

        // Phase 1: Write
        wr_tr = axi4_transaction::type_id::create("wr_tr");
        start_item(wr_tr);

        if (!wr_tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == local::addr;
            len   == local::len;
            size  == local::size;
            burst == local::burst;
            lock  == AXI4_LOCK_NORMAL;   // read-back integrity requires the write to commit
            id    inside {[id_lo : id_hi]};
        }) `uvm_fatal(get_type_name(), "Randomization failed for write transaction")

        finish_item(wr_tr);
        wait(wr_tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("Write phase: ADDR=0x%08h LEN=%0d SIZE=%s BURST=%s",
                             wr_tr.addr, wr_tr.len, wr_tr.size.name(), wr_tr.burst.name()),
                  UVM_MEDIUM)

        // Phase 2: Read-back (same addr, len, size, burst)
        rd_tr = axi4_transaction::type_id::create("rd_tr");
        start_item(rd_tr);

        if (!rd_tr.randomize() with {
            dir   == AXI4_READ;
            addr  == wr_tr.addr;
            len   == wr_tr.len;
            size  == wr_tr.size;
            burst == wr_tr.burst;
            lock  == AXI4_LOCK_NORMAL;   // normal read-back (match the write)
            id    inside {[id_lo : id_hi]};
        }) `uvm_fatal(get_type_name(), "Randomization failed for read-back transaction")

        finish_item(rd_tr);
        wait(rd_tr.done_event.ev.triggered);

        `uvm_info(get_type_name(),
                  $sformatf("Read-back phase: ADDR=0x%08h LEN=%0d - data integrity check via scoreboard",
                            rd_tr.addr, rd_tr.len),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_write_read_back_seq