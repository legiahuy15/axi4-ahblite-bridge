//==============================================================================
// File        : axi4_wlast_before_aw_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Directed sequence for the "W before AW, burst still in progress"
//               scenario (Case B). Issues W_BEFORE_AW writes with LONG bursts so
//               that the AW handshake - which the master driver delays 2-5 cycles
//               after W starts - deterministically lands mid-burst (WLAST not yet
//               seen). This exercises the retroactive WLAST_MISSING_W_BEFORE_AW
//               check in axi4_sva with legal traffic, proving it does not
//               false-fire and that the new code path is covered.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_WLAST_BEFORE_AW_SEQ_INCLUDED_
`define AXI4_WLAST_BEFORE_AW_SEQ_INCLUDED_

class axi4_wlast_before_aw_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_wlast_before_aw_seq)

    // Burst lengths (len = beats-1) to sweep. All long enough that the
    // 2-5 cycle AW delay lands well before WLAST.
    int unsigned len_list[$] = '{15, 7, 15, 7};

    function new(string name = "axi4_wlast_before_aw_seq");
        super.new(name);
    endfunction : new

    virtual task body();
        `uvm_info(get_type_name(),
                  "Starting W-before-AW partial-overlap sequence (Case B)", UVM_MEDIUM)

        foreach (len_list[i]) begin
            axi4_transaction tr;
            tr = axi4_transaction::type_id::create($sformatf("w_before_aw_tr_%0d", i));
            start_item(tr);
            if (!tr.randomize() with {
                dir      == AXI4_WRITE;
                wr_order == AXI4_WR_W_BEFORE_AW;   // W data begins before AW
                addr     == 32'h0000_4000 + (i * 32'h100);
                len      == len_list[i];
                size     == AXI4_SIZE_4B;
                burst    == AXI4_BURST_INCR;
                id       == i[AXI4_ID_WIDTH-1:0];
                foreach (strb[j]) strb[j] == 4'b1111;
            }) `uvm_fatal(get_type_name(), "Randomization failed for W_BEFORE_AW write")
            finish_item(tr);
            wait(tr.done_event.ev.triggered);

            `uvm_info(get_type_name(),
                      $sformatf("W_BEFORE_AW done: ADDR=0x%08h LEN=%0d (%0d beats) RESP=%s",
                                tr.addr, tr.len, tr.len + 1, tr.resp.name()),
                      UVM_MEDIUM)
        end

        `uvm_info(get_type_name(),
                  "W-before-AW partial-overlap sequence complete", UVM_MEDIUM)
    endtask : body

endclass : axi4_wlast_before_aw_seq

`endif // AXI4_WLAST_BEFORE_AW_SEQ_INCLUDED_
