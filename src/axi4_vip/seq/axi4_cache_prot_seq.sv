//==============================================================================
// File        : axi4_cache_prot_seq.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : AXI4 Cache and Protection Attribute Sweep Sequence.
//               Systematically sweeps all 16 values of AWCACHE/ARCACHE and 8
//               values of AWPROT/ARPROT for both read and write transactions.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_CACHE_PROT_SEQ_INCLUDED_
`define AXI4_CACHE_PROT_SEQ_INCLUDED_

class axi4_cache_prot_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_cache_prot_seq)

    // Constructor
    function new(string name = "axi4_cache_prot_seq");
        super.new(name);
    endfunction : new

    // body task
    virtual task body();
        `uvm_info(get_type_name(), "Starting cache and prot attribute sweep sequence", UVM_MEDIUM)

        // We run 16 transactions for writes, and 16 for reads to cover all values.
        // Cache has 16 values (0-15), Prot has 8 values (0-7).
        for (int c = 0; c < 16; c++) begin
            axi4_transaction wr_tr, rd_tr;

            // Write Phase
            wr_tr = axi4_transaction::type_id::create($sformatf("cache_prot_wr_%0d", c));
            start_item(wr_tr);
            if (!wr_tr.randomize() with {
                dir   == AXI4_WRITE;
                addr  inside {[addr_lo : addr_hi]};
                addr  < 32'hE000_0000;
                id    inside {[id_lo   : id_hi]};
                lock  == AXI4_LOCK_NORMAL;
                cache == c;
                prot  == c % 8;
            }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for cache/prot write #%0d", c))
            finish_item(wr_tr);

            // Read Phase
            rd_tr = axi4_transaction::type_id::create($sformatf("cache_prot_rd_%0d", c));
            start_item(rd_tr);
            if (!rd_tr.randomize() with {
                dir   == AXI4_READ;
                addr  inside {[addr_lo : addr_hi]};
                addr  < 32'hE000_0000;
                id    inside {[id_lo   : id_hi]};
                lock  == AXI4_LOCK_NORMAL;
                cache == c;
                prot  == c % 8;
            }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for cache/prot read #%0d", c))
            finish_item(rd_tr);

            `uvm_info(get_type_name(),
                      $sformatf("[%0d/16] Swept CACHE=0b%04b PROT=0b%03b (Write & Read)", 
                                c + 1, c, c % 8), UVM_HIGH)
        end

        `uvm_info(get_type_name(), "Cache and prot attribute sweep sequence complete", UVM_MEDIUM)
    endtask : body

endclass : axi4_cache_prot_seq

`endif // AXI4_CACHE_PROT_SEQ_INCLUDED_