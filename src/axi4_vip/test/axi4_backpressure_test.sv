//==============================================================================
// File        : axi4_backpressure_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Back-pressure / latency stress test.
//               Configures the slave with large, random READY and response
//               delays on all channels, then runs a random mixed workload.
//               This exercises timing corners that the zero-delay tests never
//               reach: xREADY asserted many cycles after xVALID, WREADY
//               de-asserted mid-W-burst, delayed B/R responses - hitting the
//               SVA back-pressure/stability checks and the *_BACKPRESSURE_COV
//               cover properties. The scoreboard stays ON so data integrity is
//               verified while the bus is stalling.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_BACKPRESSURE_TEST_INCLUDED_
`define AXI4_BACKPRESSURE_TEST_INCLUDED_

class axi4_backpressure_test extends axi4_base_test;

    `uvm_component_utils(axi4_backpressure_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Large, asymmetric random delays on the slave - both back-pressure
        // (xREADY latency) and response (B/R) latency.
        env_cfg.slave_agent_cfg.ready_delay_min = 3;
        env_cfg.slave_agent_cfg.ready_delay_max = 8;
        env_cfg.slave_agent_cfg.resp_delay_min  = 2;
        env_cfg.slave_agent_cfg.resp_delay_max  = 6;
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        axi4_random_seq seq;
        phase.raise_objection(this, "axi4_backpressure_test: starting");

        `uvm_info(get_type_name(),
                  "Starting back-pressure stress test (slave ready_delay=[3:8], resp_delay=[2:6])",
                  UVM_LOW)

        seq = axi4_random_seq::type_id::create("bp_seq");
        seq.num_txns = 40;
        seq.start(env.master_agent.sqr);

        // Generous drain: responses are delayed, so let everything settle
        repeat (400) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Back-pressure stress test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_backpressure_test: complete");
    endtask : run_phase

endclass : axi4_backpressure_test

`endif // AXI4_BACKPRESSURE_TEST_INCLUDED_