//==============================================================================
// File        : axi4_error_response_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Error Response Demo Sequence.
//               Generates transactions targeting OKAY, SLVERR, and DECERR
//               address regions for both write and read directions.
//               Only 6 transactions (1 pair per response type), ideal for
//               waveform capture of B-channel / R-channel error responses.
//
//               Address map (defined by slave driver):
//                 [0x0000_0000 : 0xDFFF_FFFF] -> OKAY
//                 [0xE000_0000 : 0xEFFF_FFFF] -> SLVERR
//                 [0xF000_0000 : 0xFFFF_FFFF] -> DECERR
//
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_ERROR_RESPONSE_SEQ_INCLUDED_
`define AXI4_ERROR_RESPONSE_SEQ_INCLUDED_

class axi4_error_response_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_error_response_seq)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_error_response_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - demonstrate each response type: OKAY, SLVERR, DECERR
    // =========================================================================
    virtual task body();
        axi4_transaction tr;

        `uvm_info(get_type_name(),
                  "Starting error response demo sequence (6 transactions)",
                  UVM_MEDIUM)

        // =================================================================
        // Pair 1: OKAY region - normal access to valid address
        // =================================================================
        // Write
        tr = axi4_transaction::type_id::create("okay_wr_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'h0000_0100;    // Normal address -> OKAY
            len   == 0;                // Single beat
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h0;
        }) `uvm_fatal(get_type_name(), "Randomization failed for OKAY write")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);
        `uvm_info(get_type_name(),
                  $sformatf("TX1 [OKAY-WR] ADDR=0x%08h BRESP=%s",
                            tr.addr, tr.resp.name()), UVM_MEDIUM)

        // Read
        tr = axi4_transaction::type_id::create("okay_rd_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'h0000_0100;
            len   == 0;
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'h0;
        }) `uvm_fatal(get_type_name(), "Randomization failed for OKAY read")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);
        `uvm_info(get_type_name(),
                  $sformatf("TX2 [OKAY-RD] ADDR=0x%08h RRESP=%s",
                            tr.addr, tr.rresp[0].name()), UVM_MEDIUM)

        // =================================================================
        // Pair 2: SLVERR region - slave error response
        // =================================================================
        // Write
        tr = axi4_transaction::type_id::create("slverr_wr_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'hE000_0000;    // SLVERR region
            len   == 0;
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'hA;
        }) `uvm_fatal(get_type_name(), "Randomization failed for SLVERR write")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);
        `uvm_info(get_type_name(),
                  $sformatf("TX3 [SLVERR-WR] ADDR=0x%08h BRESP=%s",
                            tr.addr, tr.resp.name()), UVM_MEDIUM)

        // Read
        tr = axi4_transaction::type_id::create("slverr_rd_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'hE000_0000;
            len   == 0;
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'hA;
        }) `uvm_fatal(get_type_name(), "Randomization failed for SLVERR read")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);
        `uvm_info(get_type_name(),
                  $sformatf("TX4 [SLVERR-RD] ADDR=0x%08h RRESP=%s",
                            tr.addr, tr.rresp[0].name()), UVM_MEDIUM)

        // =================================================================
        // Pair 3: DECERR region - decode error response
        // =================================================================
        // Write
        tr = axi4_transaction::type_id::create("decerr_wr_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  == 32'hF000_0000;    // DECERR region
            len   == 0;
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'hF;
        }) `uvm_fatal(get_type_name(), "Randomization failed for DECERR write")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);
        `uvm_info(get_type_name(),
                  $sformatf("TX5 [DECERR-WR] ADDR=0x%08h BRESP=%s",
                            tr.addr, tr.resp.name()), UVM_MEDIUM)

        // Read
        tr = axi4_transaction::type_id::create("decerr_rd_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_READ;
            addr  == 32'hF000_0000;
            len   == 0;
            size  == AXI4_SIZE_4B;
            burst == AXI4_BURST_INCR;
            lock  == AXI4_LOCK_NORMAL;
            id    == 4'hF;
        }) `uvm_fatal(get_type_name(), "Randomization failed for DECERR read")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);
        `uvm_info(get_type_name(),
                  $sformatf("TX6 [DECERR-RD] ADDR=0x%08h RRESP=%s",
                            tr.addr, tr.rresp[0].name()), UVM_MEDIUM)

        `uvm_info(get_type_name(),
                  "Error response demo complete (6/6 transactions sent)",
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_error_response_seq

`endif // AXI4_ERROR_RESPONSE_SEQ_INCLUDED_