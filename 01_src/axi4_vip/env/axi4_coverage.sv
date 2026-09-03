//==============================================================================
// File        : axi4_coverage.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 functional coverage collector.
//               Subscribes to an agent's analysis port and collects coverage
//               on transaction control fields, address space, burst patterns,
//               response types, and write strobe patterns.
//               Instantiate one per agent (master + slave) in the environment.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_coverage extends uvm_subscriber #(axi4_transaction);

    `uvm_component_utils(axi4_coverage)

    // =========================================================================
    // Sampled fields (copied from transaction for covergroup sampling)
    // =========================================================================
    protected axi4_dir_e                     m_dir;
    protected bit [AXI4_ID_WIDTH-1:0]        m_id;
    protected bit [AXI4_ADDR_WIDTH-1:0]      m_addr;
    protected bit [AXI4_LEN_WIDTH-1:0]       m_len;
    protected axi4_size_e                    m_size;
    protected axi4_burst_type_e              m_burst;
    protected axi4_lock_e                    m_lock;
    protected bit [3:0]                      m_cache;
    protected bit [2:0]                      m_prot;
    protected bit [3:0]                      m_qos;
    protected axi4_resp_e                    m_resp;
    protected bit [AXI4_STRB_WIDTH-1:0]      m_strb;        // per-beat write strobe
    protected bit                            m_addr_aligned; // addr aligned to size?

    // =========================================================================
    // Covergroup 1: Transaction control fields & key crosses
    //   Sampled once per transaction.
    // =========================================================================
    covergroup cg_transaction;
        cp_dir: coverpoint m_dir {
            bins read  = {AXI4_READ};
            bins write = {AXI4_WRITE};
        }

        cp_burst: coverpoint m_burst {
            bins fixed = {AXI4_BURST_FIXED};
            bins incr  = {AXI4_BURST_INCR};
            bins wrap  = {AXI4_BURST_WRAP};
        }

        cp_size: coverpoint m_size {
            bins sizes[] = {AXI4_SIZE_1B, AXI4_SIZE_2B, AXI4_SIZE_4B, 
                            AXI4_SIZE_8B, AXI4_SIZE_16B, AXI4_SIZE_32B, 
                            AXI4_SIZE_64B, AXI4_SIZE_128B} with ((1 << item) <= (AXI4_DATA_WIDTH / 8));
        }

        cp_len: coverpoint m_len {
            bins single    = {0};           // 1 beat
            bins short_b   = {[1:3]};       // 2-4 beats
            bins medium_b  = {[4:15]};      // 5-16 beats
            bins long_b    = {[16:63]};     // 17-64 beats
            bins very_long = {[64:254]};    // 65-255 beats
            bins max_b     = {255};         // 256 beats
        }

        cp_lock: coverpoint m_lock {
            bins normal    = {AXI4_LOCK_NORMAL};
            bins exclusive = {AXI4_LOCK_EXCLUSIVE};
        }

        cp_id: coverpoint m_id {
            bins ids[] = {[0:$]};
        }

        cp_qos: coverpoint m_qos {
            bins low      = {[0:3]};        // low priority
            bins med      = {[4:7]};        // medium priority
            bins high     = {[8:11]};       // high priority
            bins critical = {[12:15]};      // critical priority
        }

        cp_cache: coverpoint m_cache;       // auto-bins for all 16 values

        cp_prot: coverpoint m_prot;         // auto-bins for all 8 values

        // Key cross coverages - AXI4 protocol exploration
        cx_dir_burst:  cross cp_dir, cp_burst;
        cx_dir_size:   cross cp_dir, cp_size;
        cx_dir_len:    cross cp_dir, cp_len;
        cx_dir_lock:   cross cp_dir, cp_lock;
        cx_burst_len:  cross cp_burst, cp_len {
            // FIXED burst length must be <= 16 (m_len <= 15)
            ignore_bins fixed_too_long = binsof(cp_burst.fixed) && (binsof(cp_len.long_b) || binsof(cp_len.very_long) || binsof(cp_len.max_b));
            // WRAP burst length must be 2, 4, 8, or 16 (m_len = 1, 3, 7, 15)
            // So it cannot be single (m_len 0), long_b, very_long, or max_b
            ignore_bins wrap_illegal_lens = binsof(cp_burst.wrap) && (binsof(cp_len.single) || binsof(cp_len.long_b) || binsof(cp_len.very_long) || binsof(cp_len.max_b));
        }
        cx_burst_size: cross cp_burst, cp_size;
    endgroup

    // =========================================================================
    // Covergroup 2: Address space & alignment
    //   Sampled once per transaction.
    //   Checks address range distribution and alignment relative to burst size.
    // =========================================================================
    covergroup cg_address;
        cp_addr_low: coverpoint m_addr[1:0] {
            bins byte_lanes[] = {[0:3]};
        }

        cp_addr_region: coverpoint m_addr[31:28] {
            bins regions[] = {[0:15]};
        }

        cp_aligned: coverpoint m_addr_aligned {
            bins aligned   = {1'b1};
            bins unaligned = {1'b0};
        }

        cp_burst: coverpoint m_burst {
            bins fixed = {AXI4_BURST_FIXED};
            bins incr  = {AXI4_BURST_INCR};
            bins wrap  = {AXI4_BURST_WRAP};
        }

        // Unaligned INCR/FIXED is common; WRAP must be aligned (constrained by AXI spec)
        cx_aligned_burst: cross cp_aligned, cp_burst {
            ignore_bins unaligned_wrap = binsof(cp_aligned.unaligned) && binsof(cp_burst.wrap);
        }
    endgroup

    // =========================================================================
    // Covergroup 3: Response types
    //   Sampled once per write (B channel) or per beat for reads (R channel).
    // =========================================================================
    covergroup cg_response;
        cp_dir: coverpoint m_dir {
            bins read  = {AXI4_READ};
            bins write = {AXI4_WRITE};
        }

        cp_resp: coverpoint m_resp {
            bins okay   = {AXI4_RESP_OKAY};
            bins exokay = {AXI4_RESP_EXOKAY};
            bins slverr = {AXI4_RESP_SLVERR};
            bins decerr = {AXI4_RESP_DECERR};
        }

        cx_dir_resp: cross cp_dir, cp_resp;
    endgroup

    // =========================================================================
    // Covergroup 4: Write strobe patterns
    //   Sampled per beat (only for write transactions).
    //   Tracks full-word, no-byte, and partial strobe patterns.
    // =========================================================================
    covergroup cg_write_strobe;
        cp_strb: coverpoint m_strb {
            bins all_bytes = {{AXI4_STRB_WIDTH{1'b1}}};
            bins no_bytes  = {0};
            bins partial   = default;
        }
    endgroup

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_transaction  = new();
        cg_address      = new();
        cg_response     = new();
        cg_write_strobe = new();
    endfunction : new

    // =========================================================================
    // write() - called automatically by analysis_export for each transaction
    //   Copies scalar fields, then samples covergroups.
    //   Response and strobe covergroups are sampled per-beat where appropriate.
    // =========================================================================
    function void write(axi4_transaction t);
        // Copy scalar fields for sampling
        m_dir    = t.dir;
        m_id     = t.id;
        m_addr   = t.addr;
        m_len    = t.len;
        m_size   = t.size;
        m_burst  = t.burst;
        m_lock   = t.lock;
        m_cache  = t.cache;
        m_prot   = t.prot;
        m_qos    = t.qos;

        // Compute address alignment: aligned if addr % (2^size) == 0
        m_addr_aligned = (t.addr % (1 << t.size)) == 0;

        // Sample transaction-level covergroups
        cg_transaction.sample();
        cg_address.sample();

        // Direction-specific coverage
        if (t.dir == AXI4_WRITE) begin
            // Write: single response per burst (B channel)
            m_resp = t.resp;
            cg_response.sample();

            // Per-beat write strobe coverage
            foreach (t.strb[i]) begin
                m_strb = t.strb[i];
                cg_write_strobe.sample();
            end
        end else begin
            // Read: per-beat response coverage (R channel)
            foreach (t.rresp[i]) begin
                m_resp = t.rresp[i];
                cg_response.sample();
            end
        end
    endfunction : write

endclass : axi4_coverage