//=============================================================================
// File        : ahb_idle_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : IDLE transfer test. Runs ahb_idle_seq, which leaves the bus
//               IDLE in runs of several cycles around every burst and, in its
//               last phase, has the master present IDLE in the pipelined slot
//               while the slave is still waiting. A bus watcher classifies
//               every cycle and checks that the slave answered each accepted
//               IDLE and BUSY with a zero-wait OKAY, that nothing but IDLE or
//               NONSEQ ever followed an accepted IDLE, and that the address
//               moved under an IDLE held with HREADY low.
//               Covers AHB_TRN_001, AHB_TRN_006, AHB_WAI_007 and AHB_WAI_010
//               in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_IDLE_TEST_INCLUDED_
`define AHB_IDLE_TEST_INCLUDED_

class ahb_idle_test extends ahb_base_test;

    `uvm_component_utils(ahb_idle_test)

    // Write/read pairs to issue, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 24;

    // Longest IDLE run requested between transfers, overridable: +MAX_GAP=<n>
    int unsigned max_gap = 4;

    //-------------------------------------------------------------------------
    // Bus observation, filled by watch_bus()
    //-------------------------------------------------------------------------
    protected int unsigned num_idle_accepted;   // IDLE cycles accepted (HREADY=1)
    protected int unsigned num_idle_waited;     // IDLE presented with HREADY=0
    protected int unsigned num_busy_accepted;   // BUSY cycles accepted
    protected int unsigned num_bursts;          // NONSEQ address phases accepted
    protected int unsigned longest_idle_run;    // consecutive accepted IDLEs

    // The address moved while HTRANS was IDLE and HREADY low (AHB_WAI_007)
    protected int unsigned num_idle_wait_addr_change;

    // Violations, each already reported as an error where it was seen
    protected int unsigned num_resp_viol;       // IDLE/BUSY not answered OKAY
    protected int unsigned num_order_viol;      // SEQ or BUSY after an IDLE

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - auto-response mode: the read-back check needs the memory
    // model, and it is what proves the slave ignored the IDLEs it was given.
    // The overlap is deferred into the wait state, so the pipelined slot opens
    // as IDLE instead of taking the next transfer straight away - the only way
    // an IDLE is ever presented with HREADY low. Wait states start at zero;
    // the sequence rewrites ready_delay_min/max per phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 0;

        env_cfg.master_agent_cfg.en_back_to_back           = 1;
        env_cfg.master_agent_cfg.en_idle_to_nonseq_in_wait = 1;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("MAX_GAP=%d", max_gap));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // watch_bus - classify every bus cycle and check the IDLE rules against the
    // cycle that follows. Runs until killed by the run phase
    //-------------------------------------------------------------------------
    task watch_bus();
        virtual ahb_if           vif;
        ahb_trans_e              prev_t;
        bit                      prev_ready;
        bit                      prev_valid;    // a previous cycle was sampled
        bit [AHB_ADDR_WIDTH-1:0] prev_addr;
        ahb_trans_e              cur_t;
        bit                      cur_ready;
        ahb_resp_e               cur_resp;
        int unsigned             run;           // accepted IDLEs in a row

        vif        = env_cfg.master_vif;
        prev_valid = 0;
        run        = 0;

        forever begin
            @(vif.monitor_cb);

            if (!vif.rst_n) begin
                prev_valid = 0;
                run        = 0;
                continue;
            end

            cur_t     = ahb_trans_e'(vif.monitor_cb.HTRANS);
            cur_ready = (vif.monitor_cb.HREADY === 1'b1);
            cur_resp  = ahb_resp_e'(vif.monitor_cb.HRESP);

            //-----------------------------------------------------------------
            // Rules that read the cycle after the one they are about
            //-----------------------------------------------------------------
            if (prev_valid) begin
                // An accepted IDLE or BUSY moves no data: the slave must
                // complete it in the next cycle with OKAY, no wait states
                // (AHB_TRN_001, AHB_WAI_010)
                if (prev_ready && prev_t inside {AHB_TRANS_IDLE, AHB_TRANS_BUSY}
                    && (!cur_ready || cur_resp != AHB_RESP_OKAY)) begin
                    num_resp_viol++;
                    `uvm_error(get_type_name(),
                               $sformatf("%s transfer not answered zero-wait OKAY: HREADY=%0b HRESP=%s",
                                         prev_t.name(), cur_ready, cur_resp.name()))
                end

                // A burst cannot resume across an IDLE (AHB_TRN_006)
                if (prev_ready && prev_t == AHB_TRANS_IDLE &&
                    !(cur_t inside {AHB_TRANS_IDLE, AHB_TRANS_NONSEQ})) begin
                    num_order_viol++;
                    `uvm_error(get_type_name(),
                               $sformatf("%s followed an accepted IDLE (only IDLE or NONSEQ allowed)",
                                         cur_t.name()))
                end

                // Address/control need not hold under an IDLE, so the master
                // may move HADDR while the previous data phase is still waited
                // (AHB_WAI_007). Legal, and recorded here as having happened
                if (!prev_ready && prev_t == AHB_TRANS_IDLE &&
                    vif.monitor_cb.HADDR !== prev_addr)
                    num_idle_wait_addr_change++;
            end

            //-----------------------------------------------------------------
            // Cycle classification
            //-----------------------------------------------------------------
            case (cur_t)
                AHB_TRANS_IDLE: begin
                    if (cur_ready) begin
                        num_idle_accepted++;
                        run++;
                        if (run > longest_idle_run) longest_idle_run = run;
                    end else begin
                        num_idle_waited++;
                    end
                end
                AHB_TRANS_BUSY: begin
                    run = 0;
                    if (cur_ready) num_busy_accepted++;
                end
                AHB_TRANS_NONSEQ: begin
                    run = 0;
                    if (cur_ready) num_bursts++;
                end
                default: run = 0;   // SEQ stays inside an open burst
            endcase

            prev_t     = cur_t;
            prev_ready = cur_ready;
            prev_addr  = vif.monitor_cb.HADDR;
            prev_valid = 1;
        end
    endtask : watch_bus

    //-------------------------------------------------------------------------
    // Run phase - the watcher never returns, so join_any ends on the sequence
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_idle_seq seq;

        phase.raise_objection(this, "idle test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq          = ahb_idle_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.max_gap  = max_gap;

        // Bus clock, used by the sequence to count out its IDLE runs
        seq.vif = env_cfg.master_vif;

        // Null when the slave agent is passive: the sequence then runs at the
        // configured back-pressure instead of setting a window per phase
        seq.slv_drv = env.slave_agent.drv;

        fork
            watch_bus();
            seq.start(env.master_agent.sqr);
        join_any
        disable fork;

        check_bus();

        phase.drop_objection(this, "idle test done");
    endtask : run_phase

    //-------------------------------------------------------------------------
    // check_bus - the stimulus must actually have produced the transfers the
    // rules above are written against. A clean run that never idled, never
    // stalled on BUSY, or never held an IDLE through a wait proves nothing
    //-------------------------------------------------------------------------
    function void check_bus();
        `uvm_info(get_type_name(),
                  $sformatf("Bus: %0d bursts, %0d IDLE accepted (longest run %0d), %0d IDLE waited, %0d BUSY accepted, %0d address moves under a waited IDLE",
                            num_bursts, num_idle_accepted, longest_idle_run,
                            num_idle_waited, num_busy_accepted,
                            num_idle_wait_addr_change),
                  (num_resp_viol == 0 && num_order_viol == 0) ? UVM_LOW : UVM_NONE)

        if (num_idle_accepted == 0)
            `uvm_error(get_type_name(),
                       "No IDLE transfer was accepted - the bus never went idle")

        if (longest_idle_run < 2)
            `uvm_error(get_type_name(),
                       $sformatf("Longest IDLE run was %0d cycle(s) - back-to-back IDLE transfers were never exercised",
                                 longest_idle_run))

        if (num_busy_accepted == 0)
            `uvm_error(get_type_name(),
                       "No BUSY transfer was accepted - the zero-wait OKAY rule was only checked for IDLE")

        if (num_idle_waited == 0)
            `uvm_error(get_type_name(),
                       "IDLE was never presented with HREADY low - the pipelined slot never opened inside a wait state")

        if (num_idle_wait_addr_change == 0)
            `uvm_error(get_type_name(),
                       "The address never moved under a waited IDLE - AHB_WAI_007 was not exercised")
    endfunction : check_bus

endclass : ahb_idle_test

`endif // AHB_IDLE_TEST_INCLUDED_
