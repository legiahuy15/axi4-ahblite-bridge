//=============================================================================
// File        : axi4_sva.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 protocol and bridge-profile assertions.
//=============================================================================

`timescale 1ns/1ps

module axi4_sva #(
    parameter int unsigned AXI4_ADDR_WIDTH     = 32,
    parameter int unsigned AXI4_DATA_WIDTH     = 32,
    parameter int unsigned AXI4_ID_WIDTH       = 4,
    parameter bit          CHECK_BRIDGE_PROFILE = 1'b1
)(
    input logic                          clk,
    input logic                          rst_n,

    input logic [AXI4_ID_WIDTH-1:0]      AWID,
    input logic [AXI4_ADDR_WIDTH-1:0]    AWADDR,
    input logic [7:0]                    AWLEN,
    input logic [2:0]                    AWSIZE,
    input logic [1:0]                    AWBURST,
    input logic                          AWLOCK,
    input logic [3:0]                    AWCACHE,
    input logic [2:0]                    AWPROT,
    input logic                          AWVALID,
    input logic                          AWREADY,

    input logic [AXI4_DATA_WIDTH-1:0]    WDATA,
    input logic [AXI4_DATA_WIDTH/8-1:0]  WSTRB,
    input logic                          WLAST,
    input logic                          WVALID,
    input logic                          WREADY,

    input logic [AXI4_ID_WIDTH-1:0]      BID,
    input logic [1:0]                    BRESP,
    input logic                          BVALID,
    input logic                          BREADY,

    input logic [AXI4_ID_WIDTH-1:0]      ARID,
    input logic [AXI4_ADDR_WIDTH-1:0]    ARADDR,
    input logic [7:0]                    ARLEN,
    input logic [2:0]                    ARSIZE,
    input logic [1:0]                    ARBURST,
    input logic                          ARLOCK,
    input logic [3:0]                    ARCACHE,
    input logic [2:0]                    ARPROT,
    input logic                          ARVALID,
    input logic                          ARREADY,

    input logic [AXI4_ID_WIDTH-1:0]      RID,
    input logic [AXI4_DATA_WIDTH-1:0]    RDATA,
    input logic [1:0]                    RRESP,
    input logic                          RLAST,
    input logic                          RVALID,
    input logic                          RREADY
);

    localparam logic [1:0] BURST_FIXED = 2'b00;
    localparam logic [1:0] BURST_INCR  = 2'b01;
    localparam logic [1:0] BURST_WRAP  = 2'b10;
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    bit reset_active_q;

    int unsigned aw_len_fifo[$];
    bit [AXI4_ID_WIDTH-1:0] aw_id_fifo[$];
    int unsigned w_len_fifo[$];
    int unsigned w_beat_count;
    int unsigned actual_w_len;
    bit [AXI4_ID_WIDTH-1:0] completed_awid;
    int unsigned b_pending[bit [AXI4_ID_WIDTH-1:0]];

    int unsigned ar_len_fifo[bit [AXI4_ID_WIDTH-1:0]][$];
    int unsigned r_beat_count[bit [AXI4_ID_WIDTH-1:0]];
    bit [AXI4_ID_WIDTH-1:0] current_rid;
    bit [AXI4_ID_WIDTH-1:0] active_rid;
    bit                     active_r_burst;

    function automatic logic [AXI4_ADDR_WIDTH:0] incr_last_byte(
        input logic [AXI4_ADDR_WIDTH-1:0] addr,
        input logic [7:0]                 len,
        input logic [2:0]                 size
    );
        logic [AXI4_ADDR_WIDTH:0] aligned_addr;
        longint unsigned          total_bytes;

        aligned_addr = ({1'b0, addr} >> size) << size;
        total_bytes = (int'(len) + 1) * (1 << size);
        return aligned_addr + total_bytes - 1;
    endfunction : incr_last_byte

    initial begin
        if (AXI4_ADDR_WIDTH < 32 || AXI4_ADDR_WIDTH > 64)
            $fatal(1, "[AXI4_SVA] Illegal AXI4_ADDR_WIDTH=%0d", AXI4_ADDR_WIDTH);
        if (!(AXI4_DATA_WIDTH inside {32, 64}))
            $fatal(1, "[AXI4_SVA] Illegal AXI4_DATA_WIDTH=%0d", AXI4_DATA_WIDTH);
        if (AXI4_ID_WIDTH < 1 || AXI4_ID_WIDTH > 32)
            $fatal(1, "[AXI4_SVA] Illegal AXI4_ID_WIDTH=%0d", AXI4_ID_WIDTH);
    end

    always @(posedge clk)
        reset_active_q <= !rst_n;

    // Reset
    property p_valid_low_in_reset;
        @(posedge clk)
        (!rst_n && reset_active_q) |->
            !(AWVALID || WVALID || BVALID || ARVALID || RVALID);
    endproperty

    VALID_LOW_IN_RESET: assert property (p_valid_low_in_reset)
        else $error("[AXI4_SVA] VALID asserted during reset");

    // Handshake and payload stability
    property p_aw_stable;
        @(posedge clk) disable iff (!rst_n)
        AWVALID && !AWREADY |=>
            AWVALID && $stable({AWID, AWADDR, AWLEN, AWSIZE, AWBURST,
                                AWLOCK, AWCACHE, AWPROT});
    endproperty

    property p_w_stable;
        @(posedge clk) disable iff (!rst_n)
        WVALID && !WREADY |=>
            WVALID && $stable({WDATA, WSTRB, WLAST});
    endproperty

    property p_b_stable;
        @(posedge clk) disable iff (!rst_n)
        BVALID && !BREADY |=>
            BVALID && $stable({BID, BRESP});
    endproperty

    property p_ar_stable;
        @(posedge clk) disable iff (!rst_n)
        ARVALID && !ARREADY |=>
            ARVALID && $stable({ARID, ARADDR, ARLEN, ARSIZE, ARBURST,
                                ARLOCK, ARCACHE, ARPROT});
    endproperty

    property p_r_stable;
        @(posedge clk) disable iff (!rst_n)
        RVALID && !RREADY |=>
            RVALID && $stable({RID, RDATA, RRESP, RLAST});
    endproperty

    AW_STABLE: assert property (p_aw_stable)
        else $error("[AXI4_SVA] AW channel changed while stalled");
    W_STABLE: assert property (p_w_stable)
        else $error("[AXI4_SVA] W channel changed while stalled");
    B_STABLE: assert property (p_b_stable)
        else $error("[AXI4_SVA] B channel changed while stalled");
    AR_STABLE: assert property (p_ar_stable)
        else $error("[AXI4_SVA] AR channel changed while stalled");
    R_STABLE: assert property (p_r_stable)
        else $error("[AXI4_SVA] R channel changed while stalled");

    // Signal integrity
    property p_handshake_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown({AWVALID, AWREADY, WVALID, WREADY, BVALID, BREADY,
                     ARVALID, ARREADY, RVALID, RREADY});
    endproperty

    property p_aw_payload_known;
        @(posedge clk) disable iff (!rst_n)
        AWVALID |-> !$isunknown({AWID, AWADDR, AWLEN, AWSIZE, AWBURST,
                                 AWLOCK, AWCACHE, AWPROT});
    endproperty

    property p_w_payload_known;
        @(posedge clk) disable iff (!rst_n)
        WVALID |-> !$isunknown({WDATA, WSTRB, WLAST});
    endproperty

    property p_b_payload_known;
        @(posedge clk) disable iff (!rst_n)
        BVALID |-> !$isunknown({BID, BRESP});
    endproperty

    property p_ar_payload_known;
        @(posedge clk) disable iff (!rst_n)
        ARVALID |-> !$isunknown({ARID, ARADDR, ARLEN, ARSIZE, ARBURST,
                                 ARLOCK, ARCACHE, ARPROT});
    endproperty

    property p_r_payload_known;
        @(posedge clk) disable iff (!rst_n)
        RVALID |-> !$isunknown({RID, RDATA, RRESP, RLAST});
    endproperty

    HANDSHAKE_KNOWN: assert property (p_handshake_known)
        else $error("[AXI4_SVA] VALID/READY contains X/Z");
    AW_PAYLOAD_KNOWN: assert property (p_aw_payload_known)
        else $error("[AXI4_SVA] AW payload contains X/Z");
    W_PAYLOAD_KNOWN: assert property (p_w_payload_known)
        else $error("[AXI4_SVA] W payload contains X/Z");
    B_PAYLOAD_KNOWN: assert property (p_b_payload_known)
        else $error("[AXI4_SVA] B payload contains X/Z");
    AR_PAYLOAD_KNOWN: assert property (p_ar_payload_known)
        else $error("[AXI4_SVA] AR payload contains X/Z");
    R_PAYLOAD_KNOWN: assert property (p_r_payload_known)
        else $error("[AXI4_SVA] R payload contains X/Z");

    // Burst legality
    property p_aw_burst_legal;
        @(posedge clk) disable iff (!rst_n)
        AWVALID && AWREADY |->
            (AWBURST != 2'b11) &&
            ((1 << AWSIZE) <= (AXI4_DATA_WIDTH / 8)) &&
            ((AWBURST != BURST_FIXED) || (AWLEN <= 8'd15)) &&
            ((AWBURST != BURST_WRAP) ||
             ((AWLEN inside {8'd1, 8'd3, 8'd7, 8'd15}) &&
              ((AWADDR % (1 << AWSIZE)) == 0)));
    endproperty

    property p_ar_burst_legal;
        @(posedge clk) disable iff (!rst_n)
        ARVALID && ARREADY |->
            (ARBURST != 2'b11) &&
            ((1 << ARSIZE) <= (AXI4_DATA_WIDTH / 8)) &&
            ((ARBURST != BURST_FIXED) || (ARLEN <= 8'd15)) &&
            ((ARBURST != BURST_WRAP) ||
             ((ARLEN inside {8'd1, 8'd3, 8'd7, 8'd15}) &&
              ((ARADDR % (1 << ARSIZE)) == 0)));
    endproperty

    property p_aw_4kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        AWVALID && AWREADY && AWBURST == BURST_INCR |->
            (({1'b0, AWADDR} >> 12) ==
             (incr_last_byte(AWADDR, AWLEN, AWSIZE) >> 12));
    endproperty

    property p_ar_4kb_boundary;
        @(posedge clk) disable iff (!rst_n)
        ARVALID && ARREADY && ARBURST == BURST_INCR |->
            (({1'b0, ARADDR} >> 12) ==
             (incr_last_byte(ARADDR, ARLEN, ARSIZE) >> 12));
    endproperty

    AW_BURST_LEGAL: assert property (p_aw_burst_legal)
        else $error("[AXI4_SVA] Illegal AW burst attributes");
    AR_BURST_LEGAL: assert property (p_ar_burst_legal)
        else $error("[AXI4_SVA] Illegal AR burst attributes");
    AW_4KB_BOUNDARY: assert property (p_aw_4kb_boundary)
        else $error("[AXI4_SVA] Write burst crosses 4-KB boundary");
    AR_4KB_BOUNDARY: assert property (p_ar_4kb_boundary)
        else $error("[AXI4_SVA] Read burst crosses 4-KB boundary");

    // WLAST and RLAST
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_len_fifo.delete();
            aw_id_fifo.delete();
            w_len_fifo.delete();
            b_pending.delete();
            ar_len_fifo.delete();
            r_beat_count.delete();
            w_beat_count  = 0;
            active_rid    = '0;
            active_r_burst = 1'b0;
        end else begin
            if (BVALID) begin
                B_WITH_REQUEST: assert
                    (b_pending.exists(BID) && b_pending[BID] != 0)
                    else $error("[AXI4_SVA] B response before AW/W completion");

                if (BREADY && b_pending.exists(BID) && b_pending[BID] != 0) begin
                    b_pending[BID]--;
                    if (b_pending[BID] == 0)
                        b_pending.delete(BID);
                end
            end

            if (AWVALID && AWREADY) begin
                if (w_len_fifo.size() != 0) begin
                    actual_w_len = w_len_fifo.pop_front();
                    WLEN_MATCH: assert (AWLEN == actual_w_len)
                        else $error("[AXI4_SVA] AWLEN does not match prior W burst");
                    if (!b_pending.exists(AWID))
                        b_pending[AWID] = 0;
                    b_pending[AWID]++;
                end else begin
                    if (aw_len_fifo.size() == 0 && w_beat_count != 0) begin
                        W_BEFORE_AW_LENGTH: assert (AWLEN >= w_beat_count)
                            else $error("[AXI4_SVA] WLAST missing before AW handshake");
                    end
                    aw_len_fifo.push_back(AWLEN);
                    aw_id_fifo.push_back(AWID);
                end
            end

            if (WVALID && WREADY) begin
                if (aw_len_fifo.size() != 0) begin
                    WLAST_POSITION: assert
                        ((w_beat_count == aw_len_fifo[0]) == WLAST)
                        else $error("[AXI4_SVA] WLAST at incorrect beat");
                end

                if (WLAST) begin
                    if (aw_len_fifo.size() != 0) begin
                        void'(aw_len_fifo.pop_front());
                        completed_awid = aw_id_fifo.pop_front();
                        if (!b_pending.exists(completed_awid))
                            b_pending[completed_awid] = 0;
                        b_pending[completed_awid]++;
                    end else begin
                        w_len_fifo.push_back(w_beat_count);
                    end
                    w_beat_count = 0;
                end else begin
                    w_beat_count++;
                end
            end

            if (RVALID) begin
                current_rid = RID;
                R_WITH_REQUEST: assert
                    (ar_len_fifo.exists(current_rid) &&
                     ar_len_fifo[current_rid].size() != 0)
                    else $error("[AXI4_SVA] R beat without matching AR");
            end

            if (RVALID && RREADY) begin
                current_rid = RID;
                if (!r_beat_count.exists(current_rid))
                    r_beat_count[current_rid] = 0;

                if (ar_len_fifo.exists(current_rid) &&
                    ar_len_fifo[current_rid].size() != 0) begin
                    RLAST_POSITION: assert
                        ((r_beat_count[current_rid] ==
                          ar_len_fifo[current_rid][0]) == RLAST)
                        else $error("[AXI4_SVA] RLAST at incorrect beat");

                    if (RLAST) begin
                        void'(ar_len_fifo[current_rid].pop_front());
                        if (ar_len_fifo[current_rid].size() == 0)
                            ar_len_fifo.delete(current_rid);
                        r_beat_count.delete(current_rid);
                    end else begin
                        r_beat_count[current_rid]++;
                    end
                end

                if (active_r_burst) begin
                    RID_STABLE: assert (RID == active_rid)
                        else $error("[AXI4_SVA] Read data interleaving detected");
                end else begin
                    active_rid = RID;
                end
                active_r_burst = !RLAST;
            end

            if (ARVALID && ARREADY)
                ar_len_fifo[ARID].push_back(ARLEN);
        end
    end

    // Bridge profile
    generate
        if (CHECK_BRIDGE_PROFILE) begin : g_bridge_profile
            property p_lock_unsupported;
                @(posedge clk) disable iff (!rst_n)
                AWVALID |-> !AWLOCK;
            endproperty

            property p_arlock_unsupported;
                @(posedge clk) disable iff (!rst_n)
                ARVALID |-> !ARLOCK;
            endproperty

            property p_bresp_supported;
                @(posedge clk) disable iff (!rst_n)
                BVALID |-> (BRESP inside {RESP_OKAY, RESP_SLVERR});
            endproperty

            property p_rresp_supported;
                @(posedge clk) disable iff (!rst_n)
                RVALID |-> (RRESP inside {RESP_OKAY, RESP_SLVERR});
            endproperty

            LOCK_UNSUPPORTED: assert property (p_lock_unsupported)
                else $error("[AXI4_SVA] AWLOCK is unsupported");
            ARLOCK_UNSUPPORTED: assert property (p_arlock_unsupported)
                else $error("[AXI4_SVA] ARLOCK is unsupported");
            BRESP_SUPPORTED: assert property (p_bresp_supported)
                else $error("[AXI4_SVA] Bridge generated unsupported BRESP");
            RRESP_SUPPORTED: assert property (p_rresp_supported)
                else $error("[AXI4_SVA] Bridge generated unsupported RRESP");
        end
    endgenerate

    // Scenario coverage
    C_AW_HANDSHAKE: cover property (@(posedge clk) disable iff (!rst_n)
        AWVALID && AWREADY);
    C_W_STALL: cover property (@(posedge clk) disable iff (!rst_n)
        WVALID && !WREADY);
    C_B_STALL: cover property (@(posedge clk) disable iff (!rst_n)
        BVALID && !BREADY);
    C_AR_HANDSHAKE: cover property (@(posedge clk) disable iff (!rst_n)
        ARVALID && ARREADY);
    C_R_STALL: cover property (@(posedge clk) disable iff (!rst_n)
        RVALID && !RREADY);
    C_B_SLVERR: cover property (@(posedge clk) disable iff (!rst_n)
        BVALID && BRESP == RESP_SLVERR);
    C_R_SLVERR: cover property (@(posedge clk) disable iff (!rst_n)
        RVALID && RRESP == RESP_SLVERR);

endmodule : axi4_sva