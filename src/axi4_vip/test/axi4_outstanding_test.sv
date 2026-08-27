//==============================================================================
// File        : axi4_outstanding_seq_test.sv (axi4_outstanding_test.sv)
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Outstanding transactions test.
//               Executes a sequence generating concurrent read and write
//               bursts to stress-test the VIP's tracking of outstanding
//               transactions and response matching.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_OUTSTANDING_TEST_INCLUDED_
`define AXI4_OUTSTANDING_TEST_INCLUDED_

class axi4_outstanding_test extends axi4_base_test;

    `uvm_component_utils(axi4_outstanding_test)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Configurable knobs (class members so both phases can access)
    // =========================================================================
    int unsigned depth      = 4;
    bit          r_reorder  = 1;

    // =========================================================================
    // Build phase - push slave-driver config BEFORE env/agent/drv are built
    //   UVM phase order: build -> connect -> … -> run
    //   Slave driver reads config_db in its build_phase, so we must set
    //   the values here, before super.build_phase() creates the env tree.
    // =========================================================================
    function void build_phase(uvm_phase phase);
        // Allow command-line overrides (available at elaboration time)
        void'($value$plusargs("OUTSTANDING_DEPTH=%d", depth));
        void'($value$plusargs("R_REORDER_EN=%d", r_reorder));

        // Push config BEFORE super.build_phase creates env -> slave_agent -> drv
        uvm_config_db#(bit)::set(this, "env.slave_agent.drv",
                                 "r_reorder_enable", r_reorder);
        uvm_config_db#(int unsigned)::set(this, "env.slave_agent.drv",
                                          "r_outstanding_max", depth);

        super.build_phase(phase);
    endfunction : build_phase

    // =========================================================================
    // Run phase - execute outstanding sequence
    // =========================================================================
    task run_phase(uvm_phase phase);
        axi4_outstanding_seq outstanding_seq;
        int unsigned num_writes = 15;
        int unsigned num_reads  = 15;

        phase.raise_objection(this, "axi4_outstanding_test: starting");

        // Allow command-line overrides
        void'($value$plusargs("NUM_WRITES=%d", num_writes));
        void'($value$plusargs("NUM_READS=%d", num_reads));

        `uvm_info(get_type_name(),
                  $sformatf("Starting outstanding test with %0d writes, %0d reads, depth=%0d, r_reorder=%0b",
                            num_writes, num_reads, depth, r_reorder),
                  UVM_LOW)

        // Create outstanding sequence
        outstanding_seq = axi4_outstanding_seq::type_id::create("outstanding_seq");
        outstanding_seq.num_writes        = num_writes;
        outstanding_seq.num_reads         = num_reads;
        outstanding_seq.outstanding_depth = depth;

        // Start sequence on master sequencer
        outstanding_seq.start(env.master_agent.sqr);

        // Drain time - wait for outstanding responses to complete
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Outstanding test completed successfully", UVM_LOW)

        phase.drop_objection(this, "axi4_outstanding_test: complete");
    endtask : run_phase

endclass : axi4_outstanding_test

`endif // AXI4_OUTSTANDING_TEST_INCLUDED_