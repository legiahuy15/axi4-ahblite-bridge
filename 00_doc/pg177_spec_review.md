# PG177 AXI4 to AHB-Lite Bridge v3.0 - spec review

Externally visible behavior of the bridge described by PG177 (v3.0, November 18, 2015) that
the UVM environment must model and check. This is a verification checklist, not a
replacement for PG177 or the ARM AXI4 (IHI0022E) and AHB-Lite (IHI0033A) specifications.

Items marked **RTL** describe the translated RTL in `01_src/dut/` where PG177 is silent or
less specific. They are the expected behavior for this design, not PG177 requirements.

## 1. Product profile

| Area | PG177 requirement |
|---|---|
| Topology | AXI4 slave to AHB-Lite master. |
| Clocking | Synchronous design; both interfaces use `s_axi_aclk`. |
| Reset | `s_axi_aresetn`: active-low, synchronous; also resets the AHB-Lite interface. |
| Address width | 32 to 64 bits, one setting for both interfaces. The address is passed to AHB-Lite unchanged, except that an unaligned read is aligned. |
| Data width | 32 or 64 bits, equal on AXI and AHB-Lite. No width conversion. |
| Endianness | Little-endian on both interfaces. |
| Bursts | AXI INCR 1–256, WRAP 2/4/8/16, FIXED 1–16. AHB-Lite SINGLE, INCR4/8/16, undefined INCR, WRAP4/8/16. |
| Arbitration | When a read and a write are requested together (`AWVALID`/`WVALID` and `ARVALID` high), the read is issued on AHB-Lite first and the write follows. |
| Responses | Only OKAY and SLVERR. AHB ERROR and bridge timeout both map to SLVERR; EXOKAY and DECERR are never generated. |
| Timeout | `C_DPHASE_TIMEOUT` = 0 (disabled, the bridge waits indefinitely) or 16/32/64/128/256 AXI clocks. On timeout the bridge completes the AXI transaction with SLVERR and drives IDLE on AHB-Lite. PG177 recommends that the master resets the bridge after SLVERR. |
| Registers | None. |
| Latency | Best case: 4 clocks `ARVALID` → `RVALID`; 3 clocks `AWVALID` → valid AHB write data. A performance figure, not a protocol rule. |

**RTL:** any parameter combination outside this profile stops elaboration with `$fatal`.

## 2. Transaction translation (PG177 Table 3-2)

| AXI request | AHB-Lite transfers |
|---|---|
| INCR, 1 beat | SINGLE. |
| INCR, 4/8/16 beats, no 1 KB crossing | INCR4/INCR8/INCR16. |
| INCR, 2–256 beats other than 4/8/16 | Undefined-length INCR. |
| INCR crossing a 1 KB boundary (any length) | Two undefined-length INCR bursts; the second starts with NONSEQ at the boundary. |
| WRAP, 4/8/16 beats | WRAP4/WRAP8/WRAP16. |
| WRAP, 2 beats | Two SINGLE transfers. |
| FIXED, 1–16 beats | One SINGLE per AXI beat, all at the same address. |

The predictor must produce a stream of AHB beats (address, direction, `HTRANS`, `HBURST`,
`HSIZE`, `HPROT`, `HMASTLOCK`, write data), not one AHB transaction per AXI transaction.
Wait states and BUSY/IDLE cycles are not beats.

**RTL - beat spacing:** the bridge inserts one non-transfer cycle after every beat: BUSY
inside INCR/WRAP bursts, IDLE between FIXED and WRAP2 transfers and at a 1 KB split. Each
beat therefore takes at least two clocks even with `HREADY` high. This is legal AHB-Lite;
the AHB slave model and assertions must accept BUSY.

## 3. Narrow transfers and write strobes

PG177 rules:

- Narrow transfers are supported only when the core is generated with
  `C_S_AXI_SUPPORTS_NARROW_BURST = 1`. Supported sizes: 8/16 bits on a 32-bit bus,
  8/16/32 bits on a 64-bit bus.
- Single write (`AWLEN = 0`): `HSIZE` is derived from `WSTRB`.
- Burst: `HSIZE` = `AxSIZE`.
- Sparse and unaligned narrow transfers are not supported.

With narrow support disabled, narrow traffic is outside the supported profile and is used
only as negative stimulus.

**RTL - single-write `WSTRB` decoding** (same on both builds): only one size-aligned run of
lanes is recognised (on 32 bits: `0x1`, `0x2`, `0x4`, `0x8`, `0x3`, `0xC`, `0xF`). AHB-Lite
has no strobes, so any other pattern cannot be honoured:

- Zero or unrecognised `WSTRB` (e.g. `0x0`, `0x5`, `0x7`): `HSIZE` falls back to `AWSIZE`
  and the whole `AWSIZE`-wide word is written, including lanes the master did not strobe.
  `WSTRB = 0` is legal AXI, yet it overwrites data.
- A recognised narrow pattern that does not match `AWADDR` (e.g. `WSTRB = 0x4` with
  full-width `AWSIZE` at a word-aligned address): `HADDR` comes from `AWADDR`, so lane 0 is
  written and the strobed lane is left unchanged.

**RTL - burst `WSTRB`:** ignored. Every beat writes a whole `AxSIZE`-wide word, so masked
lanes are overwritten.

These are negative cases: the predictor models them so the scoreboard does not flag them,
and only read-back of the whole word shows the effect.

## 4. Address alignment

PG177 states only that an unaligned **read** address is aligned on AHB-Lite.

**RTL:** reads and writes are aligned the same way. With narrow support disabled `HADDR` is
aligned to the bus width; with it enabled, to the transfer size (`AxSIZE`, or the
`WSTRB`-derived size for a single write). An unaligned write therefore also writes the
lanes below the start address. Unaligned writes fall under the unsupported
"unaligned/sparse" category and are negative cases.

## 5. `AxPROT`/`AxCACHE` to `HPROT` (PG177 Table 3-1)

| Bit | Value | Meaning |
|---|---|---|
| `HPROT[3]` | `0` | Always non-cacheable. |
| `HPROT[2]` | `1` when `AxCACHE = 00x1`, else `0` | Bufferable. |
| `HPROT[1]` | `AxPROT[0]` | Privileged / user. |
| `HPROT[0]` | `~AxPROT[2]` | Data / instruction. |

Reset value is `4'b0011` (non-cacheable, non-bufferable, privileged data).

PG177 defines `HPROT[2]` only for `AxCACHE = 00x0`/`00x1`. **RTL:** `HPROT[2] =
AxCACHE[0] & ~AxCACHE[2] & ~AxCACHE[3]`, so the other bufferable encodings (`0111`,
`1011`, `1111`) map to non-bufferable.

The six reserved AXI4 `AxCACHE` encodings (`0100`, `0101`, `1000`, `1001`, `1100`, `1101`;
IHI0022E Table A4-5) are excluded from legal stimulus.

## 6. Error and timeout

PG177 defines only the response mapping (AHB ERROR or timeout → SLVERR). It does not say
whether the rest of a burst is still transferred after an ERROR.

**RTL - AHB ERROR:** the bridge continues the remaining beats; `HRESP` is sampled when a
beat completes and the state machine proceeds as for OKAY.

- Write burst: `BRESP` = SLVERR if any beat received ERROR.
- Read burst: `RRESP` per beat; SLVERR only on the beats that received ERROR.

**RTL - timeout:** the bridge drives IDLE and issues no further beats of that request; the
remaining AXI beats complete with SLVERR. The shortest AHB wait that triggers the timeout
is `C_DPHASE_TIMEOUT + 2` clocks for a read and `C_DPHASE_TIMEOUT + 1` for a write.

## 7. Reset

PG177 specifies a synchronous active-low reset and the `HPROT` default `4'b0011`.

**RTL - reset values:** AHB `HTRANS` = IDLE; `HADDR`, `HBURST`, `HSIZE`, `HWRITE`,
`HMASTLOCK` = 0; `HPROT` = `4'b0011`. AXI `AWREADY`, `WREADY`, `BVALID`, `ARREADY`, `RVALID`,
`RLAST` = 0. A request interrupted by reset is discarded; no response is returned for it.

## 8. Unsupported features

PG177 lists as unsupported:

- Data widths above 64 bits.
- Locked, barrier, TrustZone and exclusive operations.
- Out-of-order read or write completion (the bridge completes in order).
- Unaligned/sparse burst transfers (holes in write strobes).
- EXOKAY and DECERR responses.
- Low-power state and secure accesses.

Legal stimulus must exclude these, or classify them explicitly as negative tests.

### 8.1 Lock

An AXI master may still issue `AxLOCK = 1`. **RTL** (matches the reference design, kept
unchanged): `AxLOCK` is registered and drives `HMASTLOCK`. Expected behavior:

- The request completes normally with correct data.
- The response is OKAY or SLVERR, never EXOKAY. Per AXI, OKAY to an exclusive access tells
  the master that exclusive access is not supported.
- `HMASTLOCK` = 1 on every AHB beat of that request.

**RTL:** the lock register updates only when the next request is accepted, so `HMASTLOCK`
stays high while the bus is IDLE after a locked request. Harmless on a single-master
AHB-Lite bus, but it can keep a multi-master interconnect locked.

## 9. Open questions

- **Multiple 1 KB crossings.** PG177 describes the split as *two* bursts. A 64-bit,
  256-beat INCR (2048 bytes) can cross two 1 KB boundaries, a case PG177 does not cover.
  **RTL:** the boundary check (`one_kb_cross`) is repeated on every beat, so the burst is
  split at each boundary into three undefined-length INCR segments. Each segment after the
  first is preceded by one IDLE cycle and starts with NONSEQ. The predictor models the same
  behavior.
- **Latency.** PG177 gives only best-case figures; no latency requirement is checked.