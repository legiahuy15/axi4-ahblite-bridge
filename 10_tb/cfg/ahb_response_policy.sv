//=============================================================================
// File        : ahb_response_policy.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Response plan shared by an AXI stimulus sequence and the
//               reactive AHB-Lite slave sequence.
//               The stimulus sequence pushes one entry per expected AHB beat
//               before it sends a request; the slave sequence pops one entry
//               per observed beat. Beats beyond the plan get the defaults, so
//               a bridge that issues more beats than predicted is still
//               answered, and pending_beats() reports the beats the plan
//               expected but never saw.
//               Included inside the bridge package.
//=============================================================================

typedef struct {
    ahb_resp_e   resp;
    int unsigned ready_delay;  // OKAY wait cycles; ERROR adds its own cycle
} ahb_response_plan_t;

class ahb_response_policy extends uvm_object;

    `uvm_object_utils(ahb_response_policy)

    localparam int unsigned AHB_BYTE_LANES = AHB_DATA_WIDTH / 8;

    //-------------------------------------------------------------------------
    // Defaults for unplanned beats
    //-------------------------------------------------------------------------
    ahb_resp_e   default_resp  = AHB_RESP_OKAY;
    int unsigned default_delay = 0;

    // Read data is derived from the address so every word is distinct
    bit [AHB_DATA_WIDTH-1:0] read_seed = '0;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned beats_served;
    int unsigned error_beats_served;
    int unsigned waited_beats_served;
    int unsigned unplanned_beats;

    //-------------------------------------------------------------------------
    // Plan
    //-------------------------------------------------------------------------
    protected ahb_response_plan_t plan_queue[$];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_response_policy");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Plan interface, used by the stimulus sequence
    //-------------------------------------------------------------------------
    function void clear_plan();
        plan_queue.delete();
    endfunction : clear_plan

    function void add_beat(ahb_resp_e resp, int unsigned ready_delay);
        plan_queue.push_back('{resp, ready_delay});
    endfunction : add_beat

    function int unsigned pending_beats();
        return plan_queue.size();
    endfunction : pending_beats

    //-------------------------------------------------------------------------
    // Response interface, used by the reactive slave sequence
    //-------------------------------------------------------------------------
    function ahb_response_plan_t next_beat();
        ahb_response_plan_t plan;

        if (plan_queue.size() == 0) begin
            plan = '{default_resp, default_delay};
            unplanned_beats++;
        end else begin
            plan = plan_queue.pop_front();
        end

        beats_served++;
        if (plan.resp == AHB_RESP_ERROR)
            error_beats_served++;
        if (plan.ready_delay > 0)
            waited_beats_served++;
        return plan;
    endfunction : next_beat

    // Distinct per word address, so a dropped, repeated or reordered read beat
    // is visible to the scoreboard and to the stimulus sequence
    function bit [AHB_DATA_WIDTH-1:0] read_data(
        bit [AHB_ADDR_WIDTH-1:0] addr
    );
        bit [63:0] word_addr;
        bit [63:0] pattern;

        word_addr = addr - (addr % AHB_BYTE_LANES);
        pattern   = {word_addr[31:0], ~word_addr[31:0]};
        return pattern[AHB_DATA_WIDTH-1:0] ^ read_seed;
    endfunction : read_data

endclass : ahb_response_policy