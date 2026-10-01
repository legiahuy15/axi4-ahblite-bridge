# Basic DUT testbench

Self-checking, non-UVM directed testbenches for a quick sanity check of the RTL in
[`../dut/`](../dut/). They need only a SystemVerilog simulator, with no UVM or SVA, and run
in a few seconds. Full verification is done by the UVM environment in `10_tb/` and
`11_sim/`.

## Files

| File | Content |
|---|---|
| `tb_axi_ahblite_bridge_smoke.sv` | Top-level smoke test of `axi_ahblite_bridge`. |
| `tb_ahb_mstr_rd_wait.sv` | Unit test of `ahb_mstr_if`: read restart from `AHB_RD_WAIT`. |
| `dut_files_list.f` | DUT compile list (paths relative to this directory). |
| `Makefile` | QuestaSim build and run targets. |

## Tests

### `tb_axi_ahblite_bridge_smoke`

DUT configuration: 32-bit data and address, `C_S_AXI_SUPPORTS_NARROW_BURST = 0`,
`C_DPHASE_TIMEOUT = 0`. The AHB side is a memory slave model (1024 words, one data-phase
slot) that can insert wait states or a two-cycle ERROR response at a selected address.

| Step | Scenario | Checks |
|---|---|---|
| 1 | Reset | AXI ready/valid low; AHB outputs at reset values (`HTRANS` IDLE, `HPROT` 0011); no X. |
| 2 | Single write, read-back | One NONSEQ SINGLE word transfer; memory content; read data. |
| 3 | B and R backpressure (3 cycles) | B/R payload and `VALID` held stable while `READY` is low. |
| 4 | AHB wait states (3 cycles), write and read | Exactly 3 wait cycles; AHB address/control/data stable while `HREADY` is low. |
| 5 | AHB ERROR on write and on read, reset after each | `BRESP`/`RRESP` = SLVERR; memory not updated by the errored write. |
| 6 | INCR4 write, read-back | NONSEQ + 3 × SEQ, `HBURST` INCR4, addresses, memory and read data. |

Every AXI response is also checked for ID, `RLAST` and data.

### `tb_ahb_mstr_rd_wait`

Drives the internal request interface of `ahb_mstr_if` directly. Each case is a 2-beat
read with `axi_rready` held low, so the FSM parks in `AHB_RD_WAIT` with one beat remaining.
The test then checks `HTRANS` while waiting, and `HTRANS`/`HADDR` of the restarted beat.

| Case | `HTRANS` while waiting | Restart beat |
|---|---|---|
| FIXED | IDLE | NONSEQ, same address |
| WRAP2 | IDLE | NONSEQ, wrapped address |
| INCR across 1 KB (`0x3FC` → `0x400`) | IDLE | NONSEQ |
| INCR, no crossing | BUSY | SEQ |

The test reads `dut.ahb_wr_rd_cs` and compares it with the encoded value of `AHB_RD_WAIT`
(`4'd5`). If the order of `ahb_sm_t` in `ahb_mstr_if.sv` changes, update
`AHB_RD_WAIT_STATE` in the testbench.

## Running

Requirements: QuestaSim (`vlib`, `vmap`, `vlog`, `vsim`), GNU make and bash. If the tools are
not in `PATH`, add `QUESTA_BIN=/path/to/questa/bin/` (with the trailing `/`) to any target.

```bash
cd 01_src/dut_tb_basic
make            # compile and run the smoke test
make rd-wait    # compile and run the AHB_RD_WAIT test
make regress    # run both
```

| Target | Action |
|---|---|
| `make compile` | Compile the DUT and the selected testbench into `work/`. |
| `make gui` | Open the smoke test in the QuestaSim GUI with all signals in the wave window. |
| `make view` | Open the waveform from the last console run. |
| `make clean` | Remove `work/`, `modelsim.ini`, `transcript`, logs and waveforms. |
| `make help` | List the targets. |

**Pass criterion:** the log contains `TEST PASS:`; the make target fails otherwise. A failed
check reports `$error` and the test ends with `$fatal` and the failure count. A watchdog
stops a hung test (5000 clocks for the smoke test, 200 for `rd_wait`).

**Outputs:** `smoke.log`/`smoke.wlf` and `rd_wait.log`/`rd_wait.wlf` in this directory.

## Scope

32-bit only, narrow support off, timeout disabled. Narrow transfers, WRAP and FIXED at
bridge level, the timeout, lock and the 1 KB split at bridge level are not covered here.