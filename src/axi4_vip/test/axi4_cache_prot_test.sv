//==============================================================================
// File        : axi4_cache_prot_test.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : Test to sweep all AXI4 cache and protection combinations.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_CACHE_PROT_TEST_INCLUDED_
`define AXI4_CACHE_PROT_TEST_INCLUDED_

class axi4_cache_prot_test extends axi4_base_test;

    `uvm_component_utils(axi4_cache_prot_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    task run_phase(uvm_phase phase);
        axi4_cache_prot_seq cp_seq;
        phase.raise_objection(this, "axi4_cache_prot_test: starting");

        `uvm_info(get_type_name(), "Starting cache and protection attributes sweep test", UVM_LOW)

        cp_seq = axi4_cache_prot_seq::type_id::create("cp_seq");
        cp_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (100) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(), "Cache and protection sweep test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_cache_prot_test: complete");
    endtask : run_phase

endclass : axi4_cache_prot_test

`endif // AXI4_CACHE_PROT_TEST_INCLUDED_