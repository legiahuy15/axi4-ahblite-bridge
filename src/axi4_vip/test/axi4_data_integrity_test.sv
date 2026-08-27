//==============================================================================
// File        : axi4_data_integrity_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Data Integrity Test (Write-then-Read-back with known data).
//               Writes recognisable data patterns (0xDEADBEEF, 0xCAFEBABE, …)
//               and reads them back. On waveform: WDATA == RDATA is visually
//               obvious. Only 4 transactions - ideal for report screenshots.
//
//               Slave ready/response delays are intentionally set so that
//               each beat's data value persists on the bus for several clock
//               cycles, making waveform captures much clearer.
//               This file is `included inside axi4_test_pkg.sv.
//==============================================================================

`ifndef AXI4_DATA_INTEGRITY_TEST_INCLUDED_
`define AXI4_DATA_INTEGRITY_TEST_INCLUDED_

class axi4_data_integrity_test extends axi4_base_test;

    `uvm_component_utils(axi4_data_integrity_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase - configure slave delays for cleaner waveform
    //   ready_delay  : slave waits 1-2 cycles before asserting xREADY
    //   resp_delay   : slave waits 1-2 cycles before driving B/R response
    //   This stretches out each handshake so data values are visible
    //   for multiple clock cycles on waveform screenshots.
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env_cfg.slave_agent_cfg.ready_delay_min = 1;
        env_cfg.slave_agent_cfg.ready_delay_max = 2;
        env_cfg.slave_agent_cfg.resp_delay_min  = 1;
        env_cfg.slave_agent_cfg.resp_delay_max  = 2;
    endfunction : build_phase

    task run_phase(uvm_phase phase);
        axi4_data_integrity_seq integrity_seq;
        phase.raise_objection(this, "axi4_data_integrity_test: starting");

        `uvm_info(get_type_name(),
                  "Starting data integrity test (write known data -> read-back -> compare)",
                  UVM_LOW)

        integrity_seq = axi4_data_integrity_seq::type_id::create("integrity_seq");
        integrity_seq.start(env.master_agent.sqr);

        // Drain time
        repeat (50) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  "Data integrity test complete", UVM_LOW)
        phase.drop_objection(this, "axi4_data_integrity_test: complete");
    endtask : run_phase

endclass : axi4_data_integrity_test

`endif // AXI4_DATA_INTEGRITY_TEST_INCLUDED_