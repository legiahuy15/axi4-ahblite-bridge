//=============================================================================
// File        : ahb_error_response_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : ERROR response test. The slave agent runs in sequence mode and
//               ahb_slave_error_seq answers a share of the beats with ERROR,
//               while ahb_error_seq drives every burst type under both the
//               cancel and the continue policy.
//               Covers AHB_RSP_003 to AHB_RSP_008, AHB_BST_014, AHB_BST_015
//               and AHB_ENV_003 in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_ERROR_RESPONSE_TEST_INCLUDED_
`define AHB_ERROR_RESPONSE_TEST_INCLUDED_

class ahb_error_response_test extends ahb_base_test;

    `uvm_component_utils(ahb_error_response_test)

    // Bursts to issue, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 16;

    // Share of beats answered with ERROR, overridable: +ERROR_RATE=<n>
    int unsigned error_rate_pct = 25;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - responses come from the sequencer, so the memory model and
    // ready_delay_min/max are unused
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp = 0;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("ERROR_RATE=%d", error_rate_pct));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - the slave sequence runs forever: forked off and killed at
    // phase end. Only the master traffic holds the objection
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_error_seq       mst_seq;
        ahb_slave_error_seq slv_seq;

        phase.raise_objection(this, "error response test running");
        phase.phase_done.set_drain_time(this, 200ns);

        mst_seq          = ahb_error_seq::type_id::create("mst_seq");
        mst_seq.num_iter = num_iter;

        // Unmapped region is owned by the master sequence; mirror it here
        slv_seq                = ahb_slave_error_seq::type_id::create("slv_seq");
        slv_seq.error_rate_pct = error_rate_pct;
        slv_seq.unmapped_base  = mst_seq.unmapped_base;

        fork
            slv_seq.start(env.slave_agent.sqr);
        join_none

        mst_seq.start(env.master_agent.sqr);

        `uvm_info(get_type_name(),
                  $sformatf("Slave answered %0d beats: %0d ERROR, %0d in the unmapped region",
                            slv_seq.num_rsp, slv_seq.num_error, slv_seq.num_unmapped), UVM_LOW)

        phase.drop_objection(this, "error response test done");
    endtask : run_phase

endclass : ahb_error_response_test

`endif // AHB_ERROR_RESPONSE_TEST_INCLUDED_
