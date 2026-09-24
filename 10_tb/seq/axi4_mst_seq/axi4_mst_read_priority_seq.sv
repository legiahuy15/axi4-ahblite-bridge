//=============================================================================
// File        : axi4_mst_read_priority_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Simultaneous read/write arbitration sequence.
//               PG177: when a read and a write request arrive together the
//               bridge serves the read first. The reference design implements
//               it in axi_slv_if: the write FSM leaves AXI_WR_IDLE only on
//               (!write_pending && !ARVALID) || write_pending, so a read that
//               is already asking blocks the write from starting, while
//               write_pending latches when a read completes with a write
//               waiting and then blocks the read FSM in turn. The second half
//               is what stops a stream of reads starving the write.
//               Both halves are checked here:
//               - the first AHB transfer of every contended pair is the read
//               - the write that lost then runs, so each pair produces the
//                 AHB order read, write
//               Contention is not assumed either. An observer on the AXI
//               interface counts the cycles where AWVALID and ARVALID are both
//               asserted with neither accepted, so a case whose two requests
//               did not actually collide fails instead of passing on a
//               technicality.
//               The pairs vary the write channel order (parallel, AW first,
//               W first), the burst shapes and the AHB wait, because the
//               arrival shape of the write is what the arbiter looks at.
//               Covers BRG_ARB_001 and BRG_ARB_002.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_read_priority_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_read_priority_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    // Repeated collisions, to show the order is not a one-off
    localparam int unsigned STRESS_PAIRS = 8;

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
    int unsigned pairs_run;
    int unsigned pairs_failed;
    int unsigned read_first_count;
    int unsigned contended_pairs;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_wr_order_e wr_order;
        int unsigned    wr_len;
        int unsigned    rd_len;
        int unsigned    ahb_wait;
        string          label;
    } arb_case_t;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected arb_case_t   case_list[$];

    // Filled by the observers, cleared before each pair
    protected int unsigned contention_cycles;
    protected ahb_dir_e    ahb_order[$];   // direction of each AHB transfer
    protected bit          collect_ahb;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_read_priority_seq");
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
        if (!cfg.return_responses)
            `uvm_fatal(get_type_name(),
                       "Arbitration pairs need return_responses")
        if ((cfg.max_outstanding != 0) && (cfg.max_outstanding < 2))
            `uvm_fatal(get_type_name(),
                       {"A read and a write must be outstanding together; ",
                        "set max_outstanding to 0 or at least 2"})

        wait_reset_release();
        validate_knobs();
        build_cases();

        `uvm_info(get_type_name(),
                  $sformatf("Read priority: %0d contended pairs",
                            case_list.size()),
                  UVM_LOW)

        fork
            begin
                fork
                    observe_ahb();
                    run_all_pairs();
                join_any
                disable fork;
            end
        join

        `uvm_info(get_type_name(),
                  $sformatf({"Read priority summary: pairs=%0d failed=%0d ",
                             "read_first=%0d contended=%0d ahb_beats=%0d"},
                            pairs_run, pairs_failed, read_first_count,
                            contended_pairs, policy.beats_served),
                  UVM_LOW)
    endtask : body

    protected task run_all_pairs();
        foreach (case_list[i])
            run_pair(i, case_list[i]);
    endtask : run_all_pairs

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void add_case(
        axi4_wr_order_e wr_order,
        int unsigned    wr_len,
        int unsigned    rd_len,
        int unsigned    ahb_wait,
        string          label
    );
        arb_case_t c;

        c.wr_order = wr_order;
        c.wr_len   = wr_len;
        c.rd_len   = rd_len;
        c.ahb_wait = ahb_wait;
        c.label    = label;
        case_list.push_back(c);
    endfunction : add_case

    protected function void build_cases();
        // Shapes: the arbiter looks at the request, not at its length
        add_case(AXI4_WR_PARALLEL,     0, 0, 0, "PAR_SINGLE_SINGLE");
        add_case(AXI4_WR_PARALLEL,     3, 3, 0, "PAR_INCR4_INCR4");
        add_case(AXI4_WR_PARALLEL,     0, 3, 0, "PAR_SINGLE_INCR4");
        add_case(AXI4_WR_PARALLEL,     3, 0, 0, "PAR_INCR4_SINGLE");

        // Write channel order. AXI4_WR_AW_BEFORE_W is deliberately absent: on
        // this DUT axi_slv_if asserts AWREADY and WREADY together in
        // AXI_WVALIDS_WAIT, gated on AWVALID && WVALID, so a master that holds
        // WVALID back until the AW handshake deadlocks. W before AW is the
        // only skew the bridge accepts, and it is the interesting one anyway:
        // the write asks through WVALID while its address is still missing.
        add_case(AXI4_WR_W_BEFORE_AW,  0, 0, 0, "WFIRST_SINGLE");
        add_case(AXI4_WR_W_BEFORE_AW,  3, 3, 0, "WFIRST_INCR4");
        add_case(AXI4_WR_W_BEFORE_AW,  3, 0, 0, "WFIRST_INCR4_SINGLE");

        // With AHB wait states, so the losing write starts from a bus that is
        // still busy with the read
        add_case(AXI4_WR_PARALLEL,     3, 3, 1, "PAR_INCR4_WAIT1");
        add_case(AXI4_WR_PARALLEL,     3, 3, 4, "PAR_INCR4_WAIT4");

        // BRG_ARB_002: the same collision over and over
        for (int unsigned i = 0; i < STRESS_PAIRS; i++)
            add_case(AXI4_WR_PARALLEL, 0, 0, 0,
                     $sformatf("REPEAT%0d", i));
    endfunction : build_cases

    //-------------------------------------------------------------------------
    // Observers
    //-------------------------------------------------------------------------
    // Direction of every AHB transfer the bridge starts, in order
    protected task observe_ahb();
        ahb_trans_e htrans;

        forever begin
            @(ahb_vif.monitor_cb);
            if (ahb_vif.rst_n !== 1'b1)
                continue;
            if (!collect_ahb)
                continue;

            htrans = ahb_trans_e'(ahb_vif.monitor_cb.HTRANS);
            if ((ahb_vif.monitor_cb.HREADY === 1'b1) &&
                (htrans == AHB_TRANS_NONSEQ))
                ahb_order.push_back(ahb_dir_e'(ahb_vif.monitor_cb.HWRITE));
        end
    endtask : observe_ahb

    // Cycles where both requests are asking and neither has been taken. A
    // write asks through AWVALID or WVALID, which is also what the arbiter in
    // axi_slv_if looks at, so a W-before-AW pair counts from its first beat
    // rather than only once its address turns up.
    protected task observe_contention();
        forever begin
            @(cfg.vif.monitor_cb);
            if (((cfg.vif.monitor_cb.AWVALID === 1'b1) ||
                 (cfg.vif.monitor_cb.WVALID  === 1'b1)) &&
                (cfg.vif.monitor_cb.ARVALID === 1'b1) &&
                (cfg.vif.monitor_cb.AWREADY !== 1'b1) &&
                (cfg.vif.monitor_cb.ARREADY !== 1'b1))
                contention_cycles++;
        end
    endtask : observe_contention

    //-------------------------------------------------------------------------
    // Run one contended pair
    //-------------------------------------------------------------------------
    protected task run_pair(int unsigned index, arb_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] wr_addr;
        bit [AXI4_ADDR_WIDTH-1:0] rd_addr;
        axi4_transaction          wr_req;
        axi4_transaction          rd_req;
        axi4_transaction          wr_rsp;
        axi4_transaction          rd_rsp;
        int unsigned              beats;
        bit                       failed;

        wr_addr = base_addr + (index * case_stride);
        rd_addr = wr_addr + (case_stride / 2);

        // One plan entry per AHB beat of both requests
        beats = (c.wr_len + 1) + (c.rd_len + 1);
        policy.clear_plan();
        for (int unsigned i = 0; i < beats; i++)
            policy.add_beat(AHB_RESP_OKAY, c.ahb_wait);

        wr_req = create_request(AXI4_WRITE, c.wr_len, wr_addr, c.wr_order);
        rd_req = create_request(AXI4_READ,  c.rd_len, rd_addr,
                                AXI4_WR_PARALLEL);

        contention_cycles = 0;
        ahb_order.delete();
        collect_ahb = 1'b1;

        // Both handed over in the same time step, so the driver puts AWVALID
        // and ARVALID up on the same clock edge
        fork
            begin
                observe_contention();
            end
            begin
                send_axi_request(wr_req);
                send_axi_request(rd_req);
                get_response(rd_rsp, rd_req.get_transaction_id());
                get_response(wr_rsp, wr_req.get_transaction_id());
            end
        join_any
        disable fork;

        collect_ahb = 1'b0;
        pairs_run++;

        failed = check_pair(c, wr_addr, rd_addr, wr_rsp, rd_rsp);
        if (policy.pending_beats() != 0) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s: %0d AHB beats were never issued",
                                 c.label, policy.pending_beats()))
            policy.clear_plan();
        end

        if (failed)
            pairs_failed++;
    endtask : run_pair

    //-------------------------------------------------------------------------
    // Checks
    //-------------------------------------------------------------------------
    protected function bit check_pair(
        arb_case_t                c,
        bit [AXI4_ADDR_WIDTH-1:0] wr_addr,
        bit [AXI4_ADDR_WIDTH-1:0] rd_addr,
        axi4_transaction          wr_rsp,
        axi4_transaction          rd_rsp
    );
        bit failed;

        failed = 1'b0;

        // The pair must really have collided, otherwise the order below says
        // nothing about arbitration
        if (contention_cycles == 0) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: AWVALID and ARVALID were never up ",
                                  "together, so this pair did not contend"},
                                 c.label))
        end else begin
            contended_pairs++;
        end

        // BRG_ARB_001: the read is served first
        if (ahb_order.size() == 0) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s: no AHB transfer was observed", c.label))
        end else if (ahb_order[0] != AHB_READ) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: the first AHB transfer is a write; a ",
                                  "read arriving at the same time must be ",
                                  "served first"},
                                 c.label))
        end else begin
            read_first_count++;
        end

        // BRG_ARB_002: the write that lost must then run, not be starved
        failed |= check_write_follows(c);

        if (wr_rsp.bresp != AXI4_RESP_OKAY) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s: write at 0x%0h returned %s",
                                 c.label, wr_addr, wr_rsp.bresp.name()))
        end
        failed |= check_read_data(c, rd_addr, rd_rsp);
        return failed;
    endfunction : check_pair

    // The read transfer is served to completion and the write follows once
    // write_pending releases it, so the two are never interleaved on AHB.
    // One entry per NONSEQ, which for the INCR bursts used here is one per
    // request.
    protected function bit check_write_follows(arb_case_t c);
        int unsigned reads;
        int unsigned writes;
        bit          seen_write;
        bit          failed;

        reads      = 0;
        writes     = 0;
        seen_write = 1'b0;
        failed     = 1'b0;
        foreach (ahb_order[i]) begin
            if (ahb_order[i] == AHB_WRITE) begin
                seen_write = 1'b1;
                writes++;
            end else begin
                reads++;
                if (seen_write) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf({"%s: an AHB read transfer follows a ",
                                          "write one; the two requests were ",
                                          "interleaved"},
                                         c.label))
                end
            end
        end

        if (writes == 0) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: the write never reached AHB after ",
                                  "losing arbitration"},
                                 c.label))
        end
        return failed;
    endfunction : check_write_follows

    protected function bit check_read_data(
        arb_case_t                c,
        bit [AXI4_ADDR_WIDTH-1:0] rd_addr,
        axi4_transaction          rd_rsp
    );
        bit failed;

        failed = 1'b0;
        if (rd_rsp.data.size() != (c.rd_len + 1)) begin
            `uvm_error(get_type_name(),
                       $sformatf("%s: read at 0x%0h returned %0d beats, expected %0d",
                                 c.label, rd_addr, rd_rsp.data.size(),
                                 c.rd_len + 1))
            return 1'b1;
        end
        foreach (rd_rsp.rresp[i]) begin
            if (rd_rsp.rresp[i] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("%s: read at 0x%0h beat=%0d returned %s",
                                     c.label, rd_addr, i,
                                     rd_rsp.rresp[i].name()))
            end else if (rd_rsp.data[i] !==
                         policy.read_data(rd_addr + (i << FULL_SIZE))) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: read at 0x%0h beat=%0d ",
                                      "expected=0x%0h actual=0x%0h"},
                                     c.label, rd_addr, i,
                                     policy.read_data(rd_addr + (i << FULL_SIZE)),
                                     rd_rsp.data[i]))
            end
        end
        return failed;
    endfunction : check_read_data

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        int unsigned              len,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_wr_order_e           wr_order
    );
        axi4_transaction req;
        int unsigned     req_len;
        axi4_dir_e       req_dir;
        axi4_wr_order_e  req_order;

        req_len   = len;
        req_dir   = dir;
        req_order = wr_order;
        req = axi4_transaction::type_id::create(
                  $sformatf("arb_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", pairs_run));
        if (!req.randomize() with {
                dir      == local::req_dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == local::req_order;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed at 0x%0h", addr))

        if (dir == AXI4_WRITE) begin
            foreach (req.data[i]) begin
                for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
                    req.data[i][8*k +: 8] = 8'hA0 + pairs_run * 4 + i * 2 + k;
                req.strb[i] = '1;
            end
        end
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // The write of a pair sits in the lower half of its region and the read in
    // the upper half, so the scoreboard can tell the two apart by address and
    // neither burst crosses a 1 KB boundary.
    protected function void validate_knobs();
        int unsigned half_bytes;

        half_bytes = 4 * AXI4_STRB_WIDTH;
        if ((case_stride < (2 * half_bytes)) ||
            ((case_stride % (2 * half_bytes)) != 0))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be a non-zero multiple of %0d bytes",
                                 2 * half_bytes))
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
    endfunction : validate_knobs

endclass : axi4_mst_read_priority_seq