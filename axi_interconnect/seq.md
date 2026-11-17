
A passing stress test means four random traffic streams ran at once on the real RTL, and the scoreboard and SVA checkers raised no errors. The source is `axi_ic_stress_vseq` in `axi_ic_vseq_lib.sv`.

Traffic applied
- Four threads run in parallel: M1 writes, M2 writes, M1 reads and M2 reads.
- Each thread issues `NUM_ITEMS` back-to-back transactions, 200 by default, so about 800 in total. Override it with `+NUM_ITEMS=n`.
- Writes carry random data. Reads and writes are fully concurrent, with no ordering between the threads.

**Addresses**
- About 90% go to mapped targets, chosen from a "hot" address set across all 9 subordinates (S1..S9).
- About 10% go to unmapped addresses (`unmapped_pct`), which should return DECERR.

**Subordinate behaviour** (re-randomised once at the start of the test)
- Response latency is 0 to 6 cycles, with a random low and high bound per slave.
- AWREADY, WREADY and ARREADY are randomly early or late.
- In about a third of the slaves, 0 to 30% of responses are SLVERR.

**Manager behaviour**
- The UVC's own random start delays and random handshake timing apply.

**Scenarios this covers**
- M1 and M2 contending for the write and read arbiters, including the M1-priority and grant-lock behaviour.
- Concurrent read and write with different owners.
- All 9 destinations, plus DECERR writes and reads.
- SLVERR passing through to the manager.
- Backpressure and stalls on B and R, and AW/W skew.
- Back-to-back transactions after each response.
- Read-data checks against the memory model.

**Checked on every access**
- Correct routing and address/data pass-through.
- Response matches the target, DECERR for unmapped addresses.
- Grant ownership and lock.
- Protocol rules: valid/payload stability, one outstanding per direction, B only after AW and W, R only after AR, no EXOKAY.
- No leftover transactions.

**What it does not cover**
- Reset mid-traffic. That is `axi_ic_reset_test`.
- Each test seed uses one slave-timing profile, so vary the seed to get other profiles.
- It only proves that the interconnect passed these random scenarios. It doesn't prove that a missed corner case isn't there. Check the coverage percentages to see which scenarios were actually hit.
- The checkers haven't yet been shown to catch a fault, because no bug has been injected.