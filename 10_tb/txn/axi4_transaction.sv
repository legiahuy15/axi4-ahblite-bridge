//=============================================================================
// File        : axi4_transaction.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 request and completion transaction.
//               Included inside the bridge package.
//=============================================================================

class axi4_transaction extends uvm_sequence_item;

    // Request fields
    rand axi4_dir_e                    dir;
    rand axi4_wr_order_e               wr_order;
    rand bit [AXI4_ID_WIDTH-1:0]       id;
    rand bit [AXI4_ADDR_WIDTH-1:0]     addr;
    rand bit [AXI4_LEN_WIDTH-1:0]      len;
    rand axi4_size_e                   size;
    rand axi4_burst_e                  burst;
    rand axi4_lock_e                   lock;
    rand bit [3:0]                     cache;
    rand bit [2:0]                     prot;
    rand bit [AXI4_DATA_WIDTH-1:0]     data[];
    rand bit [AXI4_STRB_WIDTH-1:0]     strb[];

    // Completion fields
    rand axi4_resp_e                   bresp;
    rand axi4_resp_e                   rresp[];

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
        `uvm_field_enum(axi4_burst_e,      burst,    UVM_ALL_ON)
        `uvm_field_enum(axi4_lock_e,       lock,     UVM_ALL_ON)
        `uvm_field_int(                    cache,    UVM_ALL_ON)
        `uvm_field_int(                    prot,     UVM_ALL_ON)
        `uvm_field_array_int(              data,     UVM_ALL_ON)
        `uvm_field_array_int(              strb,     UVM_ALL_ON)
        `uvm_field_enum(axi4_resp_e,       bresp,    UVM_ALL_ON)
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constraints
    //-------------------------------------------------------------------------
    constraint c_array_size {
        data.size() == int'(len) + 1;
        if (dir == AXI4_WRITE) {
            strb.size()  == int'(len) + 1;
            rresp.size() == 0;
        } else {
            strb.size()  == 0;
            rresp.size() == int'(len) + 1;
        }
    }

    constraint c_size {
        (1 << size) <= AXI4_STRB_WIDTH;
    }

    constraint c_burst_length {
        (burst == AXI4_BURST_FIXED) -> len <= 15;
        (burst == AXI4_BURST_WRAP)  -> len inside {1, 3, 7, 15};
    }

    constraint c_wrap_alignment {
        (burst == AXI4_BURST_WRAP) -> (addr % (1 << size)) == 0;
    }

    constraint c_4kb_boundary {
        (burst == AXI4_BURST_INCR) ->
            ((addr >> 12) ==
             ((((addr >> size) << size) +
               ((int'(len) + 1) * (1 << size)) - 1) >> 12));
    }

    constraint c_bridge_defaults {
        soft lock == AXI4_LOCK_NORMAL;
        soft (addr % (1 << size)) == 0;
        soft bresp == AXI4_RESP_OKAY;
        foreach (rresp[i]) soft rresp[i] == AXI4_RESP_OKAY;
        (dir == AXI4_READ) -> wr_order == AXI4_WR_PARALLEL;
    }

    constraint c_distribution {
        burst dist {
            AXI4_BURST_INCR  := 60,
            AXI4_BURST_FIXED := 20,
            AXI4_BURST_WRAP  := 20
        };
        len dist {
            0        := 30,
            [1:3]    := 30,
            [4:15]   := 25,
            [16:255] := 15
        };
    }

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_transaction");
        super.new(name);
        if (AXI4_ADDR_WIDTH < 32 || AXI4_ADDR_WIDTH > 64)
            `uvm_fatal("AXI4_CFG", $sformatf("Illegal AXI4_ADDR_WIDTH=%0d", AXI4_ADDR_WIDTH))
        if (!(AXI4_DATA_WIDTH inside {32, 64}))
            `uvm_fatal("AXI4_CFG", $sformatf("Illegal AXI4_DATA_WIDTH=%0d", AXI4_DATA_WIDTH))
        if (AXI4_ID_WIDTH < 1 || AXI4_ID_WIDTH > 32)
            `uvm_fatal("AXI4_CFG", $sformatf("Illegal AXI4_ID_WIDTH=%0d", AXI4_ID_WIDTH))
    endfunction : new

    //-------------------------------------------------------------------------
    // Helpers
    //-------------------------------------------------------------------------
    function void do_copy(uvm_object rhs);
        axi4_transaction rhs_t;
        super.do_copy(rhs);
        if (!$cast(rhs_t, rhs))
            `uvm_fatal(get_type_name(), "do_copy cast failed")
        rresp = new[rhs_t.rresp.size()];
        foreach (rhs_t.rresp[i])
            rresp[i] = rhs_t.rresp[i];
    endfunction : do_copy

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axi4_transaction rhs_t;
        bit result;

        result = super.do_compare(rhs, comparer);
        if (!$cast(rhs_t, rhs))
            return 0;
        if (rresp.size() != rhs_t.rresp.size())
            return 0;
        foreach (rresp[i])
            if (rresp[i] != rhs_t.rresp[i])
                result = 0;
        return result;
    endfunction : do_compare

    function void do_print(uvm_printer printer);
        super.do_print(printer);
        foreach (rresp[i])
            printer.print_generic($sformatf("rresp[%0d]", i),
                                  "axi4_resp_e", 2, rresp[i].name());
    endfunction : do_print

    function string convert2string();
        return $sformatf("AXI4 %s id=0x%0h addr=0x%0h burst=%s beats=%0d size=%0dB",
                         dir.name(), id, addr, burst.name(), int'(len) + 1,
                         1 << size);
    endfunction : convert2string

endclass : axi4_transaction