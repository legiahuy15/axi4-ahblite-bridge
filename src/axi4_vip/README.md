# AXI4 UVM Verification IP

A parameterized, protocol-compliant AMBA AXI4 Verification IP written in SystemVerilog/UVM. The environment is self-contained: an active Master agent drives transactions directly into an active Slave agent through a shared `axi4_if` interface, with no external DUT required. It targets protocol-level verification, IP bring-up, and reuse as a reference environment for AXI4-based designs.

Conformance target: ARM AMBA AXI4 specification (IHI0022E).

---

## Architecture

The Master agent generates transactions via UVM sequences; the Slave agent responds using an internal memory model and configurable response behavior. Two monitors observe both sides of the interface. The scoreboard maintains a reference memory model and checks read-after-write data integrity, out-of-order matching, and strobe routing. A standalone SVA module checks protocol legality directly on the interface signals. A functional coverage collector samples transaction attributes and channel back-pressure.

![AXI4 VIP Architecture](doc/axi4_vip.png)

### Components

| Component | Responsibility |
|-----------|----------------|
| `axi4_if` | All five AXI4 channels with clocking blocks (`master_cb`, `slave_cb`, `monitor_cb`) and modports to prevent sampling/driving races. |
| `axi4_master_agent` | Active/passive agent: sequencer, clocking-block-driven driver, monitor. |
| `axi4_slave_agent` | Active/passive responder agent with memory model and configurable response generation (OKAY, EXOKAY, SLVERR, DECERR) and ready-handshake shaping. |
| `axi4_scoreboard` | Reference memory model, in-flight transaction tracking, out-of-order matching, read-after-write and strobe integrity checks. |
| `axi4_coverage` | Functional coverage of burst type/length/size, address alignment, response codes, and channel back-pressure. |
| `axi4_sva` | Assertion suite for handshake stability, payload stability, ordering rules, and reserved/illegal configurations. |

---

## Protocol Support

- **Configurable widths** - independent `AXI4_ADDR_WIDTH`, `AXI4_DATA_WIDTH`, `AXI4_ID_WIDTH` parameters (default 32/32/4).
- **Burst types** - FIXED, INCR, WRAP.
- **Burst length** - up to 256 beats (INCR), per AXI4.
- **Out-of-order** - ID-based tracking and matching of read/write responses.
- **Outstanding transactions** - multi-threaded outstanding reads and writes.
- **Read data interleaving** - supported by AXI4 for read transactions with different IDs, but not implemented by this VIP.
- **Exclusive access** - EXCLUSIVE/NORMAL locking with reservation tracking and EXOKAY/OKAY resolution.
- **Write strobes** - per-byte-lane `WSTRB` routing verification.
- **Write-channel ordering** - configurable AW/W interleaving (parallel, AW-first, W-first).
- **Assertions** - handshake and payload stability, ordering, and illegal/reserved-value checks.

This repository does not support read data interleaving: once it starts returning a read burst, it completes that burst through `RLAST` before returning data for another read transaction. This is a limitation of this VIP, not of the AXI4 protocol itself.

---

## Configuration

### Parameters (`src/cfg/axi4_types.sv`)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `AXI4_ADDR_WIDTH` | 32 | Address bus width |
| `AXI4_DATA_WIDTH` | 32 | Data bus width |
| `AXI4_STRB_WIDTH` | `DATA_WIDTH/8` | Write strobe width |
| `AXI4_ID_WIDTH` | 4 | Transaction ID width |
| `AXI4_LEN_WIDTH` | 8 | Burst length field width |

### Enumerations (`src/cfg/axi4_types.sv`)

- `axi4_burst_type_e` - `AXI4_BURST_FIXED` / `INCR` / `WRAP`
- `axi4_resp_e` - `AXI4_RESP_OKAY` / `EXOKAY` / `SLVERR` / `DECERR`
- `axi4_size_e` - `AXI4_SIZE_1B` … `AXI4_SIZE_128B` (bytes per beat = `2^SIZE`)
- `axi4_lock_e` - `AXI4_LOCK_NORMAL` / `EXCLUSIVE`
- `axi4_wr_order_e` - `AXI4_WR_PARALLEL` / `AW_BEFORE_W` / `W_BEFORE_AW`

---

## Repository Layout

```
src/
  axi4_if.sv            AXI4 interface, clocking blocks, modports
  axi4_pkg.sv           VIP package (types, config, agents, env)
  axi4_test_pkg.sv      Test package
  tb_top.sv             Top-level testbench
  cfg/                  Types, transaction item, agent config
  mst/                  Master agent, driver, monitor, sequencer
  slv/                  Slave agent, driver, monitor, sequencer
  seq/                  Sequence library
  env/                  Environment, scoreboard, coverage, env config
  sva/                  Protocol assertions
  test/                 Test library
sim/                    QuestaSim Makefile and generated reports
doc/                    Architecture diagram
```

---

## Test Library

All tests extend `axi4_base_test`. The regression list is defined in `sim/Makefile` (`TEST_LIST`).

| Test | Purpose |
|------|---------|
| `axi4_sanity_test` | Basic write-then-read-back |
| `axi4_random_test` | Randomized mixed traffic |
| `axi4_all_burst_type_test` | FIXED, INCR, WRAP coverage |
| `axi4_burst_sweep_test` | Sweep of burst configurations and sizes |
| `axi4_narrow_burst_test` | Narrow (sub-bus-width) transfers |
| `axi4_unaligned_test` | Unaligned address handling |
| `axi4_strobe_test` | Full/sparse/partial write-strobe patterns |
| `axi4_outstanding_test` | Multi-threaded outstanding transactions |
| `axi4_out_of_order_test` | Out-of-order response return |
| `axi4_back_to_back_test` | Back-to-back pipelined transactions |
| `axi4_backpressure_test` | Handshake back-pressure / latency stress |
| `axi4_exclusive_test` | Exclusive locks and EXOKAY resolution |
| `axi4_exclusive_fail_test` | Exclusive-reservation invalidation corners |
| `axi4_illegal_exclusive_test` | Negative test for illegal exclusive access |
| `axi4_cache_prot_test` | Cache/protection attribute sweep |
| `axi4_error_response_test` | SLVERR/DECERR response handling |
| `axi4_wr_order_demo_test` | AW/W channel ordering modes |
| `axi4_reset_mid_burst_test` | Mid-burst reset recovery |
| `axi4_data_integrity_test` | Write-then-read-back with known data |
| `axi4_addr_integrity_test` | Known-answer address/data integrity |

---

## Running Simulations

The `sim/` directory provides a Makefile targeting Siemens QuestaSim/ModelSim. It requires a QuestaSim installation with a compiled UVM library.

```bash
cd sim/

make help                                    # list targets and variables
make run                                     # default test (axi4_sanity_test), random seed
make run TESTNAME=axi4_random_test SEED=42   # specific test and seed
make gui TESTNAME=axi4_outstanding_test      # GUI with AXI4 waveform view
make -j8 regress NUM_RUNS=5                  # parallel regression, 5 runs per test
make cov_report                              # merge .ucdb and emit HTML coverage
make clean                                   # remove build, wave, and coverage artifacts
```

Overridable variables: `TESTNAME`, `SEED`, `UVM_VERBOSITY`, `NUM_RUNS`, `USE_COVERAGE`, `TEST_LIST`.

The merged HTML coverage report is written to `sim/report/cov_html/index.html`.

---

## AI Disclaimer

This codebase was developed and refactored with the assistance of AI tools, used for boilerplate scaffolding and testbench optimization. All logic, test suites, and simulation configurations have been reviewed and validated against the AMBA AXI4 specification.