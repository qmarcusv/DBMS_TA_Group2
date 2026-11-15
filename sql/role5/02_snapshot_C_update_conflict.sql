-- ============================================================================
-- Scenario 02d - SNAPSHOT UPDATE CONFLICT (optimistic concurrency, error 3960)
-- Run 99_reset.sql + 02_rcsi_0_enable_row_versioning.sql first.
-- Press F5 HERE FIRST, then immediately run 02_rcsi_A_writer.sql in Session A.
-- SNAPSHOT never blocks the read, but when two transactions update the same
-- row the later one fails ("first committer wins") instead of overwriting.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
DECLARE @v VARCHAR(20);

SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRANSACTION;
    SELECT @v = DiagnosisStatus FROM dbo.Patients WHERE PatientID = '0001';  -- snapshot taken here
    EXEC dbo.usp_Role5_Log N'C: snapshot read done';

    -- >>> Start 02_rcsi_A_writer.sql now; it updates the same row and commits <<<
    WAITFOR DELAY '00:00:13';

    BEGIN TRY
        UPDATE dbo.Patients SET DiagnosisStatus = 'Archived' WHERE PatientID = '0001';
        COMMIT TRANSACTION;
        SELECT 'C: UPDATE committed' AS Result, @v AS SnapshotValue;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT 'C: UPDATE rejected' AS Result, @v AS SnapshotValue,
               ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
    END CATCH
GO
