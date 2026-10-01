//=============================================================================
// File        : bridge_illegal_param_top.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Stand-alone bridge instance for the illegal-parameter cases
//               (BRG_CFG_003). One parameter per case is set by a define;
//               'make illegal_param_check' requires every case to fail.
//=============================================================================

`ifndef GUARD_AXI_ADDR_WIDTH
    `define GUARD_AXI_ADDR_WIDTH 32
`endif
`ifndef GUARD_AXI_DATA_WIDTH
    `define GUARD_AXI_DATA_WIDTH 32
`endif
`ifndef GUARD_AXI_ID_WIDTH
    `define GUARD_AXI_ID_WIDTH 4
`endif
`ifndef GUARD_AHB_ADDR_WIDTH
    `define GUARD_AHB_ADDR_WIDTH 32
`endif
`ifndef GUARD_AHB_DATA_WIDTH
    `define GUARD_AHB_DATA_WIDTH 32
`endif
`ifndef GUARD_NARROW_BURST
    `define GUARD_NARROW_BURST 0
`endif
`ifndef GUARD_DPHASE_TIMEOUT
    `define GUARD_DPHASE_TIMEOUT 0
`endif

`timescale 1ns/1ps

module bridge_illegal_param_top;

    axi_ahblite_bridge #(
        .C_S_AXI_ADDR_WIDTH            (`GUARD_AXI_ADDR_WIDTH),
        .C_S_AXI_DATA_WIDTH            (`GUARD_AXI_DATA_WIDTH),
        .C_S_AXI_SUPPORTS_NARROW_BURST (`GUARD_NARROW_BURST),
        .C_S_AXI_ID_WIDTH              (`GUARD_AXI_ID_WIDTH),
        .C_M_AHB_ADDR_WIDTH            (`GUARD_AHB_ADDR_WIDTH),
        .C_M_AHB_DATA_WIDTH            (`GUARD_AHB_DATA_WIDTH),
        .C_DPHASE_TIMEOUT              (`GUARD_DPHASE_TIMEOUT)
    ) dut ();

    // No stimulus: an accepted configuration simply ends the run
    initial begin
        #1;
        $display("[GUARD] elaborated and ran with AXI %0dx%0d, AHB %0dx%0d, id=%0d, narrow=%0d, timeout=%0d",
                 `GUARD_AXI_ADDR_WIDTH, `GUARD_AXI_DATA_WIDTH,
                 `GUARD_AHB_ADDR_WIDTH, `GUARD_AHB_DATA_WIDTH,
                 `GUARD_AXI_ID_WIDTH, `GUARD_NARROW_BURST,
                 `GUARD_DPHASE_TIMEOUT);
        $finish;
    end

endmodule : bridge_illegal_param_top
