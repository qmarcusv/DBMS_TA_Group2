-- ============================================================================
-- Role 5.2 - Deadlock & MVCC / RCSI: SETUP (run once, in any window)
-- Database: SpineMRI_DBMS (restored from data/SpineMRI_DBMS.bak)
--
-- Demo convention (SSMS):
--   * Each scenario has a Session A file and a Session B file. Open them in two
--     separate query windows = two sessions.
--   * The session that HOLDS locks contains a WAITFOR DELAY, which gives you
--     time to switch window and press F5 on the other session.
--   * Optional third window: 03_lock_monitor.sql (watch locks / blocking live).
--   * After every scenario run 99_reset.sql to restore the baseline data.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;

-- 1. Start from classic pessimistic locking: row versioning OFF.
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SpineMRI_DBMS' AND is_read_committed_snapshot_on = 1)
    ALTER DATABASE SpineMRI_DBMS SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SpineMRI_DBMS' AND snapshot_isolation_state = 1)
    ALTER DATABASE SpineMRI_DBMS SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO

-- 2. Timestamped log helper: RAISERROR ... WITH NOWAIT flushes the message to
--    the SSMS "Messages" tab immediately (PRINT is buffered until batch end),
--    so the interleaving of Session A and Session B is visible in real time.
CREATE OR ALTER PROCEDURE dbo.usp_Role5_Log @Msg NVARCHAR(400)
AS
BEGIN
    DECLARE @s NVARCHAR(500) = CONCAT(CONVERT(CHAR(12), SYSDATETIME(), 114), N'  ', @Msg);
    RAISERROR(@s, 0, 1) WITH NOWAIT;
END
GO

-- 3. Baseline values touched by the demos
SELECT PatientID, DiagnosisStatus FROM dbo.Patients WHERE PatientID = '0001';
SELECT ScanID, PatientID, SeriesDescription, AcquisitionDate
FROM dbo.MRI_Scans WHERE ScanID = 1;
SELECT name,
       snapshot_isolation_state_desc AS SnapshotIsolation,
       is_read_committed_snapshot_on AS RCSI
FROM sys.databases WHERE name = 'SpineMRI_DBMS';
GO
