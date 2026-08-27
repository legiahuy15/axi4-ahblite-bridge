//==============================================================================
// File        : axi4_error_response_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test for AXI4 error response handling.
//               Runs the error response sequence to demonstrate OKAY,
//               SLVERR, and DECERR responses on B and R channels.
//               Only 6 transactions - ideal for waveform capture.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_ERROR_RESPONSE_TEST_INCLUDED_
`define AXI4_ERROR_RESPONSE_TEST_INCLUDED_

class axi4_error_response_test extends axi4_base_test;

    `uvm_component_utils(axi4_error_response_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase - disable scoreboard data-mismatch checking for error regions
    //   SLVERR/DECERR regions don't store data, so scoreboard would report
    //   mismatches. We keep the scoreboard ON to demonstrate response checking,
    //   but the scoreboard already handles error-region exclusion.
    // =========================================================================

    task run_phase(uvm_phase phase);
        axi4_error_response_seq err_seq;
        phase.raise_objection(this, "axi4_error_response_test: starting");

        `uvm_info(get_type_name(),
                  "Starting error response test (6 transactions: OKAY + SLVERR + DECERR)",
                  UVM_LOW)

        err_seq = axi4_error_response_seq::type_id::create("err_seq");
        err_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (50) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  "Error response test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_error_response_test: complete");
    endtask : run_phase

endclass : axi4_error_response_test

`endif // AXI4_ERROR_RESPONSE_TEST_INCLUDED_