//==============================================================================
// File        : axi4_outstanding_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Outstanding AXI4 transactions sequence.
//               Generates multiple concurrent write and read transactions
//               using fork-join to test the bus's outstanding and interleaving
//               capabilities.
//
//               Outstanding depth is enforced on the actual bus (not just the
//               sequencer handshake) by waiting on each transaction's
//               done_event before releasing the semaphore slot.
//
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_OUTSTANDING_SEQ_INCLUDED_
`define AXI4_OUTSTANDING_SEQ_INCLUDED_

class axi4_outstanding_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_outstanding_seq)

    // =========================================================================
    // Configurable knobs
    // =========================================================================
    int unsigned num_writes         = 15; // Number of write transactions to generate
    int unsigned num_reads          = 15; // Number of read transactions to generate
    int unsigned outstanding_depth  = 4;  // Maximum outstanding transactions in flight per channel

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_outstanding_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - generate write/read transactions concurrently with outstanding limit
    //   The semaphore slot is only released after the driver signals
    //   done_event (B or R response received), ensuring that
    //   outstanding_depth truly reflects the number of in-flight
    //   transactions on the bus at any point in time.
    // =========================================================================
    virtual task body();
        semaphore sem_write;
        semaphore sem_read;

        `uvm_info(get_type_name(),
                  $sformatf("Starting outstanding sequence: writes=%0d, reads=%0d, depth=%0d", 
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
                            wr_tr = axi4_transaction::type_id::create($sformatf("wr_tr_%0d", idx));
                            start_item(wr_tr);
                            if (!wr_tr.randomize() with {
                                dir   == AXI4_WRITE;
                                addr  inside {[addr_lo : addr_hi]};
                                lock  == AXI4_LOCK_NORMAL;
                                id    inside {[id_lo   : id_hi]};
                            }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for write transaction #%0d", idx))

                            `uvm_info(get_type_name(),
                                      $sformatf("Outstanding Write [#%0d] started: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                                idx, wr_tr.id, wr_tr.addr, wr_tr.len),
                                      UVM_HIGH)

                            finish_item(wr_tr);

                            // Wait for actual B response on the bus before
                            // releasing the semaphore slot.
                            wait(wr_tr.done_event.ev.triggered);

                            `uvm_info(get_type_name(),
                                      $sformatf("Outstanding Write [#%0d] complete: ID=0x%0h", idx, wr_tr.id),
                                      UVM_HIGH)
                            sem_write.put(1);
                        end
                    join_none
                end
                // Wait for all spawned write threads to finish
                wait fork;
                `uvm_info(get_type_name(), "All outstanding write transactions finished", UVM_MEDIUM)
            end

            // Read channel thread
            begin
                for (int i = 0; i < num_reads; i++) begin
                    automatic int idx = i;
                    sem_read.get(1);
                    fork
                        begin
                            axi4_transaction rd_tr;
                            rd_tr = axi4_transaction::type_id::create($sformatf("rd_tr_%0d", idx));
                            start_item(rd_tr);
                            if (!rd_tr.randomize() with {
                                dir   == AXI4_READ;
                                addr  inside {[addr_lo : addr_hi]};
                                lock  == AXI4_LOCK_NORMAL;
                                id    inside {[id_lo   : id_hi]};
                            }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for read transaction #%0d", idx))

                            `uvm_info(get_type_name(),
                                      $sformatf("Outstanding Read [#%0d] started: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                                idx, rd_tr.id, rd_tr.addr, rd_tr.len),
                                      UVM_HIGH)

                            finish_item(rd_tr);

                            // Wait for actual R response (all beats) on the bus
                            // before releasing the semaphore slot.
                            wait(rd_tr.done_event.ev.triggered);

                            `uvm_info(get_type_name(),
                                      $sformatf("Outstanding Read [#%0d] complete: ID=0x%0h", idx, rd_tr.id),
                                      UVM_HIGH)
                            sem_read.put(1);
                        end
                    join_none
                end
                // Wait for all spawned read threads to finish
                wait fork;
                `uvm_info(get_type_name(), "All outstanding read transactions finished", UVM_MEDIUM)
            end
        join

        `uvm_info(get_type_name(), "Outstanding sequence complete", UVM_MEDIUM)
    endtask : body

endclass : axi4_outstanding_seq

`endif // AXI4_OUTSTANDING_SEQ_INCLUDED_