//=============================================================================
// File        : axi4_mst_protection_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AxCACHE/AxPROT to HPROT mapping directed sequence.
//               PG177 Table 3-1:
//                 HPROT[3] = 0                                  (non-cacheable)
//                 HPROT[2] = AxCACHE[0] & ~AxCACHE[2] & ~AxCACHE[3]
//                 HPROT[1] = AxPROT[0]                          (privileged)
//                 HPROT[0] = ~AxPROT[2]                         (data)
//               Every non-reserved AxCACHE x every AxPROT (single write and
//               read-back), plus INCR4 per AxPROT with bufferable and
//               non-bufferable AxCACHE.
//               Covers BRG_ATT_001 to BRG_ATT_004.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_protection_mapping_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_protection_mapping_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h20;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;
    bit          hprot_seen[bit [3:0]];

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        bit [3:0]    cache;
        bit [2:0]    prot;
        int unsigned len;     // AXI AxLEN value (beats-1)
        string       label;
    } prot_case_t;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_protection_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        prot_case_t cases[$];
        string      hprot_list;

        wait_reset_release();
        validate_knobs();

        build_cases(cases);

        `uvm_info(get_type_name(),
                  $sformatf("Protection mapping: %0d cases", cases.size()),
                  UVM_LOW)

        foreach (cases[i])
            run_case(i, cases[i]);

        hprot_list = "";
        foreach (hprot_seen[v])
            hprot_list = {hprot_list, $sformatf(" %04b", v)};
        `uvm_info(get_type_name(),
                  $sformatf("Protection mapping summary: run=%0d failed=%0d hprot_values=%0d [%s ]",
                            cases_run, cases_failed, hprot_seen.num(),
                            hprot_list),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void build_cases(ref prot_case_t cases[$]);
        // AXI4 AxCACHE encodings that are not reserved (IHI0022E Table A4-5)
        bit [3:0] legal_cache[] = '{4'b0000, 4'b0001, 4'b0010, 4'b0011,
                                    4'b0110, 4'b0111, 4'b1010, 4'b1011,
                                    4'b1110, 4'b1111};

        foreach (legal_cache[c])
            for (int unsigned p = 0; p < 8; p++)
                cases.push_back('{legal_cache[c], p[2:0], 0,
                                  $sformatf("SINGLE_CACHE%04b_PROT%03b",
                                            legal_cache[c], p[2:0])});

        // Every AxPROT on a burst with a bufferable and a non-bufferable
        // AxCACHE
        for (int unsigned p = 0; p < 8; p++) begin
            cases.push_back('{4'b0011, p[2:0], 3,
                              $sformatf("INCR4_CACHE0011_PROT%03b", p[2:0])});
            cases.push_back('{4'b0010, p[2:0], 3,
                              $sformatf("INCR4_CACHE0010_PROT%03b", p[2:0])});
        end
    endfunction : build_cases

    //-------------------------------------------------------------------------
    // Run one case: write, then read back with the same attributes
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, prot_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [3:0]                 hprot;
        axi4_transaction          wr_req;
        axi4_transaction          wr_rsp;
        axi4_transaction          rd_req;
        axi4_transaction          rd_rsp;
        bit                       failed;

        addr  = base_addr + (index * case_stride);
        hprot = get_expected_hprot(c.cache, c.prot);
        hprot_seen[hprot] = 1'b1;

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s addr=0x%0h beats=%0d expected HPROT=%04b",
                            index, c.label, addr, c.len + 1, hprot),
                  UVM_MEDIUM)

        wr_req = create_request(AXI4_WRITE, addr, c);
        foreach (wr_req.data[i]) begin
            for (int unsigned k = 0; k < AXI4_STRB_WIDTH; k++)
                wr_req.data[i][8*k +: 8] = 8'h10 + index * 4 + i * 16 + k;
            wr_req.strb[i] = '1;
        end
        send_axi_request_wait(wr_req, wr_rsp);
        cases_run++;
        failed = 1'b0;
        if (wr_rsp.bresp != AXI4_RESP_OKAY) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s write at 0x%0h: BRESP=%s, expected OKAY",
                                 c.label, addr, wr_rsp.bresp.name()))
        end

        rd_req = create_request(AXI4_READ, addr, c);
        send_axi_request_wait(rd_req, rd_rsp);
        cases_run++;
        if ((rd_rsp.data.size() != wr_req.data.size()) ||
            (rd_rsp.rresp.size() != wr_req.data.size())) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s read at 0x%0h: beat count expected=%0d actual=%0d",
                                 c.label, addr, wr_req.data.size(),
                                 rd_rsp.data.size()))
        end else begin
            foreach (rd_rsp.data[i]) begin
                if (rd_rsp.rresp[i] != AXI4_RESP_OKAY) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s read at 0x%0h beat=%0d: RRESP=%s, expected OKAY",
                                         c.label, addr, i, rd_rsp.rresp[i].name()))
                end
                if (rd_rsp.data[i] !== wr_req.data[i]) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s read at 0x%0h beat=%0d: expected=0x%0h actual=0x%0h",
                                         c.label, addr, i, wr_req.data[i],
                                         rd_rsp.data[i]))
                end
            end
        end

        if (failed)
            cases_failed++;
    endtask : run_case

    // Reference PG177 Table 3-1 mapping, for logging and summary
    protected function bit [3:0] get_expected_hprot(
        bit [3:0] cache,
        bit [2:0] prot
    );
        bit [3:0] hprot;

        hprot[3] = 1'b0;
        hprot[2] = cache[0] & ~cache[2] & ~cache[3];
        hprot[1] = prot[0];
        hprot[0] = ~prot[2];
        return hprot;
    endfunction : get_expected_hprot

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        prot_case_t               c
    );
        axi4_transaction req;
        int unsigned     req_len;
        bit [3:0]        req_cache;
        bit [2:0]        req_prot;

        req_len   = c.len;
        req_cache = c.cache;
        req_prot  = c.prot;
        req = axi4_transaction::type_id::create(
                  $sformatf("prot_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", cases_run));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == local::req_cache;
                prot     == local::req_prot;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s %s addr=0x%0h",
                                 dir.name(), c.label, addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // One region per case, no 1 KB crossing
    protected function void validate_knobs();
        int unsigned burst_bytes;

        burst_bytes = 4 * AXI4_STRB_WIDTH;
        if ((case_stride < burst_bytes) || ((case_stride % burst_bytes) != 0))
            `uvm_fatal(get_type_name(),
                       $sformatf("case_stride must be a non-zero multiple of %0d bytes",
                                 burst_bytes))
        if ((base_addr % burst_bytes) != 0)
            `uvm_fatal(get_type_name(),
                       $sformatf("base_addr must be a multiple of %0d bytes",
                                 burst_bytes))
    endfunction : validate_knobs

endclass : axi4_mst_protection_mapping_seq