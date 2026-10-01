//=============================================================================
// File        : axi4_mst_backpressure_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI B/R backpressure sequence. Sets the BREADY/RREADY delay
//               per case; a sampler checks VALID and payload stay stable and
//               measures the stall. Cases:
//               - B/R windows of 1, 2, 3, 8 and 16 cycles, SINGLE and INCR4
//               - R windows on INCR16, INCR5, WRAP4, WRAP8 and FIXED3
//               - independent B and R windows
//               - with AHB wait states, with SLVERR, across a 1 KB split
//               Checks responses, read data, beat count and the stall.
//               Covers BRG_WAI_002 and BRG_WAI_003.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_backpressure_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_backpressure_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned MAX_BEATS = 16;

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
    int unsigned b_stall_cycles;
    int unsigned r_stall_cycles;
    int unsigned b_longest_stall;
    int unsigned r_longest_stall;
    int unsigned stability_errors;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_dir_e          dir;
        axi4_burst_e        burst;
        int unsigned        len;         // AXI AxLEN value (beats-1)
        int unsigned        offset;      // start offset inside the region;
                                         // bytes before the boundary for
                                         // 1 KB crossing cases
        int unsigned        b_delay;     // BREADY low cycles per response
        int unsigned        r_delay;     // RREADY low cycles per beat
        int unsigned        ahb_waits;   // AHB HREADY low cycles per beat
        bit [MAX_BEATS-1:0] error_beats; // beats answered with AHB ERROR
        bit                 cross_1kb;   // placed across a 1 KB boundary
        string              label;
    } bp_case_t;

    typedef struct {
        axi4_burst_e burst;
        int unsigned len;
        int unsigned offset_beats;  // start offset in transfer-size units
        int unsigned r_delay;
        string       label;
    } shape_t;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    // Member so the forked thread needs no ref argument
    protected bp_case_t    case_list[$];
    protected int unsigned num_cases;
    protected int unsigned cross_cases_run;

    // Per-case stall measurement, updated by the sampler
    protected int unsigned case_b_cycles;
    protected int unsigned case_r_cycles;
    protected int unsigned case_b_longest;
    protected int unsigned case_r_longest;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_backpressure_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (policy == null)
            `uvm_fatal(get_type_name(), "Response policy is null")

        wait_reset_release();
        validate_knobs();

        build_cases(case_list);
        num_cases = case_list.size();

        `uvm_info(get_type_name(),
                  $sformatf("AXI backpressure: %0d cases", num_cases),
                  UVM_LOW)

        // Sampler runs beside the stimulus until the last case ends
        fork
            begin
                fork
                    sample_stalls();
                    run_all_cases();
                join_any
                disable fork;
            end
        join

        `uvm_info(get_type_name(),
                  $sformatf({"AXI backpressure summary: run=%0d failed=%0d ",
                             "b_stall_cycles=%0d r_stall_cycles=%0d ",
                             "b_longest=%0d r_longest=%0d stability_errors=%0d ",
                             "ahb_beats=%0d waited_beats=%0d unplanned_beats=%0d"},
                            cases_run, cases_failed, b_stall_cycles,
                            r_stall_cycles, b_longest_stall, r_longest_stall,
                            stability_errors, policy.beats_served,
                            policy.waited_beats_served,
                            policy.unplanned_beats),
                  UVM_LOW)
    endtask : body

    protected task run_all_cases();
        foreach (case_list[i])
            run_case(i, case_list[i]);
    endtask : run_all_cases

    //-------------------------------------------------------------------------
    // Response-channel stall sampler
    //-------------------------------------------------------------------------
    // A stalled response must hold VALID and payload; counts stall cycles
    protected task sample_stalls();
        bit                       b_stalled;
        bit [AXI4_ID_WIDTH-1:0]   b_id;
        bit [1:0]                 b_resp;
        int unsigned              b_run;
        bit                       r_stalled;
        bit [AXI4_ID_WIDTH-1:0]   r_id;
        bit [AXI4_DATA_WIDTH-1:0] r_data;
        bit [1:0]                 r_resp;
        bit                       r_last;
        int unsigned              r_run;

        forever begin
            @(cfg.vif.monitor_cb);

            // Write response channel
            if (b_stalled) begin
                if (cfg.vif.monitor_cb.BVALID !== 1'b1) begin
                    stability_errors++;
                    `uvm_error(get_type_name(),
                               "BVALID dropped while BREADY was low")
                end else if ((cfg.vif.monitor_cb.BID   !== b_id) ||
                             (cfg.vif.monitor_cb.BRESP !== b_resp)) begin
                    stability_errors++;
                    `uvm_error(get_type_name(),
                               $sformatf({"B payload changed while BREADY was ",
                                          "low: id 0x%0h to 0x%0h, resp 0x%0h ",
                                          "to 0x%0h"},
                                         b_id, cfg.vif.monitor_cb.BID,
                                         b_resp, cfg.vif.monitor_cb.BRESP))
                end
            end

            if ((cfg.vif.monitor_cb.BVALID === 1'b1) &&
                (cfg.vif.monitor_cb.BREADY !== 1'b1)) begin
                if (!b_stalled) begin
                    b_run  = 0;
                    b_id   = cfg.vif.monitor_cb.BID;
                    b_resp = cfg.vif.monitor_cb.BRESP;
                end
                b_run++;
                b_stall_cycles++;
                case_b_cycles++;
                if (b_run > case_b_longest)
                    case_b_longest = b_run;
                if (b_run > b_longest_stall)
                    b_longest_stall = b_run;
                b_stalled = 1'b1;
            end else begin
                b_stalled = 1'b0;
            end

            // Read data channel
            if (r_stalled) begin
                if (cfg.vif.monitor_cb.RVALID !== 1'b1) begin
                    stability_errors++;
                    `uvm_error(get_type_name(),
                               "RVALID dropped while RREADY was low")
                end else if ((cfg.vif.monitor_cb.RID   !== r_id)   ||
                             (cfg.vif.monitor_cb.RDATA !== r_data) ||
                             (cfg.vif.monitor_cb.RRESP !== r_resp) ||
                             (cfg.vif.monitor_cb.RLAST !== r_last)) begin
                    stability_errors++;
                    `uvm_error(get_type_name(),
                               $sformatf({"R payload changed while RREADY was ",
                                          "low: id 0x%0h/0x%0h data 0x%0h/0x%0h ",
                                          "resp 0x%0h/0x%0h last %0b/%0b"},
                                         r_id,   cfg.vif.monitor_cb.RID,
                                         r_data, cfg.vif.monitor_cb.RDATA,
                                         r_resp, cfg.vif.monitor_cb.RRESP,
                                         r_last, cfg.vif.monitor_cb.RLAST))
                end
            end

            if ((cfg.vif.monitor_cb.RVALID === 1'b1) &&
                (cfg.vif.monitor_cb.RREADY !== 1'b1)) begin
                if (!r_stalled) begin
                    r_run  = 0;
                    r_id   = cfg.vif.monitor_cb.RID;
                    r_data = cfg.vif.monitor_cb.RDATA;
                    r_resp = cfg.vif.monitor_cb.RRESP;
                    r_last = cfg.vif.monitor_cb.RLAST;
                end
                r_run++;
                r_stall_cycles++;
                case_r_cycles++;
                if (r_run > case_r_longest)
                    case_r_longest = r_run;
                if (r_run > r_longest_stall)
                    r_longest_stall = r_run;
                r_stalled = 1'b1;
            end else begin
                r_stalled = 1'b0;
            end
        end
    endtask : sample_stalls

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void build_cases(ref bp_case_t cases[$]);
        add_b_window_cases(cases);
        add_r_window_cases(cases);
        add_r_shape_cases(cases);
        add_independent_window_cases(cases);
        add_ahb_wait_cases(cases);
        add_error_cases(cases);
        add_cross_1kb_cases(cases);
    endfunction : build_cases

    protected function void add_case(
        ref bp_case_t             cases[$],
        input axi4_dir_e          dir,
        input axi4_burst_e        burst,
        input int unsigned        len,
        input int unsigned        offset,
        input int unsigned        b_delay,
        input int unsigned        r_delay,
        input string              label,
        input int unsigned        ahb_waits   = 0,
        input bit [MAX_BEATS-1:0] error_beats = '0,
        input bit                 cross_1kb   = 1'b0
    );
        bp_case_t c;

        c.dir         = dir;
        c.burst       = burst;
        c.len         = len;
        c.offset      = offset;
        c.b_delay     = b_delay;
        c.r_delay     = r_delay;
        c.ahb_waits   = ahb_waits;
        c.error_beats = error_beats;
        c.cross_1kb   = cross_1kb;
        c.label       = $sformatf("%s_%s", label,
                                  (dir == AXI4_READ) ? "RD" : "WR");
        cases.push_back(c);
    endfunction : add_case

    protected function bit [MAX_BEATS-1:0] one_hot(int unsigned beat);
        bit [MAX_BEATS-1:0] mask;

        mask       = '0;
        mask[beat] = 1'b1;
        return mask;
    endfunction : one_hot

    protected function axi4_dir_e dir_of(int unsigned d);
        return (d == 0) ? AXI4_READ : AXI4_WRITE;
    endfunction : dir_of

    // BREADY held low for 1, 2, 3, 8 and 16 cycles (BRG_WAI_002)
    protected function void add_b_window_cases(ref bp_case_t cases[$]);
        int unsigned delays[] = '{1, 2, 3, 8, 16};

        foreach (delays[w])
            add_case(cases, AXI4_WRITE, AXI4_BURST_INCR, 3, 0,
                     delays[w], 1,
                     $sformatf("INCR4_B%0d", delays[w]));
        add_case(cases, AXI4_WRITE, AXI4_BURST_INCR, 0, 0,  1, 1, "SINGLE_B1");
        add_case(cases, AXI4_WRITE, AXI4_BURST_INCR, 0, 0, 16, 1, "SINGLE_B16");
    endfunction : add_b_window_cases

    // RREADY held low for 1, 2, 3, 8 and 16 cycles on every beat (BRG_WAI_003)
    protected function void add_r_window_cases(ref bp_case_t cases[$]);
        int unsigned delays[] = '{1, 2, 3, 8, 16};

        foreach (delays[w])
            add_case(cases, AXI4_READ, AXI4_BURST_INCR, 3, 0,
                     1, delays[w],
                     $sformatf("INCR4_R%0d", delays[w]));
        add_case(cases, AXI4_READ, AXI4_BURST_INCR, 0, 0, 1,  1, "SINGLE_R1");
        add_case(cases, AXI4_READ, AXI4_BURST_INCR, 0, 0, 1, 16, "SINGLE_R16");
    endfunction : add_r_window_cases

    // Every read beat stalled, on every burst shape
    protected function void add_r_shape_cases(ref bp_case_t cases[$]);
        shape_t shapes[] = '{
            '{AXI4_BURST_INCR,  15, 0, 1, "INCR16_R1"},
            '{AXI4_BURST_INCR,  15, 0, 4, "INCR16_R4"},
            '{AXI4_BURST_INCR,   4, 0, 3, "INCR5_R3"},
            '{AXI4_BURST_WRAP,   3, 2, 2, "WRAP4_R2"},
            '{AXI4_BURST_WRAP,   7, 4, 2, "WRAP8_R2"},
            '{AXI4_BURST_FIXED,  2, 0, 2, "FIXED3_R2"}
        };

        foreach (shapes[s])
            add_case(cases, AXI4_READ, shapes[s].burst, shapes[s].len,
                     shapes[s].offset_beats * (1 << FULL_SIZE),
                     1, shapes[s].r_delay, shapes[s].label);
    endfunction : add_r_shape_cases

    // Independent windows: a write stalls only on B, a read only on R
    protected function void add_independent_window_cases(ref bp_case_t cases[$]);
        for (int unsigned d = 0; d < 2; d++) begin
            add_case(cases, dir_of(d), AXI4_BURST_INCR, 3, 0,  1, 16,
                     "INCR4_B1_R16");
            add_case(cases, dir_of(d), AXI4_BURST_INCR, 3, 0, 16,  1,
                     "INCR4_B16_R1");
        end
    endfunction : add_independent_window_cases

    // AXI backpressure together with AHB wait states
    protected function void add_ahb_wait_cases(ref bp_case_t cases[$]);
        add_case(cases, AXI4_WRITE, AXI4_BURST_INCR,  3, 0, 8, 1,
                 "INCR4_B8_HW2",   2);
        add_case(cases, AXI4_READ,  AXI4_BURST_INCR,  3, 0, 1, 8,
                 "INCR4_R8_HW2",   2);
        add_case(cases, AXI4_WRITE, AXI4_BURST_INCR, 15, 0, 2, 1,
                 "INCR16_B2_HW1",  1);
        add_case(cases, AXI4_READ,  AXI4_BURST_INCR, 15, 0, 1, 2,
                 "INCR16_R2_HW1",  1);
    endfunction : add_ahb_wait_cases

    // A SLVERR response must be held unchanged for the whole stall
    protected function void add_error_cases(ref bp_case_t cases[$]);
        add_case(cases, AXI4_WRITE, AXI4_BURST_INCR, 3, 0, 8, 1,
                 "INCR4_B8_ERR1",  0, one_hot(1));
        add_case(cases, AXI4_WRITE, AXI4_BURST_INCR, 0, 0, 16, 1,
                 "SINGLE_B16_ERR0", 0, one_hot(0));
        add_case(cases, AXI4_READ,  AXI4_BURST_INCR, 3, 0, 1, 8,
                 "INCR4_R8_ERR2",  0, one_hot(2));
        add_case(cases, AXI4_READ,  AXI4_BURST_INCR, 3, 0, 1, 4,
                 "INCR4_R4_ERR0",  0, one_hot(0));
    endfunction : add_error_cases

    // INCR16 crossing 1 KB at beat 8, R stalled on every beat
    protected function void add_cross_1kb_cases(ref bp_case_t cases[$]);
        int unsigned bytes;

        bytes = 1 << FULL_SIZE;
        add_case(cases, AXI4_READ,  AXI4_BURST_INCR, 15, 8 * bytes, 1, 4,
                 "INCR16_1KB_R4", 0, '0, 1'b1);
        add_case(cases, AXI4_WRITE, AXI4_BURST_INCR, 15, 8 * bytes, 4, 1,
                 "INCR16_1KB_B4", 0, '0, 1'b1);
    endfunction : add_cross_1kb_cases

    //-------------------------------------------------------------------------
    // Run one case: set the ready windows, plan the AHB beats, send the
    // request, then check the completion and the stall it went through
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, bp_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [AXI4_ADDR_WIDTH-1:0] beat_addr[];
        axi4_transaction          req;
        axi4_transaction          rsp;
        int unsigned              beats;
        int unsigned              case_errors;
        bit                       expect_slverr;
        bit                       failed;

        beats = c.len + 1;
        if (c.cross_1kb) begin
            addr = get_cross_boundary(cross_cases_run) - c.offset;
            cross_cases_run++;
        end else
            addr = base_addr + (index * case_stride) + c.offset;
        get_beat_addresses(addr, c, beats, beat_addr);

        case_errors = 0;
        for (int unsigned i = 0; i < beats; i++)
            if (c.error_beats[i])
                case_errors++;
        expect_slverr = (case_errors > 0);

        `uvm_info(get_type_name(),
                  $sformatf({"[%0d] %s addr=0x%0h beats=%0d bready_delay=%0d ",
                             "rready_delay=%0d ahb_waits=%0d error_beats=0x%0h ",
                             "expected %s"},
                            index, c.label, addr, beats, c.b_delay, c.r_delay,
                            c.ahb_waits, c.error_beats,
                            expect_slverr ? "SLVERR" : "OKAY"),
                  UVM_MEDIUM)

        set_ready_windows(c.b_delay, c.r_delay);

        // One plan entry per expected AHB beat
        policy.clear_plan();
        for (int unsigned i = 0; i < beats; i++)
            policy.add_beat(c.error_beats[i] ? AHB_RESP_ERROR : AHB_RESP_OKAY,
                            c.ahb_waits);

        case_b_cycles  = 0;
        case_r_cycles  = 0;
        case_b_longest = 0;
        case_r_longest = 0;

        req = create_request(c, addr);
        send_axi_request_wait(req, rsp);
        cases_run++;

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

        failed |= check_stall(c, addr);

        if (failed)
            cases_failed++;
    endtask : run_case

    // Set both windows before the request is sent
    protected function void set_ready_windows(
        int unsigned b_delay,
        int unsigned r_delay
    );
        cfg.bready_delay_min = b_delay;
        cfg.bready_delay_max = b_delay;
        cfg.rready_delay_min = r_delay;
        cfg.rready_delay_max = r_delay;
    endfunction : set_ready_windows

    //-------------------------------------------------------------------------
    // Stall checks
    //-------------------------------------------------------------------------
    // The measured stall must be at least the window
    protected function bit check_stall(
        bp_case_t                 c,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        bit failed;

        failed = 1'b0;
        if (c.dir == AXI4_WRITE) begin
            if (case_b_longest < c.b_delay) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s write at 0x%0h: BREADY window %0d ",
                                      "cycles but the longest B stall was %0d"},
                                     c.label, addr, c.b_delay, case_b_longest))
            end
            if (case_r_cycles != 0) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s write at 0x%0h: %0d R stall cycles ",
                                      "on a write request"},
                                     c.label, addr, case_r_cycles))
            end
        end else begin
            if (case_r_longest < c.r_delay) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s read at 0x%0h: RREADY window %0d ",
                                      "cycles but the longest R stall was %0d"},
                                     c.label, addr, c.r_delay, case_r_longest))
            end
            if (case_b_cycles != 0) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s read at 0x%0h: %0d B stall cycles ",
                                      "on a read request"},
                                     c.label, addr, case_b_cycles))
            end
        end

        `uvm_info(get_type_name(),
                  $sformatf({"%s at 0x%0h: b_stall=%0d cycles (longest %0d) ",
                             "r_stall=%0d cycles (longest %0d)"},
                            c.label, addr, case_b_cycles, case_b_longest,
                            case_r_cycles, case_r_longest),
                  UVM_HIGH)
        return failed;
    endfunction : check_stall

    //-------------------------------------------------------------------------
    // Response checks
    //-------------------------------------------------------------------------
    protected function bit check_write_response(
        bp_case_t                 c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp,
        bit                       expect_slverr
    );
        axi4_resp_e expected;

        expected = expect_slverr ? AXI4_RESP_SLVERR : AXI4_RESP_OKAY;
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
        bp_case_t                 c,
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
    // Addresses
    //-------------------------------------------------------------------------
    // k-th 1 KB boundary above the case regions, skipping 4 KB boundaries
    protected function bit [AXI4_ADDR_WIDTH-1:0] get_cross_boundary(
        int unsigned k
    );
        bit [AXI4_ADDR_WIDTH-1:0] boundary;
        int unsigned              found;

        boundary = base_addr + (num_cases * case_stride);
        boundary = ((boundary >> 10) + 1) << 10;
        found    = 0;
        forever begin
            if ((boundary % 'h1000) != 0) begin
                if (found == k)
                    return boundary;
                found++;
            end
            boundary += 'h400;
        end
    endfunction : get_cross_boundary

    // Beat addresses (AXI burst address rules)
    protected function void get_beat_addresses(
        input  bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        input  bp_case_t                 c,
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
        bp_case_t                 c,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;
        int unsigned     req_len;
        axi4_burst_e     req_burst;
        axi4_dir_e       req_dir;

        req_len   = c.len;
        req_burst = c.burst;
        req_dir   = c.dir;
        req = axi4_transaction::type_id::create(
                  $sformatf("bp_%s_%0d",
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
                    req.data[i][8*k +: 8] = 8'hB0 + cases_run * 4 + i * 2 + k;
                req.strb[i] = '1;
            end
        end
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // Each case fits its region; the test must start with non-zero windows
    protected function void validate_knobs();
        int unsigned region_bytes;

        region_bytes = MAX_BEATS * AXI4_STRB_WIDTH;
        if ((case_stride < region_bytes) ||
            ((case_stride % region_bytes) != 0))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be a non-zero multiple of %0d bytes",
                                 region_bytes))
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
        if ((cfg.bready_delay_max == 0) && (cfg.bready_delay_min == 0))
            `uvm_fatal(get_type_name(),
                       "bready_delay_max must be non-zero before the test starts")
        if ((cfg.rready_delay_max == 0) && (cfg.rready_delay_min == 0))
            `uvm_fatal(get_type_name(),
                       "rready_delay_max must be non-zero before the test starts")
    endfunction : validate_knobs

endclass : axi4_mst_backpressure_seq