//=============================================================================
// File        : ahb_undefined_burst_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Undefined-length burst test. Runs ahb_undefined_burst_seq with
//               INCR bursts from 1 to 256 beats, BUSY inserted mid-burst and
//               bursts terminated out of a BUSY transfer.
//               Covers AHB_BST_002, AHB_TRN_009 and AHB_WAI_006 in
//               doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_UNDEFINED_BURST_TEST_INCLUDED_
`define AHB_UNDEFINED_BURST_TEST_INCLUDED_

class ahb_undefined_burst_test extends ahb_base_test;

    `uvm_component_utils(ahb_undefined_burst_test)

    // Bursts to issue, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 8;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - wait states put BUSY on the bus with HREADY low, the case
    // BUSY_WAIT_TRANSITION checks
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 2;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - a 256-beat burst takes a while, so allow a longer drain
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_undefined_burst_seq seq;

        phase.raise_objection(this, "undefined burst test running");
        phase.phase_done.set_drain_time(this, 500ns);

        seq = ahb_undefined_burst_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "undefined burst test done");
    endtask : run_phase

endclass : ahb_undefined_burst_test

`endif // AHB_UNDEFINED_BURST_TEST_INCLUDED_
