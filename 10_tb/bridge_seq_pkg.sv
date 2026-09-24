//=============================================================================
// File        : bridge_seq_pkg.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Sequence package for bridge verification scenarios.
//=============================================================================

`ifndef BRIDGE_SEQ_PKG_INCLUDED_
`define BRIDGE_SEQ_PKG_INCLUDED_

package bridge_seq_pkg;

    //-------------------------------------------------------------------------
    // Imports and macros
    //-------------------------------------------------------------------------
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import bridge_vip_pkg::*;

    //-------------------------------------------------------------------------
    // AXI4 master sequences
    //-------------------------------------------------------------------------
    `include "seq/axi4_mst_seq/axi4_mst_base_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_sanity_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_data_integrity_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_burst_matrix_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_incr_mapping_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_fixed_mapping_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_wrap_mapping_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_1kb_boundary_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_lock_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_size_mapping_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_single_wstrb_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_unaligned_read_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_protection_mapping_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_response_mapping_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_backpressure_seq.sv"
    `include "seq/axi4_mst_seq/axi4_mst_timeout_seq.sv"

    //-------------------------------------------------------------------------
    // AHB-Lite slave sequences
    //-------------------------------------------------------------------------
    `include "seq/ahb_slv_seq/ahb_slv_base_seq.sv"
    `include "seq/ahb_slv_seq/ahb_slv_response_mapping_seq.sv"

    //-------------------------------------------------------------------------
    // Bridge virtual sequences
    //-------------------------------------------------------------------------
    `include "seq/bridge_vip_seq/bridge_base_seq.sv"
    `include "seq/bridge_vip_seq/bridge_sanity_seq.sv"
    `include "seq/bridge_vip_seq/bridge_data_integrity_seq.sv"
    `include "seq/bridge_vip_seq/bridge_burst_matrix_seq.sv"
    `include "seq/bridge_vip_seq/bridge_incr_mapping_seq.sv"
    `include "seq/bridge_vip_seq/bridge_fixed_mapping_seq.sv"
    `include "seq/bridge_vip_seq/bridge_wrap_mapping_seq.sv"
    `include "seq/bridge_vip_seq/bridge_1kb_boundary_seq.sv"
    `include "seq/bridge_vip_seq/bridge_unsupported_feature_seq.sv"
    `include "seq/bridge_vip_seq/bridge_size_mapping_seq.sv"
    `include "seq/bridge_vip_seq/bridge_single_wstrb_seq.sv"
    `include "seq/bridge_vip_seq/bridge_unaligned_read_seq.sv"
    `include "seq/bridge_vip_seq/bridge_protection_mapping_seq.sv"
    `include "seq/bridge_vip_seq/bridge_response_mapping_seq.sv"
    `include "seq/bridge_vip_seq/bridge_backpressure_seq.sv"
    `include "seq/bridge_vip_seq/bridge_timeout_seq.sv"

endpackage : bridge_seq_pkg

`endif // BRIDGE_SEQ_PKG_INCLUDED_