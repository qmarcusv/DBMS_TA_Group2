-- ============================================================================
-- Role 4 (additions):
--   PART A  Two-step admission WITHOUT a transaction  vs  WITH a transaction
--   PART B  Delayed Durability (asynchronous commit) in a scratch database
--   PART C  Checkpoint versus Lazy Writer counters
-- Everything created here is removed again at the end of each part.
-- ============================================================================

-- ============================================================================
-- PART A -- The clinical admission has two sequential steps:
--   step 1 = record the diagnosis (Patients row)
--   step 2 = store the MRI image path  (MRI_Scans row)  -> fails (CK_Series_Valid, error 547)
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
DELETE FROM dbo.Patients WHERE PatientID IN ('9001','9002');   -- make the script re-runnable
GO

PRINT '--- A1. WITHOUT a transaction (each statement auto-commits) ---';
INSERT INTO dbo.Patients (PatientID, PatientName, ClinicalNotes, DiagnosisStatus)
VALUES ('9001', N'Demo Patient 9001', N'L4-5 disc bulge (step 1: diagnosis recorded)', 'Draft');
-- step 2 raises error 547; step 1 is ALREADY committed and stays
INSERT INTO dbo.MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath, AcquisitionDate)
VALUES ('9001', 'DEMO', 'T2_TSE_SAG_INVALID', '01_MRI_Data/9001/demo/bad.ima', GETDATE());
GO
-- Orphan clinical record: a patient with a diagnosis but no scan  => integrity violated
SELECT p.PatientID, p.ClinicalNotes, scans = (SELECT COUNT(*) FROM dbo.MRI_Scans s WHERE s.PatientID = p.PatientID)
FROM dbo.Patients p WHERE p.PatientID = '9001';
GO

PRINT '--- A2. WITH BEGIN TRAN / TRY...CATCH / ROLLBACK ---';
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRAN Admission;
        INSERT INTO dbo.Patients (PatientID, PatientName, ClinicalNotes, DiagnosisStatus)
        VALUES ('9002', N'Demo Patient 9002', N'L4-5 disc bulge (step 1: diagnosis recorded)', 'Draft');
        INSERT INTO dbo.MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath, AcquisitionDate)
        VALUES ('9002', 'DEMO', 'T2_TSE_SAG_INVALID', '01_MRI_Data/9002/demo/bad.ima', GETDATE());
    COMMIT TRAN Admission;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
SET XACT_ABORT OFF;
GO
-- All-or-nothing: neither the diagnosis nor the image path exists
SELECT patients_9002 = (SELECT COUNT(*) FROM dbo.Patients WHERE PatientID = '9002'),
       scans_9002    = (SELECT COUNT(*) FROM dbo.MRI_Scans WHERE PatientID = '9002');
GO
-- Comparison table
SELECT case_name = 'A1 no transaction', patients_rows = (SELECT COUNT(*) FROM dbo.Patients WHERE PatientID='9001'),
       scans_rows = (SELECT COUNT(*) FROM dbo.MRI_Scans WHERE PatientID='9001'), verdict = 'orphan record left behind'
UNION ALL
SELECT 'A2 with transaction', (SELECT COUNT(*) FROM dbo.Patients WHERE PatientID='9002'),
       (SELECT COUNT(*) FROM dbo.MRI_Scans WHERE PatientID='9002'), 'database unchanged (all-or-nothing)';
GO
DELETE FROM dbo.Patients WHERE PatientID IN ('9001','9002');   -- clean up
GO

-- ============================================================================
-- PART B -- Delayed Durability, measured in a scratch database
--   FULL durability : every COMMIT waits until its log block is hardened on disk (WRITELOG wait)
--   DELAYED         : COMMIT returns when the log record is in the in-memory log buffer;
--                     the buffer is flushed when full (~60 KB) or by sp_flush_log
-- ============================================================================
USE master;
GO
IF DB_ID('R4_Lab') IS NOT NULL BEGIN ALTER DATABASE R4_Lab SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE R4_Lab; END
CREATE DATABASE R4_Lab;
ALTER DATABASE R4_Lab SET RECOVERY FULL;
ALTER DATABASE R4_Lab SET DELAYED_DURABILITY = ALLOWED;     -- DISABLED (default) | ALLOWED | FORCED
BACKUP DATABASE R4_Lab TO DISK = 'NUL';                      -- start the log chain (nothing is stored)
GO
USE R4_Lab;
GO
CREATE TABLE dbo.t (id INT IDENTITY PRIMARY KEY, payload CHAR(100) NOT NULL DEFAULT 'x');
CREATE TABLE dbo.result (mode VARCHAR(30), n INT, elapsed_ms INT, log_writes BIGINT, log_bytes_written BIGINT);
GO
SET NOCOUNT ON;
DECLARE @i INT, @t0 DATETIME2, @w0 BIGINT, @b0 BIGINT, @n INT = 5000;

-- B1: FULL durability, 5,000 single-row transactions
SELECT @w0 = num_of_writes, @b0 = num_of_bytes_written FROM sys.dm_io_virtual_file_stats(DB_ID(), 2);
SET @t0 = SYSDATETIME(); SET @i = 0;
WHILE @i < @n BEGIN
    BEGIN TRAN; INSERT dbo.t DEFAULT VALUES; COMMIT TRAN WITH (DELAYED_DURABILITY = OFF);
    SET @i += 1;
END
INSERT dbo.result SELECT 'FULL durability', @n, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()),
       num_of_writes - @w0, num_of_bytes_written - @b0 FROM sys.dm_io_virtual_file_stats(DB_ID(), 2);

-- B2: DELAYED durability, same work
SELECT @w0 = num_of_writes, @b0 = num_of_bytes_written FROM sys.dm_io_virtual_file_stats(DB_ID(), 2);
SET @t0 = SYSDATETIME(); SET @i = 0;
WHILE @i < @n BEGIN
    BEGIN TRAN; INSERT dbo.t DEFAULT VALUES; COMMIT TRAN WITH (DELAYED_DURABILITY = ON);
    SET @i += 1;
END
EXEC sys.sp_flush_log;                                         -- force the remaining log buffer to disk
INSERT dbo.result SELECT 'DELAYED durability', @n, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()),
       num_of_writes - @w0, num_of_bytes_written - @b0 FROM sys.dm_io_virtual_file_stats(DB_ID(), 2);
GO
SELECT * FROM dbo.result;
GO
USE master;
GO
ALTER DATABASE R4_Lab SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE R4_Lab;
GO

-- ============================================================================
-- PART C -- Who writes dirty pages? (cumulative counters since instance start)
--   Checkpoint pages/sec  : pages flushed by CHECKPOINT (data durability point)
--   Lazy writes/sec       : pages flushed by the Lazy Writer to free buffers under memory pressure
-- ============================================================================
SELECT counter_name, cntr_value
FROM sys.dm_os_performance_counters
WHERE object_name LIKE '%Buffer Manager%'
  AND counter_name IN ('Checkpoint pages/sec', 'Lazy writes/sec', 'Page writes/sec', 'Page life expectancy');
GO
