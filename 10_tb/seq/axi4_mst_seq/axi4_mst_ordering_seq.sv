//=============================================================================
// File        : axi4_mst_ordering_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : In-order completion under a deep request queue. Each phase
//               queues all its requests at once and checks:
//               - B/R completions in AW/AR acceptance order, per direction
//               - read data against a reference memory replayed in that order
//               - one contiguous AHB run per request, no interleaving
//               - RID constant within a burst; the queue must back up
//               Covers BRG_UNS_002.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_ordering_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_ordering_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BUS_BYTES = AXI4_STRB_WIDTH;

    // Longest burst in beats; sets the slot size
    localparam int unsigned MAX_BEATS = 16;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr       = 'h2000;
    int unsigned              slot_bytes      = 'h100;
    int unsigned              stress_requests = 24;
    int unsigned              stress_slots    = 8;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    // ready_delay_max is changed per phase
    ahb_slv_agent_cfg ahb_cfg;
    ahb_vif_t         ahb_vif;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned phases_run;
    int unsigned phases_failed;
    int unsigned requests_run;
    int unsigned reads_run;
    int unsigned writes_run;
    int unsigned r_bursts;
    // Maximum requests accepted but not yet completed
    int unsigned max_accepted;
    int unsigned max_queue_depth;
    int unsigned stall_cycles;
    int unsigned interleaved_beats;
    // Adjacent conflicting accesses in the observed acceptance order
    int unsigned raw_pairs;
    int unsigned war_pairs;
    int unsigned waw_pairs;
    // Reads whose expected data came from an earlier write
    int unsigned ordered_reads;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    typedef struct {
        axi4_dir_e                dir;
        bit [AXI4_ID_WIDTH-1:0]   id;
        bit [AXI4_ADDR_WIDTH-1:0] addr;   // AW/AR payload
        int unsigned              len;
    } accept_rec_t;

    typedef struct {
        axi4_dir_e              dir;
        bit [AXI4_ID_WIDTH-1:0] id;
        int unsigned            beats;    // R beats; always 1 for B
    } complete_rec_t;

    typedef struct {
        ahb_dir_e    dir;
        int unsigned beats;
    } ahb_run_t;

    //-------------------------------------------------------------------------
    // Per-phase state
    //-------------------------------------------------------------------------
    protected axi4_transaction phase_reqs[$];
    protected axi4_transaction phase_rsps[$];
    protected int              phase_tags[$];
    protected string           phase_label;

    protected accept_rec_t   accept_log[$];
    protected complete_rec_t complete_log[$];
    protected ahb_run_t      ahb_runs[$];

    protected int unsigned accepted_open;
    protected int unsigned phase_stall_cycles;
    protected bit                     r_burst_active;
    protected bit [AXI4_ID_WIDTH-1:0] r_burst_id;
    protected int unsigned            r_burst_beats;

    //-------------------------------------------------------------------------
    // Reference state that survives the whole run
    //-------------------------------------------------------------------------
    // Written bytes only; the rest read as the address pattern
    protected bit [7:0] shadow_mem[bit [AXI4_ADDR_WIDTH-1:0]];
    protected int       next_tag = 1;
    protected int unsigned data_tag;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_ordering_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (ahb_cfg == null)
            `uvm_fatal(get_type_name(), "AHB slave agent config is null")
        if (ahb_vif == null)
            `uvm_fatal(get_type_name(), "AHB virtual interface is null")
        if (!cfg.return_responses)
            `uvm_fatal(get_type_name(),
                       "Ordering checks need return_responses")
        if (cfg.max_outstanding != 0)
            `uvm_fatal(get_type_name(),
                       {"The driver must not throttle the queue, or the ",
                        "bridge is no longer the only thing choosing what ",
                        "runs next; set max_outstanding to 0"})
        if (!ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       {"A read must return what an earlier write left ",
                        "behind; auto_gen_resp must be set"})
        if (!ahb_cfg.addr_pattern_read)
            `uvm_fatal(get_type_name(),
                       {"The expected word of an untouched address is the ",
                        "address pattern; addr_pattern_read must be set"})

        validate_knobs();

        // Responses are collected per phase: enlarge the queue
        set_response_queue_depth(-1);

        wait_reset_release();

        `uvm_info(get_type_name(),
                  $sformatf({"Ordering: base=0x%0h slot=%0d bytes, ",
                             "stress=%0d requests over %0d slots"},
                            base_addr, slot_bytes, stress_requests,
                            stress_slots),
                  UVM_LOW)

        run_same_id_read_phase();
        run_id_sweep_read_phase();
        run_write_read_phase();
        run_conflict_phases();
        run_stress_phase();

        check_run_was_conclusive();

        `uvm_info(get_type_name(),
                  $sformatf({"Ordering summary: phases=%0d failed=%0d ",
                             "requests=%0d (rd=%0d wr=%0d) queue_depth=%0d ",
                             "max_accepted=%0d stall_cycles=%0d ",
                             "r_bursts=%0d interleaved=%0d ordered_reads=%0d ",
                             "raw=%0d war=%0d waw=%0d"},
                            phases_run, phases_failed, requests_run,
                            reads_run, writes_run, max_queue_depth,
                            max_accepted, stall_cycles, r_bursts,
                            interleaved_beats, ordered_reads,
                            raw_pairs, war_pairs, waw_pairs),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Phases
    //-------------------------------------------------------------------------
    // Eight outstanding reads on one ID
    protected task run_same_id_read_phase();
        int unsigned lens[8];

        lens = '{0, 3, 1, 7, 0, 3, 0, 1};
        ahb_cfg.ready_delay_max = 0;
        phase_reqs.delete();
        for (int unsigned i = 0; i < 8; i++) begin
            bit [AXI4_ID_WIDTH-1:0] id;

            id = 3;
            phase_reqs.push_back(
                make_request(AXI4_READ, AXI4_BURST_INCR, lens[i],
                             slot_addr(i), id,
                             $sformatf("SAMEID_RD%0d", i)));
        end
        run_request_phase("SAME_ID_READS");
    endtask : run_same_id_read_phase

    // Rotating IDs, falling burst lengths
    protected task run_id_sweep_read_phase();
        int unsigned lens[8];

        lens = '{15, 7, 3, 1, 0, 0, 0, 0};
        ahb_cfg.ready_delay_max = 0;
        phase_reqs.delete();
        for (int unsigned i = 0; i < 8; i++) begin
            bit [AXI4_ID_WIDTH-1:0] id;

            id = i;
            phase_reqs.push_back(
                make_request(AXI4_READ, AXI4_BURST_INCR, lens[i],
                             slot_addr(8 + i), id,
                             $sformatf("SWEEP_RD%0d", i)));
        end
        run_request_phase("ID_SWEEP_READS");
    endtask : run_id_sweep_read_phase

    // Eight writes and eight reads over the same regions
    protected task run_write_read_phase();
        int unsigned lens[8];

        lens = '{0, 3, 1, 7, 0, 3, 1, 0};
        ahb_cfg.ready_delay_max = 1;
        phase_reqs.delete();
        for (int unsigned i = 0; i < 8; i++) begin
            bit [AXI4_ID_WIDTH-1:0] id;

            id = 2 * i;
            phase_reqs.push_back(
                make_request(AXI4_WRITE, AXI4_BURST_INCR, lens[i],
                             slot_addr(16 + i), id,
                             $sformatf("STREAM_WR%0d", i)));
        end
        for (int unsigned i = 0; i < 8; i++) begin
            bit [AXI4_ID_WIDTH-1:0] id;

            id = 2 * i + 1;
            phase_reqs.push_back(
                make_request(AXI4_READ, AXI4_BURST_INCR, lens[i],
                             slot_addr(16 + i), id,
                             $sformatf("STREAM_RD%0d", i)));
        end
        run_request_phase("WRITE_READ_STREAM");
    endtask : run_write_read_phase

    // Four single-address conflict phases (RAW, WAR, WAW), shared and
    // distinct IDs
    protected task run_conflict_phases();
        ahb_cfg.ready_delay_max = 0;
        for (int unsigned slot = 0; slot < 4; slot++) begin
            bit [AXI4_ADDR_WIDTH-1:0] addr;
            bit                       shared_id;
            string                    id_style;

            addr      = slot_addr(24 + slot);
            shared_id = ((slot % 2) == 0);
            if (shared_id)
                id_style = "SAMEID";
            else
                id_style = "MULTIID";
            phase_reqs.delete();
            add_conflict_request(AXI4_READ,  0, addr, shared_id, 0, slot);
            add_conflict_request(AXI4_WRITE, 0, addr, shared_id, 1, slot);
            add_conflict_request(AXI4_READ,  0, addr, shared_id, 2, slot);
            add_conflict_request(AXI4_WRITE, 1, addr, shared_id, 3, slot);
            add_conflict_request(AXI4_READ,  1, addr, shared_id, 4, slot);
            add_conflict_request(AXI4_WRITE, 0, addr, shared_id, 5, slot);
            add_conflict_request(AXI4_WRITE, 0, addr, shared_id, 6, slot);
            add_conflict_request(AXI4_READ,  0, addr, shared_id, 7, slot);
            run_request_phase($sformatf("CONFLICT%0d_%s", slot, id_style));
        end
    endtask : run_conflict_phases

    protected function void add_conflict_request(
        axi4_dir_e                dir,
        int unsigned              len,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        bit                       shared_id,
        int unsigned              index,
        int unsigned              slot
    );
        bit [AXI4_ID_WIDTH-1:0] id;

        if (shared_id)
            id = 7;
        else
            id = index;
        phase_reqs.push_back(
            make_request(dir, AXI4_BURST_INCR, len, addr, id,
                         $sformatf("CONF%0d_%0d_%s", slot, index,
                                   (dir == AXI4_WRITE) ? "WR" : "RD")));
    endfunction : add_conflict_request

    // Random traffic over few regions, with AHB waits and AXI backpressure
    protected task run_stress_phase();
        ahb_cfg.ready_delay_max  = 3;
        cfg.rready_delay_max     = 3;
        cfg.bready_delay_max     = 2;

        phase_reqs.delete();
        for (int unsigned i = 0; i < stress_requests; i++)
            phase_reqs.push_back(make_stress_request(i));
        run_request_phase("MIXED_STRESS");

        ahb_cfg.ready_delay_max = 0;
        cfg.rready_delay_max    = 0;
        cfg.bready_delay_max    = 0;
    endtask : run_stress_phase

    protected function axi4_transaction make_stress_request(int unsigned index);
        axi4_dir_e                dir;
        axi4_burst_e              burst;
        int unsigned              len;
        int unsigned              slot;
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        bit [AXI4_ID_WIDTH-1:0]   id;
        // No WRAP2: it maps to two AHB bursts
        int unsigned              wrap_lens[3];

        wrap_lens = '{3, 7, 15};
        dir   = ($urandom_range(1, 0) == 1) ? AXI4_WRITE : AXI4_READ;
        slot  = $urandom_range(stress_slots - 1, 0);
        id    = $urandom_range((1 << AXI4_ID_WIDTH) - 1, 0);
        addr  = slot_addr(28 + slot);

        // Start WRAP inside its wrap block
        if ($urandom_range(3, 0) == 0) begin
            int unsigned span;

            burst = AXI4_BURST_WRAP;
            len   = wrap_lens[$urandom_range(2, 0)];
            span  = (len + 1) * BUS_BYTES;
            addr  = addr + (span / 2);
        end else begin
            burst = AXI4_BURST_INCR;
            len   = $urandom_range(MAX_BEATS - 1, 0);
        end

        return make_request(dir, burst, len, addr, id,
                            $sformatf("STRESS%0d", index));
    endfunction : make_stress_request

    //-------------------------------------------------------------------------
    // Phase runner
    //-------------------------------------------------------------------------
    protected task run_request_phase(string label);
        phase_label = label;
        phase_rsps.delete();
        phase_tags.delete();
        accept_log.delete();
        complete_log.delete();
        ahb_runs.delete();
        accepted_open      = 0;
        phase_stall_cycles = 0;
        r_burst_active     = 1'b0;
        r_burst_beats      = 0;

        if (phase_reqs.size() == 0)
            `uvm_fatal(get_type_name(),
                       $sformatf("%s: no requests were built", label))
        if (phase_reqs.size() > max_queue_depth)
            max_queue_depth = phase_reqs.size();

        fork
            begin
                fork
                    observe_axi();
                    observe_ahb();
                    drive_phase();
                join_any
                disable fork;
            end
        join

        stall_cycles += phase_stall_cycles;
        phases_run++;
        if (check_phase_results())
            phases_failed++;
    endtask : run_request_phase

    // Queue all requests before collecting any response
    protected task drive_phase();
        foreach (phase_reqs[i]) begin
            start_item(phase_reqs[i]);
            // Set after the grant; pairs the response with its request
            phase_reqs[i].set_transaction_id(next_tag);
            phase_tags.push_back(next_tag);
            next_tag++;
            finish_item(phase_reqs[i]);
        end

        foreach (phase_reqs[i]) begin
            axi4_transaction rsp;

            get_response(rsp, phase_tags[i]);
            if (rsp == null)
                `uvm_fatal(get_type_name(),
                           $sformatf("%s: null response for request %0d",
                                     phase_label, i))
            phase_rsps.push_back(rsp);
        end

        // Let the observers see the last completion
        wait_cycles(4);
    endtask : drive_phase

    //-------------------------------------------------------------------------
    // Observers
    //-------------------------------------------------------------------------
    protected task observe_axi();
        forever begin
            @(cfg.vif.monitor_cb);
            if (cfg.vif.rst_n !== 1'b1)
                continue;

            // Request pending while refused by the bridge
            if (((cfg.vif.monitor_cb.ARVALID === 1'b1) &&
                 (cfg.vif.monitor_cb.ARREADY !== 1'b1)) ||
                ((cfg.vif.monitor_cb.AWVALID === 1'b1) &&
                 (cfg.vif.monitor_cb.AWREADY !== 1'b1)))
                phase_stall_cycles++;

            if ((cfg.vif.monitor_cb.ARVALID === 1'b1) &&
                (cfg.vif.monitor_cb.ARREADY === 1'b1))
                note_accept(AXI4_READ,
                            cfg.vif.monitor_cb.ARID,
                            cfg.vif.monitor_cb.ARADDR,
                            cfg.vif.monitor_cb.ARLEN);

            if ((cfg.vif.monitor_cb.AWVALID === 1'b1) &&
                (cfg.vif.monitor_cb.AWREADY === 1'b1))
                note_accept(AXI4_WRITE,
                            cfg.vif.monitor_cb.AWID,
                            cfg.vif.monitor_cb.AWADDR,
                            cfg.vif.monitor_cb.AWLEN);

            if ((cfg.vif.monitor_cb.RVALID === 1'b1) &&
                (cfg.vif.monitor_cb.RREADY === 1'b1))
                note_r_beat(cfg.vif.monitor_cb.RID,
                            cfg.vif.monitor_cb.RLAST);

            if ((cfg.vif.monitor_cb.BVALID === 1'b1) &&
                (cfg.vif.monitor_cb.BREADY === 1'b1))
                note_complete(AXI4_WRITE, cfg.vif.monitor_cb.BID, 1);
        end
    endtask : observe_axi

    protected function void note_accept(
        axi4_dir_e                dir,
        bit [AXI4_ID_WIDTH-1:0]   id,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        int unsigned              len
    );
        accept_rec_t rec;

        rec.dir  = dir;
        rec.id   = id;
        rec.addr = addr;
        rec.len  = len;
        accept_log.push_back(rec);

        accepted_open++;
        if (accepted_open > max_accepted)
            max_accepted = accepted_open;
    endfunction : note_accept

    protected function void note_r_beat(
        bit [AXI4_ID_WIDTH-1:0] rid,
        bit                     last
    );
        if (!r_burst_active) begin
            r_burst_active = 1'b1;
            r_burst_id     = rid;
            r_burst_beats  = 0;
        end else if (rid !== r_burst_id) begin
            interleaved_beats++;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: RID changed from 0x%0h to 0x%0h ",
                                  "inside a read burst; read data of two ",
                                  "requests is interleaved"},
                                 phase_label, r_burst_id, rid))
            r_burst_id = rid;
        end

        r_burst_beats++;
        if (last) begin
            note_complete(AXI4_READ, r_burst_id, r_burst_beats);
            r_bursts++;
            r_burst_active = 1'b0;
        end
    endfunction : note_r_beat

    protected function void note_complete(
        axi4_dir_e              dir,
        bit [AXI4_ID_WIDTH-1:0] id,
        int unsigned            beats
    );
        complete_rec_t rec;

        rec.dir   = dir;
        rec.id    = id;
        rec.beats = beats;
        complete_log.push_back(rec);
        if (accepted_open > 0)
            accepted_open--;
    endfunction : note_complete

    // One run per AHB burst (NONSEQ + SEQ beats, HREADY high)
    protected task observe_ahb();
        forever begin
            ahb_trans_e htrans;

            @(ahb_vif.monitor_cb);
            if (ahb_vif.rst_n !== 1'b1)
                continue;
            if (ahb_vif.monitor_cb.HREADY !== 1'b1)
                continue;

            htrans = ahb_trans_e'(ahb_vif.monitor_cb.HTRANS);
            if (htrans == AHB_TRANS_NONSEQ) begin
                ahb_run_t run;

                run.dir   = ahb_dir_e'(ahb_vif.monitor_cb.HWRITE);
                run.beats = 1;
                ahb_runs.push_back(run);
            end else if (htrans == AHB_TRANS_SEQ) begin
                if (ahb_runs.size() == 0) begin
                    `uvm_error(get_type_name(),
                               $sformatf({"%s: an AHB SEQ transfer arrived ",
                                          "with no NONSEQ before it"},
                                         phase_label))
                end else begin
                    ahb_run_t run;

                    run = ahb_runs[ahb_runs.size() - 1];
                    run.beats++;
                    ahb_runs[ahb_runs.size() - 1] = run;
                end
            end
        end
    endtask : observe_ahb

    //-------------------------------------------------------------------------
    // Checks
    //-------------------------------------------------------------------------
    protected function bit check_phase_results();
        bit failed;

        failed  = 1'b0;
        failed |= check_queue_was_real();
        failed |= check_completion_order();
        failed |= replay_acceptance_order();
        failed |= check_ahb_runs();

        requests_run += phase_reqs.size();
        foreach (phase_reqs[i]) begin
            if (phase_reqs[i].dir == AXI4_WRITE)
                writes_run++;
            else
                reads_run++;
        end

        `uvm_info(get_type_name(),
                  $sformatf({"%s: requests=%0d accepted=%0d completed=%0d ",
                             "ahb_runs=%0d stall_cycles=%0d max_accepted=%0d"},
                            phase_label, phase_reqs.size(), accept_log.size(),
                            complete_log.size(), ahb_runs.size(),
                            phase_stall_cycles, max_accepted),
                  UVM_LOW)
        return failed;
    endfunction : check_phase_results

    // The bridge must have stalled at least one queued request
    protected function bit check_queue_was_real();
        if (phase_stall_cycles == 0) begin
            `uvm_error(get_type_name(),
                       $sformatf({"%s: no request ever waited for the ",
                                  "bridge, so the queue never backed up and ",
                                  "nothing was ordered"},
                                 phase_label))
            return 1'b1;
        end
        return 1'b0;
    endfunction : check_queue_was_real

    protected function bit check_completion_order();
        accept_rec_t   acc_rd[$];
        accept_rec_t   acc_wr[$];
        complete_rec_t cmp_rd[$];
        complete_rec_t cmp_wr[$];
        bit            failed;

        failed = 1'b0;
        foreach (accept_log[i]) begin
            if (accept_log[i].dir == AXI4_READ)
                acc_rd.push_back(accept_log[i]);
            else
                acc_wr.push_back(accept_log[i]);
        end
        foreach (complete_log[i]) begin
            if (complete_log[i].dir == AXI4_READ)
                cmp_rd.push_back(complete_log[i]);
            else
                cmp_wr.push_back(complete_log[i]);
        end

        if (accept_log.size() != phase_reqs.size()) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: the bridge accepted %0d of the %0d ",
                                  "requests handed to it"},
                                 phase_label, accept_log.size(),
                                 phase_reqs.size()))
        end

        if (cmp_rd.size() != acc_rd.size()) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: %0d read completions for %0d accepted ",
                                  "reads"},
                                 phase_label, cmp_rd.size(), acc_rd.size()))
        end
        if (cmp_wr.size() != acc_wr.size()) begin
            failed = 1'b1;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: %0d write completions for %0d ",
                                  "accepted writes"},
                                 phase_label, cmp_wr.size(), acc_wr.size()))
        end

        foreach (cmp_rd[k]) begin
            if (k >= acc_rd.size())
                break;
            if (cmp_rd[k].id !== acc_rd[k].id) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: read completion %0d carries ",
                                      "id=0x%0h, but the read accepted in ",
                                      "that position asked with id=0x%0h; ",
                                      "responses are reordered"},
                                     phase_label, k, cmp_rd[k].id,
                                     acc_rd[k].id))
            end else if (cmp_rd[k].beats != (acc_rd[k].len + 1)) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: read completion %0d returned %0d ",
                                      "beats, but its AR asked for %0d"},
                                     phase_label, k, cmp_rd[k].beats,
                                     acc_rd[k].len + 1))
            end
        end

        foreach (cmp_wr[k]) begin
            if (k >= acc_wr.size())
                break;
            if (cmp_wr[k].id !== acc_wr[k].id) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: write completion %0d carries ",
                                      "id=0x%0h, but the write accepted in ",
                                      "that position asked with id=0x%0h; ",
                                      "responses are reordered"},
                                     phase_label, k, cmp_wr[k].id,
                                     acc_wr[k].id))
            end
        end
        return failed;
    endfunction : check_completion_order

    // Replay the acceptance order on the reference memory and check reads
    protected function bit replay_acceptance_order();
        axi4_transaction rd_reqs[$];
        axi4_transaction rd_rsps[$];
        axi4_transaction wr_reqs[$];
        axi4_transaction wr_rsps[$];
        int unsigned     rd_idx;
        int unsigned     wr_idx;
        bit              failed;

        failed = 1'b0;
        foreach (phase_reqs[i]) begin
            if (i >= phase_rsps.size())
                break;
            if (phase_reqs[i].dir == AXI4_WRITE) begin
                wr_reqs.push_back(phase_reqs[i]);
                wr_rsps.push_back(phase_rsps[i]);
            end else begin
                rd_reqs.push_back(phase_reqs[i]);
                rd_rsps.push_back(phase_rsps[i]);
            end
        end

        count_conflict_pairs();

        rd_idx = 0;
        wr_idx = 0;
        foreach (accept_log[i]) begin
            if (accept_log[i].dir == AXI4_READ) begin
                if (rd_idx >= rd_reqs.size()) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf({"%s: more reads were accepted than ",
                                          "this phase issued"}, phase_label))
                    break;
                end
                failed |= check_accepted_request(accept_log[i],
                                                 rd_reqs[rd_idx], rd_idx);
                failed |= check_read_response(rd_reqs[rd_idx],
                                              rd_rsps[rd_idx], rd_idx);
                rd_idx++;
            end else begin
                if (wr_idx >= wr_reqs.size()) begin
                    failed = 1'b1;
                    `uvm_error(get_type_name(),
                               $sformatf({"%s: more writes were accepted ",
                                          "than this phase issued"},
                                         phase_label))
                    break;
                end
                failed |= check_accepted_request(accept_log[i],
                                                 wr_reqs[wr_idx], wr_idx);
                failed |= check_write_response(wr_reqs[wr_idx],
                                               wr_rsps[wr_idx], wr_idx);
                apply_write(wr_reqs[wr_idx]);
                wr_idx++;
            end
        end
        return failed;
    endfunction : replay_acceptance_order

    // Per direction, acceptance order must equal issue order
    protected function bit check_accepted_request(
        accept_rec_t     rec,
        axi4_transaction req,
        int unsigned     index
    );
        string kind;

        if (rec.dir == AXI4_WRITE)
            kind = "write";
        else
            kind = "read";
        if ((rec.id !== req.id) || (rec.addr !== req.addr) ||
            (rec.len != int'(req.len))) begin
            `uvm_error(get_type_name(),
                       $sformatf({"%s: the %s accepted in position %0d is ",
                                  "id=0x%0h addr=0x%0h len=%0d, but the ",
                                  "request issued in that position is ",
                                  "id=0x%0h addr=0x%0h len=%0d"},
                                 phase_label, kind,
                                 index, rec.id, rec.addr, rec.len,
                                 req.id, req.addr, int'(req.len)))
            return 1'b1;
        end
        return 1'b0;
    endfunction : check_accepted_request

    protected function bit check_read_response(
        axi4_transaction req,
        axi4_transaction rsp,
        int unsigned     index
    );
        bit failed;
        bit from_write;

        failed     = 1'b0;
        from_write = 1'b0;
        if (rsp.data.size() != (int'(req.len) + 1)) begin
            `uvm_error(get_type_name(),
                       $sformatf({"%s: read %0d at 0x%0h returned %0d beats, ",
                                  "expected %0d"},
                                 phase_label, index, req.addr,
                                 rsp.data.size(), int'(req.len) + 1))
            return 1'b1;
        end

        for (int unsigned beat = 0; beat < rsp.data.size(); beat++) begin
            bit [AXI4_ADDR_WIDTH-1:0] addr;
            bit [AXI4_DATA_WIDTH-1:0] expected;

            addr     = beat_address(req, beat);
            expected = shadow_read(addr);
            if (expected !== pattern_word(addr))
                from_write = 1'b1;

            if (rsp.rresp[beat] != AXI4_RESP_OKAY) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf("%s: read %0d beat %0d at 0x%0h returned %s",
                                     phase_label, index, beat, addr,
                                     rsp.rresp[beat].name()))
            end else if (rsp.data[beat] !== expected) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: read %0d beat %0d at 0x%0h ",
                                      "returned 0x%0h; in the order the ",
                                      "bridge accepted the requests it owes ",
                                      "0x%0h, so a request overtook another"},
                                     phase_label, index, beat, addr,
                                     rsp.data[beat], expected))
            end
        end

        if (from_write)
            ordered_reads++;
        return failed;
    endfunction : check_read_response

    protected function bit check_write_response(
        axi4_transaction req,
        axi4_transaction rsp,
        int unsigned     index
    );
        if (rsp.bresp != AXI4_RESP_OKAY) begin
            `uvm_error(get_type_name(),
                       $sformatf("%s: write %0d at 0x%0h returned %s",
                                 phase_label, index, req.addr,
                                 rsp.bresp.name()))
            return 1'b1;
        end
        return 1'b0;
    endfunction : check_write_response

    // One AHB run per accepted request, same order and length
    protected function bit check_ahb_runs();
        bit failed;

        failed = 1'b0;
        if (ahb_runs.size() != accept_log.size()) begin
            `uvm_error(get_type_name(),
                       $sformatf({"%s: %0d AHB bursts for %0d accepted AXI ",
                                  "requests; the bridge split or merged them\n",
                                  "  accepted: %s\n  observed: %s"},
                                 phase_label, ahb_runs.size(),
                                 accept_log.size(),
                                 accepted_summary(), ahb_run_summary()))
            return 1'b1;
        end

        foreach (accept_log[i]) begin
            ahb_dir_e expected_dir;

            expected_dir = (accept_log[i].dir == AXI4_WRITE) ? AHB_WRITE
                                                             : AHB_READ;
            if (ahb_runs[i].dir != expected_dir) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: AHB burst %0d is a %s, but the ",
                                      "request accepted in that position is ",
                                      "a %s; the two directions are ",
                                      "interleaved on AHB"},
                                     phase_label, i, ahb_runs[i].dir.name(),
                                     accept_log[i].dir.name()))
            end else if (ahb_runs[i].beats != (accept_log[i].len + 1)) begin
                failed = 1'b1;
                `uvm_error(get_type_name(),
                           $sformatf({"%s: AHB burst %0d carries %0d beats ",
                                      "for a request of %0d"},
                                     phase_label, i, ahb_runs[i].beats,
                                     accept_log[i].len + 1))
            end
        end
        return failed;
    endfunction : check_ahb_runs

    // The run must contain conflicting accesses, or the checks are vacuous
    protected function void check_run_was_conclusive();
        if (raw_pairs == 0)
            `uvm_error(get_type_name(),
                       {"No read was accepted straight after a write to the ",
                        "same address, so read-after-write ordering was ",
                        "never put at risk"})
        if (war_pairs == 0)
            `uvm_error(get_type_name(),
                       {"No write was accepted straight after a read of the ",
                        "same address, so write-after-read ordering was ",
                        "never put at risk"})
        if (ordered_reads == 0)
            `uvm_error(get_type_name(),
                       {"Every read returned the address pattern, so no read ",
                        "ever depended on an earlier write and the replay ",
                        "proved nothing"})
        if (r_bursts == 0)
            `uvm_error(get_type_name(),
                       "No read burst was observed on the R channel")
    endfunction : check_run_was_conclusive

    // Compact one-line pictures of the two orders, for the message above
    protected function string accepted_summary();
        string text;

        text = "";
        foreach (accept_log[i]) begin
            string mark;

            mark = (accept_log[i].dir == AXI4_WRITE) ? "W" : "R";
            if (i != 0)
                text = {text, " "};
            text = {text, $sformatf("%s%0d", mark, accept_log[i].len + 1)};
        end
        return text;
    endfunction : accepted_summary

    protected function string ahb_run_summary();
        string text;

        text = "";
        foreach (ahb_runs[i]) begin
            string mark;

            mark = (ahb_runs[i].dir == AHB_WRITE) ? "W" : "R";
            if (i != 0)
                text = {text, " "};
            text = {text, $sformatf("%s%0d", mark, ahb_runs[i].beats)};
        end
        return text;
    endfunction : ahb_run_summary

    // Neighbouring accesses to the same bytes (reported only)
    protected function void count_conflict_pairs();
        for (int unsigned i = 1; i < accept_log.size(); i++) begin
            if (!ranges_overlap(accept_log[i - 1], accept_log[i]))
                continue;
            if ((accept_log[i - 1].dir == AXI4_WRITE) &&
                (accept_log[i].dir == AXI4_READ))
                raw_pairs++;
            else if ((accept_log[i - 1].dir == AXI4_READ) &&
                     (accept_log[i].dir == AXI4_WRITE))
                war_pairs++;
            else if (accept_log[i - 1].dir == AXI4_WRITE)
                waw_pairs++;
        end
    endfunction : count_conflict_pairs

    protected function bit ranges_overlap(accept_rec_t a, accept_rec_t b);
        bit [AXI4_ADDR_WIDTH-1:0] a_lo;
        bit [AXI4_ADDR_WIDTH-1:0] a_hi;
        bit [AXI4_ADDR_WIDTH-1:0] b_lo;
        bit [AXI4_ADDR_WIDTH-1:0] b_hi;

        a_lo = a.addr - (a.addr % BUS_BYTES);
        b_lo = b.addr - (b.addr % BUS_BYTES);
        a_hi = a_lo + ((a.len + 1) * BUS_BYTES);
        b_hi = b_lo + ((b.len + 1) * BUS_BYTES);
        return (a_lo < b_hi) && (b_lo < a_hi);
    endfunction : ranges_overlap

    //-------------------------------------------------------------------------
    // Reference memory, mirroring the AHB slave model
    //-------------------------------------------------------------------------
    protected function void apply_write(axi4_transaction req);
        for (int unsigned beat = 0; beat < req.data.size(); beat++) begin
            bit [AXI4_ADDR_WIDTH-1:0] base;

            base = beat_address(req, beat);
            base = base - (base % BUS_BYTES);
            for (int unsigned lane = 0; lane < BUS_BYTES; lane++) begin
                if (req.strb[beat][lane])
                    shadow_mem[base + lane] = req.data[beat][8 * lane +: 8];
            end
        end
    endfunction : apply_write

    protected function bit [AXI4_DATA_WIDTH-1:0] shadow_read(
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        bit [AXI4_ADDR_WIDTH-1:0] base;
        bit [AXI4_DATA_WIDTH-1:0] word;

        base = addr - (addr % BUS_BYTES);
        word = pattern_word(base);
        for (int unsigned lane = 0; lane < BUS_BYTES; lane++) begin
            if (shadow_mem.exists(base + lane))
                word[8 * lane +: 8] = shadow_mem[base + lane];
        end
        return word;
    endfunction : shadow_read

    // Unwritten-word pattern (as in ahb_slv_driver)
    protected function bit [AXI4_DATA_WIDTH-1:0] pattern_word(
        bit [AXI4_ADDR_WIDTH-1:0] base
    );
        bit [63:0] addr64;
        bit [63:0] pattern;

        addr64  = base;
        pattern = {addr64[31:0], ~addr64[31:0]};
        return pattern[AXI4_DATA_WIDTH-1:0] ^ ahb_cfg.default_read_data;
    endfunction : pattern_word

    //-------------------------------------------------------------------------
    // Address helpers
    //-------------------------------------------------------------------------
    protected function bit [AXI4_ADDR_WIDTH-1:0] slot_addr(int unsigned slot);
        return base_addr + (slot * slot_bytes);
    endfunction : slot_addr

    protected function bit [AXI4_ADDR_WIDTH-1:0] beat_address(
        axi4_transaction req,
        int unsigned     beat
    );
        int unsigned              bytes;
        bit [AXI4_ADDR_WIDTH-1:0] aligned;

        bytes   = 1 << int'(req.size);
        aligned = req.addr - (req.addr % bytes);
        if (req.burst == AXI4_BURST_WRAP) begin
            int unsigned              span;
            bit [AXI4_ADDR_WIDTH-1:0] wrap_base;

            span      = (int'(req.len) + 1) * bytes;
            wrap_base = aligned - (aligned % span);
            return wrap_base +
                   ((aligned - wrap_base + (beat * bytes)) % span);
        end
        return aligned + (beat * bytes);
    endfunction : beat_address

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    protected function axi4_transaction make_request(
        axi4_dir_e                dir,
        axi4_burst_e              burst,
        int unsigned              len,
        bit [AXI4_ADDR_WIDTH-1:0] addr,
        bit [AXI4_ID_WIDTH-1:0]   id,
        string                    label
    );
        axi4_transaction req;
        axi4_dir_e       req_dir;
        axi4_burst_e     req_burst;
        int unsigned     req_len;

        req_dir   = dir;
        req_burst = burst;
        req_len   = len;
        req = axi4_transaction::type_id::create(label);
        if (!req.randomize() with {
                dir      == local::req_dir;
                id       == local::id;
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == local::req_burst;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf({"%s: randomization failed for %s len=%0d ",
                                  "addr=0x%0h"},
                                 label, burst.name(), len, addr))

        if (dir == AXI4_WRITE) begin
            // Unique data per request and beat
            data_tag++;
            foreach (req.data[beat]) begin
                for (int unsigned lane = 0; lane < BUS_BYTES; lane++)
                    req.data[beat][8 * lane +: 8] =
                        8'(8'h40 + (data_tag * 13) + (beat * 7) + (lane * 3));
                req.strb[beat] = '1;
            end
        end
        return req;
    endfunction : make_request

    //-------------------------------------------------------------------------
    // Knob validation
    //-------------------------------------------------------------------------
    // Slot = twice the longest burst, dividing 1 KB (no 1 KB split)
    protected function void validate_knobs();
        int unsigned max_bytes;

        max_bytes = MAX_BEATS * BUS_BYTES;
        if (slot_bytes < (2 * max_bytes))
            `uvm_fatal(get_type_name(),
                       $sformatf("slot_bytes must be at least %0d bytes",
                                 2 * max_bytes))
        if ((slot_bytes == 0) || ((1024 % slot_bytes) != 0))
            `uvm_fatal(get_type_name(),
                       "slot_bytes must be a non-zero divisor of 1024")
        if ((base_addr % slot_bytes) != 0)
            `uvm_fatal(get_type_name(),
                       "base_addr must be a multiple of slot_bytes")
        if (stress_slots == 0)
            `uvm_fatal(get_type_name(), "stress_slots must be non-zero")
        if (stress_requests < 2)
            `uvm_fatal(get_type_name(),
                       "stress_requests must be at least 2")
    endfunction : validate_knobs

endclass : axi4_mst_ordering_seq
