//==============================================================================
// File        : axi4_reset_traffic_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Background traffic sequence for the mid-burst reset test.
//               Continuously issues multi-beat reads/writes (fire-and-forget:
//               it does NOT wait on done_event) so that several bursts are
//               physically in flight on the bus at any instant. The reset test
//               forks this, lets a few bursts start, then asserts reset mid-
//               burst and kills this thread.
//
//               Traffic is confined to a dedicated address window (0x8000-
//               0x8FFF) and uses NORMAL locks so it never collides with the
//               recovery check that runs afterwards.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_RESET_TRAFFIC_SEQ_INCLUDED_
`define AXI4_RESET_TRAFFIC_SEQ_INCLUDED_

class axi4_reset_traffic_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_reset_traffic_seq)

    // Number of bursts to queue. Bounded on purpose: the master driver calls
    // item_done() as soon as it queues a request (no clock wait), so a `forever`
    // loop here would spin at zero simulation time. A few dozen multi-beat
    // bursts is more than enough to guarantee traffic is in flight when the
    // test asserts reset ~40 cycles later; the driver drives them over time.
    int unsigned num_txns = 30;

    function new(string name = "axi4_reset_traffic_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // body - queue multi-beat bursts (fire-and-forget: no done_event wait) so
    //   the bus stays busy and a reset lands mid-burst.
    // =========================================================================
    virtual task body();
        `uvm_info(get_type_name(),
                  $sformatf("Background reset-traffic sequence started (%0d bursts, fire-and-forget)",
                            num_txns), UVM_MEDIUM)
        repeat (num_txns) begin
            axi4_transaction tr;
            tr = axi4_transaction::type_id::create("reset_traffic_tr");
            start_item(tr);
            if (!tr.randomize() with {
                dir   inside {AXI4_READ, AXI4_WRITE};
                addr  inside {[32'h0000_8000 : 32'h0000_8FFF]};
                burst == AXI4_BURST_INCR;
                size  == AXI4_SIZE_4B;
                len   inside {3, 7};                 // multi-beat -> reset can hit mid-burst
                lock  == AXI4_LOCK_NORMAL;
            }) `uvm_fatal(get_type_name(), "Randomization failed in reset traffic seq")
            finish_item(tr);
        end
    endtask : body

endclass : axi4_reset_traffic_seq

`endif // AXI4_RESET_TRAFFIC_SEQ_INCLUDED_