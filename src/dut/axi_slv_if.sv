//=============================================================================
// File        : axi_slv_if
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 slave-side control for the AXI4-to-AHB-Lite bridge.
//               Accepts AXI requests and returns read and write responses.
//=============================================================================

`timescale 1ns/1ps

module axi_slv_if #(
    parameter string C_FAMILY           = "virtex6",
    parameter int    C_S_AXI_ID_WIDTH   = 4,
    parameter int    C_S_AXI_ADDR_WIDTH = 32,
    parameter int    C_S_AXI_DATA_WIDTH = 32,
    parameter int    C_DPHASE_TIMEOUT   = 0
) (
    input  logic                               S_AXI_ACLK,
    input  logic                               S_AXI_ARESETN,

    input  logic [C_S_AXI_ID_WIDTH-1:0]        S_AXI_AWID,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]      S_AXI_AWADDR,
    input  logic [2:0]                         S_AXI_AWPROT,
    input  logic [3:0]                         S_AXI_AWCACHE,
    input  logic [7:0]                         S_AXI_AWLEN,
    input  logic [2:0]                         S_AXI_AWSIZE,
    input  logic [1:0]                         S_AXI_AWBURST,
    input  logic                               S_AXI_AWLOCK,
    input  logic                               S_AXI_AWVALID,
    output logic                               S_AXI_AWREADY,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]      S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0]  S_AXI_WSTRB,
    input  logic                               S_AXI_WVALID,
    input  logic                               S_AXI_WLAST,
    output logic                               S_AXI_WREADY,

    output logic [C_S_AXI_ID_WIDTH-1:0]        S_AXI_BID,
    output logic [1:0]                         S_AXI_BRESP,
    output logic                               S_AXI_BVALID,
    input  logic                               S_AXI_BREADY,

    input  logic [C_S_AXI_ID_WIDTH-1:0]        S_AXI_ARID,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]      S_AXI_ARADDR,
    input  logic                               S_AXI_ARVALID,
    input  logic [2:0]                         S_AXI_ARPROT,
    input  logic [3:0]                         S_AXI_ARCACHE,
    input  logic [7:0]                         S_AXI_ARLEN,
    input  logic [2:0]                         S_AXI_ARSIZE,
    input  logic [1:0]                         S_AXI_ARBURST,
    input  logic                               S_AXI_ARLOCK,
    output logic                               S_AXI_ARREADY,

    output logic [C_S_AXI_ID_WIDTH-1:0]        S_AXI_RID,
    output logic [C_S_AXI_DATA_WIDTH-1:0]      S_AXI_RDATA,
    output logic [1:0]                         S_AXI_RRESP,
    output logic                               S_AXI_RVALID,
    output logic                               S_AXI_RLAST,
    input  logic                               S_AXI_RREADY,

    output logic [2:0]                         axi_prot,
    output logic [3:0]                         axi_cache,
    output logic [2:0]                         axi_size,
    output logic                               axi_lock,
    output logic [C_S_AXI_DATA_WIDTH-1:0]      axi_wdata,
    output logic                               ahb_rd_request,
    output logic                               ahb_wr_request,
    input  logic                               slv_err_resp,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]      rd_data,
    output logic [C_S_AXI_ADDR_WIDTH-1:0]      axi_address,
    output logic [1:0]                         axi_burst,
    output logic [7:0]                         axi_length,
    input  logic                               send_wvalid,
    output logic                               send_ahb_wr,
    output logic                               axi_wvalid,
    output logic                               single_ahb_wr_xfer,
    output logic                               single_ahb_rd_xfer,
    input  logic                               send_bresp,
    input  logic                               send_rvalid,
    input  logic                               send_rlast,
    output logic                               axi_rready,
    input  logic                               timeout_i,
    output logic                               timeout_inprogress
);

    typedef enum logic [2:0] {
        AXI_WR_IDLE,
        AXI_WRITING,
        AXI_WVALIDS_WAIT,
        AXI_WVALID_WAIT,
        AXI_WRITE_LAST,
        AXI_WR_RESP_WAIT,
        AXI_WR_RESP
    } axi_wr_sm_t;

    typedef enum logic [2:0] {
        AXI_RD_IDLE,
        AXI_READ_LAST,
        AXI_READING,
        AXI_WAIT_RREADY,
        RD_RESP
    } axi_rd_sm_t;

    axi_wr_sm_t axi_write_ns, axi_write_cs;
    axi_rd_sm_t axi_read_ns,  axi_read_cs;

    logic ARREADY_i, WREADY_i, AWREADY_i;
    logic BVALID_i, BRESP_1_i;
    logic RVALID_i, RLAST_i, RRESP_1_i;
    logic write_ready_sm, wr_addr_ready_sm, rd_addr_ready_sm;
    logic BVALID_sm, RVALID_sm, RLAST_sm;
    logic wr_request, rd_request;
    logic write_pending, write_waiting, write_complete;
    logic [C_S_AXI_ID_WIDTH-1:0] BID_i, RID_i;
    logic [C_S_AXI_ID_WIDTH-1:0] axi_rid, axi_wid;
    logic single_axi_wr_xfer, single_axi_rd_xfer;
    logic write_in_progress, read_in_progress;
    logic write_statrted;
    logic send_rd_data;
    logic wr_err_occured;
    logic axi_wlast;
    logic timeout_inprogress_s;
    logic byte_transfer, halfword_transfer, word_transfer, doubleword_transfer;

    assign S_AXI_AWREADY = AWREADY_i;
    assign S_AXI_BID     = BID_i;
    assign S_AXI_RID     = RID_i;
    assign S_AXI_WREADY  = WREADY_i;
    assign S_AXI_BRESP   = {BRESP_1_i, 1'b0};
    assign S_AXI_BVALID  = BVALID_i;
    assign S_AXI_ARREADY = ARREADY_i;
    assign S_AXI_RRESP   = {RRESP_1_i, 1'b0};
    assign S_AXI_RVALID  = RVALID_i;
    assign S_AXI_RLAST   = RLAST_i;

    assign timeout_inprogress = timeout_inprogress_s;
    assign axi_wvalid          = S_AXI_WVALID;
    assign axi_rready          = S_AXI_RREADY;
    assign single_ahb_wr_xfer  = single_axi_wr_xfer;
    assign single_ahb_rd_xfer  = single_axi_rd_xfer;

    // For single-beat writes, WSTRB can imply a transfer size narrower than the bus.
    generate
        if (C_S_AXI_DATA_WIDTH == 32) begin : gen_32_narrow_decode
            always_comb begin
                byte_transfer = (S_AXI_WSTRB == 4'b0001) ||
                                (S_AXI_WSTRB == 4'b0010) ||
                                (S_AXI_WSTRB == 4'b0100) ||
                                (S_AXI_WSTRB == 4'b1000);
                halfword_transfer = (S_AXI_WSTRB == 4'b0011) ||
                                    (S_AXI_WSTRB == 4'b1100);
                word_transfer       = (S_AXI_WSTRB == 4'b1111);
                doubleword_transfer = 1'b0;
            end
        end else if (C_S_AXI_DATA_WIDTH == 64) begin : gen_64_narrow_decode
            always_comb begin
                byte_transfer = (S_AXI_WSTRB == 8'b00000001) ||
                                (S_AXI_WSTRB == 8'b00000010) ||
                                (S_AXI_WSTRB == 8'b00000100) ||
                                (S_AXI_WSTRB == 8'b00001000) ||
                                (S_AXI_WSTRB == 8'b00010000) ||
                                (S_AXI_WSTRB == 8'b00100000) ||
                                (S_AXI_WSTRB == 8'b01000000) ||
                                (S_AXI_WSTRB == 8'b10000000);
                halfword_transfer = (S_AXI_WSTRB == 8'b00000011) ||
                                    (S_AXI_WSTRB == 8'b00001100) ||
                                    (S_AXI_WSTRB == 8'b00110000) ||
                                    (S_AXI_WSTRB == 8'b11000000);
                word_transfer       = (S_AXI_WSTRB == 8'b00001111) ||
                                      (S_AXI_WSTRB == 8'b11110000);
                doubleword_transfer = (S_AXI_WSTRB == 8'b11111111);
            end
        end else begin : gen_unsupported_narrow_decode
            always_comb begin
                byte_transfer       = 1'b0;
                halfword_transfer   = 1'b0;
                word_transfer       = 1'b0;
                doubleword_transfer = 1'b0;
            end
        end
    endgenerate

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            RID_i <= '0;
        else
            RID_i <= axi_rid;
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            RRESP_1_i <= 1'b0;
        end else begin
            if (send_rd_data)
                RRESP_1_i <= slv_err_resp | timeout_inprogress_s;
            else if (S_AXI_RREADY)
                RRESP_1_i <= 1'b0;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RDATA <= '0;
        end else begin
            if (send_rd_data)
                S_AXI_RDATA <= rd_data;
            else if (S_AXI_RREADY)
                S_AXI_RDATA <= '0;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            BID_i <= '0;
        else
            BID_i <= axi_wid;
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_rid <= '0;
        else if (rd_addr_ready_sm)
            axi_rid <= S_AXI_ARID;
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_wid <= '0;
        else if (wr_addr_ready_sm)
            axi_wid <= S_AXI_AWID;
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_address <= '0;
        end else if (wr_addr_ready_sm) begin
            axi_address <= S_AXI_AWADDR;
        end else if (rd_addr_ready_sm) begin
            axi_address <= S_AXI_ARADDR;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_prot <= '0;
        end else if (wr_addr_ready_sm) begin
            axi_prot <= S_AXI_AWPROT;
        end else if (rd_addr_ready_sm) begin
            axi_prot <= S_AXI_ARPROT;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_cache <= '0;
        end else if (wr_addr_ready_sm) begin
            axi_cache <= S_AXI_AWCACHE;
        end else if (rd_addr_ready_sm) begin
            axi_cache <= S_AXI_ARCACHE;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_lock <= 1'b0;
        end else if (wr_addr_ready_sm) begin
            axi_lock <= S_AXI_AWLOCK;
        end else if (rd_addr_ready_sm) begin
            axi_lock <= S_AXI_ARLOCK;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_size <= '0;
        end else if (wr_addr_ready_sm) begin
            if (S_AXI_AWLEN == 8'd0) begin
                if (byte_transfer)
                    axi_size <= 3'b000;
                else if (halfword_transfer)
                    axi_size <= 3'b001;
                else if (word_transfer)
                    axi_size <= 3'b010;
                else if (doubleword_transfer)
                    axi_size <= 3'b011;
                else
                    axi_size <= S_AXI_AWSIZE;
            end else begin
                axi_size <= S_AXI_AWSIZE;
            end
        end else if (rd_addr_ready_sm) begin
            axi_size <= S_AXI_ARSIZE;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_length <= '0;
        end else if (wr_addr_ready_sm) begin
            axi_length <= S_AXI_AWLEN;
        end else if (rd_addr_ready_sm) begin
            axi_length <= S_AXI_ARLEN;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_burst <= '0;
        end else if (wr_addr_ready_sm) begin
            axi_burst <= S_AXI_AWBURST;
        end else if (rd_addr_ready_sm) begin
            axi_burst <= S_AXI_ARBURST;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_wdata <= '0;
        else if (write_ready_sm)
            axi_wdata <= S_AXI_WDATA;
    end

    // AXI response bit[1] is SLVERR. Bit[0] is always zero (OKAY/SLVERR only).
    assign BRESP_1_i = wr_err_occured | timeout_inprogress_s;

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            write_in_progress <= 1'b0;
        end else begin
            if (write_statrted)
                write_in_progress <= 1'b1;
            else if (write_complete)
                write_in_progress <= 1'b0;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            wr_err_occured <= 1'b0;
        end else begin
            if (write_in_progress && slv_err_resp)
                wr_err_occured <= 1'b1;
            else if (write_complete)
                wr_err_occured <= 1'b0;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            read_in_progress <= 1'b0;
        end else begin
            if (rd_addr_ready_sm)
                read_in_progress <= 1'b1;
            else if (RLAST_sm)
                read_in_progress <= 1'b0;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            write_pending <= 1'b0;
        end else begin
            if (write_waiting)
                write_pending <= 1'b1;
            else if (BVALID_sm)
                write_pending <= 1'b0;
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            single_axi_wr_xfer <= 1'b0;
        end else begin
            if (S_AXI_AWVALID) begin
                if ((S_AXI_AWLEN == 8'd0) && !S_AXI_AWBURST[1])
                    single_axi_wr_xfer <= 1'b1;
                else
                    single_axi_wr_xfer <= 1'b0;
            end else if (BVALID_sm) begin
                single_axi_wr_xfer <= 1'b0;
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            single_axi_rd_xfer <= 1'b0;
        end else begin
            if (S_AXI_ARVALID) begin
                if ((S_AXI_ARLEN == 8'd0) && !S_AXI_ARBURST[1])
                    single_axi_rd_xfer <= 1'b1;
                else
                    single_axi_rd_xfer <= 1'b0;
            end else if (RLAST_sm) begin
                single_axi_rd_xfer <= 1'b0;
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_wlast <= 1'b0;
        else
            axi_wlast <= S_AXI_WLAST;
    end

    generate
        if (C_DPHASE_TIMEOUT != 0) begin : gen_timeout_inprogress
            always_ff @(posedge S_AXI_ACLK) begin
                if (!S_AXI_ARESETN) begin
                    timeout_inprogress_s <= 1'b0;
                end else begin
                    if (!write_in_progress && !read_in_progress)
                        timeout_inprogress_s <= 1'b0;
                    else if (timeout_i && (write_in_progress || read_in_progress))
                        timeout_inprogress_s <= 1'b1;
                end
            end
        end else begin : gen_timeout_notinprogress
            always_comb timeout_inprogress_s = 1'b0;
        end
    endgenerate

    // Write channel FSM. Read requests have priority when both directions arrive together.
    always_comb begin
        axi_write_ns     = axi_write_cs;
        write_ready_sm   = 1'b0;
        wr_addr_ready_sm = 1'b0;
        wr_request       = 1'b0;
        BVALID_sm        = 1'b0;
        write_complete   = 1'b0;
        send_ahb_wr      = 1'b0;
        write_statrted   = 1'b0;

        case (axi_write_cs)
            AXI_WR_IDLE: begin
                if ((S_AXI_AWVALID || S_AXI_WVALID) &&
                    ((!write_pending && !S_AXI_ARVALID) || write_pending) &&
                    !read_in_progress) begin
                    write_statrted = 1'b1;
                    axi_write_ns   = AXI_WVALIDS_WAIT;
                end
            end

            AXI_WVALIDS_WAIT: begin
                if (S_AXI_AWVALID && S_AXI_WVALID) begin
                    write_ready_sm   = 1'b1;
                    wr_addr_ready_sm = 1'b1;
                    wr_request       = 1'b1;
                    axi_write_ns     = single_axi_wr_xfer ? AXI_WRITE_LAST : AXI_WRITING;
                end
            end

            AXI_WVALID_WAIT: begin
                write_ready_sm = S_AXI_WVALID;
                send_ahb_wr    = S_AXI_WVALID;
                if (S_AXI_WVALID)
                    axi_write_ns = AXI_WRITING;
            end

            AXI_WRITING: begin
                if (S_AXI_WVALID && S_AXI_WLAST) begin
                    write_ready_sm = send_wvalid;
                    send_ahb_wr    = send_wvalid;
                    axi_write_ns   = send_bresp ? AXI_WR_RESP_WAIT : AXI_WRITE_LAST;
                end else if (send_wvalid) begin
                    write_ready_sm = S_AXI_WVALID;
                    send_ahb_wr    = S_AXI_WVALID;
                    if (!S_AXI_WVALID)
                        axi_write_ns = AXI_WVALID_WAIT;
                end
            end

            AXI_WR_RESP_WAIT: begin
                BVALID_sm    = 1'b1;
                axi_write_ns = AXI_WR_RESP;
            end

            AXI_WRITE_LAST: begin
                send_ahb_wr    = 1'b1;
                write_ready_sm = send_wvalid;
                BVALID_sm      = send_bresp;
                if (send_bresp) begin
                    axi_write_ns   = AXI_WR_RESP;
                    write_ready_sm = 1'b0;
                end
            end

            AXI_WR_RESP: begin
                write_complete = S_AXI_BREADY;
                BVALID_sm      = ~S_AXI_BREADY;
                if (S_AXI_BREADY)
                    axi_write_ns = AXI_WR_IDLE;
            end

            default: axi_write_ns = AXI_WR_IDLE;
        endcase
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_write_cs <= AXI_WR_IDLE;
            WREADY_i     <= 1'b0;
            AWREADY_i    <= 1'b0;
            BVALID_i     <= 1'b0;
        end else begin
            axi_write_cs <= axi_write_ns;
            WREADY_i     <= write_ready_sm;
            AWREADY_i    <= wr_addr_ready_sm;
            BVALID_i     <= BVALID_sm;
        end
    end

    always_comb begin
        axi_read_ns      = axi_read_cs;
        rd_request       = 1'b0;
        RVALID_sm        = 1'b0;
        RLAST_sm         = 1'b0;
        rd_addr_ready_sm = 1'b0;
        write_waiting    = 1'b0;
        send_rd_data     = 1'b0;

        case (axi_read_cs)
            AXI_RD_IDLE: begin
                if (S_AXI_ARVALID && !write_pending && !write_in_progress) begin
                    rd_request       = 1'b1;
                    rd_addr_ready_sm = 1'b1;
                    axi_read_ns      = single_axi_rd_xfer ? AXI_READ_LAST : AXI_READING;
                end
            end

            AXI_READING: begin
                send_rd_data = send_rlast | send_rvalid;
                RVALID_sm    = send_rlast | send_rvalid;
                if (send_rlast) begin
                    RLAST_sm    = 1'b1;
                    axi_read_ns = RD_RESP;
                end else if (send_rvalid && !S_AXI_RREADY) begin
                    axi_read_ns = AXI_WAIT_RREADY;
                end
            end

            AXI_WAIT_RREADY: begin
                if (S_AXI_RREADY)
                    axi_read_ns = AXI_READING;
                else
                    RVALID_sm = 1'b1;
            end

            RD_RESP: begin
                if (S_AXI_RREADY) begin
                    if (S_AXI_AWVALID || S_AXI_WVALID)
                        write_waiting = 1'b1;
                    axi_read_ns = AXI_RD_IDLE;
                end else begin
                    RVALID_sm = 1'b1;
                    RLAST_sm  = 1'b1;
                end
            end

            AXI_READ_LAST: begin
                if (send_rlast) begin
                    send_rd_data = 1'b1;
                    RLAST_sm     = 1'b1;
                    RVALID_sm    = 1'b1;
                    axi_read_ns  = RD_RESP;
                end
            end

            default: axi_read_ns = AXI_RD_IDLE;
        endcase
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_read_cs   <= AXI_RD_IDLE;
            ARREADY_i     <= 1'b0;
            RVALID_i      <= 1'b0;
            RLAST_i       <= 1'b0;
            ahb_rd_request <= 1'b0;
            ahb_wr_request <= 1'b0;
        end else begin
            ahb_rd_request <= rd_request;
            ahb_wr_request <= wr_request;
            axi_read_cs     <= axi_read_ns;
            ARREADY_i       <= rd_addr_ready_sm;
            RVALID_i        <= RVALID_sm;
            RLAST_i         <= RLAST_sm;
        end
    end

endmodule