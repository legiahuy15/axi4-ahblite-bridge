//==============================================================================
// File        : axi4_scoreboard.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 scoreboard.
//               Receives completed transactions from both master and slave
//               monitors, matches them by (dir, id, addr), and compares all
//               fields using axi4_transaction::compare() (which includes
//               the manual rresp[] comparison via do_compare).
//
//               Matching strategy:
//                 When a transaction arrives from one side, search the other
//                 side's queue for a match by (id, addr). If found, compare
//                 immediately. If not, queue for later matching.
//                 This handles out-of-order and timing-skewed arrivals.
//
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

// Analysis port suffix declarations (must be outside class)
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class axi4_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(axi4_scoreboard)

    // =========================================================================
    // Analysis imports - one per monitor side
    // =========================================================================
    uvm_analysis_imp_master #(axi4_transaction, axi4_scoreboard) master_export;
    uvm_analysis_imp_slave  #(axi4_transaction, axi4_scoreboard) slave_export;

    // =========================================================================
    // Unmatched transaction queues
    //   Separated by direction for efficient matching.
    //   When a transaction arrives from one side and no match exists on the
    //   other side, it is queued here until the counterpart arrives.
    // =========================================================================
    axi4_transaction master_wr_q[$];
    axi4_transaction master_rd_q[$];
    axi4_transaction slave_wr_q[$];
    axi4_transaction slave_rd_q[$];

    // =========================================================================
    // Reference Memory Model for checking read-after-write data integrity
    // =========================================================================
    bit [7:0] ref_mem [bit [AXI4_ADDR_WIDTH-1:0]];

    // =========================================================================
    // Statistics
    // =========================================================================
    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;
    int unsigned total_master   = 0;
    int unsigned total_slave    = 0;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase - create analysis imports
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        master_export = new("master_export", this);
        slave_export  = new("slave_export",  this);
    endfunction : build_phase

    // =========================================================================
    // write_master - called when master monitor broadcasts a completed txn
    // =========================================================================
    function void write_master(axi4_transaction t);
        axi4_transaction tr;
        total_master++;

        // Deep copy - the monitor may reuse the object
        tr = axi4_transaction::type_id::create("master_tr");
        tr.copy(t);

        `uvm_info(get_type_name(),
                  $sformatf("Master %s received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_HIGH)

        if (tr.dir == AXI4_WRITE)
            try_match(tr, master_wr_q, slave_wr_q, "WRITE");
        else
            try_match(tr, master_rd_q, slave_rd_q, "READ");
    endfunction : write_master

    // =========================================================================
    // write_slave - called when slave monitor broadcasts a completed txn
    // =========================================================================
    function void write_slave(axi4_transaction t);
        axi4_transaction tr;
        total_slave++;

        // Deep copy
        tr = axi4_transaction::type_id::create("slave_tr");
        tr.copy(t);

        `uvm_info(get_type_name(),
                  $sformatf("Slave %s received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_HIGH)

        if (tr.dir == AXI4_WRITE)
            try_match(tr, slave_wr_q, master_wr_q, "WRITE");
        else
            try_match(tr, slave_rd_q, master_rd_q, "READ");
    endfunction : write_slave

    // =========================================================================
    // try_match - search for matching transaction on the other side
    //   Match key: (id, addr)
    //   If found:  compare and consume both.
    //   If not:    push to own queue for future matching.
    //   FIFO ordering within same (id, addr) pairs is preserved.
    // =========================================================================
    function void try_match(
        axi4_transaction     new_tr,
        ref axi4_transaction own_q[$],
        ref axi4_transaction other_q[$],
        input string         dir_str
    );
        // Search other side's queue for a matching transaction
        for (int i = 0; i < other_q.size(); i++) begin
            if (other_q[i].id == new_tr.id && other_q[i].addr == new_tr.addr) begin
                // Match found - compare and consume
                axi4_transaction ref_tr = other_q[i];
                other_q.delete(i);
                compare_transactions(ref_tr, new_tr, dir_str);
                return;
            end
        end

        // No match on other side - queue for later
        own_q.push_back(new_tr);
    endfunction : try_match

    // =========================================================================
    // calc_beat_addr - Calculate address for each beat in a burst
    // =========================================================================
    function bit [AXI4_ADDR_WIDTH-1:0] calc_beat_addr(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_idx,
        bit [2:0]                 size,
        bit [1:0]                 burst_type,
        bit [7:0]                 len
    );
        int unsigned num_bytes  = 1 << size;
        int unsigned burst_len  = len + 1;
        bit [AXI4_ADDR_WIDTH-1:0] aligned_addr;
        bit [AXI4_ADDR_WIDTH-1:0] addr;

        aligned_addr = (start_addr / num_bytes) * num_bytes;

        case (burst_type)
            2'b00: begin // FIXED
                addr = start_addr;
            end
            2'b01: begin // INCR
                if (beat_idx == 0)
                    addr = start_addr;
                else
                    addr = aligned_addr + beat_idx * num_bytes;
            end
            2'b10: begin // WRAP
                int unsigned total_size   = num_bytes * burst_len;
                bit [AXI4_ADDR_WIDTH-1:0] wrap_boundary;
                wrap_boundary = (start_addr / total_size) * total_size;

                if (beat_idx == 0)
                    addr = start_addr;
                else begin
                    addr = aligned_addr + beat_idx * num_bytes;
                    if (addr >= wrap_boundary + total_size)
                        addr = addr - total_size;
                end
            end
            default: addr = start_addr;
        endcase

        return addr;
    endfunction : calc_beat_addr

    // =========================================================================
    // update_ref_mem - update scoreboard's reference memory on WRITES
    // =========================================================================
    function void update_ref_mem(axi4_transaction tr);
        bit do_write = 1;

        // Check if write should be ignored (matches slave driver's logic)
        if (tr.addr >= 32'hF000_0000) begin
            do_write = 0; // DECERR region
        end else if (tr.addr >= 32'hE000_0000) begin
            do_write = 0; // SLVERR region
        end else if (tr.lock == AXI4_LOCK_EXCLUSIVE) begin
            // Exclusive Write: succeeds only if it received EXOKAY
            if (tr.resp != AXI4_RESP_EXOKAY) begin
                do_write = 0;
            end
        end

        if (do_write) begin
            for (int beat = 0; beat <= tr.len; beat++) begin
                bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
                bit [AXI4_ADDR_WIDTH-1:0] aligned_beat_addr;
                beat_addr = calc_beat_addr(tr.addr, beat, tr.size, tr.burst, tr.len);
                aligned_beat_addr = (beat_addr / AXI4_STRB_WIDTH) * AXI4_STRB_WIDTH;
                for (int b = 0; b < AXI4_STRB_WIDTH; b++) begin
                    if (tr.strb[beat][b]) begin
                        ref_mem[aligned_beat_addr + b] = tr.data[beat][b*8 +: 8];
                        `uvm_info(get_type_name(),
                                  $sformatf("[REF_MEM_WRITE] Addr=0x%08h Data=0x%02h",
                                            aligned_beat_addr + b, tr.data[beat][b*8 +: 8]), UVM_HIGH)
                    end
                end
            end
        end else begin
            `uvm_info(get_type_name(),
                      $sformatf("[REF_MEM_WRITE_IGNORED] Write ignored for ADDR=0x%08h LOCK=%s RESP=%s",
                                tr.addr, tr.lock.name(), tr.resp.name()), UVM_MEDIUM)
        end
    endfunction : update_ref_mem

    // =========================================================================
    // check_ref_mem - verify READ transaction against reference memory
    // =========================================================================
    function void check_ref_mem(axi4_transaction tr);
        for (int beat = 0; beat <= tr.len; beat++) begin
            bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
            bit [AXI4_DATA_WIDTH-1:0] expected_data;
            bit [AXI4_DATA_WIDTH-1:0] actual_data;
            int unsigned num_bytes = 1 << tr.size;
            
            beat_addr = calc_beat_addr(tr.addr, beat, tr.size, tr.burst, tr.len);
            expected_data = '0;
            actual_data   = tr.data[beat];

            for (int offset = 0; offset < num_bytes; offset++) begin
                bit [AXI4_ADDR_WIDTH-1:0] byte_addr;
                int unsigned lane;
                byte_addr = beat_addr + offset;
                lane = byte_addr % AXI4_STRB_WIDTH;
                if (ref_mem.exists(byte_addr)) begin
                    expected_data[lane*8 +: 8] = ref_mem[byte_addr];
                end
            end

            for (int offset = 0; offset < num_bytes; offset++) begin
                bit [AXI4_ADDR_WIDTH-1:0] byte_addr;
                int unsigned lane;
                bit [7:0] exp_byte;
                bit [7:0] act_byte;

                byte_addr = beat_addr + offset;
                lane = byte_addr % AXI4_STRB_WIDTH;
                
                exp_byte = expected_data[lane*8 +: 8];
                act_byte = actual_data[lane*8 +: 8];

                if (exp_byte != act_byte) begin
                    mismatch_count++;
                    `uvm_error(get_type_name(),
                               $sformatf("[DATA_INTEGRITY_FAIL] Read mismatch at Beat %0d, Byte Lane %0d! Addr=0x%08h | Expected=0x%02h, Actual=0x%02h",
                                         beat, lane, byte_addr, exp_byte, act_byte))
                end
            end
        end
    endfunction : check_ref_mem

    // =========================================================================
    // compare_transactions - detailed comparison using do_compare
    //   Uses axi4_transaction::compare() which internally calls do_compare
    //   for all fields including the manually-handled rresp[] array.
    // =========================================================================
    function void compare_transactions(
        axi4_transaction expected,
        axi4_transaction actual,
        string           dir_str
    );
        if (expected.compare(actual)) begin
            match_count++;
            `uvm_info(get_type_name(),
                      $sformatf("[%s] MATCH #%0d: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                dir_str, match_count,
                                actual.id, actual.addr, actual.len), UVM_MEDIUM)
            if (actual.dir == AXI4_WRITE) begin
                update_ref_mem(actual);
            end else begin
                check_ref_mem(actual);
            end
        end else begin
            mismatch_count++;
            `uvm_error(get_type_name(),
                       $sformatf("[%s] MISMATCH #%0d: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                 dir_str, mismatch_count,
                                 actual.id, actual.addr, actual.len))
            `uvm_info(get_type_name(),
                      {"Expected:\n", expected.sprint()}, UVM_LOW)
            `uvm_info(get_type_name(),
                      {"Actual:\n", actual.sprint()}, UVM_LOW)
        end
    endfunction : compare_transactions

    // =========================================================================
    // check_phase - flag errors for unmatched/mismatched transactions
    // =========================================================================
    function void check_phase(uvm_phase phase);
        int unsigned unmatched;
        unmatched = master_wr_q.size() + master_rd_q.size()
                  + slave_wr_q.size()  + slave_rd_q.size();

        if (mismatch_count > 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d transaction MISMATCHES detected", mismatch_count))

        if (unmatched > 0)
            `uvm_warning(get_type_name(),
                         $sformatf("%0d unmatched transactions at end of simulation",
                                   unmatched))
    endfunction : check_phase

    // =========================================================================
    // report_phase - print summary statistics
    // =========================================================================
    function void report_phase(uvm_phase phase);
        int unsigned unmatched;
        string result_str;

        unmatched = master_wr_q.size() + master_rd_q.size()
                  + slave_wr_q.size()  + slave_rd_q.size();

        result_str = (mismatch_count == 0 && unmatched == 0) ? "PASS" : "FAIL";

        `uvm_info(get_type_name(), $sformatf({
            "\n",
            "========================================\n",
            "         SCOREBOARD SUMMARY\n",
            "========================================\n",
            "  Master transactions : %0d\n",
            "  Slave transactions  : %0d\n",
            "  Matches             : %0d\n",
            "  Mismatches          : %0d\n",
            "  Unmatched master WR : %0d\n",
            "  Unmatched master RD : %0d\n",
            "  Unmatched slave  WR : %0d\n",
            "  Unmatched slave  RD : %0d\n",
            "========================================\n",
            "  RESULT : %s\n",
            "========================================"},
            total_master, total_slave,
            match_count, mismatch_count,
            master_wr_q.size(), master_rd_q.size(),
            slave_wr_q.size(), slave_rd_q.size(),
            result_str), UVM_NONE)
    endfunction : report_phase

endclass : axi4_scoreboard