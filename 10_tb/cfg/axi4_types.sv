//=============================================================================
// File        : axi4_types.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 parameters, enums, and typedefs.
//               Included inside the bridge package.
//=============================================================================

    //-------------------------------------------------------------------------
    // Bus parameters
    //-------------------------------------------------------------------------
    parameter int unsigned AXI4_ADDR_WIDTH = 32;
    parameter int unsigned AXI4_DATA_WIDTH = 32;
    parameter int unsigned AXI4_STRB_WIDTH = AXI4_DATA_WIDTH / 8;
    parameter int unsigned AXI4_ID_WIDTH   = 4;
    parameter int unsigned AXI4_LEN_WIDTH  = 8;

    //-------------------------------------------------------------------------
    // Protocol enumerations
    //-------------------------------------------------------------------------

    // Transaction direction
    typedef enum bit {
        AXI4_READ  = 1'b0,
        AXI4_WRITE = 1'b1
    } axi4_dir_e;

    // Burst type
    typedef enum bit [1:0] {
        AXI4_BURST_FIXED = 2'b00,
        AXI4_BURST_INCR  = 2'b01,
        AXI4_BURST_WRAP  = 2'b10
    } axi4_burst_e;

    // Transfer size
    typedef enum bit [2:0] {
        AXI4_SIZE_1BYTE   = 3'b000,
        AXI4_SIZE_2BYTE   = 3'b001,
        AXI4_SIZE_4BYTE   = 3'b010,
        AXI4_SIZE_8BYTE   = 3'b011,
        AXI4_SIZE_16BYTE  = 3'b100,
        AXI4_SIZE_32BYTE  = 3'b101,
        AXI4_SIZE_64BYTE  = 3'b110,
        AXI4_SIZE_128BYTE = 3'b111
    } axi4_size_e;

    // Lock type
    typedef enum bit {
        AXI4_LOCK_NORMAL    = 1'b0,
        AXI4_LOCK_EXCLUSIVE = 1'b1
    } axi4_lock_e;

    // Response type
    typedef enum bit [1:0] {
        AXI4_RESP_OKAY   = 2'b00,
        AXI4_RESP_EXOKAY = 2'b01,
        AXI4_RESP_SLVERR = 2'b10,
        AXI4_RESP_DECERR = 2'b11
    } axi4_resp_e;

    // Write-channel ordering
    typedef enum bit [1:0] {
        AXI4_WR_PARALLEL    = 2'b00,
        AXI4_WR_AW_BEFORE_W = 2'b01,
        AXI4_WR_W_BEFORE_AW = 2'b10
    } axi4_wr_order_e;