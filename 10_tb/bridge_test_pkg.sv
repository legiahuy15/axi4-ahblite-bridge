//=============================================================================
// File        : bridge_test_pkg.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Test package for bridge-level verification.
//=============================================================================

`ifndef BRIDGE_TEST_PKG_INCLUDED_
`define BRIDGE_TEST_PKG_INCLUDED_

package bridge_test_pkg;

    //-------------------------------------------------------------------------
    // Imports and macros
    //-------------------------------------------------------------------------
    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import bridge_vip_pkg::*;
    import bridge_seq_pkg::*;

    //-------------------------------------------------------------------------
    // Tests
    //-------------------------------------------------------------------------
    `include "test/bridge_base_test.sv"
    `include "test/bridge_sanity_test.sv"
    `include "test/bridge_data_integrity_test.sv"
    `include "test/bridge_burst_matrix_test.sv"
    `include "test/bridge_incr_mapping_test.sv"
    `include "test/bridge_fixed_mapping_test.sv"
    `include "test/bridge_wrap_mapping_test.sv"
    `include "test/bridge_1kb_boundary_test.sv"
    `include "test/bridge_unsupported_feature_test.sv"
    `include "test/bridge_size_mapping_test.sv"
    `include "test/bridge_single_wstrb_test.sv"
    `include "test/bridge_unaligned_read_test.sv"
    `include "test/bridge_protection_mapping_test.sv"
    `include "test/bridge_response_mapping_test.sv"

endpackage : bridge_test_pkg

`endif // BRIDGE_TEST_PKG_INCLUDED_