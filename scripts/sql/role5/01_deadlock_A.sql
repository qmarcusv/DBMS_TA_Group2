-- ============================================================================
-- Scenario 01 - DEADLOCK   SESSION A   -> press F5 FIRST
-- Radiologist workflow: (1) lock the patient record, (2) then the scan.
-- Session B does the same two resources in the OPPOSITE order.
--   A: X(Patients 0001)  ... wants X(MRI_Scans ScanID 1)
--   B: X(MRI_Scans 1)    ... wants X(Patients 0001)        -> cycle
--
-- Run 1: leave DEADLOCK_PRIORITY NORMAL in both sessions -> SQL Server picks
--        the victim with the least transaction log used.
-- Run 2: change the line below to  SET DEADLOCK_PRIORITY LOW;  -> A becomes
--        the victim regardless of log used.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
SET DEADLOCK_PRIORITY NORMAL;   -- LOW (-5) / NORMAL (0) / HIGH (5) or an integer -10..10

BEGIN TRY
    BEGIN TRANSACTION;
        UPDATE dbo.Patients
        SET DiagnosisStatus = 'Under Review'
        WHERE PatientID = '0001';
        EXEC dbo.usp_Role5_Log N'A: X lock on Patients(0001) acquired';

        -- >>> Switch to Session B (01_deadlock_B.sql) and press F5 <<<
        WAITFOR DELAY '00:00:06';

        EXEC dbo.usp_Role5_Log N'A: requesting X lock on MRI_Scans(ScanID = 1) ...';
        UPDATE dbo.MRI_Scans
        SET AcquisitionDate = SYSDATETIME()
        WHERE ScanID = 1;
    COMMIT TRANSACTION;
    EXEC dbo.usp_Role5_Log N'A: COMMIT - survived';
    SELECT 'A' AS Session, 'COMMITTED (survivor)' AS Outcome;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    EXEC dbo.usp_Role5_Log N'A: chosen as deadlock victim - rolled back';
    SELECT 'A' AS Session, 'ROLLED BACK (deadlock victim)' AS Outcome,
           ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
