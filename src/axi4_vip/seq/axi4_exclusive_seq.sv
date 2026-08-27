//==============================================================================
// File        : axi4_exclusive_seq.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : AXI4 Exclusive Access Sequence.
//               Generates exclusive read followed by exclusive write to test
//               atomic read-modify-write transactions and cover AXI4 LOCK = EXEXCLUSIVE
//               and BRESP/RRESP = EXOKAY. Also tests failing exclusive write scenarios.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_EXCLUSIVE_SEQ_INCLUDED_
`define AXI4_EXCLUSIVE_SEQ_INCLUDED_

class axi4_exclusive_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_exclusive_seq)

    // Configurable knobs
    int unsigned num_iterations = 5;

    // Constructor
    function new(string name = "axi4_exclusive_seq");
        super.new(name);
    endfunction : new

    // body task
    virtual task body();
        `uvm_info(get_type_name(), $sformatf("Starting exclusive access sequence: %0d iterations", num_iterations), UVM_MEDIUM)

        for (int i = 0; i < num_iterations; i++) begin
            axi4_transaction rd_tr, wr_tr, fail_wr_tr;
            bit [AXI4_ADDR_WIDTH-1:0] target_addr;
            bit [AXI4_ID_WIDTH-1:0]   target_id;
            axi4_size_e               target_size = AXI4_SIZE_4B;
            bit [7:0]                 target_len  = 0; // single beat

            // Constrain address to be aligned for the given size
            target_addr = ($urandom_range(addr_hi, addr_lo) / 4) * 4;
            // Limit to non-error regions to make sure we get EXOKAY, not SLVERR/DECERR
            while (target_addr >= 32'hE000_0000) begin
                target_addr = ($urandom_range(addr_hi - 32'h2000_0000, addr_lo) / 4) * 4;
            end
            target_id = $urandom_range(id_hi, id_lo);

            `uvm_info(get_type_name(), $sformatf("[%0d/%0d] Running Exclusive Read-Write pair to ADDR=0x%08h ID=0x%0h", 
                                                 i + 1, num_iterations, target_addr, target_id), UVM_MEDIUM)

            // Phase 1: Exclusive Read
            rd_tr = axi4_transaction::type_id::create("excl_rd_tr");
            start_item(rd_tr);
            if (!rd_tr.randomize() with {
                dir   == AXI4_READ;
                addr  == target_addr;
                id    == target_id;
                len   == target_len;
                size  == target_size;
                burst == AXI4_BURST_INCR;
                lock  == AXI4_LOCK_EXCLUSIVE;
            }) `uvm_fatal(get_type_name(), "Randomization failed for exclusive read")
            finish_item(rd_tr);

            `uvm_info(get_type_name(), $sformatf("Exclusive Read complete: RESP=%s", rd_tr.rresp[0].name()), UVM_HIGH)

            // Phase 2: Exclusive Write (Successful)
            wr_tr = axi4_transaction::type_id::create("excl_wr_tr");
            start_item(wr_tr);
            if (!wr_tr.randomize() with {
                dir   == AXI4_WRITE;
                addr  == target_addr;
                id    == target_id;
                len   == target_len;
                size  == target_size;
                burst == AXI4_BURST_INCR;
                lock  == AXI4_LOCK_EXCLUSIVE;
            }) `uvm_fatal(get_type_name(), "Randomization failed for exclusive write")
            finish_item(wr_tr);

            `uvm_info(get_type_name(), $sformatf("Exclusive Write complete: RESP=%s", wr_tr.resp.name()), UVM_HIGH)

            // Phase 3: Exclusive Write without matching Read (Should Fail/Return OKAY)
            fail_wr_tr = axi4_transaction::type_id::create("fail_excl_wr_tr");
            start_item(fail_wr_tr);
            if (!fail_wr_tr.randomize() with {
                dir   == AXI4_WRITE;
                addr  == target_addr;
                id    == target_id;
                len   == target_len;
                size  == target_size;
                burst == AXI4_BURST_INCR;
                lock  == AXI4_LOCK_EXCLUSIVE;
            }) `uvm_fatal(get_type_name(), "Randomization failed for failing exclusive write")
            finish_item(fail_wr_tr);

            `uvm_info(get_type_name(), $sformatf("Failing Exclusive Write complete: RESP=%s (Expected OKAY, no EXOKAY)", 
                                                 fail_wr_tr.resp.name()), UVM_HIGH)
        end

        `uvm_info(get_type_name(), "Exclusive access sequence complete", UVM_MEDIUM)
    endtask : body

endclass : axi4_exclusive_seq

`endif // AXI4_EXCLUSIVE_SEQ_INCLUDED_