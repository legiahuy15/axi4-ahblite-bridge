//==============================================================================
// File        : axi4_exclusive_fail_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Exclusive-access reservation corner-case sequence.
//               Exercises how an exclusive reservation is invalidated by an
//               intervening store (AXI4 spec A7.2), which axi4_exclusive_seq
//               does not cover. All accesses here are LEGAL exclusive accesses,
//               so the slave raises no protocol error - the sequence simply
//               checks the response (EXOKAY vs OKAY) is what the spec requires.
//
//               Cases:
//                 A. Excl read -> normal write SAME id/addr -> excl write must FAIL (OKAY)
//                 B. Excl read -> normal write by OTHER id, same addr -> excl write FAILS
//                 C. Excl read -> excl write uninterrupted -> SUCCEEDS (EXOKAY)  [control]
//                 D. Excl read -> normal write to UNRELATED addr -> excl write SUCCEEDS
//                    (reservation is region-scoped, must survive an unrelated store)
//
//               `errors` counts unexpected responses (0 = all correct).
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_EXCLUSIVE_FAIL_SEQ_INCLUDED_
`define AXI4_EXCLUSIVE_FAIL_SEQ_INCLUDED_

class axi4_exclusive_fail_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_exclusive_fail_seq)

    // Number of responses that did NOT match the AXI4-required value.
    int unsigned errors = 0;

    function new(string name = "axi4_exclusive_fail_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // send_txn - issue one single-beat transaction and block until it completes.
    //   Uses SIZE_4B / LEN=0 / INCR so every exclusive access is legal.
    //   Returns the completed transaction (with resp/rresp populated).
    // =========================================================================
    task send_txn(input  axi4_dir_e                 a_dir,
                  input  bit [AXI4_ID_WIDTH-1:0]    a_id,
                  input  bit [AXI4_ADDR_WIDTH-1:0]  a_addr,
                  input  axi4_lock_e                a_lock,
                  output axi4_transaction           tr_out);
        axi4_transaction tr;
        tr = axi4_transaction::type_id::create("excl_fail_tr");
        start_item(tr);
        if (!tr.randomize() with {
            dir   == a_dir;
            id    == a_id;
            addr  == a_addr;
            lock  == a_lock;
            burst == AXI4_BURST_INCR;
            size  == AXI4_SIZE_4B;
            len   == 0;
            // Full byte-enables: an intervening store must actually WRITE the
            // monitored bytes so it deterministically clears the reservation.
            // (With random strobes, a masked write may leave it valid.)
            foreach (strb[i]) strb[i] == '1;
        }) `uvm_fatal(get_type_name(), "Randomization failed in exclusive-fail seq")
        finish_item(tr);
        wait(tr.done_event.ev.triggered);
        tr_out = tr;
    endtask : send_txn

    // =========================================================================
    // expect_resp - check an actual response against the AXI4-required value.
    // =========================================================================
    function void expect_resp(axi4_resp_e actual, axi4_resp_e exp, string tag);
        if (actual != exp) begin
            errors++;
            `uvm_error(get_type_name(),
                       $sformatf("%s: expected %s, got %s", tag, exp.name(), actual.name()))
        end else begin
            `uvm_info(get_type_name(),
                      $sformatf("%s: OK (%s)", tag, actual.name()), UVM_LOW)
        end
    endfunction : expect_resp

    // =========================================================================
    // body
    // =========================================================================
    virtual task body();
        axi4_transaction rd, wr;

        `uvm_info(get_type_name(),
                  "Starting exclusive reservation corner-case sequence", UVM_MEDIUM)

        // ---- Case A: intervening normal write (same ID) clears reservation ----
        send_txn(AXI4_READ,  4'h5, 32'h0000_A000, AXI4_LOCK_EXCLUSIVE, rd);
        expect_resp(rd.rresp[0], AXI4_RESP_EXOKAY, "A.excl_read");
        send_txn(AXI4_WRITE, 4'h5, 32'h0000_A000, AXI4_LOCK_NORMAL,    wr);
        expect_resp(wr.resp,     AXI4_RESP_OKAY,   "A.normal_write");
        send_txn(AXI4_WRITE, 4'h5, 32'h0000_A000, AXI4_LOCK_EXCLUSIVE, wr);
        expect_resp(wr.resp,     AXI4_RESP_OKAY,   "A.excl_write_must_fail");

        // ---- Case B: intervening write by a DIFFERENT ID clears reservation ----
        send_txn(AXI4_READ,  4'h6, 32'h0000_A100, AXI4_LOCK_EXCLUSIVE, rd);
        expect_resp(rd.rresp[0], AXI4_RESP_EXOKAY, "B.excl_read");
        send_txn(AXI4_WRITE, 4'h9, 32'h0000_A100, AXI4_LOCK_NORMAL,    wr);
        expect_resp(wr.resp,     AXI4_RESP_OKAY,   "B.other_id_write");
        send_txn(AXI4_WRITE, 4'h6, 32'h0000_A100, AXI4_LOCK_EXCLUSIVE, wr);
        expect_resp(wr.resp,     AXI4_RESP_OKAY,   "B.excl_write_must_fail");

        // ---- Case C (control): uninterrupted exclusive pair succeeds ----
        send_txn(AXI4_READ,  4'h7, 32'h0000_A200, AXI4_LOCK_EXCLUSIVE, rd);
        expect_resp(rd.rresp[0], AXI4_RESP_EXOKAY, "C.excl_read");
        send_txn(AXI4_WRITE, 4'h7, 32'h0000_A200, AXI4_LOCK_EXCLUSIVE, wr);
        expect_resp(wr.resp,     AXI4_RESP_EXOKAY, "C.excl_write_must_succeed");

        // ---- Case D: store to an UNRELATED address must NOT clear reservation ----
        send_txn(AXI4_READ,  4'h8, 32'h0000_A300, AXI4_LOCK_EXCLUSIVE, rd);
        expect_resp(rd.rresp[0], AXI4_RESP_EXOKAY, "D.excl_read");
        send_txn(AXI4_WRITE, 4'h8, 32'h0000_B000, AXI4_LOCK_NORMAL,    wr);
        expect_resp(wr.resp,     AXI4_RESP_OKAY,   "D.unrelated_write");
        send_txn(AXI4_WRITE, 4'h8, 32'h0000_A300, AXI4_LOCK_EXCLUSIVE, wr);
        expect_resp(wr.resp,     AXI4_RESP_EXOKAY, "D.excl_write_must_succeed");

        `uvm_info(get_type_name(),
                  $sformatf("Exclusive reservation corner-case sequence complete (%0d response errors)",
                            errors), UVM_MEDIUM)
    endtask : body

endclass : axi4_exclusive_fail_seq

`endif // AXI4_EXCLUSIVE_FAIL_SEQ_INCLUDED_