//=============================================================================
// File        : axi4_mst_single_wstrb_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 single-write (AWLEN=0) WSTRB decoding sequence.
//               For a single write the bridge derives HSIZE from WSTRB when
//               the strobe is a legal pattern (one size-aligned run of 1, 2,
//               4 or 8 byte lanes) and falls back to AWSIZE otherwise; HADDR
//               is AWADDR aligned to that size (PG177 Narrow Transfers).
//               Cases:
//               - LEGAL: every legal narrow pattern with AWSIZE equal to the
//                 pattern size and AWADDR on the strobed lane (narrow build),
//                 full-width AWSIZE with a lane-0 pattern (narrow build) and
//                 the full-width pattern (both builds).
//               - MISDIRECTED (negative, narrow build): legal narrow pattern
//                 above lane 0 with full-width AWSIZE at a word-aligned
//                 AWADDR, so HADDR does not point at the strobed lanes.
//               - FALLBACK (negative): zero and every non-legal pattern with
//                 full-width AWSIZE, plus zero with each narrow AWSIZE on the
//                 top lane (narrow build), so HSIZE falls back to AWSIZE.
//               Each case writes a background word, applies the single write,
//               then reads the whole word back and compares it with the lanes
//               the bridge writes (HADDR/HSIZE and WDATA). Negative cases log
//               how that differs from AXI WSTRB semantics.
//               Covers BRG_SIZ_004 and BRG_SIZ_006.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_single_wstrb_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_single_wstrb_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr       = 'h1000;
    int unsigned              case_stride     = 'h10;
    bit                       enable_narrow   = 1'b0;
    bit                       enable_negative = 1'b1;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned legal_cases;
    int unsigned misdirected_cases;
    int unsigned fallback_cases;
    int unsigned lanes_written_unstrobed;
    int unsigned lanes_strobed_unwritten;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef enum {
        WSTRB_LEGAL,        // bridge write matches AXI WSTRB semantics
        WSTRB_MISDIRECTED,  // legal pattern, HADDR not on the strobed lanes
        WSTRB_FALLBACK      // zero/non-legal pattern, HSIZE = AWSIZE
    } wstrb_kind_e;

    typedef struct {
        bit [AXI4_STRB_WIDTH-1:0] strobe;
        int unsigned              aw_size;      // AWSIZE code
        int unsigned              lane_offset;  // AWADDR offset in the word
        wstrb_kind_e              kind;
        string                    label;
    } wstrb_case_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_single_wstrb_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        wstrb_case_t cases[$];

        wait_reset_release();
        validate_knobs();

        build_cases(cases);

        `uvm_info(get_type_name(),
                  $sformatf("Single WSTRB: %0d cases, narrow=%0b negative=%0b",
                            cases.size(), enable_narrow, enable_negative),
                  UVM_LOW)
        if (!enable_narrow)
            `uvm_info(get_type_name(),
                      "Narrow WSTRB cases disabled by test configuration",
                      UVM_LOW)

        foreach (cases[i])
            run_case(i, cases[i]);

        `uvm_info(get_type_name(),
                  $sformatf({"Single WSTRB summary: run=%0d failed=%0d ",
                             "legal=%0d misdirected=%0d fallback=%0d ",
                             "lanes_written_unstrobed=%0d ",
                             "lanes_strobed_unwritten=%0d"},
                            cases_run, cases_failed, legal_cases,
                            misdirected_cases, fallback_cases,
                            lanes_written_unstrobed, lanes_strobed_unwritten),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void build_cases(ref wstrb_case_t cases[$]);
        // Narrow AWSIZE with AWADDR on the strobed lane
        if (enable_narrow) begin
            for (int unsigned size_code = 0; size_code < FULL_SIZE; size_code++) begin
                int unsigned bytes;

                bytes = 1 << size_code;
                for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane += bytes)
                    cases.push_back('{get_mask(size_code, lane), size_code, lane,
                                      WSTRB_LEGAL,
                                      $sformatf("AWSIZE_%0dB_LANE%0d", bytes, lane)});

                // Zero strobe with narrow AWSIZE on the top lane: HSIZE falls
                // back to AWSIZE, so the addressed lanes are written
                if (enable_negative)
                    cases.push_back('{'0, size_code, AXI4_STRB_WIDTH - bytes,
                                      WSTRB_FALLBACK,
                                      $sformatf("AWSIZE_%0dB_LANE%0d_WSTRB_0x0",
                                                bytes, AXI4_STRB_WIDTH - bytes)});
            end
        end

        // Full-width AWSIZE at a word-aligned AWADDR, every WSTRB value
        for (int unsigned value = 0; value < (1 << AXI4_STRB_WIDTH); value++) begin
            bit [AXI4_STRB_WIDTH-1:0] strobe;
            int unsigned              size_code;
            int unsigned              lane;
            wstrb_kind_e              kind;

            strobe = value;
            if (decode_strobe(strobe, size_code, lane)) begin
                if (size_code == FULL_SIZE)
                    kind = WSTRB_LEGAL;
                else if (!enable_narrow)
                    continue;
                else if (lane == 0)
                    kind = WSTRB_LEGAL;
                else if (enable_negative)
                    kind = WSTRB_MISDIRECTED;
                else
                    continue;
            end else if (enable_negative) begin
                kind = WSTRB_FALLBACK;
            end else begin
                continue;
            end

            cases.push_back('{strobe, FULL_SIZE, 0, kind,
                              $sformatf("AWSIZE_FULL_WSTRB_0x%0h", strobe)});
        end
    endfunction : build_cases

    //-------------------------------------------------------------------------
    // Run one case: background write, single write, whole-word read-back
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, wstrb_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] word_addr;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [AXI4_DATA_WIDTH-1:0] background;
        bit [AXI4_DATA_WIDTH-1:0] wdata;
        bit [AXI4_DATA_WIDTH-1:0] expected;
        bit [AXI4_DATA_WIDTH-1:0] axi_expected;
        bit [AXI4_STRB_WIDTH-1:0] written;
        int unsigned              hsize;
        int unsigned              hbytes;
        int unsigned              hlane;
        int unsigned              size_code;
        int unsigned              lane;
        axi4_transaction          req;
        axi4_transaction          rsp;

        word_addr  = base_addr + (index * case_stride);
        addr       = word_addr + c.lane_offset;
        background = get_pattern(8'hA0, index);
        wdata      = get_pattern(8'h50, index);

        // Lanes the bridge writes: HSIZE from WSTRB if legal, else AWSIZE;
        // HADDR is AWADDR aligned to HSIZE
        if (decode_strobe(c.strobe, size_code, lane))
            hsize = size_code;
        else
            hsize = c.aw_size;
        hbytes = 1 << hsize;
        hlane  = (addr - (addr % hbytes)) - word_addr;
        written = '0;
        for (int unsigned k = 0; k < hbytes; k++)
            written[hlane + k] = 1'b1;

        expected     = merge_lanes(background, wdata, written);
        axi_expected = merge_lanes(background, wdata, c.strobe);

        `uvm_info(get_type_name(),
                  $sformatf({"[%0d] %s %s addr=0x%0h AWSIZE=%0dB WSTRB=0x%0h ",
                             "expected HSIZE=%0dB HADDR=0x%0h"},
                            index, c.kind.name(), c.label, addr,
                            1 << c.aw_size, c.strobe, hbytes,
                            word_addr + hlane),
                  UVM_MEDIUM)

        // Classification must agree with the lane model
        if ((c.kind == WSTRB_LEGAL) != (written == c.strobe))
            `uvm_fatal(get_type_name(),
                       $sformatf("%s: case class %s disagrees with lane model (written=0x%0h)",
                                 c.label, c.kind.name(), written))

        // Background: full-width write of the whole word
        req = create_request(AXI4_WRITE, word_addr, FULL_SIZE);
        req.data[0] = background;
        req.strb[0] = '1;
        send_axi_request_wait(req, rsp);
        cases_run++;
        check_bresp(c.label, "background write", word_addr, rsp);

        // Single write under test
        req = create_request(AXI4_WRITE, addr, c.aw_size);
        req.data[0] = wdata;
        req.strb[0] = c.strobe;
        send_axi_request_wait(req, rsp);
        cases_run++;
        check_bresp(c.label, "single write", addr, rsp);

        // Whole-word read-back
        req = create_request(AXI4_READ, word_addr, FULL_SIZE);
        send_axi_request_wait(req, rsp);
        cases_run++;
        if ((rsp.rresp.size() != 1) || (rsp.data.size() != 1)) begin
            cases_failed++;
            `uvm_error(get_type_name(),
                       $sformatf("%s read-back at 0x%0h: expected 1 beat, got %0d",
                                 c.label, word_addr, rsp.data.size()))
        end else begin
            if (rsp.rresp[0] != AXI4_RESP_OKAY) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf("%s read-back at 0x%0h: RRESP=%s, expected OKAY",
                                     c.label, word_addr, rsp.rresp[0].name()))
            end
            if (rsp.data[0] !== expected) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf({"%s read-back at 0x%0h: expected=0x%0h ",
                                      "actual=0x%0h (background=0x%0h ",
                                      "wdata=0x%0h written lanes=0x%0h)"},
                                     c.label, word_addr, expected, rsp.data[0],
                                     background, wdata, written))
            end
        end

        // Record how negative cases differ from AXI WSTRB semantics
        case (c.kind)
            WSTRB_LEGAL:       legal_cases++;
            WSTRB_MISDIRECTED: misdirected_cases++;
            default:           fallback_cases++;
        endcase
        lanes_written_unstrobed += $countones(written & ~c.strobe);
        lanes_strobed_unwritten += $countones(c.strobe & ~written);
        if (c.kind != WSTRB_LEGAL)
            `uvm_info(get_type_name(),
                      $sformatf({"[NEG] %s: bridge writes lanes 0x%0h, AXI WSTRB ",
                                 "selects 0x%0h (AXI-correct word 0x%0h, ",
                                 "bridge word 0x%0h)"},
                                c.label, written, c.strobe, axi_expected,
                                expected),
                      UVM_MEDIUM)
    endtask : run_case

    //-------------------------------------------------------------------------
    // Strobe helpers
    //-------------------------------------------------------------------------
    // Returns 1 when the strobe is one size-aligned run of 2^n byte lanes
    protected function bit decode_strobe(
        input  bit [AXI4_STRB_WIDTH-1:0] strobe,
        output int unsigned              size_code,
        output int unsigned              lane
    );
        size_code = 0;
        lane      = 0;
        for (int unsigned s = 0; s <= FULL_SIZE; s++) begin
            for (int unsigned l = 0; l < AXI4_STRB_WIDTH; l += (1 << s)) begin
                if (strobe == get_mask(s, l)) begin
                    size_code = s;
                    lane      = l;
                    return 1'b1;
                end
            end
        end
        return 1'b0;
    endfunction : decode_strobe

    protected function bit [AXI4_STRB_WIDTH-1:0] get_mask(
        int unsigned size_code,
        int unsigned lane
    );
        bit [AXI4_STRB_WIDTH-1:0] mask;

        mask = '0;
        for (int unsigned k = 0; k < (1 << size_code); k++)
            mask[lane + k] = 1'b1;
        return mask;
    endfunction : get_mask

    protected function bit [AXI4_DATA_WIDTH-1:0] merge_lanes(
        bit [AXI4_DATA_WIDTH-1:0] base_word,
        bit [AXI4_DATA_WIDTH-1:0] new_word,
        bit [AXI4_STRB_WIDTH-1:0] lanes
    );
        bit [AXI4_DATA_WIDTH-1:0] word;

        word = base_word;
        for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
            if (lanes[k])
                word[8*k +: 8] = new_word[8*k +: 8];
        return word;
    endfunction : merge_lanes

    // Distinct per lane; the two seeds differ by 0x50 in every lane, so the
    // background and the write data never share a byte value
    protected function bit [AXI4_DATA_WIDTH-1:0] get_pattern(
        bit [7:0]    seed,
        int unsigned index
    );
        bit [AXI4_DATA_WIDTH-1:0] word;

        for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
            word[8*k +: 8] = seed + index * 4 + k;
        return word;
    endfunction : get_pattern

    //-------------------------------------------------------------------------
    // Request creation and response check
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              size_code
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("wstrb_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == 0;
                size     == axi4_size_e'(local::size_code);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s addr=0x%0h size=%0d",
                                 dir.name(), addr, size_code))
        return req;
    endfunction : create_request

    protected function void check_bresp(
        string                    label,
        string                    step,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp
    );
        if (rsp.bresp != AXI4_RESP_OKAY) begin
            cases_failed++;
            `uvm_error(get_type_name(),
                       $sformatf("%s %s at 0x%0h: BRESP=%s, expected OKAY",
                                 label, step, addr, rsp.bresp.name()))
        end
    endfunction : check_bresp

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        if ((base_addr % AXI4_STRB_WIDTH) != 0)
            `uvm_fatal(get_type_name(), "base_addr is not bus aligned")
        if ((case_stride < AXI4_STRB_WIDTH) ||
            ((case_stride % AXI4_STRB_WIDTH) != 0))
            `uvm_fatal(get_type_name(),
                       "case_stride must be a non-zero multiple of the bus width in bytes")
    endfunction : validate_knobs

endclass : axi4_mst_single_wstrb_seq