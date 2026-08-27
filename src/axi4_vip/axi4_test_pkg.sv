//==============================================================================
// File        : axi4_test_pkg.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test package for AXI4 VIP.
//               Imports axi4_pkg (VIP core) and includes all test classes.
//==============================================================================

`ifndef AXI4_TEST_PKG_INCLUDED_
`define AXI4_TEST_PKG_INCLUDED_

package axi4_test_pkg;

    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import axi4_pkg::*;

    // =========================================================================
    // Tests  (src/test/)
    // =========================================================================
    `include "test/axi4_base_test.sv"
    `include "test/axi4_sanity_test.sv"
    `include "test/axi4_random_test.sv"
    `include "test/axi4_outstanding_test.sv"
    `include "test/axi4_out_of_order_test.sv"
    `include "test/axi4_exclusive_test.sv"
    `include "test/axi4_illegal_exclusive_test.sv"
    `include "test/axi4_exclusive_fail_test.sv"
    `include "test/axi4_reset_mid_burst_test.sv"
    `include "test/axi4_unaligned_test.sv"
    `include "test/axi4_cache_prot_test.sv"
    `include "test/axi4_strobe_test.sv"
    `include "test/axi4_burst_sweep_test.sv"
    `include "test/axi4_wr_order_demo_test.sv"
    `include "test/axi4_wlast_before_aw_test.sv"
    `include "test/axi4_narrow_burst_test.sv"
    `include "test/axi4_error_response_test.sv"
    `include "test/axi4_all_burst_type_test.sv"
    `include "test/axi4_back_to_back_test.sv"
    `include "test/axi4_data_integrity_test.sv"
    `include "test/axi4_addr_integrity_test.sv"
    `include "test/axi4_backpressure_test.sv"

    // Demo tests - minimal, deterministic traffic for waveform capture
    `include "test/axi4_exclusive_demo_test.sv"
    `include "test/axi4_ooo_demo_test.sv"

endpackage : axi4_test_pkg

`endif // AXI4_TEST_PKG_INCLUDED_