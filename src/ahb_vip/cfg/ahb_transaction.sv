//==============================================================================
// File        : ahb_transaction.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite sequence item. Holds all fields for one read/write
//               transaction, protocol constraints (IHI0033A), and debug helpers.
//==============================================================================

class ahb_transaction extends uvm_sequence_item;

    //-------------------------------------------------------------------------
    // Transaction fields
    //-------------------------------------------------------------------------

    // Master channel
    rand bit [AHB_ADDR_WIDTH-1:0] addr;
    rand ahb_burst_e              burst;
    rand bit                      lock;
    rand ahb_prot_e               prot;
    rand ahb_size_e               size;
    rand ahb_trans_e              trans[];
    rand ahb_dir_e                write;     // 0: Read, 1: Write
    rand bit [AHB_DATA_WIDTH-1:0] wdata[];

    // Slave channel (beat-level signals)
    rand bit [AHB_DATA_WIDTH-1:0] rdata[];
    rand bit                      ready[];
    rand ahb_resp_e               resp[];

    // Canonical burst length (number of beats), derived from burst type
    rand int unsigned             num_beats;

    // BUSY cycles driven before beat i. busy_cycles[0] == 0, so BUSY only
    // appears between beats
    rand int unsigned             busy_cycles[];

    // INCR only: BUSY cycles after the last beat, then IDLE/NONSEQ
    rand int unsigned             trailing_busy_cycles;

    // ERROR policy: 1 = cancel remaining beats, 0 = continue (both spec-legal)
    rand bit                      abort_on_error;

    // Withdraw a presented BUSY during a wait state, replacing it with the
    // transfer that ends the BUSY run (IHI0033A 3.6.1)
    rand bit                      busy_retract_in_wait;

    // Move the address while cancelling a burst on ERROR - address/control may
    // change with HREADY low (IHI0033A 3.6.2)
    rand bit                      addr_change_on_error;

    // Set by the driver at end of transfer; rdata[]/resp[] valid only then.
    // Level flag, not an event, so an early completion cannot be missed
    bit                           done;

    // Set with done when a reset flushed the txn; rdata[]/resp[] are invalid
    bit                           aborted;

    // Beats actually completed on the bus. Below num_beats when an ERROR
    // cancelled the rest of the burst
    int unsigned                  beats_done;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(ahb_transaction)
        `uvm_field_int(                    addr,   UVM_ALL_ON)
        `uvm_field_enum(ahb_burst_e,       burst,  UVM_ALL_ON)
        `uvm_field_int(                    lock,   UVM_ALL_ON)
        `uvm_field_enum(ahb_prot_e,        prot,   UVM_ALL_ON)
        `uvm_field_enum(ahb_size_e,        size,   UVM_ALL_ON)
        `uvm_field_enum(ahb_dir_e,         write,  UVM_ALL_ON)
        `uvm_field_array_int(              wdata,  UVM_ALL_ON)
        `uvm_field_array_int(              rdata,  UVM_ALL_ON)
        `uvm_field_array_int(              ready,  UVM_ALL_ON)
        `uvm_field_int(                    num_beats, UVM_ALL_ON)
        `uvm_field_array_int(              busy_cycles, UVM_ALL_ON)
        `uvm_field_int(                    trailing_busy_cycles, UVM_ALL_ON)
        `uvm_field_int(                    abort_on_error, UVM_ALL_ON)
        `uvm_field_int(                    busy_retract_in_wait, UVM_ALL_ON)
        `uvm_field_int(                    addr_change_on_error, UVM_ALL_ON)
        // trans[]/resp[]: no macro for enum dynamic arrays - handled by
        // do_copy/do_compare/do_print
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constraints
    //-------------------------------------------------------------------------

    // Canonical beat count, derived from burst type
    constraint c_num_beats {
        if (burst == AHB_BURST_SINGLE)                              num_beats == 1;
        else if (burst inside {AHB_BURST_WRAP4,  AHB_BURST_INCR4})  num_beats == 4;
        else if (burst inside {AHB_BURST_WRAP8,  AHB_BURST_INCR8})  num_beats == 8;
        else if (burst inside {AHB_BURST_WRAP16, AHB_BURST_INCR16}) num_beats == 16;
        else                                                        num_beats inside {[1:256]}; // INCR
    }

    // Every beat-level array is sized to the canonical beat count
    constraint c_array_sizes {
        wdata.size() == num_beats;
        rdata.size() == num_beats;
        trans.size() == num_beats;
        ready.size() == num_beats;
        resp.size()  == num_beats;
        busy_cycles.size() == num_beats;
    }

    // Burst size must not exceed data bus width
    // 2^size <= DATA_WIDTH / 8
    constraint c_size_max {
        (1 << size) <= (AHB_DATA_WIDTH / 8);
    }

    // HADDR aligned to 2^HSIZE bytes
    constraint c_addr_align {
        (addr % (1 << size)) == 0;
    }

    // INCR burst must not cross a 1KB boundary
    constraint c_1kb_boundary {
        (burst inside {AHB_BURST_INCR,  AHB_BURST_INCR4,
                       AHB_BURST_INCR8, AHB_BURST_INCR16}) ->
            ((addr >> 10) == ((addr + (num_beats - 1) * (1 << size)) >> 10));
    }

    // Single master - HMASTLOCK not needed (no arbitration)
    constraint c_lock_fixed {
        lock == 1'b0;
    }

    // HPROT not supported - fixed to default
    constraint c_prot_fixed {
        prot == AHB_PROT_DEFAULT;
    }

    // Default slave responses
    constraint c_resp_default {
        foreach (resp[i]) soft resp[i] == AHB_RESP_OKAY;
    }

    // Default ready: no wait states
    constraint c_ready_default {
        foreach (ready[i]) soft ready[i] == 1'b1;
    }

    // Default: first beat NONSEQ, subsequent beats SEQ
    constraint c_trans_default {
        foreach (trans[i]) {
            if (i == 0) {
                soft trans[i] == AHB_TRANS_NONSEQ;
            } else {
                soft trans[i] == AHB_TRANS_SEQ;
            }
        }
    }

    // Beats are active transfers only (BUSY modeled via busy_cycles[]);
    // beat 0 is NONSEQ
    constraint c_trans_active {
        foreach (trans[i])
            trans[i] inside {AHB_TRANS_NONSEQ, AHB_TRANS_SEQ};
        if (num_beats > 0)
            trans[0] == AHB_TRANS_NONSEQ;
    }

    // No BUSY before beat 0; BUSY runs capped at 3 cycles, default none
    constraint c_busy_cycles {
        if (num_beats > 0) busy_cycles[0] == 0;
        foreach (busy_cycles[i]) {
            busy_cycles[i] <= 3;
            soft busy_cycles[i] == 0;
        }
    }

    // Only INCR may end the burst out of BUSY; default none
    constraint c_trailing_busy {
        trailing_busy_cycles <= 3;
        soft trailing_busy_cycles == 0;
        (burst != AHB_BURST_INCR) -> (trailing_busy_cycles == 0);
    }

    // Cancel-on-ERROR optional per spec; default cancel
    constraint c_abort_on_error {
        soft abort_on_error == 1'b1;
    }

    // BUSY retraction optional; default off
    constraint c_busy_retract {
        soft busy_retract_in_wait == 1'b0;
    }

    // Address move on ERROR cancel optional; default off
    constraint c_addr_change_on_error {
        soft addr_change_on_error == 1'b0;
    }

    // Default distribution: favour common burst types
    constraint c_burst_dist {
        burst dist {
            AHB_BURST_SINGLE := 40,
            AHB_BURST_INCR   := 15,
            AHB_BURST_INCR4  := 15,
            AHB_BURST_INCR8  := 10,
            AHB_BURST_INCR16 := 5,
            AHB_BURST_WRAP4  := 5,
            AHB_BURST_WRAP8  := 5,
            AHB_BURST_WRAP16 := 5
        };
    }

    // Default direction distribution
    constraint c_dir_dist {
        write dist {0 := 50, 1 := 50};
    }

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_transaction");
        super.new(name);
        // Defaults for non-randomized transactions
        abort_on_error       = 1'b1;
        busy_retract_in_wait = 1'b0;
        addr_change_on_error = 1'b0;
        aborted              = 1'b0;
        done                 = 1'b0;
        beats_done           = 0;
    endfunction : new

    //-------------------------------------------------------------------------
    // Helper: get number of beats for the current burst type
    //-------------------------------------------------------------------------
    function int get_num_beats();
        case (burst)
            AHB_BURST_SINGLE:                   return 1;
            AHB_BURST_WRAP4,  AHB_BURST_INCR4:  return 4;
            AHB_BURST_WRAP8,  AHB_BURST_INCR8:  return 8;
            AHB_BURST_WRAP16, AHB_BURST_INCR16: return 16;
            // INCR: canonical num_beats, else beat-array size for directed
            // items that skip it
            AHB_BURST_INCR:                     return (num_beats != 0) ? num_beats : wdata.size();
            default:                            return 1;
        endcase
    endfunction : get_num_beats

    //-------------------------------------------------------------------------
    // do_copy - deep copy including enum arrays
    //-------------------------------------------------------------------------
    function void do_copy(uvm_object rhs);
        ahb_transaction rhs_t;
        super.do_copy(rhs);     // copies all `uvm_field_*` registered fields
        if (!$cast(rhs_t, rhs))
            `uvm_fatal(get_type_name(), "do_copy: cast failed")
        // Manual copy of trans[] & resp[]
        this.trans = new[rhs_t.trans.size()];
        this.resp  = new[rhs_t.resp.size()];
        foreach (rhs_t.trans[i])
            this.trans[i] = rhs_t.trans[i];
        foreach (rhs_t.resp[i])
            this.resp[i] = rhs_t.resp[i];
    endfunction : do_copy

    //-------------------------------------------------------------------------
    // do_compare - compare including enum arrays
    //-------------------------------------------------------------------------
    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        ahb_transaction rhs_t;
        bit result;
        result = super.do_compare(rhs, comparer);   // compare all registered fields
        if (!$cast(rhs_t, rhs))
            `uvm_fatal(get_type_name(), "do_compare: cast failed")
        // Compare trans[] sizes & elements
        if (this.trans.size() != rhs_t.trans.size()) begin
            `uvm_info(get_type_name(),
                      $sformatf("trans size mismatch: %0d vs %0d",
                                this.trans.size(), rhs_t.trans.size()), UVM_LOW)
            return 0;
        end
        foreach (this.trans[i]) begin
            if (this.trans[i] != rhs_t.trans[i]) begin
                `uvm_info(get_type_name(),
                          $sformatf("trans[%0d] mismatch: %s vs %s",
                                    i, this.trans[i].name(), rhs_t.trans[i].name()), UVM_LOW)
                result = 0;
            end
        end
        // Compare resp[] sizes & elements
        if (this.resp.size() != rhs_t.resp.size()) begin
            `uvm_info(get_type_name(),
                      $sformatf("resp size mismatch: %0d vs %0d",
                                this.resp.size(), rhs_t.resp.size()), UVM_LOW)
            return 0;
        end
        foreach (this.resp[i]) begin
            if (this.resp[i] != rhs_t.resp[i]) begin
                `uvm_info(get_type_name(),
                          $sformatf("resp[%0d] mismatch: %s vs %s",
                                    i, this.resp[i].name(), rhs_t.resp[i].name()), UVM_LOW)
                result = 0;
            end
        end
        return result;
    endfunction : do_compare

    //-------------------------------------------------------------------------
    // do_print - print UVM output
    //-------------------------------------------------------------------------
    function void do_print(uvm_printer printer);
        super.do_print(printer);    // prints all registered fields
        // Manually print trans[]
        printer.print_generic("trans.size()", "int", $bits(trans.size()),
                              $sformatf("%0d", trans.size()));
        foreach (trans[i])
            printer.print_generic($sformatf("trans[%0d]", i), "ahb_trans_e", 2,
                                  trans[i].name());
        // Manually print resp[]
        printer.print_generic("resp.size()", "int", $bits(resp.size()),
                              $sformatf("%0d", resp.size()));
        foreach (resp[i])
            printer.print_generic($sformatf("resp[%0d]", i), "ahb_resp_e", 1,
                                  resp[i].name());
    endfunction : do_print

    //-------------------------------------------------------------------------
    // convert2string - human-readable transaction summary for debug
    //-------------------------------------------------------------------------
    function string convert2string();
        string s;
        int num_beats;
        num_beats = get_num_beats();
        s = $sformatf("\n---------- AHB-Lite Transaction ----------");
        s = {s, $sformatf("\n DIR    = %s",     write.name())};
        s = {s, $sformatf("\n ADDR   = 0x%08h", addr)};
        s = {s, $sformatf("\n BURST  = %s",     burst.name())};
        s = {s, $sformatf("\n SIZE   = %s (%0d bytes/beat)", size.name(), 1 << size)};
        s = {s, $sformatf("\n LOCK   = %0b",    lock)};
        s = {s, $sformatf("\n PROT   = %s",     prot.name())};
        s = {s, $sformatf("\n BEATS  = %0d",    num_beats)};
        s = {s, $sformatf("\n ABORT_ON_ERROR = %0b", abort_on_error)};
        if (trailing_busy_cycles > 0)
            s = {s, $sformatf("\n TRAILING_BUSY  = %0d", trailing_busy_cycles)};
        for (int i = 0; i < num_beats; i++) begin
            s = {s, $sformatf("\n   [%0d] TRANS=%s", i,
                              (i < trans.size()) ? trans[i].name() : "N/A")};
            if (i < busy_cycles.size() && busy_cycles[i] > 0)
                s = {s, $sformatf("  (+%0d BUSY before)", busy_cycles[i])};
            if (write == AHB_WRITE)
                s = {s, $sformatf("  WDATA=0x%08h",
                                  (i < wdata.size()) ? wdata[i] : '0)};
            else
                s = {s, $sformatf("  RDATA=0x%08h  RESP=%s",
                                  (i < rdata.size()) ? rdata[i] : '0,
                                  (i < resp.size())  ? resp[i].name() : "N/A")};
        end
        s = {s, "\n------------------------------------------\n"};
        return s;
    endfunction : convert2string

endclass : ahb_transaction