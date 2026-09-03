# PG177 AXI4 to AHB-Lite Bridge v3.0 — verification review

This review records the externally visible behavior that the UVM environment must verify
for the AXI4 to AHB-Lite Bridge v3.0 described by **PG177, November 18, 2015**. It is a
verification checklist, not a replacement for the licensed product guide or the ARM
protocol specifications.

## 1. Confirmed product profile

| Area | PG177 v3.0 requirement |
|---|---|
| Topology | AXI4 slave to AHB-Lite master. |
| Clocking | Synchronous design; both interfaces use `s_axi_aclk`. |
| Reset | `s_axi_aresetn` is an active-low synchronous reset and also resets the AHB-Lite interface. |
| Address width | Configurable from 32 to 64 bits. The AXI address is not remapped before it reaches AHB-Lite, except for alignment of an unaligned AXI read. |
| Data width | 32 or 64 bits, with equal width on AXI and AHB-Lite. |
| Endianness | Little-endian on both interfaces. |
| Read/write arbitration | A simultaneous AXI read and write request gives the read request higher priority. |
| AXI responses | The bridge generates only OKAY and SLVERR. AHB ERROR and bridge timeout map to AXI SLVERR; EXOKAY and DECERR are never generated. |
| Timeout | Disabled at zero; supported non-zero settings are 16, 32, 64, 128, and 256 AXI clocks. Timeout terminates the AHB request with IDLE and returns AXI SLVERR. |
| Registers | No register space is implemented. |

The guide reports best-case read latency of four clocks from `ARVALID` to `RVALID`, and
best-case write latency of three clocks from `AWVALID` to valid AHB write data. These are
performance targets that should be measured separately from protocol correctness; stalls
and arbitration can increase latency.

## 2. Transaction translation oracle

The bridge predictor must implement the following mapping independently of the RTL:

| Accepted AXI request | Expected AHB-Lite request |
|---|---|
| INCR, 1 beat | SINGLE. |
| INCR, 4/8/16 beats, no 1-KB crossing | INCR4/INCR8/INCR16 respectively. |
| INCR, 2–256 beats other than 4/8/16 | Undefined-length INCR. |
| INCR crossing a 1-KB boundary | Two undefined-length INCR bursts; the second begins with NONSEQ after the boundary. |
| WRAP, 4/8/16 beats | WRAP4/WRAP8/WRAP16 respectively. |
| WRAP, 2 beats | Two SINGLE transfers. |
| FIXED, 1–16 beats | One SINGLE transfer per AXI beat, all at the same address. |

The scoreboard must therefore compare a predicted **stream of AHB beats**, not compare one
AXI transaction with one AHB transaction. In particular, the predictor must retain AHB
address-phase/data-phase timing and must not count wait-state cycles as additional beats.

## 3. Narrow, alignment, data, and protection rules

### 3.1 Narrow transfers

Narrow support is configurable:

- On a 32-bit interface, supported narrow sizes are 8 and 16 bits.
- On a 64-bit interface, supported narrow sizes are 8, 16, and 32 bits.
- For a single AXI write (`AWLEN == 0`), the bridge derives `HSIZE` from `WSTRB`.
- For an AXI burst, it passes `AWSIZE` or `ARSIZE` to `HSIZE`.
- Sparse and unaligned narrow transfers are unsupported.

The verification plan must distinguish legal narrow accesses from negative protocol/input
tests. Sparse `WSTRB` is not a supported feature to be treated as ordinary legal traffic.

### 3.2 Address and data

- Both interfaces are little-endian.
- AXI write data passes to AHB write data without width conversion.
- AHB read data passes to AXI read data without width conversion.
- An unaligned AXI read address is aligned on the AHB-Lite side because AHB-Lite has no
  unaligned-address concept.

### 3.3 `AxPROT`/`AxCACHE` to `HPROT`

The predictor must calculate the four AHB protection bits as follows:

- `HPROT[3] = 0`: always non-cacheable.
- `HPROT[2] = AxCACHE[0] & ~AxCACHE[2] & ~AxCACHE[3]`: bufferable mapping.
- `HPROT[1] = AxPROT[0]`: privileged versus user.
- `HPROT[0] = ~AxPROT[2]`: data versus instruction.
- Reset/default is `4'b0011` (non-cacheable, non-bufferable, privileged data access).

## 4. Explicitly unsupported features

The legal stimulus profile must exclude, or deliberately classify as negative tests:

- Data widths greater than 64 bits.
- Locked, barrier, TrustZone, and exclusive operations.
- Out-of-order read completion and out-of-order write completion.
- Unaligned/sparse burst transfers (holes in write strobes).
- AXI EXOKAY and DECERR responses.
- Low-power state and secure accesses.
- Cacheable AHB-Lite access.

This materially narrows the standalone AXI VIP regression when that VIP drives this DUT.
Tests intended to demonstrate general AXI out-of-order or exclusive behavior are not bridge
compliance tests for this product profile.

## 5. Initial RTL traceability and audit findings

The SystemVerilog DUT visibly contains implementations corresponding to important PG177
requirements:

- The top level has an AXI slave port set and an AHB-Lite master port set.
- The AHB controller selects SINGLE, undefined INCR, INCR4/8/16, and WRAP4/8/16 from
  `axi_burst` and `axi_length` and detects 1-KB crossing.
- WRAP2 is tracked separately and fixed transfers suppress address incrementing.
- `HPROT` implements the PG177 mapping above.
- A timeout forces `HTRANS` to IDLE, and the AXI response logic maps slave error or timeout
  to response bit 1 (SLVERR).
- Address generation has separate 32-bit/64-bit and narrow-enabled/disabled branches.

These observations are **traceability evidence only**, not proof of correctness. The
following items are priority audit risks:

1. **Unsupported lock handling:** the RTL captures `AWLOCK`/`ARLOCK` and drives
   `HMASTLOCK`, while PG177 lists locked and exclusive operations as unsupported. Tests must
   establish the intended behavior and determine whether driving `HMASTLOCK` is faithful to
   the original source/product configuration.
2. **Parameter legality:** add elaboration checks for equal AXI/AHB data widths, legal data
   widths (32/64), legal address widths (32–64), and timeout values
   (0/16/32/64/128/256). The current top-level parameter types alone do not enforce the
   PG177 configuration space.
3. **Single-write `WSTRB` decoding:** exhaustively test every legal byte/halfword/word lane
   and every sparse/zero/illegal pattern, because `HSIZE` is derived from strobes for a
   single write.
4. **1-KB split off-by-one behavior:** test starts on both sides of the boundary at every
   transfer size, including the case whose final beat ends exactly at byte `0x3ff` and the
   first case that enters the next 1-KB region.
5. **AHB error timing:** inject ERROR on every beat position with and without wait states;
   verify the AXI burst terminates/continues exactly as specified and eventually returns
   SLVERR.
6. **Timeout boundaries:** test completion one clock before, on, and one clock after each
   supported timeout value. Verify AHB IDLE, AXI SLVERR, and recovery after the recommended
   reset.
7. **Read priority:** simultaneously present complete read and write requests repeatedly,
   varying AW/W ordering, and prove that the first AHB request is the read.
8. **Synchronous reset:** assert reset away from a clock edge and prove state changes only on
   the active edge; repeat during each AXI and AHB transaction phase.

## 6. Required bridge-level UVM topology

Create a new integration environment rather than connecting the two existing self-test
scoreboards:

```text
AXI active master agent -> DUT -> AHB active slave responder
          |                         |
          v                         v
     AXI monitor -> bridge predictor -> expected AHB FIFO
                                     X actual AHB monitor

AHB response/memory model -> expected AXI response FIFO
                              X actual AXI monitor
```

Required components:

1. `bridge_env_config`: widths, narrow support, timeout, supported-feature policy, and both
   virtual interfaces.
2. `bridge_virtual_sequencer`: coordinates AXI request traffic and independent AHB response
   policy.
3. `bridge_predictor`: implements Sections 2 and 3 without copying RTL state-machine code.
4. `bridge_scoreboard`: checks request translation, response/data translation, ordering,
   loss/duplication, and end-of-test outstanding queues.
5. `bridge_coverage`: requirement-oriented cross coverage.
6. AXI and AHB protocol assertions instantiated around the DUT.

## 7. Minimum compliance regression

### P0 — integration gate

- Single aligned read/write and write-read-back at 32 bits.
- AHB zero wait, fixed wait, and ERROR.
- AXI B/R backpressure.
- Reset idle and mid-transfer.
- Compile and run with zero UVM errors/fatals and all expected queues empty.

### P1 — PG177 conversion matrix

- INCR lengths 1, 2, 3, 4, 5, 8, 16, 17, and 256.
- WRAP lengths 2, 4, 8, and 16 at every legal wrap offset.
- FIXED lengths 1 and 16 plus random intermediate lengths.
- 1-KB non-cross, exact-edge, and crossing cases for read and write at every supported size.
- All `AxPROT` values crossed with relevant `AxCACHE` bufferable encodings.
- Simultaneous read/write arbitration.

### P1 — width and narrow matrix

- 32-bit and 64-bit equal-width configurations.
- Narrow disabled and enabled.
- Every legal byte lane for each supported narrow size.
- Directed unsupported sparse and unaligned narrow requests, classified separately from
  legal compliance traffic.

### P1 — response and timeout matrix

- AHB OKAY and ERROR at first/middle/last beat under 0, 1, and randomized wait states.
- Timeout disabled plus 16/32/64/128/256.
- For every non-zero timeout: ready before/at/after the boundary, AXI SLVERR, AHB IDLE, and
  reset recovery.

### P2 — closure

- Constrained-random mixed read/write traffic with independent AHB delay/error policy.
- Functional, assertion, and code coverage review against a requirement matrix.
- Mutation tests for wrong address, `HBURST`, `HSIZE`, `HPROT`, data lane, ID, response,
  beat count, 1-KB restart, and timeout threshold.
- Equivalence or side-by-side simulation against the original VHDL source using identical
  stimulus before treating this translated DUT as a golden implementation.

## 8. Definition of done

The environment is not industrial-grade merely because all directed tests pass. A release
candidate should have:

- A reviewed requirement-to-test/checker/coverage traceability matrix.
- Independent predictor review and mutation evidence that each checker detects injected
  defects.
- Zero unexplained UVM errors/fatals, assertion failures, or outstanding transactions.
- Coverage goals and reviewed waivers rather than an unqualified “100% coverage” claim.
- Multi-seed parameter regression and reproducible failing commands/seeds.
- Simulator/version support matrix, clean compile file lists, documentation, changelog, and
  generated artifacts excluded from source control.

