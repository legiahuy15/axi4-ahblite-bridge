//=============================================================================
// File        : bridge_vip_pkg.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Core package for the bridge verification environment.
//=============================================================================

`ifndef BRIDGE_VIP_PKG_INCLUDED_
`define BRIDGE_VIP_PKG_INCLUDED_

package bridge_vip_pkg;

    //-------------------------------------------------------------------------
    // Imports and macros
    //-------------------------------------------------------------------------
    `include "uvm_macros.svh"
    import uvm_pkg::*;

    //-------------------------------------------------------------------------
    // Protocol types
    //-------------------------------------------------------------------------
    `include "cfg/axi4_types.sv"
    `include "cfg/ahb_types.sv"

    //-------------------------------------------------------------------------
    // Transactions
    //-------------------------------------------------------------------------
    `include "txn/axi4_transaction.sv"
    `include "txn/ahb_transfer.sv"
    `include "txn/ahb_slave_response.sv"

    //-------------------------------------------------------------------------
    // Configuration objects
    //-------------------------------------------------------------------------
    `include "cfg/axi4_mst_agent_cfg.sv"
    `include "cfg/ahb_slv_agent_cfg.sv"
    `include "cfg/axi4_mst_req_ctx.sv"
    `include "cfg/predictor_req_entry.sv"
    `include "cfg/scoreboard_axi_ctx.sv"
    `include "cfg/vip_env_cfg.sv"

    //-------------------------------------------------------------------------
    // AXI4 master agent
    //-------------------------------------------------------------------------
    `include "axi4_mst/axi4_mst_sequencer.sv"
    `include "axi4_mst/axi4_mst_driver.sv"
    `include "axi4_mst/axi4_mst_monitor.sv"
    `include "axi4_mst/axi4_mst_coverage.sv"
    `include "axi4_mst/axi4_mst_agent.sv"

    //-------------------------------------------------------------------------
    // AHB-Lite slave agent
    //-------------------------------------------------------------------------
    `include "ahb_slv/ahb_slv_sequencer.sv"
    `include "ahb_slv/ahb_slv_driver.sv"
    `include "ahb_slv/ahb_slv_monitor.sv"
    `include "ahb_slv/ahb_slv_coverage.sv"
    `include "ahb_slv/ahb_slv_agent.sv"

    //-------------------------------------------------------------------------
    // Bridge environment
    //-------------------------------------------------------------------------
    `include "env/virtual_sequencer.sv"
    `include "env/predictor.sv"
    `include "env/scoreboard.sv"
    `include "env/e2e_cov.sv"
    `include "env/vip_env.sv"

endpackage : bridge_vip_pkg

`endif // BRIDGE_VIP_PKG_INCLUDED_