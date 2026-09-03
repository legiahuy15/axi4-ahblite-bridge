//=============================================================================
// File        : ahb_if.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite bus interface. Provides master-driver, slave-driver,
//               and monitor clocking blocks with matching modports.
//=============================================================================

`timescale 1ns/1ps

`ifndef AHB_IF_INCLUDED_
`define AHB_IF_INCLUDED_

interface ahb_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    //-------------------------------------------------------------------------
    // Master signals
    //-------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] HADDR;
    logic [2:0]            HBURST;
    logic                  HMASTLOCK;
    logic [3:0]            HPROT;
    logic [2:0]            HSIZE;
    logic [1:0]            HTRANS;
    logic [DATA_WIDTH-1:0] HWDATA;
    logic                  HWRITE;

    //-------------------------------------------------------------------------
    // Slave signals
    //-------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] HRDATA;
    logic                  HREADY;
    logic                  HRESP;

    //-------------------------------------------------------------------------
    // Master driver clocking block: drives address/control/HWDATA, samples response
    //-------------------------------------------------------------------------
    clocking master_cb @(posedge clk);
        default input #1step output #1;
        output HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWDATA, HWRITE;
        input  HRDATA, HREADY, HRESP;
    endclocking

    //-------------------------------------------------------------------------
    // Slave driver clocking block: drives HRDATA/HREADY/HRESP, samples address/control
    //-------------------------------------------------------------------------
    clocking slave_cb @(posedge clk);
        default input #1step output #1;
        input  HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWDATA, HWRITE;
        output HRDATA, HREADY, HRESP;
    endclocking

    //-------------------------------------------------------------------------
    // Monitor clocking block: samples all signals (passive)
    //-------------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;
        input HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWDATA, HWRITE;
        input HRDATA, HREADY, HRESP;
    endclocking

    //-------------------------------------------------------------------------
    // Modports
    //-------------------------------------------------------------------------
    modport master_mp  (clocking master_cb,  input clk, input rst_n);
    modport slave_mp   (clocking slave_cb,   input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

    endinterface : ahb_if

`endif // AHB_IF_INCLUDED_