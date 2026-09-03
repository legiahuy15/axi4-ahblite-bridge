//=============================================================================
// File        : ahb_agent_config.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Configuration object shared by the AHB-Lite master and slave
//               agents. Controls active/passive mode, coverage, master
//               back-to-back/backpressure, and slave response mode/timing.
//=============================================================================

class ahb_agent_config extends uvm_object;

    `uvm_object_utils(ahb_agent_config)

    //-------------------------------------------------------------------------
    // Agent mode
    //-------------------------------------------------------------------------
    //   UVM_ACTIVE  - driver + sequencer + monitor (drives traffic)
    //   UVM_PASSIVE - monitor only (passive observation)
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    //-------------------------------------------------------------------------
    // Feature enables
    //-------------------------------------------------------------------------
    bit has_coverage = 1;       // Enable functional coverage collection

    // Master back-to-back: overlap the next queued txn's beat-0 address phase
    // into the last data phase (no IDLE bubble)
    bit en_back_to_back = 1;

    // Master: defer that overlap into the wait state. The slot opens as IDLE
    // and becomes NONSEQ while HREADY is low (IHI0033A 3.6.1, HTRANS then
    // held). A zero-wait data phase has nothing to defer into and ends with
    // IDLE. Requires en_back_to_back
    bit en_idle_to_nonseq_in_wait = 0;

    // Master backpressure: max accepted-but-not-completed txns. 0 = unlimited
    int unsigned max_outstanding = 0;

    //-------------------------------------------------------------------------
    // Slave response mode (slave agent only)
    //-------------------------------------------------------------------------
    //   1 - internal memory model, OKAY responses, ready_delay_min/max wait
    //       states. No sequencer traffic required.
    //   0 - ahb_slave_response items from the sequencer control ready delay,
    //       HRESP and HRDATA per beat.
    bit auto_gen_resp = 1;

    //-------------------------------------------------------------------------
    // Slave driver timing - applied in auto-generate mode only
    //-------------------------------------------------------------------------
    int unsigned ready_delay_min = 0;   // Min cycles before HREADY
    int unsigned ready_delay_max = 0;   // Max cycles before HREADY

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_agent_config");
        super.new(name);
    endfunction : new

endclass : ahb_agent_config