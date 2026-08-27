//=============================================================================
// File        : ahb_busy_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : BUSY transfer test. Runs ahb_busy_seq with a BUSY run before
//               every beat of fixed-length and undefined-length bursts.
//               Covers AHB_TRN_002, AHB_TRN_003, AHB_TRN_008 and AHB_WAI_005
//               in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_BUSY_TEST_INCLUDED_
`define AHB_BUSY_TEST_INCLUDED_

class ahb_busy_test extends ahb_base_test;

    `uvm_component_utils(ahb_busy_test)

    // Bursts to issue, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 16;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - wait states are required: AHB_WAI_005 covers a BUSY that
    // changes while HREADY is low, impossible with a zero-wait slave
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 2;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_busy_seq seq;

        phase.raise_objection(this, "busy test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq = ahb_busy_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "busy test done");
    endtask : run_phase

endclass : ahb_busy_test

`endif // AHB_BUSY_TEST_INCLUDED_