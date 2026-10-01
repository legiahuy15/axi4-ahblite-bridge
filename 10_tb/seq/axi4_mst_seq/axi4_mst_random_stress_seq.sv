//=============================================================================
// File        : axi4_mst_random_stress_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Constrained-random traffic with an independent AHB
//               wait/error policy.
//               - legal profile only: normal lock, contiguous strobes, narrow
//                 sizes only on the narrow build, no AW-before-W
//               - the first twelve requests cover every burst type
//               - timeout builds: waits capped below the threshold; every
//                 timeout_every-th request holds its last beat past it and
//                 is declared with expect_timeout
//               - read data and responses are checked against the drawn plan
//               Covers BRG_ENV_008 and BRG_UNS_003.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_random_stress_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_random_stress_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BUS_BYTES = AXI4_STRB_WIDTH;

    // Covers SINGLE, INCR4/8/16 and WRAP4/8/16
    localparam int unsigned MAX_LEN = 15;

    // Directed head of the run: every burst type in both directions
    localparam int unsigned SEEDED_CASES = 12;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h4000;
    int unsigned              window_bytes  = 'h4000;
    int unsigned              num_requests  = 64;
    int unsigned              error_percent = 12;
    int unsigned              max_wait      = 4;
    bit                       supports_narrow;

    // C_DPHASE_TIMEOUT of the DUT (0 = no watchdog)
    int unsigned              dphase_timeout;
    int unsigned              timeout_every   = 8;
    // Hold beyond C_DPHASE_TIMEOUT for a declared timeout
    int unsigned              timeout_overshoot = 16;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    ahb_response_policy policy;
    // Needed only on a watchdog build, to declare the deliberate timeouts
    scoreboard          scb;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned requests_run;
    int unsigned requests_failed;
    int unsigned reads_run;
    int unsigned writes_run;
    int unsigned fixed_run;
    int unsigned incr_run;
    int unsigned wrap_run;
    int unsigned narrow_run;
    // Requests whose address is not bus aligned
    int unsigned lane_offset_run;
    int unsigned w_before_aw_run;
    int unsigned beats_run;
    int unsigned error_beats_planned;
    int unsigned wait_beats_planned;
    int unsigned slverr_responses;
    int unsigned okay_responses;
    int unsigned timeout_cases;
    int unsigned timeout_beats;   // beats planned for those, issued or not

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    // The plan drawn for the request in flight, one entry per beat
    protected ahb_resp_e   beat_resp[$];
    protected int unsigned beat_wait[$];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_random_stress_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (policy == null)
            `uvm_fatal(get_type_name(), "Response policy is null")
        if (!cfg.return_responses)
            `uvm_fatal(get_type_name(),
                       "The random oracle needs return_responses")
        if ((dphase_timeout != 0) && (scb == null))
            `uvm_fatal(get_type_name(),
                       {"A watchdog build needs the scoreboard handle, so ",
                        "the deliberate timeouts can be declared"})

        validate_knobs();
        wait_reset_release();

        `uvm_info(get_type_name(),
                  $sformatf({"Random stress: %0d requests, window 0x%0h..",
                             "0x%0h, error=%0d%% max_wait=%0d narrow=%0b ",
                             "C_DPHASE_TIMEOUT=%0d"},
                            num_requests, base_addr,
                            base_addr + window_bytes - 1, error_percent,
                            max_wait, supports_narrow, dphase_timeout),
                  UVM_LOW)

        for (int unsigned i = 0; i < num_requests; i++)
            run_request(i);

        check_run_was_varied();

        `uvm_info(get_type_name(),
                  $sformatf({"Random stress summary: run=%0d failed=%0d ",
                             "rd=%0d wr=%0d fixed=%0d incr=%0d wrap=%0d ",
                             "narrow=%0d lane_offset=%0d w_before_aw=%0d ",
                             "beats=%0d error_beats=%0d wait_beats=%0d ",
                             "slverr=%0d okay=%0d timeout_cases=%0d ",
                             "timeout_beats=%0d"},
                            requests_run, requests_failed, reads_run,
                            writes_run, fixed_run, incr_run, wrap_run,
                            narrow_run, lane_offset_run, w_before_aw_run,
                            beats_run, error_beats_planned,
                            wait_beats_planned, slverr_responses,
                            okay_responses, timeout_cases, timeout_beats),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // One request
    //-------------------------------------------------------------------------
    protected task run_request(int unsigned index);
        axi4_transaction req;
        axi4_transaction rsp;
        bit              failed;
        bit              timeout_case;

        timeout_case = is_timeout_case(index);
        req = build_request(index);
        draw_plan(int'(req.len) + 1, timeout_case);
        load_policy();

        // Declare before the request is predicted
        if (timeout_case)
            scb.expect_timeout(req.dir, req.id);

        send_axi_request(req);
        get_response(rsp, req.get_transaction_id());
        if (rsp == null)
            `uvm_fatal(get_type_name(),
                       $sformatf("Request %0d returned a null response",
                                 index))

        requests_run++;
        count_shape(req);

        if (timeout_case) begin
            failed = check_timeout_response(index, req, rsp);
            // Remaining beats are never issued
            policy.clear_plan();
            wait_cycles(dphase_timeout + timeout_overshoot + 16);
        end else begin
            failed = check_response(index, req, rsp);
            if (policy.pending_beats() != 0) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"Request %0d: %0d planned AHB beats ",
                                      "were never issued"},
                                     index, policy.pending_beats()))
                policy.clear_plan();
            end
        end

        if (failed)
            requests_failed++;
    endtask : run_request

    // Never inside the seeded head
    protected function bit is_timeout_case(int unsigned index);
        if ((dphase_timeout == 0) || (timeout_every == 0))
            return 1'b0;
        if (index < SEEDED_CASES)
            return 1'b0;
        return (((index - SEEDED_CASES) % timeout_every) == 0);
    endfunction : is_timeout_case

    //-------------------------------------------------------------------------
    // Independent AHB answer policy
    //-------------------------------------------------------------------------
    // Drawn independently of the request (only the beat count is used)
    protected function void draw_plan(int unsigned beats, bit timeout_case);
        int unsigned safe_wait;
        int unsigned hang_beat;

        beat_resp.delete();
        beat_wait.delete();

        // Declared timeout: all beats OKAY, last beat held past the
        // threshold (a middle beat would let HWDATA move on after the timeout)
        if (timeout_case) begin
            hang_beat = beats - 1;
            for (int unsigned i = 0; i < beats; i++) begin
                beat_resp.push_back(AHB_RESP_OKAY);
                beat_wait.push_back((i == hang_beat) ?
                                    (dphase_timeout + timeout_overshoot) : 0);
                beats_run++;
                timeout_beats++;
            end
            timeout_cases++;
            return;
        end

        // Keep ordinary waits 4 cycles below the threshold (ERROR adds one)
        safe_wait = max_wait;
        if ((dphase_timeout != 0) && (safe_wait > (dphase_timeout - 4)))
            safe_wait = dphase_timeout - 4;

        for (int unsigned i = 0; i < beats; i++) begin
            ahb_resp_e   resp;
            int unsigned waits;

            resp = ($urandom_range(99, 0) < error_percent) ? AHB_RESP_ERROR
                                                           : AHB_RESP_OKAY;
            // Mostly zero wait
            waits = ($urandom_range(2, 0) == 0) ?
                        $urandom_range(safe_wait, 1) : 0;
            beat_resp.push_back(resp);
            beat_wait.push_back(waits);

            if (resp == AHB_RESP_ERROR)
                error_beats_planned++;
            if (waits != 0)
                wait_beats_planned++;
            beats_run++;
        end
    endfunction : draw_plan

    protected function void load_policy();
        policy.clear_plan();
        foreach (beat_resp[i])
            policy.add_beat(beat_resp[i], beat_wait[i]);
    endfunction : load_policy

    protected function bit plan_has_error();
        foreach (beat_resp[i])
            if (beat_resp[i] == AHB_RESP_ERROR)
                return 1'b1;
        return 1'b0;
    endfunction : plan_has_error

    //-------------------------------------------------------------------------
    // Checks
    //-------------------------------------------------------------------------
    protected function bit check_response(
        int unsigned     index,
        axi4_transaction req,
        axi4_transaction rsp
    );
        bit failed;

        failed = 1'b0;
        if (req.dir == AXI4_WRITE)
            failed |= check_write_response(index, req, rsp);
        else
            failed |= check_read_response(index, req, rsp);
        return failed;
    endfunction : check_response

    // Declared timeout: only SLVERR is checked
    protected function bit check_timeout_response(
        int unsigned     index,
        axi4_transaction req,
        axi4_transaction rsp
    );
        bit saw_slverr;

        saw_slverr = 1'b0;
        if (req.dir == AXI4_WRITE) begin
            saw_slverr = (rsp.bresp == AXI4_RESP_SLVERR);
        end else begin
            foreach (rsp.rresp[i])
                if (rsp.rresp[i] == AXI4_RESP_SLVERR)
                    saw_slverr = 1'b1;
        end

        if (!saw_slverr) begin
            `uvm_error(get_type_name(),
                       $sformatf({"Request %0d: a beat was held %0d cycles ",
                                  "with C_DPHASE_TIMEOUT=%0d, but the %s at ",
                                  "0x%0h came back without SLVERR"},
                                 index, dphase_timeout + timeout_overshoot,
                                 dphase_timeout, req.dir.name(), req.addr))
            return 1'b1;
        end
        slverr_responses++;
        return 1'b0;
    endfunction : check_timeout_response

    protected function bit check_write_response(
        int unsigned     index,
        axi4_transaction req,
        axi4_transaction rsp
    );
        axi4_resp_e expected;

        expected = plan_has_error() ? AXI4_RESP_SLVERR : AXI4_RESP_OKAY;
        if (rsp.bresp == AXI4_RESP_SLVERR)
            slverr_responses++;
        else if (rsp.bresp == AXI4_RESP_OKAY)
            okay_responses++;

        if (rsp.bresp != expected) begin
            `uvm_error(get_type_name(),
                       $sformatf({"Request %0d: write at 0x%0h returned %s, ",
                                  "expected %s for a plan with %0d ERROR ",
                                  "beat(s)"},
                                 index, req.addr, rsp.bresp.name(),
                                 expected.name(), count_plan_errors()))
            return 1'b1;
        end
        return 1'b0;
    endfunction : check_write_response

    protected function bit check_read_response(
        int unsigned     index,
        axi4_transaction req,
        axi4_transaction rsp
    );
        bit failed;

        failed = 1'b0;
        if (rsp.data.size() != (int'(req.len) + 1)) begin
            `uvm_error(get_type_name(),
                       $sformatf({"Request %0d: read at 0x%0h returned %0d ",
                                  "beats, expected %0d"},
                                 index, req.addr, rsp.data.size(),
                                 int'(req.len) + 1))
            return 1'b1;
        end
        // Plan size must equal the beat count
        if (rsp.rresp.size() != beat_resp.size()) begin
            `uvm_error(get_type_name(),
                       $sformatf({"Request %0d: %0d read responses against a ",
                                  "plan of %0d beats"},
                                 index, rsp.rresp.size(), beat_resp.size()))
            return 1'b1;
        end

        foreach (rsp.rresp[beat]) begin
            axi4_resp_e               expected;
            bit [AXI4_ADDR_WIDTH-1:0] addr;

            expected = (beat_resp[beat] == AHB_RESP_ERROR) ? AXI4_RESP_SLVERR
                                                           : AXI4_RESP_OKAY;
            addr     = beat_address(req, beat);

            if (rsp.rresp[beat] == AXI4_RESP_SLVERR)
                slverr_responses++;
            else if (rsp.rresp[beat] == AXI4_RESP_OKAY)
                okay_responses++;

            if (rsp.rresp[beat] != expected) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"Request %0d: read at 0x%0h beat %0d ",
                                      "returned %s, but its AHB beat was ",
                                      "answered with %s"},
                                     index, req.addr, beat,
                                     rsp.rresp[beat].name(),
                                     beat_resp[beat].name()))
            end else if ((expected == AXI4_RESP_OKAY) &&
                         (rsp.data[beat] !== policy.read_data(addr))) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"Request %0d: read beat %0d at 0x%0h ",
                                      "returned 0x%0h, expected 0x%0h"},
                                     index, beat, addr, rsp.data[beat],
                                     policy.read_data(addr)))
            end
        end
        return failed;
    endfunction : check_read_response

    protected function int unsigned count_plan_errors();
        int unsigned total;

        total = 0;
        foreach (beat_resp[i])
            if (beat_resp[i] == AHB_RESP_ERROR)
                total++;
        return total;
    endfunction : count_plan_errors

    // Variety checks (shapes are guaranteed by the seeded head)
    protected function void check_run_was_varied();
        if (requests_run != num_requests)
            `uvm_error(get_type_name(),
                       $sformatf("Only %0d of %0d requests completed",
                                 requests_run, num_requests))
        if ((reads_run == 0) || (writes_run == 0))
            `uvm_error(get_type_name(),
                       $sformatf("One direction was never sent: rd=%0d wr=%0d",
                                 reads_run, writes_run))
        if ((fixed_run == 0) || (incr_run == 0) || (wrap_run == 0))
            `uvm_error(get_type_name(),
                       $sformatf({"A burst type was never sent: fixed=%0d ",
                                  "incr=%0d wrap=%0d"},
                                 fixed_run, incr_run, wrap_run))
        if (error_beats_planned == 0)
            `uvm_error(get_type_name(),
                       {"The policy never injected an AHB ERROR, so the ",
                        "error path was not stressed"})
        if (wait_beats_planned == 0)
            `uvm_error(get_type_name(),
                       {"The policy never injected a wait state, so the ",
                        "wait path was not stressed"})
        if (slverr_responses == 0)
            `uvm_error(get_type_name(),
                       {"No SLVERR reached the AXI master although the ",
                        "policy injected AHB errors"})
        if (okay_responses == 0)
            `uvm_error(get_type_name(), "No OKAY response was observed")
        // A watchdog build must have fired the watchdog
        if ((dphase_timeout != 0) && (timeout_cases == 0))
            `uvm_error(get_type_name(),
                       $sformatf({"Built with C_DPHASE_TIMEOUT=%0d but no ",
                                  "request was made to trip the watchdog"},
                                 dphase_timeout))
        if ((dphase_timeout == 0) && (timeout_cases != 0))
            `uvm_error(get_type_name(),
                       "Timeout cases were run on a build with no watchdog")
        if (supports_narrow && (narrow_run == 0))
            `uvm_error(get_type_name(),
                       {"The build supports narrow bursts but every request ",
                        "was full width"})
        if (!supports_narrow && (narrow_run != 0))
            `uvm_error(get_type_name(),
                       {"A narrow request was sent on a build that does not ",
                        "support narrow bursts"})
    endfunction : check_run_was_varied

    //-------------------------------------------------------------------------
    // Request construction
    //-------------------------------------------------------------------------
    // Only the legal profile is pinned; the rest is left to the solver
    protected function axi4_transaction build_request(int unsigned index);
        axi4_transaction          req;
        int unsigned              chosen_size;
        int unsigned              bytes;
        int unsigned              max_len;
        bit [AXI4_ADDR_WIDTH-1:0] window_hi;
        bit                       seeded;
        axi4_dir_e                seed_dir;
        axi4_burst_e              seed_burst;

        max_len = MAX_LEN;

        // A narrow size only where the build supports narrow bursts
        if (supports_narrow)
            chosen_size = $urandom_range(FULL_SIZE, 0);
        else
            chosen_size = FULL_SIZE;
        bytes     = 1 << chosen_size;
        window_hi = base_addr + window_bytes - 1;

        seeded     = (index < SEEDED_CASES);
        seed_dir   = ((index % 2) == 0) ? AXI4_READ : AXI4_WRITE;
        seed_burst = seed_burst_of(index);

        req = axi4_transaction::type_id::create(
                  $sformatf("stress_%0d", index));
        if (!req.randomize() with {
                len   <= local::max_len;
                size  == axi4_size_e'(local::chosen_size);
                lock  == AXI4_LOCK_NORMAL;
                // Address always suits the size
                (addr % local::bytes) == 0;
                addr >= local::base_addr;
                addr <= local::window_hi;
                // AW before W deadlocks on this DUT
                wr_order != AXI4_WR_AW_BEFORE_W;
                (dir == AXI4_READ) -> wr_order == AXI4_WR_PARALLEL;
                wr_order dist { AXI4_WR_PARALLEL    := 80,
                                AXI4_WR_W_BEFORE_AW := 20 };
                if (local::seeded) {
                    dir   == local::seed_dir;
                    burst == local::seed_burst;
                }
            })
            `uvm_fatal(get_type_name(),
                       $sformatf({"Randomization failed for request %0d ",
                                  "(size=%0d seeded=%0b)"},
                                 index, chosen_size, seeded))

        if (req.dir == AXI4_WRITE)
            fill_write_payload(req, index);
        return req;
    endfunction : build_request

    // Read/write crossed with FIXED, INCR and WRAP over the first twelve
    protected function axi4_burst_e seed_burst_of(int unsigned index);
        case ((index / 2) % 3)
            0:       return AXI4_BURST_INCR;
            1:       return AXI4_BURST_FIXED;
            default: return AXI4_BURST_WRAP;
        endcase
    endfunction : seed_burst_of

    // The lanes the address and size select, never a sparse pattern
    protected function void fill_write_payload(
        axi4_transaction req,
        int unsigned     index
    );
        int unsigned bytes;

        bytes = 1 << int'(req.size);
        foreach (req.data[beat]) begin
            bit [AXI4_ADDR_WIDTH-1:0] addr;
            int unsigned              lane_offset;

            addr        = beat_address(req, beat);
            lane_offset = addr % BUS_BYTES;

            req.strb[beat] = '0;
            for (int unsigned k = 0; k < bytes; k++)
                req.strb[beat][lane_offset + k] = 1'b1;

            req.data[beat] = '0;
            for (int unsigned k = 0; k < bytes; k++)
                req.data[beat][8 * (lane_offset + k) +: 8] =
                    8'(8'h20 + (index * 7) + (beat * 5) + (k * 3));
        end
    endfunction : fill_write_payload

    //-------------------------------------------------------------------------
    // Address of one beat
    //-------------------------------------------------------------------------
    protected function bit [AXI4_ADDR_WIDTH-1:0] beat_address(
        axi4_transaction req,
        int unsigned     beat
    );
        int unsigned              bytes;
        bit [AXI4_ADDR_WIDTH-1:0] aligned;

        bytes   = 1 << int'(req.size);
        aligned = req.addr - (req.addr % bytes);

        case (req.burst)
            AXI4_BURST_FIXED:
                return aligned;

            AXI4_BURST_WRAP: begin
                int unsigned              span;
                bit [AXI4_ADDR_WIDTH-1:0] wrap_base;

                span      = (int'(req.len) + 1) * bytes;
                wrap_base = aligned - (aligned % span);
                return wrap_base +
                       ((aligned - wrap_base + (beat * bytes)) % span);
            end

            default:
                return aligned + (beat * bytes);
        endcase
    endfunction : beat_address

    //-------------------------------------------------------------------------
    // Shape accounting
    //-------------------------------------------------------------------------
    protected function void count_shape(axi4_transaction req);
        if (req.dir == AXI4_WRITE)
            writes_run++;
        else
            reads_run++;

        case (req.burst)
            AXI4_BURST_FIXED: fixed_run++;
            AXI4_BURST_WRAP:  wrap_run++;
            default:          incr_run++;
        endcase

        if ((1 << int'(req.size)) < BUS_BYTES)
            narrow_run++;
        if ((req.addr % BUS_BYTES) != 0)
            lane_offset_run++;
        if (req.wr_order == AXI4_WR_W_BEFORE_AW)
            w_before_aw_run++;
    endfunction : count_shape

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // Window must hold the longest burst; waits stay below the smallest
    // timeout
    protected function void validate_knobs();
        int unsigned max_bytes;

        max_bytes = (MAX_LEN + 1) * BUS_BYTES;
        if (window_bytes < (4 * max_bytes))
            `uvm_fatal(get_type_name(),
                       $sformatf("window_bytes must be at least %0d bytes",
                                 4 * max_bytes))
        if ((base_addr % 4096) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be 4 KB aligned")
        if (num_requests < SEEDED_CASES)
            `uvm_fatal(get_type_name(),
                       $sformatf("num_requests must be at least %0d",
                                 SEEDED_CASES))
        if (error_percent > 90)
            `uvm_fatal(get_type_name(),
                       "error_percent must leave room for OKAY traffic")
        if ((max_wait == 0) || (max_wait > 8))
            `uvm_fatal(get_type_name(),
                       "max_wait must be between 1 and 8")
        // The wait cap (dphase_timeout - 2) must leave a usable value
        if ((dphase_timeout != 0) && (dphase_timeout < 6))
            `uvm_fatal(get_type_name(),
                       $sformatf({"C_DPHASE_TIMEOUT=%0d is too small to keep ",
                                  "ordinary traffic clear of the watchdog"},
                                 dphase_timeout))
        if ((dphase_timeout != 0) && (timeout_overshoot < 8))
            `uvm_fatal(get_type_name(),
                       $sformatf({"timeout_overshoot=%0d does not clear the ",
                                  "threshold of C_DPHASE_TIMEOUT plus one or ",
                                  "two cycles with any margin"},
                                 timeout_overshoot))
    endfunction : validate_knobs

endclass : axi4_mst_random_stress_seq