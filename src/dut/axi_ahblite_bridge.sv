//=============================================================================
// File        : axi_ahblite_bridge
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Top-level AXI4 slave to AHB-Lite master bridge.
//               Connects the AXI control path to the AHB-Lite master interface.
//=============================================================================

`timescale 1ns/1ps

module axi_ahblite_bridge #(
    parameter string C_FAMILY                      = "virtex7",
    parameter string C_INSTANCE                    = "axi_ahblite_bridge_inst",
    parameter int    C_S_AXI_ADDR_WIDTH            = 32,
    parameter int    C_S_AXI_DATA_WIDTH            = 32,
    parameter int    C_S_AXI_SUPPORTS_NARROW_BURST = 0,
    parameter int    C_S_AXI_ID_WIDTH              = 4,
    parameter int    C_M_AHB_ADDR_WIDTH            = 32,
    parameter int    C_M_AHB_DATA_WIDTH            = 32,
    parameter int    C_DPHASE_TIMEOUT              = 0
) (
    input  logic                              s_axi_aclk,
    input  logic                              s_axi_aresetn,

    input  logic [C_S_AXI_ID_WIDTH-1:0]       s_axi_awid,
    input  logic [7:0]                        s_axi_awlen,
    input  logic [2:0]                        s_axi_awsize,
    input  logic [1:0]                        s_axi_awburst,
    input  logic [3:0]                        s_axi_awcache,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  logic [2:0]                        s_axi_awprot,
    input  logic                              s_axi_awvalid,
    output logic                              s_axi_awready,
    input  logic                              s_axi_awlock,

    input  logic [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                              s_axi_wlast,
    input  logic                              s_axi_wvalid,
    output logic                              s_axi_wready,

    output logic [C_S_AXI_ID_WIDTH-1:0]       s_axi_bid,
    output logic [1:0]                        s_axi_bresp,
    output logic                              s_axi_bvalid,
    input  logic                              s_axi_bready,

    input  logic [C_S_AXI_ID_WIDTH-1:0]       s_axi_arid,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  logic [2:0]                        s_axi_arprot,
    input  logic [3:0]                        s_axi_arcache,
    input  logic                              s_axi_arvalid,
    input  logic [7:0]                        s_axi_arlen,
    input  logic [2:0]                        s_axi_arsize,
    input  logic [1:0]                        s_axi_arburst,
    input  logic                              s_axi_arlock,
    output logic                              s_axi_arready,

    output logic [C_S_AXI_ID_WIDTH-1:0]       s_axi_rid,
    output logic [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output logic [1:0]                        s_axi_rresp,
    output logic                              s_axi_rvalid,
    output logic                              s_axi_rlast,
    input  logic                              s_axi_rready,

    output logic [C_M_AHB_ADDR_WIDTH-1:0]     m_ahb_haddr,
    output logic                              m_ahb_hwrite,
    output logic [2:0]                        m_ahb_hsize,
    output logic [2:0]                        m_ahb_hburst,
    output logic [3:0]                        m_ahb_hprot,
    output logic [1:0]                        m_ahb_htrans,
    output logic                              m_ahb_hmastlock,
    output logic [C_M_AHB_DATA_WIDTH-1:0]     m_ahb_hwdata,

    input  logic                              m_ahb_hready,
    input  logic [C_M_AHB_DATA_WIDTH-1:0]     m_ahb_hrdata,
    input  logic                              m_ahb_hresp
);

    logic [C_S_AXI_ADDR_WIDTH-1:0] axi_address;
    logic ahb_rd_request, ahb_wr_request;
    logic [C_M_AHB_DATA_WIDTH-1:0] rd_data;
    logic slv_err_resp;
    logic axi_lock;
    logic [2:0] axi_prot;
    logic [3:0] axi_cache;
    logic [2:0] axi_size;
    logic [1:0] axi_burst;
    logic [7:0] axi_length;
    logic [C_S_AXI_DATA_WIDTH-1:0] axi_wdata;
    logic send_wvalid, send_ahb_wr, axi_wvalid;
    logic send_bresp, send_rvalid, send_rlast, axi_rready;
    logic single_ahb_wr_xfer, single_ahb_rd_xfer;
    logic load_cntr, cntr_enable;
    logic timeout_s, timeout_inprogress;

    logic s_axi_aresetn_int;
    logic [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata_int;
    logic s_axi_rvalid_int;
    logic s_axi_rlast_int;
    logic s_axi_rready_int;
    logic [C_S_AXI_ID_WIDTH-1:0] s_axi_rid_int;
    logic [1:0] s_axi_rresp_int;

    assign s_axi_aresetn_int = ~s_axi_aresetn;

    // Read-data skid buffer decouples the internal read FSM from AXI RREADY.
    ahb_skid_buf #(
        .C_WDATA_WIDTH   (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ID_WIDTH(C_S_AXI_ID_WIDTH),
        .C_TUSER_WIDTH   (1)
    ) valid_ready_skid (
        .ACLK      (s_axi_aclk),
        .ARST      (s_axi_aresetn_int),
        .skid_stop (1'b0),

        .S_VALID   (s_axi_rvalid_int),
        .S_READY   (s_axi_rready_int),
        .S_Data    (s_axi_rdata_int),
        .S_STRB    ('0),
        .S_Last    (s_axi_rlast_int),
        .S_User    ('0),
        .S_RID     (s_axi_rid_int),
        .S_RESP    (s_axi_rresp_int),

        .M_RESP    (s_axi_rresp),
        .M_VALID   (s_axi_rvalid),
        .M_READY   (s_axi_rready),
        .M_RID     (s_axi_rid),
        .M_Data    (s_axi_rdata),
        .M_STRB    (),
        .M_Last    (s_axi_rlast),
        .M_User    ()
    );

    axi_slv_if #(
        .C_FAMILY          (C_FAMILY),
        .C_S_AXI_ID_WIDTH  (C_S_AXI_ID_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_DPHASE_TIMEOUT  (C_DPHASE_TIMEOUT)
    ) axi_slv_if_module (
        .S_AXI_ACLK        (s_axi_aclk),
        .S_AXI_ARESETN     (s_axi_aresetn),

        .S_AXI_AWID        (s_axi_awid),
        .S_AXI_AWADDR      (s_axi_awaddr),
        .S_AXI_AWPROT      (s_axi_awprot),
        .S_AXI_AWCACHE     (s_axi_awcache),
        .S_AXI_AWLEN       (s_axi_awlen),
        .S_AXI_AWSIZE      (s_axi_awsize),
        .S_AXI_AWBURST     (s_axi_awburst),
        .S_AXI_AWLOCK      (s_axi_awlock),
        .S_AXI_AWVALID     (s_axi_awvalid),
        .S_AXI_AWREADY     (s_axi_awready),
        .S_AXI_WDATA       (s_axi_wdata),
        .S_AXI_WSTRB       (s_axi_wstrb),
        .S_AXI_WVALID      (s_axi_wvalid),
        .S_AXI_WLAST       (s_axi_wlast),
        .S_AXI_WREADY      (s_axi_wready),
        .S_AXI_BID         (s_axi_bid),
        .S_AXI_BRESP       (s_axi_bresp),
        .S_AXI_BVALID      (s_axi_bvalid),
        .S_AXI_BREADY      (s_axi_bready),

        .S_AXI_ARID        (s_axi_arid),
        .S_AXI_ARADDR      (s_axi_araddr),
        .S_AXI_ARVALID     (s_axi_arvalid),
        .S_AXI_ARPROT      (s_axi_arprot),
        .S_AXI_ARCACHE     (s_axi_arcache),
        .S_AXI_ARLEN       (s_axi_arlen),
        .S_AXI_ARSIZE      (s_axi_arsize),
        .S_AXI_ARBURST     (s_axi_arburst),
        .S_AXI_ARLOCK      (s_axi_arlock),
        .S_AXI_ARREADY     (s_axi_arready),
        .S_AXI_RID         (s_axi_rid_int),
        .S_AXI_RDATA       (s_axi_rdata_int),
        .S_AXI_RRESP       (s_axi_rresp_int),
        .S_AXI_RVALID      (s_axi_rvalid_int),
        .S_AXI_RLAST       (s_axi_rlast_int),
        .S_AXI_RREADY      (s_axi_rready_int),

        .axi_prot          (axi_prot),
        .axi_cache         (axi_cache),
        .axi_size          (axi_size),
        .axi_lock          (axi_lock),
        .axi_wdata         (axi_wdata),
        .ahb_rd_request    (ahb_rd_request),
        .ahb_wr_request    (ahb_wr_request),
        .slv_err_resp      (slv_err_resp),
        .rd_data           (rd_data),
        .axi_address       (axi_address),
        .axi_burst         (axi_burst),
        .axi_length        (axi_length),
        .send_wvalid       (send_wvalid),
        .send_ahb_wr       (send_ahb_wr),
        .axi_wvalid        (axi_wvalid),
        .single_ahb_wr_xfer(single_ahb_wr_xfer),
        .single_ahb_rd_xfer(single_ahb_rd_xfer),
        .send_bresp        (send_bresp),
        .send_rvalid       (send_rvalid),
        .send_rlast        (send_rlast),
        .axi_rready        (axi_rready),
        .timeout_i         (timeout_s),
        .timeout_inprogress(timeout_inprogress)
    );

    ahb_mstr_if #(
        .C_M_AHB_ADDR_WIDTH            (C_M_AHB_ADDR_WIDTH),
        .C_M_AHB_DATA_WIDTH            (C_M_AHB_DATA_WIDTH),
        .C_S_AXI_DATA_WIDTH            (C_S_AXI_DATA_WIDTH),
        .C_S_AXI_SUPPORTS_NARROW_BURST(C_S_AXI_SUPPORTS_NARROW_BURST)
    ) ahb_mstr_if_module (
        .AHB_HCLK          (s_axi_aclk),
        .AHB_HRESETN       (s_axi_aresetn),
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

    time_out #(
        .C_FAMILY        (C_FAMILY),
        .C_DPHASE_TIMEOUT(C_DPHASE_TIMEOUT)
    ) time_out_module (
        .S_AXI_ACLK   (s_axi_aclk),
        .S_AXI_ARESETN(s_axi_aresetn),
        .M_AHB_HREADY (m_ahb_hready),
        .load_cntr    (load_cntr),
        .cntr_enable  (cntr_enable),
        .timeout_o    (timeout_s)
    );

endmodule