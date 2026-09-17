//=============================================================================
// File        : axi4_mst_lock_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 unsupported-lock directed sequence.
//               Interleaves AxLOCK=1 and AxLOCK=0 requests for read and
//               write across the burst mappings and checks that locked
//               requests complete normally with OKAY (never EXOKAY) and
//               correct data. HMASTLOCK is checked per beat by the
//               scoreboard.
//               Covers BRG_UNS_001.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_lock_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_lock_seq)

    localparam int unsigned FULL_SIZE      = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BYTES_PER_BEAT = AXI4_STRB_WIDTH;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

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
        int unsigned len;       // AXI AxLEN value (beats-1)
        string       label;
    } lock_entry_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_lock_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        lock_entry_t entries[$];

        wait_reset_release();
        validate_knobs();

        build_entries(entries);

        `uvm_info(get_type_name(),
                  $sformatf("Unsupported lock: %0d burst entries", entries.size()),
                  UVM_LOW)

        foreach (entries[i])
            run_lock_case(i, entries[i]);

        `uvm_info(get_type_name(),
                  $sformatf("Unsupported lock summary: run=%0d failed=%0d",
                            cases_run, cases_failed), UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Build the burst entries (one per AHB mapping class)
    //-------------------------------------------------------------------------
    protected function void build_entries(ref lock_entry_t entries[$]);
        entries.push_back('{AXI4_BURST_INCR,  0, "INCR1_SINGLE"});
        entries.push_back('{AXI4_BURST_INCR,  3, "INCR4"});
        entries.push_back('{AXI4_BURST_INCR,  4, "INCR5_UNDEF"});
        entries.push_back('{AXI4_BURST_FIXED, 2, "FIXED3"});
        entries.push_back('{AXI4_BURST_WRAP,  1, "WRAP2"});
        entries.push_back('{AXI4_BURST_WRAP,  3, "WRAP4"});
    endfunction : build_entries

    //-------------------------------------------------------------------------
    // Run one entry
    //-------------------------------------------------------------------------
    // Locked write, normal read-back, normal write, then two back-to-back
    // locked read-backs, so HMASTLOCK is checked on 0->1, 1->0 and 1->1
    // transitions between transactions.
    protected task run_lock_case(int unsigned index, lock_entry_t entry);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [AXI4_DATA_WIDTH-1:0] expected[];

        addr = base_addr + (index * case_stride);
        addr = (addr / BYTES_PER_BEAT) * BYTES_PER_BEAT;

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s addr=0x%0h beats=%0d",
                            index, entry.label, addr, entry.len + 1),
                  UVM_MEDIUM)

        run_write(index, 0, entry, addr, AXI4_LOCK_EXCLUSIVE, expected);
        run_read(index, entry, addr, AXI4_LOCK_NORMAL, expected);
        run_write(index, 1, entry, addr, AXI4_LOCK_NORMAL, expected);
        run_read(index, entry, addr, AXI4_LOCK_EXCLUSIVE, expected);
        run_read(index, entry, addr, AXI4_LOCK_EXCLUSIVE, expected);
    endtask : run_lock_case

    protected task run_write(
        int unsigned                     index,
        int unsigned                     pass,
        lock_entry_t                     entry,
        bit [AXI4_ADDR_WIDTH-1:0]        addr,
        axi4_lock_e                      lock,
        output bit [AXI4_DATA_WIDTH-1:0] expected[]
    );
        axi4_transaction req;
        axi4_transaction rsp;
        string           tag;
        int unsigned     beats;

        beats = entry.len + 1;
        tag   = $sformatf("%s_%s_WR", entry.label, lock.name());
        req   = create_request(AXI4_WRITE, addr, entry, lock);
        foreach (req.data[i]) begin
            req.data[i] = get_data_pattern(index, pass, i);
            req.strb[i] = '1;
        end

        send_axi_request_wait(req, rsp);
        cases_run++;
        if (rsp.bresp != AXI4_RESP_OKAY) begin
            cases_failed++;
            `uvm_error(get_type_name(),
                       $sformatf("%s at 0x%0h: BRESP=%s, expected OKAY",
                                 tag, addr, rsp.bresp.name()))
        end

        // FIXED writes every beat to one address, so the last beat remains
        expected = new[beats];
        foreach (expected[i])
            expected[i] = (entry.burst == AXI4_BURST_FIXED) ?
                              req.data[beats - 1] : req.data[i];
    endtask : run_write

    protected task run_read(
        int unsigned              index,
        lock_entry_t              entry,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_lock_e               lock,
        bit [AXI4_DATA_WIDTH-1:0] expected[]
    );
        axi4_transaction req;
        axi4_transaction rsp;
        string           tag;
        bit              failed;

        tag = $sformatf("%s_%s_RD", entry.label, lock.name());
        req = create_request(AXI4_READ, addr, entry, lock);
        send_axi_request_wait(req, rsp);
        cases_run++;

        failed = 1'b0;
        if ((rsp.data.size() != expected.size()) ||
            (rsp.rresp.size() != expected.size())) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s at 0x%0h: beat count expected=%0d actual=%0d",
                                 tag, addr, expected.size(), rsp.data.size()))
        end else begin
            foreach (expected[i]) begin
                if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s at 0x%0h beat=%0d: RRESP=%s, expected OKAY",
                                         tag, addr, i, rsp.rresp[i].name()))
                end
                if (rsp.data[i] !== expected[i]) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf({"%s at 0x%0h beat=%0d: ",
                                          "expected=0x%0h actual=0x%0h"},
                                         tag, addr, i, expected[i], rsp.data[i]))
                end
            end
        end

        if (failed)
            cases_failed++;
    endtask : run_read

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        lock_entry_t              entry,
        axi4_lock_e               lock
    );
        axi4_transaction req;
        int unsigned     req_len;
        axi4_burst_e     req_burst;

        req_len   = entry.len;
        req_burst = entry.burst;
        req = axi4_transaction::type_id::create(
                  $sformatf("lock_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == local::req_burst;
                lock     == local::lock;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s %s lock=%s addr=0x%0h",
                                 dir.name(), entry.label, lock.name(), addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Data pattern
    //-------------------------------------------------------------------------
    protected function bit [AXI4_DATA_WIDTH-1:0] get_data_pattern(
        int unsigned case_index,
        int unsigned pass,
        int unsigned beat_index
    );
        bit [AXI4_DATA_WIDTH-1:0] pattern;

        pattern = '0;
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            pattern[8*lane +: 8] = 8'h90 + case_index * 16 + pass * 8 +
                                   beat_index * 2 + lane;
        return pattern;
    endfunction : get_data_pattern

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        if ((base_addr % 'h40) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be aligned to the largest wrap region")
        if ((case_stride < 'h40) || ((case_stride % 'h40) != 0))
            `uvm_fatal(get_type_name(),
                       "case_stride must be a non-zero multiple of 0x40")
    endfunction : validate_knobs

endclass : axi4_mst_lock_seq
