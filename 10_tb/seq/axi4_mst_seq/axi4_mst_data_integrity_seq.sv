//=============================================================================
// File        : axi4_mst_data_integrity_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 data-integrity burst and read-back sequence.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_data_integrity_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_data_integrity_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    int unsigned              num_iter       = 5;
    int unsigned              narrow_cases  = 8;
    bit                       enable_narrow = 1'b0;
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h1000;
    bit [AXI4_ADDR_WIDTH-1:0] narrow_base   = 'h8000;
    int unsigned              case_stride   = 'h100;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_checked;
    int unsigned cases_failed;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_data_integrity_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        wait_reset_release();
        validate_knobs();

        for (int unsigned i = 0; i < num_iter; i++) begin
            bit [AXI4_ADDR_WIDTH-1:0] addr;
            int unsigned              len;
            axi4_burst_e              burst;

            addr = base_addr + (i * case_stride);
            case (i % 5)
                0: begin len = 0; burst = AXI4_BURST_INCR;  end
                1: begin len = 3; burst = AXI4_BURST_INCR;  end
                2: begin len = 7; burst = AXI4_BURST_INCR;  end
                3: begin len = 3; burst = AXI4_BURST_WRAP;  end
                default: begin len = 3; burst = AXI4_BURST_FIXED; end
            endcase

            run_integrity_case(i, addr, len, FULL_SIZE, burst, '1,
                               "FULL");
        end

        if (enable_narrow) begin
            for (int unsigned i = 0; i < narrow_cases; i++) begin
                int unsigned              size_code;
                int unsigned              byte_count;
                int unsigned              lane;
                bit [AXI4_STRB_WIDTH-1:0] strobe;
                bit [AXI4_ADDR_WIDTH-1:0] addr;

                size_code = i % FULL_SIZE;
                byte_count = 1 << size_code;
                lane = ((i / FULL_SIZE) % (AXI4_STRB_WIDTH / byte_count)) *
                       byte_count;
                strobe = '0;
                for (int unsigned b = 0; b < byte_count; b++)
                    strobe[lane + b] = 1'b1;

                addr = narrow_base + ((i / FULL_SIZE) * AXI4_STRB_WIDTH) +
                       lane;
                run_integrity_case(num_iter + i, addr, 0, size_code,
                                   AXI4_BURST_INCR, strobe, "NARROW");
            end
        end else begin
            `uvm_info(get_type_name(),
                      "Narrow data-integrity cases disabled by test configuration",
                      UVM_LOW)
        end

        `uvm_info(get_type_name(),
                  $sformatf({"Data-integrity summary: checked=%0d ",
                             "failed=%0d"}, cases_checked, cases_failed),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Integrity case
    //-------------------------------------------------------------------------
    protected task run_integrity_case(
        int unsigned              index,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len,
        int unsigned              size_code,
        axi4_burst_e              burst,
        bit [AXI4_STRB_WIDTH-1:0] strobe,
        string                    kind
    );
        axi4_transaction              wr_req;
        axi4_transaction              wr_rsp;
        axi4_transaction              rd_req;
        axi4_transaction              rd_rsp;
        bit [AXI4_DATA_WIDTH-1:0]     expected_data[];
        bit [AXI4_DATA_WIDTH-1:0]     expected_mask[];
        int unsigned                  beats;

        beats = len + 1;
        wr_req = create_write_request(index, addr, len, size_code, burst,
                                      strobe);
        expected_data = new[beats];
        expected_mask = new[beats];
        foreach (expected_data[i]) begin
            expected_data[i] = wr_req.data[i];
            expected_mask[i] = '1;
        end

        send_axi_request_wait(wr_req, wr_rsp);
        cases_checked++;
        if (wr_rsp.bresp != AXI4_RESP_OKAY) begin
            cases_failed++;
            `uvm_error(get_type_name(),
                       $sformatf("%s write failed: addr=0x%0h BRESP=%s",
                                 kind, addr, wr_rsp.bresp.name()))
        end

        if ((len == 0) && (size_code != FULL_SIZE)) begin
            // Only strobed lanes were written; other lanes hold unrelated data
            expected_mask[0] = '0;
            for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++) begin
                if (strobe[lane])
                    expected_mask[0][8*lane +: 8] = 8'hFF;
            end
        end else if (burst == AXI4_BURST_FIXED) begin
            foreach (expected_data[i])
                expected_data[i] = wr_req.data[beats - 1];
        end

        rd_req = create_read_request(index, addr, len, size_code, burst);
        send_axi_request_wait(rd_req, rd_rsp);
        check_read_response(kind, addr, rd_rsp, expected_data, expected_mask);
    endtask : run_integrity_case

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_write_request(
        int unsigned              index,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len,
        int unsigned              size_code,
        axi4_burst_e              burst,
        bit [AXI4_STRB_WIDTH-1:0] strobe
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("integrity_wr_%0d", index));
        if (!req.randomize() with {
                dir      == AXI4_WRITE;
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
                       $sformatf("Write randomization failed at 0x%0h", addr))

        foreach (req.data[i]) begin
            req.data[i] = get_data_pattern(index, i);
            req.strb[i] = strobe;
        end
        return req;
    endfunction : create_write_request

    protected function axi4_transaction create_read_request(
        int unsigned              index,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len,
        int unsigned              size_code,
        axi4_burst_e              burst
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("integrity_rd_%0d", index));
        if (!req.randomize() with {
                dir      == AXI4_READ;
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
                       $sformatf("Read randomization failed at 0x%0h", addr))
        return req;
    endfunction : create_read_request

    //-------------------------------------------------------------------------
    // Response checking
    //-------------------------------------------------------------------------
    protected function void check_read_response(
        string                    kind,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp,
        bit [AXI4_DATA_WIDTH-1:0] expected_data[],
        bit [AXI4_DATA_WIDTH-1:0] expected_mask[]
    );
        bit failed;

        failed = 1'b0;
        if (rsp.data.size() != expected_data.size() ||
            rsp.rresp.size() != expected_data.size()) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s read size mismatch at 0x%0h: ",
                                  "expected=%0d actual=%0d"},
                                 kind, addr, expected_data.size(),
                                 rsp.data.size()))
        end else begin
            foreach (expected_data[i]) begin
                if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s read response error at 0x%0h beat=%0d: %s",
                                         kind, addr, i, rsp.rresp[i].name()))
                end
                if ((rsp.data[i] & expected_mask[i]) !==
                    (expected_data[i] & expected_mask[i])) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf({"%s data mismatch at 0x%0h beat=%0d: ",
                                          "expected=0x%0h actual=0x%0h ",
                                          "mask=0x%0h"},
                                         kind, addr, i, expected_data[i],
                                         rsp.data[i], expected_mask[i]))
                end
            end
        end

        cases_checked++;
        if (failed)
            cases_failed++;
    endfunction : check_read_response

    //-------------------------------------------------------------------------
    // Helpers
    //-------------------------------------------------------------------------
    protected function bit [AXI4_DATA_WIDTH-1:0] get_data_pattern(
        int unsigned case_index,
        int unsigned beat_index
    );
        bit [AXI4_DATA_WIDTH-1:0] pattern;

        pattern = '0;
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            pattern[8*lane +: 8] = 8'h20 + case_index * 8 +
                                   beat_index * 4 + lane;
        return pattern;
    endfunction : get_data_pattern

    protected function void validate_knobs();
        if (num_iter == 0)
            `uvm_fatal(get_type_name(), "num_iter must be greater than zero")
        if ((enable_narrow) && (FULL_SIZE == 0))
            `uvm_fatal(get_type_name(), "No narrow AXI4 size is available")
        if (case_stride < AXI4_STRB_WIDTH)
            `uvm_fatal(get_type_name(), "case_stride is smaller than bus width")
        if ((base_addr % AXI4_STRB_WIDTH) != 0)
            `uvm_fatal(get_type_name(), "base_addr is not bus aligned")
    endfunction : validate_knobs

endclass : axi4_mst_data_integrity_seq