//==============================================================================
// File        : axi4_out_of_order_test.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : Out-of-Order transactions test.
//               Executes a sequence generating concurrent read and write
//               bursts with different IDs, configuring the slave driver to
//               return read responses out-of-order without interleaving.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_OUT_OF_ORDER_TEST_INCLUDED_
`define AXI4_OUT_OF_ORDER_TEST_INCLUDED_

class axi4_out_of_order_test extends axi4_base_test;

    `uvm_component_utils(axi4_out_of_order_test)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Configurable knobs
    // =========================================================================
    int unsigned depth      = 4;
    bit          r_reorder  = 1;

    // =========================================================================
    // Build phase - push slave-driver config BEFORE env/agent/drv are built
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
    // Run phase - execute out-of-order sequence
    // =========================================================================
    task run_phase(uvm_phase phase);
        axi4_out_of_order_seq ooo_seq;
        int unsigned num_writes = 15;
        int unsigned num_reads  = 15;

        phase.raise_objection(this, "axi4_out_of_order_test: starting");

        // Allow command-line overrides
        void'($value$plusargs("NUM_WRITES=%d", num_writes));
        void'($value$plusargs("NUM_READS=%d", num_reads));

        `uvm_info(get_type_name(),
                  $sformatf("Starting Out-of-Order test with %0d writes, %0d reads, depth=%0d, r_reorder=%0b (no-interleaving)",
                            num_writes, num_reads, depth, r_reorder),
                  UVM_LOW)

        // Create outstanding/ooo sequence
        ooo_seq = axi4_out_of_order_seq::type_id::create("ooo_seq");
        ooo_seq.num_writes        = num_writes;
        ooo_seq.num_reads         = num_reads;
        ooo_seq.outstanding_depth = depth;

        // Start sequence on master sequencer
        ooo_seq.start(env.master_agent.sqr);

        // Drain time - wait for outstanding responses to complete
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Out-of-Order test completed successfully", UVM_LOW)

        phase.drop_objection(this, "axi4_out_of_order_test: complete");
    endtask : run_phase

endclass : axi4_out_of_order_test

`endif // AXI4_OUT_OF_ORDER_TEST_INCLUDED_