//=============================================================================
// File        : axi4_if.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 interface for the master agent and DUT slave port.
//=============================================================================

`timescale 1ns/1ps

`ifndef AXI4_IF_INCLUDED_
`define AXI4_IF_INCLUDED_

interface axi4_if #(
    parameter int unsigned AXI4_ADDR_WIDTH = 32,
    parameter int unsigned AXI4_DATA_WIDTH = 32,
    parameter int unsigned AXI4_ID_WIDTH   = 4
)(
    input logic clk,
    input logic rst_n
);

    localparam int unsigned AXI4_STRB_WIDTH = AXI4_DATA_WIDTH / 8;

    //-------------------------------------------------------------------------
    // Interface signals
    //-------------------------------------------------------------------------

    // Write address channel
    logic [AXI4_ID_WIDTH-1:0]   AWID;
    logic [AXI4_ADDR_WIDTH-1:0] AWADDR;
    logic [7:0]                 AWLEN;
    logic [2:0]                 AWSIZE;
    logic [1:0]                 AWBURST;
    logic                       AWLOCK;
    logic [3:0]                 AWCACHE;
    logic [2:0]                 AWPROT;
    logic                       AWVALID;
    logic                       AWREADY;

    // Write data channel
    logic [AXI4_DATA_WIDTH-1:0] WDATA;
    logic [AXI4_STRB_WIDTH-1:0] WSTRB;
    logic                       WLAST;
    logic                       WVALID;
    logic                       WREADY;

    // Write response channel
    logic [AXI4_ID_WIDTH-1:0]   BID;
    logic [1:0]                 BRESP;
    logic                       BVALID;
    logic                       BREADY;

    // Read address channel
    logic [AXI4_ID_WIDTH-1:0]   ARID;
    logic [AXI4_ADDR_WIDTH-1:0] ARADDR;
    logic [7:0]                 ARLEN;
    logic [2:0]                 ARSIZE;
    logic [1:0]                 ARBURST;
    logic                       ARLOCK;
    logic [3:0]                 ARCACHE;
    logic [2:0]                 ARPROT;
    logic                       ARVALID;
    logic                       ARREADY;

    // Read data channel
    logic [AXI4_ID_WIDTH-1:0]   RID;
    logic [AXI4_DATA_WIDTH-1:0] RDATA;
    logic [1:0]                 RRESP;
    logic                       RLAST;
    logic                       RVALID;
    logic                       RREADY;

    //-------------------------------------------------------------------------
    // Master clocking block
    //-------------------------------------------------------------------------
    clocking master_cb @(posedge clk);
        default input #1step output #1;

        output AWID, AWADDR, AWLEN, AWSIZE, AWBURST;
        output AWLOCK, AWCACHE, AWPROT, AWVALID;
        input  AWREADY;

        output WDATA, WSTRB, WLAST, WVALID;
        input  WREADY;

        input  BID, BRESP, BVALID;
        output BREADY;

        output ARID, ARADDR, ARLEN, ARSIZE, ARBURST;
        output ARLOCK, ARCACHE, ARPROT, ARVALID;
        input  ARREADY;

        input  RID, RDATA, RRESP, RLAST, RVALID;
        output RREADY;
    endclocking : master_cb

    //-------------------------------------------------------------------------
    // Monitor clocking block
    //-------------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;

        input AWID, AWADDR, AWLEN, AWSIZE, AWBURST;
        input AWLOCK, AWCACHE, AWPROT, AWVALID, AWREADY;
        input WDATA, WSTRB, WLAST, WVALID, WREADY;
        input BID, BRESP, BVALID, BREADY;
        input ARID, ARADDR, ARLEN, ARSIZE, ARBURST;
        input ARLOCK, ARCACHE, ARPROT, ARVALID, ARREADY;
        input RID, RDATA, RRESP, RLAST, RVALID, RREADY;
    endclocking : monitor_cb

    //-------------------------------------------------------------------------
    // Modports
    //-------------------------------------------------------------------------
    modport master_mp  (clocking master_cb,  input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : axi4_if

`endif // AXI4_IF_INCLUDED_