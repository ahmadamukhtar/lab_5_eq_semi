<!--
Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
All rights reserved.
EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
Project: edge-ai-eqsemi
File: design/axi_interconnect/README.md
Author(s): Ibrahim Al-Sahafi
Last Modified: 2026-11-01
-->

# AXI4-Lite 2×9 interconnect

The active block top is `axi4_lite_2x9_interconnect`. It connects two system
managers (`M1`, `M2`) to nine peripherals (`S1`–`S9`). At the interconnect boundary,
the manager inputs use `axi4_lite_if.slave`, and the peripheral outputs use
`axi4_lite_if.master`. These are the two **S** and nine **M** ports in the diagram.

The top uses two fixed-priority arbiters and `axi4_lite_1x9_interconnect` for
address decoding and channel routing. M1 wins simultaneous requests in the same
direction. A write grant lasts through the B handshake; a read grant lasts
through the R handshake. Read and write can use different managers concurrently.

| Output | Default address range | Size |
| --- | --- | --- |
| S1 | `0x00000000`–`0x00000FFF` | 4 KiB |
| S2 | `0x00001000`–`0x00001FFF` | 4 KiB |
| S3 | `0x00002000`–`0x00002FFF` | 4 KiB |
| S4 | `0x00003000`–`0x00003FFF` | 4 KiB |
| S5 | `0x00004000`–`0x00004FFF` | 4 KiB |
| S6 | `0x00005000`–`0x00005FFF` | 4 KiB |
| S7 | `0x00006000`–`0x00006FFF` | 4 KiB |
| S8 | `0x00007000`–`0x00007FFF` | 4 KiB |
| S9 | `0x00008000`–`0x00008FFF` | 4 KiB |

Each output has `Sx_BASE` and `Sx_MASK` parameters. The default mask is
`0xFFFFF000` for 32-bit addresses. Matching compares `(address & mask)` with
`(base & mask)`. The lowest-numbered matching output wins if windows overlap.
Unmapped requests receive DECERR; peripheral responses, including SLVERR, pass
through. Addresses reach peripherals unchanged; subtract the window base in the
peripheral adapter when it expects local offsets.

## Connections

```systemverilog
axi4_lite_if #(32, 32) managers [2] (ACLK, ARESETn);
axi4_lite_if #(32, 32) peripherals [9] (ACLK, ARESETn);

axi4_lite_2x9_interconnect #(
    .ADDR_WIDTH(32), .DATA_WIDTH(32)
) u_interconnect (
    .ACLK, .ARESETn,
    .M1(managers[0]), .M2(managers[1]),
    .S1(peripherals[0]), .S2(peripherals[1]), .S3(peripherals[2]),
    .S4(peripherals[3]), .S5(peripherals[4]), .S6(peripherals[5]),
    .S7(peripherals[6]), .S8(peripherals[7]), .S9(peripherals[8])
);
```

Connect each `peripherals[n]` to a peripheral's AXI slave port, or to the `axi`
port of its `axi_lite_slave_wrapper`. Connect that wrapper's backend request,
completion, data and error signals to the peripheral. All endpoints use the same
clock/reset and matching address/data widths. Compile
`design/common/rtl/axi4_lite_if.sv` before modules that use the interface; the block metadata
ensures this order in generated simulation and lint filelists. The `axi4_lite_if`
cluster supplies the interface; `common_rtl` also supplies the shared peripheral
frontends and wrapper. UART retains its existing scalar-port frontends in its
own cluster.

The implementation retains one pending write and one pending read **across both
managers**, with no additional request queue. Each manager must wait for B
acceptance before another write, and R acceptance before another read. Transfers
are single-beat, full-word accesses; the interface omits WSTRB and protection
attributes. There is no clock crossing, timeout, automatic retry or fairness
guarantee. A stalled response holds that direction's grant across all outputs.

## Verification

Run the active block or standalone routing-core test with the existing flow:

```sh
make run.sim.axi_interconnect
make run.sim.interconnect
```

Run `make gen` first to regenerate BRIX filelists after changing sources or YAML.

The testbenches check every output from both managers, window boundaries,
AW/W skew, response stalls, error responses, arbitration, independent read/write
progress, and reset recovery. The default data width is 32 bits. Override
testbench parameters through the existing Xcelium flags for additional cases:

```sh
make run.sim.axi_interconnect XRUN_ARGS='-timescale 1ns/1ps -defparam tb_axi_lite_2x9.ADDR_WIDTH=24 -defparam tb_axi_lite_2x9.DATA_WIDTH=64'
make run.sim.interconnect XRUN_ARGS='-timescale 1ns/1ps -defparam tb_axi_lite_1x9.ADDR_WIDTH=24 -defparam tb_axi_lite_1x9.DATA_WIDTH=64'
make run.sim.axi_interconnect XRUN_ARGS='-timescale 1ns/1ps -defparam tb_axi_lite_2x9.MAP_MODE=1'
make run.sim.axi_interconnect XRUN_ARGS='-timescale 1ns/1ps -defparam tb_axi_lite_2x9.MAP_MODE=2'
```

`MAP_MODE=1` tests a relocated 8 KiB S9 window; `MAP_MODE=2` tests overlapping
S8/S9 windows. The active build uses the 1×9 routing core and 2×9 top.
The OBI-to-AXI bridge system test also uses the 1×9 core, with three active outputs.
