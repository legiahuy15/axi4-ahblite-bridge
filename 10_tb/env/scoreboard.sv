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
    // Analysis callbacks
    //-------------------------------------------------------------------------
    function void write_expected_axi(axi4_transaction tr);
        axi4_transaction copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Expected AXI template clone failed")
        predict_ctx = new(copy_tr);
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
        axi4_transaction copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Actual AXI transaction clone failed")
        actual_axi_queue.push_back(copy_tr);
        compare_axi_queues();
    endfunction : write_actual_axi

    //-------------------------------------------------------------------------
    // AHB request comparison
    //-------------------------------------------------------------------------
    protected function void compare_ahb_queues();
        while (actual_ahb_queue.size() > 0) begin
            ahb_transfer expected_tr;
            ahb_transfer actual_tr;

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
    endfunction : reset_state

    //-------------------------------------------------------------------------
    // End-of-test checks
    //-------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        int unsigned unmatched_expected_ahb;

        super.check_phase(phase);

        unmatched_expected_ahb = 0;
        foreach (pending_ctx_queue[i])
            unmatched_expected_ahb += pending_ctx_queue[i].expected_beats.size();

        if ((unmatched_expected_ahb != 0) || (actual_ahb_queue.size() != 0))
            `uvm_error(get_type_name(),
                       $sformatf("Unmatched AHB transfers: expected=%0d actual=%0d",
                                 unmatched_expected_ahb,
                                 actual_ahb_queue.size()))

        if ((pending_ctx_queue.size() != 0) || (active_ctx != null) ||
            (completed_axi_queue.size() != 0) ||
            (actual_axi_queue.size() != 0))
            `uvm_error(get_type_name(),
                       $sformatf({"Unmatched AXI transactions: pending=%0d ",
                                  "expected=%0d actual=%0d"},
                                 pending_ctx_queue.size(),
                                 completed_axi_queue.size(),
                                 actual_axi_queue.size()))

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
    endfunction : report_phase

endclass : scoreboard