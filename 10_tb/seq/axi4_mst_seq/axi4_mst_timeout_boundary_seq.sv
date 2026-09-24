//=============================================================================
// File        : axi4_mst_timeout_boundary_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : C_DPHASE_TIMEOUT threshold boundary sequence.
//               BRG_TMO_003 asks that an AHB completion one clock before, on
//               and one clock after the programmed threshold is distinguished
//               correctly. Rather than assume where that boundary sits, the
//               sequence sweeps the AHB wait of a single transfer across a
//               window around C_DPHASE_TIMEOUT and measures the smallest wait
//               that the watchdog terminates. The three cases the plan names
//               are the measured threshold and its two neighbours, which the
//               sweep always contains.
//               The threshold is derived from the reference design as
//               C_DPHASE_TIMEOUT plus a small fixed offset: time_out.sv loads
//               C_DPHASE_TIMEOUT-1 into counter_f and counts one step per
//               HREADY-low cycle, the borrow out of the counter is registered
//               into timeout_o, and axi_slv_if registers that again into
//               timeout_inprogress. The offset is therefore a property of the
//               pipeline, not of the value, so it must be the same on every
//               build; the sequence reports it and, once EXPECT_OFFSET is
//               given, requires it.
//               What is checked on every run:
//               - the response is monotonic in the wait: no transfer
//                 completes at a wait longer than one that timed out
//               - the window brackets the threshold, so the measurement is
//                 not an artefact of a window that is too narrow
//               - read and write measure the same threshold, since they share
//                 one watchdog
//               - the threshold scales with C_DPHASE_TIMEOUT and stays inside
//                 the window around it
//               - with EXPECT_OFFSET set, the threshold is exactly
//                 C_DPHASE_TIMEOUT + EXPECT_OFFSET
//               Covers BRG_TMO_003.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_timeout_boundary_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_timeout_boundary_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    // Waits swept below and above C_DPHASE_TIMEOUT. Wide enough that the
    // threshold cannot sit outside it on a correct design, narrow enough that
    // the sweep stays short on the 256-cycle build.
    localparam int unsigned WINDOW_BELOW = 3;
    localparam int unsigned WINDOW_ABOVE = 8;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr      = 'h1000;
    int unsigned              case_stride    = 'h100;
    int unsigned              dphase_timeout = 0;

    // Expected threshold, as an offset from C_DPHASE_TIMEOUT. Left unset the
    // sequence measures and reports it instead of requiring a value.
    bit                       has_expected_offset;
    int                       expected_offset;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    ahb_response_policy policy;
    scoreboard          scb;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned timeouts_seen;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    // timed_out[dir][k] for the k-th wait of the sweep
    protected bit          observed_timeout[2][$];
    protected int unsigned measured_threshold[2];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_timeout_boundary_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        int unsigned index;

        if (policy == null)
            `uvm_fatal(get_type_name(), "Response policy is null")
        if (scb == null)
            `uvm_fatal(get_type_name(), "Boundary sweep needs the scoreboard")

        wait_reset_release();
        validate_knobs();

        `uvm_info(get_type_name(),
                  $sformatf({"Boundary sweep: C_DPHASE_TIMEOUT=%0d, waits ",
                             "%0d to %0d, read and write"},
                            dphase_timeout, first_wait(), last_wait()),
                  UVM_LOW)

        index = 0;
        for (int unsigned d = 0; d < 2; d++) begin
            observed_timeout[d].delete();
            for (int unsigned w = first_wait(); w <= last_wait(); w++) begin
                bit timed_out;

                run_case(index, dir_of(d), w, timed_out);
                observed_timeout[d].push_back(timed_out);
                index++;
            end
        end

        for (int unsigned d = 0; d < 2; d++)
            measured_threshold[d] = measure_threshold(dir_of(d));
        check_thresholds();

        `uvm_info(get_type_name(),
                  $sformatf({"Boundary summary: dphase_timeout=%0d run=%0d ",
                             "failed=%0d timeouts_seen=%0d ",
                             "threshold_rd=%0d threshold_wr=%0d offset=%0d"},
                            dphase_timeout, cases_run, cases_failed,
                            timeouts_seen, measured_threshold[0],
                            measured_threshold[1],
                            int'(measured_threshold[1]) - int'(dphase_timeout)),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Sweep window
    //-------------------------------------------------------------------------
    protected function int unsigned first_wait();
        return dphase_timeout - WINDOW_BELOW;
    endfunction : first_wait

    protected function int unsigned last_wait();
        return dphase_timeout + WINDOW_ABOVE;
    endfunction : last_wait

    protected function axi4_dir_e dir_of(int unsigned d);
        return (d == 0) ? AXI4_READ : AXI4_WRITE;
    endfunction : dir_of

    //-------------------------------------------------------------------------
    // Run one sweep point: a single full-width transfer whose one AHB beat is
    // held off for 'ahb_wait' cycles. Returns whether the watchdog took it.
    //-------------------------------------------------------------------------
    protected function bit beat_timed_out(axi4_transaction rsp);
        if (rsp.dir == AXI4_WRITE)
            return (rsp.bresp == AXI4_RESP_SLVERR);
        foreach (rsp.rresp[i])
            if (rsp.rresp[i] == AXI4_RESP_SLVERR)
                return 1'b1;
        return 1'b0;
    endfunction : beat_timed_out

    protected task run_case(
        input  int unsigned index,
        input  axi4_dir_e   dir,
        input  int unsigned ahb_wait,
        output bit          timed_out
    );
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          req;
        axi4_transaction          rsp;
        bit                       failed;

        addr = base_addr + (index * case_stride);

        policy.clear_plan();
        policy.add_beat(AHB_RESP_OKAY, ahb_wait);

        req = create_request(dir, addr, index);
        // Either side of the threshold is legal here, so the scoreboard is
        // told the request may time out rather than that it must
        scb.allow_timeout(dir, req.id);

        send_axi_request_wait(req, rsp);
        cases_run++;

        timed_out = beat_timed_out(rsp);
        failed    = 1'b0;
        if (timed_out) begin
            timeouts_seen++;
            policy.clear_plan();
        end else begin
            failed = check_completed(dir, addr, ahb_wait, rsp);
            if (policy.pending_beats() != 0) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"wait=%0d %s at 0x%0h: the AHB beat was ",
                                      "never issued although the transfer ",
                                      "completed"},
                                     ahb_wait, dir.name(), addr))
                policy.clear_plan();
            end
        end

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s wait=%0d addr=0x%0h -> %s",
                            index, dir.name(), ahb_wait, addr,
                            timed_out ? "SLVERR" : "OKAY"),
                  UVM_MEDIUM)

        if (failed)
            cases_failed++;

        // Let the slave finish counting out the wait of an abandoned beat
        // before the next sweep point starts
        if (timed_out)
            wait_cycles(ahb_wait + 16);
    endtask : run_case

    protected function bit check_completed(
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              ahb_wait,
        axi4_transaction          rsp
    );
        if (dir == AXI4_WRITE) begin
            if (rsp.bresp != AXI4_RESP_OKAY) begin
                `uvm_error(get_type_name(),
                           $sformatf("wait=%0d write at 0x%0h: BRESP=%s",
                                     ahb_wait, addr, rsp.bresp.name()))
                return 1'b1;
            end
            return 1'b0;
        end

        if (rsp.data.size() != 1) begin
            `uvm_error(get_type_name(),
                       $sformatf("wait=%0d read at 0x%0h: %0d beats, expected 1",
                                 ahb_wait, addr, rsp.data.size()))
            return 1'b1;
        end
        if (rsp.data[0] !== policy.read_data(addr)) begin
            `uvm_error(get_type_name(),
                       $sformatf({"wait=%0d read at 0x%0h: expected=0x%0h ",
                                  "actual=0x%0h"},
                                 ahb_wait, addr, policy.read_data(addr),
                                 rsp.data[0]))
            return 1'b1;
        end
        return 1'b0;
    endfunction : check_completed

    //-------------------------------------------------------------------------
    // Threshold measurement
    //-------------------------------------------------------------------------
    // Smallest wait that timed out. Also proves the response is monotonic in
    // the wait: a watchdog that let a longer wait through after terminating a
    // shorter one would not have a threshold at all.
    protected function int unsigned measure_threshold(axi4_dir_e dir);
        int unsigned d;
        int unsigned threshold;
        bit          seen_timeout;

        d            = (dir == AXI4_READ) ? 0 : 1;
        threshold    = 0;
        seen_timeout = 1'b0;
        for (int unsigned k = 0; k < observed_timeout[d].size(); k++) begin
            int unsigned wait_cycles_k;

            wait_cycles_k = first_wait() + k;
            if (observed_timeout[d][k]) begin
                if (!seen_timeout) begin
                    threshold    = wait_cycles_k;
                    seen_timeout = 1'b1;
                end
            end else if (seen_timeout) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: wait=%0d completed although ",
                                      "wait=%0d already timed out; the ",
                                      "watchdog is not monotonic"},
                                     dir.name(), wait_cycles_k, threshold))
            end
        end
        return seen_timeout ? threshold : 0;
    endfunction : measure_threshold

    protected function void check_thresholds();
        int unsigned rd;
        int unsigned wr;

        rd = measured_threshold[0];
        wr = measured_threshold[1];

        // The window must bracket the threshold, otherwise the measurement
        // says nothing about where the boundary really is
        for (int unsigned d = 0; d < 2; d++) begin
            axi4_dir_e dir;

            dir = dir_of(d);
            if (measured_threshold[d] == 0) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: no wait up to %0d timed out with ",
                                      "C_DPHASE_TIMEOUT=%0d; widen ",
                                      "WINDOW_ABOVE"},
                                     dir.name(), last_wait(), dphase_timeout))
            end else if (measured_threshold[d] == first_wait()) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: the shortest wait %0d already ",
                                      "timed out with C_DPHASE_TIMEOUT=%0d; ",
                                      "widen WINDOW_BELOW"},
                                     dir.name(), first_wait(), dphase_timeout))
            end
        end

        if ((rd != 0) && (wr != 0) && (rd != wr)) begin
            cases_failed++;
            `uvm_error(get_type_name(),
                       $sformatf({"read and write measure different ",
                                  "thresholds (%0d and %0d) although they ",
                                  "share one watchdog"}, rd, wr))
        end

        if (has_expected_offset && (wr != 0)) begin
            int unsigned expected;

            expected = dphase_timeout + expected_offset;
            if (wr != expected) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf({"threshold is %0d (offset %0d), ",
                                      "expected %0d (offset %0d)"},
                                     wr, int'(wr) - int'(dphase_timeout),
                                     expected, expected_offset))
            end
        end else if (wr != 0) begin
            `uvm_info(get_type_name(),
                      $sformatf({"Measured threshold %0d = C_DPHASE_TIMEOUT ",
                                 "+ offset %0d. Set EXPECT_OFFSET to ",
                                 "require it."},
                                wr, int'(wr) - int'(dphase_timeout)),
                      UVM_LOW)
        end
    endfunction : check_thresholds

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              index
    );
        axi4_transaction req;
        axi4_dir_e       req_dir;

        req_dir = dir;
        req = axi4_transaction::type_id::create(
                  $sformatf("tmob_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", index));
        if (!req.randomize() with {
                dir      == local::req_dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == 0;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed at 0x%0h", addr))

        if (dir == AXI4_WRITE) begin
            for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
                req.data[0][8*k +: 8] = 8'hD0 + index + k;
            req.strb[0] = '1;
        end
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        if (dphase_timeout == 0)
            `uvm_fatal(get_type_name(),
                       {"The boundary sweep needs a build with a watchdog; ",
                        "run it with TIMEOUT=<16|32|64|128|256>"})
        if (!(dphase_timeout inside {16, 32, 64, 128, 256}))
            `uvm_fatal(get_type_name(),
                       $sformatf("Unsupported C_DPHASE_TIMEOUT=%0d",
                                 dphase_timeout))
        if (dphase_timeout <= WINDOW_BELOW)
            `uvm_fatal(get_type_name(),
                       "C_DPHASE_TIMEOUT is too small for the sweep window")
        if ((case_stride < AXI4_STRB_WIDTH) ||
            ((case_stride % AXI4_STRB_WIDTH) != 0))
            `uvm_fatal(get_type_name(),
                       "case_stride must be a non-zero multiple of the bus width")
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
    endfunction : validate_knobs

endclass : axi4_mst_timeout_boundary_seq