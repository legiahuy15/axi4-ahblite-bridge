//=============================================================================
// File        : ahb_pkg.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Top-level package for the AHB-Lite VIP. Imports UVM and
//               includes all VIP components.
//=============================================================================

`ifndef AHB_PKG_INCLUDED_
`define AHB_PKG_INCLUDED_

package ahb_pkg;

    //-------------------------------------------------------------------------
    // Imports & Macros
    //-------------------------------------------------------------------------
    `include "uvm_macros.svh"
    import uvm_pkg::*;

    //-------------------------------------------------------------------------
    // Core Types & Transaction Objects  (src/cfg/)
    //-------------------------------------------------------------------------
    `include "cfg/ahb_types.sv"
    `include "cfg/ahb_transaction.sv"
    `include "cfg/ahb_agent_config.sv"
    `include "cfg/ahb_vip_env_config.sv"

    //-------------------------------------------------------------------------
    // Master-side Components  (src/mst/)
    //-------------------------------------------------------------------------
    `include "mst/ahb_master_sequencer.sv"
    `include "mst/ahb_master_driver.sv"
    `include "mst/ahb_master_monitor.sv"
    `include "mst/ahb_master_agent.sv"

    //-------------------------------------------------------------------------
    // Slave-side Components  (src/slv/)
    //-------------------------------------------------------------------------
    `include "slv/ahb_slave_response.sv"
    `include "slv/ahb_slave_sequencer.sv"
    `include "slv/ahb_slave_driver.sv"
    `include "slv/ahb_slave_monitor.sv"
    `include "slv/ahb_slave_agent.sv"

    //-------------------------------------------------------------------------
    // Environment-level Components  (src/env/)
    //-------------------------------------------------------------------------
    `include "env/ahb_coverage.sv"
    `include "env/ahb_scoreboard.sv"
    `include "env/ahb_vip_env.sv"

endpackage : ahb_pkg

`endif // AHB_PKG_INCLUDED_