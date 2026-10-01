//=============================================================================
// File        : axi4_mst_illegal_narrow_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Write requests the bridge cannot honour, shown on memory.
//               Two things AXI4 allows and this bridge does not, both left
//               open by BRG_SIZ_006 after bridge_single_wstrb_test closed
//               the single-write strobe cases and bridge_unaligned_read_test
//               closed the unaligned reads:
//               - WSTRB inside a burst. For AWLEN of zero the bridge reads
//                 the strobes and derives HSIZE from them, but for a burst
//                 axi_slv_if takes HSIZE from AWSIZE and never looks at
//                 WSTRB again. AHB-Lite has no byte strobes, so every beat
//                 writes a whole AWSIZE-wide word and the lanes the master
//                 masked off are overwritten with it. WSTRB of zero is the
//                 plainest case: ordinary AXI asking for nothing to be
//                 written, and the whole word changes anyway.
//               - an unaligned write. The bridge aligns the beat address
//                 down to the transfer size, so the byte offset the master
//                 asked for is lost and the data lands in the word below.
//               Neither is a bug to be fixed here; both match the reference
//               design and the spec review. They are recorded as negative
//               cases so they are not mistaken for coverage holes, and so
//               the damage is written down: which lanes change, and where
//               the data actually lands.
//               Every case is run against memory rather than argued about.
//               The slot is seeded with a known pattern, the illegal write
//               is sent, and the whole slot is read back at full width and
//               compared against a model of what the bridge really does,
//               not of what AXI asked for. A case that left the untouched
//               words alone and still corrupted the masked lanes is what
//               passing looks like.
//               Covers BRG_SIZ_006.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_illegal_narrow_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_illegal_narrow_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BUS_BYTES = AXI4_STRB_WIDTH;

    // Words of the slot seeded and read back around each case, so a write
    // that spilled outside the beats it claimed is visible too
    localparam int unsigned WINDOW_WORDS = 8;

    // Strobe patterns, all built from the bus width so they mean the same
    // thing on a 32 and a 64 bit bus
    localparam int unsigned STRB_NONE      = 0;
    localparam int unsigned STRB_ALTERNATE = 1;
    localparam int unsigned STRB_ONE_LANE  = 2;
    localparam int unsigned STRB_ROTATE    = 3;
    localparam int unsigned STRB_FULL      = 4;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'hA000;
    int unsigned              case_stride = 'h80;
    bit                       supports_narrow;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    // Only read_data is used: the canonical address pattern the slave
    // returns for a word nothing has written
    ahb_response_policy pattern;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned strobe_cases;
    int unsigned unaligned_cases;
    int unsigned narrow_cases;
    // The two findings, counted only once the read-back has confirmed them
    int unsigned lanes_overwritten;   // masked lanes the bridge wrote anyway
    int unsigned offsets_lost;        // writes that landed below their address

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_burst_e burst;
        int unsigned len;
        int unsigned size;         // AxSIZE value
        int unsigned offset;       // byte offset of the request in its slot
        int unsigned strobe_mode;
        string       label;
    } illegal_case_t;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected illegal_case_t case_list[$];
    // Model of the slave memory, written the way the bridge really writes it
    protected bit [7:0] shadow[bit [AXI4_ADDR_WIDTH-1:0]];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_illegal_narrow_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (pattern == null)
            `uvm_fatal(get_type_name(), "Read-data pattern helper is null")
        if (!cfg.return_responses)
            `uvm_fatal(get_type_name(), "The read-back needs return_responses")

        validate_knobs();
        wait_reset_release();
        build_cases();

        `uvm_info(get_type_name(),
                  $sformatf({"Illegal narrow: %0d cases, bus=%0dB narrow=%0b"},
                            case_list.size(), BUS_BYTES, supports_narrow),
                  UVM_LOW)

        foreach (case_list[i])
            run_case(i, case_list[i]);

        check_findings_were_observed();

        `uvm_info(get_type_name(),
                  $sformatf({"Illegal narrow summary: run=%0d failed=%0d ",
                             "strobe=%0d unaligned=%0d narrow=%0d ",
                             "lanes_overwritten=%0d offsets_lost=%0d"},
                            cases_run, cases_failed, strobe_cases,
                            unaligned_cases, narrow_cases, lanes_overwritten,
                            offsets_lost),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void add_case(
        axi4_burst_e burst,
        int unsigned len,
        int unsigned size,
        int unsigned offset,
        int unsigned strobe_mode,
        string       label
    );
        illegal_case_t c;

        c.burst       = burst;
        c.len         = len;
        c.size        = size;
        c.offset      = offset;
        c.strobe_mode = strobe_mode;
        c.label       = label;
        case_list.push_back(c);
    endfunction : add_case

    protected function void build_cases();
        // WSTRB inside a burst, which the bridge does not read at all
        add_case(AXI4_BURST_INCR,  3, FULL_SIZE, 0, STRB_NONE,
                 "INCR4_WSTRB_ZERO");
        add_case(AXI4_BURST_INCR,  3, FULL_SIZE, 0, STRB_ALTERNATE,
                 "INCR4_WSTRB_ALTERNATE");
        add_case(AXI4_BURST_INCR,  3, FULL_SIZE, 0, STRB_ONE_LANE,
                 "INCR4_WSTRB_ONE_LANE");
        add_case(AXI4_BURST_INCR,  7, FULL_SIZE, 0, STRB_ROTATE,
                 "INCR8_WSTRB_ROTATE");
        add_case(AXI4_BURST_WRAP,  3, FULL_SIZE, 0, STRB_ALTERNATE,
                 "WRAP4_WSTRB_ALTERNATE");
        add_case(AXI4_BURST_FIXED, 3, FULL_SIZE, 0, STRB_ALTERNATE,
                 "FIXED4_WSTRB_ALTERNATE");

        // An unaligned write, at every byte offset the bus word has. A
        // burst is used as well as a single, because a single write is the
        // one case where the bridge does read WSTRB and would decide the
        // size from it instead of from AWSIZE.
        for (int unsigned off = 1; off < BUS_BYTES; off++) begin
            add_case(AXI4_BURST_INCR, 0, FULL_SIZE, off, STRB_FULL,
                     $sformatf("SINGLE_UNALIGNED_OFF%0d", off));
            add_case(AXI4_BURST_INCR, 1, FULL_SIZE, off, STRB_FULL,
                     $sformatf("INCR2_UNALIGNED_OFF%0d", off));
        end

        // Narrow bursts at an offset that does not suit their size. Only on
        // a build that supports them, and only as bursts: for a single
        // write the bridge would take the size from WSTRB rather than from
        // AWSIZE, which is bridge_single_wstrb_test's ground.
        if (supports_narrow) begin
            for (int unsigned sz = 1; sz < FULL_SIZE; sz++)
                add_case(AXI4_BURST_INCR, 1, sz, (1 << sz) / 2, STRB_FULL,
                         $sformatf("INCR2_NARROW%0dB_UNALIGNED",
                                   1 << sz));
        end
    endfunction : build_cases

    //-------------------------------------------------------------------------
    // One case
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, illegal_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] slot;
        axi4_transaction          req;
        axi4_transaction          rsp;
        bit                       failed;
        bit                       readback_failed;

        slot = base_addr + (index * case_stride);

        // A known starting point, so anything the illegal write changes is
        // visible against it
        seed_slot(index, slot);

        req = create_illegal_write(index, c, slot);
        send_axi_request_wait(req, rsp);
        cases_run++;
        count_shape(c);

        failed = check_response(c, rsp);
        apply_bridge_write(req);
        read_back_slot(index, c, slot, readback_failed);
        failed |= readback_failed;

        if (!failed)
            record_findings(c, req);

        if (failed)
            cases_failed++;
    endtask : run_case

    // Full-strobe, full-width, aligned: the one shape the bridge honours
    // exactly, so the slot starts in a state the model and the device agree
    // on.
    protected task seed_slot(
        int unsigned              index,
        bit [AXI4_ADDR_WIDTH-1:0] slot
    );
        axi4_transaction req;
        axi4_transaction rsp;
        int unsigned     seed_len;

        seed_len = WINDOW_WORDS - 1;
        req = axi4_transaction::type_id::create(
                  $sformatf("seed_%0d", index));
        if (!req.randomize() with {
                dir      == AXI4_WRITE;
                addr     == local::slot;
                len      == local::seed_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Seed randomization failed at 0x%0h", slot))

        foreach (req.data[beat]) begin
            for (int unsigned lane = 0; lane < BUS_BYTES; lane++)
                req.data[beat][8 * lane +: 8] =
                    8'(8'h10 + (index * 3) + (beat * 2) + lane);
            req.strb[beat] = '1;
        end

        send_axi_request_wait(req, rsp);
        if (rsp.bresp != AXI4_RESP_OKAY)
            `uvm_error(get_type_name(),
                       $sformatf("Seed write at 0x%0h returned %s",
                                 slot, rsp.bresp.name()))
        apply_bridge_write(req);
    endtask : seed_slot

    //-------------------------------------------------------------------------
    // Checks
    //-------------------------------------------------------------------------
    // An unsupported request is still answered normally: PG177 has no way to
    // report it, which is exactly why it has to be written down here.
    protected function bit check_response(
        illegal_case_t   c,
        axi4_transaction rsp
    );
        if (rsp.bresp != AXI4_RESP_OKAY) begin
            `uvm_error(get_type_name(),
                       $sformatf({"%s: returned %s; an unsupported write is ",
                                  "still completed with OKAY on this bridge"},
                                 c.label, rsp.bresp.name()))
            return 1'b1;
        end
        return 1'b0;
    endfunction : check_response

    // Read the whole window back at full width and compare it with the
    // model. This is where the finding is made: the model says the masked
    // lanes changed and the offset was dropped, and memory has to agree.
    // A task rather than a function, because it has to drive the bus, so
    // the verdict comes back through an output instead of a return value.
    protected task read_back_slot(
        input  int unsigned              index,
        input  illegal_case_t            c,
        input  bit [AXI4_ADDR_WIDTH-1:0] slot,
        output bit                       failed
    );
        axi4_transaction req;
        axi4_transaction rsp;
        int unsigned     read_len;

        failed   = 1'b0;
        read_len = WINDOW_WORDS - 1;

        req = axi4_transaction::type_id::create(
                  $sformatf("readback_%0d", index));
        if (!req.randomize() with {
                dir      == AXI4_READ;
                addr     == local::slot;
                len      == local::read_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("%s: read-back randomization failed at 0x%0h",
                                 c.label, slot))

        send_axi_request_wait(req, rsp);
        if (rsp.data.size() != WINDOW_WORDS) begin
            `uvm_error(get_type_name(),
                       $sformatf("%s: read back %0d words, expected %0d",
                                 c.label, rsp.data.size(), WINDOW_WORDS))
            failed = 1'b1;
            return;
        end

        foreach (rsp.data[word]) begin
            bit [AXI4_ADDR_WIDTH-1:0] addr;
            bit [AXI4_DATA_WIDTH-1:0] expected;

            addr     = slot + (word * BUS_BYTES);
            expected = shadow_word(addr);
            if (rsp.rresp[word] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("%s: read-back word %0d returned %s",
                                     c.label, word, rsp.rresp[word].name()))
            end else if (rsp.data[word] !== expected) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: word %0d at 0x%0h is 0x%0h, the ",
                                      "model of what this bridge does with ",
                                      "the request says 0x%0h"},
                                     c.label, word, addr, rsp.data[word],
                                     expected))
            end
        end
    endtask : read_back_slot

    protected function void record_findings(
        illegal_case_t            c,
        axi4_transaction          req
    );
        int unsigned              bytes;
        bit [AXI4_ADDR_WIDTH-1:0] landed;

        bytes = effective_bytes(req);

        // Masked lanes the bridge wrote anyway. Only the lanes the transfer
        // really reaches count: a write the strobes narrowed down to two
        // bytes leaves the other two alone, and calling those overwritten
        // would overstate the finding. Counted only once the read-back has
        // agreed with the model, so it is an observation, not an intention.
        foreach (req.strb[beat]) begin
            bit [AXI4_ADDR_WIDTH-1:0] addr;
            int unsigned              lane_offset;

            addr        = bridge_beat_address(req, beat, bytes);
            lane_offset = addr % BUS_BYTES;
            for (int unsigned i = 0; i < bytes; i++)
                if (!req.strb[beat][lane_offset + i])
                    lanes_overwritten++;
        end

        // Where the first beat actually landed. The size has to come from
        // effective_bytes rather than from AWSIZE: on a single write the
        // bridge derives it from WSTRB, so an offset of 2 with a full-width
        // AWSIZE becomes a 2-byte transfer that keeps its offset, while an
        // offset of 1 falls back to AWSIZE and loses it. Counting from the
        // request alone would get those two the wrong way round.
        landed = bridge_beat_address(req, 0, bytes);
        if (landed != req.addr)
            offsets_lost++;
    endfunction : record_findings

    // Neither finding may be reported on the strength of the stimulus alone
    protected function void check_findings_were_observed();
        if (cases_run != case_list.size())
            `uvm_error(get_type_name(),
                       $sformatf("Only %0d of %0d cases ran",
                                 cases_run, case_list.size()))
        if (lanes_overwritten == 0)
            `uvm_error(get_type_name(),
                       {"No masked byte lane was overwritten, so the burst ",
                        "strobe cases did not show the behaviour they exist ",
                        "to record"})
        if (offsets_lost == 0)
            `uvm_error(get_type_name(),
                       {"No unaligned write lost its offset, so the ",
                        "alignment cases did not show the behaviour they ",
                        "exist to record"})
    endfunction : check_findings_were_observed

    //-------------------------------------------------------------------------
    // Model of what the bridge really does
    //-------------------------------------------------------------------------
    // Not a model of AXI. WSTRB is ignored unless the request is a single
    // write, every beat writes a whole size-wide word, and the address is
    // aligned down to the size first.
    protected function void apply_bridge_write(axi4_transaction req);
        int unsigned bytes;

        bytes = effective_bytes(req);
        foreach (req.data[beat]) begin
            bit [AXI4_ADDR_WIDTH-1:0] addr;
            int unsigned              lane_offset;

            addr        = bridge_beat_address(req, beat, bytes);
            lane_offset = addr % BUS_BYTES;
            for (int unsigned i = 0; i < bytes; i++)
                shadow[addr + i] =
                    req.data[beat][8 * (lane_offset + i) +: 8];
        end
    endfunction : apply_bridge_write

    // Where a beat really goes. The start is aligned once, by the rule this
    // build uses: ahb_mstr_if has one address generator per build and only
    // the narrow one aligns to the transfer size, the other drives
    // {addr[..:2], 2'b00} whatever the size. After that each beat is the
    // effective size further on, which is also what the hardware does,
    // because a burst can only be narrower than the bus on a narrow build.
    // Note the lane the data is taken from moves with the aligned address,
    // so an offset that is dropped does not just misplace the bytes, it
    // picks different ones out of WDATA.
    protected function bit [AXI4_ADDR_WIDTH-1:0] bridge_beat_address(
        axi4_transaction req,
        int unsigned     beat,
        int unsigned     bytes
    );
        bit [AXI4_ADDR_WIDTH-1:0] start;
        int unsigned              align_bytes;

        align_bytes = supports_narrow ? bytes : BUS_BYTES;
        start       = req.addr - (req.addr % align_bytes);

        case (req.burst)
            AXI4_BURST_FIXED:
                return start;
            AXI4_BURST_WRAP: begin
                int unsigned              span;
                bit [AXI4_ADDR_WIDTH-1:0] wrap_base;

                span      = (int'(req.len) + 1) * bytes;
                wrap_base = start - (start % span);
                return wrap_base +
                       ((start - wrap_base + (beat * bytes)) % span);
            end
            default:
                return start + (beat * bytes);
        endcase
    endfunction : bridge_beat_address

    // A single write is the one place the bridge reads WSTRB: one
    // size-aligned run of lanes sets HSIZE, anything else falls back to
    // AWSIZE. For a burst AWSIZE is used and the strobes are ignored.
    protected function int unsigned effective_bytes(axi4_transaction req);
        int unsigned run_bytes;

        if (req.len != 0)
            return 1 << int'(req.size);

        for (int unsigned sz = 0; (1 << sz) <= BUS_BYTES; sz++) begin
            run_bytes = 1 << sz;
            for (int unsigned lane = 0; lane < BUS_BYTES;
                 lane += run_bytes) begin
                bit [AXI4_STRB_WIDTH-1:0] mask;

                mask = '0;
                for (int unsigned i = 0; i < run_bytes; i++)
                    mask[lane + i] = 1'b1;
                if (req.strb[0] == mask)
                    return run_bytes;
            end
        end
        return 1 << int'(req.size);
    endfunction : effective_bytes

    protected function bit [AXI4_DATA_WIDTH-1:0] shadow_word(
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        bit [AXI4_ADDR_WIDTH-1:0] base;
        bit [AXI4_DATA_WIDTH-1:0] word;

        base = addr - (addr % BUS_BYTES);
        word = pattern.read_data(base);
        for (int unsigned lane = 0; lane < BUS_BYTES; lane++) begin
            if (shadow.exists(base + lane))
                word[8 * lane +: 8] = shadow[base + lane];
        end
        return word;
    endfunction : shadow_word

    protected function bit [AXI4_ADDR_WIDTH-1:0] beat_address(
        axi4_transaction req,
        int unsigned     beat
    );
        int unsigned              bytes;
        bit [AXI4_ADDR_WIDTH-1:0] aligned;

        bytes   = 1 << int'(req.size);
        aligned = req.addr - (req.addr % bytes);

        case (req.burst)
            AXI4_BURST_FIXED:
                return aligned;
            AXI4_BURST_WRAP: begin
                int unsigned              span;
                bit [AXI4_ADDR_WIDTH-1:0] wrap_base;

                span      = (int'(req.len) + 1) * bytes;
                wrap_base = aligned - (aligned % span);
                return wrap_base +
                       ((aligned - wrap_base + (beat * bytes)) % span);
            end
            default:
                return aligned + (beat * bytes);
        endcase
    endfunction : beat_address

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_illegal_write(
        int unsigned              index,
        illegal_case_t            c,
        bit [AXI4_ADDR_WIDTH-1:0] slot
    );
        axi4_transaction          req;
        axi4_burst_e              req_burst;
        int unsigned              req_len;
        int unsigned              req_size;
        bit [AXI4_ADDR_WIDTH-1:0] addr;

        req_burst = c.burst;
        req_len   = c.len;
        req_size  = c.size;
        addr      = slot + c.offset;

        req = axi4_transaction::type_id::create(
                  $sformatf("illegal_%0d", index));
        if (!req.randomize() with {
                dir      == AXI4_WRITE;
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(local::req_size);
                burst    == local::req_burst;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf({"%s: randomization failed at 0x%0h ",
                                  "len=%0d size=%0d"},
                                 c.label, addr, c.len, c.size))

        foreach (req.data[beat]) begin
            for (int unsigned lane = 0; lane < BUS_BYTES; lane++)
                req.data[beat][8 * lane +: 8] =
                    8'(8'hC0 + (index * 5) + (beat * 3) + lane);
            req.strb[beat] = strobe_for(c, req, beat);
        end
        return req;
    endfunction : create_illegal_write

    protected function bit [AXI4_STRB_WIDTH-1:0] strobe_for(
        illegal_case_t   c,
        axi4_transaction req,
        int unsigned     beat
    );
        bit [AXI4_STRB_WIDTH-1:0] strb;

        strb = '0;
        case (c.strobe_mode)
            STRB_NONE: ;
            STRB_ALTERNATE: begin
                for (int unsigned lane = 0; lane < BUS_BYTES; lane += 2)
                    strb[lane] = 1'b1;
            end
            STRB_ONE_LANE:
                strb[1] = 1'b1;
            STRB_ROTATE:
                strb[beat % BUS_BYTES] = 1'b1;
            default:
                strb = lawful_strobe(req, beat);
        endcase
        return strb;
    endfunction : strobe_for

    // The strobes a well-behaved master would drive for this beat: the
    // lanes the transfer really covers, which for an unaligned first beat
    // stops at the next size boundary and never reaches past the bus word.
    // It is not all ones. A narrow write that strobed every lane would be
    // illegal AXI in its own right, and cg_write_strobe says so with an
    // illegal bin, so the alignment cases have to be malformed in one way
    // only: their address.
    protected function bit [AXI4_STRB_WIDTH-1:0] lawful_strobe(
        axi4_transaction req,
        int unsigned     beat
    );
        bit [AXI4_STRB_WIDTH-1:0] strb;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        int unsigned              bytes;
        int unsigned              lane_offset;
        int unsigned              run;

        bytes = 1 << int'(req.size);
        // Only the first beat starts where the master asked; the rest sit on
        // size boundaries
        addr  = (beat == 0) ? req.addr : beat_address(req, beat);

        lane_offset = addr % BUS_BYTES;
        run         = bytes - (addr % bytes);
        if (run > (BUS_BYTES - lane_offset))
            run = BUS_BYTES - lane_offset;

        strb = '0;
        for (int unsigned i = 0; i < run; i++)
            strb[lane_offset + i] = 1'b1;
        return strb;
    endfunction : lawful_strobe

    //-------------------------------------------------------------------------
    // Bookkeeping
    //-------------------------------------------------------------------------
    protected function void count_shape(illegal_case_t c);
        if (c.strobe_mode != STRB_FULL)
            strobe_cases++;
        if ((c.offset % (1 << c.size)) != 0)
            unaligned_cases++;
        if (c.size != FULL_SIZE)
            narrow_cases++;
    endfunction : count_shape

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        int unsigned window_bytes;

        window_bytes = WINDOW_WORDS * BUS_BYTES;
        if (case_stride < (2 * window_bytes))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be at least %0d bytes",
                                 2 * window_bytes))
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
    endfunction : validate_knobs

endclass : axi4_mst_illegal_narrow_seq