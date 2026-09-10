//=============================================================================
// File        : axi4_mst_incr_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 INCR burst mapping directed sequence.
//               Verifies SINGLE, INCR4/8/16 and undefined-INCR selection
//               across every legal AxSIZE, without 1 KB crossing.
//               Covers BRG_BST_001 to BRG_BST_005.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_incr_mapping_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_incr_mapping_seq)

    localparam int unsigned FULL_SIZE  = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned NUM_SIZES  = FULL_SIZE + 1;   // 1B .. full-width

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr    = 'h1000;
    int unsigned              case_stride  = 'h400;

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
        string       expected_ahb;  // For logging only
        string       label;
    } incr_entry_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_incr_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        incr_entry_t entries[$];

        wait_reset_release();
        validate_knobs();

        build_entries(entries);

        `uvm_info(get_type_name(),
                  $sformatf("INCR mapping: %0d length entries",
                            entries.size()),
                  UVM_LOW)

        foreach (entries[e]) begin
            if (entries[e].len == 0) begin
                // Single-beat INCR: sweep all legal AxSIZE values
                // (bridge supports narrow only for single transfers)
                for (int unsigned sz = 0; sz < NUM_SIZES; sz++) begin
                    run_incr_case(AXI4_WRITE, entries[e], sz);
                    run_incr_case(AXI4_READ,  entries[e], sz);
                end
            end else begin
                // Multi-beat INCR: bridge always uses full bus width
                run_incr_case(AXI4_WRITE, entries[e], FULL_SIZE);
                run_incr_case(AXI4_READ,  entries[e], FULL_SIZE);
            end
        end

        `uvm_info(get_type_name(),
                  $sformatf("INCR mapping summary: run=%0d failed=%0d",
                            cases_run, cases_failed), UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Build the INCR length entries
    //-------------------------------------------------------------------------
    protected function void build_entries(ref incr_entry_t entries[$]);
        // BRG_BST_001 : 1 beat  -> AHB SINGLE
        entries.push_back('{0,   "AHB_BURST_SINGLE", "INCR_1beat"});
        // BRG_BST_005 : 2 beats -> AHB undefined INCR
        entries.push_back('{1,   "AHB_BURST_INCR",   "INCR_2beat"});
        // BRG_BST_005 : 3 beats -> AHB undefined INCR
        entries.push_back('{2,   "AHB_BURST_INCR",   "INCR_3beat"});
        // BRG_BST_002 : 4 beats -> AHB INCR4
        entries.push_back('{3,   "AHB_BURST_INCR4",  "INCR_4beat"});
        // BRG_BST_005 : 5 beats -> AHB undefined INCR
        entries.push_back('{4,   "AHB_BURST_INCR",   "INCR_5beat"});
        // BRG_BST_003 : 8 beats -> AHB INCR8
        entries.push_back('{7,   "AHB_BURST_INCR8",  "INCR_8beat"});
        // BRG_BST_004 : 16 beats -> AHB INCR16
        entries.push_back('{15,  "AHB_BURST_INCR16", "INCR_16beat"});
        // BRG_BST_005 : 17 beats -> AHB undefined INCR
        entries.push_back('{16,  "AHB_BURST_INCR",   "INCR_17beat"});
        // BRG_BST_005 : 256 beats -> AHB undefined INCR
        entries.push_back('{255, "AHB_BURST_INCR",   "INCR_256beat"});
    endfunction : build_entries


    //-------------------------------------------------------------------------
    // Run a single INCR case
    //-------------------------------------------------------------------------
    protected task run_incr_case(
        axi4_dir_e    dir,
        incr_entry_t  entry,
        int unsigned  size_code
    );
        axi4_transaction              req;
        axi4_transaction              rsp;
        bit [AXI4_ADDR_WIDTH-1:0]     addr;
        int unsigned                  beats;
        int unsigned                  bytes_per_beat;
        string                        tag;

        beats          = entry.len + 1;
        bytes_per_beat = 1 << size_code;
        addr           = compute_safe_address(cases_run, beats, bytes_per_beat);
        tag            = $sformatf("%s_sz%0dB_%s", entry.label,
                                   bytes_per_beat,
                                   (dir == AXI4_WRITE) ? "WR" : "RD");

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s addr=0x%0h beats=%0d expected=%s",
                            cases_run, tag, addr, beats,
                            entry.expected_ahb),
                  UVM_MEDIUM)

        if (dir == AXI4_WRITE) begin
            req = create_request(cases_run, AXI4_WRITE, addr, entry.len,
                                 size_code);
            fill_write_data(req, cases_run, size_code);
            send_axi_request_wait(req, rsp);
            cases_run++;
            if (rsp.bresp != AXI4_RESP_OKAY) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf("%s write BRESP=%s at 0x%0h",
                                     tag, rsp.bresp.name(), addr))
            end

            // Read-back to verify data integrity
            begin
                axi4_transaction rd_req, rd_rsp;
                rd_req = create_request(cases_run, AXI4_READ, addr,
                                        entry.len, size_code);
                send_axi_request_wait(rd_req, rd_rsp);
                cases_run++;
                check_readback(tag, addr, rd_rsp, req, beats, size_code);
            end
        end else begin
            req = create_request(cases_run, AXI4_READ, addr, entry.len,
                                 size_code);
            send_axi_request_wait(req, rsp);
            cases_run++;
            check_read_resp(tag, addr, rsp, beats);
        end
    endtask : run_incr_case

    //-------------------------------------------------------------------------
    // Address computation — align and avoid 1 KB crossing
    //-------------------------------------------------------------------------
    protected function bit [AXI4_ADDR_WIDTH-1:0] compute_safe_address(
        int unsigned index,
        int unsigned beats,
        int unsigned bytes_per_beat
    );
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        int unsigned              total_bytes;

        total_bytes = beats * bytes_per_beat;

        // Each case gets its own page region
        addr = base_addr + (index * case_stride);
        // Align to transfer size
        addr = (addr / bytes_per_beat) * bytes_per_beat;

        // Ensure no 1 KB boundary crossing
        begin
            bit [AXI4_ADDR_WIDTH-1:0] page_start;
            int unsigned              page_offset;

            page_start  = (addr >> 10) << 10;
            page_offset = addr - page_start;
            if ((page_offset + total_bytes) > 1024)
                addr = page_start;   // Start at page boundary
        end

        return addr;
    endfunction : compute_safe_address

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        int unsigned              seq_num,
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len,
        int unsigned              size_code
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("incr_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", seq_num));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::len;
                size     == axi4_size_e'(local::size_code);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s len=%0d size=%0d addr=0x%0h",
                                 dir.name(), len, size_code, addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Fill write data with recognizable per-lane patterns
    //-------------------------------------------------------------------------
    protected function void fill_write_data(
        axi4_transaction req,
        int unsigned     case_index,
        int unsigned     size_code
    );
        int unsigned bytes_per_beat;
        int unsigned lane_start;

        bytes_per_beat = 1 << size_code;
        lane_start     = req.addr % AXI4_STRB_WIDTH;

        foreach (req.data[i]) begin
            bit [AXI4_DATA_WIDTH-1:0]     pattern;
            bit [AXI4_STRB_WIDTH-1:0]     strobe;

            pattern = '0;
            strobe  = '0;
            for (int unsigned b = 0; b < bytes_per_beat; b++) begin
                int unsigned lane;
                lane = (lane_start + b) % AXI4_STRB_WIDTH;
                pattern[8*lane +: 8] = 8'hC0 + case_index * 2 +
                                       i * 2 + b;
                strobe[lane] = 1'b1;
            end
            req.data[i] = pattern;
            req.strb[i] = strobe;
        end
    endfunction : fill_write_data

    //-------------------------------------------------------------------------
    // Response checking
    //-------------------------------------------------------------------------
    protected function void check_readback(
        string           tag,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction rsp,
        axi4_transaction wr_req,
        int unsigned     expected_beats,
        int unsigned     size_code
    );
        bit failed;
        int unsigned bytes_per_beat;
        int unsigned lane_start;

        failed         = 1'b0;
        bytes_per_beat = 1 << size_code;
        lane_start     = addr % AXI4_STRB_WIDTH;

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
                // Compare only the active lanes
                for (int unsigned b = 0; b < bytes_per_beat; b++) begin
                    int unsigned lane;
                    lane = (lane_start + b) % AXI4_STRB_WIDTH;
                    if (rsp.data[i][8*lane +: 8] !==
                        wr_req.data[i][8*lane +: 8]) begin
                        failed = 1'b1;
                        `uvm_error(get_type_name(),
                                   $sformatf({"%s data mismatch at 0x%0h ",
                                              "beat=%0d lane=%0d: ",
                                              "expected=0x%02h actual=0x%02h"},
                                             tag, addr, i, lane,
                                             wr_req.data[i][8*lane +: 8],
                                             rsp.data[i][8*lane +: 8]))
                    end
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
        if ((base_addr % AXI4_STRB_WIDTH) != 0)
            `uvm_fatal(get_type_name(), "base_addr is not bus aligned")
        if (case_stride < 1024)
            `uvm_warning(get_type_name(),
                         $sformatf("case_stride=%0d may cause address overlap",
                                   case_stride))
    endfunction : validate_knobs

endclass : axi4_mst_incr_mapping_seq