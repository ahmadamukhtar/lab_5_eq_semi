<!--
Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
All rights reserved.
EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
Project: edge-ai-eqsemi
File: design/axi_interconnect/SPECS.md
Last Modified: 2026-11-04
-->

# AXI4-Lite 2x9 Interconnect - Verification Specification

Purpose: boundary-level spec used to build a reusable AXI4-Lite UVC
(master + slave + passive monitor agents) and a scoreboard for
`axi4_lite_2x9_interconnect`. Sources: `README.md`, the RTL
(`rtl/axi4_lite_2x9_interconnect.sv`, `modules/axi_1x9_interconnect/rtl/axi4_lite_1x9_interconnect.sv`,
`modules/arbiter/rtl/arbiter.sv`, `design/common/modules/axi_lite_if/rtl/axi4_lite_if.sv`)
and the 2x3 reference datasheet (same architecture, 3 targets instead of 9).
Where the datasheet and the RTL differ, the RTL is the reference.

---

## 1. DUT summary

- Top: `axi4_lite_2x9_interconnect`. 2 managers (`M1`, `M2`) -> 9 subordinates (`S1`..`S9`).
- Internals: write arbiter + read arbiter (`arbiter`) -> one shared bus `M` -> `axi4_lite_1x9_interconnect` (decode + route).
- Single clock `ACLK`, async active-low reset `ARESETn`. No CDC.
- Full-word AXI4-Lite only: no `WSTRB`, `AWPROT`, `ARPROT`. Single-beat.
- **No outstanding transactions**: one write slot and one read slot shared across both managers. Master must wait for B before the next AW and for R before the next AR.
- No response reordering, IDs, queues, timeout, retry, fairness, or address translation.

## 2. Interface and signals (boundary)

Interface `axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH)(ACLK, ARESETn)`. Modports: `master`, `slave`, `monitor` (all signals input).
The DUT sees `M1`/`M2` as `slave` modport and `S1..S9` as `master` modport.

| Channel | Signal | Width | Driven by (UVC view) |
| --- | --- | --- | --- |
| AW | AWADDR, AWVALID | A, 1 | manager |
| AW | AWREADY | 1 | subordinate |
| W | WDATA, WVALID | D, 1 | manager |
| W | WREADY | 1 | subordinate |
| B | BRESP[1:0], BVALID | 2, 1 | subordinate |
| B | BREADY | 1 | manager |
| AR | ARADDR, ARVALID | A, 1 | manager |
| AR | ARREADY | 1 | subordinate |
| R | RDATA, RRESP[1:0], RVALID | D, 2, 1 | subordinate |
| R | RREADY | 1 | manager |

Parameters: `ADDR_WIDTH` (32), `DATA_WIDTH` (32), `Sx_BASE`/`Sx_MASK` x=1..9.
Handshake = `VALID && READY` on a rising `ACLK`. Response encodings: `00` OKAY, `10` SLVERR, `11` DECERR (`01` EXOKAY never generated).

## 3. Address map

Match rule: `(addr & Sx_MASK) == (Sx_BASE & Sx_MASK)`. Lowest-numbered match wins. No match -> DECERR.

| Port | Base | Mask | Range |
| --- | --- | --- | --- |
| S1 | 0x0000_0000 | 0xFFFF_F000 | 0x0000_0000-0x0000_0FFF |
| S2 | 0x0000_1000 | 0xFFFF_F000 | 0x0000_1000-0x0000_1FFF |
| S3 | 0x0000_2000 | 0xFFFF_F000 | 0x0000_2000-0x0000_2FFF |
| S4 | 0x0000_3000 | 0xFFFF_F000 | 0x0000_3000-0x0000_3FFF |
| S5 | 0x0000_4000 | 0xFFFF_F000 | 0x0000_4000-0x0000_4FFF |
| S6 | 0x0000_5000 | 0xFFFF_F000 | 0x0000_5000-0x0000_5FFF |
| S7 | 0x0000_6000 | 0xFFFF_F000 | 0x0000_6000-0x0000_6FFF |
| S8 | 0x0000_7000 | 0xFFFF_F000 | 0x0000_7000-0x0000_7FFF |
| S9 | 0x0000_8000 | 0xFFFF_F000 | 0x0000_8000-0x0000_8FFF |

- Everything >= 0x0000_9000 is unmapped (default map).
- Address is forwarded **unchanged** (no offset subtraction). `AWADDR`/`ARADDR` are broadcast to all subordinates; only the decoded one sees `VALID`.
- Testbench map variants already used by the directed TB: `MAP_MODE=0` default, `1` relocated 8 KiB S9, `2` overlapping S8/S9. The UVM env must take the map from a config object and the scoreboard decoder must use the same base/mask values.

## 4. Features to verify

### 4.1 Routing and decode
- F-RT-1: A mapped write from either manager reaches exactly the decoded subordinate (AW and W), nothing reaches the others (`VALID` stays low).
- F-RT-2: Same for reads (AR).
- F-RT-3: Address and data pass through unmodified (AWADDR, WDATA, ARADDR) and match what the manager sent.
- F-RT-4: Window boundaries: first/last byte of every window, one below the base, one above the end.
- F-RT-5: Overlapping windows: lowest-numbered output wins.
- F-RT-6: Non-default `Sx_BASE`/`Sx_MASK`, and non-default `ADDR_WIDTH`/`DATA_WIDTH`.
- F-RT-7: The destination is latched at AW/AR handshake; later address changes on the manager do not move the response routing.

### 4.2 Responses
- F-RS-1: B (BRESP) and R (RDATA/RRESP) of the subordinate pass through unchanged to the **originating** manager only (OKAY and SLVERR).
- F-RS-2: In each direction, the manager that does not own the grant sees `BVALID=0`/`WREADY=0`/`AWREADY=0` (write) and `RVALID=0`/`ARREADY=0` (read).
- F-RS-3: Decode miss: no subordinate gets `VALID`; the DUT consumes AW and W by itself and returns `BRESP=11` after both; for reads consumes AR and returns `RRESP=11`, `RDATA=0`. The response stays valid until accepted.
- F-RS-4: Exactly one B per accepted AW+W pair and exactly one R per accepted AR.
- F-RS-5: B is not presented before both AW and W handshakes are done. R is not presented before the AR handshake.
- F-RS-6: Response back-pressure (`BREADY`/`RREADY` low) propagates to the selected subordinate and holds the payload stable.

### 4.3 Write channel behaviour
- F-WR-1: AW before W, W before AW (W waits for AWVALID; once AWVALID is high, W may handshake first if AWREADY is stalled), AW and W in the same cycle.
- F-WR-2: W is accepted exactly once per write (no duplicate beat to the subordinate after the W-done flag is set).
- F-WR-3: W offered alone (no AWVALID) must not handshake.
- F-WR-4: Subordinate that waits for WVALID before asserting AWREADY does not deadlock.

### 4.4 Arbitration (read and write are independent arbiters)
- F-AR-1: Idle + only one manager requests -> that manager wins.
- F-AR-2: Idle + both request in the same cycle -> M1 wins (fixed priority); M2 holds VALID and is served after the grant is released.
- F-AR-3: Grant is registered, so a new request needs at least one cycle to get the grant before its address handshake. `AWREADY`/`ARREADY` toward the manager are gated by the forwarded `VALID`; an idle or non-granted manager never sees READY.
- F-AR-4: Write grant is held from the grant until `BVALID && BREADY`; read grant until `RVALID && RREADY`. A new owner is selected only after that.
- F-AR-5: Read and write grants are independent: M1 can read while M2 writes (and vice versa), concurrently.
- F-AR-6: If a manager requests while the other owns the direction, it is not accepted (no READY, no handshake) until the owner finishes. No fairness guarantee: starvation of M2 under continuous M1 traffic is expected (not a bug).
- F-AR-7: A stalled B/R blocks the same direction for **all** subordinates (including other targets and the other manager).

### 4.5 Reset
- F-RST-1: Async assert of `ARESETn` clears grants, busy flags, stored write/read destinations, W-done and read-seen flags. All DUT-driven VALID/READY toward managers are low during reset.
- F-RST-2: Pending/incomplete transactions are abandoned (no B/R emitted later for them); the next access after reset succeeds normally and M1 is the idle default.
- F-RST-3: Scoreboard drops all in-flight expectations at reset.
- Constraint: managers keep request VALIDs low during reset and endpoints are reset coherently (some forwarding is combinational).

### 4.6 Protocol (assertion/checker level, at M1, M2, S1..S9 and internal `M` optional)
- P-1: VALID stays high with stable payload (AWADDR, WDATA, ARADDR, RDATA, RRESP, BRESP) until READY (manager side and subordinate response side).
- P-2: Once VALID is asserted it is not dropped before the handshake.
- P-3: No X/Z on VALID/READY after reset release; payload not X when VALID is high.
- P-4: BRESP/RRESP never `01`.
- P-5: Max one outstanding write and one outstanding read at each DUT boundary of the shared bus: no AW handshake between an AW handshake and its B handshake; same for AR/R. A master-side UVC protocol rule (the sequence layer must enforce it; violating it is illegal stimulus).
- P-6: At most one subordinate has AWVALID (and one has WVALID, one has ARVALID) high at any time.

## 5. UVC requirements (reusable `axi4l` UVC)

Parameterised on `ADDR_WIDTH`/`DATA_WIDTH` (default 32/32). One agent class, `is_active` + `mode` configurable.

### 5.1 Sequence item (`axi4l_item`)
- `kind` (WRITE/READ), `addr`, `data` (write data or captured read data), `resp`.
- Write timing knobs: `aw_delay`, `w_delay`, `aw_w_order` (AW_FIRST / W_FIRST / SAME_CYCLE), `bready_delay`.
- Read timing knobs: `ar_delay`, `rready_delay`.
- Subordinate-mode knobs: `awready_delay`, `wready_delay`, `arready_delay`, `b_delay`, `r_delay`, `resp` to return (OKAY/SLVERR).
- Timestamps `aw_time`, `w_time`, `b_time`, `ar_time`, `r_time`, plus `mgr_id` / `sub_id` tag set by the agent.

### 5.2 Master agent (drives M1/M2 as a manager)
- Driver: issues one write and/or one read at a time. Write and read drivers are separate threads so concurrent read + write from the same manager is possible; each direction waits for its own B/R before the next item (single outstanding).
- Holds VALID and payload until READY. Supports AW/W skew and response back-pressure.
- Reset-aware: drops VALIDs on reset, aborts current item, flags it as "aborted" to the sequencer.
- Config: interface handle, `is_active`, `agent_id` (1 or 2), enable per-direction.

### 5.3 Slave agent (drives S1..S9 as a subordinate)
- Responder with memory model (word array, per-subordinate signature so a misroute is visible) and optional "error window" returning SLVERR.
- Independently programmable `AWREADY`/`WREADY`/`ARREADY` delays and `B`/`R` response delays; holds responses stable until accepted.
- Must cover the "wait for WVALID before AWREADY" behaviour and "AWREADY before WVALID" behaviour (see F-WR-4).
- Config: `agent_id` (1..9), delay modes (zero / fixed / random), `slverr_enable`, base/mask only for local offset use (memory index).

### 5.4 Monitor (in every agent, always on; passive-only mode supported)
- One monitor per port: M1, M2, S1..S9 (11 monitors).
- Reconstructs write transactions (AW + W + B) and read transactions (AR + R) from handshakes; sends them through an analysis port. Write item is published at the **B handshake**, read at the **R handshake**. Also publish the individual AW/W/AR handshake events with a timestamp (needed for arbitration and latency checks).
- Reset event published to the scoreboard.
- Protocol checks P-1..P-6 live here or in an SVA bind module (recommended: SVA on the interface, so formal/blk_tb can reuse them).

### 5.5 Env / config
- `axi_ic_env`: 2 master agents, 9 slave agents, 11 monitors, scoreboard, coverage, virtual sequencer, reset agent (or reset task in the virtual interface).
- `axi_ic_cfg`: address map (9x base/mask), widths, `MAP_MODE`, per-agent delay profiles.
- TB top: clock/reset generation, interface instances `managers[2]` and `peripherals[9]` as in README, DUT with `+timescale 1ns/1ps`.

## 6. Scoreboard specification

Reference model driven only by monitors (no DUT internals). Inputs: monitor streams from M1, M2 and S1..S9.

### 6.1 Predictor
- Decode function identical to the RTL rule (base/mask, lowest match wins, unmapped -> ERR).
- Write: when manager `m` completes AW+W with address `a` and data `d`, expected subordinate `s = decode(a)`. Queue expected `{a, d, mgr=m}` per subordinate. For unmapped, expect nothing on any subordinate and a `DECERR` B at manager `m`.
- Read: same with address; for unmapped expect `RRESP=DECERR`, `RDATA=0`.
- Response: expected B/R at manager `m` = the response observed at subordinate `s` for that transaction (OKAY/SLVERR and RDATA unchanged).
- Because only one write and one read can be outstanding across both managers, the expected queues have depth one per direction. Use a shared per-direction "owner" register `{mgr, sub, addr}` rather than a deep queue; a second request while an owner is active is a stimulus bug (flag as `UVM_ERROR` from the scoreboard).

### 6.2 Checks

| ID | Check |
| --- | --- |
| SB-1 | Each write seen at a subordinate (addr, data) equals one expected write for that subordinate, and no write is seen at any other subordinate. |
| SB-2 | Each read seen at a subordinate has the expected address and appears only at the decoded subordinate. |
| SB-3 | Unmapped write/read produces no activity on S1..S9 and a DECERR response (`RDATA=0` for reads) to the right manager. |
| SB-4 | B/R response at a manager equals the response of the targeted subordinate (BRESP, RRESP, RDATA) and goes to the requester only. |
| SB-5 | Arbitration: when both managers have VALID in the same direction while that direction is idle, M1 is served first; M2 is served only after M1's B/R handshake. |
| SB-6 | Grant lock: no handshake of the other manager in the same direction between the owner's AW/AR handshake and its B/R handshake. |
| SB-7 | Independent directions: concurrent read and write from different managers both complete and are not blocked by each other. |
| SB-8 | One B per write, one R per read; no extra or missing responses. At end of test the expected queues/owners are empty. |
| SB-9 | Data integrity (end-to-end): a write followed by a read of the same mapped address returns the written data (using the slave memory model as the reference memory); also checks that other subordinates' memories are untouched (signature check). |
| SB-10 | Latency/ordering sanity: request-to-grant is >= 1 cycle; B not before both AW and W; R not before AR; ordering of events at the DUT matches monitor timestamps. |
| SB-11 | Reset: on a reset event clear all expectations; no response seen after reset for an abandoned transaction; first transaction after reset succeeds. |
| SB-12 | No handshake on any manager port (READY or response VALID) for the non-granted manager. |
| SB-13 | End-of-test: no outstanding transaction, no response pending, counters (issued vs completed) balanced per manager and per subordinate. |

### 6.3 Not checked (by design)
- Fairness/starvation, fixed response latency, throughput, timeout/retry, byte strobes, protection bits, bursts, IDs, outstanding > 1, reordering, CDC.

## 7. Functional coverage

- Cross manager (M1/M2) x direction (W/R) x subordinate (S1..S9) x response (OKAY/SLVERR) - 72 mapped bins.
- Decode: unmapped read/write per manager; boundary addresses (first/last/below/above) per window; overlap hit in `MAP_MODE=2`.
- Arbitration: M1 only, M2 only, both same cycle, M2 first then M1 arrives while M2 owns, per direction.
- Concurrency: W by M1 + R by M2, W by M2 + R by M1, W + R by the same manager, W + R by the same manager and different subordinates.
- Write ordering: AW first, W first, same cycle, AW-to-W skew (0, 1, N cycles).
- Back-pressure: AWREADY/WREADY/ARREADY stall, B/R stall (BREADY/RREADY low), stalled response while the other manager waits.
- Reset: during idle, during AW pending, during W only, between AW and B, during stalled R/B.
- Data: min/max/alternating patterns on WDATA and RDATA; address LSBs (the interconnect does not care about alignment).
- Parameters: 32/32 default, one narrow-addr/wide-data case (24/64 as in README).

## 8. Test plan (initial list)

1. `sanity_test` - each manager, each subordinate, one write + read back.
2. `all_targets_test` - sweep M1/M2 x S1..S9, write then read back with data checking.
3. `decode_boundary_test` - boundaries and unmapped addresses (both managers).
4. `aw_w_skew_test` - AW-first / W-first / same-cycle with random skew; wait-for-W subordinate.
5. `resp_backpressure_test` - random BREADY/RREADY stalls, SLVERR from subordinates.
6. `arb_write_test`, `arb_read_test` - simultaneous requests, M1 priority, grant lock through stalled B/R, M2 starvation under repeated M1 (expected).
7. `concurrent_rw_test` - read and write owned by different managers at the same time.
8. `reset_test` - reset in the middle of write/read (incomplete AW/W, stalled B/R) and recovery.
9. `map_mode_test` - relocated S9, overlapping S8/S9, non-default widths.
10. `random_test` - constrained-random mix of all knobs with scoreboard + coverage; regression with multiple seeds.

## 9. Observations from RTL review (check with the designer)

These are behaviours that the scoreboard and tests must model exactly; some may be considered limits rather than bugs.

- O-1: The RTL README states managers must obey the single-outstanding limit; the DUT does **not** block a second AW/AR (the core does not enforce it). Treat violations as illegal stimulus, not as DUT bugs; do not generate them in the normal tests. A negative test can be added later if the designer agrees on the expected behaviour.
- O-2: `AWADDR`/`ARADDR` to subordinates are broadcast from the live manager bus (not latched). After the AW/AR handshake, the address on the subordinate side may change if the manager changes it. Compare subordinate addresses **at the handshake** only.
- O-3: Decode miss accepts AW (`AWREADY=1`) and W (`WREADY=1`) without waiting for the manager's VALID; the handshake still needs `VALID && READY`, so no false transfer is observed, but READY toggles high while idle on a miss address. Do not flag READY high without VALID as an error.
- O-4: `BRESP`, `RDATA`, `RRESP` are driven to **both** managers; only meaningful when the corresponding VALID is high. Do not check payload when VALID is low.
- O-5: The datasheet in the pasted text describes the **2x3** version (3 windows). For 2x9 extend all statements to 9 windows; the structure and the limits are identical.
- O-6: Fixed priority only chooses between managers when the arbiter is idle; an M2 request that arrives first keeps the grant until its B/R, even if M1 requests later.

## 10. Subordinate-side behaviour (from the `axi_lite_slave_wrapper` datasheet)

Each of S1..S9 is expected to be an `axi_lite_slave_wrapper` in front of a peripheral. The slave agent should behave like it:

- SW-1: Per port, one AW slot, one W slot and one AR slot. The next request in a direction is blocked until B/R is accepted (so the subordinate side is also single outstanding).
- SW-2: AW and W are captured independently, in either order or together. The backend access starts only after both are held; AWREADY may come before WVALID.
- SW-3: B/R are registered and held stable until accepted. They stay valid after the backend done/error pulse has ended.
- SW-4: Responses are only OKAY (00) or SLVERR (10). A subordinate never returns DECERR or EXOKAY; DECERR comes only from the interconnect decode miss. The slave agent must not generate DECERR.
- SW-5: Read and write on the same subordinate can overlap (M1 reads while M2 writes the same S). There is no same-address hazard handling, so the scoreboard must not assume a read-after-write order for concurrent accesses to the same address; only check a read-back when the write has completed (B accepted) before the read starts.
- SW-6: The bus address is not offset. The slave memory index is `addr - Sx_BASE` (or `addr & ~Sx_MASK`).
- SW-7: Latency is set by the backend; there is no fixed response latency and no timeout (a missing done blocks that direction).
- SW-8: Reset cancels pending bus work but does not undo committed peripheral effects. The slave memory model must keep its contents across reset; only in-flight state is cleared.

Slave agent knobs implied: `awready_delay`, `wready_delay`, `arready_delay`, a backend latency (`wr_latency`, `rd_latency`), `slverr` injection and a `b_hold`/`r_hold` stall.

## 11. Implemented verification environment

Location: `blk_tb/sim_tb/` (env, tests, seq, tb) and `verif/uvm/common/axi4l_uvc/` (reusable UVC). Run: `cd blk_tb/sim_tb && ./run.sh -t <test> -s <seed> [-w]`; `./clean.sh` removes outputs.

```
verif/uvm/common/axi4l_uvc/   pkg, types, item, event, agent_cfg, sequencer, master/slave driver,
                              monitor (transactions only), agent, seq_lib, axi4l_protocol_checker.sv (SVA, per port)
blk_tb/sim_tb/
  tb/    axi_ic_tb_top.sv, axi_ic_rst_if.sv (mid-test reset), axi_ic_sva_checker.sv (arbitration / grant lock)
  env/   axi_ic_cfg, axi_ic_scoreboard, axi_ic_coverage, axi_ic_vseqr, axi_ic_env, axi_ic_pkg
  seq/   axi_ic_vseq_lib.sv (sweep, decode, arb, conc, stress, reset)
  tests/ base, smoke, sweep, decode, arb, conc, stress (+NUM_ITEMS=n), reset, full
```

Policy: the RTL is never modified by the testbench. Any mismatch is reported as a finding for the designer.

### Check allocation

| Checks | Where | Notes |
|---|---|---|
| P-1/P-2 VALID held and payload stable, P-3 no X, P-4 no EXOKAY, P-5 one outstanding, P-6 response ordering, F-RST-1 outputs low in reset | `axi4l_protocol_checker` SVA, on all 11 ports | Reported as `SVA_PROTO` |
| Grant lock, M1 priority, no READY/response without a grant | `axi_ic_sva_checker` SVA | Reported as `SVA_ARB`; models busy/owner per direction from boundary signals only |
| Routing to the decoded subordinate, address/data/response pass-through, DECERR on decode miss, response after request, no overlapping accesses per direction, read data vs shadow memory, reset flush, nothing left unmatched | `axi_ic_scoreboard` | IDs `SB-ROUTE`, `SB-PASS`, `SB-DECERR`, `SB-ORDER`, `SB-LOCK`, `SB-DATA`, `SB-LEFT` |
| Transaction extraction, cycle stamps (`req_cycle`, `rsp_cycle`) | `axi4l_monitor` | No checking |
| Coverage: access (manager x kind x target x resp), address/data corners, skew/latency/stall, arbitration, concurrency, reset | `axi_ic_coverage` | Functional coverage is collected by `run.sh` (`-coverage functional`) |

Read-data checks are skipped when a write to the same word raced with the read (SW-5), or when a reset left the word unknown (write abandoned by reset); the skip count is printed.

