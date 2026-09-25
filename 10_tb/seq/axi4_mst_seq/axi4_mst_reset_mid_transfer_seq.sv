//=============================================================================
// File        : axi4_mst_reset_mid_transfer_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Reset during an active transfer, and recovery from it.
//               BRG_RST_005 asks that a reset taken while a transfer is in
//               flight clears the partial AXI and AHB activity and the
//               predictor and scoreboard queues, without a hang and without a
//               ghost response; BRG_RST_006 asks that a fresh write and read
//               then complete correctly.
//               The reset is placed at each phase the plan names, detected on
//               the interfaces rather than guessed from a delay:
//               - AXI address phase, AWVALID or ARVALID asserted
//               - AXI write data phase, WVALID asserted before WLAST
//               - AXI read data phase, RVALID asserted before RLAST
//               - AXI response phase, BVALID asserted with BREADY still low,
//                 which the master's B delay window holds open
//               - AHB wait phase, HREADY low
//               - AHB error phase, HRESP asserted
//               The interrupted request is sent without waiting for its
//               response, because the driver discards it at the reset and
//               waiting would hang the sequence rather than test it. After
//               each reset an observer watches the B and R channels while
//               nothing is outstanding, so a response arriving for a request
//               that no longer exists is caught; then ordinary write and read
//               traffic runs and is compared by the scoreboard in full. The
//               scoreboard end-of-test check, which requires every queue to
//               be empty, is what shows the reset hooks cleared them.
//               Covers BRG_RST_005 and BRG_RST_006.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_reset_mid_transfer_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_reset_mid_transfer_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    // Long enough to hold the AHB wait phase open while the reset is placed
    localparam int unsigned HOLD_WAIT = 20;

    // Cycles the B and R channels are watched after a reset, with nothing
    // outstanding, before recovery traffic starts
    localparam int unsigned GHOST_WINDOW = 32;

    // Guard on phase detection, so a phase that never arrives fails here
    localparam int unsigned PHASE_LIMIT = 400;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    ahb_response_policy policy;
    ahb_vif_t           ahb_vif;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned resets_done;
    int unsigned ghost_responses;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef enum {
        PH_AXI_ADDR,
        PH_AXI_WDATA,
        PH_AXI_RDATA,
        PH_AXI_RESP,
        PH_AHB_WAIT,
        PH_AHB_ERROR
    } reset_phase_e;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected int unsigned case_index;
    protected bit          watch_ghost;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_reset_mid_transfer_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (policy == null)
            `uvm_fatal(get_type_name(), "Response policy is null")
        if (ahb_vif == null)
            `uvm_fatal(get_type_name(), "AHB virtual interface is null")
        if ((cfg.bready_delay_max == 0) && (cfg.bready_delay_min == 0))
            `uvm_fatal(get_type_name(),
                       {"The B response phase can only be caught if the ",
                        "master holds BREADY off; set bready_delay"})

        wait_reset_release();
        validate_knobs();

        `uvm_info(get_type_name(), "Reset during transfer: 10 cases", UVM_LOW)

        fork
            begin
                fork
                    observe_ghost();
                    run_all_cases();
                join_any
                disable fork;
            end
        join

        `uvm_info(get_type_name(),
                  $sformatf({"Reset mid-transfer summary: cases=%0d failed=%0d ",
                             "resets=%0d ghost_responses=%0d"},
                            cases_run, cases_failed, resets_done,
                            ghost_responses),
                  UVM_LOW)
    endtask : body

    protected task run_all_cases();
        run_case(PH_AXI_ADDR,  AXI4_WRITE, 3, "AXI_ADDR");
        run_case(PH_AXI_ADDR,  AXI4_READ,  3, "AXI_ADDR");
        run_case(PH_AXI_WDATA, AXI4_WRITE, 3, "AXI_WDATA");
        run_case(PH_AXI_RDATA, AXI4_READ,  3, "AXI_RDATA");
        run_case(PH_AXI_RESP,  AXI4_WRITE, 0, "AXI_RESP");
        run_case(PH_AHB_WAIT,  AXI4_WRITE, 3, "AHB_WAIT");
        run_case(PH_AHB_WAIT,  AXI4_READ,  3, "AHB_WAIT");
        run_case(PH_AHB_ERROR, AXI4_WRITE, 3, "AHB_ERROR");
        run_case(PH_AHB_ERROR, AXI4_READ,  3, "AHB_ERROR");
        // A single beat has no burst state to unwind, so the reset lands on a
        // different part of the write path than the INCR4 case above
        run_case(PH_AXI_ADDR,  AXI4_WRITE, 0, "AXI_ADDR_SINGLE");
    endtask : run_all_cases

    //-------------------------------------------------------------------------
    // Ghost-response observer
    //-------------------------------------------------------------------------
    // Between a reset and the next request nothing is outstanding, so any B or
    // R beat belongs to a request the reset was supposed to have discarded.
    protected task observe_ghost();
        forever begin
            @(cfg.vif.monitor_cb);
            if (!watch_ghost)
                continue;
            if (cfg.vif.monitor_cb.BVALID === 1'b1) begin
                ghost_responses++;
                `uvm_error(get_type_name(),
                           $sformatf({"BVALID asserted with nothing ",
                                      "outstanding after a reset: ghost write ",
                                      "response id=0x%0h"},
                                     cfg.vif.monitor_cb.BID))
            end
            if (cfg.vif.monitor_cb.RVALID === 1'b1) begin
                ghost_responses++;
                `uvm_error(get_type_name(),
                           $sformatf({"RVALID asserted with nothing ",
                                      "outstanding after a reset: ghost read ",
                                      "response id=0x%0h"},
                                     cfg.vif.monitor_cb.RID))
            end
        end
    endtask : observe_ghost

    //-------------------------------------------------------------------------
    // One case: interrupt a transfer at 'phase', then recover
    //-------------------------------------------------------------------------
    protected task run_case(
        reset_phase_e phase,
        axi4_dir_e    dir,
        int unsigned  len,
        string        label
    );
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          req;
        bit                       failed;
        bit                       recovery_failed;

        failed = 1'b0;
        addr   = base_addr + (case_index * case_stride);

        plan_beats(phase, len + 1);
        req = create_request(dir, len, addr);
        send_axi_request(req);
        cases_run++;

        wait_for_phase(phase, dir, label);
        assert_reset();

        // Nothing is outstanding now, so nothing may come back
        watch_ghost = 1'b1;
        wait_cycles(GHOST_WINDOW);
        watch_ghost = 1'b0;

        run_recovery(recovery_failed);
        failed |= recovery_failed;

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] RESET_%s_%s at 0x%0h: recovered",
                            case_index, label, dir.name(), addr),
                  UVM_MEDIUM)
        case_index++;
        if (failed)
            cases_failed++;
    endtask : run_case

    // Every beat answered OKAY with no wait, for the recovery traffic
    protected function void plan_clean_beats(int unsigned beats);
        policy.clear_plan();
        for (int unsigned i = 0; i < beats; i++)
            policy.add_beat(AHB_RESP_OKAY, 0);
    endfunction : plan_clean_beats

    // The AHB wait and error phases need the slave to produce them; the AXI
    // phases only need the request to be running.
    protected function void plan_beats(reset_phase_e phase, int unsigned beats);
        policy.clear_plan();
        for (int unsigned i = 0; i < beats; i++) begin
            case (phase)
                PH_AHB_WAIT:
                    policy.add_beat(AHB_RESP_OKAY,
                                    (i == 1) ? HOLD_WAIT : 0);
                PH_AHB_ERROR:
                    policy.add_beat((i == 1) ? AHB_RESP_ERROR : AHB_RESP_OKAY,
                                    0);
                default:
                    policy.add_beat(AHB_RESP_OKAY, 0);
            endcase
        end
    endfunction : plan_beats

    //-------------------------------------------------------------------------
    // Phase detection
    //-------------------------------------------------------------------------
    protected function bit phase_reached(reset_phase_e phase, axi4_dir_e dir);
        case (phase)
            PH_AXI_ADDR:
                return (dir == AXI4_WRITE) ? (cfg.vif.AWVALID === 1'b1)
                                           : (cfg.vif.ARVALID === 1'b1);
            PH_AXI_WDATA:
                return (cfg.vif.WVALID === 1'b1) && (cfg.vif.WLAST !== 1'b1);
            PH_AXI_RDATA:
                return (cfg.vif.RVALID === 1'b1) && (cfg.vif.RLAST !== 1'b1);
            PH_AXI_RESP:
                return (cfg.vif.BVALID === 1'b1) && (cfg.vif.BREADY !== 1'b1);
            PH_AHB_WAIT:
                return (ahb_vif.HREADY !== 1'b1);
            PH_AHB_ERROR:
                return (ahb_vif.HRESP === 1'b1);
            default:
                return 1'b0;
        endcase
    endfunction : phase_reached

    protected task wait_for_phase(
        reset_phase_e phase,
        axi4_dir_e    dir,
        string        label
    );
        for (int unsigned i = 0; !phase_reached(phase, dir); i++) begin
            if (i > PHASE_LIMIT)
                `uvm_fatal(get_type_name(),
                           $sformatf({"%s %s never reached its phase, so the ",
                                      "reset has nothing to interrupt"},
                                     label, dir.name()))
            @(posedge cfg.vif.clk);
        end
    endtask : wait_for_phase

    //-------------------------------------------------------------------------
    // Reset
    //-------------------------------------------------------------------------
    protected task assert_reset();
        uvm_event reset_event;

        reset_event = uvm_event_pool::get_global("bridge_reset_req");
        reset_event.trigger();

        wait (cfg.vif.rst_n === 1'b0);
        wait (cfg.vif.rst_n === 1'b1);
        resets_done++;

        // Whatever the interrupted request left in the plan is gone with it
        policy.clear_plan();
        wait_cycles(8);
    endtask : assert_reset

    //-------------------------------------------------------------------------
    // Recovery: BRG_RST_006
    //-------------------------------------------------------------------------
    protected task run_recovery(output bit failed);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          wr_req;
        axi4_transaction          rd_req;
        axi4_transaction          wr_rsp;
        axi4_transaction          rd_rsp;

        failed = 1'b0;
        addr   = base_addr + ((case_index + 64) * case_stride);

        plan_clean_beats(4);
        wr_req = create_request(AXI4_WRITE, 3, addr);
        send_axi_request_wait(wr_req, wr_rsp);
        if (wr_rsp.bresp != AXI4_RESP_OKAY) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("recovery write at 0x%0h returned %s",
                                 addr, wr_rsp.bresp.name()))
        end
        failed |= drain_plan("write");

        plan_clean_beats(4);
        rd_req = create_request(AXI4_READ, 3, addr);
        send_axi_request_wait(rd_req, rd_rsp);
        failed |= check_read(addr, rd_rsp);
        failed |= drain_plan("read");
    endtask : run_recovery

    protected function bit drain_plan(string what);
        if (policy.pending_beats() == 0)
            return 1'b0;

        `uvm_error(get_type_name(),
                   $sformatf({"recovery %s left %0d AHB beats unissued, so ",
                              "the bridge did not fully recover"},
                             what, policy.pending_beats()))
        policy.clear_plan();
        return 1'b1;
    endfunction : drain_plan

    protected function bit check_read(
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp
    );
        bit failed;

        failed = 1'b0;
        if (rsp.data.size() != 4) begin
            `uvm_error(get_type_name(),
                       $sformatf("recovery read at 0x%0h returned %0d beats",
                                 addr, rsp.data.size()))
            return 1'b1;
        end
        foreach (rsp.rresp[i]) begin
            if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("recovery read at 0x%0h beat=%0d: %s",
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
        return failed;
    endfunction : check_read

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
                  $sformatf("rstmt_%s_%0d",
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
                    req.data[i][8*k +: 8] = 8'h60 + cases_run * 4 + i * 2 + k;
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
    endfunction : validate_knobs

endclass : axi4_mst_reset_mid_transfer_seq