-- ============================================================================
-- Scenario 02 - LOCKING vs RCSI   SESSION A (writer)   -> press F5 FIRST
-- A radiologist keeps an UPDATE of patient 0001 open for 10 s (X lock held).
-- Run it twice with 02_rcsi_B_reader.sql:
--   Run 1: RCSI OFF (after 99_reset.sql)                -> reader is blocked
--   Run 2: RCSI ON  (after 02_rcsi_0_enable_...sql)     -> reader is not blocked
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;

BEGIN TRANSACTION;
    UPDATE dbo.Patients
    SET DiagnosisStatus = 'Revised'
    WHERE PatientID = '0001';
    EXEC dbo.usp_Role5_Log N'A: UPDATE 0001 -> Revised (uncommitted, X lock held)';

    -- >>> Switch to Session B (02_rcsi_B_reader.sql) and press F5 <<<
    WAITFOR DELAY '00:00:10';

COMMIT TRANSACTION;
EXEC dbo.usp_Role5_Log N'A: COMMIT';
GO
