//=============================================================================
// File        : axi4_mst_coverage.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 master-agent protocol coverage.
//               Included inside the bridge package.
//=============================================================================

class axi4_mst_coverage extends uvm_subscriber #(axi4_transaction);

    `uvm_component_utils(axi4_mst_coverage)

    //-------------------------------------------------------------------------
    // Sampled fields
    //-------------------------------------------------------------------------
    protected axi4_dir_e                    m_dir;
    protected bit [AXI4_ID_WIDTH-1:0]       m_id;
    protected bit [AXI4_ADDR_WIDTH-1:0]     m_addr;
    protected bit [AXI4_LEN_WIDTH-1:0]      m_len;
    protected axi4_size_e                   m_size;
    protected axi4_burst_e                  m_burst;
    protected axi4_lock_e                   m_lock;
    protected bit [3:0]                     m_cache;
    protected bit [2:0]                     m_prot;
    protected axi4_resp_e                   m_resp;
    protected bit [AXI4_STRB_WIDTH-1:0]     m_strb;
    protected bit                           m_aligned;

    //-------------------------------------------------------------------------
    // Transaction control coverage
    //-------------------------------------------------------------------------
    covergroup cg_control;
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
            bins legal[] = {[AXI4_SIZE_1BYTE:AXI4_SIZE_128BYTE]}
                           with ((1 << item) <= AXI4_STRB_WIDTH);
            bins wider_than_bus = default;
        }
        cp_len: coverpoint m_len {
            bins single    = {0};
            bins short_b   = {[1:3]};
            bins medium_b  = {[4:15]};
            bins long_b    = {[16:63]};
            bins very_long = {[64:254]};
            bins max_b     = {255};
        }
        cp_lock: coverpoint m_lock {
            bins normal      = {AXI4_LOCK_NORMAL};
            bins unsupported = {AXI4_LOCK_EXCLUSIVE};
        }
        cp_id: coverpoint m_id {
            bins zero    = {0};
            bins nonzero = default;
        }
        cp_cache: coverpoint m_cache;
        cp_prot:  coverpoint m_prot;

        cx_dir_burst: cross cp_dir, cp_burst;
        cx_dir_size:  cross cp_dir, cp_size;
        cx_dir_len:   cross cp_dir, cp_len;
    endgroup : cg_control

    //-------------------------------------------------------------------------
    // Address coverage
    //-------------------------------------------------------------------------
    covergroup cg_address;
        cp_lane: coverpoint m_addr[1:0] {
            bins lanes[] = {[0:3]};
        }
        cp_region: coverpoint m_addr[31:28] {
            bins regions[] = {[0:15]};
        }
        cp_aligned: coverpoint m_aligned {
            bins aligned   = {1'b1};
            bins unaligned = {1'b0};
        }
    endgroup : cg_address

    //-------------------------------------------------------------------------
    // Response coverage
    //-------------------------------------------------------------------------
    covergroup cg_response;
        cp_dir: coverpoint m_dir {
            bins read  = {AXI4_READ};
            bins write = {AXI4_WRITE};
        }
        cp_resp: coverpoint m_resp {
            bins okay        = {AXI4_RESP_OKAY};
            bins slverr      = {AXI4_RESP_SLVERR};
            bins unsupported = {AXI4_RESP_EXOKAY, AXI4_RESP_DECERR};
        }
        cx_dir_resp: cross cp_dir, cp_resp;
    endgroup : cg_response

    //-------------------------------------------------------------------------
    // Write strobe coverage
    //-------------------------------------------------------------------------
    covergroup cg_write_strobe;
        cp_strb: coverpoint m_strb {
            bins full    = {{AXI4_STRB_WIDTH{1'b1}}};
            bins zero    = {'0};
            bins partial = default;
        }
    endgroup : cg_write_strobe

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_control      = new();
        cg_address      = new();
        cg_response     = new();
        cg_write_strobe = new();
    endfunction : new

    //-------------------------------------------------------------------------
    // Analysis callback
    //-------------------------------------------------------------------------
    function void write(axi4_transaction t);
        m_dir     = t.dir;
        m_id      = t.id;
        m_addr    = t.addr;
        m_len     = t.len;
        m_size    = t.size;
        m_burst   = t.burst;
        m_lock    = t.lock;
        m_cache   = t.cache;
        m_prot    = t.prot;
        m_aligned = ((t.addr % (1 << int'(t.size))) == 0);

        cg_control.sample();
        cg_address.sample();

        if (t.dir == AXI4_WRITE) begin
            m_resp = t.bresp;
            cg_response.sample();
            foreach (t.strb[i]) begin
                m_strb = t.strb[i];
                cg_write_strobe.sample();
            end
        end else begin
            foreach (t.rresp[i]) begin
                m_resp = t.rresp[i];
                cg_response.sample();
            end
        end
    endfunction : write

endclass : axi4_mst_coverage