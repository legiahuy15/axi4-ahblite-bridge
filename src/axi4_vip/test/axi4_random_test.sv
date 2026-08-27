//==============================================================================
// File        : axi4_random_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Random mixed-traffic test.
//               Executes a fully randomized sequence of write and read transactions
//               to test the VIP under diverse and concurrent conditions.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_RANDOM_TEST_INCLUDED_
`define AXI4_RANDOM_TEST_INCLUDED_

class axi4_random_test extends axi4_base_test;

    `uvm_component_utils(axi4_random_test)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Run phase - execute random mixed-traffic sequence
    // =========================================================================
    task run_phase(uvm_phase phase);
        axi4_random_seq rand_seq;
        int unsigned num_txns = 50; // Default number of transactions

        phase.raise_objection(this, "axi4_random_test: starting");

        // Allow overriding the transaction count from the command line
        if ($value$plusargs("NUM_TXNS=%d", num_txns)) begin
            `uvm_info(get_type_name(),
                      $sformatf("Command line +NUM_TXNS=%0d override detected", num_txns),
                      UVM_LOW)
        end

        `uvm_info(get_type_name(),
                  $sformatf("Starting random test with %0d transactions", num_txns),
                  UVM_LOW)

        // Create random sequence
        rand_seq = axi4_random_seq::type_id::create("rand_seq");
        rand_seq.num_txns = num_txns;

        // Start sequence on master sequencer
        rand_seq.start(env.master_agent.sqr);

        // Drain time - wait for outstanding responses to complete
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  $sformatf("Random test complete: %0d transactions executed", num_txns),
                  UVM_LOW)

        phase.drop_objection(this, "axi4_random_test: complete");
    endtask : run_phase

endclass : axi4_random_test

`endif // AXI4_RANDOM_TEST_INCLUDED_