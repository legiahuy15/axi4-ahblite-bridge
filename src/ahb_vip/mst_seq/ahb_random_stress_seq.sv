//=============================================================================
// File        : ahb_random_stress_seq.sv
// Project     : AMBA 3 AHB-Lite VIP
// Description : Constrained-random mixed burst stress with read-back checking.
//=============================================================================

`ifndef AHB_RANDOM_STRESS_SEQ_INCLUDED_
`define AHB_RANDOM_STRESS_SEQ_INCLUDED_

class ahb_random_stress_seq extends ahb_base_seq;

    `uvm_object_utils(ahb_random_stress_seq)

    int unsigned num_iter = 100;
    int unsigned wait_max = 7;
    bit [AHB_ADDR_WIDTH-1:0] base_addr = 32'h0002_0000;

    ahb_slave_driver slv_drv;

    localparam int unsigned SLOT_SIZE = 128;

    int unsigned num_pipelined;
    int unsigned num_busy_write;
    int unsigned num_busy_read;
    int unsigned num_multibeat_write;
    int unsigned num_zero_wait_pairs;
    int unsigned num_max_wait_pairs;
    int unsigned burst_count[8];
    int unsigned size_count[3];

    function new(string name = "ahb_random_stress_seq");
        super.new(name);
    endfunction : new

    // Randomize BUSY independently on the read-back as well. An explicit
    // non-zero constraint is required to override ahb_transaction's soft
    // no-BUSY default; a dist containing zero alone does not override it.
    virtual function ahb_transaction build_read_back(ahb_transaction wr);
        ahb_transaction rd;
        bit             inject_busy;
        bit             inject_trailing_busy;

        inject_busy          = $urandom_range(1, 0);
        inject_trailing_busy = $urandom_range(1, 0);

        rd = ahb_transaction::type_id::create("rd");
        if (!rd.randomize() with {
                write     == AHB_READ;
                burst     == wr.burst;
                size      == wr.size;
                addr      == wr.addr;
                num_beats == wr.num_beats;
                foreach (busy_cycles[k])
                    (inject_busy && k == 1) ->
                        busy_cycles[k] inside {[1:3]};
                (inject_trailing_busy && burst == AHB_BURST_INCR) ->
                    trailing_busy_cycles inside {[1:3]};
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("Read randomization failed (%s @0x%08h)",
                                 wr.burst.name(), wr.addr))

        foreach (rd.busy_cycles[k])
            if (rd.busy_cycles[k] != 0) begin
                num_busy_read++;
                return rd;
            end
        if (rd.trailing_busy_cycles != 0) num_busy_read++;
        return rd;
    endfunction : build_read_back

    virtual task body();
        ahb_transaction          wr;
        bit [AHB_ADDR_WIDTH-1:0] slot;
        int unsigned             wait_lo;
        int unsigned             wait_hi;
        bit                      pipelined;
        bit                      has_busy;
        bit                      inject_busy;
        bit                      inject_trailing_busy;

        if (num_iter == 0)
            `uvm_fatal(get_type_name(), "NUM_ITER must be greater than zero")
        if (num_iter < 2 && wait_max != 0)
            `uvm_fatal(get_type_name(),
                       "NUM_ITER must be at least two when WAIT_MAX is non-zero")

        `uvm_info(get_type_name(),
                  $sformatf("Starting random stress: iterations=%0d base=0x%08h wait_max=%0d",
                            num_iter, base_addr, wait_max), UVM_LOW)

        for (int unsigned i = 0; i < num_iter; i++) begin
            slot = base_addr + i * SLOT_SIZE;

            // Change slave timing only after the preceding pair has drained.
            // The first two pairs are deterministic coverage anchors; the
            // remaining pairs retain constrained-random back-pressure.
            if (i == 0) begin
                wait_lo = 0;
                wait_hi = 0;
            end else if (i == 1) begin
                wait_lo = wait_max;
                wait_hi = wait_max;
            end else begin
                wait_lo = $urandom_range(wait_max, 0);
                wait_hi = $urandom_range(wait_max, wait_lo);
            end

            if (wait_lo == 0 && wait_hi == 0) num_zero_wait_pairs++;
            if (wait_lo == wait_max && wait_hi == wait_max)
                num_max_wait_pairs++;
            if (slv_drv != null) begin
                slv_drv.ready_delay_min = wait_lo;
                slv_drv.ready_delay_max = wait_hi;
            end

            pipelined = $urandom_range(1, 0);
            inject_busy          = $urandom_range(1, 0);
            inject_trailing_busy = $urandom_range(1, 0);

            wr = ahb_transaction::type_id::create($sformatf("wr_%0d", i));
            if (!wr.randomize() with {
                    write == AHB_WRITE;
                    size inside {AHB_SIZE_8B, AHB_SIZE_16B, AHB_SIZE_32B};
                    burst inside {AHB_BURST_SINGLE, AHB_BURST_INCR,
                                  AHB_BURST_WRAP4, AHB_BURST_INCR4,
                                  AHB_BURST_WRAP8, AHB_BURST_INCR8,
                                  AHB_BURST_WRAP16, AHB_BURST_INCR16};
                    (burst == AHB_BURST_INCR) -> (num_beats inside {[1:16]});
                    addr inside {[slot : slot + SLOT_SIZE - 1]};
                    (burst inside {AHB_BURST_INCR, AHB_BURST_INCR4,
                                   AHB_BURST_INCR8, AHB_BURST_INCR16}) ->
                        (addr + num_beats * (1 << size) <= slot + SLOT_SIZE);
                    foreach (busy_cycles[k])
                        (inject_busy && k == 1) ->
                            busy_cycles[k] inside {[1:3]};
                    (inject_trailing_busy && burst == AHB_BURST_INCR) ->
                        trailing_busy_cycles inside {[1:3]};
                })
                `uvm_fatal(get_type_name(),
                           $sformatf("Randomization failed at iteration %0d, slot 0x%08h",
                                     i, slot))

            has_busy = (wr.trailing_busy_cycles != 0);
            foreach (wr.busy_cycles[k])
                has_busy |= (wr.busy_cycles[k] != 0);

            burst_count[int'(wr.burst)]++;
            size_count[int'(wr.size)]++;
            if (pipelined) num_pipelined++;
            if (wr.num_beats > 1) num_multibeat_write++;
            if (has_busy)         num_busy_write++;

            `uvm_info(get_type_name(),
                      $sformatf("iter=%0d %s %s addr=0x%08h beats=%0d waits=%0d:%0d pipeline=%0b busy=%0b",
                                i, wr.burst.name(), wr.size.name(), wr.addr,
                                wr.num_beats, wait_lo, wait_hi,
                                pipelined, has_busy), UVM_MEDIUM)

            write_read_burst(wr, pipelined);
        end

        `uvm_info(get_type_name(),
                  $sformatf("Random stress done: pairs=%0d pipelined=%0d busy_wr=%0d/%0d busy_rd=%0d waits_zero=%0d waits_max=%0d beats=%0d mismatch=%0d",
                            num_iter, num_pipelined, num_busy_write,
                            num_multibeat_write, num_busy_read,
                            num_zero_wait_pairs, num_max_wait_pairs,
                            beats_checked, beats_mismatch),
                  (beats_mismatch == 0) ? UVM_LOW : UVM_NONE)

        if (num_multibeat_write != 0 &&
            (num_busy_write == 0 || num_busy_read == 0))
            `uvm_error(get_type_name(),
                       "Random stress generated no BUSY traffic in one direction")

        if (num_zero_wait_pairs == 0 || num_max_wait_pairs == 0)
            `uvm_error(get_type_name(),
                       "Random stress missed a deterministic wait-state coverage anchor")
    endtask : body

endclass : ahb_random_stress_seq

`endif // AHB_RANDOM_STRESS_SEQ_INCLUDED_
