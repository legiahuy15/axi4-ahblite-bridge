//=============================================================================
// File        : ahb_passive_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Description : Generates legal write traffic while the slave agent is
//               passive. No read-back is used because a passive slave does not
//               provide a memory model or drive response data.
//=============================================================================

`ifndef AHB_PASSIVE_SEQ_INCLUDED_
`define AHB_PASSIVE_SEQ_INCLUDED_

class ahb_passive_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_passive_seq)

    int unsigned num_iter = 12;
    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_A000;

    // Number of transactions completed successfully. The test compares this
    // with both num_iter and the passive monitor's publication count.
    int unsigned num_sent;

    function new(string name = "ahb_passive_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        ahb_transaction tr;
        bit             ok;
        ahb_burst_e     directed_burst;
        ahb_size_e      directed_size;

        if (num_iter < 6)
            `uvm_fatal(get_type_name(),
                       "NUM_ITER must be at least 6 to cover the directed burst/size matrix")

        `uvm_info(get_type_name(),
                  $sformatf("Starting passive-slave traffic: %0d transfers", num_iter),
                  UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            // Repeat a deterministic six-entry matrix:
            //   SINGLE/INCR4 x 8/16/32-bit.
            // Randomization is retained for data and other legal knobs only.
            directed_burst = ((i % 2) == 0) ? AHB_BURST_SINGLE
                                             : AHB_BURST_INCR4;
            case ((i / 2) % 3)
                0: directed_size = AHB_SIZE_8B;
                1: directed_size = AHB_SIZE_16B;
                2: directed_size = AHB_SIZE_32B;
            endcase

            tr = ahb_transaction::type_id::create($sformatf("tr_%0d", i));
            if (!tr.randomize() with {
                    write == AHB_WRITE;
                    burst == directed_burst;
                    size  == directed_size;
                    addr  == base_addr + i * 32;
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Randomization failed at iteration %0d", i))

            send_and_wait(tr, ok);
            if (!ok) begin
                `uvm_error(get_type_name(),
                           $sformatf("Transfer %0d was aborted", i))
            end else begin
                num_sent++;
            end
        end

        `uvm_info(get_type_name(),
                  $sformatf("Passive-slave traffic complete: sent=%0d expected=%0d",
                            num_sent, num_iter),
                  UVM_LOW)
    endtask : body

endclass : ahb_passive_seq

`endif // AHB_PASSIVE_SEQ_INCLUDED_