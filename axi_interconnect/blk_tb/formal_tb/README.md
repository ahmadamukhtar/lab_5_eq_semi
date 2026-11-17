# Formal environment (JasperGold) – axi4_lite_2x9_interconnect

Boundary-level formal, separate from the UVM bench (`../sim_tb`). It reads only the RTL; no sim files are shared.

## Layout
| File | Purpose |
|---|---|
| `tb/fv_ic_top.sv` | Wrapper: DUT with free manager/subordinate ports, instantiates assumes + props |
| `tb/fv_mgr_assume.sv` | Assumptions on the manager side (drive M1/M2): A = legal, B = optional restrictions |
| `tb/fv_sub_assume.sv` | Assumptions on the subordinate side (drive S1..S9): A = legal, B = optional restrictions |
| `tb/fv_ic_props.sv` | Reference model, assertions (by define group) and covers |
| `tb/fv_ic_pkg.sv` | Address-decode reference function (default map) |
| `tool/jg.tcl`, `run.sh` | JasperGold flow and profiles |

## Run
`./run.sh [-p p0..p7] [-d "EXTRA DEFINES"] [-g]` (env `FV_TIME`, default 600s; `JG` overrides the binary). Logs: `jg_<profile>.log`.

## Defines
- Manager restrictions: `FV_ONE_MGR FV_NO_WRITE FV_NO_READ FV_MAPPED_ONLY FV_UNMAPPED_ONLY FV_ONE_TARGET (FV_DEST_IDX=n) FV_ALIGNED FV_MGR_RSP_READY FV_W_WITH_AW`
- Subordinate restrictions: `FV_SUB_NO_STALL FV_SUB_FAST_RSP FV_SUB_NO_ERR`
- Assertion groups: `FV_ASRT_PROTO FV_ASRT_ARB FV_ASRT_ROUTE FV_ASRT_RESP FV_COVER` (`FV_ASRT_ALL` = all; the profiles enable all)

## Profiles (fast to full)
p0 one mgr, write-only, one target, no stalls · p1 write-only all targets · p2 read-only · p3 one mgr read+write · p4 two mgrs, no stalls · p5 two mgrs, mapped · p6 unmapped only (DECERR) · p7 unrestricted.

## Status
p0 and p7 run: all 144 assertions proven, no CEX; covers reachable (except those excluded by a profile's restrictions).
Not modelled: mid-run reset (`reset -expression` covers initial reset only).
