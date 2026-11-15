-- ============================================================================
-- Scenario 01b - LOCK_TIMEOUT (bounded waiting instead of waiting forever)
-- Run 04_queries_index_baseline.sql + 99_reset.sql (RCSI OFF) first, start
-- 04_queries_A_writer.sql in Session A, then run this file in Session B.
-- Q1 must scan MRI_Scans and hits the page that A has locked; instead of
-- waiting ~8 s it gives up after 3 s with error 1222.
-- Observed: the 65 rows of patient 0001 are already sent to the client (they
-- sit on the first pages), THEN the scan reaches the locked page of patient
-- 0002 and fails -> partial result + error. Error 1222 does NOT roll back the
-- surrounding transaction: the application must decide (rollback / retry).
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
SET LOCK_TIMEOUT 3000;            -- milliseconds; -1 = wait forever (default), 0 = no wait
DECLARE @t0 DATETIME2 = SYSDATETIME();

BEGIN TRY
    SELECT p.PatientID, p.PatientName, s.ScanID, s.SeriesDescription, s.ImagePath
    FROM Patients p
    INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
    WHERE p.PatientID = '0001';
END TRY
BEGIN CATCH
    SELECT 'Q1 gave up' AS Outcome, ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage,
           DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS WaitedMs;
END CATCH
SET LOCK_TIMEOUT -1;
GO
