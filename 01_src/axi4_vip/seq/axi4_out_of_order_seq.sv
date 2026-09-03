//==============================================================================
// File        : axi4_out_of_order_seq.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : Out-of-Order read/write transactions sequence.
//               Generates multiple concurrent transactions with different IDs
//               to verify out-of-order response handling in the system.
//               Note: This sequence complies with the design limitation that
//               read data interleaving is NOT supported. Beats within a single
//               read burst are returned contiguously.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_OUT_OF_ORDER_SEQ_INCLUDED_
`define AXI4_OUT_OF_ORDER_SEQ_INCLUDED_

class axi4_out_of_order_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_out_of_order_seq)

    // =========================================================================
    // Configurable knobs
    // =========================================================================
    int unsigned num_writes         = 15; // Number of write transactions to generate
    int unsigned num_reads          = 15; // Number of read transactions to generate
    int unsigned outstanding_depth  = 4;  // Maximum outstanding transactions in flight per channel

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_out_of_order_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - generate write/read transactions concurrently with different IDs
    // =========================================================================
    virtual task body();
        semaphore sem_write;
        semaphore sem_read;

        `uvm_info(get_type_name(),
                  $sformatf("Starting Out-of-Order sequence (no-interleaving): writes=%0d, reads=%0d, depth=%0d", 
                            num_writes, num_reads, outstanding_depth),
                  UVM_MEDIUM)

        sem_write = new(outstanding_depth);
        sem_read  = new(outstanding_depth);

        fork
            // Write channel thread
            begin
                for (int i = 0; i < num_writes; i++) begin
                    automatic int idx = i;
                    sem_write.get(1);
                    fork
                        begin
                            axi4_transaction wr_tr;
                            wr_tr = axi4_transaction::type_id::create($sformatf("ooo_wr_tr_%0d", idx));
                            start_item(wr_tr);
                            // Enforce different IDs by using idx to offset or randomize
                            if (!wr_tr.randomize() with {
                                dir   == AXI4_WRITE;
                                addr  inside {[addr_lo : addr_hi]};
                                lock  == AXI4_LOCK_NORMAL;
                                // Distribute IDs to maximize OOO possibility
                                id    == ((id_lo + idx) % (id_hi - id_lo + 1));
                            }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for OOO write transaction #%0d", idx))

                            `uvm_info(get_type_name(),
                                      $sformatf("OOO Write [#%0d] started: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                                idx, wr_tr.id, wr_tr.addr, wr_tr.len),
                                      UVM_HIGH)

                            finish_item(wr_tr);

                            // Wait for response
                            wait(wr_tr.done_event.ev.triggered);

                            `uvm_info(get_type_name(),
                                      $sformatf("OOO Write [#%0d] complete: ID=0x%0h RESP=%s", 
                                                idx, wr_tr.id, wr_tr.resp.name()),
                                      UVM_HIGH)
                            sem_write.put(1);
                        end
                    join_none
                end
                wait fork;
                `uvm_info(get_type_name(), "All OOO write transactions finished", UVM_MEDIUM)
            end

            // Read channel thread
            begin
                for (int i = 0; i < num_reads; i++) begin
                    automatic int idx = i;
                    sem_read.get(1);
                    fork
                        begin
                            axi4_transaction rd_tr;
                            rd_tr = axi4_transaction::type_id::create($sformatf("ooo_rd_tr_%0d", idx));
                            start_item(rd_tr);
                            if (!rd_tr.randomize() with {
                                dir   == AXI4_READ;
                                addr  inside {[addr_lo : addr_hi]};
                                lock  == AXI4_LOCK_NORMAL;
                                // Distribute IDs to maximize OOO possibility
                                id    == ((id_lo + idx) % (id_hi - id_lo + 1));
                            }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for OOO read transaction #%0d", idx))

                            `uvm_info(get_type_name(),
                                      $sformatf("OOO Read [#%0d] started: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                                idx, rd_tr.id, rd_tr.addr, rd_tr.len),
                                      UVM_HIGH)

                            finish_item(rd_tr);

                            // Wait for response (entire burst)
                            wait(rd_tr.done_event.ev.triggered);

                            `uvm_info(get_type_name(),
                                      $sformatf("OOO Read [#%0d] complete: ID=0x%0h", idx, rd_tr.id),
                                      UVM_HIGH)
                            sem_read.put(1);
                        end
                    join_none
                end
                wait fork;
                `uvm_info(get_type_name(), "All OOO read transactions finished", UVM_MEDIUM)
            end
        join

        `uvm_info(get_type_name(), "Out-of-Order sequence complete", UVM_MEDIUM)
    endtask : body

endclass : axi4_out_of_order_seq

`endif // AXI4_OUT_OF_ORDER_SEQ_INCLUDED_