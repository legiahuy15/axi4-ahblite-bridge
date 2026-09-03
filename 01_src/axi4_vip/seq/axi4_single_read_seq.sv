//==============================================================================
// File        : axi4_single_read_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Single AXI4 read burst sequence.
//               Generates one read transaction with configurable address,
//               burst length, size, and type.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_SINGLE_READ_SEQ_INCLUDED_
`define AXI4_SINGLE_READ_SEQ_INCLUDED_

class axi4_single_read_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_single_read_seq)

    // =========================================================================
    // Configurable fields - set before starting, or leave random
    // =========================================================================
    rand bit [AXI4_ADDR_WIDTH-1:0] addr;
    rand bit [AXI4_LEN_WIDTH-1:0]  len;
    rand axi4_size_e               size;
    rand axi4_burst_type_e         burst;

    // Constrain addr and len to sensible defaults (overridable)
    constraint c_addr_range { addr inside {[addr_lo : addr_hi]}; }
    constraint c_len_default { soft len inside {[0:15]}; }
    constraint c_size_default { soft size == AXI4_SIZE_4B; }
    constraint c_burst_default { soft burst == AXI4_BURST_INCR; }

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_single_read_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - create, randomise, and send one read transaction
    // =========================================================================
    virtual task body();
        axi4_transaction tr;

        tr = axi4_transaction::type_id::create("rd_tr");
        start_item(tr);

        if (!tr.randomize() with {
            dir   == AXI4_READ;
            addr  == local::addr;
            len   == local::len;
            size  == local::size;
            burst == local::burst;
            id    inside {[id_lo : id_hi]};
        }) `uvm_fatal(get_type_name(), "Randomization failed for read transaction")

        finish_item(tr);

        `uvm_info(get_type_name(),
                  $sformatf("Read sent: ADDR=0x%08h LEN=%0d SIZE=%s BURST=%s",
                            tr.addr, tr.len, tr.size.name(), tr.burst.name()),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_single_read_seq

`endif // AXI4_SINGLE_READ_SEQ_INCLUDED_