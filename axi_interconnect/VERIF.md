# AXI4-Lite 2x9 Interconnect: Verification Status

Companion to [SPECS.md](./SPECS.md) (what to verify). This file records what has been built, how to run it, and what is left.

Policy: the testbench never modifies the RTL. A mismatch is reported as a finding for the designer.

## 1. What has been done

### 1.1 Documentation
- [SPECS.md](./SPECS.md): boundary-level spec (signals, address map, features, scoreboard checks SB-1..13, coverage, test plan, RTL observations O-1..O-6, subordinate behaviour SW-1..8, check allocation).

### 1.2 Reusable AXI4-Lite UVC (`verif/uvm/common/axi4l_uvc/`)
- Single `axi4l_agent` class, master or slave mode (cfg-selected), active or passive.
- Master agent: separate write and read sequencers/threads, so a read and a write can be in flight together. Reset-aware, with a watchdog timeout.
- Slave agent: responder with memory (persists across reset; unwritten words read `signature ^ address`). Knobs: READY delays, early READY, B/R delay, SLVERR injection (random % or address window).
- Monitor: transaction extraction only (`item_ap` at B/R, `ev_ap` per handshake and reset). Items carry `aw/w/b/ar/r_cycle`, `req_cycle`, `rsp_cycle`.
- Sequences: directed write/read (with `start_delay`) and random write/read.
- Widths are compile-time defines (`AXI4L_ADDR_W`, `AXI4L_DATA_W`, default 32/32).
- `axi4l_protocol_checker.sv`: per-port SVA (rules P-1..P-6, F-RST-1), reports through UVM.

### 1.3 Interconnect testbench (`design/axi_interconnect/blk_tb/sim_tb/`)

| Area | File(s) | Content |
|---|---|---|
| Top | `tb/axi_ic_tb_top.sv` | 100 MHz clock, power-on reset plus mid-test reset, 2 manager and 9 subordinate interfaces, DUT, SVA instances |
| Reset | `tb/axi_ic_rst_if.sv` | `pulse(n)` for mid-test reset |
| SVA | `tb/axi_ic_sva_checker.sv` | M1 priority, grant lock, no READY/response without a grant |
| Env | `env/axi_ic_env.sv`, `axi_ic_cfg.sv` | 2 master agents (M1, M2), 9 slave agents (S1..S9), address map and decode model |
| Scoreboard | `env/axi_ic_scoreboard.sv` | Routing, address/data/response pass-through, DECERR on decode miss, response ordering, per-direction lock, read data vs shadow memory, reset flush, nothing left unmatched |
| Coverage | `env/axi_ic_coverage.sv` | 6 covergroups: access, address/data corners, timing, arbitration, concurrency, reset |
| Virtual sequencer | `env/axi_ic_vseqr.sv` | Handles to all manager sequencers, slave cfgs, reset interface |
| Virtual sequences | `seq/axi_ic_vseq_lib.sv` | sweep, decode, arb, conc, stress (4 threads), reset |
| Tests | `tests/` | smoke, sweep, decode, arb, conc, stress, reset, full |
| Scripts | `run.sh`, `clean.sh`, `file.f` | Compile and run with Xcelium plus UVM CDNS-1.2; functional coverage on |

### 1.4 Check allocation

| Layer | Checks |
|---|---|
| SVA (cycle-accurate) | VALID/payload stability, no X, no EXOKAY, one outstanding per direction, B only after AW and W, R only after AR, outputs low in reset, grant lock, M1 priority |
| Scoreboard (transaction) | Routing, pass-through, DECERR, ordering, lock, read-data shadow, reset, leftovers |
| Monitor | None (extraction only) |

### 1.5 Results so far
- Clean RTL: full test passes on seeds 3-12 and 21-25; the other tests pass on seeds 1 and 5. 0 UVM errors, no SVA failures.
- Coverage, one full-test run: access about 94-98%, timing about 94%, arbitration about 96%; address/data, concurrency and reset 100%. Holes not yet analysed.
- Not demonstrated: that the checkers catch a real bug (see 2.1).

## 2. What can be done next

### 2.1 Proving the checks (highest value)
- Fault-injection of the checkers against copies of the RTL kept outside the repo (swap arbiter priority, misroute one subordinate, drop a response, corrupt data, break the lock), confirming each is flagged. The RTL in the repo stays untouched.
- Check every SVA fires at least once (assertion coverage / cover properties) and add `cover property` for key scenarios.

### 2.2 Coverage closure
- Analyse the remaining holes (`imc`) and add directed sequences or constraints for them.
- Add `cover` for arbiter corner cases: M2 request one cycle after M1, back-to-back grants, same-cycle request.
- Merge coverage across seeds and set a closure target.

### 2.3 Configurations
- Non-default address maps (`MAP_MODE` variants), overlapping windows (lowest wins), non-aligned base or mask. The tb top and checkers currently use the default map.
- Other widths (24/64 was run on the smoke test; run the full regression).
- Pass the map to the DUT and the cfg from one place.

### 2.4 Scenarios not covered yet
- Reset in each specific phase (between AW and W, during B/R stall, back-to-back with a new request on release).
- Long B/R stalls and very slow subordinates (watchdog behaviour, O-x items).
- Byte strobes and protection signals, if the interface carries them.
- Back-to-back traffic at maximum rate and long random soak with many seeds.
- Unmapped access combined with simultaneous mapped access on the other direction.

### 2.5 Infrastructure
- Regression script: all tests x N seeds, summarise pass/fail and merged coverage.
- CI hook for the regression.
- Waves: `./run.sh -w` works; add a standard SimVision setup.
- Run the UVC unchanged against the 1x9 core block and the slave wrapper to prove reuse.
- Optional: formal on the SVA files (they are reusable) for the arbiter and lock properties.
- Optional: register-model-style peripheral model if the subordinates become real wrappers.

### 2.6 Open points for the designer
- See SPECS.md section 9 (O-1..O-6). Any scoreboard or SVA failure on the real RTL should be triaged against the spec before blaming the DUT or the testbench.

## 3. How to run

```
cd design/axi_interconnect/blk_tb/sim_tb
./run.sh -t axi_ic_full_test -s 1          # test, seed
./run.sh -t axi_ic_stress_test -s 7 -w     # with waves (waves.shm)
export AXI4L_ADDR_W=24 AXI4L_DATA_W=64     # other widths
./clean.sh
```

Tests: `axi_ic_smoke_test`, `sweep`, `decode`, `arb`, `conc`, `stress` (`+NUM_ITEMS=n`), `reset`, `full`.
Reports: the scoreboard prints counts and read-data check/skip totals; the coverage model prints a percentage per covergroup; failures use IDs `SB-*`, `SVA_PROTO`, `SVA_ARB`, `VSEQ`.

## Formal
A separate JasperGold environment lives in `blk_tb/formal_tb/` (see its README): progressive assumption/assertion defines, profiles p0..p7. Independent of the UVM bench.
