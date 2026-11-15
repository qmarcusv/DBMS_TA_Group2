-- ============================================================================
-- Scenario 02 - LOCKING vs RCSI   SESSION B (reader, READ COMMITTED)
-- Run while Session A (02_rcsi_A_writer.sql) is waiting.
-- Measures the elapsed time of the read AND the lock wait time recorded by
-- SQL Server for this session (sys.dm_exec_session_wait_stats, LCK_M_*).
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
DECLARE @t0 DATETIME2, @v VARCHAR(20), @lock0 BIGINT, @lock1 BIGINT;
DECLARE @rcsi BIT = (SELECT is_read_committed_snapshot_on
                     FROM sys.databases WHERE name = 'SpineMRI_DBMS');

SELECT @lock0 = ISNULL(SUM(wait_time_ms), 0)
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID AND wait_type LIKE 'LCK[_]M[_]%';

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET @t0 = SYSDATETIME();
SELECT @v = DiagnosisStatus FROM dbo.Patients WHERE PatientID = '0001';

SELECT @lock1 = ISNULL(SUM(wait_time_ms), 0)
FROM sys.dm_exec_session_wait_stats
WHERE session_id = @@SPID AND wait_type LIKE 'LCK[_]M[_]%';

EXEC dbo.usp_Role5_Log N'B: READ COMMITTED read finished';
SELECT CASE @rcsi WHEN 1 THEN 'READ COMMITTED SNAPSHOT (RCSI ON)'
                  ELSE 'READ COMMITTED (locking, RCSI OFF)' END AS Mode,
       @v AS ValueSeen,
       DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS ElapsedMs,
       @lock1 - @lock0 AS LockWaitMs;
-- Expected: RCSI OFF -> waits ~8-10 s (LCK_M_S) until A commits, then reads 'Revised'
--           RCSI ON  -> reads immediately (LockWaitMs = 0) the last committed
--                       version 'Confirmed' from the version store
--           (an uncommitted value is never returned in either case)
GO
