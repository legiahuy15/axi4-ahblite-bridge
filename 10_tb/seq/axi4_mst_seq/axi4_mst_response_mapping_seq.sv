//=============================================================================
// File        : axi4_mst_response_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB response to AXI response mapping directed sequence.
//               PG177: AHB OKAY maps to AXI OKAY, AHB ERROR maps to AXI
//               SLVERR, and the bridge never generates EXOKAY or DECERR.
//               PG177 does not state whether a burst continues after an AHB
//               ERROR; the RTL does, and the predictor models that, so this
//               sequence checks it directly: the plan holds one entry per
//               expected AHB beat and a burst that stops early leaves
//               entries behind.
//               Cases, each a single AXI request answered from the plan:
//               - every AHB burst shape (SINGLE, INCR4/8/16, undefined INCR,
//                 WRAP2/4/8/16, FIXED) with one ERROR beat, read and write
//               - ERROR at the first, a middle and the last beat of an INCR4,
//                 plus an all-OKAY INCR4, read and write
//               - wait states 1, 2, 8 and 16 with OKAY and with ERROR
//               - two ERROR beats in one burst, read and write
//               Checks BRESP, per-beat RRESP, beat count and the read data of
//               every OKAY beat.
//               Covers BRG_RSP_001 to BRG_RSP_004 and BRG_WAI_001.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_response_mapping_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_response_mapping_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned MAX_BEATS = 256;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

    //-------------------------------------------------------------------------
    // Shared response plan
    //-------------------------------------------------------------------------
    ahb_response_policy policy;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned error_beats;
    int unsigned slverr_responses;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_dir_e            dir;
        axi4_burst_e          burst;
        int unsigned          len;          // AXI AxLEN value (beats-1)
        int unsigned          offset;       // start offset inside the region
        bit [MAX_BEATS-1:0]   error_beats;  // beats answered with AHB ERROR
        int unsigned          waits;        // OKAY wait cycles on every beat
        string                label;
    } rsp_case_t;

    typedef struct {
        axi4_burst_e burst;
        int unsigned len;
        int unsigned offset_beats;  // start offset in transfer-size units
        int unsigned error_beat;
        string       label;
    } shape_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_response_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        rsp_case_t cases[$];

        if (policy == null)
            `uvm_fatal(get_type_name(), "Response policy is null")

        wait_reset_release();
        validate_knobs();

        build_cases(cases);

        `uvm_info(get_type_name(),
                  $sformatf("Response mapping: %0d cases", cases.size()),
                  UVM_LOW)

        foreach (cases[i])
            run_case(i, cases[i]);

        `uvm_info(get_type_name(),
                  $sformatf({"Response mapping summary: run=%0d failed=%0d ",
                             "error_beats=%0d slverr_responses=%0d ",
                             "ahb_beats=%0d waited_beats=%0d unplanned_beats=%0d"},
                            cases_run, cases_failed, error_beats,
                            slverr_responses, policy.beats_served,
                            policy.waited_beats_served,
                            policy.unplanned_beats),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void build_cases(ref rsp_case_t cases[$]);
        add_shape_cases(cases);
        add_position_cases(cases);
        add_wait_cases(cases);
        add_multi_error_cases(cases);
    endfunction : build_cases

    // Every AHB burst shape with one ERROR beat, read and write
    protected function void add_shape_cases(ref rsp_case_t cases[$]);
        shape_t shapes[] = '{
            '{AXI4_BURST_INCR,   0, 0, 0,  "SINGLE"},
            '{AXI4_BURST_INCR,   3, 0, 1,  "INCR4"},
            '{AXI4_BURST_INCR,   4, 0, 2,  "INCR5"},
            '{AXI4_BURST_INCR,   7, 0, 3,  "INCR8"},
            '{AXI4_BURST_INCR,  15, 0, 7,  "INCR16"},
            '{AXI4_BURST_WRAP,   1, 1, 1,  "WRAP2"},
            '{AXI4_BURST_WRAP,   3, 2, 2,  "WRAP4"},
            '{AXI4_BURST_WRAP,   7, 4, 4,  "WRAP8"},
            '{AXI4_BURST_WRAP,  15, 8, 8,  "WRAP16"},
            '{AXI4_BURST_FIXED,  2, 0, 1,  "FIXED3"}
        };

        foreach (shapes[s]) begin
            bit [MAX_BEATS-1:0] mask;

            mask = '0;
            mask[shapes[s].error_beat] = 1'b1;
            for (int unsigned d = 0; d < 2; d++) begin
                axi4_dir_e dir;

                dir = (d == 0) ? AXI4_READ : AXI4_WRITE;
                cases.push_back('{dir, shapes[s].burst, shapes[s].len,
                                  shapes[s].offset_beats * (1 << FULL_SIZE),
                                  mask, 0,
                                  $sformatf("%s_ERR%0d_%s", shapes[s].label,
                                            shapes[s].error_beat,
                                            (dir == AXI4_READ) ? "RD" : "WR")});
            end
        end
    endfunction : add_shape_cases

    // ERROR at the first, a middle and the last beat of an INCR4, and none
    protected function void add_position_cases(ref rsp_case_t cases[$]);
        int unsigned        positions[] = '{0, 1, 3};
        bit [MAX_BEATS-1:0] no_error;

        no_error = '0;
        for (int unsigned d = 0; d < 2; d++) begin
            axi4_dir_e dir;

            dir = (d == 0) ? AXI4_READ : AXI4_WRITE;
            cases.push_back('{dir, AXI4_BURST_INCR, 3, 0, no_error, 0,
                              $sformatf("INCR4_NOERR_%s",
                                        (dir == AXI4_READ) ? "RD" : "WR")});
            foreach (positions[p]) begin
                bit [MAX_BEATS-1:0] mask;

                mask = '0;
                mask[positions[p]] = 1'b1;
                cases.push_back('{dir, AXI4_BURST_INCR, 3, 0, mask, 0,
                                  $sformatf("INCR4_POS%0d_%s", positions[p],
                                            (dir == AXI4_READ) ? "RD" : "WR")});
            end
        end
    endfunction : add_position_cases

    // Wait states with OKAY and with ERROR. The AHB ERROR response adds one
    // cycle of its own, so an ERROR beat is never a zero-wait beat.
    protected function void add_wait_cases(ref rsp_case_t cases[$]);
        int unsigned        waits[] = '{1, 2, 8, 16};
        bit [MAX_BEATS-1:0] no_error;

        no_error = '0;
        foreach (waits[w]) begin
            bit [MAX_BEATS-1:0] mask;

            cases.push_back('{AXI4_READ, AXI4_BURST_INCR, 3, 0, no_error,
                              waits[w],
                              $sformatf("INCR4_WAIT%0d_OKAY_RD", waits[w])});
            mask    = '0;
            mask[1] = 1'b1;
            cases.push_back('{AXI4_READ, AXI4_BURST_INCR, 3, 0, mask, waits[w],
                              $sformatf("INCR4_WAIT%0d_ERR1_RD", waits[w])});
        end

        begin
            bit [MAX_BEATS-1:0] mask;

            mask    = '0;
            mask[2] = 1'b1;
            cases.push_back('{AXI4_WRITE, AXI4_BURST_INCR, 3, 0, mask, 2,
                              "INCR4_WAIT2_ERR2_WR"});
        end
    endfunction : add_wait_cases

    // Two ERROR beats: BRESP stays SLVERR and both read beats report SLVERR
    protected function void add_multi_error_cases(ref rsp_case_t cases[$]);
        for (int unsigned d = 0; d < 2; d++) begin
            axi4_dir_e          dir;
            bit [MAX_BEATS-1:0] mask;

            dir     = (d == 0) ? AXI4_READ : AXI4_WRITE;
            mask    = '0;
            mask[1] = 1'b1;
            mask[3] = 1'b1;
            cases.push_back('{dir, AXI4_BURST_INCR, 3, 0, mask, 0,
                              $sformatf("INCR4_ERR1_ERR3_%s",
                                        (dir == AXI4_READ) ? "RD" : "WR")});
        end
    endfunction : add_multi_error_cases

    //-------------------------------------------------------------------------
    // Run one case: plan the AHB beats, send the request, check the completion
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, rsp_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [AXI4_ADDR_WIDTH-1:0] beat_addr[];
        axi4_transaction          req;
        axi4_transaction          rsp;
        int unsigned              beats;
        int unsigned              case_errors;
        bit                       expect_slverr;
        bit                       failed;

        beats = c.len + 1;
        addr  = base_addr + (index * case_stride) + c.offset;
        get_beat_addresses(addr, c, beats, beat_addr);

        case_errors   = 0;
        for (int unsigned i = 0; i < beats; i++)
            if (c.error_beats[i])
                case_errors++;
        expect_slverr = (case_errors > 0);

        `uvm_info(get_type_name(),
                  $sformatf({"[%0d] %s addr=0x%0h beats=%0d waits=%0d ",
                             "error_beats=0x%0h expected %s"},
                            index, c.label, addr, beats, c.waits,
                            c.error_beats[15:0],
                            expect_slverr ? "SLVERR" : "OKAY"),
                  UVM_MEDIUM)

        // One plan entry per expected AHB beat
        policy.clear_plan();
        for (int unsigned i = 0; i < beats; i++)
            policy.add_beat(c.error_beats[i] ? AHB_RESP_ERROR : AHB_RESP_OKAY,
                            c.waits);

        req = create_request(c, addr, beats);
        send_axi_request_wait(req, rsp);
        cases_run++;
        error_beats += case_errors;

        failed = 1'b0;
        if (policy.pending_beats() != 0) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s at 0x%0h: %0d planned AHB beats were ",
                                  "never issued (burst stopped early)"},
                                 c.label, addr, policy.pending_beats()))
            policy.clear_plan();
        end

        if (c.dir == AXI4_WRITE)
            failed |= check_write_response(c, addr, rsp, expect_slverr);
        else
            failed |= check_read_response(c, addr, rsp, beats, beat_addr);

        if (failed)
            cases_failed++;
    endtask : run_case

    //-------------------------------------------------------------------------
    // Response checks
    //-------------------------------------------------------------------------
    protected function bit check_write_response(
        rsp_case_t                c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp,
        bit                       expect_slverr
    );
        axi4_resp_e expected;

        expected = expect_slverr ? AXI4_RESP_SLVERR : AXI4_RESP_OKAY;
        if (rsp.bresp == AXI4_RESP_SLVERR)
            slverr_responses++;
        if (rsp.bresp != expected) begin
            `uvm_error(get_type_name(),
                       $sformatf("%s write at 0x%0h: BRESP=%s, expected %s",
                                 c.label, addr, rsp.bresp.name(),
                                 expected.name()))
            return 1'b1;
        end
        return 1'b0;
    endfunction : check_write_response

    protected function bit check_read_response(
        rsp_case_t                c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp,
        int unsigned              beats,
        bit [AXI4_ADDR_WIDTH-1:0] beat_addr[]
    );
        bit failed;

        failed = 1'b0;
        if ((rsp.data.size() != beats) || (rsp.rresp.size() != beats)) begin
            `uvm_error(get_type_name(),
                       $sformatf("%s read at 0x%0h: beat count expected=%0d actual=%0d",
                                 c.label, addr, beats, rsp.data.size()))
            return 1'b1;
        end

        foreach (rsp.rresp[i]) begin
            axi4_resp_e expected;

            expected = c.error_beats[i] ? AXI4_RESP_SLVERR : AXI4_RESP_OKAY;
            if (rsp.rresp[i] == AXI4_RESP_SLVERR)
                slverr_responses++;
            if (rsp.rresp[i] != expected) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("%s read at 0x%0h beat=%0d: RRESP=%s, expected %s",
                                     c.label, addr, i, rsp.rresp[i].name(),
                                     expected.name()))
            end
            // Data on an errored beat is not defined by PG177
            if (!c.error_beats[i]) begin
                bit [AXI4_DATA_WIDTH-1:0] expected_data;

                expected_data = policy.read_data(beat_addr[i]);
                if (rsp.data[i] !== expected_data) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf({"%s read at 0x%0h beat=%0d: ",
                                          "expected=0x%0h actual=0x%0h"},
                                         c.label, addr, i, expected_data,
                                         rsp.data[i]))
                end
            end
        end
        return failed;
    endfunction : check_read_response

    //-------------------------------------------------------------------------
    // Beat addresses (AXI burst address rules)
    //-------------------------------------------------------------------------
    protected function void get_beat_addresses(
        input  bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        input  rsp_case_t                c,
        input  int unsigned              beats,
        output bit [AXI4_ADDR_WIDTH-1:0] beat_addr[]
    );
        int unsigned              bytes;
        bit [AXI4_ADDR_WIDTH-1:0] wrap_base;
        bit [AXI4_ADDR_WIDTH-1:0] next_addr;

        bytes        = 1 << FULL_SIZE;
        wrap_base    = start_addr - (start_addr % (beats * bytes));
        beat_addr    = new[beats];
        beat_addr[0] = start_addr;
        for (int unsigned i = 1; i < beats; i++) begin
            case (c.burst)
                AXI4_BURST_FIXED: next_addr = start_addr;
                AXI4_BURST_WRAP: begin
                    next_addr = beat_addr[i - 1] + bytes;
                    if (next_addr >= (wrap_base + (beats * bytes)))
                        next_addr = wrap_base;
                end
                default: next_addr = beat_addr[i - 1] + bytes;
            endcase
            beat_addr[i] = next_addr;
        end
    endfunction : get_beat_addresses

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        rsp_case_t                c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              beats
    );
        axi4_transaction req;
        int unsigned     req_len;
        axi4_burst_e     req_burst;
        axi4_dir_e       req_dir;

        req_len   = c.len;
        req_burst = c.burst;
        req_dir   = c.dir;
        req = axi4_transaction::type_id::create(
                  $sformatf("rspmap_%s_%0d",
                            (c.dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::req_dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == local::req_burst;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s addr=0x%0h",
                                 c.label, addr))

        if (c.dir == AXI4_WRITE) begin
            foreach (req.data[i]) begin
                for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
                    req.data[i][8*k +: 8] = 8'h70 + cases_run * 4 + i * 2 + k;
                req.strb[i] = '1;
            end
        end
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // Every case fits in its own region, so no burst crosses a 1 KB boundary
    // and the AHB beats of one case never overlap another case.
    protected function void validate_knobs();
        int unsigned region_bytes;

        region_bytes = 16 * AXI4_STRB_WIDTH;
        if ((case_stride < region_bytes) ||
            ((case_stride % region_bytes) != 0))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be a non-zero multiple of %0d bytes",
                                 region_bytes))
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
    endfunction : validate_knobs

endclass : axi4_mst_response_mapping_seq