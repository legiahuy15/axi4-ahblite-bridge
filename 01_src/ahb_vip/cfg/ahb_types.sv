//==============================================================================
// File        : ahb_types.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite protocol parameters, enums, and typedefs (IHI0033A).
//               Included inside ahb_pkg.sv - do NOT add package/endpackage here.
//==============================================================================

    // ---------------------------------------------------------------------------
    // Bus-width parameters
    // ---------------------------------------------------------------------------
    parameter AHB_ADDR_WIDTH = 32;                   // Address bus width
    parameter AHB_DATA_WIDTH = 32;                   // Data bus width

    // ---------------------------------------------------------------------------
    // Burst type - HBURST[2:0]
    // ---------------------------------------------------------------------------
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

    // ---------------------------------------------------------------------------
    // Protection control - HPROT[3:0]
    //    [0] data/opcode  [1] privileged/user  [2] bufferable  [3] cacheable
    // ---------------------------------------------------------------------------
    typedef enum bit [3:0] {
        AHB_PROT_DEFAULT        = 4'b0000,   // Opcode, user, non-bufferable, non-cacheable
        AHB_PROT_DATA           = 4'b0001,   // Data access
        AHB_PROT_PRIVILEGED     = 4'b0010,   // Privileged access
        AHB_PROT_BUFFERABLE     = 4'b0100,   // Bufferable
        AHB_PROT_CACHEABLE      = 4'b1000    // Cacheable
    } ahb_prot_e;

    // ---------------------------------------------------------------------------
    // Transfer size - HSIZE[2:0]
    //    Bytes per transfer = 2^HSIZE; must not exceed DATA_WIDTH/8
    // ---------------------------------------------------------------------------
    typedef enum bit [2:0] {
        AHB_SIZE_8B    = 3'b000,   //   1 byte   (8 bits)
        AHB_SIZE_16B   = 3'b001,   //   2 bytes  (16 bits)
        AHB_SIZE_32B   = 3'b010,   //   4 bytes  (32 bits)  <- max for 32-bit bus
        AHB_SIZE_64B   = 3'b011,   //   8 bytes  (64 bits)
        AHB_SIZE_128B  = 3'b100,   //  16 bytes  (128 bits)
        AHB_SIZE_256B  = 3'b101,   //  32 bytes  (256 bits)
        AHB_SIZE_512B  = 3'b110,   //  64 bytes  (512 bits)
        AHB_SIZE_1024B = 3'b111    // 128 bytes  (1024 bits)
    } ahb_size_e;

    // ---------------------------------------------------------------------------
    // Transfer type - HTRANS[1:0]
    //    IDLE   - no transfer
    //    BUSY   - idle cycle within a burst
    //    NONSEQ - first beat of a burst (or single)
    //    SEQ    - subsequent beats
    // ---------------------------------------------------------------------------
    typedef enum bit [1:0] {
        AHB_TRANS_IDLE   = 2'b00,
        AHB_TRANS_BUSY   = 2'b01,
        AHB_TRANS_NONSEQ = 2'b10,
        AHB_TRANS_SEQ    = 2'b11
    } ahb_trans_e;

    // ---------------------------------------------------------------------------
    // Direction control - HWRITE
    //    Constant throughout a burst
    // ---------------------------------------------------------------------------
    typedef enum bit {
        AHB_READ  = 1'b0,
        AHB_WRITE = 1'b1
    } ahb_dir_e;

    // ---------------------------------------------------------------------------
    // Transfer response - HRESP (single-bit in AHB-Lite)
    //    OKAY  - success
    //    ERROR - transfer error
    // ---------------------------------------------------------------------------
    typedef enum bit {
        AHB_RESP_OKAY  = 1'b0,
        AHB_RESP_ERROR = 1'b1
    } ahb_resp_e;
