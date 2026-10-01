//=============================================================================
// File        : ahb_slv_response_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Reactive AHB-Lite slave sequence: answers each beat from the
//               response plan with address-derived read data.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class ahb_slv_response_mapping_seq extends ahb_slv_base_seq;

    `uvm_object_utils(ahb_slv_response_mapping_seq)

    //-------------------------------------------------------------------------
    // Shared response plan
    //-------------------------------------------------------------------------
    ahb_response_policy policy;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "ahb_slv_response_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (policy == null)
            `uvm_fatal(get_type_name(), "Response policy is null")

        forever begin
            ahb_transfer        req;
            ahb_slave_response  rsp;
            ahb_response_plan_t plan;

            wait_ahb_request(req);
            plan = policy.next_beat();

            rsp             = ahb_slave_response::type_id::create("rsp");
            rsp.resp        = plan.resp;
            rsp.ready_delay = plan.ready_delay;
            rsp.rdata       = (req.write == AHB_READ) ?
                                  policy.read_data(req.addr) : '0;

            `uvm_info(get_type_name(),
                      $sformatf("[RSP][AHB] %s addr=0x%0h resp=%s waits=%0d",
                                req.write.name(), req.addr, rsp.resp.name(),
                                rsp.ready_delay),
                      UVM_HIGH)
            send_ahb_response(rsp);

            // The driver clears the pending request once the item is taken
            wait (p_sequencer.req == null);
        end
    endtask : body

endclass : ahb_slv_response_mapping_seq