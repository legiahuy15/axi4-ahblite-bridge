//=============================================================================
// File        : axi4_transaction.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 sequence item (transaction object).
//               Contains all fields for a single AXI4 read/write transaction,
//               constraints per AXI4 spec, and utility methods for debug.
//               This file is `included inside axi4_pkg.sv.
//=============================================================================

class axi4_transaction extends uvm_sequence_item;

    //-------------------------------------------------------------------------
    // Transaction fields
    //-------------------------------------------------------------------------

    // VIP-internal
    rand axi4_dir_e                         dir;        // Direction (0: read - 1: write)
    rand axi4_wr_order_e                    wr_order;   // Write channels (AW-W) ordering

    // Address channel (shared between AW and AR)
    rand bit [AXI4_ID_WIDTH-1:0]            id;
    rand bit [AXI4_ADDR_WIDTH-1:0]          addr;
    rand bit [AXI4_LEN_WIDTH-1:0]           len;        // Burst length = len + 1 (beats)
    rand axi4_size_e                        size;
    rand axi4_burst_type_e                  burst;
    rand axi4_lock_e                        lock;
    rand bit [3:0]                          cache;
    rand bit [2:0]                          prot;
    rand bit [3:0]                          qos;
    rand bit [3:0]                          region;

    // Write data channel
    rand bit [AXI4_DATA_WIDTH-1:0]          data[];     // 1 entry per beat
    rand bit [AXI4_STRB_WIDTH-1:0]          strb[];     // 1 entry per beat

    // Write response - B channel (1 per burst)
    rand axi4_resp_e                        resp;

    // Read response - R channel (1 per beat)
    rand axi4_resp_e                        rresp[];

    // Bus completion event - triggered by driver when B/R response is received.
    // Sequences can wait on this to implement true outstanding depth control.
    axi4_event_wrapper                      done_event;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(axi4_transaction)
        `uvm_field_enum(axi4_dir_e,        dir,      UVM_ALL_ON)
        `uvm_field_enum(axi4_wr_order_e,   wr_order, UVM_ALL_ON)
        `uvm_field_int(                    id,       UVM_ALL_ON)
        `uvm_field_int(                    addr,     UVM_ALL_ON)
        `uvm_field_int(                    len,      UVM_ALL_ON)
        `uvm_field_enum(axi4_size_e,       size,     UVM_ALL_ON)
        `uvm_field_enum(axi4_burst_type_e, burst,    UVM_ALL_ON)
        `uvm_field_enum(axi4_lock_e,       lock,     UVM_ALL_ON)
        `uvm_field_int(                    cache,    UVM_ALL_ON)
        `uvm_field_int(                    prot,     UVM_ALL_ON)
        `uvm_field_int(                    qos,      UVM_ALL_ON)
        `uvm_field_int(                    region,   UVM_ALL_ON)
        `uvm_field_array_int(              data,     UVM_ALL_ON)
        `uvm_field_array_int(              strb,     UVM_ALL_ON)
        `uvm_field_enum(axi4_resp_e,       resp,     UVM_ALL_ON)
        // Note: rresp[] uses enum array - no built-in macro for enum dynamic
        //       arrays, so do_copy/do_compare/do_print handle it manually.
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constraints
    //-------------------------------------------------------------------------

    // Data / strobe array size must match burst length
    constraint c_data_size {
        data.size() == len + 1;
    }

    constraint c_strb_size {
        strb.size() == len + 1;
    }

    // Read response array size must match burst length
    constraint c_rresp_size {
        rresp.size() == len + 1;
    }

    // Burst size must not exceed data bus width
    // 2^size <= DATA_WIDTH / 8  ->  size <= log2(DATA_WIDTH / 8)
    constraint c_size_max {
        (1 << size) <= (AXI4_DATA_WIDTH / 8);
    }

    // WRAP burst: len must be 2, 4, 8, or 16 beats (len = 1, 3, 7, 15)
    constraint c_wrap_len {
        (burst == AXI4_BURST_WRAP) -> len inside {1, 3, 7, 15};
    }

    // WRAP burst: start address must be aligned to transfer size
    constraint c_wrap_align {
        (burst == AXI4_BURST_WRAP) -> (addr % (1 << size)) == 0;
    }

    // FIXED burst: length must not exceed 16 beats (AXI4 spec)
    constraint c_fixed_len {
        (burst == AXI4_BURST_FIXED) -> len <= 15;
    }

    // INCR burst: AXI4 allows up to 256 beats (len 0-255), no extra constraint needed.
    // But we keep an explicit one for clarity and future configurability.
    constraint c_incr_len {
        (burst == AXI4_BURST_INCR) -> len <= 255;
    }

    // Exclusive access rules: a legal exclusive transaction must
    //   - span a power-of-two number of bytes (2^size is pow2, so len+1 must be pow2)
    //   - not exceed 128 bytes in total
    //   - use at most 16 beats
    //   - start at an address aligned to the total byte count
    // Constraining the master guarantees it never issues an illegal exclusive access.
    constraint c_exclusive_legal {
        (lock == AXI4_LOCK_EXCLUSIVE) -> {
            (len + 1) inside {1, 2, 4, 8, 16};          // pow2 beats, <= 16 beats
            ((1 << size) * (len + 1)) <= 128;           // total bytes <= 128
            (addr % ((1 << size) * (len + 1))) == 0;    // aligned to total bytes
        }
    }

    // Default response: OKAY for write resp (slave will override as needed)
    constraint c_resp_default {
        soft resp == AXI4_RESP_OKAY;
    }

    // Default rresp: OKAY for all read beats (slave will override as needed)
    constraint c_rresp_default {
        foreach (rresp[i]) soft rresp[i] == AXI4_RESP_OKAY;
    }

    // Read transactions: strobe is not used, set to all-1s
    constraint c_read_strb {
        if (dir == AXI4_READ) {
            foreach (strb[i]) strb[i] == {AXI4_STRB_WIDTH{1'b1}};
        }
    }

    // Default distribution: favour common burst types
    constraint c_burst_dist {
        burst dist {
            AXI4_BURST_INCR  := 60,
            AXI4_BURST_FIXED := 20,
            AXI4_BURST_WRAP  := 20
        };
    }

    // Default distribution: favour shorter bursts for faster sim
    constraint c_len_dist {
        len dist {
            0       := 30,      // single beat
            [1:3]   := 30,      // 2-4 beats
            [4:15]  := 25,      // 5-16 beats
            [16:255]:= 15       // 17-256 beats
        };
    }

    // Default write channel ordering distribution
    constraint c_wr_order_dist {
        (dir == AXI4_WRITE) -> wr_order dist {
            AXI4_WR_PARALLEL    := 50,
            AXI4_WR_AW_BEFORE_W := 25,
            AXI4_WR_W_BEFORE_AW := 25
        };
        (dir == AXI4_READ) -> wr_order == AXI4_WR_PARALLEL;
    }

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_transaction");
        super.new(name);
        done_event = new;
    endfunction : new

    //-------------------------------------------------------------------------
    // do_copy - deep copy including rresp[] enum array
    //-------------------------------------------------------------------------
    function void do_copy(uvm_object rhs);
        axi4_transaction rhs_t;
        super.do_copy(rhs);     // copies all registered fields
        if (!$cast(rhs_t, rhs))
            `uvm_fatal(get_type_name(), "do_copy: cast failed")
        // Manual copy of rresp[] (enum array, no built-in macro)
        this.rresp = new[rhs_t.rresp.size()];
        foreach (rhs_t.rresp[i])
            this.rresp[i] = rhs_t.rresp[i];
        // done_event is per-instance, don't copy - each transaction
        // gets its own fresh event from the constructor.
    endfunction : do_copy

    //-------------------------------------------------------------------------
    // do_compare - compare including rresp[] enum array
    //-------------------------------------------------------------------------
    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi4_transaction rhs_t;
        bit result;
        result = super.do_compare(rhs, comparer);   // compare all registered fields
        if (!$cast(rhs_t, rhs))
            `uvm_fatal(get_type_name(), "do_compare: cast failed")
        // Compare rresp[] sizes
        if (this.rresp.size() != rhs_t.rresp.size()) begin
            `uvm_info(get_type_name(),
                      $sformatf("rresp size mismatch: %0d vs %0d",
                                this.rresp.size(), rhs_t.rresp.size()), UVM_LOW)
            return 0;
        end
        // Compare rresp[] elements
        foreach (this.rresp[i]) begin
            if (this.rresp[i] != rhs_t.rresp[i]) begin
                `uvm_info(get_type_name(),
                          $sformatf("rresp[%0d] mismatch: %s vs %s",
                                    i, this.rresp[i].name(), rhs_t.rresp[i].name()), UVM_LOW)
                result = 0;
            end
        end
        return result;
    endfunction : do_compare

    //-------------------------------------------------------------------------
    // do_print - include rresp[] in UVM print output
    //-------------------------------------------------------------------------
    function void do_print(uvm_printer printer);
        super.do_print(printer);   // prints all registered fields
        // Manually print rresp[] enum array
        printer.print_generic("rresp.size()", "int", $bits(rresp.size()),
                              $sformatf("%0d", rresp.size()));
        foreach (rresp[i])
            printer.print_generic($sformatf("rresp[%0d]", i), "axi4_resp_e", 2,
                                  rresp[i].name());
    endfunction : do_print

    //-------------------------------------------------------------------------
    // convert2string - human-readable transaction summary for debug
    //-------------------------------------------------------------------------
    function string convert2string();
        string s;
        s = $sformatf("\n---------- AXI4 Transaction ----------");
        s = {s, $sformatf("\n DIR    = %s",     dir.name())};
        s = {s, $sformatf("\n ID     = 0x%0h",  id)};
        s = {s, $sformatf("\n ADDR   = 0x%08h", addr)};
        s = {s, $sformatf("\n LEN    = %0d (beats = %0d)", len, len + 1)};
        s = {s, $sformatf("\n SIZE   = %s (%0d bytes/beat)", size.name(), 1 << size)};
        s = {s, $sformatf("\n BURST  = %s",     burst.name())};
        if (dir == AXI4_WRITE)
            s = {s, $sformatf("\n WR_ORD = %s",     wr_order.name())};
        s = {s, $sformatf("\n LOCK   = %s",     lock.name())};
        s = {s, $sformatf("\n CACHE  = 0b%04b", cache)};
        s = {s, $sformatf("\n PROT   = 0b%03b", prot)};
        s = {s, $sformatf("\n QOS    = 0x%0h",  qos)};
        s = {s, $sformatf("\n REGION = 0x%0h",  region)};
        if (dir == AXI4_WRITE) begin
            s = {s, $sformatf("\n RESP   = %s (B channel)", resp.name())};
        end
        s = {s, $sformatf("\n DATA[%0d] = {",   data.size())};
        foreach (data[i]) begin
            if (dir == AXI4_WRITE)
                s = {s, $sformatf("\n   [%0d] 0x%08h  STRB=0b%0b", i, data[i], strb[i])};
            else
                s = {s, $sformatf("\n   [%0d] 0x%08h  RRESP=%s", i, data[i],
                                  (i < rresp.size()) ? rresp[i].name() : "N/A")};
        end
        s = {s, "\n }"};
        s = {s, "\n---------------------------------------\n"};
        return s;
    endfunction : convert2string

endclass : axi4_transaction