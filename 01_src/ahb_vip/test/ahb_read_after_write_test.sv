//=============================================================================
// File        : ahb_read_after_write_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Data-integrity test. Runs ahb_read_after_write_seq, which
//               writes a random word and reads back the same address. The
//               slave answers from its memory model (auto_gen_resp), so the
//               read must return the value just written.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_READ_AFTER_WRITE_TEST_INCLUDED_
`define AHB_READ_AFTER_WRITE_TEST_INCLUDED_

class ahb_read_after_write_test extends ahb_base_test;

    `uvm_component_utils(ahb_read_after_write_test)

    // Iterations (write/read pairs), overridable: +NUM_ITER=<n>
    int unsigned num_iter = 20;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - a few slave wait states exercise the pipelined driver
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;    // memory-model loopback
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 2;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - start the read-after-write sequence on the master sequencer
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_read_after_write_seq seq;

        phase.raise_objection(this, "read-after-write test running");
        // Let the monitors publish the last burst before the phase ends
        phase.phase_done.set_drain_time(this, 200ns);

        seq = ahb_read_after_write_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "read-after-write test done");
    endtask : run_phase

endclass : ahb_read_after_write_test

`endif // AHB_READ_AFTER_WRITE_TEST_INCLUDED_