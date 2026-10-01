//=============================================================================
// File        : counter_f
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Loadable up/down counter for the timeout watchdog.
//=============================================================================

`timescale 1ns/1ps

module counter_f #(
    parameter int    C_NUM_BITS = 9,
    parameter string C_FAMILY   = "nofamily"
) (
    input  logic                  Clk,
    input  logic                  Rst,
    input  logic [C_NUM_BITS-1:0] Load_In,
    input  logic                  Count_Enable,
    input  logic                  Count_Load,
    input  logic                  Count_Down,
    output logic [C_NUM_BITS-1:0] Count_Out,
    output logic                  Carry_Out
);

    logic [C_NUM_BITS:0] icount_out;
    logic [C_NUM_BITS:0] icount_out_x;
    logic [C_NUM_BITS:0] load_in_x;

    always_comb begin
        load_in_x   = {1'b0, Load_In};
        // The carry bit is intentionally discarded before the next count.
        icount_out_x = {1'b0, icount_out[C_NUM_BITS-1:0]};
    end

    always_ff @(posedge Clk) begin
        if (Rst) begin
            icount_out <= '0;
        end else if (Count_Load) begin
            icount_out <= load_in_x;
        end else if (Count_Down && Count_Enable) begin
            icount_out <= icount_out_x - 1'b1;
        end else if (Count_Enable) begin
            icount_out <= icount_out_x + 1'b1;
        end
    end

    assign Carry_Out = icount_out[C_NUM_BITS];
    assign Count_Out = icount_out[C_NUM_BITS-1:0];

endmodule