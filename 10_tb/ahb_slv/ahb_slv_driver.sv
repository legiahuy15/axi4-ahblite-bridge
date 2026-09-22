//=============================================================================
// File        : ahb_slv_driver.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Reactive AHB-Lite slave driver and memory model.
//               Included inside the bridge package.
//=============================================================================

class ahb_slv_driver extends uvm_driver #(ahb_slave_response);

    `uvm_component_utils(ahb_slv_driver)

    localparam int unsigned AHB_BYTE_LANES = AHB_DATA_WIDTH / 8;

    //-------------------------------------------------------------------------
    // Configuration and handles
    //-------------------------------------------------------------------------
    ahb_slv_agent_cfg cfg;
    ahb_vif_t         vif;
    ahb_slv_sequencer sqr;

    // Byte-addressable little-endian memory
    protected bit [7:0] mem[bit [AHB_ADDR_WIDTH-1:0]];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(ahb_slv_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal(get_type_name(), "AHB-Lite slave agent config not found")
        vif = cfg.vif;
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        forever begin
            drive_idle();
            if (cfg.clear_mem_on_reset && (vif.rst_n !== 1'b1))
                clear_memory();
            wait_reset_release();

            fork
                serve_bus();
                wait_reset_assertion();
            join_any
            disable fork;

            if (sqr != null)
                sqr.req = null;
            if (cfg.clear_mem_on_reset)
                clear_memory();
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // Request handling
    //-------------------------------------------------------------------------
    protected task serve_bus();
        @(vif.slave_cb);
        forever begin
            ahb_trans_e htrans;

            htrans = ahb_trans_e'(vif.slave_cb.HTRANS);
            if (htrans inside {AHB_TRANS_NONSEQ, AHB_TRANS_SEQ}) begin
                ahb_transfer req;
                int unsigned delay_cycles;
                ahb_resp_e   resp;
                bit [AHB_DATA_WIDTH-1:0] rdata;

                req = capture_request(htrans);
                `uvm_info(get_type_name(),
                          $sformatf({"[DRV][AHB][REQ] %s addr=0x%0h ",
                                     "trans=%s burst=%s size=%0dB"},
                                    req.write.name(), req.addr,
                                    req.trans.name(), req.burst.name(),
                                    1 << int'(req.size)),
                          UVM_HIGH)
                resolve_response(req, delay_cycles, resp, rdata);
                drive_response(req, delay_cycles, resp, rdata);
            end else begin
                vif.slave_cb.HREADY <= 1'b1;
                vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
                @(vif.slave_cb);
            end
        end
    endtask : serve_bus

    protected function ahb_transfer capture_request(ahb_trans_e htrans);
        ahb_transfer req;

        req             = ahb_transfer::type_id::create("req");
        req.addr        = vif.slave_cb.HADDR;
        req.write       = ahb_dir_e'(vif.slave_cb.HWRITE);
        req.trans       = htrans;
        req.burst       = ahb_burst_e'(vif.slave_cb.HBURST);
        req.size        = ahb_size_e'(vif.slave_cb.HSIZE);
        req.prot        = vif.slave_cb.HPROT;
        req.mastlock    = vif.slave_cb.HMASTLOCK;
        req.wdata       = '0;
        req.rdata       = '0;
        req.resp        = AHB_RESP_OKAY;
        req.wait_cycles = 0;
        return req;
    endfunction : capture_request

    protected task resolve_response(
        input  ahb_transfer             req,
        output int unsigned             delay_cycles,
        output ahb_resp_e               resp,
        output bit [AHB_DATA_WIDTH-1:0] rdata
    );
        if ((1 << int'(req.size)) > AHB_BYTE_LANES) begin
            `uvm_error(get_type_name(),
                       $sformatf("HSIZE exceeds AHB data width at address 0x%0h",
                                 req.addr))
            delay_cycles = 0;
            resp         = AHB_RESP_ERROR;
            rdata        = '0;
        end else if (cfg.auto_gen_resp) begin
            delay_cycles = $urandom_range(cfg.ready_delay_max,
                                          cfg.ready_delay_min);
            resp         = AHB_RESP_OKAY;
            rdata        = read_memory_word(req.addr);
        end else begin
            ahb_slave_response rsp;

            if (sqr == null)
                `uvm_fatal(get_type_name(), "Slave sequencer handle is null")

            sqr.req = req;
            vif.slave_cb.HREADY <= 1'b0;
            vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
            seq_item_port.get_next_item(rsp);
            delay_cycles = rsp.ready_delay;
            resp         = rsp.resp;
            rdata        = rsp.rdata;
            seq_item_port.item_done();
            sqr.req = null;
        end
    endtask : resolve_response

    //-------------------------------------------------------------------------
    // Data-phase response
    //-------------------------------------------------------------------------
    protected task drive_response(
        input ahb_transfer             req,
        input int unsigned             delay_cycles,
        input ahb_resp_e               resp,
        input bit [AHB_DATA_WIDTH-1:0] rdata
    );
        bit [AHB_DATA_WIDTH-1:0] transfer_data;

        if (req.write == AHB_READ)
            vif.slave_cb.HRDATA <= rdata;

        repeat (delay_cycles) begin
            vif.slave_cb.HREADY <= 1'b0;
            vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
            @(vif.slave_cb);
        end

        if (resp == AHB_RESP_ERROR) begin
            vif.slave_cb.HREADY <= 1'b0;
            vif.slave_cb.HRESP  <= AHB_RESP_ERROR;
            @(vif.slave_cb);
            vif.slave_cb.HREADY <= 1'b1;
            vif.slave_cb.HRESP  <= AHB_RESP_ERROR;
            @(vif.slave_cb);
        end else begin
            vif.slave_cb.HREADY <= 1'b1;
            vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
            @(vif.slave_cb);

            if (req.write == AHB_WRITE) begin
                transfer_data = vif.slave_cb.HWDATA;
                write_memory_transfer(req.addr, req.size,
                                      transfer_data);
            end
        end

        if (req.write == AHB_READ)
            transfer_data = rdata;
        else if (resp == AHB_RESP_ERROR)
            transfer_data = vif.slave_cb.HWDATA;

        `uvm_info(get_type_name(),
                  $sformatf({"[DRV][AHB][RSP] %s addr=0x%0h data=0x%0h ",
                             "resp=%s ready_delay=%0d"},
                            req.write.name(), req.addr, transfer_data,
                            resp.name(), delay_cycles),
                  UVM_HIGH)
    endtask : drive_response

    //-------------------------------------------------------------------------
    // Internal memory model
    //-------------------------------------------------------------------------
    protected function bit [AHB_DATA_WIDTH-1:0] read_memory_word(
        bit [AHB_ADDR_WIDTH-1:0] addr
    );
        bit [AHB_DATA_WIDTH-1:0] data;
        bit [AHB_ADDR_WIDTH-1:0] base_addr;

        base_addr = addr - (addr % AHB_BYTE_LANES);
        data      = cfg.addr_pattern_read ?
                        get_unwritten_word(base_addr) : cfg.default_read_data;
        for (int unsigned lane = 0; lane < AHB_BYTE_LANES; lane++) begin
            bit [AHB_ADDR_WIDTH-1:0] byte_addr;

            byte_addr = base_addr + lane;
            if (mem.exists(byte_addr))
                data[(8 * lane) +: 8] = mem[byte_addr];
        end
        return data;
    endfunction : read_memory_word

    // Distinct per word address so dropped, repeated or reordered read beats
    // are visible to the scoreboard even without a prior write.
    protected function bit [AHB_DATA_WIDTH-1:0] get_unwritten_word(
        bit [AHB_ADDR_WIDTH-1:0] base_addr
    );
        bit [63:0] addr64;
        bit [63:0] pattern;

        addr64  = base_addr;
        pattern = {addr64[31:0], ~addr64[31:0]};
        return pattern[AHB_DATA_WIDTH-1:0] ^ cfg.default_read_data;
    endfunction : get_unwritten_word

    protected function void write_memory_transfer(
        bit [AHB_ADDR_WIDTH-1:0] addr,
        ahb_size_e               size,
        bit [AHB_DATA_WIDTH-1:0] data
    );
        int unsigned             byte_count;
        int unsigned             lane_offset;
        bit [AHB_ADDR_WIDTH-1:0] byte_addr;

        byte_count = 1 << int'(size);
        lane_offset = int'(addr % AHB_BYTE_LANES);
        if ((lane_offset + byte_count) > AHB_BYTE_LANES) begin
            `uvm_error(get_type_name(),
                       $sformatf("Transfer crosses data-word boundary at 0x%0h", addr))
            return;
        end

        for (int unsigned i = 0; i < byte_count; i++) begin
            byte_addr      = addr + i;
            mem[byte_addr] = data[(8 * (lane_offset + i)) +: 8];
        end
    endfunction : write_memory_transfer

    //-------------------------------------------------------------------------
    // Memory backdoor access
    //-------------------------------------------------------------------------
    function void set_memory_byte(
        bit [AHB_ADDR_WIDTH-1:0] addr,
        bit [7:0]                data
    );
        mem[addr] = data;
    endfunction : set_memory_byte

    function bit [7:0] get_memory_byte(bit [AHB_ADDR_WIDTH-1:0] addr);
        return mem.exists(addr) ? mem[addr] : 8'h00;
    endfunction : get_memory_byte

    function bit memory_byte_exists(bit [AHB_ADDR_WIDTH-1:0] addr);
        return mem.exists(addr);
    endfunction : memory_byte_exists

    function void clear_memory();
        mem.delete();
    endfunction : clear_memory

    //-------------------------------------------------------------------------
    // Reset handling
    //-------------------------------------------------------------------------
    protected task drive_idle();
        @(vif.slave_cb);
        vif.slave_cb.HRDATA <= '0;
        vif.slave_cb.HREADY <= 1'b1;
        vif.slave_cb.HRESP  <= AHB_RESP_OKAY;
    endtask : drive_idle

    protected task wait_reset_release();
        wait (vif.rst_n === 1'b1);
    endtask : wait_reset_release

    protected task wait_reset_assertion();
        forever begin
            @(vif.slave_cb);
            if (vif.rst_n !== 1'b1)
                return;
        end
    endtask : wait_reset_assertion

endclass : ahb_slv_driver