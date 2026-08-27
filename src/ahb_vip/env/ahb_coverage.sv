//==============================================================================
// File        : ahb_coverage.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite functional coverage collector. Subscribes to both of
//               a monitor's analysis ports:
//                 ap       -> one completed ahb_transaction per burst, sampled
//                             into ahb_cg (direction, burst, size, response)
//                 trans_ap -> one HTRANS per accepted address phase, sampled
//                             into ahb_trans_cg. A reconstructed burst carries
//                             no IDLE, so the transfer-type coverage has to
//                             come off the raw bus stream
//               One instance per agent; the instance name tags the report.
//==============================================================================

// Second stream alongside the uvm_subscriber write() that takes ahb_transaction
`uvm_analysis_imp_decl(_trans)

class ahb_coverage extends uvm_subscriber #(ahb_transaction);

    `uvm_component_utils(ahb_coverage)

    //-------------------------------------------------------------------------
    // Transfer-type stream from the monitor (name matches ahb_vip_env
    // connect_phase). analysis_export, for the burst stream, comes from
    // uvm_subscriber
    //-------------------------------------------------------------------------
    uvm_analysis_imp_trans #(ahb_trans_e, ahb_coverage) trans_export;

    //-------------------------------------------------------------------------
    // Sampled transaction handle (covergroup reads from this)
    //-------------------------------------------------------------------------
    ahb_transaction tr;

    //-------------------------------------------------------------------------
    // Last transfer type accepted on the bus (ahb_trans_cg reads from this)
    //-------------------------------------------------------------------------
    ahb_trans_e bus_trans;

    //-------------------------------------------------------------------------
    // Per-transaction derived scalars (populated in write() before sampling)
    //-------------------------------------------------------------------------
    bit          has_error;    // any beat returned ERROR
    bit          has_busy;     // any BUSY cycle inserted mid-burst
    bit          has_wait;     // any beat driven with HREADY low (wait state)
    int unsigned beats;        // number of beats in the burst

    //-------------------------------------------------------------------------
    // Functional coverage
    //-------------------------------------------------------------------------
    covergroup ahb_cg;
        option.per_instance = 1;

        // Transfer direction - HWRITE
        cp_dir : coverpoint tr.write {
            bins read  = {AHB_READ};
            bins write = {AHB_WRITE};
        }

        // Burst type - HBURST
        cp_burst : coverpoint tr.burst {
            bins single = {AHB_BURST_SINGLE};
            bins incr   = {AHB_BURST_INCR};
            bins wrap4  = {AHB_BURST_WRAP4};
            bins incr4  = {AHB_BURST_INCR4};
            bins wrap8  = {AHB_BURST_WRAP8};
            bins incr8  = {AHB_BURST_INCR8};
            bins wrap16 = {AHB_BURST_WRAP16};
            bins incr16 = {AHB_BURST_INCR16};
        }

        // Transfer size - HSIZE (only sizes legal for the bus width)
        cp_size : coverpoint tr.size {
            bins byte_8   = {AHB_SIZE_8B};
            bins half_16  = {AHB_SIZE_16B};
            bins word_32  = {AHB_SIZE_32B};
            // Illegal on a 32-bit bus, excluded by c_size_max
            ignore_bins wide = {AHB_SIZE_64B, AHB_SIZE_128B, AHB_SIZE_256B,
                                AHB_SIZE_512B, AHB_SIZE_1024B};
        }

        // Burst length (number of beats)
        cp_beats : coverpoint beats {
            bins single      = {1};
            bins len4        = {4};
            bins len8        = {8};
            bins len16       = {16};
            bins incr_other  = {[2:3], [5:7], [9:15], [17:256]};
        }

        // Slave response
        cp_resp : coverpoint has_error {
            bins okay  = {0};
            bins error = {1};
        }

        // BUSY insertion (master stalling mid-burst)
        cp_busy : coverpoint has_busy {
            bins none = {0};
            bins busy = {1};
        }

        // HREADY wait states (slave back-pressure)
        cp_wait : coverpoint has_wait {
            bins none = {0};
            bins wait_states = {1};
        }

        // Interesting crosses
        x_dir_burst  : cross cp_dir, cp_burst;
        x_dir_size   : cross cp_dir, cp_size;
        x_burst_resp : cross cp_burst, cp_resp;
    endgroup : ahb_cg

    //-------------------------------------------------------------------------
    // Transfer-type coverage - HTRANS, one sample per accepted address phase.
    // Separate from ahb_cg because its sampling event is a bus cycle, not a
    // completed burst: sampling it per burst would never see an IDLE and would
    // count the same transfer type once per burst instead of once per transfer
    //-------------------------------------------------------------------------
    covergroup ahb_trans_cg;
        option.per_instance = 1;

        // Transfer type - HTRANS
        cp_trans : coverpoint bus_trans {
            bins idle   = {AHB_TRANS_IDLE};
            bins busy   = {AHB_TRANS_BUSY};
            bins nonseq = {AHB_TRANS_NONSEQ};
            bins seq    = {AHB_TRANS_SEQ};
        }
    endgroup : ahb_trans_cg

    //-------------------------------------------------------------------------
    // Constructor - covergroups must be built here
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
        ahb_cg       = new();
        ahb_trans_cg = new();
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - create the transfer-type export
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        trans_export = new("trans_export", this);
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // write - analysis callback; derive scalars then sample
    //-------------------------------------------------------------------------
    function void write(ahb_transaction t);
        tr = t;

        beats     = t.get_num_beats();
        has_error = 0;
        has_busy  = 0;
        has_wait  = 0;

        foreach (t.resp[i])
            if (t.resp[i] == AHB_RESP_ERROR) has_error = 1;
        foreach (t.busy_cycles[i])
            if (t.busy_cycles[i] > 0) has_busy = 1;
        if (t.trailing_busy_cycles > 0) has_busy = 1;
        foreach (t.ready[i])
            if (t.ready[i] == 1'b0) has_wait = 1;

        ahb_cg.sample();

        `uvm_info(get_type_name(),
                  $sformatf("Sampled [%s]: burst=%s size=%s beats=%0d error=%0b",
                            t.write.name(), t.burst.name(), t.size.name(),
                            beats, has_error), UVM_HIGH)
    endfunction : write

    //-------------------------------------------------------------------------
    // write_trans - transfer-type callback; one accepted address phase
    //-------------------------------------------------------------------------
    function void write_trans(ahb_trans_e t);
        bus_trans = t;
        ahb_trans_cg.sample();
    endfunction : write_trans

    //-------------------------------------------------------------------------
    // report_phase - print achieved coverage for this instance
    //-------------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        // Reported per covergroup, not averaged: the merged figure is the
        // UCDB's to compute, and it weights by bins rather than by group
        `uvm_info(get_type_name(),
                  $sformatf("[%s] functional coverage: ahb_cg = %.2f%%, ahb_trans_cg = %.2f%%",
                            get_name(), ahb_cg.get_coverage(),
                            ahb_trans_cg.get_coverage()), UVM_LOW)
    endfunction : report_phase

endclass : ahb_coverage