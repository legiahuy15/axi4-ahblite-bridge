//=============================================================================
// File        : axi4_mst_wrap_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 WRAP burst mapping directed sequence.
//               Verifies WRAP2 expansion (two AHB SINGLE/NONSEQ) and
//               WRAP4/8/16 address wrapping behavior across every legal
//               wrap offset.
//               Covers BRG_BST_007 to BRG_BST_010.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_wrap_mapping_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_wrap_mapping_seq)

    localparam int unsigned FULL_SIZE      = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BYTES_PER_BEAT = AXI4_STRB_WIDTH;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        int unsigned len;           // AXI AxLEN (beats-1)
        int unsigned beats;
        string       expected_ahb;  // For logging
        string       label;
    } wrap_entry_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_wrap_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        wrap_entry_t entries[$];

        wait_reset_release();
        validate_knobs();

        build_entries(entries);

        `uvm_info(get_type_name(),
                  $sformatf("WRAP mapping: %0d wrap lengths, sweeping all legal offsets",
                            entries.size()),
                  UVM_LOW)

        foreach (entries[e]) begin
            int unsigned wrap_bytes;
            int unsigned num_offsets;

            wrap_bytes  = entries[e].beats * BYTES_PER_BEAT;
            num_offsets = entries[e].beats;  // offsets: 0, 1*BPB, 2*BPB, ...

            for (int unsigned off = 0; off < num_offsets; off++) begin
                run_wrap_case(AXI4_WRITE, entries[e], off);
                run_wrap_case(AXI4_READ,  entries[e], off);
            end
        end

        `uvm_info(get_type_name(),
                  $sformatf("WRAP mapping summary: run=%0d failed=%0d",
                            cases_run, cases_failed), UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Build the WRAP length entries
    //-------------------------------------------------------------------------
    protected function void build_entries(ref wrap_entry_t entries[$]);
        // BRG_BST_007 : WRAP2 -> AHB SINGLE (both beats NONSEQ)
        entries.push_back('{1,  2,  "AHB_BURST_SINGLE", "WRAP2"});
        // BRG_BST_008 : WRAP4 -> AHB WRAP4
        entries.push_back('{3,  4,  "AHB_BURST_WRAP4",  "WRAP4"});
        // BRG_BST_009 : WRAP8 -> AHB WRAP8
        entries.push_back('{7,  8,  "AHB_BURST_WRAP8",  "WRAP8"});
        // BRG_BST_010 : WRAP16 -> AHB WRAP16
        entries.push_back('{15, 16, "AHB_BURST_WRAP16", "WRAP16"});
    endfunction : build_entries

    //-------------------------------------------------------------------------
    // Run a single WRAP case with a specific starting offset
    //-------------------------------------------------------------------------
    protected task run_wrap_case(
        axi4_dir_e    dir,
        wrap_entry_t  entry,
        int unsigned  offset_index
    );
        axi4_transaction              req;
        axi4_transaction              rsp;
        bit [AXI4_ADDR_WIDTH-1:0]     addr;
        bit [AXI4_ADDR_WIDTH-1:0]     wrap_base;
        int unsigned                  wrap_bytes;
        string                        tag;

        wrap_bytes = entry.beats * BYTES_PER_BEAT;
        wrap_base  = compute_wrap_base(cases_run, wrap_bytes);
        addr       = wrap_base + (offset_index * BYTES_PER_BEAT);
        tag        = $sformatf("%s_off%0d_%s", entry.label, offset_index,
                               (dir == AXI4_WRITE) ? "WR" : "RD");

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s addr=0x%0h wrap_base=0x%0h beats=%0d expected=%s",
                            cases_run, tag, addr, wrap_base, entry.beats,
                            entry.expected_ahb),
                  UVM_MEDIUM)

        if (dir == AXI4_WRITE) begin
            req = create_request(cases_run, AXI4_WRITE, addr, entry.len);
            fill_write_data(req, cases_run);
            send_axi_request_wait(req, rsp);
            cases_run++;
            if (rsp.bresp != AXI4_RESP_OKAY) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf("%s write BRESP=%s at 0x%0h",
                                     tag, rsp.bresp.name(), addr))
            end

            // Read-back with the same WRAP parameters to verify data
            begin
                axi4_transaction rd_req, rd_rsp;
                rd_req = create_request(cases_run, AXI4_READ, addr,
                                        entry.len);
                send_axi_request_wait(rd_req, rd_rsp);
                cases_run++;
                check_readback(tag, addr, rd_rsp, req, entry.beats);
            end
        end else begin
            // Read
            req = create_request(cases_run, AXI4_READ, addr, entry.len);
            send_axi_request_wait(req, rsp);
            cases_run++;
            check_read_resp(tag, addr, rsp, entry.beats);
        end
    endtask : run_wrap_case

    //-------------------------------------------------------------------------
    // Address computation (wrap base aligned to the wrap boundary)
    //-------------------------------------------------------------------------
    protected function bit [AXI4_ADDR_WIDTH-1:0] compute_wrap_base(
        int unsigned index,
        int unsigned wrap_bytes
    );
        bit [AXI4_ADDR_WIDTH-1:0] raw_addr;
        bit [AXI4_ADDR_WIDTH-1:0] aligned;

        // Space out each case; ensure wrap-boundary alignment
        raw_addr = base_addr + (index * wrap_bytes);
        aligned  = (raw_addr / wrap_bytes) * wrap_bytes;
        return aligned;
    endfunction : compute_wrap_base

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        int unsigned              seq_num,
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("wrap_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", seq_num));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_WRAP;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s WRAP len=%0d addr=0x%0h",
                                 dir.name(), len, addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Fill write data with recognizable per-beat patterns
    //-------------------------------------------------------------------------
    protected function void fill_write_data(
        axi4_transaction req,
        int unsigned     case_index
    );
        foreach (req.data[i]) begin
            req.data[i] = get_data_pattern(case_index, i);
            req.strb[i] = '1;
        end
    endfunction : fill_write_data

    protected function bit [AXI4_DATA_WIDTH-1:0] get_data_pattern(
        int unsigned case_index,
        int unsigned beat_index
    );
        bit [AXI4_DATA_WIDTH-1:0] pattern;

        pattern = '0;
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            pattern[8*lane +: 8] = 8'hE0 + case_index * 2 +
                                   beat_index * 2 + lane;
        return pattern;
    endfunction : get_data_pattern

    //-------------------------------------------------------------------------
    // Response checking
    //-------------------------------------------------------------------------
    protected function void check_readback(
        string           tag,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction rsp,
        axi4_transaction wr_req,
        int unsigned     expected_beats
    );
        bit failed;

        failed = 1'b0;
        if (rsp.data.size() != expected_beats ||
            rsp.rresp.size() != expected_beats) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s readback beat count mismatch at 0x%0h: expected=%0d actual=%0d",
                                 tag, addr, expected_beats, rsp.data.size()))
        end else begin
            foreach (rsp.data[i]) begin
                if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s readback RRESP error at 0x%0h beat=%0d: %s",
                                         tag, addr, i, rsp.rresp[i].name()))
                end
                if (rsp.data[i] !== wr_req.data[i]) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf({"%s readback data mismatch at 0x%0h ",
                                          "beat=%0d: expected=0x%0h actual=0x%0h"},
                                         tag, addr, i, wr_req.data[i],
                                         rsp.data[i]))
                end
            end
        end

        if (failed)
            cases_failed++;
    endfunction : check_readback

    protected function void check_read_resp(
        string           tag,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction rsp,
        int unsigned     expected_beats
    );
        bit failed;

        failed = 1'b0;
        if (rsp.data.size() != expected_beats ||
            rsp.rresp.size() != expected_beats) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s read beat count mismatch at 0x%0h: expected=%0d actual=%0d",
                                 tag, addr, expected_beats, rsp.data.size()))
        end else begin
            foreach (rsp.rresp[i]) begin
                if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s read RRESP error at 0x%0h beat=%0d: %s",
                                         tag, addr, i, rsp.rresp[i].name()))
                end
            end
        end

        if (failed)
            cases_failed++;
    endfunction : check_read_resp

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        if ((base_addr % BYTES_PER_BEAT) != 0)
            `uvm_fatal(get_type_name(), "base_addr is not bus aligned")
    endfunction : validate_knobs

endclass : axi4_mst_wrap_mapping_seq