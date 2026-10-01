//=============================================================================
// File        : axi4_mst_reset_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Synchronous reset sequence. With a read parked on the bus,
//               reset is asserted at several points within a clock cycle:
//               - outputs must not change before the next rising edge
//               - after that edge all outputs must hold their reset values
//               - ordinary traffic must work afterwards
//               Covers BRG_RST_002, BRG_RST_003, BRG_RST_004 and BRG_ATT_005.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_reset_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_reset_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    // AHB wait that parks the bus during reset (default build only)
    localparam int unsigned HOLD_WAIT = 30;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    ahb_response_policy policy;
    ahb_vif_t           ahb_vif;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned early_change_errors;
    int unsigned default_errors;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    // Packed bus state, compared with 4-state !==
    typedef struct packed {
        logic [1:0]                htrans;
        logic [AHB_ADDR_WIDTH-1:0] haddr;
        logic [2:0]                hburst;
        logic [2:0]                hsize;
        logic [3:0]                hprot;
        logic                      hwrite;
        logic                      hmastlock;
        logic                      awready;
        logic                      wready;
        logic                      bvalid;
        logic                      arready;
        logic                      rvalid;
        logic                      rlast;
    } bus_state_t;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected realtime     clk_period;
    protected realtime     epsilon;      // kept clear of both clock edges
    protected int unsigned case_index;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_reset_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (policy == null)
            `uvm_fatal(get_type_name(), "Response policy is null")
        if (ahb_vif == null)
            `uvm_fatal(get_type_name(), "AHB virtual interface is null")

        wait_reset_release();
        validate_knobs();
        measure_clk_period();

        `uvm_info(get_type_name(),
                  $sformatf("Reset timing: clock period measured as %0t",
                            clk_period),
                  UVM_LOW)

        // Reset points within the cycle (never exactly on the edge)
        run_case(epsilon);
        run_case(clk_period / 4);
        run_case(clk_period / 2);
        run_case((clk_period * 3) / 4);
        run_case(clk_period - (2 * epsilon));

        `uvm_info(get_type_name(),
                  $sformatf({"Reset summary: cases=%0d failed=%0d ",
                             "early_change_errors=%0d default_errors=%0d"},
                            cases_run, cases_failed, early_change_errors,
                            default_errors),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Clock period
    //-------------------------------------------------------------------------
    protected task measure_clk_period();
        realtime first_edge;

        @(posedge cfg.vif.clk);
        first_edge = $realtime;
        @(posedge cfg.vif.clk);
        clk_period = $realtime - first_edge;
        if (clk_period <= 0)
            `uvm_fatal(get_type_name(), "Measured a non-positive clock period")
        epsilon = clk_period / 20;
    endtask : measure_clk_period

    //-------------------------------------------------------------------------
    // One reset placed 'offset' after a rising edge
    //-------------------------------------------------------------------------
    protected task run_case(realtime offset);
        bus_state_t before_reset;
        bus_state_t before_edge;
        bit         failed;
        bit         recovery_failed;

        failed = 1'b0;
        cases_run++;

        start_held_read();

        // Just before the next edge nothing may have changed
        @(posedge cfg.vif.clk);
        #(offset);
        before_reset = capture();
        request_reset();

        #(clk_period - offset - epsilon);
        before_edge = capture();
        failed |= check_unchanged(offset, before_reset, before_edge);

        // One edge later: reset values
        @(posedge cfg.vif.clk);
        #(epsilon);
        failed |= check_defaults(offset);

        wait_reset_done();
        run_recovery(recovery_failed);
        failed |= recovery_failed;

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] reset at edge + %0t: checked", case_index,
                            offset),
                  UVM_MEDIUM)
        case_index++;
        if (failed)
            cases_failed++;
    endtask : run_case

    // Parked read; its response is discarded by the reset
    protected task start_held_read();
        axi4_transaction req;

        policy.clear_plan();
        policy.add_beat(AHB_RESP_OKAY, HOLD_WAIT);

        req = create_request(AXI4_READ, base_addr + (case_index * case_stride));
        send_axi_request(req);

        // Wait (bounded) until the bridge drives the bus
        for (int unsigned i = 0; ahb_vif.HTRANS === 2'b00; i++) begin
            if (i > HOLD_WAIT) begin
                `uvm_fatal(get_type_name(),
                           {"The bridge never left HTRANS IDLE, so there is ",
                            "no active state to reset"})
            end
            @(posedge cfg.vif.clk);
        end
    endtask : start_held_read

    protected task request_reset();
        uvm_event reset_event;

        reset_event = uvm_event_pool::get_global("bridge_reset_req");
        reset_event.trigger();
    endtask : request_reset

    protected task wait_reset_done();
        wait (cfg.vif.rst_n === 1'b1);
        policy.clear_plan();
        wait_cycles(8);
    endtask : wait_reset_done

    //-------------------------------------------------------------------------
    // Sampling
    //-------------------------------------------------------------------------
    // Sampled directly (no clocking block) to see values between edges
    protected function bus_state_t capture();
        bus_state_t s;

        s.htrans    = ahb_vif.HTRANS;
        s.haddr     = ahb_vif.HADDR;
        s.hburst    = ahb_vif.HBURST;
        s.hsize     = ahb_vif.HSIZE;
        s.hprot     = ahb_vif.HPROT;
        s.hwrite    = ahb_vif.HWRITE;
        s.hmastlock = ahb_vif.HMASTLOCK;
        s.awready   = cfg.vif.AWREADY;
        s.wready    = cfg.vif.WREADY;
        s.bvalid    = cfg.vif.BVALID;
        s.arready   = cfg.vif.ARREADY;
        s.rvalid    = cfg.vif.RVALID;
        s.rlast     = cfg.vif.RLAST;
        return s;
    endfunction : capture

    //-------------------------------------------------------------------------
    // BRG_RST_002: nothing moves until the next rising edge
    //-------------------------------------------------------------------------
    protected function bit check_unchanged(
        realtime    offset,
        bus_state_t before_reset,
        bus_state_t before_edge
    );
        if (before_reset == before_edge)
            return 1'b0;

        early_change_errors++;
        `uvm_error(get_type_name(),
                   $sformatf({"reset at edge + %0t: the bridge changed state ",
                              "before the next rising edge, so the reset is ",
                              "not synchronous. HTRANS %0h->%0h HADDR ",
                              "0x%0h->0x%0h HBURST %0h->%0h HSIZE %0h->%0h ",
                              "HWRITE %0b->%0b AWREADY %0b->%0b WREADY ",
                              "%0b->%0b BVALID %0b->%0b ARREADY %0b->%0b ",
                              "RVALID %0b->%0b"},
                             offset,
                             before_reset.htrans,  before_edge.htrans,
                             before_reset.haddr,   before_edge.haddr,
                             before_reset.hburst,  before_edge.hburst,
                             before_reset.hsize,   before_edge.hsize,
                             before_reset.hwrite,  before_edge.hwrite,
                             before_reset.awready, before_edge.awready,
                             before_reset.wready,  before_edge.wready,
                             before_reset.bvalid,  before_edge.bvalid,
                             before_reset.arready, before_edge.arready,
                             before_reset.rvalid,  before_edge.rvalid))
        return 1'b1;
    endfunction : check_unchanged

    //-------------------------------------------------------------------------
    // BRG_RST_003, BRG_RST_004, BRG_ATT_005: the reset values themselves
    //-------------------------------------------------------------------------
    protected function bit check_defaults(realtime offset);
        bus_state_t s;
        bit         failed;

        s      = capture();
        failed = 1'b0;

        failed |= expect_value(offset, "HTRANS",    s.htrans,    2'b00);
        failed |= expect_value(offset, "HADDR",     s.haddr,     '0);
        failed |= expect_value(offset, "HBURST",    s.hburst,    3'b000);
        failed |= expect_value(offset, "HSIZE",     s.hsize,     3'b000);
        failed |= expect_value(offset, "HPROT",     s.hprot,     4'b0011);
        failed |= expect_value(offset, "HWRITE",    s.hwrite,    1'b0);
        failed |= expect_value(offset, "HMASTLOCK", s.hmastlock, 1'b0);
        failed |= expect_value(offset, "AWREADY",   s.awready,   1'b0);
        failed |= expect_value(offset, "WREADY",    s.wready,    1'b0);
        failed |= expect_value(offset, "BVALID",    s.bvalid,    1'b0);
        failed |= expect_value(offset, "ARREADY",   s.arready,   1'b0);
        failed |= expect_value(offset, "RVALID",    s.rvalid,    1'b0);
        failed |= expect_value(offset, "RLAST",     s.rlast,     1'b0);
        return failed;
    endfunction : check_defaults

    protected function bit expect_value(
        realtime                   offset,
        string                     name,
        logic [AHB_ADDR_WIDTH-1:0] actual,
        logic [AHB_ADDR_WIDTH-1:0] expected
    );
        if (actual === expected)
            return 1'b0;

        default_errors++;
        `uvm_error(get_type_name(),
                   $sformatf({"reset at edge + %0t: %s is 0x%0h one edge ",
                              "after the reset, expected 0x%0h"},
                             offset, name, actual, expected))
        return 1'b1;
    endfunction : expect_value

    //-------------------------------------------------------------------------
    // Recovery: the bridge must still work after the reset
    //-------------------------------------------------------------------------
    protected function bit check_read(
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp
    );
        bit failed;

        failed = 1'b0;
        if (rsp.data.size() != 1) begin
            `uvm_error(get_type_name(),
                       $sformatf("recovery read at 0x%0h returned %0d beats",
                                 addr, rsp.data.size()))
            return 1'b1;
        end
        if (rsp.rresp[0] != AXI4_RESP_OKAY) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("recovery read at 0x%0h returned %s",
                                 addr, rsp.rresp[0].name()))
        end
        if (rsp.data[0] !== policy.read_data(addr)) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"recovery read at 0x%0h: expected=0x%0h ",
                                  "actual=0x%0h"},
                                 addr, policy.read_data(addr), rsp.data[0]))
        end
        return failed;
    endfunction : check_read

    protected task run_recovery(output bit failed);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          wr_req;
        axi4_transaction          rd_req;
        axi4_transaction          wr_rsp;
        axi4_transaction          rd_rsp;

        failed = 1'b0;
        addr   = base_addr + ((case_index + 64) * case_stride);

        policy.clear_plan();
        policy.add_beat(AHB_RESP_OKAY, 0);
        wr_req = create_request(AXI4_WRITE, addr);
        send_axi_request_wait(wr_req, wr_rsp);
        if (wr_rsp.bresp != AXI4_RESP_OKAY) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("recovery write at 0x%0h returned %s",
                                 addr, wr_rsp.bresp.name()))
        end

        policy.clear_plan();
        policy.add_beat(AHB_RESP_OKAY, 0);
        rd_req = create_request(AXI4_READ, addr);
        send_axi_request_wait(rd_req, rd_rsp);
        failed |= check_read(addr, rd_rsp);
    endtask : run_recovery

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;
        axi4_dir_e       req_dir;

        req_dir = dir;
        req = axi4_transaction::type_id::create(
                  $sformatf("rst_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::req_dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == 0;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed at 0x%0h", addr))

        if (dir == AXI4_WRITE) begin
            for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
                req.data[0][8*k +: 8] = 8'h50 + cases_run + k;
            req.strb[0] = '1;
        end
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        if ((case_stride < AXI4_STRB_WIDTH) ||
            ((case_stride % AXI4_STRB_WIDTH) != 0))
            `uvm_fatal(get_type_name(),
                       "case_stride must be a non-zero multiple of the bus width")
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
    endfunction : validate_knobs

endclass : axi4_mst_reset_seq