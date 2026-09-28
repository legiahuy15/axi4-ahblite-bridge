//=============================================================================
// File        : ahb_types.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite parameters, enums, and typedefs.
//               Included inside the bridge package.
//=============================================================================

    //-------------------------------------------------------------------------
    // Bus parameters
    //-------------------------------------------------------------------------
    // Same knobs as axi4_types.sv, repeated so this file does not depend on
    // the include order. The bridge requires equal widths on both sides.
`ifndef BRIDGE_DATA_WIDTH
    `define BRIDGE_DATA_WIDTH 32
`endif
`ifndef BRIDGE_ADDR_WIDTH
    `define BRIDGE_ADDR_WIDTH 32
`endif

    parameter int unsigned AHB_ADDR_WIDTH = `BRIDGE_ADDR_WIDTH;
    parameter int unsigned AHB_DATA_WIDTH = `BRIDGE_DATA_WIDTH;

    //-------------------------------------------------------------------------
    // Protocol enumerations
    //-------------------------------------------------------------------------

    // Transfer direction
    typedef enum bit {
        AHB_READ  = 1'b0,
        AHB_WRITE = 1'b1
    } ahb_dir_e;

    // Transfer type
    typedef enum bit [1:0] {
        AHB_TRANS_IDLE   = 2'b00,
        AHB_TRANS_BUSY   = 2'b01,
        AHB_TRANS_NONSEQ = 2'b10,
        AHB_TRANS_SEQ    = 2'b11
    } ahb_trans_e;

    // Burst type
    typedef enum bit [2:0] {
        AHB_BURST_SINGLE = 3'b000,
        AHB_BURST_INCR   = 3'b001,
        AHB_BURST_WRAP4  = 3'b010,
        AHB_BURST_INCR4  = 3'b011,
        AHB_BURST_WRAP8  = 3'b100,
        AHB_BURST_INCR8  = 3'b101,
        AHB_BURST_WRAP16 = 3'b110,
        AHB_BURST_INCR16 = 3'b111
    } ahb_burst_e;

    // Transfer size
    typedef enum bit [2:0] {
        AHB_SIZE_1BYTE   = 3'b000,
        AHB_SIZE_2BYTE   = 3'b001,
        AHB_SIZE_4BYTE   = 3'b010,
        AHB_SIZE_8BYTE   = 3'b011,
        AHB_SIZE_16BYTE  = 3'b100,
        AHB_SIZE_32BYTE  = 3'b101,
        AHB_SIZE_64BYTE  = 3'b110,
        AHB_SIZE_128BYTE = 3'b111
    } ahb_size_e;

    // Response type
    typedef enum bit {
        AHB_RESP_OKAY  = 1'b0,
        AHB_RESP_ERROR = 1'b1
    } ahb_resp_e;