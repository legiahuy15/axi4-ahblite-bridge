# AXI4 to AHB-Lite Bridge — SystemVerilog translation

This directory contains a synthesizable SystemVerilog translation of the user-provided
`axi_ahblite_bridge_v3_0_vh_rfs.vhd` source. The design is split along the original
logical module boundaries:

- `counter_f.sv` — timeout counter
- `time_out.sv` — AHB data-phase watchdog
- `ahb_skid_buf.sv` — registered read-data skid buffer
- `axi_slv_if.sv` — AXI4 slave/control state machines
- `ahb_mstr_if.sv` — AHB-Lite master/control state machine and address/burst conversion
- `axi_ahblite_bridge.sv` — top level
- `files.f` — compile order
- `axi_ahblite_bridge_all.sv` — all six modules concatenated into one file for convenience

The translation keeps synchronous reset behavior and the original state-machine/control
structure. Comments focus on protocol behavior and non-obvious SystemVerilog constructs,
rather than comparing line-by-line with VHDL.

## Notes

- The original design assumes AXI and AHB data widths match (32 or 64 bits).
- `C_S_AXI_SUPPORTS_NARROW_BURST` controls narrow-transfer address handling.
- `C_DPHASE_TIMEOUT = 0` removes timeout behavior; non-zero enables the watchdog.
- The code is intended as a faithful source translation, but it should still be verified
  against the original VHDL with the same testbench before production use.
