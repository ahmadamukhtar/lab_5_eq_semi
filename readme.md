# Lab 5 — Memory Testbench and Interface

## Purpose

Practice SystemVerilog testbench subprograms by verifying a 32-location, 8-bit
memory, then practice connecting a design and testbench through a SystemVerilog
interface.

## What the report asks students to do

### Verify the memory

The report specifies a 5-bit address, 8-bit `data_in` and `data_out`, and
`read`, `write`, and `clk` controls. Reads and writes occur on the positive
clock edge, and `read` and `write` must not be high at the same time.

1. Complete the memory testbench using read and write tasks synchronized to
   the clock. Drive signals on the inactive clock edge to avoid races.
2. Provide optional debug output using a default task argument.
3. Test all 32 locations with two patterns:
   - Clear memory: write zero everywhere, then read and check every location.
   - Data equals address: write each address as its data, then read and check.
4. Report the total number of errors with a `void` status function.
5. Simulate the memory, testbench, and top-level module together.

### Add and use an interface

The report then asks students to:

1. Move the memory signals into a SystemVerilog interface.
2. Connect the memory and testbench through the interface.
3. Move the clock into the interface and remove the separate module clock
   ports.
4. Add design and testbench modports with the appropriate signal directions.
5. Move the read/write tasks into the interface and import them through the
   testbench modport.
6. Rerun the memory test after the interface changes.

## Supplied files and current state

`lab_5_files/` contains:

- `mem.sv` — memory model.
- `mem_test.sv` — testbench, read/write tasks, two memory tests, and status
  reporting.
- `mem_intf.sv` — interface currently used to connect the memory signals.
- `top.sv` — clock generator and instances of the memory and testbench.
- `lab7.f` — simulator file list.

The memory tests and interface-based signal connections are already present.
The interface does not yet contain the clock, modports, or the memory access
tasks. The design and testbench still have separate clock ports, so these are
the remaining interface steps from the report.

## Notes for future lab planning

The report describes an initial memory-testbench exercise followed by an
interface extension. The provided files appear to be at the interface stage,
but do not yet implement all of the report's interface requirements. Confirm
the simulator and expected submission/output format before preparing the
student procedure.