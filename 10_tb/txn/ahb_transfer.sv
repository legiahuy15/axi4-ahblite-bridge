//=============================================================================
// File        : ahb_transfer.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Completed AHB-Lite transfer item.
//               Included inside the bridge package.
//=============================================================================

class ahb_transfer extends uvm_sequence_item;

    // Address phase
    rand bit [AHB_ADDR_WIDTH-1:0] addr;
    rand ahb_dir_e            write;
    rand ahb_trans_e          trans;
    rand ahb_burst_e          burst;
    rand ahb_size_e           size;
    rand bit [3:0]            prot;
    rand bit                  mastlock;

    // Data phase
    rand bit [AHB_DATA_WIDTH-1:0] wdata;
    rand bit [AHB_DATA_WIDTH-1:0] rdata;
    rand ahb_resp_e           resp;
    // HREADY-low cycles before completion; includes the first ERROR cycle.
    rand int unsigned         wait_cycles;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(ahb_transfer)
        `uvm_field_int(              addr,        UVM_ALL_ON)
        `uvm_field_enum(ahb_dir_e,   write,       UVM_ALL_ON)
        `uvm_field_enum(ahb_trans_e, trans,       UVM_ALL_ON)
        `uvm_field_enum(ahb_burst_e, burst,       UVM_ALL_ON)
        `uvm_field_enum(ahb_size_e,  size,        UVM_ALL_ON)
        `uvm_field_int(              prot,        UVM_ALL_ON)
        `uvm_field_int(              mastlock,    UVM_ALL_ON)
        `uvm_field_int(              wdata,       UVM_ALL_ON)
        `uvm_field_int(              rdata,       UVM_ALL_ON)
        `uvm_field_enum(ahb_resp_e,  resp,        UVM_ALL_ON)
        `uvm_field_int(              wait_cycles, UVM_ALL_ON)
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constraints
    //-------------------------------------------------------------------------
    constraint c_active_transfer {
        trans inside {AHB_TRANS_NONSEQ, AHB_TRANS_SEQ};
    }

    constraint c_size {
        (1 << size) <= (AHB_DATA_WIDTH / 8);
    }

    constraint c_alignment {
        (addr % (1 << size)) == 0;
    }

    constraint c_defaults {
        soft mastlock    == 1'b0;
        soft resp        == AHB_RESP_OKAY;
        soft wait_cycles == 0;
    }

    //-------------------------------------------------------------------------
    // Constructors
    //-------------------------------------------------------------------------
    function new(string name = "ahb_transfer");
        super.new(name);
        if (AHB_ADDR_WIDTH < 32 || AHB_ADDR_WIDTH > 64)
            `uvm_fatal("AHB_CFG", $sformatf("Illegal AHB_ADDR_WIDTH=%0d", AHB_ADDR_WIDTH))
        if (!(AHB_DATA_WIDTH inside {32, 64}))
            `uvm_fatal("AHB_CFG", $sformatf("Illegal AHB_DATA_WIDTH=%0d", AHB_DATA_WIDTH))
    endfunction : new

    //-------------------------------------------------------------------------
    // Helpers
    //-------------------------------------------------------------------------
    function string convert2string();
        return $sformatf("AHB %s addr=0x%0h trans=%s burst=%s size=%0dB resp=%s waits=%0d",
                         write.name(), addr, trans.name(), burst.name(),
                         1 << size, resp.name(), wait_cycles);
    endfunction : convert2string

endclass : ahb_transfer