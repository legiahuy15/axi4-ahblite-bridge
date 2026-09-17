//=============================================================================
// File        : axi4_mst_size_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 transfer-size to HSIZE mapping directed sequence.
//               Full width: SINGLE, INCR4, undefined INCR, FIXED, WRAP2 and
//               WRAP4 for read and write (HSIZE = AxSIZE).
//               Narrow (only when enabled): every legal byte lane for each
//               narrow single transfer, single writes whose size is carried
//               only by WSTRB, and the same burst set at each narrow size.
//               Every case writes, then reads back with the same attributes.
//               The scoreboard checks HSIZE/HADDR per beat; this sequence
//               checks responses and the written byte lanes.
//               Covers BRG_SIZ_001 and BRG_SIZ_003.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_size_mapping_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_size_mapping_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

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

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_burst_e burst;
        int unsigned len;         // AXI AxLEN value (beats-1)
        int unsigned size_code;   // transfer size = 1 << size_code bytes
        int unsigned offset;      // start offset inside the case region
        bit          strb_sized;  // AxSIZE is full width; WSTRB carries the size
        string       label;
    } size_case_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_size_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        size_case_t cases[$];

        wait_reset_release();
        validate_knobs();

        build_cases(cases);

        `uvm_info(get_type_name(),
                  $sformatf("Size mapping: %0d cases, narrow=%0b",
                            cases.size(), enable_narrow),
                  UVM_LOW)
        if (!enable_narrow)
            `uvm_info(get_type_name(),
                      "Narrow size-mapping cases disabled by test configuration",
                      UVM_LOW)

        foreach (cases[i])
            run_case(i, cases[i]);

        `uvm_info(get_type_name(),
                  $sformatf("Size mapping summary: run=%0d failed=%0d",
                            cases_run, cases_failed), UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void build_cases(ref size_case_t cases[$]);
        add_size_cases(cases, FULL_SIZE);
        if (!enable_narrow)
            return;
        for (int unsigned size_code = 0; size_code < FULL_SIZE; size_code++)
            add_size_cases(cases, size_code);
    endfunction : build_cases

    protected function void add_size_cases(
        ref size_case_t cases[$],
        input int unsigned size_code
    );
        int unsigned bytes;
        string       tag;

        bytes = 1 << size_code;
        tag   = (size_code == FULL_SIZE) ? "FULL" : $sformatf("%0dB", bytes);

        // Single transfer at every legal byte lane for this size
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane += bytes)
            cases.push_back('{AXI4_BURST_INCR, 0, size_code, lane, 1'b0,
                              $sformatf("SINGLE_%s_LANE%0d", tag, lane)});

        // Narrow single write whose size is given only by WSTRB
        if (size_code != FULL_SIZE)
            cases.push_back('{AXI4_BURST_INCR, 0, size_code, 0, 1'b1,
                              $sformatf("SINGLE_%s_WSTRB_ONLY", tag)});

        // Bursts: HSIZE follows AxSIZE. Start offsets make INCR cross a
        // bus-word boundary for narrow sizes and make WRAP wrap immediately.
        cases.push_back('{AXI4_BURST_INCR,  3, size_code, bytes, 1'b0,
                          $sformatf("INCR4_%s", tag)});
        cases.push_back('{AXI4_BURST_INCR,  4, size_code, 0, 1'b0,
                          $sformatf("INCR5_%s", tag)});
        cases.push_back('{AXI4_BURST_FIXED, 2, size_code,
                          AXI4_STRB_WIDTH - bytes, 1'b0,
                          $sformatf("FIXED3_%s", tag)});
        cases.push_back('{AXI4_BURST_WRAP,  1, size_code, bytes, 1'b0,
                          $sformatf("WRAP2_%s", tag)});
        cases.push_back('{AXI4_BURST_WRAP,  3, size_code, 3 * bytes, 1'b0,
                          $sformatf("WRAP4_%s", tag)});
    endfunction : add_size_cases

    //-------------------------------------------------------------------------
    // Run one case: write, then read back with the same attributes
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, size_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [AXI4_ADDR_WIDTH-1:0] beat_addr[];
        bit [AXI4_DATA_WIDTH-1:0] expected[];
        bit [AXI4_DATA_WIDTH-1:0] mask[];
        axi4_transaction          wr_req;
        axi4_transaction          wr_rsp;
        axi4_transaction          rd_req;
        axi4_transaction          rd_rsp;
        int unsigned              req_size;
        int unsigned              beats;

        beats    = c.len + 1;
        addr     = base_addr + (index * case_stride) + c.offset;
        req_size = c.strb_sized ? FULL_SIZE : c.size_code;
        get_beat_addresses(addr, c, beat_addr);

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s addr=0x%0h beats=%0d AxSIZE=%0dB expected HSIZE=%0dB",
                            index, c.label, addr, beats, 1 << req_size,
                            1 << c.size_code),
                  UVM_MEDIUM)

        // Write
        wr_req = create_request(AXI4_WRITE, addr, c, req_size);
        foreach (wr_req.data[i]) begin
            bit [AXI4_DATA_WIDTH-1:0] data;
            bit [AXI4_STRB_WIDTH-1:0] strb;

            get_beat_data(index, i, beat_addr[i], c.size_code, data, strb);
            wr_req.data[i] = data;
            wr_req.strb[i] = strb;
        end
        send_axi_request_wait(wr_req, wr_rsp);
        cases_run++;
        if (wr_rsp.bresp != AXI4_RESP_OKAY) begin
            cases_failed++;
            `uvm_error(get_type_name(),
                       $sformatf("%s write at 0x%0h: BRESP=%s, expected OKAY",
                                 c.label, addr, wr_rsp.bresp.name()))
        end

        // FIXED writes every beat to one address, so the last beat remains
        expected = new[beats];
        mask     = new[beats];
        foreach (expected[i]) begin
            int unsigned src;

            src         = (c.burst == AXI4_BURST_FIXED) ? beats - 1 : i;
            expected[i] = wr_req.data[src];
            mask[i]     = get_lane_mask(wr_req.strb[src]);
        end

        // Read back
        rd_req = create_request(AXI4_READ, addr, c, req_size);
        send_axi_request_wait(rd_req, rd_rsp);
        cases_run++;
        check_readback(c.label, addr, rd_rsp, expected, mask);
    endtask : run_case

    //-------------------------------------------------------------------------
    // Beat addresses (AXI burst address rules)
    //-------------------------------------------------------------------------
    protected function void get_beat_addresses(
        input  bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        input  size_case_t               c,
        output bit [AXI4_ADDR_WIDTH-1:0] beat_addr[]
    );
        int unsigned              bytes;
        int unsigned              beats;
        bit [AXI4_ADDR_WIDTH-1:0] wrap_base;
        bit [AXI4_ADDR_WIDTH-1:0] next_addr;

        bytes     = 1 << c.size_code;
        beats     = c.len + 1;
        wrap_base = start_addr - (start_addr % (beats * bytes));
        beat_addr = new[beats];
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
    // Beat data: active lanes follow the beat address, other lanes carry a
    // filler byte that must never be written to memory
    //-------------------------------------------------------------------------
    protected function void get_beat_data(
        input  int unsigned              case_index,
        input  int unsigned              beat_index,
        input  bit [AXI4_ADDR_WIDTH-1:0] beat_addr,
        input  int unsigned              size_code,
        output bit [AXI4_DATA_WIDTH-1:0] data,
        output bit [AXI4_STRB_WIDTH-1:0] strb
    );
        int unsigned lane_start;

        lane_start = beat_addr % AXI4_STRB_WIDTH;
        strb       = '0;
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            data[8*lane +: 8] = 8'hEE;
        for (int unsigned b = 0; b < (1 << size_code); b++) begin
            int unsigned lane;

            lane = lane_start + b;
            data[8*lane +: 8] = 8'h40 + case_index * 8 + beat_index * 2 + b;
            strb[lane]        = 1'b1;
        end
    endfunction : get_beat_data

    protected function bit [AXI4_DATA_WIDTH-1:0] get_lane_mask(
        bit [AXI4_STRB_WIDTH-1:0] strb
    );
        bit [AXI4_DATA_WIDTH-1:0] mask;

        mask = '0;
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            if (strb[lane])
                mask[8*lane +: 8] = 8'hFF;
        return mask;
    endfunction : get_lane_mask

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        size_case_t               c,
        int unsigned              size_code
    );
        axi4_transaction req;
        int unsigned     req_len;
        axi4_burst_e     req_burst;

        req_len   = c.len;
        req_burst = c.burst;
        req = axi4_transaction::type_id::create(
                  $sformatf("size_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(local::size_code);
                burst    == local::req_burst;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s %s addr=0x%0h",
                                 dir.name(), c.label, addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Read-back check (written lanes only)
    //-------------------------------------------------------------------------
    protected function void check_readback(
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
                if ((rsp.data[i] & mask[i]) !== (expected[i] & mask[i])) begin
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
    endfunction : check_readback

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // Case regions start on 0x100 boundaries and every case fits in 0x100
    // bytes, so no burst crosses a 1 KB or 4 KB boundary.
    protected function void validate_knobs();
        if ((base_addr % 'h100) != 0)
            `uvm_fatal(get_type_name(), "base_addr must be a multiple of 0x100")
        if ((case_stride == 0) || ((case_stride % 'h100) != 0))
            `uvm_fatal(get_type_name(),
                       "case_stride must be a non-zero multiple of 0x100")
    endfunction : validate_knobs

endclass : axi4_mst_size_mapping_seq