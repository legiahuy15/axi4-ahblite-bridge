//=============================================================================
// File        : axi4_if.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 full interface with all 5 channels.
//               Includes clocking blocks for master driver, slave driver,
//               and monitor to avoid race conditions.
//               Signal widths use parameters from axi4_types.sv.
//=============================================================================

`timescale 1ns/1ps

`ifndef AXI4_IF_INCLUDED_
`define AXI4_IF_INCLUDED_

interface axi4_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input logic clk,
    input logic rst_n
);

    // Derived parameter
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    //-------------------------------------------------------------------------
    // AW Channel - Write Address (Master -> Slave)
    //-------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]    AWID;
    logic [ADDR_WIDTH-1:0]  AWADDR;
    logic [7:0]             AWLEN;      // Burst length    (length = AWLEN+1)
    logic [2:0]             AWSIZE;     // Burst size      (bytes = 2^AWSIZE)
    logic [1:0]             AWBURST;    // Burst type      (FIXED/INCR/WRAP)
    logic                   AWLOCK;     // Lock type       (NORMAL/EXCLUSIVE)
    logic [3:0]             AWCACHE;    // Cache type
    logic [2:0]             AWPROT;     // Protection type
    logic [3:0]             AWQOS;      // Quality of Service
    logic [3:0]             AWREGION;   // Region identifier
    logic                   AWVALID;
    logic                   AWREADY;

    //-------------------------------------------------------------------------
    // W Channel - Write Data (Master -> Slave)
    //-------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0]  WDATA;
    logic [STRB_WIDTH-1:0]  WSTRB;     // 1 bit per byte lane
    logic                   WLAST;     // Last transfer in burst
    logic                   WVALID;
    logic                   WREADY;

    //-------------------------------------------------------------------------
    // B Channel - Write Response (Slave -> Master)
    //-------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]    BID;
    logic [1:0]             BRESP;
    logic                   BVALID;
    logic                   BREADY;

    //-------------------------------------------------------------------------
    // AR Channel - Read Address (Master -> Slave)
    //-------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]    ARID;
    logic [ADDR_WIDTH-1:0]  ARADDR;
    logic [7:0]             ARLEN;
    logic [2:0]             ARSIZE;
    logic [1:0]             ARBURST;
    logic                   ARLOCK;
    logic [3:0]             ARCACHE;
    logic [2:0]             ARPROT;
    logic [3:0]             ARQOS;
    logic [3:0]             ARREGION;
    logic                   ARVALID;
    logic                   ARREADY;

    //-------------------------------------------------------------------------
    // R Channel - Read Data (Slave -> Master)
    //-------------------------------------------------------------------------
    logic [ID_WIDTH-1:0]    RID;
    logic [DATA_WIDTH-1:0]  RDATA;
    logic [1:0]             RRESP;
    logic                   RLAST;
    logic                   RVALID;
    logic                   RREADY;

    //-------------------------------------------------------------------------
    // Clocking Block: Master Driver
    //   - Drives  : AW*, W*, BREADY, AR*, RREADY  (master-to-slave + ready)
    //   - Samples : AWREADY, WREADY, B*, ARREADY, R* (slave-to-master + ready)
    //-------------------------------------------------------------------------
    clocking master_cb @(posedge clk);
        default input #1step output #1;
        // AW channel (master drives)
        output AWID, AWADDR, AWLEN, AWSIZE, AWBURST;
        output AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION;
        output AWVALID;
        input  AWREADY;
        // W channel (master drives)
        output WDATA, WSTRB, WLAST;
        output WVALID;
        input  WREADY;
        // B channel (master receives)
        input  BID, BRESP, BVALID;
        output BREADY;
        // AR channel (master drives)
        output ARID, ARADDR, ARLEN, ARSIZE, ARBURST;
        output ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION;
        output ARVALID;
        input  ARREADY;
        // R channel (master receives)
        input  RID, RDATA, RRESP, RLAST, RVALID;
        output RREADY;
    endclocking

    //-------------------------------------------------------------------------
    // Clocking Block: Slave Driver
    //   - Drives  : AWREADY, WREADY, B*, ARREADY, R*  (slave-to-master + ready)
    //   - Samples : AW*, W*, BREADY, AR*, RREADY      (master-to-slave + ready)
    //-------------------------------------------------------------------------
    clocking slave_cb @(posedge clk);
        default input #1step output #1;
        // AW channel (slave receives)
        input  AWID, AWADDR, AWLEN, AWSIZE, AWBURST;
        input  AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION;
        input  AWVALID;
        output AWREADY;
        // W channel (slave receives)
        input  WDATA, WSTRB, WLAST;
        input  WVALID;
        output WREADY;
        // B channel (slave drives)
        output BID, BRESP, BVALID;
        input  BREADY;
        // AR channel (slave receives)
        input  ARID, ARADDR, ARLEN, ARSIZE, ARBURST;
        input  ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION;
        input  ARVALID;
        output ARREADY;
        // R channel (slave drives)
        output RID, RDATA, RRESP, RLAST, RVALID;
        input  RREADY;
    endclocking

    //-------------------------------------------------------------------------
    // Clocking Block: Monitor
    //   - Samples all signals (passive observation only)
    //-------------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1step;
        // AW channel
        input AWID, AWADDR, AWLEN, AWSIZE, AWBURST;
        input AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION;
        input AWVALID, AWREADY;
        // W channel
        input WDATA, WSTRB, WLAST;
        input WVALID, WREADY;
        // B channel
        input BID, BRESP;
        input BVALID, BREADY;
        // AR channel
        input ARID, ARADDR, ARLEN, ARSIZE, ARBURST;
        input ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION;
        input ARVALID, ARREADY;
        // R channel
        input RID, RDATA, RRESP, RLAST;
        input RVALID, RREADY;
    endclocking

    //-------------------------------------------------------------------------
    // Modports
    //-------------------------------------------------------------------------
    modport master_mp  (clocking master_cb,  input clk, input rst_n);
    modport slave_mp   (clocking slave_cb,   input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : axi4_if

`endif // AXI4_IF_INCLUDED_