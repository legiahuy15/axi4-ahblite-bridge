//=============================================================================
// File        : ahb_mstr_if
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite master-side control for the AXI4-to-AHB-Lite bridge.
//               Converts AXI burst semantics into AHB SINGLE/INCR/WRAP transfers,
//               including WRAP2 expansion and 1-KB boundary splitting.
//=============================================================================

`timescale 1ns/1ps

module ahb_mstr_if #(
    parameter int C_M_AHB_ADDR_WIDTH             = 32,
    parameter int C_M_AHB_DATA_WIDTH             = 32,
    parameter int C_S_AXI_DATA_WIDTH             = 32,
    parameter int C_S_AXI_SUPPORTS_NARROW_BURST = 0
) (
    input  logic                              AHB_HCLK,
    input  logic                              AHB_HRESETN,

    output logic [C_M_AHB_ADDR_WIDTH-1:0]     M_AHB_HADDR,
    output logic                              M_AHB_HWRITE,
    output logic [2:0]                        M_AHB_HSIZE,
    output logic [2:0]                        M_AHB_HBURST,
    output logic [3:0]                        M_AHB_HPROT,
    output logic [1:0]                        M_AHB_HTRANS,
    output logic                              M_AHB_HMASTLOCK,
    output logic [C_M_AHB_DATA_WIDTH-1:0]     M_AHB_HWDATA,

    input  logic                              M_AHB_HREADY,
    input  logic [C_M_AHB_DATA_WIDTH-1:0]     M_AHB_HRDATA,
    input  logic                              M_AHB_HRESP,

    input  logic                              ahb_rd_request,
    input  logic                              ahb_wr_request,
    input  logic                              axi_lock,
    output logic [C_M_AHB_DATA_WIDTH-1:0]     rd_data,
    output logic                              slv_err_resp,
    input  logic [2:0]                        axi_prot,
    input  logic [3:0]                        axi_cache,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]     axi_wdata,
    input  logic [2:0]                        axi_size,
    input  logic [7:0]                        axi_length,
    input  logic [C_M_AHB_ADDR_WIDTH-1:0]     axi_address,
    input  logic [1:0]                        axi_burst,
    input  logic                              single_ahb_wr_xfer,
    input  logic                              single_ahb_rd_xfer,
    output logic                              send_wvalid,
    input  logic                              send_ahb_wr,
    input  logic                              axi_wvalid,
    output logic                              send_bresp,
    output logic                              send_rvalid,
    output logic                              send_rlast,
    input  logic                              axi_rready,
    input  logic                              timeout_inprogress,
    output logic                              load_cntr,
    output logic                              cntr_enable
);

    //-------------------------------------------------------------------------
    // Value declaration
    //-------------------------------------------------------------------------

    typedef enum logic [3:0] {
        AHB_IDLE,
        AHB_RD_ADDR,
        AHB_RD_SINGLE,
        AHB_RD_DATA_INCR,
        AHB_RD_LAST,
        AHB_RD_WAIT,
        AHB_WR_ADDR,
        AHB_WR_SINGLE,
        AHB_WR_WAIT,
        AHB_WR_INCR,
        AHB_INCR_ADDR,
        AHB_LAST_ADDR,
        AHB_ONEKB_LAST,
        AHB_LAST_WAIT,
        AHB_LAST
    } ahb_sm_t;

    localparam logic [1:0] IDLE   = 2'b00;
    localparam logic [1:0] BUSY   = 2'b01;
    localparam logic [1:0] NONSEQ = 2'b10;
    localparam logic [1:0] SEQ    = 2'b11;

    //-------------------------------------------------------------------------
    // Signals
    //-------------------------------------------------------------------------

    ahb_sm_t ahb_wr_rd_ns, ahb_wr_rd_cs;

    logic HWRITE_i;
    logic [C_M_AHB_DATA_WIDTH-1:0] HWDATA_i;
    logic [C_M_AHB_ADDR_WIDTH-1:0] HADDR_i;
    logic [3:0] HPROT_i;
    logic [2:0] HBURST_i;
    logic [2:0] HSIZE_i;
    logic HLOCK_i;

    logic ahb_hslverr;
    logic ahb_hready;
    logic [C_M_AHB_DATA_WIDTH-1:0] ahb_hrdata;
    logic ahb_write_sm;
    logic [7:0] wrap_brst_count;
    logic burst_ready;
    logic wrap_brst_last;
    logic [2:0] ahb_burst;
    logic send_wr_data;
    logic incr_addr;
    logic load_counter;
    logic load_counter_sm;
    logic wrap_brst_one;
    logic send_trans_seq;
    logic send_trans_nonseq;
    logic send_trans_idle;
    logic send_trans_busy;
    logic send_wrap_burst;
    logic wrap_in_progress;
    logic send_rlast_sm;
    logic send_bresp_sm;
    logic one_kb_cross;
    logic addr_all_ones;
    logic one_kb_in_progress;
    logic one_kb_splitted;
    logic wrap_2_in_progress;
    logic axi_len_les_eq_sixteen;
    logic [11:0] axi_end_address;
    logic [11:0] axi_length_burst;
    logic onekb_cross_access;
    logic fixed_burst_access;
    logic incr_burst_access;
    logic wrap_burst_access;
    logic wrap_four;
    logic wrap_eight;
    logic wrap_sixteen;
    logic onekb_brst_add;
    logic single_ahb_wr;

    assign M_AHB_HADDR     = HADDR_i;
    assign M_AHB_HWRITE    = HWRITE_i;
    assign M_AHB_HWDATA    = HWDATA_i;
    assign M_AHB_HPROT     = HPROT_i;
    assign M_AHB_HMASTLOCK = HLOCK_i;
    assign M_AHB_HSIZE     = HSIZE_i;
    assign M_AHB_HBURST    = HBURST_i;

    assign ahb_hslverr = M_AHB_HRESP;
    assign ahb_hready  = M_AHB_HREADY;
    assign ahb_hrdata  = M_AHB_HRDATA;
    assign send_rlast  = send_rlast_sm;
    assign send_bresp  = send_bresp_sm;

    assign fixed_burst_access = (axi_burst == 2'b00);
    assign incr_burst_access  = (axi_burst == 2'b01);
    assign wrap_burst_access  = (axi_burst == 2'b10);

    assign wrap_four    = (axi_length[3:0] == 4'b0011) && wrap_in_progress;
    assign wrap_eight   = (axi_length[3:0] == 4'b0111) && wrap_in_progress;
    assign wrap_sixteen = (axi_length[3:0] == 4'b1111) && wrap_in_progress;

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN)
            HWDATA_i <= '0;
        else if (send_wr_data)
            HWDATA_i <= axi_wdata;
    end

    // HTRANS is registered. During a timeout the bridge explicitly returns AHB to IDLE.
    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN) begin
            M_AHB_HTRANS <= IDLE;
        end else begin
            if (send_trans_nonseq && !timeout_inprogress)
                M_AHB_HTRANS <= NONSEQ;
            else if (send_trans_seq && !timeout_inprogress)
                M_AHB_HTRANS <= SEQ;
            else if (send_trans_idle && !timeout_inprogress)
                M_AHB_HTRANS <= IDLE;
            else if (send_trans_busy && !timeout_inprogress)
                M_AHB_HTRANS <= BUSY;
            else if (timeout_inprogress)
                M_AHB_HTRANS <= IDLE;
        end
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN)
            HWRITE_i <= 1'b0;
        else if (ahb_rd_request)
            HWRITE_i <= 1'b0;
        else if (ahb_wr_request)
            HWRITE_i <= 1'b1;
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN)
            wrap_in_progress <= 1'b0;
        else if (send_wrap_burst)
            wrap_in_progress <= 1'b1;
        else if (send_rlast_sm || send_bresp_sm)
            wrap_in_progress <= 1'b0;
    end

    assign wrap_2_in_progress = wrap_in_progress && (axi_length[3:0] == 4'b0001);

    // -------------------------------------------------------------------------
    // Address generation. Exactly one generate branch drives HADDR_i
    // -------------------------------------------------------------------------
    generate
        if ((C_M_AHB_DATA_WIDTH == 32) && (C_S_AXI_SUPPORTS_NARROW_BURST == 1)) begin : gen_32_data_width_narrow
            always_ff @(posedge AHB_HCLK) begin
                if (!AHB_HRESETN) begin
                    HADDR_i <= '0;
                end else if (ahb_wr_request || ahb_rd_request) begin
                    case (axi_size)
                        3'b010: HADDR_i <= {axi_address[C_M_AHB_ADDR_WIDTH-1:2], 2'b00};
                        3'b001: HADDR_i <= {axi_address[C_M_AHB_ADDR_WIDTH-1:1], 1'b0};
                        default: HADDR_i <= axi_address;
                    endcase
                end else if (incr_addr && !fixed_burst_access) begin
                    case (axi_size)
                        3'b000: begin
                            if (wrap_2_in_progress)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:1], ~HADDR_i[0]};
                            else if (wrap_four)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:2], HADDR_i[1:0] + 2'b01};
                            else if (wrap_eight)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:3], HADDR_i[2:0] + 3'b001};
                            else if (wrap_sixteen)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b0001};
                            else
                                HADDR_i <= HADDR_i + 1;
                        end
                        3'b001: begin
                            if (wrap_2_in_progress)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:2], HADDR_i[1:0] + 2'b10};
                            else if (wrap_four)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:3], HADDR_i[2:0] + 3'b010};
                            else if (wrap_eight)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b0010};
                            else if (wrap_sixteen)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:5], HADDR_i[4:0] + 5'b00010};
                            else
                                HADDR_i <= HADDR_i + 2;
                        end
                        3'b010: begin
                            if (wrap_2_in_progress)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:3], HADDR_i[2:0] + 3'b100};
                            else if (wrap_four)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b0100};
                            else if (wrap_eight)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:5], HADDR_i[4:0] + 5'b00100};
                            else if (wrap_sixteen)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:6], HADDR_i[5:0] + 6'b000100};
                            else
                                HADDR_i <= HADDR_i + 4;
                        end
                        default: HADDR_i <= HADDR_i;
                    endcase
                end
            end
        end else if ((C_M_AHB_DATA_WIDTH == 64) && (C_S_AXI_SUPPORTS_NARROW_BURST == 1)) begin : gen_64_data_width_narrow
            always_ff @(posedge AHB_HCLK) begin
                if (!AHB_HRESETN) begin
                    HADDR_i <= '0;
                end else if (ahb_wr_request || ahb_rd_request) begin
                    case (axi_size)
                        3'b011: HADDR_i <= {axi_address[C_M_AHB_ADDR_WIDTH-1:3], 3'b000};
                        3'b010: HADDR_i <= {axi_address[C_M_AHB_ADDR_WIDTH-1:2], 2'b00};
                        3'b001: HADDR_i <= {axi_address[C_M_AHB_ADDR_WIDTH-1:1], 1'b0};
                        default: HADDR_i <= axi_address;
                    endcase
                end else if (incr_addr && !fixed_burst_access) begin
                    case (axi_size)
                        3'b000: begin
                            if (wrap_2_in_progress)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:1], ~HADDR_i[0]};
                            else if (wrap_four)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:2], HADDR_i[1:0] + 2'b01};
                            else if (wrap_eight)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:3], HADDR_i[2:0] + 3'b001};
                            else if (wrap_sixteen)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b0001};
                            else
                                HADDR_i <= HADDR_i + 1;
                        end
                        3'b001: begin
                            if (wrap_2_in_progress)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:2], HADDR_i[1:0] + 2'b10};
                            else if (wrap_four)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:3], HADDR_i[2:0] + 3'b010};
                            else if (wrap_eight)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b0010};
                            else if (wrap_sixteen)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:5], HADDR_i[4:0] + 5'b00010};
                            else
                                HADDR_i <= HADDR_i + 2;
                        end
                        3'b010: begin
                            if (wrap_2_in_progress)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:3], HADDR_i[2:0] + 3'b100};
                            else if (wrap_four)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b0100};
                            else if (wrap_eight)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:5], HADDR_i[4:0] + 5'b00100};
                            else if (wrap_sixteen)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:6], HADDR_i[5:0] + 6'b000100};
                            else
                                HADDR_i <= HADDR_i + 4;
                        end
                        3'b011: begin
                            if (wrap_2_in_progress)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b1000};
                            else if (wrap_four)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:5], HADDR_i[4:0] + 5'b01000};
                            else if (wrap_eight)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:6], HADDR_i[5:0] + 6'b001000};
                            else if (wrap_sixteen)
                                HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:7], HADDR_i[6:0] + 7'b0001000};
                            else
                                HADDR_i <= HADDR_i + 8;
                        end
                        default: HADDR_i <= HADDR_i;
                    endcase
                end
            end
        end else if ((C_M_AHB_DATA_WIDTH == 32) && (C_S_AXI_SUPPORTS_NARROW_BURST == 0)) begin : gen_32_data_width
            always_ff @(posedge AHB_HCLK) begin
                if (!AHB_HRESETN) begin
                    HADDR_i <= '0;
                end else if (ahb_wr_request || ahb_rd_request) begin
                    HADDR_i <= {axi_address[C_M_AHB_ADDR_WIDTH-1:2], 2'b00};
                end else if (incr_addr && !fixed_burst_access) begin
                    if (wrap_2_in_progress)
                        HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:3], HADDR_i[2:0] + 3'b100};
                    else if (wrap_four)
                        HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b0100};
                    else if (wrap_eight)
                        HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:5], HADDR_i[4:0] + 5'b00100};
                    else if (wrap_sixteen)
                        HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:6], HADDR_i[5:0] + 6'b000100};
                    else
                        HADDR_i <= HADDR_i + 4;
                end
            end
        end else if ((C_M_AHB_DATA_WIDTH == 64) && (C_S_AXI_SUPPORTS_NARROW_BURST == 0)) begin : gen_64_data_width
            always_ff @(posedge AHB_HCLK) begin
                if (!AHB_HRESETN) begin
                    HADDR_i <= '0;
                end else if (ahb_wr_request || ahb_rd_request) begin
                    HADDR_i <= {axi_address[C_M_AHB_ADDR_WIDTH-1:3], 3'b000};
                end else if (incr_addr && !fixed_burst_access) begin
                    if (wrap_2_in_progress)
                        HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:4], HADDR_i[3:0] + 4'b1000};
                    else if (wrap_four)
                        HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:5], HADDR_i[4:0] + 5'b01000};
                    else if (wrap_eight)
                        HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:6], HADDR_i[5:0] + 6'b001000};
                    else if (wrap_sixteen)
                        HADDR_i <= {HADDR_i[C_M_AHB_ADDR_WIDTH-1:7], HADDR_i[6:0] + 7'b0001000};
                    else
                        HADDR_i <= HADDR_i + 8;
                end
            end
        end
    endgenerate

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN) begin
            HPROT_i <= 4'b0011;
        end else if (ahb_wr_request || ahb_rd_request) begin
            HPROT_i[3] <= 1'b0; // always non-cacheable on AHB-Lite
            HPROT_i[2] <= axi_cache[0] & ~axi_cache[2] & ~axi_cache[3];
            HPROT_i[1] <= axi_prot[0];
            HPROT_i[0] <= ~axi_prot[2];
        end
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN)
            wrap_brst_count <= '0;
        else if (load_counter)
            wrap_brst_count <= axi_length + 8'd1;
        else if (burst_ready)
            wrap_brst_count <= wrap_brst_count - 8'd1;
    end

    assign wrap_brst_last = (wrap_brst_count == 8'd1);
    assign wrap_brst_one  = (wrap_brst_count == 8'd2);
    assign axi_len_les_eq_sixteen = (axi_length[7:4] == 4'b0000);

    assign onekb_brst_add = axi_end_address[10] | axi_end_address[11];

    always_comb begin
        if ((axi_length[3:0] == 4'b1111) && axi_len_les_eq_sixteen) begin
            if (wrap_burst_access)
                ahb_burst = 3'b110; // WRAP16
            else if (incr_burst_access && !onekb_brst_add)
                ahb_burst = 3'b111; // INCR16
            else if (incr_burst_access && onekb_brst_add)
                ahb_burst = 3'b001; // undefined INCR, split at 1 KB
            else
                ahb_burst = 3'b000;
        end else if ((axi_length[2:0] == 3'b111) && axi_len_les_eq_sixteen) begin
            if (wrap_burst_access)
                ahb_burst = 3'b100; // WRAP8
            else if (incr_burst_access && !onekb_brst_add)
                ahb_burst = 3'b101; // INCR8
            else if (incr_burst_access && onekb_brst_add)
                ahb_burst = 3'b001;
            else
                ahb_burst = 3'b000;
        end else if ((axi_length[3:0] == 4'b0011) && axi_len_les_eq_sixteen) begin
            if (wrap_burst_access)
                ahb_burst = 3'b010; // WRAP4
            else if (incr_burst_access && !onekb_brst_add)
                ahb_burst = 3'b011; // INCR4
            else if (incr_burst_access && onekb_brst_add)
                ahb_burst = 3'b001;
            else
                ahb_burst = 3'b000;
        end else begin
            if (incr_burst_access && (axi_length[3:0] == 4'b0000) && axi_len_les_eq_sixteen)
                ahb_burst = 3'b000; // SINGLE
            else if (incr_burst_access)
                ahb_burst = 3'b001; // undefined INCR
            else
                ahb_burst = 3'b000;
        end
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN)
            HBURST_i <= '0;
        else
            HBURST_i <= ahb_burst;
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN)
            HSIZE_i <= '0;
        else
            HSIZE_i <= axi_size;
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN)
            HLOCK_i <= 1'b0;
        else
            HLOCK_i <= axi_lock;
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN)
            single_ahb_wr <= 1'b0;
        else if (ahb_wr_request)
            single_ahb_wr <= single_ahb_wr_xfer;
    end

    // -------------------------------------------------------------------------
    // AHB transfer state machine
    // -------------------------------------------------------------------------
    always_comb begin
        ahb_wr_rd_ns      = ahb_wr_rd_cs;
        rd_data           = '0;
        slv_err_resp      = 1'b0;
        burst_ready       = 1'b0;
        send_wr_data      = 1'b0;
        send_wvalid       = 1'b0;
        incr_addr         = 1'b0;
        ahb_write_sm      = 1'b0;
        send_bresp_sm     = 1'b0;
        load_counter_sm   = 1'b0;
        send_rvalid       = 1'b0;
        send_rlast_sm     = 1'b0;
        send_trans_nonseq = 1'b0;
        send_trans_seq    = 1'b0;
        send_trans_idle   = 1'b0;
        send_trans_busy   = 1'b0;
        send_wrap_burst   = 1'b0;
        one_kb_splitted   = 1'b0;
        load_cntr         = 1'b0;
        cntr_enable       = 1'b0;

        case (ahb_wr_rd_cs)
            AHB_IDLE: begin
                if (ahb_wr_request) begin
                    send_wrap_burst   = axi_burst[1] & ~axi_burst[0];
                    load_counter_sm   = 1'b1;
                    load_cntr         = 1'b1;
                    send_trans_nonseq = 1'b1;
                    ahb_wr_rd_ns      = AHB_WR_ADDR;
                end else if (ahb_rd_request) begin
                    send_trans_nonseq = 1'b1;
                    load_cntr         = 1'b1;
                    if (single_ahb_rd_xfer) begin
                        ahb_wr_rd_ns = AHB_RD_SINGLE;
                    end else if (!axi_burst[1]) begin
                        load_counter_sm = 1'b1;
                        ahb_wr_rd_ns    = AHB_RD_ADDR;
                    end else if (axi_burst == 2'b10) begin
                        send_wrap_burst = 1'b1;
                        load_counter_sm = 1'b1;
                        ahb_wr_rd_ns    = AHB_RD_ADDR;
                    end
                end
            end

            AHB_WR_SINGLE: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable   = timeout_inprogress;
                    load_cntr     = ~timeout_inprogress;
                    send_bresp_sm = 1'b1;
                    slv_err_resp  = ahb_hslverr;
                    burst_ready   = 1'b1;
                    ahb_wr_rd_ns  = AHB_IDLE;
                end
            end

            AHB_WR_WAIT: begin
                if (send_ahb_wr) begin
                    if (one_kb_in_progress && !one_kb_cross) begin
                        send_trans_nonseq = 1'b1;
                        one_kb_splitted   = 1'b1;
                    end else if (fixed_burst_access) begin
                        send_trans_nonseq = 1'b1;
                    end else begin
                        send_trans_seq = 1'b1;
                    end
                    ahb_wr_rd_ns = AHB_INCR_ADDR;
                end else begin
                    send_trans_idle = fixed_burst_access;
                end
            end

            AHB_INCR_ADDR: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable  = timeout_inprogress;
                    load_cntr    = ~timeout_inprogress;
                    send_wr_data = 1'b1;
                    incr_addr    = 1'b1;
                    if (one_kb_in_progress || fixed_burst_access)
                        send_trans_idle = 1'b1;
                    else
                        send_trans_busy = 1'b1;
                    ahb_wr_rd_ns = AHB_WR_INCR;
                end
            end

            AHB_LAST_ADDR: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable     = timeout_inprogress;
                    load_cntr       = ~timeout_inprogress;
                    send_wr_data    = 1'b1;
                    send_trans_idle = 1'b1;
                    ahb_wr_rd_ns    = AHB_WR_INCR;
                end
            end

            AHB_LAST_WAIT: begin
                if (send_ahb_wr) begin
                    if (one_kb_in_progress && !one_kb_cross) begin
                        send_trans_nonseq = 1'b1;
                        one_kb_splitted   = 1'b1;
                    end else if (fixed_burst_access || wrap_2_in_progress) begin
                        send_trans_nonseq = 1'b1;
                    end else begin
                        send_trans_seq = 1'b1;
                    end
                    ahb_wr_rd_ns = AHB_LAST_ADDR;
                end else if (one_kb_in_progress && !one_kb_cross) begin
                    ahb_wr_rd_ns = AHB_ONEKB_LAST;
                end
            end

            AHB_LAST: begin
                if (send_ahb_wr) begin
                    if (fixed_burst_access || wrap_2_in_progress)
                        send_trans_nonseq = 1'b1;
                    else
                        send_trans_seq = 1'b1;
                    ahb_wr_rd_ns = AHB_LAST_ADDR;
                end
            end

            AHB_ONEKB_LAST: begin
                if (send_ahb_wr) begin
                    send_trans_nonseq = 1'b1;
                    one_kb_splitted   = 1'b1;
                    ahb_wr_rd_ns      = AHB_LAST_ADDR;
                end
            end

            AHB_WR_INCR: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable  = timeout_inprogress;
                    load_cntr    = ~timeout_inprogress;
                    burst_ready  = 1'b1;
                    send_wvalid  = 1'b1;
                    slv_err_resp = ahb_hslverr;

                    if (wrap_brst_last) begin
                        send_bresp_sm   = 1'b1;
                        send_trans_idle = 1'b1;
                        ahb_wr_rd_ns    = AHB_IDLE;
                    end else if (wrap_brst_one) begin
                        if (axi_wvalid) begin
                            if (one_kb_in_progress && !one_kb_cross) begin
                                send_trans_nonseq = 1'b1;
                                one_kb_splitted   = 1'b1;
                            end else if (fixed_burst_access || wrap_2_in_progress) begin
                                send_trans_nonseq = 1'b1;
                            end else begin
                                send_trans_seq = 1'b1;
                            end
                            ahb_wr_rd_ns = AHB_LAST_ADDR;
                        end else begin
                            if ((one_kb_in_progress && !one_kb_cross) ||
                                fixed_burst_access || wrap_2_in_progress) begin
                                send_trans_idle = 1'b1;
                                ahb_wr_rd_ns    = AHB_LAST_WAIT;
                            end else begin
                                send_trans_busy = 1'b1;
                                ahb_wr_rd_ns    = AHB_LAST;
                            end
                        end
                    end else begin
                        if (axi_wvalid) begin
                            if (one_kb_in_progress && !one_kb_cross) begin
                                send_trans_nonseq = 1'b1;
                                one_kb_splitted   = 1'b1;
                            end else if (fixed_burst_access) begin
                                send_trans_nonseq = 1'b1;
                            end else begin
                                send_trans_seq = 1'b1;
                            end
                            ahb_wr_rd_ns = AHB_INCR_ADDR;
                        end else begin
                            send_trans_idle = fixed_burst_access;
                            ahb_wr_rd_ns    = AHB_WR_WAIT;
                        end
                    end
                end
            end

            AHB_WR_ADDR: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable  = timeout_inprogress;
                    load_cntr    = ~timeout_inprogress;
                    send_wr_data = 1'b1;
                    if (single_ahb_wr) begin
                        send_trans_idle = 1'b1;
                        ahb_wr_rd_ns    = AHB_WR_SINGLE;
                    end else if (wrap_2_in_progress || fixed_burst_access ||
                                 one_kb_in_progress || one_kb_cross) begin
                        send_trans_idle = 1'b1;
                        incr_addr       = 1'b1;
                        ahb_wr_rd_ns    = AHB_WR_INCR;
                    end else begin
                        incr_addr       = 1'b1;
                        send_trans_busy = 1'b1;
                        ahb_wr_rd_ns    = AHB_WR_INCR;
                    end
                end
            end

            AHB_RD_SINGLE: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable     = timeout_inprogress;
                    load_cntr       = ~timeout_inprogress;
                    send_trans_idle = 1'b1;
                    ahb_wr_rd_ns    = AHB_RD_LAST;
                end
            end

            AHB_RD_LAST: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable   = timeout_inprogress;
                    load_cntr     = ~timeout_inprogress;
                    burst_ready   = 1'b1;
                    slv_err_resp  = ahb_hslverr;
                    rd_data       = ahb_hrdata;
                    send_rvalid   = 1'b1;
                    send_rlast_sm = 1'b1;
                    ahb_wr_rd_ns  = AHB_IDLE;
                end
            end

            AHB_RD_ADDR: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable = timeout_inprogress;
                    load_cntr   = ~timeout_inprogress;
                    if (wrap_brst_last) begin
                        send_trans_idle = 1'b1;
                        ahb_wr_rd_ns    = AHB_RD_LAST;
                    end else if (wrap_2_in_progress || fixed_burst_access ||
                                 one_kb_in_progress || one_kb_cross) begin
                        send_trans_idle = 1'b1;
                        incr_addr       = 1'b1;
                        ahb_wr_rd_ns    = AHB_RD_DATA_INCR;
                    end else begin
                        incr_addr       = 1'b1;
                        send_trans_busy = 1'b1;
                        ahb_wr_rd_ns    = AHB_RD_DATA_INCR;
                    end
                end
            end

            AHB_RD_WAIT: begin
                if (axi_rready) begin
                    // A resumed segment and each SINGLE transfer must start with
                    // NONSEQ, even when only the final AXI beat remains.
                    if (one_kb_in_progress && !one_kb_cross) begin
                        send_trans_nonseq = 1'b1;
                        one_kb_splitted   = 1'b1;
                    end else if (fixed_burst_access || wrap_2_in_progress) begin
                        send_trans_nonseq = 1'b1;
                    end else begin
                        send_trans_seq = 1'b1;
                    end
                    ahb_wr_rd_ns = AHB_RD_ADDR;
                end
            end

            AHB_RD_DATA_INCR: begin
                cntr_enable = 1'b1;
                if (ahb_hready || timeout_inprogress) begin
                    cntr_enable  = timeout_inprogress;
                    load_cntr    = ~timeout_inprogress;
                    burst_ready  = 1'b1;
                    slv_err_resp = ahb_hslverr;
                    rd_data      = ahb_hrdata;
                    send_rvalid  = 1'b1;
                    if (axi_rready) begin
                        if (one_kb_in_progress && !one_kb_cross) begin
                            send_trans_nonseq = 1'b1;
                            one_kb_splitted   = 1'b1;
                        end else if (wrap_2_in_progress || fixed_burst_access) begin
                            send_trans_nonseq = 1'b1;
                        end else begin
                            send_trans_seq = 1'b1;
                        end
                        ahb_wr_rd_ns = AHB_RD_ADDR;
                    end else begin
                        ahb_wr_rd_ns = AHB_RD_WAIT;
                    end
                end
            end

            default: ahb_wr_rd_ns = AHB_IDLE;
        endcase
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN) begin
            ahb_wr_rd_cs <= AHB_IDLE;
            load_counter <= 1'b0;
        end else begin
            ahb_wr_rd_cs <= ahb_wr_rd_ns;
            load_counter <= load_counter_sm;
        end
    end

    // AXI last-beat address relative to the current 1-KB region.
    assign axi_end_address = {2'b00, axi_address[9:0]} + axi_length_burst;

    always_comb begin
        case (axi_size)
            3'b001: axi_length_burst = {3'b000, axi_length, 1'b0};
            3'b010: axi_length_burst = {2'b00,  axi_length, 2'b00};
            3'b011: axi_length_burst = {1'b0,   axi_length, 3'b000};
            default: axi_length_burst = {4'b0000, axi_length};
        endcase
    end

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN) begin
            onekb_cross_access <= 1'b0;
        end else begin
            if (ahb_wr_request || ahb_rd_request)
                onekb_cross_access <= axi_end_address[10] | axi_end_address[11];
            else if (wrap_brst_last)
                onekb_cross_access <= 1'b0;
        end
    end

    assign addr_all_ones =
        ((HADDR_i[9:2] == 8'hFF)  && (HSIZE_i == 3'b010)) ||
        ((HADDR_i[9:1] == 9'h1FF) && (HSIZE_i == 3'b001)) ||
        ((HADDR_i[9:3] == 7'h7F)  && (HSIZE_i == 3'b011)) ||
        ((HADDR_i[9:0] == 10'h3FF) && (HSIZE_i == 3'b000));

    assign one_kb_cross = onekb_cross_access & addr_all_ones &
                          ~wrap_in_progress & ~fixed_burst_access;

    always_ff @(posedge AHB_HCLK) begin
        if (!AHB_HRESETN) begin
            one_kb_in_progress <= 1'b0;
        end else begin
            if (one_kb_cross)
                one_kb_in_progress <= 1'b1;
            else if (one_kb_splitted || (ahb_wr_rd_cs == AHB_IDLE))
                one_kb_in_progress <= 1'b0;
        end
    end

endmodule