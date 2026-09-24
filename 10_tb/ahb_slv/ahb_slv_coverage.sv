//=============================================================================
// File        : ahb_slv_coverage.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite slave-agent protocol coverage.
//               Included inside the bridge package.
//=============================================================================

`uvm_analysis_imp_decl(_ahb_trans)

class ahb_slv_coverage extends uvm_subscriber #(ahb_transfer);

    `uvm_component_utils(ahb_slv_coverage)

    //-------------------------------------------------------------------------
    // Analysis interfaces
    //-------------------------------------------------------------------------
    uvm_analysis_imp_ahb_trans #(ahb_trans_e, ahb_slv_coverage) trans_export;

    //-------------------------------------------------------------------------
    // Sampled fields
    //-------------------------------------------------------------------------
    protected ahb_dir_e                    m_write;
    protected ahb_trans_e                  m_trans;
    protected ahb_burst_e                  m_burst;
    protected ahb_size_e                   m_size;
    protected bit [AHB_ADDR_WIDTH-1:0]     m_addr;
    protected bit [3:0]                    m_prot;
    protected bit                          m_mastlock;
    protected ahb_resp_e                   m_resp;
    protected int unsigned                 m_wait_cycles;
    protected ahb_trans_e                  m_bus_trans;

    //-------------------------------------------------------------------------
    // Completed transfer coverage
    //-------------------------------------------------------------------------
    covergroup cg_transfer;
        cp_dir: coverpoint m_write {
            bins read  = {AHB_READ};
            bins write = {AHB_WRITE};
        }
        cp_trans: coverpoint m_trans {
            bins nonseq = {AHB_TRANS_NONSEQ};
            bins seq    = {AHB_TRANS_SEQ};
        }
        cp_burst: coverpoint m_burst {
            bins single = {AHB_BURST_SINGLE};
            bins incr   = {AHB_BURST_INCR};
            bins wrap4  = {AHB_BURST_WRAP4};
            bins incr4  = {AHB_BURST_INCR4};
            bins wrap8  = {AHB_BURST_WRAP8};
            bins incr8  = {AHB_BURST_INCR8};
            bins wrap16 = {AHB_BURST_WRAP16};
            bins incr16 = {AHB_BURST_INCR16};
        }
        cp_size: coverpoint m_size {
            bins legal[] = {[AHB_SIZE_1BYTE:AHB_SIZE_128BYTE]}
                           with ((1 << item) <= (AHB_DATA_WIDTH / 8));
            bins wider_than_bus = default;
        }
        cp_resp: coverpoint m_resp {
            bins okay  = {AHB_RESP_OKAY};
            bins error = {AHB_RESP_ERROR};
        }
        cp_wait: coverpoint m_wait_cycles {
            bins zero   = {0};
            bins short  = {[1:3]};
            bins mid    = {[4:15]};
            bins long   = {[16:$]};
        }
        cp_lock: coverpoint m_mastlock {
            bins normal      = {1'b0};
            bins unsupported = {1'b1};
        }
        cp_prot: coverpoint m_prot {
            bins values[] = {[4'b0000:4'b0111]};
            // The bridge always drives HPROT[3]=0 (PG177 Table 3-1); the
            // NONCACHEABLE assertion checks it
            ignore_bins cacheable = {[4'b1000:4'b1111]};
        }
        cp_lane: coverpoint m_addr[1:0] {
            bins lanes[] = {[0:3]};
        }

        cx_dir_burst:  cross cp_dir, cp_burst;
        cx_dir_size:   cross cp_dir, cp_size;
        cx_burst_resp: cross cp_burst, cp_resp;
    endgroup : cg_transfer

    //-------------------------------------------------------------------------
    // Bus transfer-type coverage
    //-------------------------------------------------------------------------
    covergroup cg_bus_trans;
        cp_trans: coverpoint m_bus_trans {
            bins idle   = {AHB_TRANS_IDLE};
            bins busy   = {AHB_TRANS_BUSY};
            bins nonseq = {AHB_TRANS_NONSEQ};
            bins seq    = {AHB_TRANS_SEQ};
        }
    endgroup : cg_bus_trans

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_transfer  = new();
        cg_bus_trans = new();
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        trans_export = new("trans_export", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Analysis callbacks
    //-------------------------------------------------------------------------
    function void write(ahb_transfer t);
        m_write       = t.write;
        m_trans       = t.trans;
        m_burst       = t.burst;
        m_size        = t.size;
        m_addr        = t.addr;
        m_prot        = t.prot;
        m_mastlock    = t.mastlock;
        m_resp        = t.resp;
        m_wait_cycles = t.wait_cycles;
        cg_transfer.sample();
    endfunction : write

    function void write_ahb_trans(ahb_trans_e trans);
        m_bus_trans = trans;
        cg_bus_trans.sample();
    endfunction : write_ahb_trans

endclass : ahb_slv_coverage