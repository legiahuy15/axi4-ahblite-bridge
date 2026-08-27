//=============================================================================
// File        : tb_top.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Top-level testbench module for the AHB-Lite VIP.
//               Generates clock and reset, instantiates the interface,
//               propagates the virtual interface to UVM config_db,
//               and starts the UVM phase execution via run_test().
//=============================================================================

`timescale 1ns/1ps

module tb_top;

    //-------------------------------------------------------------------------
    // Imports & Macros
    //-------------------------------------------------------------------------
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Import VIP and Test packages
    import ahb_pkg::*;
    import ahb_test_pkg::*;

    //-------------------------------------------------------------------------
    // Parameters (Match standard values used across agents & tests)
    //-------------------------------------------------------------------------
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    //-------------------------------------------------------------------------
    // Clock and Reset Generation
    //-------------------------------------------------------------------------
    bit clk;
    bit rst_n;

    // 100 MHz Clock (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset assertion (HRESETn is active low, held for 10 clock cycles)
    initial begin
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        `uvm_info("TB_TOP", "Reset de-asserted", UVM_MEDIUM)
    end

    //-------------------------------------------------------------------------
    // Mid-simulation reset - extra pulse requested by a test through the global
    // UVM event "ahb_reset_req", independent of the power-on reset
    //-------------------------------------------------------------------------
    initial begin
        automatic uvm_event reset_ev = uvm_event_pool::get_global("ahb_reset_req");
        forever begin
            reset_ev.wait_trigger();
            `uvm_info("TB_TOP", "Mid-sim reset requested - asserting rst_n", UVM_LOW)
            rst_n = 1'b0;
            repeat (8) @(posedge clk);
            rst_n = 1'b1;
            `uvm_info("TB_TOP", "Mid-sim reset pulse complete - rst_n deasserted", UVM_LOW)
        end
    end

    //-------------------------------------------------------------------------
    // Interface Instance
    //-------------------------------------------------------------------------
    ahb_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) intf (
        .clk(clk),
        .rst_n(rst_n)
    );

    //-------------------------------------------------------------------------
    // Time-0 signal initialisation - the drivers take the bus on their first
    // clocking edge, so the signals would otherwise be X at the first sampling
    // edge. Values match the drivers' reset_signals()
    //-------------------------------------------------------------------------
    initial begin
        intf.HADDR     = '0;
        intf.HBURST    = '0;       // SINGLE
        intf.HMASTLOCK = 1'b0;
        intf.HPROT     = '0;       // AHB_PROT_DEFAULT
        intf.HSIZE     = '0;
        intf.HTRANS    = '0;       // IDLE
        intf.HWDATA    = '0;
        intf.HWRITE    = 1'b0;
        intf.HRDATA    = '0;
        intf.HREADY    = 1'b1;
        intf.HRESP     = 1'b0;     // OKAY
    end

    //-------------------------------------------------------------------------
    // SVA - AHB-Lite protocol assertion checker
    //-------------------------------------------------------------------------
    ahb_sva #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_ahb_sva (
        .clk       (clk),
        .rst_n     (rst_n),
        // Master signals
        .HADDR     (intf.HADDR),
        .HBURST    (intf.HBURST),
        .HMASTLOCK (intf.HMASTLOCK),
        .HPROT     (intf.HPROT),
        .HSIZE     (intf.HSIZE),
        .HTRANS    (intf.HTRANS),
        .HWDATA    (intf.HWDATA),
        .HWRITE    (intf.HWRITE),
        // Slave signals
        .HRDATA    (intf.HRDATA),
        .HREADY    (intf.HREADY),
        .HRESP     (intf.HRESP)
    );

    //-------------------------------------------------------------------------
    // UVM Setup & Execution
    //-------------------------------------------------------------------------
    initial begin
        uvm_config_db#(virtual ahb_if)::set(null, "*", "vif", intf);
        `uvm_info("TB_TOP", "Virtual interface set in config_db", UVM_LOW)

        // Test selected with +UVM_TESTNAME
        run_test();
    end

    //-------------------------------------------------------------------------
    // Simulation Control & Waveform Dumping
    //-------------------------------------------------------------------------
    initial begin
        // Enable waveform dumping if requested by +DUMP_VCD plusarg
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("ahb_lite_vip.vcd");
            $dumpvars(0, tb_top);
            `uvm_info("TB_TOP", "Waveform VCD dumping enabled (ahb_lite_vip.vcd)", UVM_LOW)
        end
    end

    //-------------------------------------------------------------------------
    // Safety simulation watchdog - timeout in ns, overridable with +TIMEOUT_NS
    //-------------------------------------------------------------------------
    initial begin
        automatic longint unsigned timeout_ns = 10_000_000;  // 10 ms default backup
        void'($value$plusargs("TIMEOUT_NS=%d", timeout_ns));
        #(timeout_ns);
        `uvm_fatal("TB_TOP",
                   $sformatf("Simulation safety timeout reached (%0d ns)! Possible hang detected.",
                             timeout_ns))
    end

endmodule : tb_top