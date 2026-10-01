//=============================================================================
// File        : ahb_skid_buf
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Registered skid buffer on the AXI read-data channel.
//=============================================================================

`timescale 1ns/1ps

module ahb_skid_buf #(
    parameter int C_WDATA_WIDTH    = 32,
    parameter int C_S_AXI_ID_WIDTH = 4,
    parameter int C_TUSER_WIDTH    = 1
) (
    input  logic                            ACLK,
    input  logic                            ARST,
    input  logic                            skid_stop,

    input  logic                            S_VALID,
    output logic                            S_READY,
    input  logic [C_WDATA_WIDTH-1:0]        S_Data,
    input  logic [(C_WDATA_WIDTH/8)-1:0]    S_STRB,
    input  logic                            S_Last,
    input  logic [C_TUSER_WIDTH-1:0]        S_User,
    input  logic [C_S_AXI_ID_WIDTH-1:0]     S_RID,
    input  logic [1:0]                      S_RESP,

    output logic [1:0]                      M_RESP,
    output logic                            M_VALID,
    input  logic                            M_READY,
    output logic [C_S_AXI_ID_WIDTH-1:0]     M_RID,
    output logic [C_WDATA_WIDTH-1:0]        M_Data,
    output logic [(C_WDATA_WIDTH/8)-1:0]    M_STRB,
    output logic                            M_Last,
    output logic [C_TUSER_WIDTH-1:0]        M_User
);

    logic sig_reset_reg;
    logic sig_spcl_s_ready_set;

    logic [C_WDATA_WIDTH-1:0]     sig_data_skid_reg;
    logic [(C_WDATA_WIDTH/8)-1:0] sig_strb_skid_reg;
    logic                          sig_last_skid_reg;
    logic                          sig_skid_reg_en;

    logic [C_WDATA_WIDTH-1:0]     sig_data_skid_mux_out;
    logic [(C_WDATA_WIDTH/8)-1:0] sig_strb_skid_mux_out;
    logic                          sig_last_skid_mux_out;
    logic                          sig_skid_mux_sel;

    logic [C_S_AXI_ID_WIDTH-1:0] sig_rid_skid_reg;
    logic [C_S_AXI_ID_WIDTH-1:0] sig_rid_skid_mux_out;
    logic [1:0]                  sig_resp_reg_out;
    logic [1:0]                  sig_resp_skid_mux_out;
    logic [1:0]                  sig_resp_skid_reg;
    logic [C_S_AXI_ID_WIDTH-1:0] sig_rid_reg_out;
    logic [C_WDATA_WIDTH-1:0]    sig_data_reg_out;
    logic [(C_WDATA_WIDTH/8)-1:0] sig_strb_reg_out;
    logic                         sig_last_reg_out;
    logic                         sig_data_reg_out_en;

    (* keep = "true", equivalent_register_removal = "no" *) logic sig_m_valid_out;
    (* keep = "true", equivalent_register_removal = "no" *) logic sig_m_valid_dup;
    logic sig_m_valid_comb;

    (* keep = "true", equivalent_register_removal = "no" *) logic sig_s_ready_out;
    (* keep = "true", equivalent_register_removal = "no" *) logic sig_s_ready_dup;
    logic sig_s_ready_comb;

    logic sig_stop_request;
    logic sig_sready_stop;
    logic sig_sready_stop_reg;
    logic sig_s_last_xfered;
    logic sig_m_last_xfered;
    logic sig_mvalid_stop_reg;
    logic sig_mvalid_stop;

    logic sig_slast_with_stop;
    logic [(C_WDATA_WIDTH/8)-1:0] sig_sstrb_stop_mask;
    logic [(C_WDATA_WIDTH/8)-1:0] sig_sstrb_with_stop;

    logic [C_TUSER_WIDTH-1:0] sig_user_skid_mux_out;
    logic [C_TUSER_WIDTH-1:0] sig_user_skid_reg;
    logic [C_TUSER_WIDTH-1:0] sig_user_reg_out;

    assign M_VALID = sig_m_valid_out;
    assign S_READY = sig_s_ready_out;
    assign M_STRB  = sig_strb_reg_out;
    assign M_Last  = sig_last_reg_out;
    assign M_Data  = sig_data_reg_out;
    assign M_RID   = sig_rid_reg_out;
    assign M_RESP  = sig_resp_reg_out;
    assign M_User  = sig_user_reg_out;

    assign sig_slast_with_stop  = S_Last | sig_stop_request;
    assign sig_sstrb_with_stop  = S_STRB | sig_sstrb_stop_mask;
    assign sig_spcl_s_ready_set = sig_reset_reg;

    assign sig_data_reg_out_en = M_READY | ~sig_m_valid_dup;
    assign sig_skid_reg_en     = sig_s_ready_dup;
    assign sig_skid_mux_sel    = ~sig_s_ready_dup;

    assign sig_data_skid_mux_out = sig_skid_mux_sel ? sig_data_skid_reg : S_Data;
    assign sig_rid_skid_mux_out  = sig_skid_mux_sel ? sig_rid_skid_reg  : S_RID;
    assign sig_resp_skid_mux_out = sig_skid_mux_sel ? sig_resp_skid_reg : S_RESP;
    assign sig_user_skid_mux_out = sig_skid_mux_sel ? sig_user_skid_reg : S_User;
    assign sig_strb_skid_mux_out = sig_skid_mux_sel ? sig_strb_skid_reg : sig_sstrb_with_stop;
    assign sig_last_skid_mux_out = sig_skid_mux_sel ? sig_last_skid_reg : sig_slast_with_stop;

    assign sig_m_valid_comb = S_VALID |
                              (sig_m_valid_dup & (~sig_s_ready_dup | ~M_READY));

    assign sig_s_ready_comb = M_READY |
                              (sig_s_ready_dup & (~sig_m_valid_dup | ~S_VALID));

    always_ff @(posedge ACLK) begin
        sig_reset_reg <= ARST;
    end

    always_ff @(posedge ACLK) begin
        if (ARST || sig_sready_stop) begin
            sig_s_ready_out <= 1'b0;
            sig_s_ready_dup <= 1'b0;
        end else if (sig_spcl_s_ready_set) begin
            sig_s_ready_out <= 1'b1;
            sig_s_ready_dup <= 1'b1;
        end else begin
            sig_s_ready_out <= sig_s_ready_comb;
            sig_s_ready_dup <= sig_s_ready_comb;
        end
    end

    always_ff @(posedge ACLK) begin
        if (ARST || sig_spcl_s_ready_set || sig_mvalid_stop) begin
            sig_m_valid_out <= 1'b0;
            sig_m_valid_dup <= 1'b0;
        end else begin
            sig_m_valid_out <= sig_m_valid_comb;
            sig_m_valid_dup <= sig_m_valid_comb;
        end
    end

    always_ff @(posedge ACLK) begin
        if (ARST) begin
            sig_data_skid_reg <= '0;
            sig_rid_skid_reg  <= '0;
            sig_resp_skid_reg <= '0;
            sig_strb_skid_reg <= '0;
            sig_last_skid_reg <= 1'b0;
            sig_user_skid_reg <= '0;
        end else if (sig_skid_reg_en) begin
            sig_data_skid_reg <= S_Data;
            sig_rid_skid_reg  <= S_RID;
            sig_resp_skid_reg <= S_RESP;
            sig_strb_skid_reg <= sig_sstrb_with_stop;
            sig_last_skid_reg <= sig_slast_with_stop;
            sig_user_skid_reg <= S_User;
        end
    end

    always_ff @(posedge ACLK) begin
        if (ARST || sig_mvalid_stop_reg) begin
            sig_data_reg_out <= '0;
            sig_rid_reg_out  <= '0;
            sig_resp_reg_out <= '0;
            sig_strb_reg_out <= '0;
            sig_last_reg_out <= 1'b0;
            sig_user_reg_out <= '0;
        end else if (sig_data_reg_out_en) begin
            sig_data_reg_out <= sig_data_skid_mux_out;
            sig_rid_reg_out  <= sig_rid_skid_mux_out;
            sig_resp_reg_out <= sig_resp_skid_mux_out;
            sig_strb_reg_out <= sig_strb_skid_mux_out;
            sig_last_reg_out <= sig_last_skid_mux_out;
            sig_user_reg_out <= sig_user_skid_mux_out;
        end
    end

    assign sig_s_last_xfered = sig_s_ready_dup & S_VALID & sig_slast_with_stop;
    assign sig_sready_stop   = (sig_s_last_xfered & sig_stop_request) |
                               sig_sready_stop_reg;

    assign sig_m_last_xfered = sig_m_valid_dup & M_READY & sig_last_reg_out;
    assign sig_mvalid_stop   = (sig_m_last_xfered & sig_stop_request) |
                               sig_mvalid_stop_reg;

    // skid_stop is latched until reset. The final buffered beat is forced to LAST.
    always_ff @(posedge ACLK) begin
        if (ARST) begin
            sig_stop_request   <= 1'b0;
            sig_sstrb_stop_mask <= '0;
        end else if (skid_stop) begin
            sig_stop_request   <= 1'b1;
            sig_sstrb_stop_mask <= '1;
        end
    end

    always_ff @(posedge ACLK) begin
        if (ARST)
            sig_sready_stop_reg <= 1'b0;
        else if (sig_s_last_xfered && sig_stop_request)
            sig_sready_stop_reg <= 1'b1;
    end

    always_ff @(posedge ACLK) begin
        if (ARST)
            sig_mvalid_stop_reg <= 1'b0;
        else if (sig_m_last_xfered && sig_stop_request)
            sig_mvalid_stop_reg <= 1'b1;
    end

endmodule