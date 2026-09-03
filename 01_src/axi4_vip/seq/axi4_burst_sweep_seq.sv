//==============================================================================
// File        : axi4_burst_sweep_seq.sv
// Project     : AXI4 VIP
// Author      : Antigravity
// Description : AXI4 Burst Type, Size, and Length Sweep Sequence.
//               Systematically generates transactions to cover all legal
//               combinations of burst type, transfer size, and burst length,
//               ensuring 100% cross coverage of cx_burst_len and cx_burst_size.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_BURST_SWEEP_SEQ_INCLUDED_
`define AXI4_BURST_SWEEP_SEQ_INCLUDED_

class axi4_burst_sweep_seq extends axi4_base_sequence;

    `uvm_object_utils(axi4_burst_sweep_seq)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_burst_sweep_seq");
        super.new(name);
    endfunction : new

    // =========================================================================
    // Body task
    // =========================================================================
    virtual task body();
        axi4_transaction tr;
        int count = 0;
        int fixed_lens[5] = '{0, 1, 2, 3, 4};
        int wrap_lens[4]  = '{0, 1, 2, 3};
        int incr_lens[6]  = '{0, 1, 2, 3, 4, 5};
        int sizes[3]      = '{0, 1, 2};
        int err_types[2]  = '{0, 1};

        `uvm_info(get_type_name(), "Starting burst type, size, and length sweep sequence", UVM_MEDIUM)

        // 1. FIXED bursts (lengths 0, 1, 3, 7, 15; sizes 1B, 2B, 4B)
        foreach (fixed_lens[l]) begin
            bit [7:0] len_val;
            case (l)
                0: len_val = 0;   // 1 beat
                1: len_val = 1;   // 2 beats
                2: len_val = 3;   // 4 beats
                3: len_val = 7;   // 8 beats
                4: len_val = 15;  // 16 beats
            endcase

            foreach (sizes[s]) begin
                axi4_size_e size_val;
                case (s)
                    0: size_val = AXI4_SIZE_1B;
                    1: size_val = AXI4_SIZE_2B;
                    2: size_val = AXI4_SIZE_4B;
                endcase

                // Perform a write and a read
                repeat (2) begin
                    bit is_write = (count % 2 == 0);
                    tr = axi4_transaction::type_id::create($sformatf("fixed_sweep_%0d", count++));
                    start_item(tr);
                    if (!tr.randomize() with {
                        dir   == (is_write ? AXI4_WRITE : AXI4_READ);
                        addr  inside {[addr_lo : addr_hi]};
                        addr  < 32'hE000_0000;
                        id    inside {[id_lo   : id_hi]};
                        lock  == AXI4_LOCK_NORMAL;
                        burst == AXI4_BURST_FIXED;
                        size  == size_val;
                        len   == len_val;
                    }) `uvm_fatal(get_type_name(), "Randomization failed during FIXED sweep")
                    finish_item(tr);
                end
            end
        end

        // 2. WRAP bursts (lengths 1, 3, 7, 15; sizes 1B, 2B, 4B)
        foreach (wrap_lens[l]) begin
            bit [7:0] len_val;
            case (l)
                0: len_val = 1;   // 2 beats
                1: len_val = 3;   // 4 beats
                2: len_val = 7;   // 8 beats
                3: len_val = 15;  // 16 beats
            endcase

            foreach (sizes[s]) begin
                axi4_size_e size_val;
                case (s)
                    0: size_val = AXI4_SIZE_1B;
                    1: size_val = AXI4_SIZE_2B;
                    2: size_val = AXI4_SIZE_4B;
                endcase

                repeat (2) begin
                    bit is_write = (count % 2 == 0);
                    tr = axi4_transaction::type_id::create($sformatf("wrap_sweep_%0d", count++));
                    start_item(tr);
                    if (!tr.randomize() with {
                        dir   == (is_write ? AXI4_WRITE : AXI4_READ);
                        addr  inside {[addr_lo : addr_hi]};
                        addr  < 32'hE000_0000;
                        id    inside {[id_lo   : id_hi]};
                        lock  == AXI4_LOCK_NORMAL;
                        burst == AXI4_BURST_WRAP;
                        size  == size_val;
                        len   == len_val;
                    }) `uvm_fatal(get_type_name(), "Randomization failed during WRAP sweep")
                    finish_item(tr);
                end
            end
        end

        // 3. INCR bursts (sweep all length bins: 0, [1:3], [4:15], [16:63], [64:254], 255; sizes 1B, 2B, 4B)
        foreach (incr_lens[l]) begin
            bit [7:0] len_val;
            case (l)
                0: len_val = 0;   // single beat
                1: len_val = 2;   // short_b
                2: len_val = 10;  // medium_b
                3: len_val = 32;  // long_b
                4: len_val = 100; // very_long
                5: len_val = 255; // max_b
            endcase

            foreach (sizes[s]) begin
                axi4_size_e size_val;
                case (s)
                    0: size_val = AXI4_SIZE_1B;
                    1: size_val = AXI4_SIZE_2B;
                    2: size_val = AXI4_SIZE_4B;
                endcase

                repeat (2) begin
                    bit is_write = (count % 2 == 0);
                    tr = axi4_transaction::type_id::create($sformatf("incr_sweep_%0d", count++));
                    start_item(tr);
                    if (!tr.randomize() with {
                        dir   == (is_write ? AXI4_WRITE : AXI4_READ);
                        addr  inside {[addr_lo : addr_hi]};
                        addr  < 32'hE000_0000;
                        id    inside {[id_lo   : id_hi]};
                        lock  == AXI4_LOCK_NORMAL;
                        burst == AXI4_BURST_INCR;
                        size  == size_val;
                        len   == len_val;
                    }) `uvm_fatal(get_type_name(), "Randomization failed during INCR sweep")
                    finish_item(tr);
                end
            end
        end

        // 4. Inject Error Regions to hit SLVERR and DECERR coverpoints
        // SLVERR region is [32'hE000_0000 : 32'hEFFF_FFFF]
        // DECERR region is [32'hF000_0000 : 32'hFFFF_FFFF]
        foreach (err_types[e]) begin
            bit [AXI4_ADDR_WIDTH-1:0] err_addr = (e == 0) ? 32'hE000_0000 : 32'hF000_0000;
            repeat (2) begin
                bit is_write = (count % 2 == 0);
                tr = axi4_transaction::type_id::create($sformatf("err_inject_%0d", count++));
                start_item(tr);
                if (!tr.randomize() with {
                    dir   == (is_write ? AXI4_WRITE : AXI4_READ);
                    addr  == err_addr;
                    id    inside {[id_lo   : id_hi]};
                    burst == AXI4_BURST_INCR;
                    size  == AXI4_SIZE_4B;
                    len   == 0; // 1 beat
                }) `uvm_fatal(get_type_name(), "Randomization failed during error injection sweep")
                finish_item(tr);
            end
        end

        `uvm_info(get_type_name(), $sformatf("Burst sweep sequence complete: sent %0d transactions", count), UVM_MEDIUM)
    endtask : body

endclass : axi4_burst_sweep_seq

`endif // AXI4_BURST_SWEEP_SEQ_INCLUDED_