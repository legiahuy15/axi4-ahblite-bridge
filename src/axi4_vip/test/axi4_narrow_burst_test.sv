//==============================================================================
// File        : axi4_narrow_burst_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test for AXI4 narrow burst transfers.
//               Runs the narrow burst sequence to demonstrate transfers
//               where AxSIZE < data bus width (1B and 2B on 32-bit bus).
//               Only 4 transactions - ideal for waveform capture.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_NARROW_BURST_TEST_INCLUDED_
`define AXI4_NARROW_BURST_TEST_INCLUDED_

class axi4_narrow_burst_test extends axi4_base_test;

    `uvm_component_utils(axi4_narrow_burst_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_narrow_burst_seq narrow_seq;
        phase.raise_objection(this, "axi4_narrow_burst_test: starting");

        `uvm_info(get_type_name(),
                  "Starting narrow burst test (4 transactions)",
                  UVM_LOW)

        narrow_seq = axi4_narrow_burst_seq::type_id::create("narrow_seq");
        narrow_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (50) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  "Narrow burst test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_narrow_burst_test: complete");
    endtask : run_phase

endclass : axi4_narrow_burst_test

`endif // AXI4_NARROW_BURST_TEST_INCLUDED_