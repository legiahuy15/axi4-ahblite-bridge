# PG177 AXI4 to AHB-Lite Bridge v3.0 — verification review

This review records the externally visible behavior that the UVM environment must verify
for the AXI4 to AHB-Lite Bridge v3.0 described by **PG177, November 18, 2015**. It is a
verification checklist, not a replacement for the licensed product guide or the ARM
protocol specifications.

**Last re-reviewed: 2026-09-17**, against the PG177 text in `00_doc/`, the translated RTL in
`01_src/dut/`, the environment in `10_tb/`, and the third regression (45/45 runs passing:
40 on the default build, 5 on the `C_S_AXI_SUPPORTS_NARROW_BURST=1` build). Items marked
**RTL observation** describe the translated RTL, not PG177; they are not requirements
until confirmed against the reference VHDL (`00_doc/axi_ahblite_bridge_v3_0_vh_rfs.vhd`).

## 1. Confirmed product profile

| Area | PG177 v3.0 requirement |
|---|---|
| Topology | AXI4 slave to AHB-Lite master. |
| Clocking | Synchronous design; both interfaces use `s_axi_aclk`. |
| Reset | `s_axi_aresetn` is an active-low synchronous reset and also resets the AHB-Lite interface. |
| Address width | Configurable from 32 to 64 bits. The AXI address is not remapped before it reaches AHB-Lite, except for alignment of an unaligned AXI read. |
| Data width | 32 or 64 bits, with equal width on AXI and AHB-Lite. |
| Endianness | Little-endian on both interfaces. |
| Burst support | AXI INCR 1–256, WRAP 2/4/8/16, FIXED 1–16. AHB-Lite SINGLE, INCR4/8/16, undefined INCR, WRAP4/8/16. |
| Read/write arbitration | When a read and a write are requested simultaneously (`AWVALID`/`WVALID` and `ARVALID` high), the read is requested on AHB-Lite first. |
| AXI responses | The bridge generates only OKAY and SLVERR. AHB ERROR and bridge timeout map to AXI SLVERR; EXOKAY and DECERR are never generated. |
| Timeout | Disabled at zero (the bridge then waits indefinitely); supported non-zero settings are 16, 32, 64, 128, and 256 AXI clocks. Timeout completes the AXI transaction with SLVERR and sends IDLE on AHB-Lite. PG177 recommends that the AXI master resets the bridge after SLVERR. |
| Registers | No register space is implemented. |

The guide reports best-case read latency of four clocks from `ARVALID` to `RVALID`, and
best-case write latency of three clocks from `AWVALID` to valid AHB write data. These are
performance targets that should be measured separately from protocol correctness; stalls
and arbitration can increase latency. Latency is not measured by the current environment.

**RTL observation — address alignment:** with narrow support disabled, the RTL aligns every
`HADDR` (read and write) to the full bus width; with narrow support enabled it aligns to
`AxSIZE` (`ahb_mstr_if.sv`, address generation). PG177 only mentions read alignment, so the
expected behavior for an unaligned full-width **write** is an open question.

**RTL observation — beat spacing:** the RTL inserts one non-transfer cycle between AHB beats
(BUSY inside INCR/WRAP bursts; IDLE for FIXED, WRAP2 and 1 KB split segments). Regression
logs show every AHB beat taking two clocks even with `HREADY` always high. The AHB slave
model and assertions must therefore accept BUSY; this is legal AHB-Lite behavior.

## 2. Transaction translation oracle

The bridge predictor must implement the following mapping independently of the RTL
(PG177 Table 3-2):

| Accepted AXI request | Expected AHB-Lite request |
|---|---|
| INCR, 1 beat | SINGLE. |
| INCR, 4/8/16 beats, no 1-KB crossing | INCR4/INCR8/INCR16 respectively. |
| INCR, 2–256 beats other than 4/8/16 | Undefined-length INCR. |
| INCR crossing a 1-KB boundary (any length, including 4/8/16) | Two undefined-length INCR bursts; the second begins with NONSEQ after the boundary. |
| WRAP, 4/8/16 beats | WRAP4/WRAP8/WRAP16 respectively. |
| WRAP, 2 beats | Two SINGLE transfers. |
| FIXED, 1–16 beats | One SINGLE transfer per AXI beat, all at the same address. |

The scoreboard compares a predicted **stream of AHB beats** (address, direction, `HTRANS`,
`HBURST`, `HSIZE`, `HPROT`, `HMASTLOCK`, write data) against completed AHB transfers, not one
AXI transaction against one AHB transaction. Wait-state cycles and BUSY/IDLE cycles are not
beats.

**Open question:** PG177 describes the 1-KB split as *two* bursts. A 64-bit, 256-beat INCR
(2048 bytes) can cross two 1-KB boundaries; PG177 does not describe that case. The
predictor currently restarts with NONSEQ at every boundary crossed.

## 3. Narrow, alignment, data, and protection rules

### 3.1 Narrow transfers

Narrow support is a generation parameter; the core must be generated with it enabled to
support narrow transfers:

- On a 32-bit interface, supported narrow sizes are 8 and 16 bits.
- On a 64-bit interface, supported narrow sizes are 8, 16, and 32 bits.
- For a single AXI write (`AWLEN == 0`), the bridge derives `HSIZE` from `WSTRB`.
- For an AXI burst, it passes `AWSIZE` or `ARSIZE` to `HSIZE`.
- Sparse and unaligned narrow transfers are unsupported.

The verification plan must distinguish legal narrow accesses from negative protocol/input
tests. Sparse `WSTRB` is not a supported feature to be treated as ordinary legal traffic.
With narrow support disabled, narrow traffic is outside the supported profile: the RTL
aligns `HADDR` to the full bus width, so narrow accesses at non-zero byte lanes do not map
to the requested address.

### 3.2 Address and data

- Both interfaces are little-endian.
- AXI write data passes to AHB write data without width conversion.
- AHB read data passes to AXI read data without width conversion.
- An unaligned AXI read address is aligned on the AHB-Lite side because AHB-Lite has no
  unaligned-address concept.

### 3.3 `AxPROT`/`AxCACHE` to `HPROT`

The predictor must calculate the four AHB protection bits as follows (PG177 Table 3-1):

- `HPROT[3] = 0`: always non-cacheable.
- `HPROT[2] = AxCACHE[0] & ~AxCACHE[2] & ~AxCACHE[3]`: bufferable mapping.
- `HPROT[1] = AxPROT[0]`: privileged versus user.
- `HPROT[0] = ~AxPROT[2]`: data versus instruction.
- Reset/default is `4'b0011` (non-cacheable, non-bufferable, privileged data access).

### 3.4 Error and timeout completion

PG177 defines the response mapping (AHB ERROR or timeout → SLVERR) but **does not define**
whether the remaining beats of a burst are still transferred after an AHB ERROR.

**RTL observation:** the RTL continues the remaining AHB beats after ERROR. A write burst
returns SLVERR on `BRESP` if any beat received ERROR (sticky until the write completes);
a read burst reports `RRESP` per beat. A timeout forces the remaining beats to complete with
SLVERR. The scoreboard currently models the same continue-and-report behavior; this oracle
must be confirmed against the reference VHDL before error tests are signed off.

## 4. Explicitly unsupported features

The legal stimulus profile must exclude, or deliberately classify as negative tests:

- Data widths greater than 64 bits.
- Locked, barrier, TrustZone, and exclusive operations.
- Out-of-order read completion and out-of-order write completion.
- Unaligned/sparse burst transfers (holes in write strobes).
- AXI EXOKAY and DECERR responses.
- Low-power state and secure accesses.
- Cacheable AHB-Lite access.

In the environment, the legal profile is enforced by `axi4_transaction` constraints
(normal lock, legal WRAP/FIXED lengths, no 4-KB crossing) and by the bridge-profile
assertions in `axi4_sva`/`ahb_sva` (`LOCK_UNSUPPORTED`, `ARLOCK_UNSUPPORTED`,
`BRESP_SUPPORTED`, `RRESP_SUPPORTED`, `NO_LOCK`, `NONCACHEABLE`).

### 4.1 Lock policy (decided 2026-09-17)

Locked/exclusive access is unsupported, but an AXI master may still issue `AxLOCK = 1`
(for example exclusive-access software). The reference VHDL registers `AxLOCK` and drives
`HMASTLOCK` from it (`AXI_LOCK_REG`, `AHB_LOCK_REG`), and the translated RTL matches. The
decision is to **keep the reference behavior and leave the RTL unchanged**. The expected
behavior for `AxLOCK = 1` is:

- The request completes like a normal request, with correct read/write data.
- The response is OKAY or SLVERR, never EXOKAY. Per the AXI specification, OKAY to an
  exclusive access tells the master that exclusive access is not supported.
- `HMASTLOCK` is 1 on every AHB transfer of that request and returns to 0 on the transfers
  of the next normal request.

**RTL observation:** the lock register is updated only when a new request is accepted, so
`HMASTLOCK` stays high while the bus is IDLE after a locked request until the next request.
This is harmless for a single-master AHB-Lite bus but can keep a multi-master interconnect
locked; it is recorded as a reference-design characteristic, not fixed.

Verification: legal-profile tests keep `LOCK_UNSUPPORTED`, `ARLOCK_UNSUPPORTED` and
`NO_LOCK` active. `bridge_unsupported_feature_test` triggers the `bridge_allow_lock` event,
which makes `bridge_tb_top` turn those three assertions off with `$assertoff`, then runs
interleaved locked and normal reads/writes. The predictor expects `HMASTLOCK = AxLOCK` per
beat and the scoreboard compares it; the sequence checks responses and read-back data.
Transaction log lines print `lock=` (AXI) and `mastlock=` (AHB) so the lock values are
visible at `UVM_HIGH`. The `C_LOCKED_IDLE` cover property in `ahb_sva` records the
held-lock IDLE characteristic and prints its first occurrence to the log.

**Result (third regression, 5 seeds):** every run passes with `run=30 failed=0` and 0
scoreboard mismatches (95 AHB beats, 30 AXI transactions). The AXI monitor shows the
intended lock order on all six burst types; the observed `HMASTLOCK` stream matches the
predicted stream on all 95 beats (57 locked beats = 3 locked transactions x 19 beats), with
no EXOKAY. `C_LOCKED_IDLE` fires at 155 ns, right after the first locked write completes.
None of the 40 legal-profile runs shows `lock=1`, `mastlock=1` or `C_LOCKED_IDLE`.

## 5. RTL traceability and audit findings

The SystemVerilog DUT visibly contains implementations corresponding to important PG177
requirements:

- The top level has an AXI slave port set and an AHB-Lite master port set.
- The AHB controller selects SINGLE, undefined INCR, INCR4/8/16, and WRAP4/8/16 from
  `axi_burst` and `axi_length` and detects 1-KB crossing.
- WRAP2 is tracked separately and fixed transfers suppress address incrementing.
- `HPROT` implements the PG177 mapping above, with reset value `4'b0011`.
- A timeout forces `HTRANS` to IDLE, and the AXI response logic maps slave error or timeout
  to response bit 1 (SLVERR).
- Address generation has separate 32-bit/64-bit and narrow-enabled/disabled branches.

These observations are **traceability evidence only**, not proof of correctness. Status of
the priority audit risks as of 2026-09-17:

| # | Risk | Status |
|---|---|---|
| 1 | **Unsupported lock handling:** the RTL captures `AWLOCK`/`ARLOCK` and drives `HMASTLOCK` from it, while PG177 lists locked and exclusive operations as unsupported. | **Closed (Section 4.1):** matches the reference VHDL; kept. Verified by `bridge_unsupported_feature_test` in the third regression. |
| 2 | **Parameter legality:** equal AXI/AHB data widths, data width 32/64, address width 32–64, timeout 0/16/32/64/128/256. | **Open in the DUT** (no elaboration guards). The environment checks widths and timeout values in `vip_env_cfg.is_valid()`, the transaction constructors and the SVA; no negative elaboration test exists. |
| 3 | **Single-write `WSTRB` decoding:** every legal lane and every sparse/zero/illegal pattern. | **Partial.** On the 32-bit narrow build, all seven legal patterns (`0x1`, `0x2`, `0x4`, `0x8`, `0x3`, `0xC`, `0xF`) are checked. Zero/sparse patterns and 64-bit are not tested. |
| 4 | **1-KB split off-by-one behavior** at every transfer size. | **Partial.** No-cross, exact-edge (last byte at `0x3FF`) and crossing cases pass at full width only; crossings start one beat before the boundary only. Narrow sizes, other crossing positions and the 64-bit multi-boundary case are not tested. |
| 5 | **AHB error timing:** ERROR on every beat position with and without wait states. | **Open.** No ERROR or wait-state stimulus yet; see Section 3.4 for the unconfirmed oracle. |
| 6 | **Timeout boundaries:** completion one clock before, on and after each timeout value; AHB IDLE, AXI SLVERR, reset recovery. | **Open.** Only `C_DPHASE_TIMEOUT=0` is built, and the predictor does not model timeout. |
| 7 | **Read priority:** simultaneous read and write requests with varied AW/W ordering. | **Open.** All traffic runs with one outstanding transaction. The predictor orders requests by monitor timestamp, and write requests are published only at `WLAST`, so it must be extended before this test can pass reliably. |
| 8 | **Synchronous reset:** reset away from a clock edge and during every transaction phase. | **Open.** The testbench only releases power-on reset on a clock edge; a mid-test reset event exists in `bridge_tb_top` but no test uses it. |

## 6. Bridge-level UVM topology (implemented)

The integration environment exists (`10_tb/`):

```text
axi4_mst_agent (active) --> DUT --> ahb_slv_agent (reactive slave + memory model)
      |  req_ap / ap                         |  ap
      v                                      v
  predictor ---- expected AHB beats ---> scoreboard <--- actual AHB transfers
      |                                      |
      +---- expected AXI template ---------->+  expected AXI completion rebuilt from
                                             |  observed AHB response/read data
                                             +<--- actual AXI completions (AXI monitor)
```

| Required component | Implementation | Remaining gap |
|---|---|---|
| Environment configuration | `vip_env_cfg`: agent configs, narrow support, timeout value, scoreboard/coverage switches | No supported-feature/negative-test policy. |
| Virtual sequencer | `virtual_sequencer` with AXI and AHB sequencers | AHB response sequences are not used by any test (all tests use automatic OKAY, zero-wait responses). |
| Predictor | `predictor`: Sections 2 and 3.3, strobe-derived `HSIZE`, 1-KB restart | No timeout model; request ordering assumes one outstanding transaction. |
| Scoreboard | `scoreboard`: AHB beat compare, AXI completion compare (ID, attributes, data, strobes, responses), empty-queue check | No check that at least one transaction was compared. |
| Coverage | `e2e_cov` plus agent covergroups | Merged coverage not yet reviewed; several bins are unreachable by design and need waivers. |
| Protocol assertions | `axi4_sva`, `ahb_sva` bound in `bridge_tb_top`; lock-profile assertions can be turned off at run time through the `bridge_allow_lock` event (Section 4.1) | Assertion failures are reported with `$error`; the regression Makefile fails a run on simulator errors (`FAIL_REGEX`), but this gate has not yet been proven by fault injection. |

## 7. Minimum compliance regression

Status as of the third regression (2026-09-17). All stimulus is currently 32-bit, one
outstanding transaction, zero AHB wait, AHB OKAY only, `AxCACHE = AxPROT = 0`, and
`AxLOCK = 0` except in `bridge_unsupported_feature_test`. The random
seed only changes AXI IDs (and FIXED lengths), so repeated runs of the same test are
nearly identical.

### P0 — integration gate

| Item | Status |
|---|---|
| Single aligned read/write and write-read-back at 32 bits | Done — `bridge_sanity_test`. |
| AHB zero wait | Done — all tests. |
| AHB fixed wait and ERROR | Not started (slave agent supports `ready_delay_*` and response sequences). |
| AXI B/R backpressure | Not started (driver supports `bready_delay_*`/`rready_delay_*`). |
| Reset idle and mid-transfer | Not started. |
| Zero UVM errors/fatals, zero simulator/assertion errors, all expected queues empty | Done — enforced by `bridge_base_test`, `scoreboard.check_phase` and the Makefile `FAIL_REGEX`. |

### P1 — PG177 conversion matrix

| Item | Status |
|---|---|
| INCR lengths 1, 2, 3, 4, 5, 8, 16, 17, and 256 | Done — `bridge_incr_mapping_test`, `bridge_burst_matrix_test`. |
| WRAP lengths 2, 4, 8, and 16 at every legal wrap offset | Done at full width — `bridge_wrap_mapping_test`. |
| FIXED lengths 1 and 16 plus random intermediate lengths | Done — `bridge_fixed_mapping_test`. |
| 1-KB non-cross, exact-edge, and crossing cases, read and write, every supported size | Partial — full width only (`bridge_1kb_boundary_test`). |
| All `AxPROT` values crossed with relevant `AxCACHE` bufferable encodings | Not started. |
| Simultaneous read/write arbitration | Not started. |

### P1 — width and narrow matrix

| Item | Status |
|---|---|
| 32-bit and 64-bit equal-width configurations | 32-bit only. |
| Narrow disabled and enabled | Both builds run; the enabled build runs only `bridge_data_integrity_test`. Note: `bridge_incr_mapping_test` sends single-beat 8/16-bit requests on the narrow-disabled build; they pass only because they use byte lane 0, and they are outside the supported profile. |
| Every legal byte lane for each supported narrow size | Partial — 32-bit single-beat 8/16-bit lanes; no narrow bursts, no 64-bit. |
| Directed unsupported sparse and unaligned narrow requests, classified separately | Not started. |

### P1 — unsupported-feature policy

| Item | Status |
|---|---|
| Locked/exclusive requests complete with OKAY and correct data; `HMASTLOCK` follows `AxLOCK` (Section 4.1) | Done — `bridge_unsupported_feature_test` (third regression, 5 seeds). |
| Sparse `WSTRB` and unaligned narrow requests classified as negative tests | Not started. |

### P1 — response and timeout matrix

| Item | Status |
|---|---|
| AHB OKAY and ERROR at first/middle/last beat under 0, 1, and randomized wait states | OKAY with zero wait only. |
| Timeout disabled plus 16/32/64/128/256 | Not started (disabled build exists, but no long-wait stimulus). |
| For every non-zero timeout: ready before/at/after the boundary, AXI SLVERR, AHB IDLE, reset recovery | Not started. |

### P2 — closure

| Item | Status |
|---|---|
| Constrained-random mixed read/write traffic with independent AHB delay/error policy | Not started. |
| Functional, assertion, and code coverage review against a requirement matrix | Not started (UCDB files are produced; no merged review). |
| Mutation tests (address, `HBURST`, `HSIZE`, `HPROT`, data lane, ID, response, beat count, 1-KB restart, timeout threshold) | Not started. |
| Equivalence or side-by-side simulation against the original VHDL source | Not started; required before treating the translated DUT, or the RTL observations above, as golden. |

## 8. Definition of done

The environment is not industrial-grade merely because all directed tests pass. A release
candidate should have:

- A reviewed requirement-to-test/checker/coverage traceability matrix
  (`00_doc/axi_ahblite_bridge_vplan.xlsx`).
- Independent predictor review and mutation evidence that each checker detects injected
  defects.
- Zero unexplained UVM errors/fatals, assertion failures, or outstanding transactions.
- Coverage goals and reviewed waivers rather than an unqualified “100% coverage” claim.
- Multi-seed parameter regression and reproducible failing commands/seeds.
- Simulator/version support matrix, clean compile file lists, documentation, changelog, and
  generated artifacts excluded from source control (regression logs and UCDB files are
  currently committed).
