//=============================================================================
// File        : ahb_random_stress_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Description : Test wrapper for ahb_random_stress_seq.
//=============================================================================

`ifndef AHB_RANDOM_STRESS_TEST_INCLUDED_
`define AHB_RANDOM_STRESS_TEST_INCLUDED_

class ahb_random_stress_test extends ahb_base_test;

    `uvm_component_utils(ahb_random_stress_test)

    int unsigned num_iter = 100;
    int unsigned wait_max = 7;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        void'($value$plusargs("NUM_ITER=%d", num_iter));
        void'($value$plusargs("WAIT_MAX=%d", wait_max));

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = wait_max;
        env_cfg.master_agent_cfg.en_back_to_back = 1;
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        ahb_random_stress_seq seq;

        phase.raise_objection(this, "random stress test running");
        phase.phase_done.set_drain_time(this, 1us);

        seq          = ahb_random_stress_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.wait_max = wait_max;
        seq.slv_drv  = env.slave_agent.drv;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "random stress test done");
    endtask : run_phase

endclass : ahb_random_stress_test

`endif // AHB_RANDOM_STRESS_TEST_INCLUDED_
