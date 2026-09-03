//==============================================================================
// File        : axi4_random_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Random mixed-traffic sequence.
//               Generates a configurable number of random write and read
//               transactions with fully randomised parameters. Useful for
//               stress testing, corner-case discovery, and coverage closure.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_RANDOM_SEQ_INCLUDED_
`define AXI4_RANDOM_SEQ_INCLUDED_

class axi4_random_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_random_seq)

    // =========================================================================
    // Configurable knobs
    // =========================================================================
    int unsigned num_txns = 20;     // Total number of transactions to generate

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_random_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - generate num_txns random write/read transactions
    // =========================================================================
    virtual task body();
        `uvm_info(get_type_name(),
                  $sformatf("Starting random sequence: %0d transactions", num_txns),
                  UVM_MEDIUM)

        for (int i = 0; i < num_txns; i++) begin
            axi4_transaction tr;

            tr = axi4_transaction::type_id::create($sformatf("rand_tr_%0d", i));
            start_item(tr);

            if (!tr.randomize() with {
                addr inside {[addr_lo : addr_hi]};
                id   inside {[id_lo   : id_hi]};
            }) `uvm_fatal(get_type_name(),
                          $sformatf("Randomization failed for transaction #%0d", i))

            finish_item(tr);

            `uvm_info(get_type_name(),
                      $sformatf("[%0d/%0d] %s: ID=0x%0h ADDR=0x%08h LEN=%0d BURST=%s",
                                i + 1, num_txns,
                                tr.dir.name(), tr.id, tr.addr, tr.len,
                                tr.burst.name()),
                      UVM_HIGH)
        end

        `uvm_info(get_type_name(),
                  $sformatf("Random sequence complete: %0d transactions sent", num_txns),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_random_seq

`endif // AXI4_RANDOM_SEQ_INCLUDED_