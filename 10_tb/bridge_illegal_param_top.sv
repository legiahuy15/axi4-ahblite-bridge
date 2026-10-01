//=============================================================================
// File        : bridge_illegal_param_top.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Harness for the negative parameter cases of BRG_CFG_003.
//               The bridge is instantiated on its own, with no ports
//               connected and no stimulus, so the only thing the build can
//               be judged on is whether the configuration guards in
//               axi_ahblite_bridge stop it. Each case is its own
//               compilation: the parameter under test comes from a define
//               and everything else keeps a legal default, so a case that
//               fails can only have failed for the one reason it names.
//               Driven by 'make illegal_param_check', which requires every
//               case to fail. A case that elaborates and runs to completion
//               is the finding: it means the bridge accepts a configuration
//               PG177 does not support, and would then misbehave quietly.
//               Not part of the regression, because a target whose cases
//               are all meant to fail cannot share a pass criterion with
//               one whose cases are all meant to pass.
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

    // Nothing to drive. If the guards let this configuration through, the
    // simulation simply ends, and that silence is what the check reports.
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
