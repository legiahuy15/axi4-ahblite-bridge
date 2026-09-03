//==============================================================================
// File        : ahb_scoreboard.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite scoreboard. Runs two checks:
//   1. Passthrough fidelity - master vs slave monitor streams compared in
//      program order (same bus in passthrough topology).
//   2. Data integrity - byte-addressable reference memory replays the master
//      stream; WRITE stores bytes, READ checks against the last write. Only
//      OKAY beats update/check; reads of unwritten locations are skipped.
//==============================================================================

// Separate analysis imp ports so write_master() / write_slave() are distinct
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class ahb_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(ahb_scoreboard)

    //-------------------------------------------------------------------------
    // Analysis exports (names match ahb_vip_env connect_phase)
    //-------------------------------------------------------------------------
    uvm_analysis_imp_master #(ahb_transaction, ahb_scoreboard) master_export;
    uvm_analysis_imp_slave  #(ahb_transaction, ahb_scoreboard) slave_export;

    //-------------------------------------------------------------------------
    // Passthrough-matching FIFOs (in-order master vs slave)
    //-------------------------------------------------------------------------
    ahb_transaction master_q[$];
    ahb_transaction slave_q[$];

    //-------------------------------------------------------------------------
    // Reference memory model - byte addressable, populated by WRITE beats
    //-------------------------------------------------------------------------
    localparam int unsigned BUS_BYTES = AHB_DATA_WIDTH / 8;
    bit [7:0] ref_mem [bit [AHB_ADDR_WIDTH-1:0]];

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    // Passthrough comparison
    int unsigned num_compared;
    int unsigned num_matched;
    int unsigned num_mismatched;
    // Reference memory model
    int unsigned num_wr_bytes;      // bytes written into ref memory
    int unsigned num_rd_checked;    // read bytes checked against ref memory
    int unsigned num_rd_uninit;     // read bytes with no prior write (skipped)
    int unsigned num_rd_mismatch;   // read bytes that disagreed with ref memory

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - create analysis exports
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        master_export = new("master_export", this);
        slave_export  = new("slave_export", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Analysis callbacks
    //   master stream drives BOTH checks; slave stream feeds only the compare
    //-------------------------------------------------------------------------
    function void write_master(ahb_transaction t);
        update_ref_model(t);        // data-integrity check
        master_q.push_back(t);      // passthrough compare
        try_compare();
    endfunction : write_master

    function void write_slave(ahb_transaction t);
        slave_q.push_back(t);
        try_compare();
    endfunction : write_slave

    //=========================================================================
    // Check 1 - passthrough fidelity (master vs slave)
    //=========================================================================

    //-------------------------------------------------------------------------
    // try_compare - while both FIFOs have an entry, pop and compare fronts
    //-------------------------------------------------------------------------
    function void try_compare();
        ahb_transaction m_tr;
        ahb_transaction s_tr;

        while (master_q.size() > 0 && slave_q.size() > 0) begin
            m_tr = master_q.pop_front();
            s_tr = slave_q.pop_front();
            num_compared++;

            if (m_tr.compare(s_tr)) begin
                num_matched++;
                `uvm_info(get_type_name(),
                          $sformatf("MATCH #%0d: [%s] HADDR=0x%08h %s %0d beats",
                                    num_compared, m_tr.write.name(), m_tr.addr,
                                    m_tr.burst.name(), m_tr.get_num_beats()), UVM_HIGH)
            end else begin
                num_mismatched++;
                `uvm_error(get_type_name(),
                           $sformatf("MISMATCH #%0d:\n--- MASTER ---%s\n--- SLAVE ---%s",
                                     num_compared, m_tr.convert2string(),
                                     s_tr.convert2string()))
            end
        end
    endfunction : try_compare

    //=========================================================================
    // Check 2 - reference memory model (data integrity)
    //=========================================================================

    //-------------------------------------------------------------------------
    // beat_address - address of beat i, honouring INCR increment and WRAP
    //-------------------------------------------------------------------------
    function bit [AHB_ADDR_WIDTH-1:0] beat_address(ahb_transaction t, int i);
        int unsigned bytes = 1 << t.size;               // bytes per beat
        int unsigned len   = t.get_num_beats();
        bit [AHB_ADDR_WIDTH-1:0] base;
        case (t.burst)
            AHB_BURST_WRAP4, AHB_BURST_WRAP8, AHB_BURST_WRAP16: begin
                int unsigned wrap_bytes = len * bytes;  // wrap region size
                base = t.addr - (t.addr % wrap_bytes);  // aligned region base
                return base + ((t.addr + i * bytes) % wrap_bytes);
            end
            default: begin                              // SINGLE, INCR, INCRx
                return t.addr + i * bytes;
            end
        endcase
    endfunction : beat_address

    //-------------------------------------------------------------------------
    // update_ref_model - replay one transaction against the reference memory
    //-------------------------------------------------------------------------
    function void update_ref_model(ahb_transaction t);
        int unsigned bytes;
        bit [AHB_ADDR_WIDTH-1:0] a;
        int unsigned lane;
        bit [7:0] exp_b, got_b;

        // No reset filter needed - the monitor drops bursts truncated by reset
        bytes = 1 << t.size;

        foreach (t.trans[i]) begin
            // Only OKAY beats carry committed data
            if (i < t.resp.size() && t.resp[i] == AHB_RESP_ERROR) continue;

            a    = beat_address(t, i);
            lane = a % BUS_BYTES;                        // byte lane on the bus

            for (int k = 0; k < bytes; k++) begin
                if (t.write == AHB_WRITE) begin
                    ref_mem[a + k] = t.wdata[i][(lane + k)*8 +: 8];
                    num_wr_bytes++;
                end else begin
                    // READ: check against last written value (if any)
                    if (!ref_mem.exists(a + k)) begin
                        num_rd_uninit++;
                        continue;
                    end
                    exp_b = ref_mem[a + k];
                    got_b = t.rdata[i][(lane + k)*8 +: 8];
                    num_rd_checked++;
                    if (got_b !== exp_b) begin
                        num_rd_mismatch++;
                        `uvm_error(get_type_name(),
                                   $sformatf("REF-MEM read mismatch @0x%08h: exp=0x%02h got=0x%02h (beat %0d, burst %s)",
                                             a + k, exp_b, got_b, i, t.burst.name()))
                    end
                end
            end
        end
    endfunction : update_ref_model

    //=========================================================================
    // End-of-test reporting
    //=========================================================================

    //-------------------------------------------------------------------------
    // Check phase - flag any transactions left unmatched
    //-------------------------------------------------------------------------
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (master_q.size() != 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d master transaction(s) left unmatched at end of test",
                                 master_q.size()))
        if (slave_q.size() != 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d slave transaction(s) left unmatched at end of test",
                                 slave_q.size()))
    endfunction : check_phase

    //-------------------------------------------------------------------------
    // Report phase - final tally for both checks
    //-------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(),
                  $sformatf("Passthrough : compared=%0d matched=%0d mismatched=%0d",
                            num_compared, num_matched, num_mismatched),
                  (num_mismatched == 0) ? UVM_LOW : UVM_NONE)
        `uvm_info(get_type_name(),
                  $sformatf("Ref-memory  : wr_bytes=%0d rd_checked=%0d rd_uninit=%0d rd_mismatch=%0d",
                            num_wr_bytes, num_rd_checked, num_rd_uninit, num_rd_mismatch),
                  (num_rd_mismatch == 0) ? UVM_LOW : UVM_NONE)
    endfunction : report_phase

endclass : ahb_scoreboard