//=============================================================================
// File        : axi4_mst_sanity_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 single-beat write-read-back sequence.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_sanity_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_sanity_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    int unsigned              num_iter    = 4;
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              addr_stride = AXI4_STRB_WIDTH;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned transfers_checked;
    int unsigned transfers_failed;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_sanity_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        wait_reset_release();
        validate_knobs();

        for (int unsigned i = 0; i < num_iter; i++) begin
            bit [AXI4_ADDR_WIDTH-1:0] target_addr;
            bit [AXI4_DATA_WIDTH-1:0] expected_data;
            axi4_transaction          wr_req;
            axi4_transaction          wr_rsp;
            axi4_transaction          rd_req;
            axi4_transaction          rd_rsp;

            target_addr   = base_addr + (i * addr_stride);
            expected_data = get_data_pattern(i);
            check_address(target_addr);

            wr_req = create_write_request(i, target_addr, expected_data);
            send_axi_request_wait(wr_req, wr_rsp);
            check_write_response(wr_rsp, target_addr);

            rd_req = create_read_request(i, target_addr);
            send_axi_request_wait(rd_req, rd_rsp);
            check_read_response(rd_rsp, target_addr, expected_data);
        end

        `uvm_info(get_type_name(),
                  $sformatf("AXI4 sanity summary: checked=%0d failed=%0d",
                            transfers_checked, transfers_failed), UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction create_write_request(
        int unsigned              index,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        bit [AXI4_DATA_WIDTH-1:0] data
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("wr_req_%0d", index));
        if (!req.randomize() with {
                dir      == AXI4_WRITE;
                id       inside {[local::id_lo:local::id_hi]};
                addr     == local::addr;
                len      == 0;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
                data[0]  == local::data;
                strb[0]  == '1;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Write request randomization failed at 0x%0h",
                                 addr))
        return req;
    endfunction : create_write_request

    protected function axi4_transaction create_read_request(
        int unsigned              index,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;

        req = axi4_transaction::type_id::create(
                  $sformatf("rd_req_%0d", index));
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
                       $sformatf("Read request randomization failed at 0x%0h",
                                 addr))
        return req;
    endfunction : create_read_request

    //-------------------------------------------------------------------------
    // Response checks
    //-------------------------------------------------------------------------
    protected function void check_write_response(
        axi4_transaction          rsp,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        transfers_checked++;
        if (rsp.bresp != AXI4_RESP_OKAY) begin
            transfers_failed++;
            `uvm_error(get_type_name(),
                       $sformatf("Write failed at 0x%0h: BRESP=%s",
                                 addr, rsp.bresp.name()))
        end
    endfunction : check_write_response

    protected function void check_read_response(
        axi4_transaction          rsp,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        bit [AXI4_DATA_WIDTH-1:0] expected_data
    );
        bit failed;

        transfers_checked++;
        failed = 1'b0;
        if ((rsp.data.size() != 1) || (rsp.rresp.size() != 1)) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf("Invalid read response size at 0x%0h", addr))
        end else begin
            if (rsp.rresp[0] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("Read failed at 0x%0h: RRESP=%s",
                                     addr, rsp.rresp[0].name()))
            end
            if (rsp.data[0] !== expected_data) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"Read data mismatch at 0x%0h: ",
                                      "expected=0x%0h actual=0x%0h"},
                                     addr, expected_data, rsp.data[0]))
            end
        end

        if (failed)
            transfers_failed++;
    endfunction : check_read_response

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    protected function void validate_knobs();
        if (num_iter == 0)
            `uvm_fatal(get_type_name(), "num_iter must be greater than zero")
        if (addr_stride < AXI4_STRB_WIDTH)
            `uvm_fatal(get_type_name(), "addr_stride is smaller than bus width")
        if ((addr_stride % AXI4_STRB_WIDTH) != 0)
            `uvm_fatal(get_type_name(), "addr_stride is not bus aligned")
        if ((base_addr % AXI4_STRB_WIDTH) != 0)
            `uvm_fatal(get_type_name(), "base_addr is not bus aligned")
        if (id_lo > id_hi)
            `uvm_fatal(get_type_name(), "Invalid AXI4 ID range")
        if (addr_lo > addr_hi)
            `uvm_fatal(get_type_name(), "Invalid AXI4 address range")
    endfunction : validate_knobs

    protected function void check_address(
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        if ((addr < addr_lo) || (addr > addr_hi))
            `uvm_fatal(get_type_name(),
                       $sformatf("Address 0x%0h is outside the sequence range",
                                 addr))
    endfunction : check_address

    //-------------------------------------------------------------------------
    // Data pattern
    //-------------------------------------------------------------------------
    protected function bit [AXI4_DATA_WIDTH-1:0] get_data_pattern(
        int unsigned index
    );
        bit [AXI4_DATA_WIDTH-1:0] pattern;

        pattern = '0;
        for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH; lane++)
            pattern[(8 * lane) +: 8] = 8'hA0 + index + lane;
        return pattern;
    endfunction : get_data_pattern

endclass : axi4_mst_sanity_seq
