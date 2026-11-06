-- ============================================================================
-- Scenario 04 - SESSION B: canonical Query 2 at READ COMMITTED
-- Run (a) alone            -> lock footprint of Q2 (no contention)
--     (b) while 04_queries_A_writer.sql waits -> is Q2 blocked?
-- Repeat with RCSI OFF / ON and with both index states.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DECLARE @t0 DATETIME2, @ms INT, @lock0 BIGINT, @lock1 BIGINT, @rows INT;

-- Lock requests per table so far (sys.dm_db_index_operational_stats counts every
-- row / page lock requested on each index, at any isolation level)
SELECT o.name AS TableName, SUM(s.row_lock_count) AS RowLocks, SUM(s.page_lock_count) AS PageLocks
INTO #before
FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) s
JOIN sys.objects o ON o.object_id = s.object_id
WHERE o.name IN ('Patients', 'MRI_Scans', 'Image_Features')
GROUP BY o.name;
SELECT @lock0 = ISNULL(SUM(wait_time_ms), 0) FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID AND wait_type LIKE 'LCK[_]M[_]%';

SET @t0 = SYSDATETIME();
-- ---------------- Query 2 (canonical) ----------------
SELECT p.PatientID, p.PatientName, p.ClinicalNotes,
       s.ScanID, s.SeriesDescription, s.ImagePath
INTO #result
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';
-- -----------------------------------------------------
SET @rows = @@ROWCOUNT;
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
SELECT @lock1 = ISNULL(SUM(wait_time_ms), 0) FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID AND wait_type LIKE 'LCK[_]M[_]%';
EXEC dbo.usp_Role5_Log N'B: Q2 finished';

SELECT 'Q2' AS Query,
       CASE (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE name = DB_NAME())
            WHEN 1 THEN 'RCSI' ELSE 'Locking RC' END AS Mode,
       CASE WHEN INDEXPROPERTY(OBJECT_ID('dbo.MRI_Scans'), 'IX_MRIScans_PatientID_Covering', 'IndexID') IS NULL
            THEN 'PK only' ELSE 'PK + covering' END AS IndexState,
       @rows AS RowsReturned, @ms AS ElapsedMs, @lock1 - @lock0 AS LockWaitMs;

SELECT a.TableName, a.RowLocks - b.RowLocks AS RowLocksRequested,
       a.PageLocks - b.PageLocks AS PageLocksRequested
FROM (SELECT o.name AS TableName, SUM(s.row_lock_count) AS RowLocks, SUM(s.page_lock_count) AS PageLocks
      FROM sys.dm_db_index_operational_stats(DB_ID(), NULL, NULL, NULL) s
      JOIN sys.objects o ON o.object_id = s.object_id
      WHERE o.name IN ('Patients', 'MRI_Scans', 'Image_Features')
      GROUP BY o.name) a
JOIN #before b ON b.TableName = a.TableName
ORDER BY a.TableName;

-- SELECT * FROM #result;   -- uncomment to display the 15 rows of Q2
DROP TABLE #before, #result;
GO
