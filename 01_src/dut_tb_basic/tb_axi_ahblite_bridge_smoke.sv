//=============================================================================
// File        : tb_axi_ahblite_bridge_smoke
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Self-checking non-UVM smoke testbench for the AXI4-to-AHB-Lite
//               bridge using a pipelined AHB-Lite memory slave model.
//=============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_axi_ahblite_bridge_smoke;

    localparam int ADDR_WIDTH      = 32;
    localparam int DATA_WIDTH      = 32;
    localparam int ID_WIDTH        = 4;
    localparam int MEM_WORDS       = 1024;
    localparam int MAX_AHB_LOG     = 128;
    localparam int HANDSHAKE_LIMIT = 200;
    localparam int TEST_TIMEOUT    = 5000;

    localparam time CLK_PERIOD = 10ns;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam logic [1:0] AXI_BURST_INCR  = 2'b01;

    localparam logic [1:0] AHB_HTRANS_IDLE   = 2'b00;
    localparam logic [1:0] AHB_HTRANS_NONSEQ = 2'b10;
    localparam logic [1:0] AHB_HTRANS_SEQ    = 2'b11;
    localparam logic [2:0] AHB_HBURST_SINGLE = 3'b000;
    localparam logic [2:0] AHB_HBURST_INCR4  = 3'b011;
    localparam logic [2:0] AHB_HSIZE_WORD    = 3'b010;

    localparam logic [ADDR_WIDTH-1:0] SINGLE_ADDR = 32'h0000_0100;
    localparam logic [ADDR_WIDTH-1:0] BP_ADDR     = 32'h0000_0104;
    localparam logic [ADDR_WIDTH-1:0] WAIT_ADDR   = 32'h0000_0180;
    localparam logic [ADDR_WIDTH-1:0] ERROR_ADDR  = 32'h0000_01C0;
    localparam logic [ADDR_WIDTH-1:0] INCR4_ADDR  = 32'h0000_0200;

    logic s_axi_aclk;
    logic s_axi_aresetn;

    logic [ID_WIDTH-1:0]   s_axi_awid;
    logic [7:0]            s_axi_awlen;
    logic [2:0]            s_axi_awsize;
    logic [1:0]            s_axi_awburst;
    logic [3:0]            s_axi_awcache;
    logic [ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [2:0]            s_axi_awprot;
    logic                  s_axi_awvalid;
    logic                  s_axi_awready;
    logic                  s_axi_awlock;

    logic [DATA_WIDTH-1:0]     s_axi_wdata;
    logic [(DATA_WIDTH/8)-1:0] s_axi_wstrb;
    logic                      s_axi_wlast;
    logic                      s_axi_wvalid;
    logic                      s_axi_wready;

    logic [ID_WIDTH-1:0] s_axi_bid;
    logic [1:0]          s_axi_bresp;
    logic                s_axi_bvalid;
    logic                s_axi_bready;

    logic [ID_WIDTH-1:0]   s_axi_arid;
    logic [ADDR_WIDTH-1:0] s_axi_araddr;
    logic [2:0]            s_axi_arprot;
    logic [3:0]            s_axi_arcache;
    logic                  s_axi_arvalid;
    logic [7:0]            s_axi_arlen;
    logic [2:0]            s_axi_arsize;
    logic [1:0]            s_axi_arburst;
    logic                  s_axi_arlock;
    logic                  s_axi_arready;

    logic [ID_WIDTH-1:0]   s_axi_rid;
    logic [DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]            s_axi_rresp;
    logic                  s_axi_rvalid;
    logic                  s_axi_rlast;
    logic                  s_axi_rready;

    logic [ADDR_WIDTH-1:0] m_ahb_haddr;
    logic                  m_ahb_hwrite;
    logic [2:0]            m_ahb_hsize;
    logic [2:0]            m_ahb_hburst;
    logic [3:0]            m_ahb_hprot;
    logic [1:0]            m_ahb_htrans;
    logic                  m_ahb_hmastlock;
    logic [DATA_WIDTH-1:0] m_ahb_hwdata;
    logic                  m_ahb_hready;
    logic [DATA_WIDTH-1:0] m_ahb_hrdata;
    logic                  m_ahb_hresp;

    logic [DATA_WIDTH-1:0] ahb_mem [0:MEM_WORDS-1];

    logic                  dp_valid;
    logic                  dp_write;
    logic [ADDR_WIDTH-1:0] dp_addr;
    logic [2:0]            dp_size;
    logic [DATA_WIDTH-1:0] dp_rdata;
    logic                  dp_error;
    logic                  dp_error_first_cycle_done;
    integer                dp_wait_left;

    logic                  slave_wait_enable;
    logic [ADDR_WIDTH-1:0] slave_wait_addr;
    integer                slave_wait_cycles;
    logic                  slave_error_enable;
    logic [ADDR_WIDTH-1:0] slave_error_addr;

    logic [ADDR_WIDTH-1:0] ahb_log_addr   [0:MAX_AHB_LOG-1];
    logic [1:0]            ahb_log_htrans [0:MAX_AHB_LOG-1];
    logic [2:0]            ahb_log_hburst [0:MAX_AHB_LOG-1];
    logic [2:0]            ahb_log_hsize  [0:MAX_AHB_LOG-1];
    logic                  ahb_log_hwrite [0:MAX_AHB_LOG-1];
    integer                ahb_log_count;
    integer                ahb_stall_cycle_count;

    logic        previous_ahb_stall;
    logic [77:0] previous_ahb_bundle;
    logic [77:0] current_ahb_bundle;

    logic                      previous_b_stall;
    logic [ID_WIDTH+1:0]       previous_b_payload;
    logic                      previous_r_stall;
    logic [ID_WIDTH+DATA_WIDTH+2:0] previous_r_payload;

    integer error_count;
    integer log_start;
    integer stall_start;
    integer i;

    assign current_ahb_bundle = {
        m_ahb_haddr,
        m_ahb_hwrite,
        m_ahb_hsize,
        m_ahb_hburst,
        m_ahb_hprot,
        m_ahb_htrans,
        m_ahb_hmastlock,
        m_ahb_hwdata
    };

    axi_ahblite_bridge #(
        .C_S_AXI_ADDR_WIDTH           (ADDR_WIDTH),
        .C_S_AXI_DATA_WIDTH           (DATA_WIDTH),
        .C_S_AXI_SUPPORTS_NARROW_BURST(0),
        .C_S_AXI_ID_WIDTH             (ID_WIDTH),
        .C_M_AHB_ADDR_WIDTH           (ADDR_WIDTH),
        .C_M_AHB_DATA_WIDTH           (DATA_WIDTH),
        .C_DPHASE_TIMEOUT             (0)
    ) dut (
        .s_axi_aclk      (s_axi_aclk),
        .s_axi_aresetn   (s_axi_aresetn),

        .s_axi_awid      (s_axi_awid),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_awcache   (s_axi_awcache),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awprot    (s_axi_awprot),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_awlock    (s_axi_awlock),

        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),

        .s_axi_bid       (s_axi_bid),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),

        .s_axi_arid      (s_axi_arid),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arprot    (s_axi_arprot),
        .s_axi_arcache   (s_axi_arcache),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_arlock    (s_axi_arlock),
        .s_axi_arready   (s_axi_arready),

        .s_axi_rid       (s_axi_rid),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rlast     (s_axi_rlast),
        .s_axi_rready    (s_axi_rready),

        .m_ahb_haddr     (m_ahb_haddr),
        .m_ahb_hwrite    (m_ahb_hwrite),
        .m_ahb_hsize     (m_ahb_hsize),
        .m_ahb_hburst    (m_ahb_hburst),
        .m_ahb_hprot     (m_ahb_hprot),
        .m_ahb_htrans    (m_ahb_htrans),
        .m_ahb_hmastlock (m_ahb_hmastlock),
        .m_ahb_hwdata    (m_ahb_hwdata),
        .m_ahb_hready    (m_ahb_hready),
        .m_ahb_hrdata    (m_ahb_hrdata),
        .m_ahb_hresp     (m_ahb_hresp)
    );

    function automatic integer mem_index(
        input logic [ADDR_WIDTH-1:0] address
    );
        mem_index = address[11:2];
    endfunction

    function automatic logic [DATA_WIDTH-1:0] beat_data(
        input logic [DATA_WIDTH-1:0] base,
        input integer                beat
    );
        beat_data = base + beat;
    endfunction

    task automatic check_condition(
        input logic  condition,
        input string message
    );
        if (condition !== 1'b1) begin
            error_count = error_count + 1;
            $error("[%0t] %s", $time, message);
        end
    endtask

    task automatic initialize_axi_inputs;
        begin
            s_axi_aresetn = 1'b0;

            s_axi_awid    = '0;
            s_axi_awlen   = '0;
            s_axi_awsize  = AHB_HSIZE_WORD;
            s_axi_awburst = AXI_BURST_INCR;
            s_axi_awcache = '0;
            s_axi_awaddr  = '0;
            s_axi_awprot  = '0;
            s_axi_awvalid = 1'b0;
            s_axi_awlock  = 1'b0;

            s_axi_wdata   = '0;
            s_axi_wstrb   = '1;
            s_axi_wlast   = 1'b0;
            s_axi_wvalid  = 1'b0;

            s_axi_bready  = 1'b0;

            s_axi_arid    = '0;
            s_axi_araddr  = '0;
            s_axi_arprot  = '0;
            s_axi_arcache = '0;
            s_axi_arvalid = 1'b0;
            s_axi_arlen   = '0;
            s_axi_arsize  = AHB_HSIZE_WORD;
            s_axi_arburst = AXI_BURST_INCR;
            s_axi_arlock  = 1'b0;

            s_axi_rready  = 1'b0;
        end
    endtask

    task automatic apply_reset;
        begin
            @(negedge s_axi_aclk);
            s_axi_aresetn = 1'b0;
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            s_axi_wlast   = 1'b0;
            s_axi_bready  = 1'b0;
            s_axi_arvalid = 1'b0;
            s_axi_rready  = 1'b0;

            slave_wait_enable  = 1'b0;
            slave_error_enable = 1'b0;

            repeat (4) @(posedge s_axi_aclk);
            @(negedge s_axi_aclk);

            check_condition(s_axi_awready === 1'b0,
                            "AWREADY must be low during reset");
            check_condition(s_axi_wready === 1'b0,
                            "WREADY must be low during reset");
            check_condition(s_axi_arready === 1'b0,
                            "ARREADY must be low during reset");
            check_condition(s_axi_bvalid === 1'b0,
                            "BVALID must be low during reset");
            check_condition(s_axi_rvalid === 1'b0,
                            "RVALID must be low during reset");
            check_condition(s_axi_rlast === 1'b0,
                            "RLAST must be low during reset");
            check_condition(m_ahb_haddr === '0,
                            "HADDR reset value is not zero");
            check_condition(m_ahb_htrans === AHB_HTRANS_IDLE,
                            "HTRANS reset value is not IDLE");
            check_condition(m_ahb_hwrite === 1'b0,
                            "HWRITE reset value is not zero");
            check_condition(m_ahb_hsize === 3'b000,
                            "HSIZE reset value is not zero");
            check_condition(m_ahb_hburst === AHB_HBURST_SINGLE,
                            "HBURST reset value is not SINGLE");
            check_condition(m_ahb_hprot === 4'b0011,
                            "HPROT reset value is not 0011");
            check_condition(m_ahb_hmastlock === 1'b0,
                            "HMASTLOCK reset value is not zero");
            check_condition(m_ahb_hwdata === '0,
                            "HWDATA reset value is not zero");
            check_condition(!$isunknown({
                                s_axi_awready,
                                s_axi_wready,
                                s_axi_bvalid,
                                s_axi_bresp,
                                s_axi_arready,
                                s_axi_rvalid,
                                s_axi_rresp,
                                s_axi_rlast,
                                m_ahb_haddr,
                                m_ahb_hwrite,
                                m_ahb_hsize,
                                m_ahb_hburst,
                                m_ahb_hprot,
                                m_ahb_htrans,
                                m_ahb_hmastlock,
                                m_ahb_hwdata
                            }),
                            "Protocol outputs contain X/Z after reset");

            s_axi_aresetn = 1'b1;
            s_axi_bready  = 1'b1;
            s_axi_rready  = 1'b1;
            repeat (3) @(posedge s_axi_aclk);
        end
    endtask

    task automatic drive_aw(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [ID_WIDTH-1:0]   id,
        input integer                beats
    );
        integer guard;
        logic   handshake;
        begin
            @(negedge s_axi_aclk);
            s_axi_awid    = id;
            s_axi_awaddr  = address;
            s_axi_awlen   = beats - 1;
            s_axi_awsize  = AHB_HSIZE_WORD;
            s_axi_awburst = AXI_BURST_INCR;
            s_axi_awcache = 4'b0000;
            s_axi_awprot  = 3'b000;
            s_axi_awlock  = 1'b0;
            s_axi_awvalid = 1'b1;

            guard     = 0;
            handshake = 1'b0;
            while (!handshake) begin
                @(posedge s_axi_aclk);
                guard = guard + 1;
                if (s_axi_awready === 1'b1)
                    handshake = 1'b1;
                if (guard > HANDSHAKE_LIMIT)
                    $fatal(1, "AW handshake timed out");
            end

            @(negedge s_axi_aclk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task automatic drive_w_burst(
        input integer                beats,
        input logic [DATA_WIDTH-1:0] data_base
    );
        integer beat;
        integer guard;
        logic   handshake;
        begin
            for (beat = 0; beat < beats; beat = beat + 1) begin
                @(negedge s_axi_aclk);
                s_axi_wdata  = beat_data(data_base, beat);
                s_axi_wstrb  = '1;
                s_axi_wlast  = (beat == (beats - 1));
                s_axi_wvalid = 1'b1;

                guard     = 0;
                handshake = 1'b0;
                while (!handshake) begin
                    @(posedge s_axi_aclk);
                    guard = guard + 1;
                    if (s_axi_wready === 1'b1)
                        handshake = 1'b1;
                    if (guard > HANDSHAKE_LIMIT)
                        $fatal(1, "W beat %0d handshake timed out", beat);
                end
            end

            @(negedge s_axi_aclk);
            s_axi_wvalid = 1'b0;
            s_axi_wlast  = 1'b0;
            s_axi_wdata  = '0;
        end
    endtask

    task automatic receive_b_response(
        input logic [ID_WIDTH-1:0] expected_id,
        input logic [1:0]          expected_resp,
        input integer              stall_cycles
    );
        integer guard;
        integer cycle;
        logic   response_seen;
        logic [ID_WIDTH-1:0] held_id;
        logic [1:0]          held_resp;
        begin
            if (stall_cycles > 0) begin
                guard         = 0;
                response_seen = 1'b0;
                while (!response_seen) begin
                    @(posedge s_axi_aclk);
                    guard = guard + 1;
                    if (s_axi_bvalid === 1'b1) begin
                        response_seen = 1'b1;
                        held_id        = s_axi_bid;
                        held_resp      = s_axi_bresp;
                    end
                    if (guard > HANDSHAKE_LIMIT)
                        $fatal(1, "BVALID assertion timed out");
                end

                for (cycle = 0; cycle < stall_cycles; cycle = cycle + 1) begin
                    @(posedge s_axi_aclk);
                    check_condition(s_axi_bvalid === 1'b1,
                                    "BVALID dropped under backpressure");
                    check_condition({s_axi_bid, s_axi_bresp} ===
                                    {held_id, held_resp},
                                    "B payload changed under backpressure");
                end

                @(negedge s_axi_aclk);
                s_axi_bready = 1'b1;
            end

            guard         = 0;
            response_seen = 1'b0;
            while (!response_seen) begin
                @(posedge s_axi_aclk);
                guard = guard + 1;
                if ((s_axi_bvalid === 1'b1) &&
                    (s_axi_bready === 1'b1)) begin
                    response_seen = 1'b1;
                    check_condition(s_axi_bid === expected_id,
                                    $sformatf("BID mismatch: expected %0h, got %0h",
                                              expected_id, s_axi_bid));
                    check_condition(s_axi_bresp === expected_resp,
                                    $sformatf("BRESP mismatch: expected %0b, got %0b",
                                              expected_resp, s_axi_bresp));
                end
                if (guard > HANDSHAKE_LIMIT)
                    $fatal(1, "B response handshake timed out");
            end
        end
    endtask

    task automatic axi_write_burst(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [ID_WIDTH-1:0]   id,
        input integer                beats,
        input logic [DATA_WIDTH-1:0] data_base,
        input logic [1:0]            expected_resp,
        input integer                b_stall_cycles
    );
        begin
            s_axi_bready = (b_stall_cycles == 0);
            fork
                drive_aw(address, id, beats);
                drive_w_burst(beats, data_base);
            join
            receive_b_response(id, expected_resp, b_stall_cycles);
            s_axi_bready = 1'b1;
        end
    endtask

    task automatic drive_ar(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [ID_WIDTH-1:0]   id,
        input integer                beats
    );
        integer guard;
        logic   handshake;
        begin
            @(negedge s_axi_aclk);
            s_axi_arid    = id;
            s_axi_araddr  = address;
            s_axi_arlen   = beats - 1;
            s_axi_arsize  = AHB_HSIZE_WORD;
            s_axi_arburst = AXI_BURST_INCR;
            s_axi_arcache = 4'b0000;
            s_axi_arprot  = 3'b000;
            s_axi_arlock  = 1'b0;
            s_axi_arvalid = 1'b1;

            guard     = 0;
            handshake = 1'b0;
            while (!handshake) begin
                @(posedge s_axi_aclk);
                guard = guard + 1;
                if (s_axi_arready === 1'b1)
                    handshake = 1'b1;
                if (guard > HANDSHAKE_LIMIT)
                    $fatal(1, "AR handshake timed out");
            end

            @(negedge s_axi_aclk);
            s_axi_arvalid = 1'b0;
        end
    endtask

    task automatic receive_r_burst(
        input logic [ID_WIDTH-1:0]   expected_id,
        input integer                beats,
        input logic [DATA_WIDTH-1:0] expected_data_base,
        input logic [1:0]            expected_resp,
        input integer                stall_cycles
    );
        integer beat;
        integer guard;
        integer cycle;
        logic   response_seen;
        logic [ID_WIDTH-1:0]   held_id;
        logic [DATA_WIDTH-1:0] held_data;
        logic [1:0]            held_resp;
        logic                  held_last;
        begin
            if (stall_cycles > 0) begin
                guard         = 0;
                response_seen = 1'b0;
                while (!response_seen) begin
                    @(posedge s_axi_aclk);
                    guard = guard + 1;
                    if (s_axi_rvalid === 1'b1) begin
                        response_seen = 1'b1;
                        held_id        = s_axi_rid;
                        held_data      = s_axi_rdata;
                        held_resp      = s_axi_rresp;
                        held_last      = s_axi_rlast;
                    end
                    if (guard > HANDSHAKE_LIMIT)
                        $fatal(1, "RVALID assertion timed out");
                end

                for (cycle = 0; cycle < stall_cycles; cycle = cycle + 1) begin
                    @(posedge s_axi_aclk);
                    check_condition(s_axi_rvalid === 1'b1,
                                    "RVALID dropped under backpressure");
                    check_condition({s_axi_rid, s_axi_rdata,
                                     s_axi_rresp, s_axi_rlast} ===
                                    {held_id, held_data, held_resp, held_last},
                                    "R payload changed under backpressure");
                end

                @(negedge s_axi_aclk);
                s_axi_rready = 1'b1;
            end

            for (beat = 0; beat < beats; beat = beat + 1) begin
                guard         = 0;
                response_seen = 1'b0;
                while (!response_seen) begin
                    @(posedge s_axi_aclk);
                    guard = guard + 1;
                    if ((s_axi_rvalid === 1'b1) &&
                        (s_axi_rready === 1'b1)) begin
                        response_seen = 1'b1;
                        check_condition(s_axi_rid === expected_id,
                                        $sformatf("RID mismatch on beat %0d", beat));
                        check_condition(s_axi_rresp === expected_resp,
                                        $sformatf("RRESP mismatch on beat %0d", beat));
                        check_condition(s_axi_rlast === (beat == (beats - 1)),
                                        $sformatf("RLAST mismatch on beat %0d", beat));
                        if (expected_resp == AXI_RESP_OKAY) begin
                            check_condition(
                                s_axi_rdata === beat_data(expected_data_base, beat),
                                $sformatf("RDATA mismatch on beat %0d: expected %0h, got %0h",
                                          beat,
                                          beat_data(expected_data_base, beat),
                                          s_axi_rdata)
                            );
                        end
                    end
                    if (guard > HANDSHAKE_LIMIT)
                        $fatal(1, "R beat %0d handshake timed out", beat);
                end
            end
        end
    endtask

    task automatic axi_read_burst(
        input logic [ADDR_WIDTH-1:0]   address,
        input logic [ID_WIDTH-1:0]     id,
        input integer                  beats,
        input logic [DATA_WIDTH-1:0]   expected_data_base,
        input logic [1:0]              expected_resp,
        input integer                  r_stall_cycles
    );
        begin
            s_axi_rready = (r_stall_cycles == 0);
            drive_ar(address, id, beats);
            receive_r_burst(id, beats, expected_data_base,
                            expected_resp, r_stall_cycles);
            s_axi_rready = 1'b1;
        end
    endtask

    task automatic check_single_ahb_transfer(
        input integer                  start_index,
        input logic [ADDR_WIDTH-1:0]   expected_addr,
        input logic                    expected_write
    );
        begin
            check_condition((ahb_log_count - start_index) == 1,
                            $sformatf("Expected one AHB transfer, observed %0d",
                                      ahb_log_count - start_index));
            if ((ahb_log_count - start_index) == 1) begin
                check_condition(ahb_log_addr[start_index] === expected_addr,
                                "AHB single-transfer address mismatch");
                check_condition(ahb_log_hwrite[start_index] === expected_write,
                                "AHB single-transfer direction mismatch");
                check_condition(ahb_log_htrans[start_index] === AHB_HTRANS_NONSEQ,
                                "AHB single transfer did not use NONSEQ");
                check_condition(ahb_log_hburst[start_index] === AHB_HBURST_SINGLE,
                                "AHB single transfer did not use HBURST=SINGLE");
                check_condition(ahb_log_hsize[start_index] === AHB_HSIZE_WORD,
                                "AHB single transfer did not use word HSIZE");
            end
        end
    endtask

    task automatic check_incr4_ahb_transfers(
        input integer                start_index,
        input logic [ADDR_WIDTH-1:0] base_addr,
        input logic                  expected_write
    );
        integer beat;
        begin
            check_condition((ahb_log_count - start_index) == 4,
                            $sformatf("Expected four AHB transfers, observed %0d",
                                      ahb_log_count - start_index));
            if ((ahb_log_count - start_index) == 4) begin
                for (beat = 0; beat < 4; beat = beat + 1) begin
                    check_condition(
                        ahb_log_addr[start_index + beat] === (base_addr + (beat * 4)),
                        $sformatf("INCR4 address mismatch on beat %0d", beat)
                    );
                    check_condition(
                        ahb_log_hwrite[start_index + beat] === expected_write,
                        $sformatf("INCR4 direction mismatch on beat %0d", beat)
                    );
                    check_condition(
                        ahb_log_hburst[start_index + beat] === AHB_HBURST_INCR4,
                        $sformatf("INCR4 HBURST mismatch on beat %0d", beat)
                    );
                    check_condition(
                        ahb_log_hsize[start_index + beat] === AHB_HSIZE_WORD,
                        $sformatf("INCR4 HSIZE mismatch on beat %0d", beat)
                    );
                    if (beat == 0) begin
                        check_condition(
                            ahb_log_htrans[start_index + beat] === AHB_HTRANS_NONSEQ,
                            "INCR4 first beat did not use NONSEQ"
                        );
                    end else begin
                        check_condition(
                            ahb_log_htrans[start_index + beat] === AHB_HTRANS_SEQ,
                            $sformatf("INCR4 beat %0d did not use SEQ", beat)
                        );
                    end
                end
            end
        end
    endtask

    // AHB-Lite slave response generation. Wait and ERROR behavior is latched
    // only after an address phase has been accepted.
    always_comb begin
        m_ahb_hready = 1'b1;
        m_ahb_hresp  = 1'b0;
        m_ahb_hrdata = dp_rdata;

        if (dp_valid) begin
            if (dp_wait_left > 0) begin
                m_ahb_hready = 1'b0;
            end else if (dp_error && !dp_error_first_cycle_done) begin
                m_ahb_hready = 1'b0;
                m_ahb_hresp  = 1'b1;
            end else begin
                m_ahb_hready = 1'b1;
                m_ahb_hresp  = dp_error;
            end
        end
    end

    // One registered AHB data-phase slot. The current HWDATA is committed for
    // the previous address/control phase when HREADY completes that transfer.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            dp_valid                  <= 1'b0;
            dp_write                  <= 1'b0;
            dp_addr                   <= '0;
            dp_size                   <= '0;
            dp_rdata                  <= '0;
            dp_error                  <= 1'b0;
            dp_error_first_cycle_done <= 1'b0;
            dp_wait_left              <= 0;
        end else if (dp_valid && (dp_wait_left > 0)) begin
            dp_wait_left <= dp_wait_left - 1;
        end else if (dp_valid && dp_error &&
                     !dp_error_first_cycle_done) begin
            dp_error_first_cycle_done <= 1'b1;
        end else begin
            if (dp_valid && m_ahb_hready && dp_write && !dp_error)
                ahb_mem[mem_index(dp_addr)] <= m_ahb_hwdata;

            if (m_ahb_hready && m_ahb_htrans[1]) begin
                dp_valid <= 1'b1;
                dp_write <= m_ahb_hwrite;
                dp_addr  <= m_ahb_haddr;
                dp_size  <= m_ahb_hsize;
                if (m_ahb_hwrite)
                    dp_rdata <= '0;
                else
                    dp_rdata <= ahb_mem[mem_index(m_ahb_haddr)];

                dp_error <= slave_error_enable &&
                            (m_ahb_haddr == slave_error_addr);
                dp_error_first_cycle_done <= 1'b0;

                if (slave_wait_enable &&
                    (m_ahb_haddr == slave_wait_addr))
                    dp_wait_left <= slave_wait_cycles;
                else
                    dp_wait_left <= 0;
            end else begin
                dp_valid                  <= 1'b0;
                dp_write                  <= 1'b0;
                dp_error                  <= 1'b0;
                dp_error_first_cycle_done <= 1'b0;
                dp_wait_left              <= 0;
            end
        end
    end

    // AHB accepted-address monitor and wait-state counter.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            ahb_log_count         <= 0;
            ahb_stall_cycle_count <= 0;
        end else begin
            if (!m_ahb_hready && dp_valid)
                ahb_stall_cycle_count <= ahb_stall_cycle_count + 1;

            if (m_ahb_hready && m_ahb_htrans[1]) begin
                if (ahb_log_count >= MAX_AHB_LOG)
                    $fatal(1, "AHB monitor log overflow");

                ahb_log_addr[ahb_log_count]   <= m_ahb_haddr;
                ahb_log_htrans[ahb_log_count] <= m_ahb_htrans;
                ahb_log_hburst[ahb_log_count] <= m_ahb_hburst;
                ahb_log_hsize[ahb_log_count]  <= m_ahb_hsize;
                ahb_log_hwrite[ahb_log_count] <= m_ahb_hwrite;
                ahb_log_count                 <= ahb_log_count + 1;
            end
        end
    end

    // Procedural protocol stability checks avoid requiring an SVA-capable
    // simulator for this first smoke test.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            previous_ahb_stall <= 1'b0;
            previous_ahb_bundle <= '0;
            previous_b_stall <= 1'b0;
            previous_b_payload <= '0;
            previous_r_stall <= 1'b0;
            previous_r_payload <= '0;
        end else begin
            if (previous_ahb_stall) begin
                check_condition(current_ahb_bundle === previous_ahb_bundle,
                                "AHB address/control/data changed while HREADY was low");
            end

            if (previous_b_stall) begin
                check_condition(s_axi_bvalid === 1'b1,
                                "BVALID dropped while BREADY was low");
                check_condition({s_axi_bid, s_axi_bresp} === previous_b_payload,
                                "B payload changed while BREADY was low");
            end

            if (previous_r_stall) begin
                check_condition(s_axi_rvalid === 1'b1,
                                "RVALID dropped while RREADY was low");
                check_condition({s_axi_rid, s_axi_rdata,
                                 s_axi_rresp, s_axi_rlast} === previous_r_payload,
                                "R payload changed while RREADY was low");
            end

            previous_ahb_stall  <= !m_ahb_hready;
            previous_ahb_bundle <= current_ahb_bundle;
            previous_b_stall    <= s_axi_bvalid && !s_axi_bready;
            previous_b_payload  <= {s_axi_bid, s_axi_bresp};
            previous_r_stall    <= s_axi_rvalid && !s_axi_rready;
            previous_r_payload  <= {s_axi_rid, s_axi_rdata,
                                    s_axi_rresp, s_axi_rlast};
        end
    end

    initial begin
        s_axi_aclk = 1'b0;
        forever #(CLK_PERIOD/2) s_axi_aclk = ~s_axi_aclk;
    end

    initial begin : global_watchdog
        repeat (TEST_TIMEOUT) @(posedge s_axi_aclk);
        $fatal(1, "Global smoke-test timeout");
    end

    initial begin : smoke_test
        error_count = 0;
        initialize_axi_inputs();

        slave_wait_enable  = 1'b0;
        slave_wait_addr    = WAIT_ADDR;
        slave_wait_cycles  = 0;
        slave_error_enable = 1'b0;
        slave_error_addr   = ERROR_ADDR;

        for (i = 0; i < MEM_WORDS; i = i + 1)
            ahb_mem[i] = '0;

        $display("[%0t] TEST: reset", $time);
        apply_reset();

        $display("[%0t] TEST: single full-word write", $time);
        log_start = ahb_log_count;
        axi_write_burst(SINGLE_ADDR, 4'h1, 1, 32'hDEAD_BEEF,
                        AXI_RESP_OKAY, 0);
        check_single_ahb_transfer(log_start, SINGLE_ADDR, 1'b1);
        check_condition(ahb_mem[mem_index(SINGLE_ADDR)] === 32'hDEAD_BEEF,
                        "Single write did not update AHB memory");

        $display("[%0t] TEST: single full-word read-back", $time);
        log_start = ahb_log_count;
        axi_read_burst(SINGLE_ADDR, 4'h2, 1, 32'hDEAD_BEEF,
                       AXI_RESP_OKAY, 0);
        check_single_ahb_transfer(log_start, SINGLE_ADDR, 1'b0);

        $display("[%0t] TEST: AXI B-channel backpressure", $time);
        log_start = ahb_log_count;
        axi_write_burst(BP_ADDR, 4'h3, 1, 32'hCAFE_1234,
                        AXI_RESP_OKAY, 3);
        check_single_ahb_transfer(log_start, BP_ADDR, 1'b1);

        $display("[%0t] TEST: AXI R-channel backpressure", $time);
        log_start = ahb_log_count;
        axi_read_burst(BP_ADDR, 4'h4, 1, 32'hCAFE_1234,
                       AXI_RESP_OKAY, 3);
        check_single_ahb_transfer(log_start, BP_ADDR, 1'b0);

        $display("[%0t] TEST: AHB wait-state write", $time);
        slave_wait_enable = 1'b1;
        slave_wait_cycles = 3;
        log_start          = ahb_log_count;
        stall_start        = ahb_stall_cycle_count;
        axi_write_burst(WAIT_ADDR, 4'h5, 1, 32'h55AA_00FF,
                        AXI_RESP_OKAY, 0);
        check_single_ahb_transfer(log_start, WAIT_ADDR, 1'b1);
        check_condition((ahb_stall_cycle_count - stall_start) == 3,
                        "AHB write did not observe exactly three wait-state cycles");
        check_condition(ahb_mem[mem_index(WAIT_ADDR)] === 32'h55AA_00FF,
                        "Wait-state write did not update AHB memory");

        $display("[%0t] TEST: AHB wait-state read", $time);
        log_start   = ahb_log_count;
        stall_start = ahb_stall_cycle_count;
        axi_read_burst(WAIT_ADDR, 4'h6, 1, 32'h55AA_00FF,
                       AXI_RESP_OKAY, 0);
        check_single_ahb_transfer(log_start, WAIT_ADDR, 1'b0);
        check_condition((ahb_stall_cycle_count - stall_start) == 3,
                        "AHB read did not observe exactly three wait-state cycles");
        slave_wait_enable = 1'b0;

        $display("[%0t] TEST: AHB ERROR to AXI write SLVERR", $time);
        slave_error_enable = 1'b1;
        log_start           = ahb_log_count;
        axi_write_burst(ERROR_ADDR, 4'h7, 1, 32'hBAD0_BAD0,
                        AXI_RESP_SLVERR, 0);
        check_single_ahb_transfer(log_start, ERROR_ADDR, 1'b1);
        check_condition(ahb_mem[mem_index(ERROR_ADDR)] === '0,
                        "Errored AHB write unexpectedly updated memory");

        $display("[%0t] TEST: reset after write SLVERR", $time);
        apply_reset();

        $display("[%0t] TEST: AHB ERROR to AXI read SLVERR", $time);
        slave_error_enable = 1'b1;
        log_start           = ahb_log_count;
        axi_read_burst(ERROR_ADDR, 4'h8, 1, '0,
                       AXI_RESP_SLVERR, 0);
        check_single_ahb_transfer(log_start, ERROR_ADDR, 1'b0);

        $display("[%0t] TEST: reset after read SLVERR", $time);
        apply_reset();

        $display("[%0t] TEST: INCR4 write", $time);
        log_start = ahb_log_count;
        axi_write_burst(INCR4_ADDR, 4'h9, 4, 32'h1000_0000,
                        AXI_RESP_OKAY, 0);
        check_incr4_ahb_transfers(log_start, INCR4_ADDR, 1'b1);
        for (i = 0; i < 4; i = i + 1) begin
            check_condition(
                ahb_mem[mem_index(INCR4_ADDR + (i * 4))] ===
                    beat_data(32'h1000_0000, i),
                $sformatf("INCR4 write memory mismatch on beat %0d", i)
            );
        end

        $display("[%0t] TEST: INCR4 read-back", $time);
        log_start = ahb_log_count;
        axi_read_burst(INCR4_ADDR, 4'hA, 4, 32'h1000_0000,
                       AXI_RESP_OKAY, 0);
        check_incr4_ahb_transfers(log_start, INCR4_ADDR, 1'b0);

        repeat (5) @(posedge s_axi_aclk);
        if (error_count == 0) begin
            $display("============================================================");
            $display("TEST PASS: AXI4-to-AHB-Lite bridge smoke test completed");
            $display("============================================================");
            $finish;
        end else begin
            $fatal(1, "TEST FAIL: %0d check(s) failed", error_count);
        end
    end

endmodule

`default_nettype wire
