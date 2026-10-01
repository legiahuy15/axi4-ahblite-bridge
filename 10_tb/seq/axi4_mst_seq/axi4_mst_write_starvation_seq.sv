//=============================================================================
// File        : axi4_mst_write_starvation_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Write bursts with WVALID gaps:
//               - mid-burst INCR gap: AHB_WR_WAIT, AXI_WVALID_WAIT
//               - gap before the last INCR beat: BUSY, AHB_LAST
//               - same on FIXED/WRAP2: IDLE, AHB_LAST_WAIT
//               - after a 1 KB split: AHB_ONEKB_LAST
//               BUSY/IDLE inside bursts must be observed; data is read back.
//               Covers BRG_ENV_005.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_write_starvation_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_write_starvation_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BUS_BYTES = AXI4_STRB_WIDTH;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    // 4 KB aligned base for all cases
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h8000;
    int unsigned              case_stride = 'h40;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    ahb_vif_t ahb_vif;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned gaps_requested;
    int unsigned gap_cycles_total;
    int unsigned busy_transfers;      // AHB BUSY seen inside a burst
    int unsigned idle_in_burst;       // AHB IDLE cycles seen inside a burst

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_burst_e burst;
        int unsigned len;
        int unsigned gap_beat;    // beat the gap sits in front of
        int unsigned gap_cycles;
        bit          cross_1kb;
        int unsigned region;      // which 1 KB crossing point, cross_1kb only
        string       label;
    } starve_case_t;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected starve_case_t case_list[$];
    protected bit           collect_ahb;
    // Open from the first to the last beat (the closing IDLE is excluded)
    protected bit           burst_active;
    protected int unsigned  beats_expected;
    protected int unsigned  beats_seen;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_write_starvation_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (ahb_vif == null)
            `uvm_fatal(get_type_name(), "AHB virtual interface is null")
        if (!cfg.return_responses)
            `uvm_fatal(get_type_name(),
                       "The read-back needs return_responses")

        validate_knobs();
        wait_reset_release();
        build_cases();

        `uvm_info(get_type_name(),
                  $sformatf("Write starvation: %0d directed cases",
                            case_list.size()),
                  UVM_LOW)

        fork
            begin
                fork
                    observe_ahb();
                    run_all_cases();
                join_any
                disable fork;
            end
        join

        check_bridge_actually_stalled();

        `uvm_info(get_type_name(),
                  $sformatf({"Write starvation summary: run=%0d failed=%0d ",
                             "gaps=%0d gap_cycles=%0d ahb_busy=%0d ",
                             "ahb_idle_in_burst=%0d"},
                            cases_run, cases_failed, gaps_requested,
                            gap_cycles_total, busy_transfers, idle_in_burst),
                  UVM_LOW)
    endtask : body

    protected task run_all_cases();
        foreach (case_list[i])
            run_case(i, case_list[i]);
        // Let the observer see the tail of the last burst
        wait_cycles(4);
    endtask : run_all_cases

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void add_case(
        axi4_burst_e burst,
        int unsigned len,
        int unsigned gap_beat,
        int unsigned gap_cycles,
        bit          cross_1kb,
        int unsigned region,
        string       label
    );
        starve_case_t c;

        c.burst      = burst;
        c.len        = len;
        c.gap_beat   = gap_beat;
        c.gap_cycles = gap_cycles;
        c.cross_1kb  = cross_1kb;
        c.region     = region;
        c.label      = label;
        case_list.push_back(c);
    endfunction : add_case

    protected function void build_cases();
        // A gap in the middle of a plain INCR: AHB_WR_WAIT, AXI_WVALID_WAIT
        add_case(AXI4_BURST_INCR, 7, 3, 1, 1'b0, 0, "INCR8_MID_GAP1");
        add_case(AXI4_BURST_INCR, 7, 3, 5, 1'b0, 0, "INCR8_MID_GAP5");
        add_case(AXI4_BURST_INCR, 3, 1, 2, 1'b0, 0, "INCR4_EARLY_GAP2");
        add_case(AXI4_BURST_INCR, 15, 8, 12, 1'b0, 0, "INCR16_MID_GAP12");

        // A gap before the last beat of a plain INCR: the bridge answers
        // with BUSY and goes to AHB_LAST
        add_case(AXI4_BURST_INCR, 7, 7, 3, 1'b0, 0, "INCR8_LAST_GAP3");
        add_case(AXI4_BURST_INCR, 3, 3, 6, 1'b0, 0, "INCR4_LAST_GAP6");

        // FIXED and WRAP2 take the IDLE route to AHB_LAST_WAIT instead
        add_case(AXI4_BURST_FIXED, 3, 3, 4, 1'b0, 0, "FIXED4_LAST_GAP4");
        add_case(AXI4_BURST_FIXED, 3, 1, 4, 1'b0, 0, "FIXED4_MID_GAP4");
        add_case(AXI4_BURST_WRAP,  1, 1, 4, 1'b0, 0, "WRAP2_LAST_GAP4");

        // Gap on the beat after the 1 KB boundary (burst starts one beat
        // below it)
        add_case(AXI4_BURST_INCR, 1, 1, 4, 1'b1, 0, "ONEKB_LAST_GAP4");
        add_case(AXI4_BURST_INCR, 3, 1, 4, 1'b1, 1, "ONEKB_SPLIT_GAP4");
        // Short gaps: the other exit from AHB_LAST_WAIT
        add_case(AXI4_BURST_INCR, 1, 1, 1, 1'b1, 2, "ONEKB_LAST_GAP1");
        add_case(AXI4_BURST_INCR, 1, 1, 2, 1'b1, 3, "ONEKB_LAST_GAP2");
    endfunction : build_cases

    //-------------------------------------------------------------------------
    // Observer
    //-------------------------------------------------------------------------
    // Count BUSY and IDLE inside bursts
    protected task observe_ahb();
        ahb_trans_e htrans;

        forever begin
            @(ahb_vif.monitor_cb);
            if (ahb_vif.rst_n !== 1'b1)
                continue;
            if (!collect_ahb)
                continue;
            if (ahb_vif.monitor_cb.HREADY !== 1'b1)
                continue;

            htrans = ahb_trans_e'(ahb_vif.monitor_cb.HTRANS);
            case (htrans)
                AHB_TRANS_NONSEQ, AHB_TRANS_SEQ: begin
                    beats_seen++;
                    burst_active = (beats_seen < beats_expected);
                end
                AHB_TRANS_BUSY: begin
                    if (burst_active)
                        busy_transfers++;
                end
                AHB_TRANS_IDLE: begin
                    if (burst_active)
                        idle_in_burst++;
                end
                default: ;
            endcase
        end
    endtask : observe_ahb

    //-------------------------------------------------------------------------
    // One case
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, starve_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          wr_req;
        axi4_transaction          wr_rsp;
        axi4_transaction          rd_req;
        axi4_transaction          rd_rsp;
        bit                       failed;

        addr = case_address(index, c);

        wr_req = create_write(index, c, addr);
        gaps_requested++;
        gap_cycles_total += c.gap_cycles;

        beats_expected = c.len + 1;
        beats_seen     = 0;
        burst_active   = 1'b0;
        collect_ahb    = 1'b1;
        send_axi_request_wait(wr_req, wr_rsp);
        // The burst is over; anything after this is the read-back
        burst_active = 1'b0;
        collect_ahb  = 1'b0;

        cases_run++;
        failed = check_write(c, addr, wr_rsp);

        rd_req = create_read(c, addr);
        send_axi_request_wait(rd_req, rd_rsp);
        failed |= check_readback(c, addr, wr_req, rd_rsp);

        `uvm_info(get_type_name(),
                  $sformatf({"[%0d] %s addr=0x%0h %s len=%0d gap=%0d cycles ",
                             "before beat %0d"},
                            index, c.label, addr, c.burst.name(), c.len,
                            c.gap_cycles, c.gap_beat + 1),
                  UVM_MEDIUM)

        if (failed)
            cases_failed++;
    endtask : run_case

    //-------------------------------------------------------------------------
    // Checks
    //-------------------------------------------------------------------------
    protected function bit check_write(
        starve_case_t             c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp
    );
        if (rsp.bresp != AXI4_RESP_OKAY) begin
            `uvm_error(get_type_name(),
                       $sformatf({"%s: the write at 0x%0h returned %s; a gap ",
                                  "in the write data must not change the ",
                                  "response"},
                                 c.label, addr, rsp.bresp.name()))
            return 1'b1;
        end
        return 1'b0;
    endfunction : check_write

    // Every beat has to have landed where it would have without the gap
    protected function bit check_readback(
        starve_case_t             c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          wr_req,
        axi4_transaction          rd_rsp
    );
        bit failed;

        failed = 1'b0;
        if (rd_rsp.data.size() != (c.len + 1)) begin
            `uvm_error(get_type_name(),
                       $sformatf("%s: read back %0d beats, expected %0d",
                                 c.label, rd_rsp.data.size(), c.len + 1))
            return 1'b1;
        end

        foreach (rd_rsp.data[beat]) begin
            bit [AXI4_DATA_WIDTH-1:0] expected;

            // A FIXED burst writes every beat to the same word, so the last
            // one is what stayed there
            expected = (c.burst == AXI4_BURST_FIXED) ?
                           wr_req.data[c.len] : wr_req.data[beat];

            if (rd_rsp.rresp[beat] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("%s: read-back beat %0d returned %s",
                                     c.label, beat, rd_rsp.rresp[beat].name()))
            end else if (rd_rsp.data[beat] !== expected) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: read-back beat %0d at 0x%0h is ",
                                      "0x%0h, expected 0x%0h; the gap ",
                                      "changed what the write left behind"},
                                     c.label, beat,
                                     beat_address(c, addr, beat),
                                     rd_rsp.data[beat], expected))
            end
        end
        return failed;
    endfunction : check_readback

    // The bridge must have stalled
    protected function void check_bridge_actually_stalled();
        if (cases_run != case_list.size())
            `uvm_error(get_type_name(),
                       $sformatf("Only %0d of %0d cases ran",
                                 cases_run, case_list.size()))
        if (busy_transfers == 0)
            `uvm_error(get_type_name(),
                       {"The bridge never issued an AHB BUSY, so the write ",
                        "data never ran dry in the middle of a burst as far ",
                        "as the bridge was concerned"})
        if (idle_in_burst == 0)
            `uvm_error(get_type_name(),
                       {"The bridge never drove IDLE inside a burst, so the ",
                        "FIXED, WRAP2 and 1 KB split gaps did not reach it"})
    endfunction : check_bridge_actually_stalled

    //-------------------------------------------------------------------------
    // Addresses
    //-------------------------------------------------------------------------
    // Crossing cases start one beat below a 1 KB boundary; others get a slot
    // below the first boundary
    protected function bit [AXI4_ADDR_WIDTH-1:0] case_address(
        int unsigned  index,
        starve_case_t c
    );
        bit [AXI4_ADDR_WIDTH-1:0] boundary;

        if (!c.cross_1kb)
            return base_addr + (index * case_stride);

        // Three usable 1 KB boundaries per 4 KB page
        boundary = base_addr + ((c.region / 3) * 4096)
                             + (((c.region % 3) + 1) * 1024);
        return boundary - BUS_BYTES;
    endfunction : case_address

    protected function bit [AXI4_ADDR_WIDTH-1:0] beat_address(
        starve_case_t             c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              beat
    );
        int unsigned span;

        case (c.burst)
            AXI4_BURST_FIXED:
                return addr;
            AXI4_BURST_WRAP: begin
                span = (c.len + 1) * BUS_BYTES;
                return (addr - (addr % span)) +
                       ((addr % span) + (beat * BUS_BYTES)) % span;
            end
            default:
                return addr + (beat * BUS_BYTES);
        endcase
    endfunction : beat_address

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_write(
        int unsigned              index,
        starve_case_t             c,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;
        axi4_burst_e     req_burst;
        int unsigned     req_len;
        int unsigned     gap_beat;
        int unsigned     gap_cycles;

        req_burst  = c.burst;
        req_len    = c.len;
        gap_beat   = c.gap_beat;
        gap_cycles = c.gap_cycles;

        req = axi4_transaction::type_id::create(
                  $sformatf("starve_wr_%0d", index));
        if (!req.randomize() with {
                dir      == AXI4_WRITE;
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == local::req_burst;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("%s: randomization failed at 0x%0h",
                                 c.label, addr))

        req.w_gap_beat   = gap_beat;
        req.w_gap_cycles = gap_cycles;

        foreach (req.data[beat]) begin
            for (int unsigned lane = 0; lane < BUS_BYTES; lane++)
                req.data[beat][8 * lane +: 8] =
                    8'(8'h60 + (index * 11) + (beat * 5) + lane);
            req.strb[beat] = '1;
        end
        return req;
    endfunction : create_write

    protected function axi4_transaction create_read(
        starve_case_t             c,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;
        axi4_burst_e     req_burst;
        int unsigned     req_len;

        req_burst = c.burst;
        req_len   = c.len;

        req = axi4_transaction::type_id::create("starve_rd");
        if (!req.randomize() with {
                dir      == AXI4_READ;
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == local::req_burst;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("%s: read-back randomization failed at 0x%0h",
                                 c.label, addr))
        return req;
    endfunction : create_read

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        if ((base_addr % 4096) != 0)
            `uvm_fatal(get_type_name(),
                       {"base_addr must be 4 KB aligned: the 1 KB crossing ",
                        "cases are placed relative to it and no burst may ",
                        "leave its 4 KB page"})
        if (case_stride < (16 * BUS_BYTES))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be at least %0d bytes",
                                 16 * BUS_BYTES))
    endfunction : validate_knobs

endclass : axi4_mst_write_starvation_seq