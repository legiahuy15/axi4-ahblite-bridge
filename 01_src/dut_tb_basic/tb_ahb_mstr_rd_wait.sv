//=============================================================================
// File        : tb_ahb_mstr_rd_wait
// Project     : AXI4 to AHB-Lite Bridge VIP
// Description : Directed test of ahb_mstr_if read restart from AHB_RD_WAIT
//               (FIXED, WRAP2, 1 KB split, INCR).
//=============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_ahb_mstr_rd_wait;

    localparam int ADDR_WIDTH      = 32;
    localparam int DATA_WIDTH      = 32;
    localparam int MAX_AHB_LOG     = 8;
    localparam int STATE_TIMEOUT   = 20;
    localparam int GLOBAL_TIMEOUT  = 200;

    localparam time CLK_PERIOD = 10ns;

    localparam logic [1:0] AXI_BURST_FIXED = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR  = 2'b01;
    localparam logic [1:0] AXI_BURST_WRAP  = 2'b10;

    localparam logic [1:0] AHB_HTRANS_IDLE   = 2'b00;
    localparam logic [1:0] AHB_HTRANS_BUSY   = 2'b01;
    localparam logic [1:0] AHB_HTRANS_NONSEQ = 2'b10;
    localparam logic [1:0] AHB_HTRANS_SEQ    = 2'b11;
    localparam logic [2:0] AHB_HBURST_SINGLE = 3'b000;
    localparam logic [2:0] AHB_HBURST_INCR   = 3'b001;
    localparam logic [2:0] AHB_HSIZE_WORD    = 3'b010;

    // Encoded ahb_sm_t values, used to confirm the FSM reaches AHB_RD_WAIT
    localparam logic [3:0] AHB_RD_WAIT_STATE = 4'd5;
    localparam logic [3:0] AHB_IDLE_STATE    = 4'd0;

    logic                       clk;
    logic                       resetn;
    logic [ADDR_WIDTH-1:0]      m_ahb_haddr;
    logic                       m_ahb_hwrite;
    logic [2:0]                 m_ahb_hsize;
    logic [2:0]                 m_ahb_hburst;
    logic [3:0]                 m_ahb_hprot;
    logic [1:0]                 m_ahb_htrans;
    logic                       m_ahb_hmastlock;
    logic [DATA_WIDTH-1:0]      m_ahb_hwdata;
    logic                       m_ahb_hready;
    logic [DATA_WIDTH-1:0]      m_ahb_hrdata;
    logic                       m_ahb_hresp;

    logic                       ahb_rd_request;
    logic                       ahb_wr_request;
    logic                       axi_lock;
    logic [DATA_WIDTH-1:0]      rd_data;
    logic                       slv_err_resp;
    logic [2:0]                 axi_prot;
    logic [3:0]                 axi_cache;
    logic [DATA_WIDTH-1:0]      axi_wdata;
    logic [2:0]                 axi_size;
    logic [7:0]                 axi_length;
    logic [ADDR_WIDTH-1:0]      axi_address;
    logic [1:0]                 axi_burst;
    logic                       single_ahb_wr_xfer;
    logic                       single_ahb_rd_xfer;
    logic                       send_wvalid;
    logic                       send_ahb_wr;
    logic                       axi_wvalid;
    logic                       send_bresp;
    logic                       send_rvalid;
    logic                       send_rlast;
    logic                       axi_rready;
    logic                       timeout_inprogress;
    logic                       load_cntr;
    logic                       cntr_enable;

    logic [ADDR_WIDTH-1:0]      ahb_log_addr   [0:MAX_AHB_LOG-1];
    logic [1:0]                 ahb_log_htrans [0:MAX_AHB_LOG-1];
    logic [2:0]                 ahb_log_hburst [0:MAX_AHB_LOG-1];
    integer                     ahb_log_count;
    integer                     error_count;

    ahb_mstr_if #(
        .C_M_AHB_ADDR_WIDTH            (ADDR_WIDTH),
        .C_M_AHB_DATA_WIDTH            (DATA_WIDTH),
        .C_S_AXI_DATA_WIDTH            (DATA_WIDTH),
        .C_S_AXI_SUPPORTS_NARROW_BURST(0)
    ) dut (
        .AHB_HCLK          (clk),
        .AHB_HRESETN       (resetn),
        .M_AHB_HADDR       (m_ahb_haddr),
        .M_AHB_HWRITE      (m_ahb_hwrite),
        .M_AHB_HSIZE       (m_ahb_hsize),
        .M_AHB_HBURST      (m_ahb_hburst),
        .M_AHB_HPROT       (m_ahb_hprot),
        .M_AHB_HTRANS      (m_ahb_htrans),
        .M_AHB_HMASTLOCK   (m_ahb_hmastlock),
        .M_AHB_HWDATA      (m_ahb_hwdata),
        .M_AHB_HREADY      (m_ahb_hready),
        .M_AHB_HRDATA      (m_ahb_hrdata),
        .M_AHB_HRESP       (m_ahb_hresp),
        .ahb_rd_request    (ahb_rd_request),
        .ahb_wr_request    (ahb_wr_request),
        .axi_lock          (axi_lock),
        .rd_data           (rd_data),
        .slv_err_resp      (slv_err_resp),
        .axi_prot          (axi_prot),
        .axi_cache         (axi_cache),
        .axi_wdata         (axi_wdata),
        .axi_size          (axi_size),
        .axi_length        (axi_length),
        .axi_address       (axi_address),
        .axi_burst         (axi_burst),
        .single_ahb_wr_xfer(single_ahb_wr_xfer),
        .single_ahb_rd_xfer(single_ahb_rd_xfer),
        .send_wvalid       (send_wvalid),
        .send_ahb_wr       (send_ahb_wr),
        .axi_wvalid        (axi_wvalid),
        .send_bresp        (send_bresp),
        .send_rvalid       (send_rvalid),
        .send_rlast        (send_rlast),
        .axi_rready        (axi_rready),
        .timeout_inprogress(timeout_inprogress),
        .load_cntr         (load_cntr),
        .cntr_enable       (cntr_enable)
    );

    task automatic check_condition(
        input logic  condition,
        input string message
    );
        if (condition !== 1'b1) begin
            error_count = error_count + 1;
            $error("[%0t] %s", $time, message);
        end
    endtask

    task automatic apply_reset;
        begin
            @(negedge clk);
            resetn         = 1'b0;
            ahb_rd_request = 1'b0;
            axi_rready     = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            resetn = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic run_restart_case(
        input string                  case_name,
        input logic [1:0]             burst_kind,
        input logic [ADDR_WIDTH-1:0]  first_addr,
        input logic [ADDR_WIDTH-1:0]  second_addr,
        input logic [2:0]             expected_hburst,
        input logic [1:0]             expected_wait_htrans,
        input logic [1:0]             expected_restart_htrans
    );
        integer guard;
        begin
            apply_reset();

            // Two beats with axi_rready low: park in AHB_RD_WAIT, one beat left
            @(negedge clk);
            axi_address    = first_addr;
            axi_length     = 8'd1;
            axi_size       = AHB_HSIZE_WORD;
            axi_burst      = burst_kind;
            axi_rready     = 1'b0;
            ahb_rd_request = 1'b1;

            @(posedge clk);
            @(negedge clk);
            ahb_rd_request = 1'b0;

            guard = 0;
            while ((dut.ahb_wr_rd_cs !== AHB_RD_WAIT_STATE) &&
                   (guard < STATE_TIMEOUT)) begin
                @(negedge clk);
                guard = guard + 1;
            end

            if (dut.ahb_wr_rd_cs !== AHB_RD_WAIT_STATE)
                $fatal(1, "%s did not enter AHB_RD_WAIT", case_name);

            check_condition(dut.wrap_brst_count === 8'd1,
                            $sformatf("%s did not stall with one beat remaining",
                                      case_name));
            check_condition(m_ahb_htrans === expected_wait_htrans,
                            $sformatf("%s wait HTRANS mismatch: expected %0b, got %0b",
                                      case_name, expected_wait_htrans,
                                      m_ahb_htrans));
            check_condition(ahb_log_count == 1,
                            $sformatf("%s expected one transfer before restart, got %0d",
                                      case_name, ahb_log_count));

            // Release axi_rready and check the restarted address phase
            axi_rready = 1'b1;
            @(posedge clk);
            #1;
            check_condition(m_ahb_htrans === expected_restart_htrans,
                            $sformatf("%s restart HTRANS mismatch: expected %0b, got %0b",
                                      case_name, expected_restart_htrans,
                                      m_ahb_htrans));
            check_condition(m_ahb_haddr === second_addr,
                            $sformatf("%s restart address mismatch: expected %08h, got %08h",
                                      case_name, second_addr, m_ahb_haddr));

            // The restarted address phase is accepted on the following edge.
            @(posedge clk);
            #1;

            guard = 0;
            while ((dut.ahb_wr_rd_cs !== AHB_IDLE_STATE) &&
                   (guard < STATE_TIMEOUT)) begin
                @(negedge clk);
                guard = guard + 1;
            end

            if (dut.ahb_wr_rd_cs !== AHB_IDLE_STATE)
                $fatal(1, "%s did not complete", case_name);

            check_condition(ahb_log_count == 2,
                            $sformatf("%s expected two AHB transfers, got %0d",
                                      case_name, ahb_log_count));
            if (ahb_log_count == 2) begin
                check_condition(ahb_log_addr[0] === first_addr,
                                $sformatf("%s first address mismatch", case_name));
                check_condition(ahb_log_addr[1] === second_addr,
                                $sformatf("%s second address mismatch", case_name));
                check_condition(ahb_log_htrans[0] === AHB_HTRANS_NONSEQ,
                                $sformatf("%s first beat was not NONSEQ", case_name));
                check_condition(ahb_log_htrans[1] === expected_restart_htrans,
                                $sformatf("%s restarted beat HTRANS mismatch", case_name));
                check_condition(ahb_log_hburst[0] === expected_hburst,
                                $sformatf("%s first HBURST mismatch", case_name));
                check_condition(ahb_log_hburst[1] === expected_hburst,
                                $sformatf("%s restarted HBURST mismatch", case_name));
            end
        end
    endtask

    always @(posedge clk) begin
        if (!resetn) begin
            ahb_log_count <= 0;
        end else if (m_ahb_hready && m_ahb_htrans[1]) begin
            if (ahb_log_count >= MAX_AHB_LOG)
                $fatal(1, "AHB monitor log overflow");
            ahb_log_addr[ahb_log_count]   <= m_ahb_haddr;
            ahb_log_htrans[ahb_log_count] <= m_ahb_htrans;
            ahb_log_hburst[ahb_log_count] <= m_ahb_hburst;
            ahb_log_count                 <= ahb_log_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin : watchdog
        repeat (GLOBAL_TIMEOUT) @(posedge clk);
        $fatal(1, "Global AHB_RD_WAIT regression timeout");
    end

    initial begin : test
        error_count         = 0;
        resetn              = 1'b0;
        ahb_rd_request      = 1'b0;
        ahb_wr_request      = 1'b0;
        axi_lock            = 1'b0;
        axi_prot            = 3'b000;
        axi_cache           = 4'b0000;
        axi_wdata           = '0;
        axi_size            = AHB_HSIZE_WORD;
        axi_length          = 8'd1;
        axi_address         = '0;
        axi_burst           = AXI_BURST_INCR;
        single_ahb_wr_xfer  = 1'b0;
        single_ahb_rd_xfer  = 1'b0;
        send_ahb_wr         = 1'b0;
        axi_wvalid          = 1'b0;
        axi_rready          = 1'b1;
        timeout_inprogress  = 1'b0;
        m_ahb_hready        = 1'b1;
        m_ahb_hrdata        = 32'hA5A5_5A5A;
        m_ahb_hresp         = 1'b0;

        $display("[%0t] TEST: AHB_RD_WAIT restart for AXI FIXED", $time);
        run_restart_case("FIXED", AXI_BURST_FIXED,
                         32'h0000_0100, 32'h0000_0100,
                         AHB_HBURST_SINGLE, AHB_HTRANS_IDLE,
                         AHB_HTRANS_NONSEQ);

        $display("[%0t] TEST: AHB_RD_WAIT restart for AXI WRAP2", $time);
        run_restart_case("WRAP2", AXI_BURST_WRAP,
                         32'h0000_0208, 32'h0000_020C,
                         AHB_HBURST_SINGLE, AHB_HTRANS_IDLE,
                         AHB_HTRANS_NONSEQ);

        $display("[%0t] TEST: AHB_RD_WAIT restart after 1-KB split", $time);
        run_restart_case("INCR-1KB", AXI_BURST_INCR,
                         32'h0000_03FC, 32'h0000_0400,
                         AHB_HBURST_INCR, AHB_HTRANS_IDLE,
                         AHB_HTRANS_NONSEQ);

        $display("[%0t] TEST: AHB_RD_WAIT continuation for regular AXI INCR", $time);
        run_restart_case("INCR", AXI_BURST_INCR,
                         32'h0000_0300, 32'h0000_0304,
                         AHB_HBURST_INCR, AHB_HTRANS_BUSY,
                         AHB_HTRANS_SEQ);

        repeat (2) @(posedge clk);
        if (error_count == 0) begin
            $display("============================================================");
            $display("TEST PASS: AHB_RD_WAIT restart regression completed");
            $display("============================================================");
            $finish;
        end else begin
            $fatal(1, "TEST FAIL: %0d check(s) failed", error_count);
        end
    end

endmodule

`default_nettype wire
