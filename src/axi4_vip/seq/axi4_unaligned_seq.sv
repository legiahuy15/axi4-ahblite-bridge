//==============================================================================
// File        : axi4_unaligned_seq.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : AXI4 Unaligned Access Sequence.
//               Generates unaligned write and read transactions to cover the
//               cp_aligned = unaligned coverpoint and its cross coverage crosses.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_UNALIGNED_SEQ_INCLUDED_
`define AXI4_UNALIGNED_SEQ_INCLUDED_

class axi4_unaligned_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_unaligned_seq)

    // Configurable knobs
    int unsigned num_txns = 20;

    // Constructor
    function new(string name = "axi4_unaligned_seq");
        super.new(name);
    endfunction : new

    // body task
    virtual task body();
        `uvm_info(get_type_name(), $sformatf("Starting unaligned access sequence: %0d transactions", num_txns), UVM_MEDIUM)

        for (int i = 0; i < num_txns; i++) begin
            axi4_transaction tr;
            tr = axi4_transaction::type_id::create($sformatf("unalign_tr_%0d", i));
            start_item(tr);

            if (!tr.randomize() with {
                addr inside {[addr_lo : addr_hi]};
                id   inside {[id_lo   : id_hi]};
                // Exclude WRAP burst because AXI4 spec says WRAP burst start address must be aligned
                burst != AXI4_BURST_WRAP;
                // Exclude error regions for general ease of checking data
                addr < 32'hE000_0000;
                // Force unaligned address: address is not divisible by transfer size
                (addr % (1 << size)) != 0;
                // Distribute size between 2B and 4B to test various unaligned offset levels
                size inside {AXI4_SIZE_2B, AXI4_SIZE_4B};
            }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for unaligned transaction #%0d", i))

            finish_item(tr);

            `uvm_info(get_type_name(),
                      $sformatf("[%0d/%0d] Unaligned %s: ADDR=0x%08h SIZE=%s BURST=%s (AlignmentOffset=%0d)",
                                i + 1, num_txns, tr.dir.name(), tr.addr, tr.size.name(),
                                tr.burst.name(), tr.addr % (1 << tr.size)),
                      UVM_HIGH)
        end

        `uvm_info(get_type_name(), "Unaligned access sequence complete", UVM_MEDIUM)
    endtask : body

endclass : axi4_unaligned_seq

`endif // AXI4_UNALIGNED_SEQ_INCLUDED_