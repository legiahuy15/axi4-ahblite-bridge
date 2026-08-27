//=============================================================================
// File        : ahb_wait_state_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Wait-state test. Runs ahb_wait_state_seq, which sweeps the
//               slave's wait-state window from zero up to the 16 recommended by
//               IHI0033A 5.1.2 while reads and writes run through it.
//               Covers AHB_WAI_001 to AHB_WAI_004, AHB_WAI_009, AHB_BAS_005,
//               AHB_BAS_006, AHB_RSP_002 and AHB_DAT_001 in
//               doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_WAIT_STATE_TEST_INCLUDED_
`define AHB_WAIT_STATE_TEST_INCLUDED_

class ahb_wait_state_test extends ahb_base_test;

    `uvm_component_utils(ahb_wait_state_test)

    // Bursts to issue, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 24;

    // Ceiling on the swept window, overridable: +WAIT_MAX=<n>
    int unsigned wait_max = 16;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - auto-response mode: the read-back check needs the memory
    // model, and all-OKAY beats leave HREADY as the only variable. Starts at
    // zero wait; the sequence rewrites ready_delay_min/max as it sweeps
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 0;

        // Back-to-back overlap puts an address phase inside the previous
        // beat's wait state, feeding the stability checks. Deferring it opens
        // the slot as IDLE and upgrades to NONSEQ mid-wait (AHB_WAI_004)
        env_cfg.master_agent_cfg.en_back_to_back          = 1;
        env_cfg.master_agent_cfg.en_idle_to_nonseq_in_wait = 1;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("WAIT_MAX=%d", wait_max));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - a 16-wait beat is 17 cycles, so the drain time must outlast
    // the deepest window
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_wait_state_seq seq;

        phase.raise_objection(this, "wait state test running");
        phase.phase_done.set_drain_time(this, 500ns);

        seq          = ahb_wait_state_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.wait_max = wait_max;

        // Null when the slave agent is passive: the sequence then runs at the
        // configured back-pressure instead of sweeping
        seq.slv_drv = env.slave_agent.drv;

        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "wait state test done");
    endtask : run_phase

endclass : ahb_wait_state_test

`endif // AHB_WAIT_STATE_TEST_INCLUDED_
