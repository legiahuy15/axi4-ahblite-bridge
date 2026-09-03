//=============================================================================
// File        : predictor.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 request to AHB-Lite beat predictor.
//               Included inside the bridge package.
//=============================================================================

`uvm_analysis_imp_decl(_axi_request)

class predictor extends uvm_component;

    `uvm_component_utils(predictor)

    //-------------------------------------------------------------------------
    // Analysis interfaces
    //-------------------------------------------------------------------------
    uvm_analysis_imp_axi_request #(axi4_transaction, predictor)
        axi_request_export;
    uvm_analysis_port #(ahb_transfer)     expected_ahb_ap;
    uvm_analysis_port #(axi4_transaction) expected_axi_ap;

    //-------------------------------------------------------------------------
    // Request scheduling state
    //-------------------------------------------------------------------------
    protected predictor_req_entry request_queue[$];

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
        axi_request_export = new("axi_request_export", this);
        expected_ahb_ap    = new("expected_ahb_ap", this);
        expected_axi_ap    = new("expected_axi_ap", this);

        if (AXI4_ADDR_WIDTH != AHB_ADDR_WIDTH)
            `uvm_fatal(get_type_name(), "AXI4 and AHB-Lite address widths differ")
        if (AXI4_DATA_WIDTH != AHB_DATA_WIDTH)
            `uvm_fatal(get_type_name(), "AXI4 and AHB-Lite data widths differ")
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        forever begin
            wait (request_queue.size() > 0);
            #0;
            process_request_batch();
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // AXI request input
    //-------------------------------------------------------------------------
    function void write_axi_request(axi4_transaction tr);
        axi4_transaction             copy_tr;
        predictor_req_entry entry;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "AXI4 request clone failed")
        entry = new(copy_tr, $time);
        request_queue.push_back(entry);
    endfunction : write_axi_request

    //-------------------------------------------------------------------------
    // Same-cycle read priority
    //-------------------------------------------------------------------------
    protected function void process_request_batch();
        predictor_req_entry read_queue[$];
        predictor_req_entry write_queue[$];
        time batch_time;

        if (request_queue.size() == 0)
            return;

        batch_time = request_queue[0].timestamp;
        while ((request_queue.size() > 0) &&
               (request_queue[0].timestamp == batch_time)) begin
            predictor_req_entry entry;

            entry = request_queue.pop_front();
            if (entry.tr.dir == AXI4_READ)
                read_queue.push_back(entry);
            else
                write_queue.push_back(entry);
        end

        foreach (read_queue[i])
            predict_request(read_queue[i].tr);
        foreach (write_queue[i])
            predict_request(write_queue[i].tr);
    endfunction : process_request_batch

    //-------------------------------------------------------------------------
    // Request translation
    //-------------------------------------------------------------------------
    protected function void predict_request(axi4_transaction axi_tr);
        axi4_transaction             axi_copy;
        bit [AXI4_ADDR_WIDTH-1:0]    beat_addr;
        bit [AXI4_ADDR_WIDTH-1:0]    prev_addr;
        axi4_size_e                  effective_size;
        ahb_burst_e                  ahb_burst;
        int unsigned                 beat_count;
        int unsigned                 bytes_per_beat;
        bit                          crosses_1kb;

        if (!$cast(axi_copy, axi_tr.clone()))
            `uvm_fatal(get_type_name(), "Expected AXI template clone failed")
        expected_axi_ap.write(axi_copy);

        beat_count     = int'(axi_tr.len) + 1;
        effective_size = get_effective_size(axi_tr);
        bytes_per_beat = 1 << int'(effective_size);
        beat_addr      = align_address(axi_tr.addr, bytes_per_beat);
        crosses_1kb    = is_1kb_crossing(beat_addr, beat_count,
                                         bytes_per_beat, axi_tr.burst);
        ahb_burst      = get_ahb_burst(axi_tr.burst, beat_count,
                                       crosses_1kb);

        for (int unsigned i = 0; i < beat_count; i++) begin
            ahb_transfer ahb_tr;

            if (i != 0) begin
                prev_addr = beat_addr;
                beat_addr = get_next_address(beat_addr, axi_tr.addr,
                                             axi_tr.burst, beat_count,
                                             bytes_per_beat);
            end

            ahb_tr          = ahb_transfer::type_id::create("expected_ahb_tr");
            ahb_tr.addr     = beat_addr;
            ahb_tr.write    = (axi_tr.dir == AXI4_WRITE) ? AHB_WRITE : AHB_READ;
            ahb_tr.trans    = get_ahb_trans(axi_tr.burst, beat_count, i,
                                            prev_addr, beat_addr);
            ahb_tr.burst    = ahb_burst;
            ahb_tr.size     = ahb_size_e'(effective_size);
            ahb_tr.prot     = get_ahb_prot(axi_tr.cache, axi_tr.prot);
            ahb_tr.mastlock = bit'(axi_tr.lock);
            ahb_tr.wdata    = (axi_tr.dir == AXI4_WRITE) ? axi_tr.data[i] : '0;
            ahb_tr.rdata    = '0;
            ahb_tr.resp     = AHB_RESP_OKAY;
            ahb_tr.wait_cycles = 0;
            expected_ahb_ap.write(ahb_tr);
        end
    endfunction : predict_request

    //-------------------------------------------------------------------------
    // Size and strobe mapping
    //-------------------------------------------------------------------------
    protected function axi4_size_e get_effective_size(axi4_transaction tr);
        bit [AXI4_STRB_WIDTH-1:0] strobe;

        if ((tr.dir != AXI4_WRITE) || (tr.len != 0) ||
            (tr.strb.size() == 0))
            return tr.size;

        strobe = tr.strb[0];
        for (int unsigned size = 0;
             (1 << size) <= AXI4_STRB_WIDTH; size++) begin
            int unsigned byte_count;

            byte_count = 1 << size;
            for (int unsigned lane = 0; lane < AXI4_STRB_WIDTH;
                 lane += byte_count) begin
                bit [AXI4_STRB_WIDTH-1:0] mask;

                mask = '0;
                for (int unsigned i = 0; i < byte_count; i++)
                    mask[lane + i] = 1'b1;
                if (strobe == mask)
                    return axi4_size_e'(size);
            end
        end

        return tr.size;
    endfunction : get_effective_size

    //-------------------------------------------------------------------------
    // Burst mapping
    //-------------------------------------------------------------------------
    protected function ahb_burst_e get_ahb_burst(
        axi4_burst_e axi_burst,
        int unsigned beat_count,
        bit          crosses_1kb
    );
        case (axi_burst)
            AXI4_BURST_FIXED:
                return AHB_BURST_SINGLE;

            AXI4_BURST_INCR: begin
                if (crosses_1kb)
                    return AHB_BURST_INCR;
                case (beat_count)
                    1:       return AHB_BURST_SINGLE;
                    4:       return AHB_BURST_INCR4;
                    8:       return AHB_BURST_INCR8;
                    16:      return AHB_BURST_INCR16;
                    default: return AHB_BURST_INCR;
                endcase
            end

            AXI4_BURST_WRAP: begin
                case (beat_count)
                    2:       return AHB_BURST_SINGLE;
                    4:       return AHB_BURST_WRAP4;
                    8:       return AHB_BURST_WRAP8;
                    16:      return AHB_BURST_WRAP16;
                    default: begin
                        `uvm_error(get_type_name(),
                                   $sformatf("Unsupported AXI WRAP length %0d",
                                             beat_count))
                        return AHB_BURST_SINGLE;
                    end
                endcase
            end
        endcase

        return AHB_BURST_SINGLE;
    endfunction : get_ahb_burst

    protected function ahb_trans_e get_ahb_trans(
        axi4_burst_e               axi_burst,
        int unsigned               beat_count,
        int unsigned               beat_index,
        bit [AXI4_ADDR_WIDTH-1:0]  prev_addr,
        bit [AXI4_ADDR_WIDTH-1:0]  beat_addr
    );
        if (beat_index == 0)
            return AHB_TRANS_NONSEQ;
        if (axi_burst == AXI4_BURST_FIXED)
            return AHB_TRANS_NONSEQ;
        if ((axi_burst == AXI4_BURST_WRAP) && (beat_count == 2))
            return AHB_TRANS_NONSEQ;
        if ((axi_burst == AXI4_BURST_INCR) &&
            ((prev_addr >> 10) != (beat_addr >> 10)))
            return AHB_TRANS_NONSEQ;
        return AHB_TRANS_SEQ;
    endfunction : get_ahb_trans

    //-------------------------------------------------------------------------
    // Address generation
    //-------------------------------------------------------------------------
    protected function bit [AXI4_ADDR_WIDTH-1:0] align_address(
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              byte_count
    );
        return addr - (addr % byte_count);
    endfunction : align_address

    protected function bit [AXI4_ADDR_WIDTH-1:0] get_next_address(
        bit [AXI4_ADDR_WIDTH-1:0] current_addr,
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        axi4_burst_e              burst,
        int unsigned              beat_count,
        int unsigned              byte_count
    );
        bit [AXI4_ADDR_WIDTH-1:0] wrap_base;
        bit [AXI4_ADDR_WIDTH-1:0] next_addr;
        int unsigned              wrap_bytes;

        if (burst == AXI4_BURST_FIXED)
            return current_addr;

        next_addr = current_addr + byte_count;
        if (burst == AXI4_BURST_WRAP) begin
            wrap_bytes = beat_count * byte_count;
            wrap_base  = (start_addr / wrap_bytes) * wrap_bytes;
            if (next_addr >= (wrap_base + wrap_bytes))
                next_addr = wrap_base;
        end
        return next_addr;
    endfunction : get_next_address

    protected function bit is_1kb_crossing(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_count,
        int unsigned              byte_count,
        axi4_burst_e              burst
    );
        bit [AXI4_ADDR_WIDTH:0] end_addr;

        if (burst != AXI4_BURST_INCR)
            return 1'b0;
        end_addr = {1'b0, start_addr} + (beat_count * byte_count) - 1;
        return ((start_addr >> 10) != (end_addr >> 10));
    endfunction : is_1kb_crossing

    //-------------------------------------------------------------------------
    // Protection mapping
    //-------------------------------------------------------------------------
    protected function bit [3:0] get_ahb_prot(
        bit [3:0] cache,
        bit [2:0] prot
    );
        bit [3:0] hprot;

        hprot[3] = 1'b0;
        hprot[2] = cache[0] & ~cache[2] & ~cache[3];
        hprot[1] = prot[0];
        hprot[0] = ~prot[2];
        return hprot;
    endfunction : get_ahb_prot

    //-------------------------------------------------------------------------
    // Reset handling
    //-------------------------------------------------------------------------
    function void reset_state();
        request_queue.delete();
    endfunction : reset_state

endclass : predictor