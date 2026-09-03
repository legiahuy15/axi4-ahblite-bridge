//==============================================================================
// File        : axi4_addr_data_integrity_seq.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Known-answer address/data integrity sequence.
//
//               The scoreboard's read check rebuilds expected data with the
//               SAME calc_beat_addr used by the slave, so a bug in the burst
//               address math would be duplicated on both sides and go
//               undetected. This sequence provides an INDEPENDENT reference:
//
//                 1. Seed memory over a 256-byte window with a trusted, simple
//                    INCR write so that mem[A] == A[7:0] for every byte A.
//                 2. Read the window back with WRAP / unaligned-INCR / narrow
//                    bursts and, for each beat, compute the expected data from
//                    a SEPARATELY-CODED beat-address function (ref_beat_addr)
//                    plus the address-encoded memory contents.
//
//               Any error in WRAP wrap-around, unaligned first-beat, or narrow
//               byte-lane placement then shows up as a data mismatch.
//               `errors` counts mismatches (0 = all correct).
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_ADDR_DATA_INTEGRITY_SEQ_INCLUDED_
`define AXI4_ADDR_DATA_INTEGRITY_SEQ_INCLUDED_

class axi4_addr_data_integrity_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_addr_data_integrity_seq)

    // 256-byte aligned window: mem[BASE+k] == k for k in 0..255 after seeding.
    localparam bit [AXI4_ADDR_WIDTH-1:0] BASE = 32'h0000_4000;

    int unsigned errors = 0;

    function new(string name = "axi4_addr_data_integrity_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // ref_beat_addr - INDEPENDENT (spec-derived) per-beat address.
    //   Intentionally a separate implementation from the driver/scoreboard's
    //   calc_beat_addr so a bug in either is exposed.
    // =========================================================================
    function bit [AXI4_ADDR_WIDTH-1:0] ref_beat_addr(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int                       beat,
        int                       num_bytes,
        axi4_burst_type_e         burst,
        int                       len);
        int total = num_bytes * (len + 1);
        bit [AXI4_ADDR_WIDTH-1:0] aligned = (start_addr / num_bytes) * num_bytes;
        bit [AXI4_ADDR_WIDTH-1:0] wrap_lo = (start_addr / total) * total;
        bit [AXI4_ADDR_WIDTH-1:0] a;
        case (burst)
            AXI4_BURST_FIXED: return start_addr;
            AXI4_BURST_INCR:  return (beat == 0) ? start_addr : (aligned + beat * num_bytes);
            AXI4_BURST_WRAP: begin
                if (beat == 0) return start_addr;
                a = aligned + beat * num_bytes;
                if (a >= wrap_lo + total) a -= total;
                return a;
            end
            default: return start_addr;
        endcase
    endfunction : ref_beat_addr

    // =========================================================================
    // ref_beat_data - expected RDATA word for a beat, given mem[A] == A[7:0].
    //   Mirrors the AXI4 byte-lane rule (lane = addr % STRB_WIDTH); inactive
    //   lanes read as 0.
    // =========================================================================
    function bit [AXI4_DATA_WIDTH-1:0] ref_beat_data(
        bit [AXI4_ADDR_WIDTH-1:0] beat_addr,
        int                       num_bytes);
        bit [AXI4_DATA_WIDTH-1:0] d = '0;
        for (int off = 0; off < num_bytes; off++) begin
            bit [AXI4_ADDR_WIDTH-1:0] ba = beat_addr + off;
            int lane = ba % AXI4_STRB_WIDTH;
            d[lane*8 +: 8] = ba[7:0];
        end
        return d;
    endfunction : ref_beat_data

    // =========================================================================
    // seed_memory - trusted INCR write so mem[BASE+k] == (BASE+k)[7:0].
    //   64 beats * 4 bytes = 256 bytes. Fields are set manually (no randomize)
    //   so the payload is exactly the address-encoded pattern.
    // =========================================================================
    task seed_memory();
        axi4_transaction tr;
        tr = axi4_transaction::type_id::create("seed_wr");
        tr.dir   = AXI4_WRITE;
        tr.id    = 4'h1;
        tr.addr  = BASE;
        tr.size  = AXI4_SIZE_4B;
        tr.burst = AXI4_BURST_INCR;
        tr.len   = 63;
        tr.lock  = AXI4_LOCK_NORMAL;
        tr.data  = new[64];
        tr.strb  = new[64];
        tr.rresp = new[64];
        for (int i = 0; i < 64; i++) begin
            tr.data[i] = '0;
            for (int j = 0; j < 4; j++)
                tr.data[i][j*8 +: 8] = (BASE + i*4 + j);   // = (i*4+j) since BASE%256==0
            tr.strb[i] = '1;                               // full byte-enables
        end
        start_item(tr);
        finish_item(tr);
        wait(tr.done_event.ev.triggered);
        `uvm_info(get_type_name(),
                  $sformatf("Seeded 256 bytes at 0x%08h (mem[A]=A[7:0]) RESP=%s",
                            BASE, tr.resp.name()), UVM_MEDIUM)
    endtask : seed_memory

    // =========================================================================
    // read_and_check - read one burst and verify every beat independently.
    // =========================================================================
    task read_and_check(bit [AXI4_ADDR_WIDTH-1:0] addr,
                        axi4_size_e               size,
                        axi4_burst_type_e         burst,
                        bit [7:0]                 len,
                        string                    tag);
        axi4_transaction tr;
        int num_bytes = (1 << size);
        tr = axi4_transaction::type_id::create("chk_rd");
        tr.dir   = AXI4_READ;
        tr.id    = 4'h2;
        tr.addr  = addr;
        tr.size  = size;
        tr.burst = burst;
        tr.len   = len;
        tr.lock  = AXI4_LOCK_NORMAL;
        tr.data  = new[len + 1];
        tr.strb  = new[len + 1];
        tr.rresp = new[len + 1];
        foreach (tr.strb[i]) tr.strb[i] = '1;

        start_item(tr);
        finish_item(tr);
        wait(tr.done_event.ev.triggered);

        for (int b = 0; b <= len; b++) begin
            bit [AXI4_ADDR_WIDTH-1:0] ba  = ref_beat_addr(addr, b, num_bytes, burst, len);
            bit [AXI4_DATA_WIDTH-1:0] exp = ref_beat_data(ba, num_bytes);
            if (tr.data[b] !== exp) begin
                errors++;
                `uvm_error(get_type_name(),
                           $sformatf("%s beat[%0d]: addr=0x%08h expected 0x%08h, read 0x%08h",
                                     tag, b, ba, exp, tr.data[b]))
            end
        end
        `uvm_info(get_type_name(),
                  $sformatf("%s: checked %0d beats from ADDR=0x%08h SIZE=%s BURST=%s",
                            tag, len + 1, addr, size.name(), burst.name()), UVM_LOW)
    endtask : read_and_check

    // =========================================================================
    // body
    // =========================================================================
    virtual task body();
        `uvm_info(get_type_name(),
                  "Starting known-answer address/data integrity sequence", UVM_MEDIUM)

        seed_memory();

        // WRAP 4B, 16 beats (64B), start forces a wrap at the 64B boundary
        read_and_check(BASE + 32'h08, AXI4_SIZE_4B, AXI4_BURST_WRAP, 8'd15, "WRAP_4B");
        // WRAP 2B, 8 beats (16B), start forces a wrap at the 16B boundary
        read_and_check(BASE + 32'h06, AXI4_SIZE_2B, AXI4_BURST_WRAP, 8'd7,  "WRAP_2B");
        // Unaligned INCR 4B: first beat at a non-4B-aligned address
        read_and_check(BASE + 32'h02, AXI4_SIZE_4B, AXI4_BURST_INCR, 8'd3,  "UNALIGN_4B");
        // Narrow 1B, 8 beats - byte-lane rotates every beat
        read_and_check(BASE + 32'h10, AXI4_SIZE_1B, AXI4_BURST_INCR, 8'd7,  "NARROW_1B");
        // Narrow 2B, 6 beats
        read_and_check(BASE + 32'h20, AXI4_SIZE_2B, AXI4_BURST_INCR, 8'd5,  "NARROW_2B");
        // FIXED 4B: same aligned address every beat
        read_and_check(BASE + 32'h30, AXI4_SIZE_4B, AXI4_BURST_FIXED, 8'd3, "FIXED_4B");

        `uvm_info(get_type_name(),
                  $sformatf("Known-answer integrity sequence complete (%0d mismatches)", errors),
                  UVM_MEDIUM)
    endtask : body

endclass : axi4_addr_data_integrity_seq

`endif // AXI4_ADDR_DATA_INTEGRITY_SEQ_INCLUDED_