//=============================================================================
// File        : ahb_sva.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite protocol and bridge-profile assertions.
//=============================================================================

`timescale 1ns/1ps

module ahb_sva #(
    parameter int unsigned AHB_ADDR_WIDTH      = 32,
    parameter int unsigned AHB_DATA_WIDTH      = 32,
    parameter bit          CHECK_BRIDGE_PROFILE = 1'b1
)(
    input logic                        clk,
    input logic                        rst_n,

    input logic [AHB_ADDR_WIDTH-1:0]   HADDR,
    input logic [2:0]                  HBURST,
    input logic                        HMASTLOCK,
    input logic [3:0]                  HPROT,
    input logic [2:0]                  HSIZE,
    input logic [1:0]                  HTRANS,
    input logic [AHB_DATA_WIDTH-1:0]   HWDATA,
    input logic                        HWRITE,

    input logic [AHB_DATA_WIDTH-1:0]   HRDATA,
    input logic                        HREADY,
    input logic                        HRESP
);

    //-------------------------------------------------------------------------
    // Protocol constants and checker state
    //-------------------------------------------------------------------------
    localparam logic [1:0] TRANS_IDLE   = 2'b00;
    localparam logic [1:0] TRANS_BUSY   = 2'b01;
    localparam logic [1:0] TRANS_NONSEQ = 2'b10;
    localparam logic [1:0] TRANS_SEQ    = 2'b11;

    localparam logic [2:0] BURST_SINGLE = 3'b000;
    localparam logic [2:0] BURST_INCR   = 3'b001;
    localparam logic [2:0] BURST_WRAP4  = 3'b010;
    localparam logic [2:0] BURST_INCR4  = 3'b011;
    localparam logic [2:0] BURST_WRAP8  = 3'b100;
    localparam logic [2:0] BURST_INCR8  = 3'b101;
    localparam logic [2:0] BURST_WRAP16 = 3'b110;
    localparam logic [2:0] BURST_INCR16 = 3'b111;

    wire [31:0] bytes_per_beat = 32'd1 << HSIZE;
    wire active_transfer =
        (HTRANS == TRANS_NONSEQ) || (HTRANS == TRANS_SEQ);

    bit reset_active_q;
    bit data_phase_active;
    bit data_phase_write;

    // Address and size of the last issued NONSEQ/SEQ beat. The bridge drives
    // BUSY between the beats of a burst and holds it through wait states, so
    // the previous beat of a burst is not $past(HADDR): BUSY cycles and wait
    // cycles sit in between. The address rules below compare against this
    // instead, which is what "the previous transfer" means in AHB-Lite.
    bit [AHB_ADDR_WIDTH-1:0] last_beat_addr;
    bit [2:0]                last_beat_size;
    bit                      last_beat_valid;

    //-------------------------------------------------------------------------
    // Address helper
    //-------------------------------------------------------------------------
    function automatic logic [AHB_ADDR_WIDTH-1:0] wrap_next_addr(
        input logic [AHB_ADDR_WIDTH-1:0] addr,
        input logic [2:0]                size,
        input int unsigned               beats
    );
        longint unsigned bytes;
        longint unsigned wrap_bytes;
        logic [AHB_ADDR_WIDTH-1:0] boundary;
        logic [AHB_ADDR_WIDTH-1:0] next_addr;

        bytes      = 1 << size;
        wrap_bytes = beats * bytes;
        boundary   = (addr / wrap_bytes) * wrap_bytes;
        next_addr  = addr + bytes;
        if (next_addr >= boundary + wrap_bytes)
            next_addr = boundary;
        return next_addr;
    endfunction : wrap_next_addr

    //-------------------------------------------------------------------------
    // Parameter checks
    //-------------------------------------------------------------------------
    initial begin
        if (AHB_ADDR_WIDTH < 32 || AHB_ADDR_WIDTH > 64)
            $fatal(1, "[AHB_SVA] Illegal AHB_ADDR_WIDTH=%0d", AHB_ADDR_WIDTH);
        if (!(AHB_DATA_WIDTH inside {32, 64}))
            $fatal(1, "[AHB_SVA] Illegal AHB_DATA_WIDTH=%0d", AHB_DATA_WIDTH);
    end

    //-------------------------------------------------------------------------
    // Data-phase tracking
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        reset_active_q <= !rst_n;
        if (!rst_n) begin
            data_phase_active <= 1'b0;
            data_phase_write  <= 1'b0;
        end else if (HREADY) begin
            data_phase_active <= active_transfer;
            data_phase_write  <= HWRITE;
        end
    end

    //-------------------------------------------------------------------------
    // Previous-beat tracking
    //-------------------------------------------------------------------------
    // A beat is issued on a rising edge with HREADY high and HTRANS NONSEQ or
    // SEQ. BUSY leaves the reference beat alone, because BUSY only stretches
    // the burst. IDLE ends the burst, so the next NONSEQ starts fresh and no
    // address relation is checked across it.
    always @(posedge clk) begin
        if (!rst_n) begin
            last_beat_addr  <= '0;
            last_beat_size  <= '0;
            last_beat_valid <= 1'b0;
        end else if (HREADY) begin
            if (active_transfer) begin
                last_beat_addr  <= HADDR;
                last_beat_size  <= HSIZE;
                last_beat_valid <= 1'b1;
            end else if (HTRANS == TRANS_IDLE) begin
                last_beat_valid <= 1'b0;
            end
        end
    end

    wire [31:0] last_beat_bytes = 32'd1 << last_beat_size;

    //-------------------------------------------------------------------------
    // Reset
    //-------------------------------------------------------------------------
    property p_reset_defaults;
        @(posedge clk)
        (!rst_n && reset_active_q) |->
            (HTRANS == TRANS_IDLE && HREADY && !HRESP);
    endproperty

    // Address and control outputs during reset. Kept apart from
    // RESET_DEFAULTS, which is about the bus handshake, so a failure names
    // which of the two rules broke. Values are the reset assignments of
    // ahb_mstr_if: HADDR, HBURST, HSIZE, HWRITE and HMASTLOCK clear, while
    // HPROT resets to 4'b0011 and is checked by RESET_HPROT.
    property p_reset_ahb_control;
        @(posedge clk)
        (!rst_n && reset_active_q) |->
            ((HADDR == '0) && (HBURST == BURST_SINGLE) && (HSIZE == '0) &&
             !HWRITE && !HMASTLOCK);
    endproperty

    RESET_DEFAULTS: assert property (p_reset_defaults)
        else $error("[AHB_SVA] Illegal bus state during reset");
    RESET_AHB_CONTROL: assert property (p_reset_ahb_control)
        else $error("[AHB_SVA] AHB address/control not at reset defaults");

    //-------------------------------------------------------------------------
    // Signal integrity
    //-------------------------------------------------------------------------
    property p_control_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown({HTRANS, HREADY, HRESP});
    endproperty

    property p_active_payload_known;
        @(posedge clk) disable iff (!rst_n)
        active_transfer |->
            !$isunknown({HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HWRITE});
    endproperty

    property p_wdata_known;
        @(posedge clk) disable iff (!rst_n)
        (data_phase_active && data_phase_write) |-> !$isunknown(HWDATA);
    endproperty

    property p_rdata_known;
        @(posedge clk) disable iff (!rst_n)
        (data_phase_active && !data_phase_write && HREADY && !HRESP) |->
            !$isunknown(HRDATA);
    endproperty

    CONTROL_KNOWN: assert property (p_control_known)
        else $error("[AHB_SVA] HTRANS/HREADY/HRESP contains X/Z");
    ACTIVE_PAYLOAD_KNOWN: assert property (p_active_payload_known)
        else $error("[AHB_SVA] Active address phase contains X/Z");
    WDATA_KNOWN: assert property (p_wdata_known)
        else $error("[AHB_SVA] HWDATA contains X/Z");
    RDATA_KNOWN: assert property (p_rdata_known)
        else $error("[AHB_SVA] HRDATA contains X/Z");

    //-------------------------------------------------------------------------
    // Wait states
    //-------------------------------------------------------------------------
    property p_addr_ctrl_stable_during_wait;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && HTRANS != TRANS_IDLE) |=>
            (HTRANS == TRANS_IDLE) ||
            ($past(HTRANS) == TRANS_BUSY && HTRANS == TRANS_SEQ &&
             $stable({HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HWRITE})) ||
            ($past(HTRANS) == TRANS_BUSY && $past(HBURST) == BURST_INCR &&
             HTRANS == TRANS_NONSEQ) ||
            $stable({HADDR, HBURST, HMASTLOCK, HPROT, HSIZE, HTRANS, HWRITE});
    endproperty

    property p_wdata_stable_during_wait;
        @(posedge clk) disable iff (!rst_n)
        (!HREADY && data_phase_active && data_phase_write) |=>
            $stable(HWDATA) || (HTRANS == TRANS_IDLE);
    endproperty

    ADDR_CTRL_STABLE_DURING_WAIT: assert property
        (p_addr_ctrl_stable_during_wait)
        else $error("[AHB_SVA] Address/control changed during wait state");
    WDATA_STABLE_DURING_WAIT: assert property
        (p_wdata_stable_during_wait)
        else $error("[AHB_SVA] HWDATA changed during wait state");

    //-------------------------------------------------------------------------
    // Address and burst rules
    //-------------------------------------------------------------------------
    property p_addr_aligned;
        @(posedge clk) disable iff (!rst_n)
        active_transfer |-> (HADDR % bytes_per_beat) == 0;
    endproperty

    property p_size_legal;
        @(posedge clk) disable iff (!rst_n)
        active_transfer |-> bytes_per_beat <= (AHB_DATA_WIDTH / 8);
    endproperty

    property p_no_seq_after_idle;
        @(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_IDLE |=>
            (HTRANS inside {TRANS_IDLE, TRANS_NONSEQ});
    endproperty

    property p_single_terminates;
        @(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_NONSEQ && HBURST == BURST_SINGLE |=>
            (HTRANS inside {TRANS_IDLE, TRANS_NONSEQ});
    endproperty

    property p_no_busy_single;
        @(posedge clk) disable iff (!rst_n)
        HTRANS == TRANS_BUSY |-> HBURST != BURST_SINGLE;
    endproperty

    property p_burst_control_stable;
        @(posedge clk) disable iff (!rst_n)
        HREADY && (HTRANS inside {TRANS_SEQ, TRANS_BUSY}) |->
            $stable({HBURST, HMASTLOCK, HPROT, HSIZE, HWRITE});
    endproperty

    property p_incr_1kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_SEQ &&
        (HBURST inside {BURST_INCR, BURST_INCR4, BURST_INCR8, BURST_INCR16})
        |-> HADDR[AHB_ADDR_WIDTH-1:10] ==
            $past(HADDR[AHB_ADDR_WIDTH-1:10]);
    endproperty

    property p_incr_address;
        @(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_SEQ && last_beat_valid &&
        (HBURST inside {BURST_INCR, BURST_INCR4, BURST_INCR8, BURST_INCR16})
        |-> HADDR == last_beat_addr + last_beat_bytes;
    endproperty

    property p_addr_stable_after_busy;
        @(posedge clk) disable iff (!rst_n)
        HTRANS == TRANS_SEQ && $past(HTRANS) == TRANS_BUSY |->
            $stable(HADDR);
    endproperty

    property p_wrap4_address;
        @(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_SEQ && last_beat_valid &&
        HBURST == BURST_WRAP4
        |-> HADDR == wrap_next_addr(last_beat_addr, last_beat_size, 4);
    endproperty

    property p_wrap8_address;
        @(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_SEQ && last_beat_valid &&
        HBURST == BURST_WRAP8
        |-> HADDR == wrap_next_addr(last_beat_addr, last_beat_size, 8);
    endproperty

    property p_wrap16_address;
        @(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_SEQ && last_beat_valid &&
        HBURST == BURST_WRAP16
        |-> HADDR == wrap_next_addr(last_beat_addr, last_beat_size, 16);
    endproperty

    ADDR_ALIGNED: assert property (p_addr_aligned)
        else $error("[AHB_SVA] HADDR is not aligned to HSIZE");
    SIZE_LEGAL: assert property (p_size_legal)
        else $error("[AHB_SVA] HSIZE exceeds data width");
    NO_SEQ_AFTER_IDLE: assert property (p_no_seq_after_idle)
        else $error("[AHB_SVA] SEQ/BUSY follows IDLE");
    SINGLE_TERMINATES: assert property (p_single_terminates)
        else $error("[AHB_SVA] SINGLE followed by SEQ/BUSY");
    NO_BUSY_SINGLE: assert property (p_no_busy_single)
        else $error("[AHB_SVA] BUSY used with SINGLE");
    BURST_CONTROL_STABLE: assert property (p_burst_control_stable)
        else $error("[AHB_SVA] Burst control changed mid-burst");
    INCR_1KB_BOUNDARY: assert property (p_incr_1kb_boundary)
        else $error("[AHB_SVA] INCR burst crossed 1-KB boundary");
    INCR_ADDRESS: assert property (p_incr_address)
        else $error("[AHB_SVA] Incorrect INCR address");
    ADDR_STABLE_AFTER_BUSY: assert property (p_addr_stable_after_busy)
        else $error("[AHB_SVA] HADDR changed after BUSY");
    WRAP4_ADDRESS: assert property (p_wrap4_address)
        else $error("[AHB_SVA] Incorrect WRAP4 address");
    WRAP8_ADDRESS: assert property (p_wrap8_address)
        else $error("[AHB_SVA] Incorrect WRAP8 address");
    WRAP16_ADDRESS: assert property (p_wrap16_address)
        else $error("[AHB_SVA] Incorrect WRAP16 address");

    //-------------------------------------------------------------------------
    // ERROR response
    //-------------------------------------------------------------------------
    property p_error_first_cycle;
        @(posedge clk) disable iff (!rst_n)
        $rose(HRESP) |-> !HREADY;
    endproperty

    property p_error_second_cycle;
        @(posedge clk) disable iff (!rst_n)
        HRESP && !HREADY |=> HRESP && HREADY;
    endproperty

    property p_error_has_first_cycle;
        @(posedge clk) disable iff (!rst_n)
        HRESP && HREADY |-> $past(HRESP) && !$past(HREADY);
    endproperty

    ERROR_FIRST_CYCLE: assert property (p_error_first_cycle)
        else $error("[AHB_SVA] ERROR first cycle has HREADY high");
    ERROR_SECOND_CYCLE: assert property (p_error_second_cycle)
        else $error("[AHB_SVA] ERROR second cycle is missing");
    ERROR_HAS_FIRST_CYCLE: assert property (p_error_has_first_cycle)
        else $error("[AHB_SVA] ERROR completed without first cycle");

    //-------------------------------------------------------------------------
    // Bridge profile
    //-------------------------------------------------------------------------
    generate
        if (CHECK_BRIDGE_PROFILE) begin : g_bridge_profile
            property p_no_lock;
                @(posedge clk) disable iff (!rst_n)
                active_transfer |-> !HMASTLOCK;
            endproperty

            property p_noncacheable;
                @(posedge clk) disable iff (!rst_n)
                active_transfer |-> !HPROT[3];
            endproperty

            // PG177 default HPROT: non-cacheable, non-bufferable, privileged
            // data access. Checked from the second reset cycle so the
            // synchronous reset has taken effect.
            property p_reset_hprot;
                @(posedge clk)
                (!rst_n && reset_active_q) |-> (HPROT == 4'b0011);
            endproperty

            NO_LOCK: assert property (p_no_lock)
                else $error("[AHB_SVA] HMASTLOCK asserted by bridge");
            NONCACHEABLE: assert property (p_noncacheable)
                else $error("[AHB_SVA] Bridge generated cacheable transfer");
            RESET_HPROT: assert property (p_reset_hprot)
                else $error("[AHB_SVA] HPROT is not 4'b0011 during reset");
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Scenario coverage
    //-------------------------------------------------------------------------
    C_NONSEQ: cover property (@(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_NONSEQ);
    // A wait state is an extended data phase, and the bridge drives BUSY on
    // HTRANS while it waits, so the address phase is not what to look at here
    C_WAIT_STATE: cover property (@(posedge clk) disable iff (!rst_n)
        data_phase_active && !HREADY);
    C_ERROR: cover property (@(posedge clk) disable iff (!rst_n)
        HRESP && HREADY);
    C_INCR: cover property (@(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_NONSEQ && HBURST == BURST_INCR);
    C_WRAP: cover property (@(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_NONSEQ &&
        (HBURST inside {BURST_WRAP4, BURST_WRAP8, BURST_WRAP16}));

    // HMASTLOCK held high on an IDLE bus. The bridge reference design does
    // this after a locked request until the next request is accepted; the
    // first occurrence is reported so the behavior is visible in the log.
    bit locked_idle_reported;

    C_LOCKED_IDLE: cover property (@(posedge clk) disable iff (!rst_n)
        HREADY && HTRANS == TRANS_IDLE && HMASTLOCK)
        begin
            if (!locked_idle_reported)
                $display("%0t: [AHB_SVA] C_LOCKED_IDLE: HMASTLOCK high during IDLE (first occurrence)",
                         $realtime);
            locked_idle_reported = 1'b1;
        end

endmodule : ahb_sva