//=============================================================================
// File        : axi4_mst_1kb_boundary_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 1 KB boundary directed sequence.
//               Exercises no-cross, exact-edge and first-crossing INCR
//               cases for both read and write.
//               Covers BRG_1KB_001 to BRG_1KB_004.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_1kb_boundary_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_1kb_boundary_seq)

    localparam int unsigned FULL_SIZE      = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BYTES_PER_BEAT = AXI4_STRB_WIDTH;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] page_base = 'h10000;   // 1 KB-aligned region

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef enum {
        BOUNDARY_NO_CROSS,    // wholly inside 1 KB
        BOUNDARY_EXACT_EDGE,  // last byte at offset 0x3FF
        BOUNDARY_CROSSING,    // crosses after the first beat
        BOUNDARY_CROSS_MID,   // crosses in the middle of the burst
        BOUNDARY_CROSS_LATE   // only the last beat is past the boundary
    } boundary_class_e;

    typedef struct {
        int unsigned      len;        // AXI AxLEN
        boundary_class_e  bclass;
        string            label;
    } boundary_entry_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_1kb_boundary_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        boundary_entry_t entries[$];
        int unsigned     page_index;

        wait_reset_release();
        validate_knobs();

        build_entries(entries);

        page_index = 0;
        `uvm_info(get_type_name(),
                  $sformatf("1KB boundary: %0d entries", entries.size()),
                  UVM_LOW)

        foreach (entries[e]) begin
            // Write
            run_boundary_case(AXI4_WRITE, entries[e], page_index);
            page_index++;
            // Read
            run_boundary_case(AXI4_READ, entries[e], page_index);
            page_index++;
        end

        `uvm_info(get_type_name(),
                  $sformatf("1KB boundary summary: run=%0d failed=%0d",
                            cases_run, cases_failed), UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Build the boundary test entries
    //-------------------------------------------------------------------------
    protected function void build_entries(ref boundary_entry_t entries[$]);
        // Fixed-length INCR mappings: 4, 8, 16 beats
        int unsigned fixed_lens[] = '{3, 7, 15};

        // ---- BRG_1KB_001: No-cross cases ----
        // Bursts well inside 1 KB (use fixed-length and undefined-length)
        foreach (fixed_lens[i])
            entries.push_back('{fixed_lens[i], BOUNDARY_NO_CROSS,
                                $sformatf("NO_CROSS_INCR%0d",
                                          fixed_lens[i] + 1)});
        // Undefined-length no-cross
        entries.push_back('{4, BOUNDARY_NO_CROSS, "NO_CROSS_INCR5"});

        // ---- BRG_1KB_002: Exact-edge cases ----
        // Burst ends exactly at offset 0x3FF (last byte of 1 KB page)
        foreach (fixed_lens[i])
            entries.push_back('{fixed_lens[i], BOUNDARY_EXACT_EDGE,
                                $sformatf("EXACT_EDGE_INCR%0d",
                                          fixed_lens[i] + 1)});
        entries.push_back('{4, BOUNDARY_EXACT_EDGE, "EXACT_EDGE_INCR5"});

        // ---- BRG_1KB_003: Crossing cases ----
        // Burst crosses the 1 KB boundary after the first beat, in the
        // middle, or on the last beat
        foreach (fixed_lens[i])
            entries.push_back('{fixed_lens[i], BOUNDARY_CROSSING,
                                $sformatf("CROSS_INCR%0d",
                                          fixed_lens[i] + 1)});
        entries.push_back('{4, BOUNDARY_CROSSING, "CROSS_INCR5"});
        // 256-beat crossing
        entries.push_back('{255, BOUNDARY_CROSSING, "CROSS_INCR256"});

        foreach (fixed_lens[i]) begin
            entries.push_back('{fixed_lens[i], BOUNDARY_CROSS_MID,
                                $sformatf("CROSS_MID_INCR%0d",
                                          fixed_lens[i] + 1)});
            entries.push_back('{fixed_lens[i], BOUNDARY_CROSS_LATE,
                                $sformatf("CROSS_LATE_INCR%0d",
                                          fixed_lens[i] + 1)});
        end
        entries.push_back('{4,   BOUNDARY_CROSS_MID,  "CROSS_MID_INCR5"});
        entries.push_back('{4,   BOUNDARY_CROSS_LATE, "CROSS_LATE_INCR5"});
        entries.push_back('{255, BOUNDARY_CROSS_MID,  "CROSS_MID_INCR256"});
        entries.push_back('{255, BOUNDARY_CROSS_LATE, "CROSS_LATE_INCR256"});
    endfunction : build_entries

    //-------------------------------------------------------------------------
    // Run a single boundary case
    //-------------------------------------------------------------------------
    protected task run_boundary_case(
        axi4_dir_e       dir,
        boundary_entry_t entry,
        int unsigned     page_index
    );
        axi4_transaction              req;
        axi4_transaction              rsp;
        bit [AXI4_ADDR_WIDTH-1:0]     addr;
        int unsigned                  beats;
        string                        tag;

        beats = entry.len + 1;
        addr  = compute_boundary_address(page_index, beats, entry.bclass);
        tag   = $sformatf("%s_%s", entry.label,
                          (dir == AXI4_WRITE) ? "WR" : "RD");

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s addr=0x%0h beats=%0d page_off=0x%0h class=%s",
                            cases_run, tag, addr, beats,
                            addr[9:0], entry.bclass.name()),
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
        end else begin
            req = create_request(cases_run, AXI4_READ, addr, entry.len);
            send_axi_request_wait(req, rsp);
            cases_run++;
            check_read_resp(tag, addr, rsp, beats);
        end
    endtask : run_boundary_case

    //-------------------------------------------------------------------------
    // Address computation for boundary classes
    //-------------------------------------------------------------------------
    protected function bit [AXI4_ADDR_WIDTH-1:0] compute_boundary_address(
        int unsigned     page_index,
        int unsigned     beats,
        boundary_class_e bclass
    );
        bit [AXI4_ADDR_WIDTH-1:0] kb_base;
        int unsigned              total_bytes;
        int unsigned              offset;

        // Each case gets its own 4 KB page to avoid interference
        kb_base     = page_base + (page_index * 'h1000);
        total_bytes = beats * BYTES_PER_BEAT;

        case (bclass)
            BOUNDARY_NO_CROSS: begin
                // Start at offset 0
                offset = 0;
            end

            BOUNDARY_EXACT_EDGE: begin
                // Last byte at 0x3FF: start_offset = 0x400 - total_bytes
                if (total_bytes > 'h400)
                    // Burst too large to fit in 1 KB; start at 0
                    offset = 0;
                else
                    offset = 'h400 - total_bytes;
            end

            BOUNDARY_CROSSING: begin
                // First beat is the last one below the boundary
                offset = 'h400 - BYTES_PER_BEAT;
            end

            BOUNDARY_CROSS_MID: begin
                // About half of the beats on each side of the boundary
                offset = 'h400 - (((beats / 2) > 0 ? (beats / 2) : 1) *
                                  BYTES_PER_BEAT);
            end

            BOUNDARY_CROSS_LATE: begin
                // Only the last beat past the boundary (offset 0 if > 1 KB)
                if (((beats - 1) * BYTES_PER_BEAT) > 'h400)
                    offset = 0;
                else
                    offset = 'h400 - ((beats - 1) * BYTES_PER_BEAT);
            end

            default:
                offset = 0;
        endcase

        // Ensure bus alignment
        offset = (offset / BYTES_PER_BEAT) * BYTES_PER_BEAT;
        return kb_base + offset;
    endfunction : compute_boundary_address

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
                  $sformatf("boundary_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", seq_num));

        // For crossing cases, disable the 4 KB boundary constraint
        // (1 KB crossing is legal in AXI, the bridge handles it)
        req.c_4kb_boundary.constraint_mode(0);
        req.c_distribution.constraint_mode(0);

        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s len=%0d addr=0x%0h",
                                 dir.name(), len, addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Fill write data
    //-------------------------------------------------------------------------
    protected function void fill_write_data(
        axi4_transaction req,
        int unsigned     case_index
    );
        foreach (req.data[i]) begin
            bit [AXI4_DATA_WIDTH-1:0] pattern;
            pattern = '0;
            for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
                pattern[8*lane +: 8] = 8'hA0 + case_index * 2 +
                                       i * 2 + lane;
            req.data[i] = pattern;
            req.strb[i] = '1;
        end
    endfunction : fill_write_data

    //-------------------------------------------------------------------------
    // Response checking
    //-------------------------------------------------------------------------
    protected function void check_read_resp(
        string                    tag,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp,
        int unsigned              expected_beats
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
        if ((page_base % 'h1000) != 0)
            `uvm_fatal(get_type_name(),
                       "page_base must be 4 KB aligned")
    endfunction : validate_knobs

endclass : axi4_mst_1kb_boundary_seq