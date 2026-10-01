//=============================================================================
// File        : bridge_mutation_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge fault-injection test.
//               Every other test in this regression asks whether the bridge
//               is right. This one asks whether the answer would have been
//               different had it been wrong, which is the question the rest
//               of the regression rests on and the only one none of them
//               ask.
//               The target is the two hand-written comparisons at the heart
//               of the scoreboard, ahb_request_matches and
//               axi_transaction_matches. Both are lists of fields, and a
//               field left out of one of them would make the whole
//               regression blind to that field while still reporting a
//               pass. The suite corrupts one named field at a time in the
//               stream the scoreboard observes and requires a mismatch to
//               come back; a case where nothing is reported is the bug it
//               exists to find.
//               It runs inside the regression rather than beside it. While
//               the suite is active the scoreboard reports a failed
//               comparison as a caught fault instead of an error, so the
//               run stays green, and the verdict is in the counts: a fault
//               that went in without being caught fails the test, and so
//               does one that never reached a comparison at all.
//               Two gaps, each for a reason. A wrong ID cannot be injected
//               this way, because the scoreboard pairs a completion with its
//               request by ID, so a corrupted one produces an unmatched
//               completion rather than a mismatch; ID sensitivity rests on
//               the driver and monitor ID checks and on B_WITH_REQUEST and
//               R_WITH_REQUEST. The assertions are not covered either: they
//               report with $error, which does not pass through the UVM
//               report server and so cannot be demoted, and proving their
//               sensitivity needs a run whose pass criterion is inverted.
//               Covers BRG_ENV_006.
//               Included inside the bridge test package.
//=============================================================================

class bridge_mutation_test extends bridge_base_test;

    `uvm_component_utils(bridge_mutation_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'hC000;
    int unsigned              case_stride = 'h40;

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

        env_cfg.axi_cfg.return_responses = 1'b1;
        env_cfg.axi_cfg.max_outstanding  = 1;
        // Nothing about the traffic should vary: a case that behaves
        // differently has to differ because of its fault
        env_cfg.ahb_cfg.auto_gen_resp   = 1'b1;
        env_cfg.ahb_cfg.ready_delay_min = 0;
        env_cfg.ahb_cfg.ready_delay_max = 0;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_mutation_seq seq;

        phase.raise_objection(this, "Bridge mutation test started");

        seq = bridge_mutation_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge mutation test completed");
    endtask : run_phase

endclass : bridge_mutation_test
