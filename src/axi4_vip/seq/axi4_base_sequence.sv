//==============================================================================
// File        : axi4_base_sequence.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Base sequence for all AXI4 master sequences.
//               Provides common configuration knobs shared by derived
//               sequences: address range, ID range, burst constraints.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_BASE_SEQ_INCLUDED_
`define AXI4_BASE_SEQ_INCLUDED_

class axi4_base_sequence extends uvm_sequence #(axi4_transaction);

    `uvm_object_utils(axi4_base_sequence)

    // =========================================================================
    // Configurable knobs - override from test or parent sequence
    // =========================================================================
    bit [AXI4_ADDR_WIDTH-1:0] addr_lo  = 0;                        // Address range lower
    bit [AXI4_ADDR_WIDTH-1:0] addr_hi  = {AXI4_ADDR_WIDTH{1'b1}};  // Address range upper
    bit [AXI4_ID_WIDTH-1:0]   id_lo    = 0;                        // ID range lower
    bit [AXI4_ID_WIDTH-1:0]   id_hi    = {AXI4_ID_WIDTH{1'b1}};    // ID range upper

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_base_sequence");
        super.new(name);
    endfunction : new

endclass : axi4_base_sequence

`endif // AXI4_BASE_SEQ_INCLUDED_