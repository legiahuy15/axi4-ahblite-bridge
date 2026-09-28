//=============================================================================
// File        : axi4_mst_burst_matrix_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 burst-matrix sweep sequence.
//               Exercises FIXED, INCR and WRAP burst types across
//               conversion-sensitive lengths for both read and write.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_burst_matrix_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_burst_matrix_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr    = 'h1000;
    int unsigned              case_stride  = 256 * AXI4_STRB_WIDTH;
    bit                       enable_write = 1'b1;
    bit                       enable_read  = 1'b1;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_burst_e burst;
        int unsigned len;       // AXI AxLEN value (beats-1)
        string       label;
    } burst_entry_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_burst_matrix_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        burst_entry_t matrix[$];

        wait_reset_release();
        validate_knobs();

        build_matrix(matrix);

        `uvm_info(get_type_name(),
                  $sformatf("Burst matrix: %0d entries, write=%0b read=%0b",
                            matrix.size(), enable_write, enable_read),
                  UVM_LOW)

        foreach (matrix[i]) begin
            if (enable_write)
                run_case(i, AXI4_WRITE, matrix[i]);
            if (enable_read)
                run_case(i, AXI4_READ, matrix[i]);
        end

        `uvm_info(get_type_name(),
                  $sformatf("Burst matrix summary: run=%0d failed=%0d",
                            cases_run, cases_failed), UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Build the sweep matrix
    //-------------------------------------------------------------------------
    protected function void build_matrix(ref burst_entry_t matrix[$]);
        // INCR lengths: 1,2,3,4,5,8,10,16,17,32,128,256
        //   len = beats-1 => 0,1,2,3,4,7,9,15,16,31,127,255
        // 10, 32 and 128 are non-fixed-length AHB INCR bursts between the
        // AHB INCR4/8/16 lengths; 128 also covers AxLEN 64..254
        int unsigned incr_lens[] = '{0, 1, 2, 3, 4, 7, 9, 15, 16, 31, 127, 255};
        foreach (incr_lens[i])
            matrix.push_back('{AXI4_BURST_INCR, incr_lens[i],
                               $sformatf("INCR_%0d", incr_lens[i] + 1)});

        // FIXED lengths: 1,2,3,4,5,8,16 (FIXED max AxLEN=15)
        //   len = beats-1 => 0,1,2,3,4,7,15
        begin
            int unsigned fixed_lens[] = '{0, 1, 2, 3, 4, 7, 15};
            foreach (fixed_lens[i])
                matrix.push_back('{AXI4_BURST_FIXED, fixed_lens[i],
                                   $sformatf("FIXED_%0d",
                                             fixed_lens[i] + 1)});
        end

        // WRAP legal lengths: 2,4,8,16
        //   len = beats-1 => 1,3,7,15
        begin
            int unsigned wrap_lens[] = '{1, 3, 7, 15};
            foreach (wrap_lens[i])
                matrix.push_back('{AXI4_BURST_WRAP, wrap_lens[i],
                                   $sformatf("WRAP_%0d",
                                             wrap_lens[i] + 1)});
        end
    endfunction : build_matrix

    //-------------------------------------------------------------------------
    // Run a single burst case (write-then-readback or read-only)
    //-------------------------------------------------------------------------
    protected task run_case(
        int unsigned   index,
        axi4_dir_e     dir,
        burst_entry_t  entry
    );
        axi4_transaction              req;
        axi4_transaction              rsp;
        bit [AXI4_ADDR_WIDTH-1:0]     addr;
        int unsigned                  beats;
        string                        tag;

        beats = entry.len + 1;
        addr  = compute_address(index, entry.burst, entry.len);
        tag   = $sformatf("%s_%s", entry.label,
                          (dir == AXI4_WRITE) ? "WR" : "RD");

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s addr=0x%0h beats=%0d",
                            cases_run, tag, addr, beats), UVM_MEDIUM)

        if (dir == AXI4_WRITE) begin
            // Write then read-back
            req = create_request(cases_run, AXI4_WRITE, addr, entry.len,
                                 FULL_SIZE, entry.burst);
            fill_data(req, index);
            send_axi_request_wait(req, rsp);
            cases_run++;
            if (rsp.bresp != AXI4_RESP_OKAY) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf("%s write BRESP=%s at 0x%0h",
                                     tag, rsp.bresp.name(), addr))
            end

            // Read-back for non-FIXED bursts (FIXED overwrites same addr)
            if (entry.burst != AXI4_BURST_FIXED) begin
                axi4_transaction rd_req, rd_rsp;
                rd_req = create_request(cases_run, AXI4_READ, addr,
                                        entry.len, FULL_SIZE, entry.burst);
                send_axi_request_wait(rd_req, rd_rsp);
                cases_run++;
                check_read_data(tag, addr, rd_rsp, req, beats);
            end
        end else begin
            // Read-only (scoreboard/predictor validate AHB translation)
            req = create_request(cases_run, AXI4_READ, addr, entry.len,
                                 FULL_SIZE, entry.burst);
            send_axi_request_wait(req, rsp);
            cases_run++;
            check_read_resp(tag, addr, rsp, beats);
        end
    endtask : run_case

    //-------------------------------------------------------------------------
    // Address computation
    //-------------------------------------------------------------------------
    protected function bit [AXI4_ADDR_WIDTH-1:0] compute_address(
        int unsigned   index,
        axi4_burst_e   burst,
        int unsigned   len
    );
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        int unsigned              beats;
        int unsigned              byte_per_beat;
        int unsigned              total_bytes;

        beats        = len + 1;
        byte_per_beat = (1 << FULL_SIZE);
        total_bytes  = beats * byte_per_beat;

        // Base offset per case, ensure bus-aligned
        addr = base_addr + (index * case_stride);
        addr = (addr / byte_per_beat) * byte_per_beat;

        // For WRAP, alignment must be on size boundary (already done above).
        // For INCR the rule to respect here is the AXI one: a burst must not
        // cross a 4 KB boundary. Aligning the start down to a power of two at
        // least as large as the burst guarantees that for any bus width.
        // The 1 KB boundary is an AHB concern and bridge_1kb_boundary_test
        // covers it deliberately, so nothing is done about it here: the old
        // nudge to the next 1 KB boundary assumed a burst fits in 1 KB, which
        // stops being true at 8 bytes a beat, and it pushed a 256-beat 64-bit
        // burst across a 4 KB boundary instead of away from one.
        if (burst == AXI4_BURST_INCR) begin
            int unsigned span;

            span = byte_per_beat;
            while (span < total_bytes)
                span = span << 1;
            addr = (addr / span) * span;
        end

        return addr;
    endfunction : compute_address

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        int unsigned              seq_num,
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len,
        int unsigned              size_code,
        axi4_burst_e              burst
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("matrix_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", seq_num));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::len;
                size     == axi4_size_e'(local::size_code);
                burst    == local::burst;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s burst=%s len=%0d addr=0x%0h",
                                 dir.name(), burst.name(), len, addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Fill write data with recognizable patterns
    //-------------------------------------------------------------------------
    protected function void fill_data(
        axi4_transaction req,
        int unsigned     case_index
    );
        foreach (req.data[i]) begin
            req.data[i] = get_data_pattern(case_index, i);
            req.strb[i] = '1;
        end
    endfunction : fill_data

    protected function bit [AXI4_DATA_WIDTH-1:0] get_data_pattern(
        int unsigned case_index,
        int unsigned beat_index
    );
        bit [AXI4_DATA_WIDTH-1:0] pattern;

        pattern = '0;
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            pattern[8*lane +: 8] = 8'hB0 + case_index * 4 +
                                   beat_index * 2 + lane;
        return pattern;
    endfunction : get_data_pattern

    //-------------------------------------------------------------------------
    // Response checking
    //-------------------------------------------------------------------------
    protected function void check_read_data(
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
                               $sformatf("%s readback data mismatch at 0x%0h beat=%0d: expected=0x%0h actual=0x%0h",
                                         tag, addr, i, wr_req.data[i],
                                         rsp.data[i]))
                end
            end
        end

        if (failed)
            cases_failed++;
    endfunction : check_read_data

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
        if (!enable_write && !enable_read)
            `uvm_fatal(get_type_name(),
                       "At least one of enable_write or enable_read must be set")
        if (case_stride < (256 * AXI4_STRB_WIDTH))
            `uvm_warning(get_type_name(),
                         $sformatf("case_stride=%0d may cause address overlap for long bursts",
                                   case_stride))
        if ((base_addr % AXI4_STRB_WIDTH) != 0)
            `uvm_fatal(get_type_name(), "base_addr is not bus aligned")
    endfunction : validate_knobs

endclass : axi4_mst_burst_matrix_seq