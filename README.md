# Clinical MRI DBMS — reproduction guide (SSMS)

> **CO3021 – Database Management Systems · Group 02 · HCMUT**
> Workload-driven evaluation of **Microsoft SQL Server 2025** on 575 patients and 48,345 lumbar-spine MRI slices.

**Read in this order:** 1) the website → 2) the report (PDF) → 3) this repository.

| | Link |
|---|---|
| 1. Website (summary, one page per role) | <https://qmarcusv.github.io/DBMS_TA_Group2/> |
| 2. Full report (PDF) | [`report/DBMS_TA_Group2_report.pdf`](report/DBMS_TA_Group2_report.pdf) (also linked from the website) |
| 3. This repository | SQL scripts + the instructions below |

This README only explains how to **rebuild the results with SQL Server Management Studio (SSMS)**. The explanations, plans and conclusions are in the report.

---

## 1. Contents

```
README.md
report/DBMS_TA_Group2_report.pdf   the full report (67 pages)
data/SpineMRI_DBMS.bak        backup of the finished database (53 MB)
sql/
  00_canonical_queries.sql    the three queries Q1, Q2, Q3 shared by all roles
  01_schema_definition.sql    Role 1  - DDL of the three tables
  02_bulk_import.sql          Role 1  - how the CSV files were loaded (optional)
  02_role_2_indexing_experiments.sql
  03_role_3_support.sql       Role 3  - Hash/Loop comparison, statistics
  03_role_3_experiments.sql   Role 3  - hints, Seek vs Scan, cut-off, spill, Adaptive Join
  04_transactions_recovery_role4.sql
  04b_role4_atomicity_contrast_and_delayed_durability.sql
  05_concurrency_control_role5.sql
  role5/                      Role 5  - two-session deadlock / RCSI / Snapshot scenarios
docs/                         the website (GitHub Pages), with a copy of the report PDF
```

## 2. Requirements

* **SQL Server 2025 (version 17.x)**, Developer edition is free, and **SSMS 21/22**. The backup was made on SQL Server 2025, so it cannot be restored on 2022 or older.
* Run everything on a **development instance**: some scripts use `DBCC DROPCLEANBUFFERS` and clear the procedure cache of this database, and the Role 4 script creates and drops a scratch database.

## 3. Restore the database (once)

**With the SSMS wizard.** Connect to your instance → right-click **Databases → Restore Database…** → **Device** → **…** → **Add** → select `data/SpineMRI_DBMS.bak` → **OK**. Tick *Overwrite the existing database* if it already exists.

**With T-SQL** (change the three paths):

```sql
RESTORE DATABASE SpineMRI_DBMS
FROM DISK = N'C:\path\to\data\SpineMRI_DBMS.bak'
WITH MOVE N'SpineMRI_DBMS'     TO N'C:\SQLData\SpineMRI_DBMS.mdf',
     MOVE N'SpineMRI_DBMS_log' TO N'C:\SQLData\SpineMRI_DBMS_log.ldf',
     REPLACE, STATS = 10;
```

**Check the restore** (expected: 575, 48,345, 48,345):

```sql
USE SpineMRI_DBMS;
SELECT (SELECT COUNT(*) FROM Patients)       AS Patients,
       (SELECT COUNT(*) FROM MRI_Scans)      AS Scans,
       (SELECT COUNT(*) FROM Image_Features) AS Features;
```

## 4. How to run a script

1. **File → Open → File…** and open the script.
2. For plans: **Query → Include Actual Execution Plan** (`Ctrl+M`). The Role 2 and Role 3 scripts switch on `SET STATISTICS IO, TIME` themselves: read logical reads and times in the **Messages** tab (for other scripts run `SET STATISTICS IO ON; SET STATISTICS TIME ON;` first). If you reconnect, the setting is lost: run it again.
3. **Select the block you want** (the scripts are divided into numbered sections with comments) and press **F5**. Do not run a whole experiment file at once unless it says so.
4. Hover over an operator in the **Execution plan** tab to see *Estimated Subtree Cost*, estimated and actual rows. Press `F4` on the first operator for the memory grant and the “Reason for early termination”.
5. Every experiment that creates objects removes them again (`ROLLBACK`/`DROP`). Section 8 of `03_role_3_experiments.sql` checks that the database is back to its baseline.

Cold-cache protocol used by the scripts before a measurement (dev instance only):

```sql
CHECKPOINT; DBCC DROPCLEANBUFFERS;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
```

## 5. Results you should obtain

Page counts reproduce exactly. Estimated rows depend on sampled statistics, and times, memory grants and the degree of parallelism depend on your machine; plan shapes and the ratios between alternatives stay the same.

| Role | Script / section | Expected result |
|---|---|---|
| all | `00_canonical_queries.sql` | Q1 → 65 rows, Q2 → 15 rows, Q3 → 3 rows |
| 2 | `02_role_2_indexing_experiments.sql` | Q1/Q2: **1,880 → 6** logical reads on `MRI_Scans`; Q3 baseline 3,909 + 1,972 reads |
| 3 | `03_role_3_experiments.sql` §1 | Q1 estimated subtree cost ≈ 1.47, scan = 98 % of it; 1,880 reads |
| 3 | §2 (hints) | Q3 forced `LOOP JOIN` ≈ 3.4 × the cost of `HASH JOIN`; ≈ 148,000 reads on `MRI_Scans` |
| 3 | §4 (Seek vs Scan) | Q1 with the temporary index: 210 reads; range `PatientID <= '0100'` → scan + Hash Match again |
| 3 | §5 (cut-off) | `Reason For Early Termination = Time Out`; counter `timeout` +1 (run with `Ctrl+M` **off**) |
| 3 | §6 (spill) | yellow warning on Sort (spill level 2) and Hash Match (level 3) |
| 3 | §7 (Adaptive Join) | operator *Adaptive Join*, threshold ≈ 1,025.83, Actual Join Type = HashMatch |
| 4 | `04b_…` Part A | without a transaction: 1 orphan `Patients` row; with `BEGIN TRAN`/`ROLLBACK`: 0 / 0 |
| 4 | `04b_…` Part B | 5,000 commits: delayed durability is several times faster than full durability |
| 5 | `role5/` | see section 6 |

## 6. Role 5 — two sessions

Open **two query windows** (= two sessions). Press **F5** in window A, then switch to window B and press **F5** while A is still waiting.

1. Run `role5/00_setup.sql` once.
2. For each scenario open the A file in window 1 and the B file in window 2; run `role5/99_reset.sql` after **every** scenario.

| Scenario | Window A (F5 first) | Window B | You see |
|---|---|---|---|
| Deadlock | `01_deadlock_A.sql` | `01_deadlock_B.sql` (within ≈ 4 s) | one session gets error **1205** |
| Deadlock, priority | `01_deadlock_A.sql` with `SET DEADLOCK_PRIORITY LOW;` | `01_deadlock_B.sql` | A becomes the victim |
| Deadlock graph | `01_deadlock_graph.sql` | | XML to save as `.xdl` and open in SSMS |
| Lock timeout | `04_queries_A_writer.sql` | `01_lock_timeout_B_Q1.sql` | error **1222** |
| Locking | `02_rcsi_A_writer.sql` | `02_rcsi_B_reader.sql` | reader waits ≈ 8 s (`LCK_M_S`) |
| RCSI | run `02_rcsi_0_enable_row_versioning.sql`, then `02_rcsi_A_writer.sql` | `02_rcsi_B_reader.sql` | reader waits 0 ms |
| Snapshot | `02_rcsi_A_writer.sql` | `02_snapshot_B_reader.sql` | second read still returns the old value |
| Update conflict | `02_snapshot_C_update_conflict.sql` | `02_rcsi_A_writer.sql` | error **3960** |
| Q1–Q3 under a writer | `04_queries_A_writer.sql` | `04_queries_B_Q1.sql` / `_Q2` / `_Q3` | wait ≈ 8 s (locking) vs 0 ms (RCSI) |

Index state for the last scenario: `04_queries_index_baseline.sql` (primary keys only) or `04_queries_index_covering.sql` (Role 2 index). Optional third window: `03_lock_monitor.sql` while A waits shows the waits-for edges, the lock table and the version store.

## 7. Notes

* `02_bulk_import.sql` and `01_schema_definition.sql` document how the database was built from the cleaned CSV files; they are **not needed** after the restore.
* The Python pre-processing and feature-extraction code is described in Chapter 1 of the report and is not part of this repository.
* The website is plain HTML, CSS and JavaScript in `docs/` and is served by GitHub Pages (*Settings → Pages → Branch `main`, folder `/docs`*).
