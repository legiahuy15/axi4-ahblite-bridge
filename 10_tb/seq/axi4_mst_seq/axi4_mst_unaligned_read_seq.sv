//=============================================================================
// File        : axi4_mst_unaligned_read_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 unaligned read directed sequence.
//               PG177: the bridge aligns the address on AHB-Lite for an
//               unaligned AXI read. For each case the sequence writes a known
//               background with an aligned full-width INCR16, then reads with
//               an ARADDR that is not aligned to ARSIZE and checks the byte
//               lanes AXI defines as valid:
//               - first beat (and every FIXED beat): from the ARADDR byte to
//                 the end of its ARSIZE container;
//               - later INCR beats: the whole aligned container.
//               The scoreboard checks the aligned HADDR and HSIZE per beat.
//               Full-width cases run on every build; narrow ARSIZE cases run
//               only when narrow support is enabled.
//               Covers BRG_SIZ_005.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_unaligned_read_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_unaligned_read_seq)

    localparam int unsigned FULL_SIZE     = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BG_BEATS      = 16;   // background INCR16

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h1000;
    int unsigned              case_stride   = 'h100;
    bit                       enable_narrow = 1'b0;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    int unsigned unaligned_cases;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_burst_e burst;
        int unsigned len;         // AXI ARLEN value (beats-1)
        int unsigned size_code;   // ARSIZE code
        int unsigned offset;      // ARADDR byte offset in the case region
        string       label;
    } unaligned_case_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_unaligned_read_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        unaligned_case_t cases[$];

        wait_reset_release();
        validate_knobs();

        build_cases(cases);

        `uvm_info(get_type_name(),
                  $sformatf("Unaligned read: %0d cases, narrow=%0b",
                            cases.size(), enable_narrow),
                  UVM_LOW)
        if (!enable_narrow)
            `uvm_info(get_type_name(),
                      "Narrow unaligned-read cases disabled by test configuration",
                      UVM_LOW)

        foreach (cases[i])
            run_case(i, cases[i]);

        `uvm_info(get_type_name(),
                  $sformatf("Unaligned read summary: run=%0d failed=%0d unaligned=%0d",
                            cases_run, cases_failed, unaligned_cases),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    // Every byte offset in the first bus word. Offsets that are multiples of
    // the transfer size are aligned reference cases.
    protected function void build_cases(ref unaligned_case_t cases[$]);
        add_size_cases(cases, FULL_SIZE);
        if (!enable_narrow)
            return;
        // 1-byte transfers are always aligned
        for (int unsigned size_code = 1; size_code < FULL_SIZE; size_code++)
            add_size_cases(cases, size_code);
    endfunction : build_cases

    protected function void add_size_cases(
        ref unaligned_case_t cases[$],
        input int unsigned size_code
    );
        string tag;

        tag = (size_code == FULL_SIZE) ? "FULL" : $sformatf("%0dB", 1 << size_code);
        for (int unsigned offset = 0; offset < AXI4_STRB_WIDTH; offset++) begin
            // Narrow sizes: only unaligned offsets (aligned ones are covered
            // by bridge_size_mapping_test)
            if ((size_code != FULL_SIZE) && ((offset % (1 << size_code)) == 0))
                continue;
            cases.push_back('{AXI4_BURST_INCR,  0, size_code, offset,
                              $sformatf("SINGLE_%s_OFF%0d", tag, offset)});
            cases.push_back('{AXI4_BURST_INCR,  3, size_code, offset,
                              $sformatf("INCR4_%s_OFF%0d", tag, offset)});
            cases.push_back('{AXI4_BURST_INCR,  4, size_code, offset,
                              $sformatf("INCR5_%s_OFF%0d", tag, offset)});
            cases.push_back('{AXI4_BURST_FIXED, 2, size_code, offset,
                              $sformatf("FIXED3_%s_OFF%0d", tag, offset)});
        end
    endfunction : add_size_cases

    //-------------------------------------------------------------------------
    // Run one case: background write, unaligned read, lane check
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, unaligned_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] region;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
        bit [AXI4_DATA_WIDTH-1:0] expected[];
        bit [AXI4_DATA_WIDTH-1:0] mask[];
        int unsigned              bytes;
        int unsigned              beats;
        axi4_transaction          req;
        axi4_transaction          rsp;

        region = base_addr + (index * case_stride);
        addr   = region + c.offset;
        bytes  = 1 << c.size_code;
        beats  = c.len + 1;
        if ((addr % bytes) != 0)
            unaligned_cases++;

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s ARADDR=0x%0h ARSIZE=%0dB beats=%0d expected first HADDR=0x%0h",
                            index, c.label, addr, bytes, beats,
                            addr - (addr % bytes)),
                  UVM_MEDIUM)

        // Background: aligned full-width INCR16 over the case region
        req = create_request(AXI4_WRITE, region, BG_BEATS - 1, FULL_SIZE,
                             AXI4_BURST_INCR);
        foreach (req.data[i]) begin
            for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
                req.data[i][8*k +: 8] = get_background_byte(
                    index, (i * AXI4_STRB_WIDTH) + k);
            req.strb[i] = '1;
        end
        send_axi_request_wait(req, rsp);
        cases_run++;
        if (rsp.bresp != AXI4_RESP_OKAY) begin
            cases_failed++;
            `uvm_error(get_type_name(),
                       $sformatf("%s background write at 0x%0h: BRESP=%s, expected OKAY",
                                 c.label, region, rsp.bresp.name()))
        end

        // Expected valid lanes and bytes for each read beat (AXI rules)
        expected = new[beats];
        mask     = new[beats];
        for (int unsigned i = 0; i < beats; i++) begin
            bit [AXI4_ADDR_WIDTH-1:0] container;
            int unsigned              first_lane;
            int unsigned              last_lane;

            if ((i == 0) || (c.burst == AXI4_BURST_FIXED))
                beat_addr = addr;
            else
                beat_addr = (addr - (addr % bytes)) + (i * bytes);
            container  = beat_addr - (beat_addr % bytes);
            first_lane = beat_addr % AXI4_STRB_WIDTH;
            last_lane  = (container % AXI4_STRB_WIDTH) + bytes - 1;
            expected[i] = '0;
            mask[i]     = '0;
            for (int unsigned k = first_lane; k <= last_lane; k++) begin
                expected[i][8*k +: 8] = get_background_byte(
                    index, (beat_addr - (beat_addr % AXI4_STRB_WIDTH)) - region + k);
                mask[i][8*k +: 8] = 8'hFF;
            end
        end

        // Unaligned read
        req = create_request(AXI4_READ, addr, c.len, c.size_code, c.burst);
        send_axi_request_wait(req, rsp);
        cases_run++;
        check_read(c.label, addr, rsp, expected, mask);
    endtask : run_case

    // Distinct per region offset and case
    protected function bit [7:0] get_background_byte(
        int unsigned case_index,
        int unsigned region_offset
    );
        return 8'h30 + case_index * 16 + region_offset;
    endfunction : get_background_byte

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len,
        int unsigned              size_code,
        axi4_burst_e              burst
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("unaligned_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::len;
                size     == axi4_size_e'(local::size_code);
                burst    == local::burst;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s %s len=%0d size=%0d addr=0x%0h",
                                 dir.name(), burst.name(), len, size_code, addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Read check (AXI-valid lanes only)
    //-------------------------------------------------------------------------
    protected function void check_read(
        string                    label,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp,
        bit [AXI4_DATA_WIDTH-1:0] expected[],
        bit [AXI4_DATA_WIDTH-1:0] mask[]
    );
        bit failed;

        failed = 1'b0;
        if ((rsp.data.size() != expected.size()) ||
            (rsp.rresp.size() != expected.size())) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s read at 0x%0h: beat count expected=%0d actual=%0d",
                                 label, addr, expected.size(), rsp.data.size()))
        end else begin
            foreach (expected[i]) begin
                if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s read at 0x%0h beat=%0d: RRESP=%s, expected OKAY",
                                         label, addr, i, rsp.rresp[i].name()))
                end
                if ((rsp.data[i] & mask[i]) !== expected[i]) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf({"%s read at 0x%0h beat=%0d: ",
                                          "expected=0x%0h actual=0x%0h mask=0x%0h"},
                                         label, addr, i, expected[i],
                                         rsp.data[i], mask[i]))
                end
            end
        end

        if (failed)
            cases_failed++;
    endfunction : check_read

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // Case regions start on 0x100 boundaries and the background covers every
    // byte a case reads, so no access crosses a 1 KB or 4 KB boundary.
    protected function void validate_knobs();
        if ((base_addr % 'h100) != 0)
            `uvm_fatal(get_type_name(), "base_addr must be a multiple of 0x100")
        if ((case_stride % 'h100) != 0 || (case_stride < BG_BEATS * AXI4_STRB_WIDTH))
            `uvm_fatal(get_type_name(),
                       "case_stride must be a multiple of 0x100 and cover the background")
    endfunction : validate_knobs

endclass : axi4_mst_unaligned_read_seq