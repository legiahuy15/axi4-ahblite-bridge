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

    // Oldest declared-timeout request of this direction and ID whose
    // completion has not been dropped yet
    protected function scoreboard_axi_ctx find_timed_out_ctx(
        axi4_dir_e              dir,
        bit [AXI4_ID_WIDTH-1:0] id
    );
        foreach (pending_ctx_queue[i]) begin
            scoreboard_axi_ctx ctx;

            ctx = pending_ctx_queue[i];
            if (ctx.timed_out && !ctx.response_dropped &&
                (ctx.tr.dir == dir) && (ctx.tr.id == id))
                return ctx;
        end
        return null;
    endfunction : find_timed_out_ctx

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
                missed_timeouts++;
                `uvm_error(get_type_name(),
                           $sformatf({"Declared timeout on %s id=0x%0h ",
                                      "completed without SLVERR"},
                                     tr.dir.name(), tr.id))
            end
            timed_out_ctx.timed_out = 1'b0;
            timed_out_ctx           = null;
        end
        if (timed_out_ctx != null) begin
            timed_out_ctx.response_dropped = 1'b1;
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
                mismatched_ahb++;
                `uvm_error(get_type_name(),
                           $sformatf({"AHB request mismatch\n",
                                     "  expected: %s\n",
                                     "  actual  : %s"},
                                     expected_tr.sprint(),
                                     actual_tr.sprint()))
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
            // A declared timeout forces SLVERR whatever the AHB side said, so
            // the rebuilt completion is not an oracle for it
            if (!active_ctx.timed_out)
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
                mismatched_axi++;
                `uvm_error(get_type_name(),
                           $sformatf({"AXI completion mismatch\n",
                                     "  expected: %s\n",
                                     "  actual  : %s"},
                                     expected_tr.sprint(),
                                     actual_tr.sprint()))
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
        foreach (pending_ctx_queue[i])
            if (pending_ctx_queue[i].timed_out &&
                !pending_ctx_queue[i].response_dropped)
                `uvm_error(get_type_name(),
                           $sformatf({"Declared timeout on %s id=0x%0h never ",
                                      "returned an AXI completion"},
                                     pending_ctx_queue[i].tr.dir.name(),
                                     pending_ctx_queue[i].tr.id))
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