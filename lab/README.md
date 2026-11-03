# Lab 5 — Memory Model, Testbench Tasks, and Interface

This is a prepared demonstration. Students run each activity, follow the
annotated messages, and inspect the captured waveform; no coding is required.

## Activities

| Activity | Directory | Command |
|---|---|---|
| 1. Memory tasks and functions | `01_memory_subprograms/` | `bash run.sh` |
| 2. Memory interface and modports | `02_memory_interface/` | `bash run.sh` |

Use `bash run_gui.sh` in either activity to open the Xcelium GUI. Each activity
has its own source list, transcript, and `waves.shm` database. For verbose
per-address messages, add `+DEBUG` after the script name. These scripts assume
`xrun` is already available in the student's server environment.

## Activity 1 — Memory tasks

Observe a 32 x 8-bit synchronous memory. The testbench tasks drive signals on
the falling edge, then sample reads after the rising-edge memory update. The
simulation clears all 32 words and checks them, then writes each address as its
data and checks all 32 words again.

## Activity 2 — Interface

Observe the same memory checks after putting the clock and bus in an interface.
The interface defines memory/testbench modports and supplies read/write
methods. Xcelium 25.03 can compile and elaborate those interface methods when
the testbench receives the interface directly, but reports that task imports in
modports are unimplemented. Therefore the functional demonstration uses the
unmodported interface connection for the testbench; the testbench modport is
still defined for discussing the report's intended direction declaration. A
simulation license was unavailable in the validation environment, so runtime
behavior still needs confirmation on a licensed server.

## Grading checks

- Both activities print `MEMORY_CLEAR_PASS checks=32` and
  `MEMORY_ADDRESS_PASS checks=32`.
- Each activity prints its own final `LAB5_..._PASS` marker.
- A mismatch prints a failure and exits non-zero.
- The interface run completes the same 64 readback checks as Activity 1.
- Waveform database shows clock, controls, address, input data, and output
  data. In Activity 2, inspect them through the interface instance.
