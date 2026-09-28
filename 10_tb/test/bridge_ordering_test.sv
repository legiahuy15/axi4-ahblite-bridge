//=============================================================================
// File        : bridge_ordering_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge completion ordering test.
//               Every other test sends one request and waits for it. This
//               one hands the driver a whole list at once and lets the queue
//               back up behind the bridge, which is the only way the bridge
//               gets the chance to reorder anything: eight reads on one ID,
//               eight reads on rotating IDs with falling burst lengths, a
//               write and read stream over the same addresses, four phases
//               that put every access of the phase on a single address, and
//               a randomized mixed phase with AHB wait states and AXI
//               response backpressure.
//               The reference order is the order the bridge accepted the
//               requests on AW and AR, not the order they were issued in,
//               because a read arriving with a write wins arbitration and
//               the write then takes the next turn. That acceptance order is
//               replayed through a reference copy of the slave memory, so
//               every read is compared against what an in-order bridge would
//               owe it at that point.
//               max_outstanding is 0 so the driver never throttles the
//               queue, and the AHB slave answers from its memory model so a
//               read that overtook a write returns the wrong word. The
//               scoreboard matches AHB beats to requests by first-beat
//               direction and address and AXI completions by direction and
//               ID, both of which stay usable here because the requests that
//               share an address carry different data.
//               Covers BRG_UNS_002.
//               Included inside the bridge test package.
//=============================================================================

class bridge_ordering_test extends bridge_base_test;

    `uvm_component_utils(bridge_ordering_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr       = 'h2000;
    int unsigned              slot_bytes      = 'h100;
    int unsigned              stress_requests = 24;
    int unsigned              stress_slots    = 8;

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
        // The point of the test: the driver must not throttle the queue, so
        // the bridge is the only thing deciding what is served next
        env_cfg.axi_cfg.max_outstanding  = 0;
        // A read returns what an earlier write put there, which is what makes
        // the order of the two visible in the data
        env_cfg.ahb_cfg.auto_gen_resp     = 1'b1;
        env_cfg.ahb_cfg.addr_pattern_read = 1'b1;
        // Moved per phase by the sequence
        env_cfg.ahb_cfg.ready_delay_min   = 0;
        env_cfg.ahb_cfg.ready_delay_max   = 0;

        void'($value$plusargs("BASE_ADDR=%h",       base_addr));
        void'($value$plusargs("SLOT_BYTES=%d",      slot_bytes));
        void'($value$plusargs("STRESS_REQUESTS=%d", stress_requests));
        void'($value$plusargs("STRESS_SLOTS=%d",    stress_slots));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_ordering_seq seq;

        phase.raise_objection(this, "Bridge ordering test started");

        seq = bridge_ordering_seq::type_id::create("seq");
        seq.base_addr       = base_addr;
        seq.slot_bytes      = slot_bytes;
        seq.stress_requests = stress_requests;
        seq.stress_slots    = stress_slots;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge ordering test completed");
    endtask : run_phase

endclass : bridge_ordering_test
