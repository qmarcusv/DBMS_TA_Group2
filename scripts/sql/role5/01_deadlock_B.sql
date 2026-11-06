-- ============================================================================
-- Scenario 01 - DEADLOCK   SESSION B   -> run within ~4 s after Session A
-- Technician workflow: (1) fix the scan metadata, (2) then the patient record.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
SET DEADLOCK_PRIORITY NORMAL;

BEGIN TRY
    BEGIN TRANSACTION;
        UPDATE dbo.MRI_Scans
        SET AcquisitionDate = SYSDATETIME()
        WHERE ScanID = 1;
        EXEC dbo.usp_Role5_Log N'B: X lock on MRI_Scans(ScanID = 1) acquired';

        WAITFOR DELAY '00:00:02';

        EXEC dbo.usp_Role5_Log N'B: requesting X lock on Patients(0001) ...';
        UPDATE dbo.Patients
        SET DiagnosisStatus = 'Image Checked'
        WHERE PatientID = '0001';
    COMMIT TRANSACTION;
    EXEC dbo.usp_Role5_Log N'B: COMMIT - survived';
    SELECT 'B' AS Session, 'COMMITTED (survivor)' AS Outcome;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    EXEC dbo.usp_Role5_Log N'B: chosen as deadlock victim - rolled back';
    SELECT 'B' AS Session, 'ROLLED BACK (deadlock victim)' AS Outcome,
           ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
