//==============================================================================
// File        : tb_sva_wlast_before_aw.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Standalone unit testbench for the WLAST_MISSING_W_BEFORE_AW
//               assertion added to axi4_sva.
//
//               The UVM master driver only ever produces legal traffic, so it
//               can prove the check does not false-fire but CANNOT make it fire.
//               This TB drives axi4_sva's ports directly to exercise:
//
//                 PHASE A (legal)   : W starts before AW and is still in
//                                     progress when AW arrives (Case B), but the
//                                     final WLAST lands exactly on AWLEN.
//                                     Expect NO [SVA] error.
//
//                 PHASE B (legal)   : pipelined - burst 1's final WLAST and
//                                     burst 2's AW handshake occur on the SAME
//                                     clock edge (AWLEN2 < burst 1's length).
//                                     Locks in the AW-before-W ordering of the
//                                     merged tracking block; the old two-block
//                                     version could false-fire here.
//                                     Expect NO [SVA] error.
//
//                 PHASE C (illegal) : W accepts MORE beats than AWLEN+1 without
//                                     WLAST before AW arrives (WLAST missing/late).
//                                     Expect exactly ONE [SVA] error:
//                                     "WLAST missing/late, W before AW".
//
//               Run from sim/ (QuestaSim): make sva_unit
//==============================================================================

`timescale 1ns/1ps

module tb_sva_wlast_before_aw;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam ID_WIDTH   = 4;

    // Clock / reset
    logic clk;
    logic rst_n;

    // AW channel
    logic [ID_WIDTH-1:0]   AWID;
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [7:0]            AWLEN;
    logic [2:0]            AWSIZE;
    logic [1:0]            AWBURST;
    logic                  AWLOCK, AWVALID, AWREADY;
    logic [3:0]            AWCACHE, AWQOS, AWREGION;
    logic [2:0]            AWPROT;

    // W channel
    logic [DATA_WIDTH-1:0]   WDATA;
    logic [DATA_WIDTH/8-1:0] WSTRB;
    logic                    WLAST, WVALID, WREADY;

    // B channel
    logic [ID_WIDTH-1:0] BID;
    logic [1:0]          BRESP;
    logic                BVALID, BREADY;

    // AR / R channel (unused - held idle)
    logic [ID_WIDTH-1:0]   ARID;
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic [7:0]            ARLEN;
    logic [2:0]            ARSIZE;
    logic [1:0]            ARBURST;
    logic                  ARLOCK, ARVALID, ARREADY;
    logic [3:0]            ARCACHE, ARQOS, ARREGION;
    logic [2:0]            ARPROT;
    logic [ID_WIDTH-1:0]   RID;
    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]            RRESP;
    logic                  RLAST, RVALID, RREADY;

    //--------------------------------------------------------------------------
    // DUT: the assertion module under test
    //--------------------------------------------------------------------------
    axi4_sva #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH  (ID_WIDTH)
    ) dut (.*);

    //--------------------------------------------------------------------------
    // Clock
    //--------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Stimulus helpers - drive on negedge so values are stable at the sampling
    // posedge. Each call consumes exactly one posedge with the handshake high.
    //--------------------------------------------------------------------------

    // One W data beat (WVALID && WREADY for a single cycle)
    task automatic w_beat(input logic last);
        @(negedge clk);
        WVALID = 1'b1; WREADY = 1'b1; WLAST = last;
        WDATA  = $urandom; WSTRB = '1;
        @(negedge clk);
        WVALID = 1'b0; WREADY = 1'b0; WLAST = 1'b0;
    endtask

    // One AW address handshake (AWVALID && AWREADY for a single cycle)
    task automatic aw_hs(input logic [7:0] len);
        @(negedge clk);
        AWVALID = 1'b1; AWREADY = 1'b1;
        AWLEN   = len; AWSIZE = 3'b010; AWBURST = 2'b01;  // 4B, INCR (legal)
        AWID    = '0;  AWADDR = 32'h1000;
        @(negedge clk);
        AWVALID = 1'b0; AWREADY = 1'b0;
    endtask

    // One W beat AND one AW handshake on the SAME clock edge (pipelined,
    // same-cycle). Stresses the AW-vs-W ordering inside the merged block.
    task automatic w_and_aw(input logic w_last, input logic [7:0] aw_len);
        @(negedge clk);
        WVALID  = 1'b1; WREADY = 1'b1; WLAST = w_last;
        WDATA   = $urandom; WSTRB = '1;
        AWVALID = 1'b1; AWREADY = 1'b1;
        AWLEN   = aw_len; AWSIZE = 3'b010; AWBURST = 2'b01;
        AWID    = '0; AWADDR = 32'h2000;
        @(negedge clk);
        WVALID  = 1'b0; WREADY = 1'b0; WLAST = 1'b0;
        AWVALID = 1'b0; AWREADY = 1'b0;
    endtask

    task automatic idle(input int n);
        repeat (n) @(negedge clk);
    endtask

    //--------------------------------------------------------------------------
    // Test body
    //--------------------------------------------------------------------------
    initial begin
        // Init all master/slave signals idle
        {AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT,
         AWQOS, AWREGION, AWVALID, AWREADY} = '0;
        {WDATA, WSTRB, WLAST, WVALID, WREADY}   = '0;
        {BID, BRESP, BVALID, BREADY}            = '0;
        {ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT,
         ARQOS, ARREGION, ARVALID, ARREADY}     = '0;
        {RID, RDATA, RRESP, RLAST, RVALID, RREADY} = '0;

        // Reset
        rst_n = 1'b0;
        idle(4);
        @(negedge clk) rst_n = 1'b1;
        idle(2);

        // ------------------------------------------------------------------
        // PHASE A - legal Case B (W before AW, still in progress, WLAST on AWLEN)
        //   Burst of 4 beats (AWLEN=3). Send 2 beats, then AW arrives mid-burst,
        //   then finish beats 2 & 3 with WLAST on beat 3.
        //   Expect: NO [SVA] error.
        // ------------------------------------------------------------------
        $display("\n[TB] ===== PHASE A: legal W-before-AW partial overlap =====");
        $display("[TB] Expect NO [SVA] error in this phase.");
        w_beat(1'b0);              // beat 0  (w_beat_cnt -> 1)
        w_beat(1'b0);              // beat 1  (w_beat_cnt -> 2)
        aw_hs(8'd3);               // AW arrives mid-burst: AWLEN=3 >= 2  -> OK
        w_beat(1'b0);              // beat 2  (w_beat_cnt -> 3)
        w_beat(1'b1);              // beat 3, WLAST on AWLEN=3 -> OK, burst done
        idle(4);

        // ------------------------------------------------------------------
        // PHASE B - legal pipelined: AW and WLAST on the SAME clock edge
        //   Burst 1 (AWLEN=3) is in flight; its final beat (WLAST) handshakes
        //   on the exact same cycle as burst 2's AW (AWLEN=1 < 3). This is the
        //   race the merged block fixes: a "W before AW" order would pop burst 1
        //   off aw_len_fifo, then run the retroactive check for burst 2 against
        //   burst 1's stale w_beat_cnt(3) -> AWLEN(1) >= 3 FALSE -> false
        //   positive. The merged "AW first" order leaves burst 1 on the FIFO so
        //   the retroactive guard (aw_len_fifo empty) is skipped correctly.
        //   Expect: NO [SVA] error.
        // ------------------------------------------------------------------
        $display("\n[TB] ===== PHASE B: legal pipelined AW==WLAST same edge =====");
        $display("[TB] Expect NO [SVA] error in this phase.");
        aw_hs(8'd3);               // burst1 AW: AWLEN=3       (aw_len_fifo=[3])
        w_beat(1'b0);              // burst1 beat 0  (w_beat_cnt -> 1)
        w_beat(1'b0);              // burst1 beat 1  (w_beat_cnt -> 2)
        w_beat(1'b0);              // burst1 beat 2  (w_beat_cnt -> 3)
        w_and_aw(1'b1, 8'd1);      // burst1 WLAST(beat3) + burst2 AW(AWLEN=1), SAME edge
        w_beat(1'b0);              // burst2 beat 0  (w_beat_cnt -> 1)
        w_beat(1'b1);              // burst2 beat 1, WLAST on AWLEN=1 -> OK, done
        idle(4);

        // ------------------------------------------------------------------
        // PHASE C - illegal (WLAST missing/late before AW)
        //   Master streams 5 W beats without WLAST, THEN AW arrives with AWLEN=2
        //   (only 3 beats allowed). Beat index 2 should have carried WLAST, so
        //   the retroactive check AWLEN(2) >= w_beat_cnt(5) FAILS.
        //   Expect: exactly ONE [SVA] "WLAST missing/late, W before AW" error.
        // ------------------------------------------------------------------
        $display("\n[TB] ===== PHASE C: illegal WLAST missing before AW =====");
        $display("[TB] Expect exactly ONE [SVA] WLAST_MISSING_W_BEFORE_AW error.");
        w_beat(1'b0);              // beat 0  (w_beat_cnt -> 1)
        w_beat(1'b0);              // beat 1  (w_beat_cnt -> 2)
        w_beat(1'b0);              // beat 2  (w_beat_cnt -> 3)  <- should have been WLAST
        w_beat(1'b0);              // beat 3  (w_beat_cnt -> 4)
        w_beat(1'b0);              // beat 4  (w_beat_cnt -> 5)
        aw_hs(8'd2);               // AW: AWLEN=2 < w_beat_cnt=5 -> ASSERTION FIRES
        idle(6);

        $display("\n[TB] ===== DONE =====");
        $display("[TB] PASS criteria: 0 [SVA] errors in PHASE A and PHASE B,");
        $display("[TB]                exactly 1 [SVA] error in PHASE C.");
        $finish;
    end

    // Safety timeout
    initial begin
        #10000;
        $display("[TB] ERROR: timeout");
        $finish;
    end

endmodule : tb_sva_wlast_before_aw
