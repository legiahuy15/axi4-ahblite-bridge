//=============================================================================
// File        : axi4_mst_parameter_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Compliance profile driven from the configuration the build
//               was compiled with.
//               PG177 supports equal AXI and AHB data widths of 32 or 64 bits
//               with narrow bursts off or on. The widths are package
//               parameters, so each one is a separate compilation, and this
//               sequence reads AXI4_DATA_WIDTH and AXI4_STRB_WIDTH rather
//               than assuming either. The same source therefore runs on all
//               four builds and the case list grows with the bus:
//               - full-width SINGLE, INCR4, INCR16, undefined INCR5, WRAP4
//                 and FIXED3, read and write, with the read data checked
//                 beat by beat
//               - one single write per legal narrow size on every lane it can
//                 sit on, but only where the build supports narrow bursts;
//                 the word is then read back at full width, so the lanes
//                 outside the transfer are checked to be untouched as well
//               On a 64-bit build that adds the 8-byte size and a third
//               narrow size on twice as many lanes, which is what makes the
//               profile a width sweep rather than the same traffic twice.
//               The AHB slave answers automatically from its memory model,
//               so a read returns what was written and an untouched word
//               returns its address pattern. ahb_response_policy is kept only
//               because read_data is the canonical form of that pattern.
//               Covers BRG_CFG_001 and BRG_CFG_002.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_parameter_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_parameter_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;
    bit                       supports_narrow;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    // Not used to answer anything here: only read_data, which is the same
    // address pattern the slave returns for a word nothing has written
    ahb_response_policy pattern;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned narrow_cases;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_dir_e   dir;
        axi4_burst_e burst;
        int unsigned len;          // AxLEN value
        int unsigned size;         // AxSIZE value
        int unsigned addr_offset;  // byte offset of the burst in its region
        int unsigned lane;         // byte lane in the bus word, narrow only
        bit          narrow;       // checked by a whole-word read-back
        string       label;
    } param_case_t;

    typedef struct {
        axi4_burst_e burst;
        int unsigned len;
        int unsigned offset_beats;
        string       label;
    } shape_t;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected param_case_t case_list[$];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_parameter_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (pattern == null)
            `uvm_fatal(get_type_name(), "Read-data pattern helper is null")

        wait_reset_release();
        validate_knobs();
        build_cases();

        `uvm_info(get_type_name(),
                  $sformatf({"Parameter profile: data=%0d addr=%0d id=%0d ",
                             "narrow=%0b, %0d cases"},
                            AXI4_DATA_WIDTH, AXI4_ADDR_WIDTH, AXI4_ID_WIDTH,
                            supports_narrow, case_list.size()),
                  UVM_LOW)

        foreach (case_list[i])
            run_case(i, case_list[i]);

        `uvm_info(get_type_name(),
                  $sformatf({"Parameter summary: data_width=%0d narrow=%0b ",
                             "run=%0d failed=%0d narrow_cases=%0d"},
                            AXI4_DATA_WIDTH, supports_narrow, cases_run,
                            cases_failed, narrow_cases),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void build_cases();
        add_full_width_cases();
        if (supports_narrow)
            add_narrow_cases();
    endfunction : build_cases

    protected function void add_case(
        axi4_dir_e   dir,
        axi4_burst_e burst,
        int unsigned len,
        int unsigned size,
        int unsigned addr_offset,
        int unsigned lane,
        bit          narrow,
        string       label
    );
        param_case_t c;

        c.dir         = dir;
        c.burst       = burst;
        c.len         = len;
        c.size        = size;
        c.addr_offset = addr_offset;
        c.lane        = lane;
        c.narrow      = narrow;
        c.label       = $sformatf("%s_%s", label,
                                  (dir == AXI4_READ) ? "RD" : "WR");
        case_list.push_back(c);
    endfunction : add_case

    // The shapes the bridge translates differently, at the full bus width
    protected function void add_full_width_cases();
        shape_t shapes[] = '{
            '{AXI4_BURST_INCR,   0, 0, "SINGLE"},
            '{AXI4_BURST_INCR,   3, 0, "INCR4"},
            '{AXI4_BURST_INCR,  15, 0, "INCR16"},
            '{AXI4_BURST_INCR,   4, 0, "INCR5"},
            '{AXI4_BURST_WRAP,   3, 2, "WRAP4"},
            '{AXI4_BURST_FIXED,  2, 0, "FIXED3"}
        };

        foreach (shapes[s])
            for (int unsigned d = 0; d < 2; d++)
                add_case((d == 0) ? AXI4_READ : AXI4_WRITE,
                         shapes[s].burst, shapes[s].len, FULL_SIZE,
                         shapes[s].offset_beats * AXI4_STRB_WIDTH, 0,
                         1'b0, shapes[s].label);
    endfunction : add_full_width_cases

    // One single write per legal narrow size on every lane it can occupy.
    // On 32 bits that is 1 and 2 bytes; on 64 bits it also covers 4.
    protected function void add_narrow_cases();
        for (int unsigned sz = 0; sz < FULL_SIZE; sz++) begin
            int unsigned bytes;

            bytes = 1 << sz;
            for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane += bytes)
                add_case(AXI4_WRITE, AXI4_BURST_INCR, 0, sz, 0, lane, 1'b1,
                         $sformatf("NARROW%0dB_L%0d", bytes, lane));
        end
    endfunction : add_narrow_cases

    //-------------------------------------------------------------------------
    // Run one case
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, param_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] region;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        int unsigned              beats;
        bit                       failed;

        region = base_addr + (index * case_stride);
        addr   = region + c.addr_offset + c.lane;
        beats  = c.len + 1;

        `uvm_info(get_type_name(),
                  $sformatf({"[%0d] %s addr=0x%0h beats=%0d size=%0dB ",
                             "burst=%s"},
                            index, c.label, addr, beats, 1 << c.size,
                            c.burst.name()),
                  UVM_MEDIUM)

        if (c.narrow) begin
            narrow_cases++;
            run_narrow_case(c, region, addr, failed);
        end else begin
            run_full_width_case(c, addr, beats, failed);
        end

        cases_run++;
        if (failed)
            cases_failed++;
    endtask : run_case

    // One burst at the full bus width, its read data checked beat by beat
    protected task run_full_width_case(
        input  param_case_t              c,
        input  bit [AXI4_ADDR_WIDTH-1:0] addr,
        input  int unsigned              beats,
        output bit                       failed
    );
        axi4_transaction req;
        axi4_transaction rsp;

        failed = 1'b0;
        req    = create_request(c, addr);
        send_axi_request_wait(req, rsp);

        if (c.dir == AXI4_WRITE) begin
            if (rsp.bresp != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("%s at 0x%0h: BRESP=%s",
                                     c.label, addr, rsp.bresp.name()))
            end
            return;
        end

        if (rsp.data.size() != beats) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s at 0x%0h: %0d beats, expected %0d",
                                 c.label, addr, rsp.data.size(), beats))
            return;
        end
        failed = check_read_beats(c, addr, beats, rsp);
    endtask : run_full_width_case

    // A narrow single write, then a full-width read of the word it landed in:
    // the strobed lanes must carry the new data and the others must not move
    protected task run_narrow_case(
        input  param_case_t              c,
        input  bit [AXI4_ADDR_WIDTH-1:0] region,
        input  bit [AXI4_ADDR_WIDTH-1:0] addr,
        output bit                       failed
    );
        axi4_transaction          wr_req;
        axi4_transaction          wr_rsp;
        axi4_transaction          rd_req;
        axi4_transaction          rd_rsp;
        bit [AXI4_DATA_WIDTH-1:0] expected;
        int unsigned              bytes;

        failed = 1'b0;
        bytes  = 1 << c.size;

        wr_req = create_request(c, addr);
        send_axi_request_wait(wr_req, wr_rsp);
        if (wr_rsp.bresp != AXI4_RESP_OKAY) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s at 0x%0h: BRESP=%s",
                                 c.label, addr, wr_rsp.bresp.name()))
        end

        // Untouched lanes keep the slave's address pattern
        expected = pattern.read_data(region);
        for (int unsigned i = 0; i < bytes; i++)
            expected[8*(c.lane + i) +: 8] = wr_req.data[0][8*(c.lane + i) +: 8];

        rd_req = create_full_read(region);
        send_axi_request_wait(rd_req, rd_rsp);

        if (rd_rsp.data.size() != 1) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s read-back at 0x%0h returned %0d beats",
                                 c.label, region, rd_rsp.data.size()))
            return;
        end
        if (rd_rsp.data[0] !== expected) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s read-back at 0x%0h: expected=0x%0h ",
                                  "actual=0x%0h (%0d-byte write on lane %0d)"},
                                 c.label, region, expected, rd_rsp.data[0],
                                 bytes, c.lane))
        end
    endtask : run_narrow_case

    //-------------------------------------------------------------------------
    // Checks
    //-------------------------------------------------------------------------
    protected function bit check_read_beats(
        param_case_t              c,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              beats,
        axi4_transaction          rsp
    );
        bit [AXI4_ADDR_WIDTH-1:0] beat_addr[];
        bit                       failed;

        failed = 1'b0;
        get_beat_addresses(addr, c, beats, beat_addr);
        foreach (rsp.rresp[i]) begin
            if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("%s at 0x%0h beat=%0d: RRESP=%s",
                                     c.label, addr, i, rsp.rresp[i].name()))
            end else if (rsp.data[i] !== pattern.read_data(beat_addr[i])) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s at 0x%0h beat=%0d: expected=0x%0h ",
                                      "actual=0x%0h"},
                                     c.label, addr, i,
                                     pattern.read_data(beat_addr[i]),
                                     rsp.data[i]))
            end
        end
        return failed;
    endfunction : check_read_beats

    //-------------------------------------------------------------------------
    // Addresses
    //-------------------------------------------------------------------------
    protected function void get_beat_addresses(
        input  bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        input  param_case_t              c,
        input  int unsigned              beats,
        output bit [AXI4_ADDR_WIDTH-1:0] beat_addr[]
    );
        int unsigned              bytes;
        bit [AXI4_ADDR_WIDTH-1:0] wrap_base;
        bit [AXI4_ADDR_WIDTH-1:0] next_addr;

        bytes        = 1 << c.size;
        wrap_base    = start_addr - (start_addr % (beats * bytes));
        beat_addr    = new[beats];
        beat_addr[0] = start_addr;
        for (int unsigned i = 1; i < beats; i++) begin
            case (c.burst)
                AXI4_BURST_FIXED: next_addr = start_addr;
                AXI4_BURST_WRAP: begin
                    next_addr = beat_addr[i - 1] + bytes;
                    if (next_addr >= (wrap_base + (beats * bytes)))
                        next_addr = wrap_base;
                end
                default: next_addr = beat_addr[i - 1] + bytes;
            endcase
            beat_addr[i] = next_addr;
        end
    endfunction : get_beat_addresses

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        param_case_t              c,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;
        int unsigned     req_len;
        int unsigned     req_size;
        axi4_burst_e     req_burst;
        axi4_dir_e       req_dir;
        int unsigned     bytes;

        req_len   = c.len;
        req_size  = c.size;
        req_burst = c.burst;
        req_dir   = c.dir;
        bytes     = 1 << c.size;

        req = axi4_transaction::type_id::create(
                  $sformatf("par_%s_%0d",
                            (c.dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::req_dir;
                id       inside {[local::id_lo:local::id_hi]};
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
                       $sformatf("Randomization failed: %s addr=0x%0h",
                                 c.label, addr))

        if (c.dir == AXI4_WRITE) begin
            foreach (req.data[i]) begin
                req.data[i] = '0;
                req.strb[i] = '0;
                // Only the lanes the transfer covers carry data and strobes
                for (int unsigned k = 0; k < bytes; k++) begin
                    req.data[i][8*(c.lane + k) +: 8] =
                        8'h10 + cases_run + (i * 4) + k;
                    req.strb[i][c.lane + k] = 1'b1;
                end
            end
        end
        return req;
    endfunction : create_request

    protected function axi4_transaction create_full_read(
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("par_rdback_%0d", cases_run));
        if (!req.randomize() with {
                dir      == AXI4_READ;
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
                       $sformatf("Read-back randomization failed at 0x%0h",
                                 addr))
        return req;
    endfunction : create_full_read

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // Every case owns a region, so a read case never lands on a word another
    // case wrote and the address pattern is the whole oracle for it.
    protected function void validate_knobs();
        int unsigned region_bytes;

        if (!(AXI4_DATA_WIDTH inside {32, 64}))
            `uvm_fatal(get_type_name(),
                       $sformatf("Unsupported AXI4_DATA_WIDTH=%0d",
                                 AXI4_DATA_WIDTH))
        if (AXI4_DATA_WIDTH != AHB_DATA_WIDTH)
            `uvm_fatal(get_type_name(),
                       "AXI4 and AHB-Lite data widths differ")
        region_bytes = 16 * AXI4_STRB_WIDTH;
        if ((case_stride < region_bytes) ||
            ((case_stride % region_bytes) != 0))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be a non-zero multiple of %0d bytes",
                                 region_bytes))
        if ((base_addr % case_stride) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of case_stride")
    endfunction : validate_knobs

endclass : axi4_mst_parameter_seq
