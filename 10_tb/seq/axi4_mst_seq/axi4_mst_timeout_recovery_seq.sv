//=============================================================================
// File        : axi4_mst_timeout_recovery_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : C_DPHASE_TIMEOUT termination and recovery sequence.
//               BRG_TMO_004 asks for three things: the watchdog returns the
//               AHB bus to IDLE, the AXI side gets SLVERR, and the bridge
//               recovers cleanly after a reset.
//               Termination is checked on the AHB interface itself rather
//               than from the response. An observer counts the address phases
//               the bridge actually issues and watches HTRANS once the
//               watchdog has fired, so a burst that kept running or restarted
//               after being abandoned is caught even though its AXI response
//               would look the same.
//               Cases:
//               - single write and single read abandoned: exactly one address
//                 phase, HTRANS IDLE from then until the slave releases the
//                 bus, SLVERR on the AXI side
//               - INCR4 write and read abandoned on their second beat: the
//                 two remaining beats are never issued
//               - a write-path and a read-path timeout, each followed by a
//                 reset and by ordinary traffic that must complete with OKAY
//               - a reset asserted while the slave is still holding HREADY
//                 low after an abandoned beat, which is the case a stuck
//                 slave produces, again followed by ordinary traffic
//               The traffic after each reset is compared by the scoreboard as
//               usual, so recovery means the whole path works again, not just
//               that a response came back.
//               Covers BRG_TMO_004.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_timeout_recovery_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_timeout_recovery_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    // Comfortably past the threshold, which bridge_timeout_boundary_test
    // pins at C_DPHASE_TIMEOUT+2 at the latest
    localparam int unsigned OVER_MARGIN = 32;

    // The bridge drives IDLE from the cycle the watchdog fires; the response
    // reaches the sequence around the same time, so the check starts a couple
    // of cycles later to stay clear of that skew
    localparam int unsigned IDLE_GRACE = 2;

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
    ahb_vif_t           ahb_vif;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned timeouts_seen;
    int unsigned resets_done;
    int unsigned idle_violations;
    int unsigned extra_beats;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected int unsigned case_index;
    protected int unsigned case_addr_phases;  // address phases this case issued
    protected bit          watch_idle;        // AHB must stay IDLE right now

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_timeout_recovery_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (policy == null)
            `uvm_fatal(get_type_name(), "Response policy is null")
        if (scb == null)
            `uvm_fatal(get_type_name(), "Recovery sequence needs the scoreboard")
        if (ahb_vif == null)
            `uvm_fatal(get_type_name(), "AHB virtual interface is null")

        wait_reset_release();
        validate_knobs();

        `uvm_info(get_type_name(),
                  $sformatf({"Timeout recovery: C_DPHASE_TIMEOUT=%0d, AHB ",
                             "wait %0d"},
                            dphase_timeout, stall_wait()),
                  UVM_LOW)

        fork
            begin
                fork
                    observe_ahb();
                    run_all_cases();
                join_any
                disable fork;
            end
        join

        `uvm_info(get_type_name(),
                  $sformatf({"Timeout recovery summary: dphase_timeout=%0d ",
                             "run=%0d failed=%0d timeouts_seen=%0d ",
                             "resets=%0d idle_violations=%0d extra_beats=%0d"},
                            dphase_timeout, cases_run, cases_failed,
                            timeouts_seen, resets_done, idle_violations,
                            extra_beats),
                  UVM_LOW)
    endtask : body

    protected task run_all_cases();
        // Termination: the abandoned burst must stop on the AHB side
        check_termination(AXI4_WRITE, 0, 0, "SINGLE");
        check_termination(AXI4_READ,  0, 0, "SINGLE");
        check_termination(AXI4_WRITE, 3, 1, "INCR4_B1");
        check_termination(AXI4_READ,  3, 1, "INCR4_B1");

        // Recovery: a reset after a timeout must leave a working bridge
        check_reset_recovery(AXI4_WRITE, 1'b0, "AFTER_WR_TIMEOUT");
        check_reset_recovery(AXI4_READ,  1'b0, "AFTER_RD_TIMEOUT");
        check_reset_recovery(AXI4_WRITE, 1'b1, "DURING_STALL");
    endtask : run_all_cases

    protected function int unsigned stall_wait();
        return dphase_timeout + OVER_MARGIN;
    endfunction : stall_wait

    //-------------------------------------------------------------------------
    // AHB observer
    //-------------------------------------------------------------------------
    // Counts every address phase the bridge gets accepted, and reports any
    // address or data phase driven while the bus is supposed to be idle.
    protected task observe_ahb();
        ahb_trans_e htrans;

        forever begin
            @(ahb_vif.monitor_cb);
            if (ahb_vif.rst_n !== 1'b1)
                continue;

            htrans = ahb_trans_e'(ahb_vif.monitor_cb.HTRANS);

            if ((ahb_vif.monitor_cb.HREADY === 1'b1) &&
                (htrans inside {AHB_TRANS_NONSEQ, AHB_TRANS_SEQ}))
                case_addr_phases++;

            if (watch_idle && (htrans != AHB_TRANS_IDLE)) begin
                idle_violations++;
                `uvm_error(get_type_name(),
                           $sformatf({"HTRANS is %s after the watchdog fired, ",
                                      "the bridge must return AHB to IDLE"},
                                     htrans.name()))
            end
        end
    endtask : observe_ahb

    //-------------------------------------------------------------------------
    // Termination
    //-------------------------------------------------------------------------
    protected task check_termination(
        axi4_dir_e   dir,
        int unsigned len,
        int unsigned stall_beat,
        string       label
    );
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          rsp;
        int unsigned              expected_phases;
        bit                       failed;

        addr            = next_addr();
        expected_phases = stall_beat + 1;

        do_timeout(dir, len, stall_beat, addr, rsp, failed);

        // The bridge walked away from the beat, so nothing more may appear on
        // the bus until the next request
        watch_idle = 1'b1;
        wait_cycles(stall_wait() + 16);
        watch_idle = 1'b0;

        if (case_addr_phases != expected_phases) begin
            failed = 1'b1;
            extra_beats += (case_addr_phases > expected_phases) ?
                               (case_addr_phases - expected_phases) : 0;
            `uvm_error(get_type_name(),
                       $sformatf({"%s %s at 0x%0h: %0d AHB address phases, ",
                                  "expected %0d (the beats after the ",
                                  "abandoned one must not be issued)"},
                                 label, dir.name(), addr, case_addr_phases,
                                 expected_phases))
        end

        `uvm_info(get_type_name(),
                  $sformatf({"[%0d] %s %s at 0x%0h: SLVERR, %0d AHB address ",
                             "phase(s), AHB idle afterwards"},
                            case_index, label, dir.name(), addr,
                            case_addr_phases),
                  UVM_MEDIUM)
        if (failed)
            cases_failed++;
    endtask : check_termination

    //-------------------------------------------------------------------------
    // Recovery
    //-------------------------------------------------------------------------
    // reset_during_stall asserts reset while the slave is still counting out
    // the wait of the beat the bridge abandoned, which is what a stuck slave
    // looks like; otherwise the bus is left to settle first.
    protected task check_reset_recovery(
        axi4_dir_e dir,
        bit        reset_during_stall,
        string     label
    );
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          rsp;
        bit                       failed;
        bit                       step_failed;

        addr = next_addr();
        do_timeout(dir, 0, 0, addr, rsp, failed);

        if (!reset_during_stall)
            wait_cycles(stall_wait() + 16);
        else
            wait_cycles(4);

        assert_reset();

        // Ordinary traffic must work again, and it is compared in full
        do_normal(AXI4_WRITE, 3, next_addr(), step_failed);
        failed |= step_failed;
        do_normal(AXI4_READ,  3, next_addr(), step_failed);
        failed |= step_failed;

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] RESET_%s: recovery traffic completed",
                            case_index, label),
                  UVM_MEDIUM)
        if (failed)
            cases_failed++;
    endtask : check_reset_recovery

    protected task assert_reset();
        uvm_event reset_event;

        reset_event = uvm_event_pool::get_global("bridge_reset_req");
        `uvm_info(get_type_name(), "Requesting a mid-test reset", UVM_MEDIUM)
        reset_event.trigger();

        wait (cfg.vif.rst_n === 1'b0);
        wait (cfg.vif.rst_n === 1'b1);
        resets_done++;

        // The plan is per request and the scoreboard cleared its queues, so
        // nothing from before the reset may be carried over
        policy.clear_plan();
        wait_cycles(8);
    endtask : assert_reset

    //-------------------------------------------------------------------------
    // Building blocks
    //-------------------------------------------------------------------------
    // One request whose beat 'stall_beat' is held off past the threshold.
    // Returns 1 when the response was not the expected SLVERR.
    protected task do_timeout(
        input  axi4_dir_e                dir,
        input  int unsigned              len,
        input  int unsigned              stall_beat,
        input  bit [AXI4_ADDR_WIDTH-1:0] addr,
        output axi4_transaction          rsp,
        output bit                       failed
    );
        axi4_transaction req;
        int unsigned     beats;

        failed = 1'b0;
        beats  = len + 1;
        policy.clear_plan();
        for (int unsigned i = 0; i < beats; i++)
            policy.add_beat(AHB_RESP_OKAY,
                            (i == stall_beat) ? stall_wait() : 0);

        req = create_request(dir, len, addr);
        scb.expect_timeout(dir, req.id);

        case_addr_phases = 0;
        send_axi_request_wait(req, rsp);
        cases_run++;
        policy.clear_plan();

        if (!is_slverr(rsp)) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s at 0x%0h: expected SLVERR from the ",
                                  "watchdog with an AHB wait of %0d and ",
                                  "C_DPHASE_TIMEOUT=%0d"},
                                 dir.name(), addr, stall_wait(),
                                 dphase_timeout))
        end else begin
            timeouts_seen++;
        end
    endtask : do_timeout

    // One ordinary request with no AHB wait, checked end to end
    protected task do_normal(
        input axi4_dir_e                dir,
        input int unsigned              len,
        input bit [AXI4_ADDR_WIDTH-1:0] addr,
        output bit                      failed
    );
        axi4_transaction req;
        axi4_transaction rsp;
        int unsigned     beats;

        beats  = len + 1;
        failed = 1'b0;

        policy.clear_plan();
        for (int unsigned i = 0; i < beats; i++)
            policy.add_beat(AHB_RESP_OKAY, 0);

        req = create_request(dir, len, addr);
        send_axi_request_wait(req, rsp);
        cases_run++;

        if (policy.pending_beats() != 0) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"recovery %s at 0x%0h: %0d AHB beats were ",
                                  "never issued"},
                                 dir.name(), addr, policy.pending_beats()))
            policy.clear_plan();
        end

        if (dir == AXI4_WRITE) begin
            if (rsp.bresp != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("recovery write at 0x%0h: BRESP=%s",
                                     addr, rsp.bresp.name()))
            end
            return;
        end

        if (rsp.data.size() != beats) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"recovery read at 0x%0h: %0d beats, ",
                                  "expected %0d"},
                                 addr, rsp.data.size(), beats))
            return;
        end
        foreach (rsp.rresp[i]) begin
            if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("recovery read at 0x%0h beat=%0d: RRESP=%s",
                                     addr, i, rsp.rresp[i].name()))
            end else if (rsp.data[i] !==
                         policy.read_data(addr + (i << FULL_SIZE))) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"recovery read at 0x%0h beat=%0d: ",
                                      "expected=0x%0h actual=0x%0h"},
                                     addr, i,
                                     policy.read_data(addr + (i << FULL_SIZE)),
                                     rsp.data[i]))
            end
        end
    endtask : do_normal

    protected function bit is_slverr(axi4_transaction rsp);
        if (rsp.dir == AXI4_WRITE)
            return (rsp.bresp == AXI4_RESP_SLVERR);
        foreach (rsp.rresp[i])
            if (rsp.rresp[i] == AXI4_RESP_SLVERR)
                return 1'b1;
        return 1'b0;
    endfunction : is_slverr

    protected function bit [AXI4_ADDR_WIDTH-1:0] next_addr();
        next_addr = base_addr + (case_index * case_stride);
        case_index++;
    endfunction : next_addr

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        int unsigned              len,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;
        int unsigned     req_len;
        axi4_dir_e       req_dir;

        req_len = len;
        req_dir = dir;
        req = axi4_transaction::type_id::create(
                  $sformatf("tmor_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
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
                       $sformatf("Randomization failed at 0x%0h", addr))

        if (dir == AXI4_WRITE) begin
            foreach (req.data[i]) begin
                for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
                    req.data[i][8*k +: 8] = 8'hE0 + cases_run * 4 + i * 2 + k;
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

        if (dphase_timeout == 0)
            `uvm_fatal(get_type_name(),
                       {"Timeout recovery needs a build with a watchdog; ",
                        "run it with TIMEOUT=<16|32|64|128|256>"})
        if (!(dphase_timeout inside {16, 32, 64, 128, 256}))
            `uvm_fatal(get_type_name(),
                       $sformatf("Unsupported C_DPHASE_TIMEOUT=%0d",
                                 dphase_timeout))
        region_bytes = 4 * AXI4_STRB_WIDTH;
        if ((case_stride < region_bytes) ||
            ((case_stride % region_bytes) != 0))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be a non-zero multiple of %0d bytes",
                                 region_bytes))
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
    endfunction : validate_knobs

endclass : axi4_mst_timeout_recovery_seq