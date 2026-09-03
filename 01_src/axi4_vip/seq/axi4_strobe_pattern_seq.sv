//==============================================================================
// File        : axi4_strobe_pattern_seq.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : AXI4 Write Strobe Pattern Sequence.
//               Generates write transactions targeting different write strobe (WSTRB)
//               patterns: all-bytes enabled, no-bytes enabled (sparse writes),
//               and partial strobe patterns (individual byte lane checks).
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_STROBE_PATTERN_SEQ_INCLUDED_
`define AXI4_STROBE_PATTERN_SEQ_INCLUDED_

class axi4_strobe_pattern_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_strobe_pattern_seq)

    // Constructor
    function new(string name = "axi4_strobe_pattern_seq");
        super.new(name);
    endfunction : new

    // body task
    virtual task body();
        axi4_transaction tr;

        `uvm_info(get_type_name(), "Starting write strobe pattern sequence", UVM_MEDIUM)

        // Pattern 1: All bytes enabled (full-word write)
        tr = axi4_transaction::type_id::create("strb_all_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  inside {[addr_lo : addr_hi]};
            addr  < 32'hE000_0000;
            id    inside {[id_lo   : id_hi]};
            size  == AXI4_SIZE_4B;
            len   == 3; // 4 beats
            foreach (strb[i]) strb[i] == 4'b1111;
        }) `uvm_fatal(get_type_name(), "Randomization failed for full write strobe pattern")
        finish_item(tr);
        `uvm_info(get_type_name(), "Sent Write with all-bytes strobe (4'b1111)", UVM_HIGH)

        // Pattern 2: No bytes enabled (sparse transaction)
        tr = axi4_transaction::type_id::create("strb_none_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == AXI4_WRITE;
            addr  inside {[addr_lo : addr_hi]};
            addr  < 32'hE000_0000;
            id    inside {[id_lo   : id_hi]};
            size  == AXI4_SIZE_4B;
            len   == 3; // 4 beats
            foreach (strb[i]) strb[i] == 4'b0000;
        }) `uvm_fatal(get_type_name(), "Randomization failed for empty write strobe pattern")
        finish_item(tr);
        `uvm_info(get_type_name(), "Sent Write with zero-bytes strobe (4'b0000)", UVM_HIGH)

        // Pattern 3: Partial strobe patterns (walking ones and half-words)
        for (int p = 0; p < 6; p++) begin
            bit [3:0] test_strb;
            case (p)
                0: test_strb = 4'b0001;
                1: test_strb = 4'b0010;
                2: test_strb = 4'b0100;
                3: test_strb = 4'b1000;
                4: test_strb = 4'b0011; // lower halfword
                5: test_strb = 4'b1100; // upper halfword
            endcase

            tr = axi4_transaction::type_id::create($sformatf("strb_partial_tr_%0d", p));
            start_item(tr);
            if (!tr.randomize() with {
                dir   == AXI4_WRITE;
                addr  inside {[addr_lo : addr_hi]};
                addr  < 32'hE000_0000;
                id    inside {[id_lo   : id_hi]};
                size  == AXI4_SIZE_4B;
                len   == 0; // single beat
                strb[0] == test_strb;
            }) `uvm_fatal(get_type_name(), $sformatf("Randomization failed for partial write strobe pattern %0d", p))
            finish_item(tr);
            `uvm_info(get_type_name(), $sformatf("Sent Write with partial strobe (4'b%04b)", test_strb), UVM_HIGH)
        end

        `uvm_info(get_type_name(), "Write strobe pattern sequence complete", UVM_MEDIUM)
    endtask : body

endclass : axi4_strobe_pattern_seq

`endif // AXI4_STROBE_PATTERN_SEQ_INCLUDED_