//=============================================================================
// File        : ahb_master_monitor.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite master monitor. Reconstructs burst transactions from
//               the pipelined bus and broadcasts them on an analysis port.
//=============================================================================

class ahb_master_monitor extends uvm_monitor;

    `uvm_component_utils(ahb_master_monitor)

    // Virtual interface handle
    virtual ahb_if vif;

    // Completed transactions -> scoreboard / coverage
    uvm_analysis_port #(ahb_transaction) ap;

    // One accepted address phase -> coverage. A reconstructed burst carries
    // only its own beats, so IDLE never reaches ap; this port is the raw HTRANS
    // the bus presented, IDLE included
    uvm_analysis_port #(ahb_trans_e) trans_ap;

    //-------------------------------------------------------------------------
    // Burst reconstruction state
    //-------------------------------------------------------------------------

    // Burst open (NONSEQ accepted, not yet closed by NONSEQ/IDLE/reset)
    protected bit                       burst_open;

    // Beat-0 control (constant throughout a burst)
    protected bit [AHB_ADDR_WIDTH-1:0]  cur_addr;
    protected ahb_burst_e               cur_burst;
    protected ahb_size_e                cur_size;
    protected ahb_dir_e                 cur_write;
    protected bit                       cur_lock;
    protected ahb_prot_e                cur_prot;

    // Per-beat accumulators. addr_q/trans_q/busy_q grow at address-phase
    // accept; data_q/resp_q one HREADY edge later (data phase)
    protected bit [AHB_ADDR_WIDTH-1:0]  addr_q[$];
    protected ahb_trans_e               trans_q[$];
    protected int unsigned              busy_q[$];
    protected bit [AHB_DATA_WIDTH-1:0]  data_q[$];
    protected ahb_resp_e                resp_q[$];
    protected bit                       ready_q[$];   // 1 = zero-wait data phase

    // Last accepted active beat's data phase is still in flight
    protected bit                       pending_valid;
    protected int unsigned              pending_waits;   // HREADY=0 cycles seen

    // BUSY cycles since the last active beat (busy-before-beat, or trailing
    // BUSY when the burst closes out of BUSY)
    protected int unsigned              busy_cnt;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - get virtual interface from config_db
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap       = new("ap", this);
        trans_ap = new("trans_ap", this);
        if (!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase - collect loop with reset recovery (mirrors driver structure)
    //-------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        forever begin
            flush_state();
            if (!vif.rst_n) @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - master monitor active", UVM_MEDIUM)

            fork
                collect_loop();
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(),
                              "Reset asserted - discarding partial transaction", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    //-------------------------------------------------------------------------
    // Collect loop - one evaluation per HREADY=1 edge:
    //   1) complete the in-flight data phase (sample HWDATA/HRDATA + HRESP)
    //   2) accept the address phase presented this cycle
    // NONSEQ/IDLE accept closes the previous burst, whose last data phase
    // completed in step 1 on the same edge (covers back-to-back)
    //-------------------------------------------------------------------------
    task collect_loop();
        forever begin
            @(vif.monitor_cb);
            if (vif.monitor_cb.HREADY !== 1'b1) begin
                if (pending_valid) pending_waits++;
                continue;
            end

            // One transfer per accepted address phase, whatever its type. A
            // transfer held across wait states is one transfer, so this counts
            // it once - on the cycle it is accepted
            trans_ap.write(ahb_trans_e'(vif.monitor_cb.HTRANS));

            // Complete the pending beat's data phase
            if (pending_valid) begin
                data_q.push_back((cur_write == AHB_WRITE) ? vif.monitor_cb.HWDATA
                                                          : vif.monitor_cb.HRDATA);
                resp_q.push_back(ahb_resp_e'(vif.monitor_cb.HRESP));
                ready_q.push_back(pending_waits == 0);
                pending_valid = 0;

                `uvm_info(get_type_name(),
                          $sformatf("Beat[%0d] addr=0x%08h %s=0x%08h resp=%s",
                                    data_q.size()-1, addr_q[data_q.size()-1],
                                    (cur_write == AHB_WRITE) ? "wdata" : "rdata",
                                    data_q[data_q.size()-1],
                                    resp_q[resp_q.size()-1].name()), UVM_HIGH)

                // An ERROR-cancelled burst closes below, via IDLE/NONSEQ
            end

            // Decode the accepted address phase
            case (ahb_trans_e'(vif.monitor_cb.HTRANS))

                AHB_TRANS_NONSEQ: begin
                    publish_if_complete();          // close previous burst
                    cur_addr  = vif.monitor_cb.HADDR;
                    cur_burst = ahb_burst_e'(vif.monitor_cb.HBURST);
                    cur_size  = ahb_size_e'(vif.monitor_cb.HSIZE);
                    cur_write = ahb_dir_e'(vif.monitor_cb.HWRITE);
                    cur_lock  = vif.monitor_cb.HMASTLOCK;
                    cur_prot  = ahb_prot_e'(vif.monitor_cb.HPROT);
                    burst_open = 1;
                    accept_beat(AHB_TRANS_NONSEQ);
                end

                AHB_TRANS_SEQ: begin
                    if (!burst_open)
                        `uvm_error(get_type_name(), "SEQ accepted with no open burst")
                    else
                        accept_beat(AHB_TRANS_SEQ);
                end

                AHB_TRANS_BUSY: begin
                    if (!burst_open)
                        `uvm_error(get_type_name(), "BUSY accepted with no open burst")
                    else
                        busy_cnt++;
                end

                AHB_TRANS_IDLE: begin
                    publish_if_complete();          // burst (if any) is done
                end

            endcase
        end
    endtask : collect_loop

    //-------------------------------------------------------------------------
    // Accept one active beat's address phase
    //-------------------------------------------------------------------------
    function void accept_beat(ahb_trans_e t);
        addr_q.push_back(vif.monitor_cb.HADDR);
        trans_q.push_back(t);
        busy_q.push_back(busy_cnt);     // BUSY cycles seen before this beat
        busy_cnt = 0;
        pending_valid = 1;
        pending_waits = 0;
    endfunction : accept_beat

    //-------------------------------------------------------------------------
    // Close the open burst and publish it. Called at NONSEQ/IDLE accept, after
    // step 1 filled data_q. Leftover busy_cnt is the trailing BUSY run
    //-------------------------------------------------------------------------
    function void publish_if_complete();
        ahb_transaction tr;
        int n;

        if (!burst_open) begin
            busy_cnt = 0;               // stray BUSY, no open burst
            return;
        end
        n = addr_q.size();
        if (n == 0 || data_q.size() != n) begin
            `uvm_warning(get_type_name(),
                         $sformatf("Closing burst with incomplete data (%0d/%0d beats) - discarded",
                                   data_q.size(), n))
            flush_burst();
            return;
        end

        tr = ahb_transaction::type_id::create("mon_tr");
        tr.addr      = cur_addr;
        tr.burst     = cur_burst;
        tr.size      = cur_size;
        tr.write     = cur_write;
        tr.lock      = cur_lock;
        tr.prot      = cur_prot;
        tr.num_beats = n;

        tr.trans       = new[n];
        tr.wdata       = new[n];
        tr.rdata       = new[n];
        tr.resp        = new[n];
        tr.ready       = new[n];
        tr.busy_cycles = new[n];
        for (int i = 0; i < n; i++) begin
            tr.trans[i]       = trans_q[i];
            tr.resp[i]        = resp_q[i];
            tr.ready[i]       = ready_q[i];
            tr.busy_cycles[i] = busy_q[i];
            if (cur_write == AHB_WRITE) tr.wdata[i] = data_q[i];
            else                        tr.rdata[i] = data_q[i];
        end
        tr.trailing_busy_cycles = busy_cnt;

        `uvm_info(get_type_name(),
                  $sformatf("Observed [%s]: HADDR=0x%08h, HBURST=%s, HSIZE=%s, %0d beats",
                            tr.write.name(), tr.addr, tr.burst.name(),
                            tr.size.name(), n), UVM_MEDIUM)

        ap.write(tr);
        flush_burst();
    endfunction : publish_if_complete

    //-------------------------------------------------------------------------
    // Clear per-burst accumulators
    //-------------------------------------------------------------------------
    function void flush_burst();
        burst_open    = 0;
        pending_valid = 0;
        pending_waits = 0;
        busy_cnt      = 0;
        addr_q.delete();
        trans_q.delete();
        busy_q.delete();
        data_q.delete();
        resp_q.delete();
        ready_q.delete();
    endfunction : flush_burst

    //-------------------------------------------------------------------------
    // Full state flush (reset) - partial bursts are discarded, not published
    //-------------------------------------------------------------------------
    function void flush_state();
        if (burst_open)
            `uvm_info(get_type_name(),
                      $sformatf("Discarding partial burst at reset (%0d beats accepted)",
                                addr_q.size()), UVM_MEDIUM)
        flush_burst();
    endfunction : flush_state

endclass : ahb_master_monitor