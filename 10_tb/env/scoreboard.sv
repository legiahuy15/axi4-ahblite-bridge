//=============================================================================
// File        : scoreboard.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge request and response scoreboard.
//               Observed AHB beats are matched to predicted requests without
//               relying on the order in which requests were predicted: a new
//               AHB transfer sequence is assigned to the pending request whose
//               first predicted beat has the same direction and address, and
//               the bridge's following beats stay with that request until it
//               completes (the bridge serves one request at a time). AXI
//               completions are matched by direction and ID.
//               Included inside the bridge package.
//=============================================================================

`uvm_analysis_imp_decl(_expected_ahb)
`uvm_analysis_imp_decl(_actual_ahb)
`uvm_analysis_imp_decl(_expected_axi)
`uvm_analysis_imp_decl(_actual_axi)

// Faults bridge_mutation_test asks the scoreboard to put into the stream it
// observes, one at a time, to find out whether the comparison notices. They
// name a field of ahb_request_matches or of axi_transaction_matches, both of
// which are hand-written lists, so a field quietly left out of one of them
// is the bug this is looking for. There is deliberately no entry for the
// ID: completions are paired with their request by direction and ID, so a
// corrupted one would not be compared and found wrong, it would simply
// never be paired.
typedef enum {
    MUT_NONE,
    MUT_AHB_ADDR,
    MUT_AHB_DIR,
    MUT_AHB_TRANS,
    MUT_AHB_BURST,
    MUT_AHB_SIZE,
    MUT_AHB_PROT,
    MUT_AHB_MASTLOCK,
    MUT_AHB_WDATA,
    MUT_AXI_ADDR,
    MUT_AXI_LEN,
    MUT_AXI_RESP,
    MUT_AXI_DATA,
    MUT_AXI_STRB
} mutation_e;

class scoreboard extends uvm_scoreboard;

    `uvm_component_utils(scoreboard)

    //-------------------------------------------------------------------------
    // Analysis interfaces
    //-------------------------------------------------------------------------
    uvm_analysis_imp_expected_ahb #(ahb_transfer, scoreboard)
        expected_ahb_export;
    uvm_analysis_imp_actual_ahb #(ahb_transfer, scoreboard)
        actual_ahb_export;
    uvm_analysis_imp_expected_axi #(axi4_transaction, scoreboard)
        expected_axi_export;
    uvm_analysis_imp_actual_axi #(axi4_transaction, scoreboard)
        actual_axi_export;

    //-------------------------------------------------------------------------
    // Comparison state
    //-------------------------------------------------------------------------
    // Requests whose AHB beats are not all observed yet, in prediction order
    protected scoreboard_axi_ctx pending_ctx_queue[$];
    // Request currently receiving observed AHB beats
    protected scoreboard_axi_ctx active_ctx;
    // Request receiving predicted beats (the predictor sends a request and
    // then all of its beats in the same call)
    protected scoreboard_axi_ctx predict_ctx;
    protected ahb_transfer       actual_ahb_queue[$];
    protected axi4_transaction   completed_axi_queue[$];
    protected axi4_transaction   actual_axi_queue[$];

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    protected int unsigned matched_ahb;
    protected int unsigned mismatched_ahb;
    protected int unsigned matched_axi;
    protected int unsigned mismatched_axi;
    protected int unsigned timed_out_requests;
    protected int unsigned timed_out_beats;
    protected int unsigned missed_timeouts;

    //-------------------------------------------------------------------------
    // Declared timeouts
    //-------------------------------------------------------------------------
    // Direction and ID of requests the test expects the C_DPHASE_TIMEOUT
    // watchdog to abandon, oldest first. Each key is consumed by the next
    // predicted request that matches it.
    typedef struct {
        axi4_dir_e              dir;
        bit [AXI4_ID_WIDTH-1:0] id;
        bit                     strict;
    } timeout_key_t;

    protected timeout_key_t timeout_keys[$];

    // Requests the watchdog abandoned, taken out of the live queues once their
    // AXI completion was dropped. The AHB slave is still counting out the wait
    // of the beat the bridge walked away from, so that one beat is reported by
    // the monitor after the AXI side has already finished; it is matched here
    // and discarded instead of being attributed to the next request.
    protected scoreboard_axi_ctx abandoned_ctx_queue[$];

    // Declared requests whose AXI completion has not arrived yet, in
    // declaration order. Kept separate from pending_ctx_queue so a request
    // stays findable after its beats have all been accounted for.
    protected scoreboard_axi_ctx declared_ctx_queue[$];

    //-------------------------------------------------------------------------
    // Fault injection, used only by bridge_mutation_test
    //-------------------------------------------------------------------------
    // While mutation_mode is set, a comparison that fails is reported as a
    // caught fault rather than as an error, so the suite can run inside the
    // regression without turning it red. It is the counts that decide the
    // verdict: every fault armed has to be caught, and nothing may be caught
    // that was not armed.
    protected bit          mutation_mode;
    protected mutation_e   pending_ahb_mut = MUT_NONE;
    // Beats to let past before the fault goes in. The first beat of a
    // request is the one find_start_ctx uses to bind the context, by
    // direction and address, so corrupting that one stops the beat being
    // attributed at all instead of being compared and found wrong.
    protected int unsigned pending_ahb_skip;
    protected mutation_e   pending_axi_mut = MUT_NONE;
    protected int unsigned mutations_armed;
    protected int unsigned mutations_caught;

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
        expected_ahb_export = new("expected_ahb_export", this);
        actual_ahb_export   = new("actual_ahb_export", this);
        expected_axi_export = new("expected_axi_export", this);
        actual_axi_export   = new("actual_axi_export", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Fault injection interface
    //-------------------------------------------------------------------------
    function void set_mutation_mode(bit enable);
        mutation_mode = enable;
    endfunction : set_mutation_mode

    // Armed one at a time: the next observed AHB beat, or the next observed
    // AXI completion, is corrupted in the named field before it is compared
    function void inject_ahb_mutation(mutation_e kind, int unsigned skip = 1);
        if (!mutation_mode)
            `uvm_fatal(get_type_name(),
                       "Fault injection needs mutation mode")
        pending_ahb_mut  = kind;
        pending_ahb_skip = skip;
        mutations_armed++;
    endfunction : inject_ahb_mutation

    function void inject_axi_mutation(mutation_e kind);
        if (!mutation_mode)
            `uvm_fatal(get_type_name(),
                       "Fault injection needs mutation mode")
        pending_axi_mut = kind;
        mutations_armed++;
    endfunction : inject_axi_mutation

    // Still armed means the comparison let the fault through
    function bit injection_pending();
        return ((pending_ahb_mut != MUT_NONE) ||
                (pending_axi_mut != MUT_NONE));
    endfunction : injection_pending

    function void clear_injection();
        pending_ahb_mut = MUT_NONE;
        pending_axi_mut = MUT_NONE;
    endfunction : clear_injection

    function int unsigned faults_armed();
        return mutations_armed;
    endfunction : faults_armed

    function int unsigned faults_caught();
        return mutations_caught;
    endfunction : faults_caught

    protected function void apply_ahb_mutation(ahb_transfer tr);
        case (pending_ahb_mut)
            MUT_AHB_ADDR:     tr.addr     = tr.addr ^ 'h40;
            MUT_AHB_DIR:      tr.write    = (tr.write == AHB_WRITE) ? AHB_READ
                                                                    : AHB_WRITE;
            MUT_AHB_TRANS:    tr.trans    = (tr.trans == AHB_TRANS_NONSEQ) ?
                                                AHB_TRANS_SEQ : AHB_TRANS_NONSEQ;
            MUT_AHB_BURST:    tr.burst    = (tr.burst == AHB_BURST_SINGLE) ?
                                                AHB_BURST_INCR4 : AHB_BURST_SINGLE;
            MUT_AHB_SIZE:     tr.size     = (tr.size == AHB_SIZE_1BYTE) ?
                                                AHB_SIZE_2BYTE : AHB_SIZE_1BYTE;
            MUT_AHB_PROT:     tr.prot     = ~tr.prot;
            MUT_AHB_MASTLOCK: tr.mastlock = ~tr.mastlock;
            MUT_AHB_WDATA:    tr.wdata    = ~tr.wdata;
            default: ;
        endcase
        pending_ahb_mut = MUT_NONE;
    endfunction : apply_ahb_mutation

    protected function void apply_axi_mutation(axi4_transaction tr);
        case (pending_axi_mut)
            MUT_AXI_ADDR: tr.addr = tr.addr ^ 'h40;
            MUT_AXI_LEN:  tr.len  = tr.len + 1;
            MUT_AXI_RESP: begin
                if (tr.dir == AXI4_WRITE)
                    tr.bresp = (tr.bresp == AXI4_RESP_OKAY) ? AXI4_RESP_SLVERR
                                                            : AXI4_RESP_OKAY;
                else if (tr.rresp.size() != 0)
                    tr.rresp[0] = (tr.rresp[0] == AXI4_RESP_OKAY) ?
                                      AXI4_RESP_SLVERR : AXI4_RESP_OKAY;
            end
            MUT_AXI_DATA: begin
                if (tr.data.size() != 0)
                    tr.data[0] = ~tr.data[0];
            end
            MUT_AXI_STRB: begin
                if (tr.strb.size() != 0)
                    tr.strb[0] = ~tr.strb[0];
            end
            default: ;
        endcase
        pending_axi_mut = MUT_NONE;
    endfunction : apply_axi_mutation

    // One place decides how a failed comparison is reported, so an injected
    // fault and a real one cannot drift apart
    protected function void report_mismatch(string message);
        if (mutation_mode) begin
            mutations_caught++;
            `uvm_info(get_type_name(),
                      $sformatf("[SCB][MUTATION] caught: %s", message),
                      UVM_MEDIUM)
        end else begin
            `uvm_error(get_type_name(), message)
        end
    endfunction : report_mismatch

    //-------------------------------------------------------------------------
    // Declared timeouts
    //-------------------------------------------------------------------------
    // Called by the stimulus before it sends a request whose AHB data phase
    // the watchdog will abandon. Without it such a request looks like a
    // bridge fault: the beats after the abandoned one are never issued and
    // the completion carries the forced SLVERR instead of the AHB response.
    // The response itself is checked by the sequence, and the AHB side by
    // bridge_timeout_recovery_test.
    function void expect_timeout(
        axi4_dir_e              dir,
        bit [AXI4_ID_WIDTH-1:0] id
    );
        // A declaration that will not come true is itself a fault the suite
        // arms, so it is counted like the field mutations
        if (mutation_mode)
            mutations_armed++;
        timeout_keys.push_back('{dir, id, 1'b1});
    endfunction : expect_timeout

    // For stimulus that sweeps the threshold and so cannot say in advance
    // which side of it a wait falls on. A request that times out is dropped
    // like a declared one; a request that completes is compared as usual.
    // It relies on SLVERR meaning "watchdog", so the AHB slave must answer
    // OKAY throughout such a test.
    function void allow_timeout(
        axi4_dir_e              dir,
        bit [AXI4_ID_WIDTH-1:0] id
    );
        timeout_keys.push_back('{dir, id, 1'b0});
    endfunction : allow_timeout

    protected function bit take_timeout_key(
        axi4_dir_e              dir,
        bit [AXI4_ID_WIDTH-1:0] id,
        output bit              strict
    );
        foreach (timeout_keys[i]) begin
            if ((timeout_keys[i].dir == dir) && (timeout_keys[i].id == id)) begin
                strict = timeout_keys[i].strict;
                timeout_keys.delete(i);
                return 1'b1;
            end
        end
        strict = 1'b0;
        return 1'b0;
    endfunction : take_timeout_key

    protected function bit response_is_timeout(axi4_transaction tr);
        if (tr.dir == AXI4_WRITE)
            return (tr.bresp == AXI4_RESP_SLVERR);
        foreach (tr.rresp[i])
            if (tr.rresp[i] == AXI4_RESP_SLVERR)
                return 1'b1;
        return 1'b0;
    endfunction : response_is_timeout

    // Oldest declared request of this direction and ID still waiting for its
    // completion. It is looked up in its own list rather than in
    // pending_ctx_queue, because the beat the watchdog cancelled can be
    // reported before the AXI completion arrives, and that removes the
    // request from pending_ctx_queue on the way.
    protected function scoreboard_axi_ctx find_timed_out_ctx(
        axi4_dir_e              dir,
        bit [AXI4_ID_WIDTH-1:0] id
    );
        foreach (declared_ctx_queue[i]) begin
            scoreboard_axi_ctx ctx;

            ctx = declared_ctx_queue[i];
            if ((ctx.tr.dir == dir) && (ctx.tr.id == id))
                return ctx;
        end
        return null;
    endfunction : find_timed_out_ctx

    protected function void forget_declared_ctx(scoreboard_axi_ctx ctx);
        foreach (declared_ctx_queue[i]) begin
            if (declared_ctx_queue[i] == ctx) begin
                declared_ctx_queue.delete(i);
                return;
            end
        end
    endfunction : forget_declared_ctx

    // The completion rebuilt from the AHB beats of a request the watchdog took
    // is not an oracle for it, so it is withdrawn rather than compared
    protected function void drop_rebuilt_completion(
        axi4_dir_e              dir,
        bit [AXI4_ID_WIDTH-1:0] id
    );
        foreach (completed_axi_queue[i]) begin
            if ((completed_axi_queue[i].dir == dir) &&
                (completed_axi_queue[i].id  == id)) begin
                completed_axi_queue.delete(i);
                return;
            end
        end
    endfunction : drop_rebuilt_completion

    //-------------------------------------------------------------------------
    // Analysis callbacks
    //-------------------------------------------------------------------------
    function void write_expected_axi(axi4_transaction tr);
        axi4_transaction copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Expected AXI template clone failed")
        predict_ctx = new(copy_tr);
        predict_ctx.timed_out = take_timeout_key(copy_tr.dir, copy_tr.id,
                                                 predict_ctx.timeout_strict);
        pending_ctx_queue.push_back(predict_ctx);
        if (predict_ctx.timed_out)
            declared_ctx_queue.push_back(predict_ctx);
    endfunction : write_expected_axi

    function void write_expected_ahb(ahb_transfer tr);
        ahb_transfer copy_tr;

        if (predict_ctx == null) begin
            `uvm_error(get_type_name(),
                       "Predicted AHB beat has no corresponding AXI request")
            return;
        end
        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Expected AHB transfer clone failed")
        predict_ctx.expected_beats.push_back(copy_tr);
        compare_ahb_queues();
    endfunction : write_expected_ahb

    function void write_actual_ahb(ahb_transfer tr);
        ahb_transfer copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Actual AHB transfer clone failed")
        // Corrupt the observed beat before it is compared, so the
        // comparison is the only thing that can notice
        if (pending_ahb_mut != MUT_NONE) begin
            if (pending_ahb_skip != 0)
                pending_ahb_skip--;
            else
                apply_ahb_mutation(copy_tr);
        end
        actual_ahb_queue.push_back(copy_tr);
        compare_ahb_queues();
    endfunction : write_actual_ahb

    function void write_actual_axi(axi4_transaction tr);
        axi4_transaction   copy_tr;
        scoreboard_axi_ctx timed_out_ctx;

        // Dropped as soon as it arrives, so it can never be mistaken later for
        // the completion of another request with the same direction and ID
        timed_out_ctx = find_timed_out_ctx(tr.dir, tr.id);
        if ((timed_out_ctx != null) && !response_is_timeout(tr)) begin
            // A declared request that completed instead. Permissive on a
            // threshold sweep, a fault when the test said it must time out.
            if (timed_out_ctx.timeout_strict) begin
                if (!mutation_mode)
                    missed_timeouts++;
                report_mismatch($sformatf({"Declared timeout on %s id=0x%0h ",
                                           "completed without SLVERR"},
                                          tr.dir.name(), tr.id));
            end
            timed_out_ctx.timed_out = 1'b0;
            forget_declared_ctx(timed_out_ctx);
            timed_out_ctx = null;
        end
        if (timed_out_ctx != null) begin
            timed_out_ctx.response_dropped = 1'b1;
            forget_declared_ctx(timed_out_ctx);
            // The beats may all have been accounted for already, in which case
            // a completion was rebuilt for this request; withdraw it
            drop_rebuilt_completion(tr.dir, tr.id);
            timed_out_requests++;
            // Taken out of the live queues at once: the bridge has finished
            // with it, so it must not keep receiving the next request's beats
            foreach (pending_ctx_queue[i]) begin
                if (pending_ctx_queue[i] == timed_out_ctx) begin
                    pending_ctx_queue.delete(i);
                    break;
                end
            end
            if (active_ctx == timed_out_ctx)
                active_ctx = null;
            abandoned_ctx_queue.push_back(timed_out_ctx);
            `uvm_info(get_type_name(),
                      $sformatf({"[SCB][AXI][TIMEOUT] %s | resp=%s | ",
                                 "declared timeout, not compared"},
                                tr.convert2string(),
                                (tr.dir == AXI4_WRITE) ? tr.bresp.name()
                                                       : "per beat"),
                      UVM_MEDIUM)
            return;
        end

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Actual AXI transaction clone failed")
        if (pending_axi_mut != MUT_NONE)
            apply_axi_mutation(copy_tr);
        actual_axi_queue.push_back(copy_tr);
        compare_axi_queues();
    endfunction : write_actual_axi

    //-------------------------------------------------------------------------
    // AHB request comparison
    //-------------------------------------------------------------------------
    // A beat of a request the watchdog already abandoned, reported after its
    // AXI completion was dropped. Matched on direction and address so it can
    // never swallow a beat that belongs to a live request.
    protected function bit take_abandoned_beat(ahb_transfer actual_tr);
        foreach (abandoned_ctx_queue[i]) begin
            scoreboard_axi_ctx ctx;

            ctx = abandoned_ctx_queue[i];
            if ((ctx.expected_beats.size() > 0) &&
                (ctx.expected_beats[0].write == actual_tr.write) &&
                (ctx.expected_beats[0].addr  == actual_tr.addr)) begin
                void'(ctx.expected_beats.pop_front());
                timed_out_beats++;
                `uvm_info(get_type_name(),
                          $sformatf({"[SCB][AHB][TIMEOUT] %s | beat of an ",
                                     "abandoned request, not compared"},
                                    actual_tr.convert2string()),
                          UVM_HIGH)
                return 1'b1;
            end
        end
        return 1'b0;
    endfunction : take_abandoned_beat

    protected function void compare_ahb_queues();
        while (actual_ahb_queue.size() > 0) begin
            ahb_transfer expected_tr;
            ahb_transfer actual_tr;

            if ((abandoned_ctx_queue.size() > 0) &&
                take_abandoned_beat(actual_ahb_queue[0])) begin
                void'(actual_ahb_queue.pop_front());
                continue;
            end

            if (active_ctx == null) begin
                active_ctx = find_start_ctx(actual_ahb_queue[0]);
                // The request has not been predicted yet (for example a write
                // whose AHB beats start before WLAST); retry on the next call
                if (active_ctx == null)
                    break;
                active_ctx.started = 1'b1;
            end
            // The predictor sends beats one at a time; wait for the next one.
            // Extra observed beats remain queued and fail in check_phase.
            if (active_ctx.expected_beats.size() == 0)
                break;

            expected_tr = active_ctx.expected_beats.pop_front();
            actual_tr   = actual_ahb_queue.pop_front();

            if (ahb_request_matches(expected_tr, actual_tr)) begin
                matched_ahb++;
                `uvm_info(get_type_name(),
                          $sformatf({"[SCB][AHB][PASS] %s | data=0x%0h ",
                                     "| total=%0d"},
                                    actual_tr.convert2string(),
                                    (actual_tr.write == AHB_WRITE) ?
                                        actual_tr.wdata : actual_tr.rdata,
                                    matched_ahb),
                          UVM_HIGH)
            end else begin
                if (!mutation_mode)
                    mismatched_ahb++;
                report_mismatch($sformatf({"AHB request mismatch\n",
                                           "  expected: %s\n",
                                           "  actual  : %s"},
                                          expected_tr.sprint(),
                                          actual_tr.sprint()));
            end

            update_axi_completion(actual_tr);
        end
    endfunction : compare_ahb_queues

    // Pending request that an observed transfer starts: first choice is the
    // oldest unstarted request whose first predicted beat has the same
    // direction and address; otherwise the oldest unstarted request of the
    // same direction, so a wrong address is still reported as a mismatch.
    protected function scoreboard_axi_ctx find_start_ctx(ahb_transfer actual_tr);
        foreach (pending_ctx_queue[i]) begin
            scoreboard_axi_ctx ctx;

            ctx = pending_ctx_queue[i];
            if (!ctx.started && (ctx.expected_beats.size() > 0) &&
                (ctx.expected_beats[0].write == actual_tr.write) &&
                (ctx.expected_beats[0].addr  == actual_tr.addr))
                return ctx;
        end
        foreach (pending_ctx_queue[i]) begin
            scoreboard_axi_ctx ctx;

            ctx = pending_ctx_queue[i];
            if (!ctx.started && (ctx.expected_beats.size() > 0) &&
                (ctx.expected_beats[0].write == actual_tr.write))
                return ctx;
        end
        return null;
    endfunction : find_start_ctx

    protected function bit ahb_request_matches(
        ahb_transfer expected_tr,
        ahb_transfer actual_tr
    );
        bit is_match;

        is_match  = (expected_tr.addr     == actual_tr.addr);
        is_match &= (expected_tr.write    == actual_tr.write);
        is_match &= (expected_tr.trans    == actual_tr.trans);
        is_match &= (expected_tr.burst    == actual_tr.burst);
        is_match &= (expected_tr.size     == actual_tr.size);
        is_match &= (expected_tr.prot     == actual_tr.prot);
        is_match &= (expected_tr.mastlock == actual_tr.mastlock);
        if (expected_tr.write == AHB_WRITE)
            is_match &= (expected_tr.wdata == actual_tr.wdata);
        return is_match;
    endfunction : ahb_request_matches

    //-------------------------------------------------------------------------
    // AXI completion prediction
    //-------------------------------------------------------------------------
    protected function void update_axi_completion(ahb_transfer ahb_tr);
        int unsigned beat_count;

        beat_count = int'(active_ctx.tr.len) + 1;
        if (active_ctx.beat_index >= beat_count) begin
            `uvm_error(get_type_name(), "AXI completion beat index overflow")
            return;
        end

        if (active_ctx.tr.dir == AXI4_WRITE) begin
            if (ahb_tr.resp == AHB_RESP_ERROR)
                active_ctx.write_error = 1'b1;
        end else begin
            active_ctx.tr.data[active_ctx.beat_index] = ahb_tr.rdata;
            active_ctx.tr.rresp[active_ctx.beat_index] =
                (ahb_tr.resp == AHB_RESP_ERROR) ? AXI4_RESP_SLVERR
                                                : AXI4_RESP_OKAY;
        end

        active_ctx.beat_index++;
        if (active_ctx.beat_index == beat_count) begin
            foreach (pending_ctx_queue[i]) begin
                if (pending_ctx_queue[i] == active_ctx) begin
                    pending_ctx_queue.delete(i);
                    break;
                end
            end
            if (active_ctx.tr.dir == AXI4_WRITE)
                active_ctx.tr.bresp = active_ctx.write_error ? AXI4_RESP_SLVERR
                                                             : AXI4_RESP_OKAY;
            // Always rebuilt: whether a declared request actually timed out is
            // only known when its AXI completion arrives, which may be after
            // its beats. The drop path withdraws this again if it did.
            completed_axi_queue.push_back(active_ctx.tr);
            active_ctx = null;
            compare_axi_queues();
        end
    endfunction : update_axi_completion

    //-------------------------------------------------------------------------
    // AXI response comparison
    //-------------------------------------------------------------------------
    // Each observed completion is matched with the oldest reconstructed
    // completion of the same direction and ID.
    protected function void compare_axi_queues();
        int unsigned actual_index;

        actual_index = 0;
        while (actual_index < actual_axi_queue.size()) begin
            axi4_transaction actual_tr;
            axi4_transaction expected_tr;
            int              expected_index;

            actual_tr      = actual_axi_queue[actual_index];
            expected_index = -1;
            foreach (completed_axi_queue[i]) begin
                if ((completed_axi_queue[i].dir == actual_tr.dir) &&
                    (completed_axi_queue[i].id  == actual_tr.id)) begin
                    expected_index = i;
                    break;
                end
            end
            if (expected_index < 0) begin
                actual_index++;
                continue;
            end

            expected_tr = completed_axi_queue[expected_index];
            completed_axi_queue.delete(expected_index);
            actual_axi_queue.delete(actual_index);

            if (axi_transaction_matches(expected_tr, actual_tr)) begin
                matched_axi++;
                if (actual_tr.dir == AXI4_WRITE)
                    `uvm_info(get_type_name(),
                              $sformatf({"[SCB][AXI][PASS] %s | bresp=%s ",
                                         "| total=%0d"},
                                        actual_tr.convert2string(),
                                        actual_tr.bresp.name(), matched_axi),
                              UVM_HIGH)
                else
                    `uvm_info(get_type_name(),
                              $sformatf({"[SCB][AXI][PASS] %s | ",
                                         "read beats=%0d | total=%0d"},
                                        actual_tr.convert2string(),
                                        actual_tr.data.size(), matched_axi),
                              UVM_HIGH)
            end else begin
                if (!mutation_mode)
                    mismatched_axi++;
                report_mismatch($sformatf({"AXI completion mismatch
",
                                           "  expected: %s
",
                                           "  actual  : %s"},
                                          expected_tr.sprint(),
                                          actual_tr.sprint()));
            end
        end
    endfunction : compare_axi_queues

    protected function bit axi_transaction_matches(
        axi4_transaction expected_tr,
        axi4_transaction actual_tr
    );
        bit is_match;

        is_match  = (expected_tr.dir   == actual_tr.dir);
        is_match &= (expected_tr.id    == actual_tr.id);
        is_match &= (expected_tr.addr  == actual_tr.addr);
        is_match &= (expected_tr.len   == actual_tr.len);
        is_match &= (expected_tr.size  == actual_tr.size);
        is_match &= (expected_tr.burst == actual_tr.burst);
        is_match &= (expected_tr.lock  == actual_tr.lock);
        is_match &= (expected_tr.cache == actual_tr.cache);
        is_match &= (expected_tr.prot  == actual_tr.prot);
        is_match &= (expected_tr.data.size() == actual_tr.data.size());

        if (expected_tr.dir == AXI4_WRITE) begin
            is_match &= (expected_tr.strb.size() == actual_tr.strb.size());
            is_match &= (expected_tr.bresp == actual_tr.bresp);
            if ((expected_tr.data.size() == actual_tr.data.size()) &&
                (expected_tr.strb.size() == actual_tr.strb.size())) begin
                foreach (expected_tr.data[i]) begin
                    is_match &= (expected_tr.data[i] == actual_tr.data[i]);
                    is_match &= (expected_tr.strb[i] == actual_tr.strb[i]);
                end
            end
        end else begin
            is_match &= (expected_tr.rresp.size() == actual_tr.rresp.size());
            if ((expected_tr.data.size() == actual_tr.data.size()) &&
                (expected_tr.rresp.size() == actual_tr.rresp.size())) begin
                foreach (expected_tr.data[i]) begin
                    is_match &= (expected_tr.data[i] == actual_tr.data[i]);
                    is_match &= (expected_tr.rresp[i] == actual_tr.rresp[i]);
                end
            end
        end

        return is_match;
    endfunction : axi_transaction_matches

    //-------------------------------------------------------------------------
    // Reset handling
    //-------------------------------------------------------------------------
    function void reset_state();
        pending_ctx_queue.delete();
        active_ctx  = null;
        predict_ctx = null;
        actual_ahb_queue.delete();
        completed_axi_queue.delete();
        actual_axi_queue.delete();
        timeout_keys.delete();
        abandoned_ctx_queue.delete();
        declared_ctx_queue.delete();
        pending_ahb_mut  = MUT_NONE;
        pending_axi_mut  = MUT_NONE;
        pending_ahb_skip = 0;
    endfunction : reset_state

    //-------------------------------------------------------------------------
    // End-of-test checks
    //-------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        int unsigned unmatched_expected_ahb;
        int unsigned pending_requests;

        super.check_phase(phase);

        // Beats the watchdog cancelled are expected to be missing, so they are
        // taken out of the balance rather than reported as lost
        unmatched_expected_ahb = 0;
        pending_requests       = 0;
        foreach (pending_ctx_queue[i]) begin
            unmatched_expected_ahb += pending_ctx_queue[i].expected_beats.size();
            pending_requests++;
        end
        foreach (abandoned_ctx_queue[i])
            timed_out_beats += abandoned_ctx_queue[i].expected_beats.size();

        if ((unmatched_expected_ahb != 0) || (actual_ahb_queue.size() != 0))
            `uvm_error(get_type_name(),
                       $sformatf("Unmatched AHB transfers: expected=%0d actual=%0d",
                                 unmatched_expected_ahb,
                                 actual_ahb_queue.size()))

        // An abandoned request is removed from the live queues as soon as its
        // completion is dropped, so anything still here is unfinished
        if ((pending_requests != 0) || (active_ctx != null) ||
            (completed_axi_queue.size() != 0) ||
            (actual_axi_queue.size() != 0))
            `uvm_error(get_type_name(),
                       $sformatf({"Unmatched AXI transactions: pending=%0d ",
                                  "expected=%0d actual=%0d"},
                                 pending_requests,
                                 completed_axi_queue.size(),
                                 actual_axi_queue.size()))

        // A declared timeout that never happened is a hole in the test, not a
        // pass: the watchdog was expected to abandon a request and did not
        if (timeout_keys.size() != 0)
            `uvm_error(get_type_name(),
                       $sformatf({"%0d declared timeout(s) were never matched ",
                                  "to a predicted request"},
                                 timeout_keys.size()))
        foreach (declared_ctx_queue[i])
            `uvm_error(get_type_name(),
                       $sformatf({"Declared timeout on %s id=0x%0h never ",
                                  "returned an AXI completion"},
                                 declared_ctx_queue[i].tr.dir.name(),
                                 declared_ctx_queue[i].tr.id))
        if (missed_timeouts != 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d declared timeout(s) did not time out",
                                 missed_timeouts))

        // A test that compares nothing must not pass silently
        if (((matched_ahb + mismatched_ahb) == 0) ||
            ((matched_axi + mismatched_axi) == 0))
            `uvm_error(get_type_name(),
                       $sformatf({"No transactions compared: AHB=%0d AXI=%0d ",
                                  "(stimulus missing or not observed)"},
                                 matched_ahb + mismatched_ahb,
                                 matched_axi + mismatched_axi))
    endfunction : check_phase

    //-------------------------------------------------------------------------
    // Report phase
    //-------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
                  $sformatf({"Scoreboard summary: AHB match/mismatch=%0d/%0d, ",
                             "AXI match/mismatch=%0d/%0d"},
                            matched_ahb, mismatched_ahb,
                            matched_axi, mismatched_axi), UVM_LOW)
        if (timed_out_requests != 0)
            `uvm_info(get_type_name(),
                      $sformatf({"Scoreboard timeouts: requests=%0d, ",
                                 "cancelled AHB beats=%0d (declared by the ",
                                 "test, not compared)"},
                                timed_out_requests, timed_out_beats), UVM_LOW)
    endfunction : report_phase

endclass : scoreboard