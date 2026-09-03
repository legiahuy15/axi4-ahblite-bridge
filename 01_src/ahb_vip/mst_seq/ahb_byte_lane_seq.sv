//=============================================================================
// File        : ahb_byte_lane_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Active byte-lane walk for narrow transfers. Every beat carries
//               an address-derived payload on the lanes its address selects
//               (little endian, IHI0033A 6.1.3) and the inverted payload on the
//               lanes it must not use, so a lane-mapping error cannot read back
//               as a match. Only the active lanes are ever compared - the
//               checker never relies on data being replicated across the bus.
//               The set of lanes walked is fixed; the order they reach the bus
//               follows the seed.
//               Requires the slave agent in auto-response mode (memory model).
//               This file is `included inside ahb_seq_pkg.sv.
//=============================================================================

`ifndef AHB_BYTE_LANE_SEQ_INCLUDED_
`define AHB_BYTE_LANE_SEQ_INCLUDED_

class ahb_byte_lane_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_byte_lane_seq)

    //-------------------------------------------------------------------------
    // Knobs
    //-------------------------------------------------------------------------
    // Sizes rotate per iteration, so a full lane walk needs at least NUM_SIZE
    // iterations
    int unsigned num_iter = 12;

    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0000_E000;

    localparam int unsigned BUS_BYTES = AHB_DATA_WIDTH / 8;

    // Slot layout, word aligned: the SINGLE lane walk covers the first bus word
    // and the 4-beat burst runs in the upper half. One size per slot and every
    // address written and read at that same size, so narrow and wide accesses
    // never alias in the scoreboard reference memory
    localparam int unsigned SLOT_SIZE  = 32;
    localparam int unsigned BURST_OFFS = 16;

    localparam int unsigned NUM_SIZE = 3;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned lane_hits[BUS_BYTES];   // beats whose active window starts here
    int unsigned num_singles;
    int unsigned num_bursts;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_byte_lane_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Narrow sizes first - the word entry is the full-width reference case
    //-------------------------------------------------------------------------
    function ahb_size_e get_size(int unsigned idx);
        case (idx % NUM_SIZE)
            0:       return AHB_SIZE_8B;
            1:       return AHB_SIZE_16B;
            default: return AHB_SIZE_32B;
        endcase
    endfunction : get_size

    //-------------------------------------------------------------------------
    // Payload byte for one byte address. Address-derived, so a byte that lands
    // on the wrong lane - or at the wrong address - carries the wrong value
    //-------------------------------------------------------------------------
    function bit [7:0] byte_val(bit [AHB_ADDR_WIDTH-1:0] a);
        return a[7:0] ^ 8'hA5;
    endfunction : byte_val

    //-------------------------------------------------------------------------
    // One bus word for a beat at address a covering 'bytes' bytes:
    //   active lanes   (a % BUS_BYTES) ... +bytes-1 : the payload
    //   inactive lanes                              : the inverted payload
    // A byte and its inverse can never be equal, so a transfer driven onto the
    // wrong lanes fails the read-back check instead of passing on a match
    //-------------------------------------------------------------------------
    function bit [AHB_DATA_WIDTH-1:0] lane_pattern(bit [AHB_ADDR_WIDTH-1:0] a,
                                                   int unsigned             bytes);
        bit [AHB_DATA_WIDTH-1:0] w;
        int unsigned             lane      = a % BUS_BYTES;
        bit [AHB_ADDR_WIDTH-1:0] word_base = a - lane;

        for (int unsigned l = 0; l < BUS_BYTES; l++)
            w[l*8 +: 8] = ~byte_val(word_base + l);
        for (int unsigned b = 0; b < bytes; b++)
            w[(lane + b)*8 +: 8] = byte_val(a + b);

        return w;
    endfunction : lane_pattern

    //-------------------------------------------------------------------------
    // Body - one slot per iteration, visited in shuffled order: a SINGLE at
    // every legal offset of the first word, then a 4-beat burst that moves the
    // active window along the bus from a rotating start lane
    //-------------------------------------------------------------------------
    virtual task body();
        int unsigned             order[];
        int unsigned             offs[];
        int unsigned             idx;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        ahb_size_e               sz;
        int unsigned             bytes;
        int unsigned             burst_offs;

        `uvm_info(get_type_name(),
                  $sformatf("Starting byte-lane walk: %0d iterations from 0x%08h, %0d lanes on a %0d-bit bus",
                            num_iter, base_addr, BUS_BYTES, AHB_DATA_WIDTH), UVM_LOW)

        // Which slot takes which size is shuffled, and so is the order the
        // lanes inside a slot are visited. Every seed covers the same lanes at
        // the same addresses, but presents them to the bus in a different
        // order, so the back-to-back and wait-state overlaps differ per run
        order = new[num_iter];
        foreach (order[j]) order[j] = j;
        order.shuffle();

        foreach (order[j]) begin
            idx   = order[j];
            slot  = base_addr + idx * SLOT_SIZE;
            sz    = get_size(idx);
            bytes = 1 << sz;

            // Every legal offset inside one bus word: a byte transfer visits
            // all four lanes, a halfword lanes 0 and 2, a word the full width
            offs = new[BUS_BYTES / bytes];
            foreach (offs[k]) offs[k] = k * bytes;
            offs.shuffle();

            foreach (offs[k]) begin
                lane_transfer(AHB_BURST_SINGLE, slot + offs[k], sz);
                num_singles++;
            end

            // INCR4 through the upper half of the slot. Consecutive beats step
            // the active window along the bus; the start offset rotates with
            // the slot so a burst also enters on a non-zero lane. Widest case
            // is a word burst, 16 bytes from BURST_OFFS - exactly the rest of
            // the slot, which is why this offset is not randomized
            burst_offs = BURST_OFFS + ((idx % BUS_BYTES) & ~(bytes - 1));
            lane_transfer(AHB_BURST_INCR4, slot + burst_offs, sz);
            num_bursts++;
        end

        report_walk();
    endtask : body

    //-------------------------------------------------------------------------
    // One write/read-back pair with the payload placed by hand. wdata is left
    // free by the randomize call and filled afterwards, because the pattern
    // depends on each beat's own address. write_read_burst() compares the
    // active byte lanes only
    //-------------------------------------------------------------------------
    protected task lane_transfer(ahb_burst_e              burst_type,
                                 bit [AHB_ADDR_WIDTH-1:0] tgt_addr,
                                 ahb_size_e               sz);
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] a;
        int unsigned             bytes;

        bytes = 1 << sz;

        wr = ahb_transaction::type_id::create("wr");
        if (!wr.randomize() with {
                write == AHB_WRITE;
                burst == burst_type;
                size  == sz;
                addr  == tgt_addr;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Write randomization failed (%s %s @0x%08h)",
                                 burst_type.name(), sz.name(), tgt_addr))

        foreach (wr.wdata[k]) begin
            a           = beat_address(wr, k);
            wr.wdata[k] = lane_pattern(a, bytes);
            lane_hits[a % BUS_BYTES]++;
        end

        `uvm_info(get_type_name(),
                  $sformatf("%s %s @0x%08h: %0d beats, start lane %0d, HWDATA[0]=0x%08h",
                            burst_type.name(), sz.name(), tgt_addr,
                            wr.get_num_beats(), tgt_addr % BUS_BYTES, wr.wdata[0]),
                  UVM_MEDIUM)

        write_read_burst(wr);
    endtask : lane_transfer

    //-------------------------------------------------------------------------
    // End-of-sequence tally. The point of this sequence is that every lane
    // carried an active transfer, so a lane left untouched is a failure
    //-------------------------------------------------------------------------
    protected function void report_walk();
        `uvm_info(get_type_name(),
                  $sformatf("Byte-lane walk done: singles=%0d bursts=%0d beats=%0d mismatch=%0d",
                            num_singles, num_bursts, beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)

        foreach (lane_hits[l]) begin
            `uvm_info(get_type_name(),
                      $sformatf("  lane %0d -> %0d beats", l, lane_hits[l]),
                      UVM_MEDIUM)
            if (lane_hits[l] == 0)
                `uvm_error(get_type_name(),
                           $sformatf("byte lane %0d never carried an active transfer - raise +NUM_ITER (at least %0d needed)",
                                     l, NUM_SIZE))
        end
    endfunction : report_walk

endclass : ahb_byte_lane_seq

`endif // AHB_BYTE_LANE_SEQ_INCLUDED_
