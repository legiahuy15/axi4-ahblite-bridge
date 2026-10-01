//=============================================================================
// File        : bridge_tb_top.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Top-level UVM testbench for the AXI4 to AHB-Lite bridge.
//=============================================================================

`timescale 1ns/1ps

module bridge_tb_top #(
    parameter bit          C_S_AXI_SUPPORTS_NARROW_BURST = 1'b0,
    parameter int unsigned C_DPHASE_TIMEOUT              = 0,
    parameter bit          CHECK_BRIDGE_PROFILE          = 1'b1,
    parameter time         CLK_PERIOD                    = 10ns,
    parameter int unsigned RESET_CYCLES                  = 10
);

    //-------------------------------------------------------------------------
    // Imports and parameters
    //-------------------------------------------------------------------------
    import uvm_pkg::*;
    import bridge_vip_pkg::*;
    import bridge_seq_pkg::*;
    import bridge_test_pkg::*;
    `include "uvm_macros.svh"

    //-------------------------------------------------------------------------
    // Clock and reset
    //-------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial begin
        if (CLK_PERIOD == 0)
            `uvm_fatal("BRIDGE_TB_TOP", "CLK_PERIOD must be greater than zero")
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    initial begin
        uvm_event reset_event;

        reset_event = uvm_event_pool::get_global("bridge_reset_req");
        rst_n = 1'b0;
        repeat (RESET_CYCLES) @(posedge clk);
        rst_n = 1'b1;
        `uvm_info("BRIDGE_TB_TOP", "Power-on reset released", UVM_MEDIUM)

        forever begin
            reset_event.wait_trigger();
            `uvm_info("BRIDGE_TB_TOP", "Mid-test reset asserted", UVM_LOW)
            rst_n = 1'b0;
            repeat (RESET_CYCLES) @(posedge clk);
            rst_n = 1'b1;
            `uvm_info("BRIDGE_TB_TOP", "Mid-test reset released", UVM_LOW)
        end
    end

    //-------------------------------------------------------------------------
    // Interface instances
    //-------------------------------------------------------------------------
    axi4_if #(
        .AXI4_ADDR_WIDTH (AXI4_ADDR_WIDTH),
        .AXI4_DATA_WIDTH (AXI4_DATA_WIDTH),
        .AXI4_ID_WIDTH   (AXI4_ID_WIDTH)
    ) axi_intf (
        .clk   (clk),
        .rst_n (rst_n)
    );

    ahb_if #(
        .AHB_ADDR_WIDTH (AHB_ADDR_WIDTH),
        .AHB_DATA_WIDTH (AHB_DATA_WIDTH)
    ) ahb_intf (
        .clk   (clk),
        .rst_n (rst_n)
    );

    //-------------------------------------------------------------------------
    // DUT instance
    //-------------------------------------------------------------------------
    axi_ahblite_bridge #(
        .C_S_AXI_ADDR_WIDTH            (AXI4_ADDR_WIDTH),
        .C_S_AXI_DATA_WIDTH            (AXI4_DATA_WIDTH),
        .C_S_AXI_SUPPORTS_NARROW_BURST (C_S_AXI_SUPPORTS_NARROW_BURST),
        .C_S_AXI_ID_WIDTH              (AXI4_ID_WIDTH),
        .C_M_AHB_ADDR_WIDTH            (AHB_ADDR_WIDTH),
        .C_M_AHB_DATA_WIDTH            (AHB_DATA_WIDTH),
        .C_DPHASE_TIMEOUT              (C_DPHASE_TIMEOUT)
    ) dut (
        .s_axi_aclk       (clk),
        .s_axi_aresetn    (rst_n),

        .s_axi_awid       (axi_intf.AWID),
        .s_axi_awlen      (axi_intf.AWLEN),
        .s_axi_awsize     (axi_intf.AWSIZE),
        .s_axi_awburst    (axi_intf.AWBURST),
        .s_axi_awcache    (axi_intf.AWCACHE),
        .s_axi_awaddr     (axi_intf.AWADDR),
        .s_axi_awprot     (axi_intf.AWPROT),
        .s_axi_awvalid    (axi_intf.AWVALID),
        .s_axi_awready    (axi_intf.AWREADY),
        .s_axi_awlock     (axi_intf.AWLOCK),

        .s_axi_wdata      (axi_intf.WDATA),
        .s_axi_wstrb      (axi_intf.WSTRB),
        .s_axi_wlast      (axi_intf.WLAST),
        .s_axi_wvalid     (axi_intf.WVALID),
        .s_axi_wready     (axi_intf.WREADY),

        .s_axi_bid        (axi_intf.BID),
        .s_axi_bresp      (axi_intf.BRESP),
        .s_axi_bvalid     (axi_intf.BVALID),
        .s_axi_bready     (axi_intf.BREADY),

        .s_axi_arid       (axi_intf.ARID),
        .s_axi_araddr     (axi_intf.ARADDR),
        .s_axi_arprot     (axi_intf.ARPROT),
        .s_axi_arcache    (axi_intf.ARCACHE),
        .s_axi_arvalid    (axi_intf.ARVALID),
        .s_axi_arlen      (axi_intf.ARLEN),
        .s_axi_arsize     (axi_intf.ARSIZE),
        .s_axi_arburst    (axi_intf.ARBURST),
        .s_axi_arlock     (axi_intf.ARLOCK),
        .s_axi_arready    (axi_intf.ARREADY),

        .s_axi_rid        (axi_intf.RID),
        .s_axi_rdata      (axi_intf.RDATA),
        .s_axi_rresp      (axi_intf.RRESP),
        .s_axi_rvalid     (axi_intf.RVALID),
        .s_axi_rlast      (axi_intf.RLAST),
        .s_axi_rready     (axi_intf.RREADY),

        .m_ahb_haddr      (ahb_intf.HADDR),
        .m_ahb_hwrite     (ahb_intf.HWRITE),
        .m_ahb_hsize      (ahb_intf.HSIZE),
        .m_ahb_hburst     (ahb_intf.HBURST),
        .m_ahb_hprot      (ahb_intf.HPROT),
        .m_ahb_htrans     (ahb_intf.HTRANS),
        .m_ahb_hmastlock  (ahb_intf.HMASTLOCK),
        .m_ahb_hwdata     (ahb_intf.HWDATA),
        .m_ahb_hready     (ahb_intf.HREADY),
        .m_ahb_hrdata     (ahb_intf.HRDATA),
        .m_ahb_hresp      (ahb_intf.HRESP)
    );

    //-------------------------------------------------------------------------
    // Protocol assertions
    //-------------------------------------------------------------------------
    axi4_sva #(
        .AXI4_ADDR_WIDTH     (AXI4_ADDR_WIDTH),
        .AXI4_DATA_WIDTH     (AXI4_DATA_WIDTH),
        .AXI4_ID_WIDTH       (AXI4_ID_WIDTH),
        .CHECK_BRIDGE_PROFILE(CHECK_BRIDGE_PROFILE)
    ) axi_checker (
        .clk     (clk),
        .rst_n   (rst_n),
        .AWID    (axi_intf.AWID),
        .AWADDR  (axi_intf.AWADDR),
        .AWLEN   (axi_intf.AWLEN),
        .AWSIZE  (axi_intf.AWSIZE),
        .AWBURST (axi_intf.AWBURST),
        .AWLOCK  (axi_intf.AWLOCK),
        .AWCACHE (axi_intf.AWCACHE),
        .AWPROT  (axi_intf.AWPROT),
        .AWVALID (axi_intf.AWVALID),
        .AWREADY (axi_intf.AWREADY),
        .WDATA   (axi_intf.WDATA),
        .WSTRB   (axi_intf.WSTRB),
        .WLAST   (axi_intf.WLAST),
        .WVALID  (axi_intf.WVALID),
        .WREADY  (axi_intf.WREADY),
        .BID     (axi_intf.BID),
        .BRESP   (axi_intf.BRESP),
        .BVALID  (axi_intf.BVALID),
        .BREADY  (axi_intf.BREADY),
        .ARID    (axi_intf.ARID),
        .ARADDR  (axi_intf.ARADDR),
        .ARLEN   (axi_intf.ARLEN),
        .ARSIZE  (axi_intf.ARSIZE),
        .ARBURST (axi_intf.ARBURST),
        .ARLOCK  (axi_intf.ARLOCK),
        .ARCACHE (axi_intf.ARCACHE),
        .ARPROT  (axi_intf.ARPROT),
        .ARVALID (axi_intf.ARVALID),
        .ARREADY (axi_intf.ARREADY),
        .RID     (axi_intf.RID),
        .RDATA   (axi_intf.RDATA),
        .RRESP   (axi_intf.RRESP),
        .RLAST   (axi_intf.RLAST),
        .RVALID  (axi_intf.RVALID),
        .RREADY  (axi_intf.RREADY)
    );

    ahb_sva #(
        .AHB_ADDR_WIDTH      (AHB_ADDR_WIDTH),
        .AHB_DATA_WIDTH      (AHB_DATA_WIDTH),
        .CHECK_BRIDGE_PROFILE(CHECK_BRIDGE_PROFILE)
    ) ahb_checker (
        .clk       (clk),
        .rst_n     (rst_n),
        .HADDR     (ahb_intf.HADDR),
        .HBURST    (ahb_intf.HBURST),
        .HMASTLOCK (ahb_intf.HMASTLOCK),
        .HPROT     (ahb_intf.HPROT),
        .HSIZE     (ahb_intf.HSIZE),
        .HTRANS    (ahb_intf.HTRANS),
        .HWDATA    (ahb_intf.HWDATA),
        .HWRITE    (ahb_intf.HWRITE),
        .HRDATA    (ahb_intf.HRDATA),
        .HREADY    (ahb_intf.HREADY),
        .HRESP     (ahb_intf.HRESP)
    );

    //-------------------------------------------------------------------------
    // Unsupported-lock policy
    //-------------------------------------------------------------------------
    // "bridge_allow_lock" disables the no-lock assertions for lock tests
    generate
        if (CHECK_BRIDGE_PROFILE) begin : g_lock_policy
            initial begin
                uvm_event allow_lock_event;

                allow_lock_event = uvm_event_pool::get_global("bridge_allow_lock");
                allow_lock_event.wait_on();
                $assertoff(0, axi_checker.g_bridge_profile.LOCK_UNSUPPORTED,
                              axi_checker.g_bridge_profile.ARLOCK_UNSUPPORTED,
                              ahb_checker.g_bridge_profile.NO_LOCK);
                `uvm_info("BRIDGE_TB_TOP",
                          {"Lock-profile assertions disabled: ",
                           "LOCK_UNSUPPORTED, ARLOCK_UNSUPPORTED, NO_LOCK"},
                          UVM_LOW)
            end
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Time-zero driver outputs
    //-------------------------------------------------------------------------
    initial begin
        axi_intf.AWID    = '0;
        axi_intf.AWADDR  = '0;
        axi_intf.AWLEN   = '0;
        axi_intf.AWSIZE  = '0;
        axi_intf.AWBURST = '0;
        axi_intf.AWLOCK  = '0;
        axi_intf.AWCACHE = '0;
        axi_intf.AWPROT  = '0;
        axi_intf.AWVALID = 1'b0;
        axi_intf.WDATA   = '0;
        axi_intf.WSTRB   = '0;
        axi_intf.WLAST   = 1'b0;
        axi_intf.WVALID  = 1'b0;
        axi_intf.BREADY  = 1'b0;
        axi_intf.ARID    = '0;
        axi_intf.ARADDR  = '0;
        axi_intf.ARLEN   = '0;
        axi_intf.ARSIZE  = '0;
        axi_intf.ARBURST = '0;
        axi_intf.ARLOCK  = '0;
        axi_intf.ARCACHE = '0;
        axi_intf.ARPROT  = '0;
        axi_intf.ARVALID = 1'b0;
        axi_intf.RREADY  = 1'b0;

        ahb_intf.HRDATA = '0;
        ahb_intf.HREADY = 1'b1;
        ahb_intf.HRESP  = 1'b0;
    end

    //-------------------------------------------------------------------------
    // UVM configuration and execution
    //-------------------------------------------------------------------------
    initial begin
        uvm_config_db#(axi4_vif_t)::set(null, "uvm_test_top", "axi_vif",
                                        axi_intf);
        uvm_config_db#(ahb_vif_t)::set(null, "uvm_test_top", "ahb_vif",
                                       ahb_intf);
        uvm_config_db#(bit)::set(null, "uvm_test_top",
                                 "supports_narrow_burst",
                                 C_S_AXI_SUPPORTS_NARROW_BURST);
        uvm_config_db#(int unsigned)::set(null, "uvm_test_top",
                                          "dphase_timeout",
                                          C_DPHASE_TIMEOUT);

        run_test();
    end

    //-------------------------------------------------------------------------
    // Waveform dumping
    //-------------------------------------------------------------------------
    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("axi_ahblite_bridge_vip.vcd");
            $dumpvars(0, bridge_tb_top);
        end
    end

    //-------------------------------------------------------------------------
    // Simulation watchdog
    //-------------------------------------------------------------------------
    initial begin
        longint unsigned timeout_ns;

        timeout_ns = 10_000_000;
        void'($value$plusargs("TIMEOUT_NS=%d", timeout_ns));
        #(timeout_ns);
        `uvm_fatal("BRIDGE_TB_TOP",
                   $sformatf("Simulation timeout after %0d ns", timeout_ns))
    end

endmodule : bridge_tb_top