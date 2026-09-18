//=============================================================================
// File        : e2e_cov.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : End-to-end bridge functional coverage.
//               Included inside the bridge package.
//=============================================================================

`uvm_analysis_imp_decl(_e2e_axi_req)
`uvm_analysis_imp_decl(_e2e_expected_ahb)
`uvm_analysis_imp_decl(_e2e_actual_ahb)
`uvm_analysis_imp_decl(_e2e_axi_rsp)

// Response-side correlation state for one predicted AXI request
class e2e_rsp_ctx;

    axi4_transaction tr;
    bit              has_first_beat;  // first predicted AHB beat recorded
    ahb_dir_e        first_write;
    bit [AHB_ADDR_WIDTH-1:0] first_addr;
    bit              started;         // an observed AHB beat was assigned
    int unsigned     beat_index;
    bit              saw_error;
    bit              saw_wait;

    function new(axi4_transaction tr);
        this.tr = tr;
    endfunction : new

endclass : e2e_rsp_ctx

class e2e_cov extends uvm_component;

    `uvm_component_utils(e2e_cov)

    //-------------------------------------------------------------------------
    // Analysis interfaces
    //-------------------------------------------------------------------------
    uvm_analysis_imp_e2e_axi_req #(axi4_transaction, e2e_cov)
        axi_req_export;
    uvm_analysis_imp_e2e_expected_ahb #(ahb_transfer, e2e_cov)
        expected_ahb_export;
    uvm_analysis_imp_e2e_actual_ahb #(ahb_transfer, e2e_cov)
        actual_ahb_export;
    uvm_analysis_imp_e2e_axi_rsp #(axi4_transaction, e2e_cov)
        axi_rsp_export;

    //-------------------------------------------------------------------------
    // Correlation state
    //-------------------------------------------------------------------------
    // Predicted side: the predictor sends a request and then all of its
    // beats in one call, so a FIFO is exact.
    protected axi4_transaction   map_axi_queue[$];
    protected int unsigned       map_beat_index;
    // Observed side: matched like the scoreboard, independent of request
    // order (first beat direction/address, then AXI completion by ID).
    protected e2e_rsp_ctx        rsp_ctx_queue[$];
    protected e2e_rsp_ctx        rsp_active_ctx;
    protected e2e_rsp_ctx        rsp_predict_ctx;
    protected e2e_rsp_ctx        rsp_done_queue[$];
    protected ahb_transfer       pending_actual_ahb_queue[$];
    protected axi4_transaction   actual_axi_queue[$];

    //-------------------------------------------------------------------------
    // AXI request sample fields
    //-------------------------------------------------------------------------
    protected axi4_dir_e   m_axi_dir;
    protected axi4_burst_e m_axi_burst;
    protected axi4_size_e  m_axi_size;
    protected int unsigned m_axi_beats;
    protected bit [3:0]    m_axi_cache;
    protected bit [2:0]    m_axi_prot;
    protected bit          m_axi_narrow;
    protected bit          m_axi_aligned;
    protected bit [1:0]    m_boundary_class;
    protected bit [1:0]    m_strobe_class;

    //-------------------------------------------------------------------------
    // Translation sample fields
    //-------------------------------------------------------------------------
    protected axi4_dir_e   m_map_dir;
    protected axi4_burst_e m_map_axi_burst;
    protected ahb_burst_e  m_map_ahb_burst;
    protected ahb_trans_e  m_map_ahb_trans;
    protected ahb_size_e   m_map_ahb_size;
    protected int unsigned m_map_axi_beats;
    protected bit [1:0]    m_map_beat_pos;
    protected bit [3:0]    m_map_class;
    protected bit          m_map_new_segment;
    protected bit          m_map_narrow;
    protected bit          m_map_axi_bufferable;
    protected bit          m_map_axi_privileged;
    protected bit          m_map_axi_data;
    protected bit [3:0]    m_map_hprot;

    //-------------------------------------------------------------------------
    // AHB response sample fields
    //-------------------------------------------------------------------------
    protected ahb_dir_e    m_ahb_dir;
    protected ahb_burst_e  m_ahb_burst;
    protected ahb_size_e   m_ahb_size;
    protected ahb_resp_e   m_ahb_resp;
    protected int unsigned m_ahb_wait_cycles;
    protected bit [1:0]    m_ahb_beat_pos;

    //-------------------------------------------------------------------------
    // End-to-end response sample fields
    //-------------------------------------------------------------------------
    protected axi4_dir_e m_rsp_dir;
    protected bit        m_rsp_ahb_error;
    protected bit        m_rsp_ahb_wait;
    protected bit [1:0]  m_rsp_axi_status;

    //-------------------------------------------------------------------------
    // AXI request coverage
    //-------------------------------------------------------------------------
    covergroup cg_axi_request;
        option.per_instance = 1;

        cp_dir: coverpoint m_axi_dir {
            bins read  = {AXI4_READ};
            bins write = {AXI4_WRITE};
        }
        cp_burst: coverpoint m_axi_burst {
            bins fixed = {AXI4_BURST_FIXED};
            bins incr  = {AXI4_BURST_INCR};
            bins wrap  = {AXI4_BURST_WRAP};
        }
        cp_size: coverpoint m_axi_size {
            bins legal[] = {[AXI4_SIZE_1BYTE:AXI4_SIZE_128BYTE]}
                           with ((1 << item) <= AXI4_STRB_WIDTH);
            bins wider_than_bus = default;
        }
        cp_beats: coverpoint m_axi_beats {
            bins len1   = {1};
            bins len2   = {2};
            bins len3   = {3};
            bins len4   = {4};
            bins len5   = {5};
            bins len8   = {8};
            bins len16  = {16};
            bins len17  = {17};
            bins len256 = {256};
            bins other  = {[6:7], [9:15], [18:255]};
        }
        cp_narrow: coverpoint m_axi_narrow {
            bins full_width = {1'b0};
            bins narrow     = {1'b1};
        }
        cp_aligned: coverpoint m_axi_aligned {
            bins aligned   = {1'b1};
            bins unaligned = {1'b0};
        }
        cp_boundary: coverpoint m_boundary_class {
            bins no_cross  = {2'd0};
            bins exact_edge = {2'd1};
            bins cross_1kb = {2'd2};
        }
        cp_cache: coverpoint m_axi_cache {
            bins legal[] = {4'b0000, 4'b0001, 4'b0010, 4'b0011,
                            4'b0110, 4'b0111, 4'b1010, 4'b1011,
                            4'b1110, 4'b1111};
            // AXI4 reserved encodings (IHI0022E Table A4-5)
            illegal_bins reserved = {4'b0100, 4'b0101, 4'b1000, 4'b1001,
                                     4'b1100, 4'b1101};
        }
        cp_prot:  coverpoint m_axi_prot;

        cx_dir_burst:     cross cp_dir, cp_burst;
        cx_burst_beats: cross cp_burst, cp_beats {
            ignore_bins fixed_too_long =
                binsof(cp_burst.fixed) &&
                (binsof(cp_beats.len17) || binsof(cp_beats.len256));
            ignore_bins wrap_illegal_length =
                binsof(cp_burst.wrap) &&
                (binsof(cp_beats.len1) || binsof(cp_beats.len3) ||
                 binsof(cp_beats.len5) || binsof(cp_beats.len17) ||
                 binsof(cp_beats.len256) || binsof(cp_beats.other));
        }
        cx_dir_narrow:    cross cp_dir, cp_narrow;
        cx_burst_boundary: cross cp_burst, cp_boundary {
            ignore_bins fixed_boundary =
                binsof(cp_burst.fixed) &&
                (binsof(cp_boundary.exact_edge) ||
                 binsof(cp_boundary.cross_1kb));
            ignore_bins wrap_boundary =
                binsof(cp_burst.wrap) &&
                (binsof(cp_boundary.exact_edge) ||
                 binsof(cp_boundary.cross_1kb));
        }
    endgroup : cg_axi_request

    //-------------------------------------------------------------------------
    // Write strobe coverage
    //-------------------------------------------------------------------------
    covergroup cg_write_strobe;
        option.per_instance = 1;

        cp_class: coverpoint m_strobe_class {
            bins full       = {2'd0};
            bins zero       = {2'd1};
            bins contiguous = {2'd2};
            bins sparse     = {2'd3};
        }
        cp_narrow: coverpoint m_axi_narrow {
            bins full_width = {1'b0};
            bins narrow     = {1'b1};
        }
        cx_class_narrow: cross cp_class, cp_narrow;
    endgroup : cg_write_strobe

    //-------------------------------------------------------------------------
    // AXI-to-AHB translation coverage
    //-------------------------------------------------------------------------
    covergroup cg_translation;
        option.per_instance = 1;

        cp_dir: coverpoint m_map_dir {
            bins read  = {AXI4_READ};
            bins write = {AXI4_WRITE};
        }
        cp_axi_burst: coverpoint m_map_axi_burst {
            bins fixed = {AXI4_BURST_FIXED};
            bins incr  = {AXI4_BURST_INCR};
            bins wrap  = {AXI4_BURST_WRAP};
        }
        cp_ahb_burst: coverpoint m_map_ahb_burst {
            bins single = {AHB_BURST_SINGLE};
            bins incr   = {AHB_BURST_INCR};
            bins wrap4  = {AHB_BURST_WRAP4};
            bins incr4  = {AHB_BURST_INCR4};
            bins wrap8  = {AHB_BURST_WRAP8};
            bins incr8  = {AHB_BURST_INCR8};
            bins wrap16 = {AHB_BURST_WRAP16};
            bins incr16 = {AHB_BURST_INCR16};
        }
        cp_ahb_trans: coverpoint m_map_ahb_trans {
            bins nonseq = {AHB_TRANS_NONSEQ};
            bins seq    = {AHB_TRANS_SEQ};
        }
        cp_ahb_size: coverpoint m_map_ahb_size {
            bins legal[] = {[AHB_SIZE_1BYTE:AHB_SIZE_128BYTE]}
                           with ((1 << item) <= (AHB_DATA_WIDTH / 8));
            bins wider_than_bus = default;
        }
        cp_beats: coverpoint m_map_axi_beats {
            bins single  = {1};
            bins len2    = {2};
            bins len4    = {4};
            bins len8    = {8};
            bins len16   = {16};
            bins other   = default;
        }
        cp_position: coverpoint m_map_beat_pos {
            bins single = {2'd0};
            bins first  = {2'd1};
            bins middle = {2'd2};
            bins last   = {2'd3};
        }
        cp_mapping: coverpoint m_map_class {
            bins fixed_single = {4'd0};
            bins incr_single  = {4'd1};
            bins incr_undef   = {4'd2};
            bins incr4        = {4'd3};
            bins incr8        = {4'd4};
            bins incr16       = {4'd5};
            bins wrap2_single = {4'd6};
            bins wrap4        = {4'd7};
            bins wrap8        = {4'd8};
            bins wrap16       = {4'd9};
            bins unsupported  = default;
        }
        cp_new_segment: coverpoint m_map_new_segment {
            bins no  = {1'b0};
            bins yes = {1'b1};
        }
        cp_narrow: coverpoint m_map_narrow {
            bins full_width = {1'b0};
            bins narrow     = {1'b1};
        }
        cp_axi_bufferable: coverpoint m_map_axi_bufferable {
            bins no  = {1'b0};
            bins yes = {1'b1};
        }
        cp_axi_privileged: coverpoint m_map_axi_privileged {
            bins no  = {1'b0};
            bins yes = {1'b1};
        }
        cp_axi_data: coverpoint m_map_axi_data {
            bins instruction = {1'b0};
            bins data        = {1'b1};
        }
        cp_hprot_bufferable: coverpoint m_map_hprot[2] {
            bins no  = {1'b0};
            bins yes = {1'b1};
        }
        cp_hprot_privileged: coverpoint m_map_hprot[1] {
            bins no  = {1'b0};
            bins yes = {1'b1};
        }
        cp_hprot_data: coverpoint m_map_hprot[0] {
            bins instruction = {1'b0};
            bins data        = {1'b1};
        }

        cx_dir_mapping:  cross cp_dir, cp_mapping;
        cx_mapping_size: cross cp_mapping, cp_ahb_size;
        cx_dir_size:     cross cp_dir, cp_ahb_size;
        cx_segment_trans: cross cp_new_segment, cp_ahb_trans {
            ignore_bins segment_seq = binsof(cp_new_segment.yes) &&
                                      binsof(cp_ahb_trans.seq);
        }
        cx_bufferable_map: cross cp_axi_bufferable, cp_hprot_bufferable {
            ignore_bins mismatch =
                (binsof(cp_axi_bufferable.no) &&
                 binsof(cp_hprot_bufferable.yes)) ||
                (binsof(cp_axi_bufferable.yes) &&
                 binsof(cp_hprot_bufferable.no));
        }
        cx_privileged_map: cross cp_axi_privileged, cp_hprot_privileged {
            ignore_bins mismatch =
                (binsof(cp_axi_privileged.no) &&
                 binsof(cp_hprot_privileged.yes)) ||
                (binsof(cp_axi_privileged.yes) &&
                 binsof(cp_hprot_privileged.no));
        }
        cx_data_map: cross cp_axi_data, cp_hprot_data {
            ignore_bins mismatch =
                (binsof(cp_axi_data.instruction) &&
                 binsof(cp_hprot_data.data)) ||
                (binsof(cp_axi_data.data) &&
                 binsof(cp_hprot_data.instruction));
        }
    endgroup : cg_translation

    //-------------------------------------------------------------------------
    // Actual AHB response coverage
    //-------------------------------------------------------------------------
    covergroup cg_ahb_response;
        option.per_instance = 1;

        cp_dir: coverpoint m_ahb_dir {
            bins read  = {AHB_READ};
            bins write = {AHB_WRITE};
        }
        cp_burst: coverpoint m_ahb_burst;
        cp_size:  coverpoint m_ahb_size;
        cp_resp: coverpoint m_ahb_resp {
            bins okay  = {AHB_RESP_OKAY};
            bins error = {AHB_RESP_ERROR};
        }
        cp_wait: coverpoint m_ahb_wait_cycles {
            bins zero   = {0};
            bins one    = {1};
            bins short  = {[2:3]};
            bins mid    = {[4:15]};
            bins long   = {[16:$]};
        }
        cp_position: coverpoint m_ahb_beat_pos {
            bins single = {2'd0};
            bins first  = {2'd1};
            bins middle = {2'd2};
            bins last   = {2'd3};
        }

        cx_dir_resp:      cross cp_dir, cp_resp;
        cx_burst_resp:    cross cp_burst, cp_resp;
        cx_position_resp: cross cp_position, cp_resp;
        cx_resp_wait:     cross cp_resp, cp_wait;
    endgroup : cg_ahb_response

    //-------------------------------------------------------------------------
    // End-to-end response coverage
    //-------------------------------------------------------------------------
    covergroup cg_response_map;
        option.per_instance = 1;

        cp_dir: coverpoint m_rsp_dir {
            bins read  = {AXI4_READ};
            bins write = {AXI4_WRITE};
        }
        cp_ahb_error: coverpoint m_rsp_ahb_error {
            bins okay  = {1'b0};
            bins error = {1'b1};
        }
        cp_ahb_wait: coverpoint m_rsp_ahb_wait {
            bins zero_wait = {1'b0};
            bins waited    = {1'b1};
        }
        cp_axi_status: coverpoint m_rsp_axi_status {
            bins okay   = {2'd0};
            bins slverr = {2'd1};
            // The bridge never generates EXOKAY/DECERR (PG177)
            illegal_bins unsupported = {2'd2};
        }

        cx_error_map: cross cp_ahb_error, cp_axi_status;
        cx_dir_status: cross cp_dir, cp_axi_status;
        cx_wait_status: cross cp_ahb_wait, cp_axi_status;
    endgroup : cg_response_map

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_axi_request   = new();
        cg_write_strobe  = new();
        cg_translation   = new();
        cg_ahb_response  = new();
        cg_response_map  = new();
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_req_export      = new("axi_req_export", this);
        expected_ahb_export = new("expected_ahb_export", this);
        actual_ahb_export   = new("actual_ahb_export", this);
        axi_rsp_export      = new("axi_rsp_export", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // AXI request callback
    //-------------------------------------------------------------------------
    function void write_e2e_axi_req(axi4_transaction tr);
        axi4_transaction map_tr;
        axi4_transaction rsp_tr;
        int unsigned     byte_count;

        if (!$cast(map_tr, tr.clone()) || !$cast(rsp_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "AXI request clone failed")
        map_axi_queue.push_back(map_tr);
        rsp_predict_ctx = new(rsp_tr);
        rsp_ctx_queue.push_back(rsp_predict_ctx);

        byte_count       = 1 << int'(tr.size);
        m_axi_dir        = tr.dir;
        m_axi_burst      = tr.burst;
        m_axi_size       = tr.size;
        m_axi_beats      = int'(tr.len) + 1;
        m_axi_cache      = tr.cache;
        m_axi_prot       = tr.prot;
        m_axi_narrow     = (byte_count < AXI4_STRB_WIDTH);
        m_axi_aligned    = ((tr.addr % byte_count) == 0);
        m_boundary_class = get_boundary_class(tr, byte_count);
        cg_axi_request.sample();

        if (tr.dir == AXI4_WRITE) begin
            foreach (tr.strb[i]) begin
                m_strobe_class = get_strobe_class(tr.strb[i]);
                cg_write_strobe.sample();
            end
        end
    endfunction : write_e2e_axi_req

    //-------------------------------------------------------------------------
    // Expected AHB callback
    //-------------------------------------------------------------------------
    function void write_e2e_expected_ahb(ahb_transfer tr);
        axi4_transaction axi_tr;
        int unsigned     beat_count;

        if (map_axi_queue.size() == 0) begin
            `uvm_warning(get_type_name(),
                         "Expected AHB beat has no AXI coverage context")
            return;
        end

        axi_tr    = map_axi_queue[0];
        beat_count = int'(axi_tr.len) + 1;
        m_map_dir            = axi_tr.dir;
        m_map_axi_burst      = axi_tr.burst;
        m_map_ahb_burst      = tr.burst;
        m_map_ahb_trans      = tr.trans;
        m_map_ahb_size       = tr.size;
        m_map_axi_beats      = beat_count;
        m_map_beat_pos       = get_beat_position(map_beat_index, beat_count);
        m_map_class          = get_mapping_class(axi_tr, tr);
        m_map_new_segment    = ((map_beat_index != 0) &&
                                (tr.trans == AHB_TRANS_NONSEQ));
        m_map_narrow         = ((1 << int'(tr.size)) <
                                (AHB_DATA_WIDTH / 8));
        m_map_axi_bufferable = axi_tr.cache[0] & ~axi_tr.cache[2] &
                               ~axi_tr.cache[3];
        m_map_axi_privileged = axi_tr.prot[0];
        m_map_axi_data       = ~axi_tr.prot[2];
        m_map_hprot          = tr.prot;
        cg_translation.sample();

        map_beat_index++;
        if (map_beat_index == beat_count) begin
            void'(map_axi_queue.pop_front());
            map_beat_index = 0;
        end

        if ((rsp_predict_ctx != null) && !rsp_predict_ctx.has_first_beat) begin
            rsp_predict_ctx.has_first_beat = 1'b1;
            rsp_predict_ctx.first_write    = tr.write;
            rsp_predict_ctx.first_addr     = tr.addr;
            drain_actual_ahb();
        end
    endfunction : write_e2e_expected_ahb

    //-------------------------------------------------------------------------
    // Actual AHB callback
    //-------------------------------------------------------------------------
    function void write_e2e_actual_ahb(ahb_transfer tr);
        ahb_transfer copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Actual AHB transfer clone failed")
        pending_actual_ahb_queue.push_back(copy_tr);
        drain_actual_ahb();
    endfunction : write_e2e_actual_ahb

    protected function void drain_actual_ahb();
        while (pending_actual_ahb_queue.size() != 0) begin
            ahb_transfer tr;
            int unsigned beat_count;

            if (rsp_active_ctx == null) begin
                rsp_active_ctx = find_rsp_ctx(pending_actual_ahb_queue[0]);
                // Request not predicted yet; retry when it is
                if (rsp_active_ctx == null)
                    break;
                rsp_active_ctx.started = 1'b1;
            end

            tr         = pending_actual_ahb_queue.pop_front();
            beat_count = int'(rsp_active_ctx.tr.len) + 1;
            m_ahb_dir         = tr.write;
            m_ahb_burst       = tr.burst;
            m_ahb_size        = tr.size;
            m_ahb_resp        = tr.resp;
            m_ahb_wait_cycles = tr.wait_cycles;
            m_ahb_beat_pos    = get_beat_position(rsp_active_ctx.beat_index,
                                                  beat_count);
            cg_ahb_response.sample();

            if (tr.resp == AHB_RESP_ERROR)
                rsp_active_ctx.saw_error = 1'b1;
            if (tr.wait_cycles != 0)
                rsp_active_ctx.saw_wait = 1'b1;

            rsp_active_ctx.beat_index++;
            if (rsp_active_ctx.beat_index >= beat_count) begin
                foreach (rsp_ctx_queue[i]) begin
                    if (rsp_ctx_queue[i] == rsp_active_ctx) begin
                        rsp_ctx_queue.delete(i);
                        break;
                    end
                end
                rsp_done_queue.push_back(rsp_active_ctx);
                rsp_active_ctx = null;
                sample_response_queue();
            end
        end
    endfunction : drain_actual_ahb

    // Same selection rule as the scoreboard: oldest unstarted request whose
    // first predicted beat has the same direction and address, otherwise the
    // oldest unstarted request of the same direction.
    protected function e2e_rsp_ctx find_rsp_ctx(ahb_transfer tr);
        foreach (rsp_ctx_queue[i]) begin
            if (!rsp_ctx_queue[i].started && rsp_ctx_queue[i].has_first_beat &&
                (rsp_ctx_queue[i].first_write == tr.write) &&
                (rsp_ctx_queue[i].first_addr  == tr.addr))
                return rsp_ctx_queue[i];
        end
        foreach (rsp_ctx_queue[i]) begin
            if (!rsp_ctx_queue[i].started && rsp_ctx_queue[i].has_first_beat &&
                (rsp_ctx_queue[i].first_write == tr.write))
                return rsp_ctx_queue[i];
        end
        return null;
    endfunction : find_rsp_ctx

    //-------------------------------------------------------------------------
    // AXI completion callback
    //-------------------------------------------------------------------------
    function void write_e2e_axi_rsp(axi4_transaction tr);
        axi4_transaction copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "AXI completion clone failed")
        actual_axi_queue.push_back(copy_tr);
        sample_response_queue();
    endfunction : write_e2e_axi_rsp

    //-------------------------------------------------------------------------
    // Response correlation
    //-------------------------------------------------------------------------
    // Each AXI completion is paired with the oldest AHB-complete request of
    // the same direction and ID.
    protected function void sample_response_queue();
        int unsigned actual_index;

        actual_index = 0;
        while (actual_index < actual_axi_queue.size()) begin
            axi4_transaction axi_tr;
            e2e_rsp_ctx      ctx;
            int              done_index;

            axi_tr     = actual_axi_queue[actual_index];
            done_index = -1;
            foreach (rsp_done_queue[i]) begin
                if ((rsp_done_queue[i].tr.dir == axi_tr.dir) &&
                    (rsp_done_queue[i].tr.id  == axi_tr.id)) begin
                    done_index = i;
                    break;
                end
            end
            if (done_index < 0) begin
                actual_index++;
                continue;
            end

            ctx = rsp_done_queue[done_index];
            rsp_done_queue.delete(done_index);
            actual_axi_queue.delete(actual_index);

            m_rsp_dir        = axi_tr.dir;
            m_rsp_ahb_error  = ctx.saw_error;
            m_rsp_ahb_wait   = ctx.saw_wait;
            m_rsp_axi_status = get_axi_status(axi_tr);
            cg_response_map.sample();
        end
    endfunction : sample_response_queue

    //-------------------------------------------------------------------------
    // Coverage helpers
    //-------------------------------------------------------------------------
    protected function bit [1:0] get_boundary_class(
        axi4_transaction tr,
        int unsigned     byte_count
    );
        bit [AXI4_ADDR_WIDTH:0] aligned_addr;
        bit [AXI4_ADDR_WIDTH:0] end_addr;

        if (tr.burst != AXI4_BURST_INCR)
            return 2'd0;
        aligned_addr = {1'b0, tr.addr - (tr.addr % byte_count)};
        end_addr = aligned_addr + ((int'(tr.len) + 1) * byte_count) - 1;
        if ((aligned_addr >> 10) != (end_addr >> 10))
            return 2'd2;
        if (end_addr[9:0] == 10'h3ff)
            return 2'd1;
        return 2'd0;
    endfunction : get_boundary_class

    protected function bit [1:0] get_strobe_class(
        bit [AXI4_STRB_WIDTH-1:0] strobe
    );
        bit seen_one;
        bit seen_gap;

        if (strobe == '0)
            return 2'd1;
        if (&strobe)
            return 2'd0;

        for (int unsigned i = 0; i < AXI4_STRB_WIDTH; i++) begin
            if (strobe[i]) begin
                if (seen_gap)
                    return 2'd3;
                seen_one = 1'b1;
            end else if (seen_one) begin
                seen_gap = 1'b1;
            end
        end
        return 2'd2;
    endfunction : get_strobe_class

    protected function bit [1:0] get_beat_position(
        int unsigned beat_index,
        int unsigned beat_count
    );
        if (beat_count == 1)
            return 2'd0;
        if (beat_index == 0)
            return 2'd1;
        if (beat_index == (beat_count - 1))
            return 2'd3;
        return 2'd2;
    endfunction : get_beat_position

    protected function bit [3:0] get_mapping_class(
        axi4_transaction axi_tr,
        ahb_transfer     ahb_tr
    );
        case (axi_tr.burst)
            AXI4_BURST_FIXED:
                return 4'd0;
            AXI4_BURST_INCR: begin
                case (ahb_tr.burst)
                    AHB_BURST_SINGLE: return 4'd1;
                    AHB_BURST_INCR:   return 4'd2;
                    AHB_BURST_INCR4:  return 4'd3;
                    AHB_BURST_INCR8:  return 4'd4;
                    AHB_BURST_INCR16: return 4'd5;
                    default:          return 4'd15;
                endcase
            end
            AXI4_BURST_WRAP: begin
                case (ahb_tr.burst)
                    AHB_BURST_SINGLE: return 4'd6;
                    AHB_BURST_WRAP4:  return 4'd7;
                    AHB_BURST_WRAP8:  return 4'd8;
                    AHB_BURST_WRAP16: return 4'd9;
                    default:          return 4'd15;
                endcase
            end
        endcase
        return 4'd15;
    endfunction : get_mapping_class

    protected function bit [1:0] get_axi_status(axi4_transaction tr);
        bit saw_slverr;

        if (tr.dir == AXI4_WRITE) begin
            if (tr.bresp == AXI4_RESP_OKAY)
                return 2'd0;
            if (tr.bresp == AXI4_RESP_SLVERR)
                return 2'd1;
            return 2'd2;
        end

        foreach (tr.rresp[i]) begin
            if (tr.rresp[i] inside {AXI4_RESP_EXOKAY, AXI4_RESP_DECERR})
                return 2'd2;
            if (tr.rresp[i] == AXI4_RESP_SLVERR)
                saw_slverr = 1'b1;
        end
        return saw_slverr ? 2'd1 : 2'd0;
    endfunction : get_axi_status

    //-------------------------------------------------------------------------
    // Reset handling
    //-------------------------------------------------------------------------
    function void reset_state();
        map_axi_queue.delete();
        map_beat_index = 0;
        rsp_ctx_queue.delete();
        rsp_active_ctx  = null;
        rsp_predict_ctx = null;
        rsp_done_queue.delete();
        pending_actual_ahb_queue.delete();
        actual_axi_queue.delete();
    endfunction : reset_state

    //-------------------------------------------------------------------------
    // End-of-test checks
    //-------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if ((map_axi_queue.size() != 0) || (rsp_ctx_queue.size() != 0) ||
            (pending_actual_ahb_queue.size() != 0) ||
            (rsp_done_queue.size() != 0) || (actual_axi_queue.size() != 0))
            `uvm_warning(get_type_name(),
                         "End-to-end coverage has unmatched input streams")
    endfunction : check_phase

    //-------------------------------------------------------------------------
    // Report phase
    //-------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
                  $sformatf({"E2E coverage: AXI=%.2f%% strobe=%.2f%% ",
                             "translation=%.2f%% AHB=%.2f%% response=%.2f%%"},
                            cg_axi_request.get_coverage(),
                            cg_write_strobe.get_coverage(),
                            cg_translation.get_coverage(),
                            cg_ahb_response.get_coverage(),
                            cg_response_map.get_coverage()), UVM_LOW)
    endfunction : report_phase

endclass : e2e_cov