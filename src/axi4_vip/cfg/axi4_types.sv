//==============================================================================
// File        : axi4_types.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 protocol parameters, enums, and typedefs.
//               All values follow ARM AMBA AXI4 specification (IHI0022E).
//               This file is `included inside axi4_pkg.sv - do NOT add
//               package/endpackage here.
//==============================================================================

    //-------------------------------------------------------------------------
    // 1. Bus-width parameters
    //-------------------------------------------------------------------------
    parameter AXI4_ADDR_WIDTH = 32;                    // Address bus width
    parameter AXI4_DATA_WIDTH = 32;                    // Data bus width
    parameter AXI4_STRB_WIDTH = AXI4_DATA_WIDTH / 8;   // 1 strobe bit per byte lane
    parameter AXI4_ID_WIDTH   = 4;                     // Transaction ID width
    parameter AXI4_LEN_WIDTH  = 8;                     // Burst length field (AXI4 = 8-bit)

    //-------------------------------------------------------------------------
    // 2. Burst type
    //    Defines how the address is calculated for each transfer in a burst.
    //        FIXED - same address for every transfer  (e.g. FIFO access)
    //        INCR  - incrementing address             (most common)
    //        WRAP  - wrapping burst                   (cache-line fills)
    //-------------------------------------------------------------------------
    typedef enum bit [1:0] {
        AXI4_BURST_FIXED = 2'b00,
        AXI4_BURST_INCR  = 2'b01,
        AXI4_BURST_WRAP  = 2'b10
        // 2'b11 is reserved
    } axi4_burst_type_e;

    //-------------------------------------------------------------------------
    // 3. Response type
    //    Indicates the status of a read/write transaction.
    //        OKAY   - normal access success
    //        EXOKAY - exclusive access success
    //        SLVERR - slave error (valid address, slave-side failure)
    //        DECERR - decode error (no slave at that address)
    //-------------------------------------------------------------------------
    typedef enum bit [1:0] {
        AXI4_RESP_OKAY   = 2'b00,
        AXI4_RESP_EXOKAY = 2'b01,
        AXI4_RESP_SLVERR = 2'b10,
        AXI4_RESP_DECERR = 2'b11
    } axi4_resp_e;

    //-------------------------------------------------------------------------
    // 4. Burst size
    //      Number of bytes per transfer = 2^SIZE.
    //      Must not exceed the data bus width (DATA_WIDTH / 8 bytes).
    //-------------------------------------------------------------------------
    typedef enum bit [2:0] {
        AXI4_SIZE_1B   = 3'b000,   //   1 byte  per transfer
        AXI4_SIZE_2B   = 3'b001,   //   2 bytes per transfer
        AXI4_SIZE_4B   = 3'b010,   //   4 bytes per transfer  ← max for 32-bit bus
        AXI4_SIZE_8B   = 3'b011,   //   8 bytes per transfer
        AXI4_SIZE_16B  = 3'b100,   //  16 bytes per transfer
        AXI4_SIZE_32B  = 3'b101,   //  32 bytes per transfer
        AXI4_SIZE_64B  = 3'b110,   //  64 bytes per transfer
        AXI4_SIZE_128B = 3'b111    // 128 bytes per transfer
    } axi4_size_e;

    //-------------------------------------------------------------------------
    // 5. Lock type
    //        NORMAL    - normal access
    //        EXCLUSIVE - exclusive access (for atomic read-modify-write)
    //-------------------------------------------------------------------------
    typedef enum bit {
        AXI4_LOCK_NORMAL    = 1'b0,
        AXI4_LOCK_EXCLUSIVE = 1'b1
    } axi4_lock_e;

    //-------------------------------------------------------------------------
    // 6. Transaction direction (VIP-internal, not in AXI spec)
    //      Used inside the sequence item to distinguish write vs read.
    //-------------------------------------------------------------------------
    typedef enum bit {
        AXI4_READ  = 1'b0,
        AXI4_WRITE = 1'b1
    } axi4_dir_e;

    //-------------------------------------------------------------------------
    // 7. Write channel ordering (VIP-internal, not in AXI spec)
    //      Controls the relative timing of AW and W channels.
    //        PARALLEL   - AW and W start simultaneously (default, most common)
    //        AW_BEFORE_W - AW handshake completes before W data begins
    //        W_BEFORE_AW - W data begins before AW address is sent
    //-------------------------------------------------------------------------
    typedef enum bit [1:0] {
        AXI4_WR_PARALLEL    = 2'b00,
        AXI4_WR_AW_BEFORE_W = 2'b01,
        AXI4_WR_W_BEFORE_AW = 2'b10
    } axi4_wr_order_e;

    //-------------------------------------------------------------------------
    // 8. Event wrapper class
    //    Used to wrap SystemVerilog built-in event type, because event is not a
    //    class and cannot be dynamically instantiated with 'new'.
    //-------------------------------------------------------------------------
    class axi4_event_wrapper;
        event ev;
    endclass