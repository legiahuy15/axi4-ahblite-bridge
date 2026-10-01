//=============================================================================
// File        : axi4_mst_mutation_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Scoreboard fault injection. One field is corrupted per case
//               (never in the first beat) and a mismatch must be reported.
//               ID and assertions are not covered.
//               Covers BRG_ENV_006.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class axi4_mst_mutation_seq extends axi4_mst_base_seq;

    `uvm_object_utils(axi4_mst_mutation_seq)

    localparam int unsigned FULL_SIZE = $clog2(AXI4_STRB_WIDTH);
    localparam int unsigned BUS_BYTES = AXI4_STRB_WIDTH;

    // Long enough that a fault can go into a beat other than the first
    localparam int unsigned BURST_LEN = 3;

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'hC000;
    int unsigned              case_stride = 'h40;

    //-------------------------------------------------------------------------
    // Shared handles
    //-------------------------------------------------------------------------
    scoreboard scb;

    //-------------------------------------------------------------------------
    // Statistics
    //-------------------------------------------------------------------------
    int unsigned cases_run;
    int unsigned faults_missed;
    int unsigned ahb_faults;
    int unsigned axi_faults;
    int unsigned timeout_faults;

    //-------------------------------------------------------------------------
    // Internal types
    //-------------------------------------------------------------------------
    // side: 0 an observed AHB beat, 1 an observed AXI completion,
    //       2 a declared timeout that will not happen
    typedef struct {
        int unsigned side;
        mutation_e   kind;
        axi4_dir_e   dir;
        string       label;
    } mutation_case_t;

    //-------------------------------------------------------------------------
    // Internal state
    //-------------------------------------------------------------------------
    protected mutation_case_t case_list[$];

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "axi4_mst_mutation_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        if (scb == null)
            `uvm_fatal(get_type_name(),
                       "The scoreboard handle is what this sequence tests")
        if (!cfg.return_responses)
            `uvm_fatal(get_type_name(),
                       "Each case waits for its own completion")

        wait_reset_release();
        build_cases();

        `uvm_info(get_type_name(),
                  $sformatf("Mutation: %0d faults to inject", case_list.size()),
                  UVM_LOW)

        // From here a failed comparison is a result, not a fault of the DUT
        scb.set_mutation_mode(1'b1);
        foreach (case_list[i])
            run_case(i, case_list[i]);
        scb.set_mutation_mode(1'b0);

        `uvm_info(get_type_name(),
                  $sformatf({"Mutation summary: run=%0d missed=%0d ",
                             "ahb=%0d axi=%0d timeout=%0d ",
                             "scoreboard armed=%0d caught=%0d"},
                            cases_run, faults_missed, ahb_faults, axi_faults,
                            timeout_faults, scb.faults_armed(),
                            scb.faults_caught()),
                  UVM_LOW)
    endtask : body

    //-------------------------------------------------------------------------
    // Case list
    //-------------------------------------------------------------------------
    protected function void add_case(
        int unsigned side,
        mutation_e   kind,
        axi4_dir_e   dir,
        string       label
    );
        mutation_case_t c;

        c.side  = side;
        c.kind  = kind;
        c.dir   = dir;
        c.label = label;
        case_list.push_back(c);
    endfunction : add_case

    protected function void build_cases();
        // Every field ahb_request_matches claims to compare
        add_case(0, MUT_AHB_ADDR,     AXI4_WRITE, "AHB_ADDR");
        add_case(0, MUT_AHB_DIR,      AXI4_WRITE, "AHB_DIR");
        add_case(0, MUT_AHB_TRANS,    AXI4_WRITE, "AHB_TRANS");
        add_case(0, MUT_AHB_BURST,    AXI4_WRITE, "AHB_BURST");
        add_case(0, MUT_AHB_SIZE,     AXI4_WRITE, "AHB_SIZE");
        add_case(0, MUT_AHB_PROT,     AXI4_WRITE, "AHB_PROT");
        add_case(0, MUT_AHB_MASTLOCK, AXI4_WRITE, "AHB_MASTLOCK");
        add_case(0, MUT_AHB_WDATA,    AXI4_WRITE, "AHB_WDATA");

        // and the fields of axi_transaction_matches that a corrupted
        // completion can reach without breaking the pairing
        add_case(1, MUT_AXI_ADDR, AXI4_WRITE, "AXI_ADDR");
        add_case(1, MUT_AXI_LEN,  AXI4_WRITE, "AXI_LEN");
        add_case(1, MUT_AXI_STRB, AXI4_WRITE, "AXI_STRB");
        add_case(1, MUT_AXI_RESP, AXI4_WRITE, "AXI_BRESP");
        add_case(1, MUT_AXI_RESP, AXI4_READ,  "AXI_RRESP");
        add_case(1, MUT_AXI_DATA, AXI4_READ,  "AXI_RDATA");

        // Declared timeout that does not happen must be reported
        add_case(2, MUT_NONE, AXI4_WRITE, "TIMEOUT_NOT_TAKEN");
        add_case(2, MUT_NONE, AXI4_READ,  "TIMEOUT_NOT_TAKEN_RD");
    endfunction : build_cases

    //-------------------------------------------------------------------------
    // One case
    //-------------------------------------------------------------------------
    protected task run_case(int unsigned index, mutation_case_t c);
        bit [AXI4_ADDR_WIDTH-1:0] addr;
        axi4_transaction          req;
        axi4_transaction          rsp;
        int unsigned              caught_before;

        addr = base_addr + (index * case_stride);
        req  = create_request(index, c, addr);

        caught_before = scb.faults_caught();

        case (c.side)
            0: scb.inject_ahb_mutation(c.kind, 1);
            1: scb.inject_axi_mutation(c.kind);
            default: scb.expect_timeout(c.dir, req.id);
        endcase

        send_axi_request_wait(req, rsp);
        cases_run++;
        count_side(c);

        // Anything still armed never reached a comparison at all
        if (scb.injection_pending()) begin
            faults_missed++;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: the fault was never applied, so the ",
                                  "case says nothing; no observed transfer ",
                                  "reached the comparison"},
                                 c.label))
            scb.clear_injection();
        end else if (scb.faults_caught() == caught_before) begin
            faults_missed++;
            `uvm_error(get_type_name(),
                       $sformatf({"%s: the fault went in and the comparison ",
                                  "did not report it, so that field is not ",
                                  "being checked and every test in the ",
                                  "regression is blind to it"},
                                 c.label))
        end else begin
            `uvm_info(get_type_name(),
                      $sformatf("[%0d] %s: injected and caught",
                                index, c.label),
                      UVM_MEDIUM)
        end
    endtask : run_case

    protected function void count_side(mutation_case_t c);
        case (c.side)
            0:       ahb_faults++;
            1:       axi_faults++;
            default: timeout_faults++;
        endcase
    endfunction : count_side

    //-------------------------------------------------------------------------
    // Request creation
    //-------------------------------------------------------------------------
    // Same request shape for every case
    protected function axi4_transaction create_request(
        int unsigned              index,
        mutation_case_t           c,
        bit [AXI4_ADDR_WIDTH-1:0] addr
    );
        axi4_transaction req;
        axi4_dir_e       req_dir;
        int unsigned     req_len;

        req_dir = c.dir;
        req_len = BURST_LEN;

        req = axi4_transaction::type_id::create(
                  $sformatf("mutation_%0d", index));
        if (!req.randomize() with {
                dir      == local::req_dir;
                addr     == local::addr;
                len      == local::req_len;
                size     == axi4_size_e'(FULL_SIZE);
                burst    == AXI4_BURST_INCR;
                lock     == AXI4_LOCK_NORMAL;
                cache    == 0;
                prot     == 0;
                wr_order == AXI4_WR_PARALLEL;
            })
            `uvm_fatal(get_type_name(),
                       $sformatf("%s: randomization failed at 0x%0h",
                                 c.label, addr))

        if (req_dir == AXI4_WRITE) begin
            foreach (req.data[beat]) begin
                for (int unsigned lane = 0; lane < BUS_BYTES; lane++)
                    req.data[beat][8 * lane +: 8] =
                        8'(8'h30 + (index * 7) + (beat * 3) + lane);
                req.strb[beat] = '1;
            end
        end
        return req;
    endfunction : create_request

endclass : axi4_mst_mutation_seq
