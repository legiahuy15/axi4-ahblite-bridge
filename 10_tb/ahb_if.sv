//=============================================================================
// File        : ahb_if.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite interface for the DUT master port and slave agent.
//=============================================================================

`timescale 1ns/1ps

`ifndef AHB_IF_INCLUDED_
`define AHB_IF_INCLUDED_

interface ahb_if #(
    parameter int unsigned AHB_ADDR_WIDTH = 32,
    parameter int unsigned AHB_DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    //-------------------------------------------------------------------------
    // Interface signals
    //-------------------------------------------------------------------------

    // Master signals
    logic [AHB_ADDR_WIDTH-1:0] HADDR;
    logic [2:0]                HBURST;
    logic                      HMASTLOCK;
    logic [3:0]                HPROT;
    logic [2:0]                HSIZE;
    logic [1:0]                HTRANS;
    logic [AHB_DATA_WIDTH-1:0] HWDATA;
    logic                      HWRITE;

    // Slave signals
    logic [AHB_DATA_WIDTH-1:0] HRDATA;
    logic                      HREADY;
    logic                      HRESP;

    //-------------------------------------------------------------------------
    // Slave clocking block
    //-------------------------------------------------------------------------
    clocking slave_cb @(posedge clk);
        default input #1step output #1;
        input  HADDR, HBURST, HMASTLOCK, HPROT;
        input  HSIZE, HTRANS, HWDATA, HWRITE;
        output HRDATA, HREADY, HRESP;
    endclocking : slave_cb

    //-------------------------------------------------------------------------
    // Monitor clocking block
    //-------------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;
        input HADDR, HBURST, HMASTLOCK, HPROT;
        input HSIZE, HTRANS, HWDATA, HWRITE;
        input HRDATA, HREADY, HRESP;
    endclocking : monitor_cb

    //-------------------------------------------------------------------------
    // Modports
    //-------------------------------------------------------------------------
    modport slave_mp   (clocking slave_cb,   input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : ahb_if

`endif // AHB_IF_INCLUDED_