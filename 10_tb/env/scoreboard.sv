//=============================================================================
// File        : scoreboard.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge request and response scoreboard.
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
    // Comparison queues
    //-------------------------------------------------------------------------
    protected ahb_transfer       expected_ahb_queue[$];
    protected ahb_transfer       actual_ahb_queue[$];
    protected scoreboard_axi_ctx axi_context_queue[$];
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
    function void write_expected_ahb(ahb_transfer tr);
        ahb_transfer copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Expected AHB transfer clone failed")
        expected_ahb_queue.push_back(copy_tr);
        compare_ahb_queues();
    endfunction : write_expected_ahb

    function void write_actual_ahb(ahb_transfer tr);
        ahb_transfer copy_tr;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Actual AHB transfer clone failed")
        actual_ahb_queue.push_back(copy_tr);
        compare_ahb_queues();
    endfunction : write_actual_ahb

    function void write_expected_axi(axi4_transaction tr);
        axi4_transaction          copy_tr;
        scoreboard_axi_ctx ctx;

        if (!$cast(copy_tr, tr.clone()))
            `uvm_fatal(get_type_name(), "Expected AXI template clone failed")
        ctx = new(copy_tr);
        axi_context_queue.push_back(ctx);
    endfunction : write_expected_axi

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
        while ((expected_ahb_queue.size() > 0) &&
               (actual_ahb_queue.size() > 0)) begin
            ahb_transfer expected_tr;
            ahb_transfer actual_tr;

            expected_tr = expected_ahb_queue.pop_front();
            actual_tr   = actual_ahb_queue.pop_front();

            if (ahb_request_matches(expected_tr, actual_tr)) begin
                matched_ahb++;
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
        scoreboard_axi_ctx ctx;
        int unsigned              beat_count;

        if (axi_context_queue.size() == 0) begin
            `uvm_error(get_type_name(),
                       "AHB transfer has no corresponding AXI request")
            return;
        end

        ctx        = axi_context_queue[0];
        beat_count = int'(ctx.tr.len) + 1;
        if (ctx.beat_index >= beat_count) begin
            `uvm_error(get_type_name(), "AXI completion beat index overflow")
            return;
        end

        if (ctx.tr.dir == AXI4_WRITE) begin
            if (ahb_tr.resp == AHB_RESP_ERROR)
                ctx.write_error = 1'b1;
        end else begin
            ctx.tr.data[ctx.beat_index] = ahb_tr.rdata;
            ctx.tr.rresp[ctx.beat_index] =
                (ahb_tr.resp == AHB_RESP_ERROR) ? AXI4_RESP_SLVERR
                                                : AXI4_RESP_OKAY;
        end

        ctx.beat_index++;
        if (ctx.beat_index == beat_count) begin
            void'(axi_context_queue.pop_front());
            if (ctx.tr.dir == AXI4_WRITE)
                ctx.tr.bresp = ctx.write_error ? AXI4_RESP_SLVERR
                                               : AXI4_RESP_OKAY;
            completed_axi_queue.push_back(ctx.tr);
            compare_axi_queues();
        end
    endfunction : update_axi_completion

    //-------------------------------------------------------------------------
    // AXI response comparison
    //-------------------------------------------------------------------------
    protected function void compare_axi_queues();
        while ((completed_axi_queue.size() > 0) &&
               (actual_axi_queue.size() > 0)) begin
            axi4_transaction expected_tr;
            axi4_transaction actual_tr;

            expected_tr = completed_axi_queue.pop_front();
            actual_tr   = actual_axi_queue.pop_front();

            if (axi_transaction_matches(expected_tr, actual_tr)) begin
                matched_axi++;
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
        expected_ahb_queue.delete();
        actual_ahb_queue.delete();
        axi_context_queue.delete();
        completed_axi_queue.delete();
        actual_axi_queue.delete();
    endfunction : reset_state

    //-------------------------------------------------------------------------
    // End-of-test checks
    //-------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        if ((expected_ahb_queue.size() != 0) ||
            (actual_ahb_queue.size() != 0))
            `uvm_error(get_type_name(),
                       $sformatf("Unmatched AHB transfers: expected=%0d actual=%0d",
                                 expected_ahb_queue.size(),
                                 actual_ahb_queue.size()))

        if ((axi_context_queue.size() != 0) ||
            (completed_axi_queue.size() != 0) ||
            (actual_axi_queue.size() != 0))
            `uvm_error(get_type_name(),
                       $sformatf({"Unmatched AXI transactions: pending=%0d ",
                                  "expected=%0d actual=%0d"},
                                 axi_context_queue.size(),
                                 completed_axi_queue.size(),
                                 actual_axi_queue.size()))
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