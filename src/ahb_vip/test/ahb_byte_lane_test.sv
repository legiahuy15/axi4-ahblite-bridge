//=============================================================================
// File        : ahb_byte_lane_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Byte-lane test. Runs ahb_byte_lane_seq, which walks narrow
//               transfers across every active byte lane of the data bus and
//               checks each one against the reference memory, with the inverted
//               payload on the lanes the transfer must not use.
//               Covers AHB_DAT_003 and AHB_DAT_004 in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_BYTE_LANE_TEST_INCLUDED_
`define AHB_BYTE_LANE_TEST_INCLUDED_

class ahb_byte_lane_test extends ahb_base_test;

    `uvm_component_utils(ahb_byte_lane_test)

    // Slots to walk, overridable: +NUM_ITER=<n>. Sizes rotate per slot, so at
    // least 3 are needed to reach every lane
    int unsigned num_iter = 12;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - memory-model slave with a few wait states, so a narrow
    // beat also has to hold HWDATA on its lanes across an extended data phase
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
        ahb_byte_lane_seq seq;

        phase.raise_objection(this, "byte lane test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq          = ahb_byte_lane_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "byte lane test done");
    endtask : run_phase

endclass : ahb_byte_lane_test

`endif // AHB_BYTE_LANE_TEST_INCLUDED_
