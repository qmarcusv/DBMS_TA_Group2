# Role 5.2 — Deadlock & MVCC / RCSI

Report chapter: `report/source/chapters/06-concurrency-role5-2.tex`
(own chapter, placed right after the Role 5.1 chapter `06-concurrency-role5.tex`).

## Demo in SSMS (two query windows = two sessions)

1. Run `00_setup.sql` once (log helper, row versioning OFF).
2. For each scenario open the **A** file in window 1 and the **B** file in window 2.
   Press F5 in A, then switch and press F5 in B while A is waiting.
   *Messages* tab = timestamps, *Results* tab = values, `ElapsedMs`, `LockWaitMs`.
3. Optional window 3: `03_lock_monitor.sql` while A waits (waits-for edges, lock table,
   deadlock priority, version store).
4. Run `99_reset.sql` after **every** scenario.

| # | Session A (F5 first) | Session B | Shows |
|---|---|---|---|
| 01 | `01_deadlock_A.sql` | `01_deadlock_B.sql` (within ~4 s) | Deadlock, victim gets Msg 1205 (lowest log used) |
| 01 run 2 | `01_deadlock_A.sql` with `SET DEADLOCK_PRIORITY LOW;` | `01_deadlock_B.sql` | A becomes the victim: priority beats log cost |
| 01 graph | `01_deadlock_graph.sql` | | Deadlock graph XML from `system_health` → save as `.xdl` |
| 01b | `04_queries_A_writer.sql` | `01_lock_timeout_B_Q1.sql` | `LOCK_TIMEOUT 3000` → error 1222 (partial result) |
| 02 locking | `02_rcsi_A_writer.sql` | `02_rcsi_B_reader.sql` | RCSI OFF: reader waits ~8 s (`LCK_M_S`) |
| 02 RCSI | run `02_rcsi_0_enable_row_versioning.sql`, then `02_rcsi_A_writer.sql` | `02_rcsi_B_reader.sql` | RCSI ON: reader waits 0 ms, reads last committed version |
| 02c | (versioning ON) `02_rcsi_A_writer.sql` | `02_snapshot_B_reader.sql` | Snapshot = transaction-level snapshot |
| 02d | `02_snapshot_C_update_conflict.sql` (F5 first) | `02_rcsi_A_writer.sql` | Snapshot update conflict, error 3960 |
| 04 | `04_queries_A_writer.sql` | `04_queries_B_Q1.sql` / `_Q2` / `_Q3` | How the canonical queries behave under a concurrent write |

Scenario 04 matrix: switch index state with `04_queries_index_baseline.sql` (PK only, as in the
backup) or `04_queries_index_covering.sql` (Role 2 covering index), and mode with
`99_reset.sql` (locking) or `02_rcsi_0_enable_row_versioning.sql` (RCSI). Run each B file once
alone (lock footprint) and once while the writer waits (blocking).

## Evidence

- `evidence/deadlock_run1_priority_normal.xdl`, `evidence/deadlock_run2_A_priority_low.xdl`:
  open in SSMS for the graphical Deadlock Graph; screenshot run 1 to
  `report/image/role_5/role5_deadlock_graph_ssms.png` (placeholder shown until then).
- `evidence/run_logs/`: raw `sqlcmd` output of every run used in the report
  (`lock*`/`rcsi*` = Experiment 2, `dl1`/`dl2` = deadlock runs, `04_query_matrix/` = Q1–Q3).

Note: the `system_health` event file is flushed asynchronously — if the newest deadlock is not
listed yet, wait a minute and run `01_deadlock_graph.sql` again. In `sqlcmd` use `-I`
(QUOTED_IDENTIFIER ON), which SSMS enables by default.
