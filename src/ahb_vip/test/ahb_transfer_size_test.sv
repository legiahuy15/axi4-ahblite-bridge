//=============================================================================
// File        : ahb_transfer_size_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Transfer-size test. Runs ahb_size_seq, which sweeps HSIZE over
//               every encoding legal on the data bus, at every alignment each
//               one allows, as SINGLE and as multi-beat bursts, and checks that
//               the encodings fitting the bus are accepted by constraint while
//               the wider ones are rejected.
//               Covers AHB_SIZ_001 to AHB_SIZ_006 in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_TRANSFER_SIZE_TEST_INCLUDED_
`define AHB_TRANSFER_SIZE_TEST_INCLUDED_

class ahb_transfer_size_test extends ahb_base_test;

    `uvm_component_utils(ahb_transfer_size_test)

    // Bursts to issue, overridable: +NUM_ITER=<n>. 12 covers the full sweep;
    // the default runs it twice
    int unsigned num_iter = 24;

    // HSIZE encoding check, overridable: +CHK_SIZE_ENCODINGS=0. The failed
    // randomize() calls it makes on the wide encodings are the expected result,
    // not an error
    int unsigned chk_size_encodings = 1;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - memory-model slave with a few wait states, so a narrow
    // beat also has to hold its data phase across back-pressure
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 2;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("CHK_SIZE_ENCODINGS=%d", chk_size_encodings));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_size_seq seq;

        phase.raise_objection(this, "transfer size test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq                    = ahb_size_seq::type_id::create("seq");
        seq.num_iter           = num_iter;
        seq.chk_size_encodings = (chk_size_encodings != 0);
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "transfer size test done");
    endtask : run_phase

endclass : ahb_transfer_size_test

`endif // AHB_TRANSFER_SIZE_TEST_INCLUDED_
