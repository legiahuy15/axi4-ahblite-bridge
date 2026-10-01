//=============================================================================
// File        : axi4_mst_timeout_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Timeout sequence, for every C_DPHASE_TIMEOUT build:
//               - 0: a very long AHB wait completes with OKAY (BRG_TMO_001)
//               - N: a wait below N completes, above N returns SLVERR, on a
//                 single and an INCR4, read and write (BRG_TMO_002)
//               Checks responses, beat count and the traffic afterwards.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_timeout_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_timeout_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    // Longer than the largest supported threshold, so the watchdog would fire
    // on any non-zero build and the run proves it really is generated away
    localparam int unsigned DISABLED_WAIT = 512;

    // Margins around the threshold. The exact boundary belongs to
    // bridge_timeout_boundary_test, so these stay clear of it.
    localparam int unsigned UNDER_MARGIN = 4;
    localparam int unsigned OVER_MARGIN  = 32;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr      = 'h1000;
    int unsigned              case_stride    = 'h100;
    int unsigned              dphase_timeout = 0;

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
    int unsigned long_waits_completed;
    int unsigned cancelled_beats;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_dir_e   dir;
        int unsigned len;          // AXI AxLEN value (beats-1)
        int unsigned stall_beat;   // beat whose AHB data phase is held off
        int unsigned ahb_wait;     // HREADY-low cycles on that beat
        bit          expect_tmo;   // the watchdog is expected to abandon it
        string       label;
    } tmo_case_t;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected tmo_case_t case_list[$];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_timeout_seq");
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
        build_cases();

        `uvm_info(get_type_name(),
                  $sformatf("Timeout: C_DPHASE_TIMEOUT=%0d, %0d cases",
                            dphase_timeout, case_list.size()),
                  UVM_LOW)

        foreach (case_list[i])
            run_case(i, case_list[i]);

        `uvm_info(get_type_name(),
                  $sformatf({"Timeout summary: dphase_timeout=%0d run=%0d ",
                             "failed=%0d timeouts_seen=%0d ",
                             "long_waits_completed=%0d cancelled_beats=%0d ",
                             "ahb_beats=%0d"},
                            dphase_timeout, cases_run, cases_failed,
                            timeouts_seen, long_waits_completed,
                            cancelled_beats, policy.beats_served),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void build_cases();
        if (dphase_timeout == 0)
            build_disabled_cases();
        else
            build_enabled_cases();
    endfunction : build_cases

    protected function void add_case(
        axi4_dir_e   dir,
        int unsigned len,
        int unsigned stall_beat,
        int unsigned ahb_wait,
        bit          expect_tmo,
        string       label
    );
        tmo_case_t c;

        c.dir        = dir;
        c.len        = len;
        c.stall_beat = stall_beat;
        c.ahb_wait   = ahb_wait;
        c.expect_tmo = expect_tmo;
        c.label      = $sformatf("%s_%s", label,
                                 (dir == AXI4_READ) ? "RD" : "WR");
        case_list.push_back(c);
    endfunction : add_case

    // BRG_TMO_001: with the watchdog generated away, a wait longer than every
    // supported threshold must still complete normally
    protected function void build_disabled_cases();
        add_case(AXI4_WRITE, 0, 0, DISABLED_WAIT, 1'b0, "SINGLE_LONGWAIT");
        add_case(AXI4_READ,  0, 0, DISABLED_WAIT, 1'b0, "SINGLE_LONGWAIT");
        add_case(AXI4_WRITE, 3, 1, DISABLED_WAIT, 1'b0, "INCR4_LONGWAIT_B1");
        add_case(AXI4_READ,  3, 2, DISABLED_WAIT, 1'b0, "INCR4_LONGWAIT_B2");
    endfunction : build_disabled_cases

    // BRG_TMO_002: below the threshold the transfer completes, above it the
    // watchdog abandons the data phase, and ordinary traffic works afterwards
    protected function void build_enabled_cases();
        int unsigned under;
        int unsigned over;

        under = dphase_timeout - UNDER_MARGIN;
        over  = dphase_timeout + OVER_MARGIN;

        add_case(AXI4_WRITE, 0, 0, under, 1'b0, "SINGLE_UNDER");
        add_case(AXI4_READ,  0, 0, under, 1'b0, "SINGLE_UNDER");
        add_case(AXI4_WRITE, 3, 1, under, 1'b0, "INCR4_UNDER_B1");
        add_case(AXI4_READ,  3, 2, under, 1'b0, "INCR4_UNDER_B2");

        add_case(AXI4_WRITE, 0, 0, over, 1'b1, "SINGLE_OVER");
        add_case(AXI4_READ,  0, 0, over, 1'b1, "SINGLE_OVER");
        add_case(AXI4_WRITE, 3, 1, over, 1'b1, "INCR4_OVER_B1");
        add_case(AXI4_READ,  3, 2, over, 1'b1, "INCR4_OVER_B2");

        // The watchdog must not leave the bridge stuck
        add_case(AXI4_WRITE, 3, 0, 0, 1'b0, "RECOVER_INCR4");
        add_case(AXI4_READ,  3, 0, 0, 1'b0, "RECOVER_INCR4");
    endfunction : build_enabled_cases

    //-------------------------------------------------------------------------
    // Run one case
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, tmo_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          req;
        axi4_transaction          rsp;
        int unsigned              beats;
        int unsigned              leftover;
        bit                       failed;

        beats = c.len + 1;
        addr  = base_addr + (index * case_stride);

        `uvm_info(get_type_name(),
                  $sformatf({"[%0d] %s addr=0x%0h beats=%0d stall_beat=%0d ",
                             "ahb_wait=%0d expected %s"},
                            index, c.label, addr, beats, c.stall_beat,
                            c.ahb_wait, c.expect_tmo ? "SLVERR" : "OKAY"),
                  UVM_MEDIUM)

        // One plan entry per predicted AHB beat; only the stalled beat waits
        policy.clear_plan();
        for (int unsigned i = 0; i < beats; i++)
            policy.add_beat(AHB_RESP_OKAY,
                            (i == c.stall_beat) ? c.ahb_wait : 0);

        req = create_request(c, addr);

        // Declared before the request is sent, so the scoreboard never treats
        // the cancelled beats or the forced SLVERR as a bridge fault
        if (c.expect_tmo) begin
            if (scb == null)
                `uvm_fatal(get_type_name(),
                           "A timeout case needs the scoreboard handle")
            scb.expect_timeout(c.dir, req.id);
        end

        send_axi_request_wait(req, rsp);
        cases_run++;

        failed = 1'b0;
        if (c.dir == AXI4_WRITE)
            failed |= check_write(c, addr, rsp);
        else
            failed |= check_read(c, addr, beats, rsp);

        // An abandoned burst leaves the beats the bridge never issued in the
        // plan. They are counted, not reported as an error.
        leftover = policy.pending_beats();
        if (c.expect_tmo) begin
            cancelled_beats += leftover;
            policy.clear_plan();
        end else if (leftover != 0) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s at 0x%0h: %0d AHB beats were never ",
                                  "issued although no timeout was expected"},
                                 c.label, addr, leftover))
            policy.clear_plan();
        end

        if (failed)
            cases_failed++;

        // Let the slave finish the abandoned wait before the next case
        if (c.expect_tmo)
            wait_cycles(c.ahb_wait + 16);
    endtask : run_case

    //-------------------------------------------------------------------------
    // Response checks
    //-------------------------------------------------------------------------
    protected function bit check_write(
        tmo_case_t                c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp
    );
        axi4_resp_e expected;

        expected = c.expect_tmo ? AXI4_RESP_SLVERR : AXI4_RESP_OKAY;
        if (rsp.bresp != expected) begin
            `uvm_error(get_type_name(),
                       $sformatf({"%s write at 0x%0h: BRESP=%s, expected %s ",
                                  "(C_DPHASE_TIMEOUT=%0d, AHB wait=%0d)"},
                                 c.label, addr, rsp.bresp.name(),
                                 expected.name(), dphase_timeout, c.ahb_wait))
            return 1'b1;
        end
        if (c.expect_tmo)
            timeouts_seen++;
        else if (c.ahb_wait > 0)
            long_waits_completed++;
        return 1'b0;
    endfunction : check_write

    // Abandoned read: ARLEN+1 beats, SLVERR from the timed-out beat on;
    // data is checked only before it
    protected function bit check_read(
        tmo_case_t                c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              beats,
        axi4_transaction          rsp
    );
        bit          failed;
        bit          seen_slverr;
        int unsigned slverr_beats;

        failed = 1'b0;
        if ((rsp.data.size() != beats) || (rsp.rresp.size() != beats)) begin
            `uvm_error(get_type_name(),
                       $sformatf({"%s read at 0x%0h: beat count expected=%0d ",
                                  "actual=%0d"},
                                 c.label, addr, beats, rsp.data.size()))
            return 1'b1;
        end

        seen_slverr  = 1'b0;
        slverr_beats = 0;
        foreach (rsp.rresp[i]) begin
            if (rsp.rresp[i] == AXI4_RESP_SLVERR) begin
                seen_slverr = 1'b1;
                slverr_beats++;
                continue;
            end
            // Once the watchdog has fired it stays fired for the rest of the
            // request, so an OKAY beat after a SLVERR beat is a fault
            if (seen_slverr) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s read at 0x%0h beat=%0d: OKAY after ",
                                      "a SLVERR beat"},
                                     c.label, addr, i))
            end
            if (rsp.data[i] !== policy.read_data(addr + (i << FULL_SIZE))) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s read at 0x%0h beat=%0d: ",
                                      "expected=0x%0h actual=0x%0h"},
                                     c.label, addr, i,
                                     policy.read_data(addr + (i << FULL_SIZE)),
                                     rsp.data[i]))
            end
        end

        if (c.expect_tmo) begin
            if (!seen_slverr) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s read at 0x%0h: no SLVERR beat, but ",
                                      "the AHB wait of %0d cycles exceeds ",
                                      "C_DPHASE_TIMEOUT=%0d"},
                                     c.label, addr, c.ahb_wait,
                                     dphase_timeout))
            end else if (rsp.rresp[beats - 1] != AXI4_RESP_SLVERR) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s read at 0x%0h: last beat is OKAY ",
                                      "after a timeout"},
                                     c.label, addr))
            end else begin
                timeouts_seen++;
            end
        end else if (seen_slverr) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s read at 0x%0h: %0d SLVERR beat(s) with ",
                                  "an AHB wait of %0d cycles and ",
                                  "C_DPHASE_TIMEOUT=%0d"},
                                 c.label, addr, slverr_beats, c.ahb_wait,
                                 dphase_timeout))
        end else if (c.ahb_wait > 0) begin
            long_waits_completed++;
        end

        return failed;
    endfunction : check_read

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        tmo_case_t                c,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;
        int unsigned     req_len;
        axi4_dir_e       req_dir;

        req_len = c.len;
        req_dir = c.dir;
        req = axi4_transaction::type_id::create(
                  $sformatf("tmo_%s_%0d",
                            (c.dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::req_dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
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
                    req.data[i][8*k +: 8] = 8'hC0 + cases_run * 4 + i * 2 + k;
                req.strb[i] = '1;
            end
        end
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        int unsigned region_bytes;

        region_bytes = 4 * AXI4_STRB_WIDTH;
        if ((case_stride < region_bytes) ||
            ((case_stride % region_bytes) != 0))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be a non-zero multiple of %0d bytes",
                                 region_bytes))
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
        if (!(dphase_timeout inside {0, 16, 32, 64, 128, 256}))
            `uvm_fatal(get_type_name(),
                       $sformatf("Unsupported C_DPHASE_TIMEOUT=%0d",
                                 dphase_timeout))
        if ((dphase_timeout != 0) && (dphase_timeout <= UNDER_MARGIN))
            `uvm_fatal(get_type_name(),
                       "C_DPHASE_TIMEOUT is too small for an under-threshold case")
    endfunction : validate_knobs

endclass : axi4_mst_timeout_seq