# Lab 5 — Instructor-Led Demonstration Strategy

## Teaching goal

Demonstrate the two stages in the report: first verify a synchronous 32 x
8-bit memory using SystemVerilog tasks/functions, then move its shared signals,
clock, and access tasks into a SystemVerilog interface. Students should be
able to run each stage and understand the comments; they should not need to
write RTL during the presentation.

## Proposed lab directory

```text
lab_5/
├── Lab_5.pdf
├── readme.md
├── strategy.md
└── lab/
    ├── README.md
    ├── 01_memory_subprograms/
    │   ├── mem.sv
    │   ├── mem_test.sv
    │   ├── top.sv
    │   ├── sources.f
    │   └── run.sh
    └── 02_memory_interface/
        ├── mem_intf.sv
        ├── mem.sv
        ├── mem_test.sv
        ├── top.sv
        ├── sources.f
        └── run.sh
```

Each activity is a self-contained Xcelium run, with its own source list,
transcript, and SHM waveform database. The original `lab_5_files/` remains
unchanged as the supplied course material. Both activities include batch and
GUI launchers.

## Activity 1 — Memory tasks and functions

Use the report's non-interface memory design. The testbench should use
clock-synchronized read/write tasks, optional debug messages, and a function
or equivalent checker that counts mismatches. Run the required clear-memory
and data-equals-address patterns across all 32 locations.

**Run:** from `lab/01_memory_subprograms/`, use `bash run.sh`; use
`bash run_gui.sh` for the GUI waveform.

**Grading checks:** the run exits successfully and prints distinct pass
markers for both patterns; each pattern reports 32 successful readbacks; any
mismatch ends the run as a failure.

## Activity 2 — Interface extension

Use a separate final design in which the interface owns the memory signals and
clock, defines design/testbench modports, and provides the read/write methods
used by the testbench. Run the same two memory patterns to show that the
interface refactor preserves behavior.

**Xcelium compatibility note:** Xcelium 25.03 reports that imported tasks in
modports are not implemented. The runnable reference therefore uses the memory
modport on the DUT and an unmodported interface port on the testbench so the
interface tasks remain executable. The intended testbench modport is retained
for discussion, but cannot currently be used to import these methods with the
installed simulator version.

**Run:** from `lab/02_memory_interface/`, use `bash run.sh`; use
`bash run_gui.sh` for the GUI waveform.

**Grading checks:** the run exits successfully, both pattern markers appear,
and the interface version completes the same 64 readback checks as Activity 1.

## Run-script behavior

Each `run.sh` compiles its local `sources.f` with Xcelium, executes the
simulation, saves `xrun.log`, and checks the expected pass markers. It
prints a clear setup error if `xrun` is not in `PATH`. The student-facing
`lab/README.md` gives the commands and explains the expected output.

## Implementation sequence

1. Activity 1 and Activity 2 source sets and run scripts are in `lab/`.
2. Both simulations capture signals with Xcelium SHM probing for SimVision.
3. Validate compile/runtime behavior and pass/fail output in an Xcelium-enabled
   terminal before presentation.

## Validation note

The Xcelium 25.03 executable and SimVision are installed in the current
environment. Both activity designs compile and elaborate, but simulator
license checkout failed before runtime, so pass markers and generated SHM
waveforms still need confirmation on a licensed server. Student scripts use
plain `xrun` and expect their server environment to configure it in `PATH`.
