//=============================================================================
// File        : ahb_test_pkg.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Test package for AHB-Lite VIP.
//               Imports ahb_pkg (VIP core) and ahb_seq_pkg (sequence library),
//               and includes all test classes.
//=============================================================================

`ifndef AHB_TEST_PKG_INCLUDED_
`define AHB_TEST_PKG_INCLUDED_

package ahb_test_pkg;

    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import ahb_pkg::*;
    import ahb_seq_pkg::*;

    //-------------------------------------------------------------------------
    // Tests  (src/test/)
    //-------------------------------------------------------------------------
    `include "test/ahb_base_test.sv"
    `include "test/ahb_sanity_test.sv"
    `include "test/ahb_single_transfer_test.sv"
    `include "test/ahb_transfer_size_test.sv"
    `include "test/ahb_byte_lane_test.sv"
    `include "test/ahb_incr_burst_test.sv"
    `include "test/ahb_wrap_burst_test.sv"
    `include "test/ahb_undefined_burst_test.sv"
    `include "test/ahb_error_response_test.sv"
    `include "test/ahb_reset_test.sv"
    `include "test/ahb_busy_test.sv"
    `include "test/ahb_idle_test.sv"
    `include "test/ahb_wait_state_test.sv"
    `include "test/ahb_read_after_write_test.sv"
    `include "test/ahb_back_to_back_test.sv"
    `include "test/ahb_passive_test.sv"
    `include "test/ahb_random_stress_test.sv"

endpackage : ahb_test_pkg

`endif // AHB_TEST_PKG_INCLUDED_
