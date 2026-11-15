-- ============================================================================
-- Scenario 02c - SNAPSHOT ISOLATION   SESSION B (reader)
-- Requires 02_rcsi_0_enable_row_versioning.sql. Run while 02_rcsi_A_writer.sql
-- is waiting. Shows the transaction-level snapshot: both reads inside the
-- transaction return the version committed when the transaction started,
-- even after A has committed in between.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
DECLARE @t0 DATETIME2, @v1 VARCHAR(20), @v2 VARCHAR(20), @ms1 INT;

SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;
    SET @t0 = SYSDATETIME();
    SELECT @v1 = DiagnosisStatus FROM dbo.Patients WHERE PatientID = '0001';
    SET @ms1 = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
    EXEC dbo.usp_Role5_Log N'B: first SNAPSHOT read done';

    WAITFOR DELAY '00:00:12';      -- A commits 'Revised' during this wait

    SELECT @v2 = DiagnosisStatus FROM dbo.Patients WHERE PatientID = '0001';
    EXEC dbo.usp_Role5_Log N'B: second SNAPSHOT read done (after A committed)';
COMMIT TRANSACTION;

SELECT 'SNAPSHOT' AS Mode, @v1 AS FirstRead, @ms1 AS FirstReadMs, @v2 AS SecondRead,
       (SELECT DiagnosisStatus FROM dbo.Patients WHERE PatientID = '0001') AS CommittedNow;
-- Expected: FirstRead = SecondRead = 'Confirmed' (transaction-level snapshot),
--           CommittedNow = 'Revised'. Under RCSI the second read would already
--           return 'Revised' (statement-level snapshot).
GO
