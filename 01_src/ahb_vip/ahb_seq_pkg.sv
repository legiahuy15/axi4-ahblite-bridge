//=============================================================================
// File        : ahb_seq_pkg.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Sequence library package for the AHB-Lite VIP. Imports
//               ahb_pkg (transaction, types, sequencers) and includes all
//               master-side and slave-side sequences.
//=============================================================================

`ifndef AHB_SEQ_PKG_INCLUDED_
`define AHB_SEQ_PKG_INCLUDED_

package ahb_seq_pkg;

    //-------------------------------------------------------------------------
    // Imports & Macros
    //-------------------------------------------------------------------------
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import ahb_pkg::*;

    //-------------------------------------------------------------------------
    // Master-sequence Library  (src/mst_seq/)
    //-------------------------------------------------------------------------
    `include "mst_seq/ahb_base_seq.sv"
    `include "mst_seq/ahb_sanity_seq.sv"
    `include "mst_seq/ahb_single_seq.sv"
    `include "mst_seq/ahb_size_seq.sv"
    `include "mst_seq/ahb_byte_lane_seq.sv"
    `include "mst_seq/ahb_incr_burst_seq.sv"
    `include "mst_seq/ahb_wrap_burst_seq.sv"
    `include "mst_seq/ahb_undefined_burst_seq.sv"
    `include "mst_seq/ahb_error_seq.sv"
    `include "mst_seq/ahb_reset_seq.sv"
    `include "mst_seq/ahb_busy_seq.sv"
    `include "mst_seq/ahb_idle_seq.sv"
    `include "mst_seq/ahb_wait_state_seq.sv"
    `include "mst_seq/ahb_read_after_write_seq.sv"
    `include "mst_seq/ahb_back_to_back_seq.sv"
    `include "mst_seq/ahb_passive_seq.sv"
    `include "mst_seq/ahb_random_stress_seq.sv"

    //-------------------------------------------------------------------------
    // Slave-sequence Library  (src/slv_seq/)
    //   Used only when the slave agent runs in sequence mode
    //   (ahb_agent_config.auto_gen_resp = 0)
    //-------------------------------------------------------------------------
    `include "slv_seq/ahb_slave_error_seq.sv"

endpackage : ahb_seq_pkg

`endif // AHB_SEQ_PKG_INCLUDED_
