//==============================================================================
// File        : axi4_back_to_back_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Back-to-Back Transaction Demo Sequence.
//               Fires consecutive write and read transactions without
//               waiting for completion between them. Tests bus pipelining
//               and demonstrates how xVALID/xREADY handshakes chain
//               without idle gaps.
//               4 writes (different IDs) then 4 reads (different IDs).
//               Total: 8 transactions, compact waveform.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_BACK_TO_BACK_SEQ_INCLUDED_
`define AXI4_BACK_TO_BACK_SEQ_INCLUDED_

class axi4_back_to_back_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_back_to_back_seq)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_back_to_back_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - fire writes then reads back-to-back
    // =========================================================================
    virtual task body();
        axi4_transaction tr;
        bit [AXI4_ADDR_WIDTH-1:0] base_addr = 32'h0000_A000;

        `uvm_info(get_type_name(),
                  "Starting back-to-back demo sequence (4 writes + 4 reads)",
                  UVM_MEDIUM)

        // =================================================================
        // Phase 1: 4 consecutive writes - different IDs and addresses
        //   Sent without waiting for B response. On waveform, you should
        //   see AW handshakes pipelining (next AWVALID right after AWREADY).
        // =================================================================
        begin
            axi4_transaction wr_trs[4];
            for (int i = 0; i < 4; i++) begin
                wr_trs[i] = axi4_transaction::type_id::create($sformatf("b2b_wr_%0d", i));
                start_item(wr_trs[i]);
                if (!wr_trs[i].randomize() with {
                    dir   == AXI4_WRITE;
                    addr  == base_addr + (i * 32'h100);
                    len   == 1;                  // 2 beats (short burst)
                    size  == AXI4_SIZE_4B;
                    burst == AXI4_BURST_INCR;
                    lock  == AXI4_LOCK_NORMAL;   // demo: normal access so the write commits
                    id    == i[3:0];
                    foreach (strb[j]) strb[j] == 4'b1111;
                }) `uvm_fatal(get_type_name(),
                              $sformatf("Randomization failed for B2B write #%0d", i))
                finish_item(wr_trs[i]);
                // Do NOT wait for done_event here - fire next immediately
            end

            `uvm_info(get_type_name(),
                      "All 4 back-to-back writes submitted",
                      UVM_MEDIUM)

            // Wait for the last write to complete before starting reads
            wait(wr_trs[3].done_event.ev.triggered);
        end

        // =================================================================
        // Phase 2: 4 consecutive reads - same addresses (read-back)
        //   Also pipelined. On waveform: AR handshakes chain without gaps.
        // =================================================================
        for (int i = 0; i < 4; i++) begin
            tr = axi4_transaction::type_id::create($sformatf("b2b_rd_%0d", i));
            start_item(tr);
            if (!tr.randomize() with {
                dir   == AXI4_READ;
                addr  == base_addr + (i * 32'h100);
                len   == 1;                  // 2 beats (matching writes)
                size  == AXI4_SIZE_4B;
                burst == AXI4_BURST_INCR;
                lock  == AXI4_LOCK_NORMAL;   // demo: normal read-back (no EXOKAY)
                id    == i[3:0];
            }) `uvm_fatal(get_type_name(),
                          $sformatf("Randomization failed for B2B read #%0d", i))
            finish_item(tr);
        end

        `uvm_info(get_type_name(),
                  "All 4 back-to-back reads submitted",
                  UVM_MEDIUM)

        `uvm_info(get_type_name(),
                  "Back-to-back demo complete (8/8 transactions sent)",
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_back_to_back_seq

`endif // AXI4_BACK_TO_BACK_SEQ_INCLUDED_