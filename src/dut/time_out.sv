//=============================================================================
// File        : time_out
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Watchdog for an AHB transfer whose data phase does not
//               complete within the configured timeout interval.
//=============================================================================

`timescale 1ns/1ps

module time_out #(
    parameter string C_FAMILY         = "virtex7",
    parameter int    C_DPHASE_TIMEOUT = 0
) (
    input  logic S_AXI_ACLK,
    input  logic S_AXI_ARESETN,
    input  logic M_AHB_HREADY,
    input  logic load_cntr,
    input  logic cntr_enable,
    output logic timeout_o
);

    generate
        if (C_DPHASE_TIMEOUT != 0) begin : gen_wdt
            localparam int COUNTER_WIDTH = (C_DPHASE_TIMEOUT <= 1) ? 1 : $clog2(C_DPHASE_TIMEOUT);
            localparam logic [COUNTER_WIDTH-1:0] DPTO_LD_VALUE = C_DPHASE_TIMEOUT - 1;

            logic timeout_i;
            logic cntr_rst;

            assign cntr_rst = ~S_AXI_ARESETN | timeout_i;

            counter_f #(
                .C_NUM_BITS(COUNTER_WIDTH),
                .C_FAMILY  (C_FAMILY)
            ) i_to_counter (
                .Clk          (S_AXI_ACLK),
                .Rst          (cntr_rst),
                .Load_In      (DPTO_LD_VALUE),
                .Count_Enable (cntr_enable),
                .Count_Load   (load_cntr),
                .Count_Down   (1'b1),
                .Count_Out    (),
                .Carry_Out    (timeout_i)
            );

            always_ff @(posedge S_AXI_ACLK) begin
                if (!S_AXI_ARESETN)
                    timeout_o <= 1'b0;
                else
                    timeout_o <= timeout_i & ~M_AHB_HREADY;
            end
        end else begin : gen_no_wdt
            always_comb timeout_o = 1'b0;
        end
    endgenerate

endmodule
