//=============================================================================
// File        : axi4_mst_fixed_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 FIXED burst mapping directed sequence.
//               Verifies that each beat of an AXI FIXED burst becomes
//               an AHB SINGLE/NONSEQ transfer at the same address.
//               Covers BRG_BST_006.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_fixed_mapping_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_fixed_mapping_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h1000;
    int unsigned              case_stride   = 'h100;
    int unsigned              random_cases  = 4;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned cases_failed;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_fixed_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        int unsigned fixed_lens[$];

        wait_reset_release();
        validate_knobs();

        // Directed lengths: 1 beat (len=0) and 16 beats (len=15)
        fixed_lens.push_back(0);
        fixed_lens.push_back(15);

        // Random intermediate lengths (FIXED max AxLEN is 15)
        for (int unsigned i = 0; i < random_cases; i++) begin
            int unsigned rnd_len;
            rnd_len = $urandom_range(14, 1);   // 2..15 beats
            fixed_lens.push_back(rnd_len);
        end

        `uvm_info(get_type_name(),
                  $sformatf("FIXED mapping: %0d length entries",
                            fixed_lens.size()),
                  UVM_LOW)

        foreach (fixed_lens[i]) begin
            run_fixed_case(AXI4_WRITE, fixed_lens[i], i);
            run_fixed_case(AXI4_READ,  fixed_lens[i], i);
        end

        `uvm_info(get_type_name(),
                  $sformatf("FIXED mapping summary: run=%0d failed=%0d",
                            cases_run, cases_failed), UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Run a single FIXED case
    //-------------------------------------------------------------------------
    protected task run_fixed_case(
        axi4_dir_e   dir,
        int unsigned len,
        int unsigned entry_index
    );
        axi4_transaction              req;
        axi4_transaction              rsp;
        bit [AXI4_ADDR_WIDTH-1:0]     addr;
        int unsigned                  beats;
        string                        tag;

        beats = len + 1;
        addr  = compute_address(entry_index);
        tag   = $sformatf("FIXED_%0dbeat_%s", beats,
                          (dir == AXI4_WRITE) ? "WR" : "RD");

        `uvm_info(get_type_name(),
                  $sformatf("[%0d] %s addr=0x%0h beats=%0d",
                            cases_run, tag, addr, beats),
                  UVM_MEDIUM)

        if (dir == AXI4_WRITE) begin
            // Write: all beats to the same address, last beat wins
            req = create_request(cases_run, AXI4_WRITE, addr, len);
            fill_write_data(req, entry_index);
            send_axi_request_wait(req, rsp);
            cases_run++;
            if (rsp.bresp != AXI4_RESP_OKAY) begin
                cases_failed++;
                `uvm_error(get_type_name(),
                           $sformatf("%s write BRESP=%s at 0x%0h",
                                     tag, rsp.bresp.name(), addr))
            end

            // FIXED keeps only the last beat: read back one beat
            begin
                axi4_transaction rd_req, rd_rsp;
                bit [AXI4_DATA_WIDTH-1:0] last_data;

                last_data = req.data[beats - 1];
                rd_req = create_request(cases_run, AXI4_READ, addr, 0);
                send_axi_request_wait(rd_req, rd_rsp);
                cases_run++;
                check_single_readback(tag, addr, rd_rsp, last_data);
            end
        end else begin
            // Read: one AHB SINGLE/NONSEQ per beat at the same address
            req = create_request(cases_run, AXI4_READ, addr, len);
            send_axi_request_wait(req, rsp);
            cases_run++;
            check_read_resp(tag, addr, rsp, beats);
        end
    endtask : run_fixed_case

    //-------------------------------------------------------------------------
    // Address computation
    //-------------------------------------------------------------------------
    protected function bit [AXI4_ADDR_WIDTH-1:0] compute_address(
        int unsigned index
    );
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        int unsigned              byte_per_beat;

        byte_per_beat = 1 << FULL_SIZE;
        addr = base_addr + (index * case_stride);
        // Align to transfer size
        addr = (addr / byte_per_beat) * byte_per_beat;
        return addr;
    endfunction : compute_address

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_request(
        int unsigned              seq_num,
        axi4_dir_e                dir,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("fixed_%s_%0d",
                            (dir == AXI4_WRITE) ? "wr" : "rd", seq_num));
        if (!req.randomize() with {
                dir      == local::dir;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == local::len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_FIXED;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Randomization failed: %s FIXED len=%0d addr=0x%0h",
                                 dir.name(), len, addr))
        return req;
    endfunction : create_request

    //-------------------------------------------------------------------------
    // Fill write data with recognizable per-beat patterns
    //-------------------------------------------------------------------------
    protected function void fill_write_data(
        axi4_transaction req,
        int unsigned     case_index
    );
        foreach (req.data[i]) begin
            req.data[i] = get_data_pattern(case_index, i);
            req.strb[i] = '1;
        end
    endfunction : fill_write_data

    protected function bit [AXI4_DATA_WIDTH-1:0] get_data_pattern(
        int unsigned case_index,
        int unsigned beat_index
    );
        bit [AXI4_DATA_WIDTH-1:0] pattern;

        pattern = '0;
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            pattern[8*lane +: 8] = 8'hD0 + case_index * 4 +
                                   beat_index * 2 + lane;
        return pattern;
    endfunction : get_data_pattern

    //-------------------------------------------------------------------------
    // Response checking
    //-------------------------------------------------------------------------
    protected function void check_single_readback(
        string                    tag,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp,
        bit [AXI4_DATA_WIDTH-1:0] expected_data
    );
        bit failed;

        failed = 1'b0;
        if (rsp.data.size() != 1 || rsp.rresp.size() != 1) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s readback size mismatch at 0x%0h: expected=1 actual=%0d",
                                 tag, addr, rsp.data.size()))
        end else begin
            if (rsp.rresp[0] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("%s readback RRESP error at 0x%0h: %s",
                                     tag, addr, rsp.rresp[0].name()))
            end
            if (rsp.data[0] !== expected_data) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s readback data mismatch at 0x%0h: ",
                                      "expected=0x%0h actual=0x%0h"},
                                     tag, addr, expected_data, rsp.data[0]))
            end
        end

        if (failed)
            cases_failed++;
    endfunction : check_single_readback

    protected function void check_read_resp(
        string                    tag,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        axi4_transaction          rsp,
        int unsigned              expected_beats
    );
        bit failed;

        failed = 1'b0;
        if (rsp.data.size() != expected_beats ||
            rsp.rresp.size() != expected_beats) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("%s read beat count mismatch at 0x%0h: expected=%0d actual=%0d",
                                 tag, addr, expected_beats, rsp.data.size()))
        end else begin
            foreach (rsp.rresp[i]) begin
                if (rsp.rresp[i] != AXI4_RESP_OKAY) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf("%s read RRESP error at 0x%0h beat=%0d: %s",
                                         tag, addr, i, rsp.rresp[i].name()))
                end
            end
        end

        if (failed)
            cases_failed++;
    endfunction : check_read_resp

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        if ((base_addr % AXI4_STRB_WIDTH) != 0)
            `uvm_fatal(get_type_name(), "base_addr is not bus aligned")
    endfunction : validate_knobs

endclass : axi4_mst_fixed_mapping_seq