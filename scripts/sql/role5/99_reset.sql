-- ============================================================================
-- Role 5.2 - RESET: restore the baseline after each scenario
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;

-- Close any transaction left open in THIS window
WHILE @@TRANCOUNT > 0 ROLLBACK;

-- Back to classic locking (scenario 02 turns row versioning ON)
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SpineMRI_DBMS' AND is_read_committed_snapshot_on = 1)
    ALTER DATABASE SpineMRI_DBMS SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SpineMRI_DBMS' AND snapshot_isolation_state = 1)
    ALTER DATABASE SpineMRI_DBMS SET ALLOW_SNAPSHOT_ISOLATION OFF;
GO

UPDATE dbo.Patients
SET DiagnosisStatus = 'Confirmed'
WHERE PatientID = '0001' AND DiagnosisStatus <> 'Confirmed';

UPDATE dbo.MRI_Scans
SET AcquisitionDate = '2026-10-29 12:25:45'
WHERE ScanID = 1;

SELECT PatientID, DiagnosisStatus FROM dbo.Patients WHERE PatientID = '0001';
SELECT name, snapshot_isolation_state_desc AS SnapshotIsolation,
       is_read_committed_snapshot_on AS RCSI
FROM sys.databases WHERE name = 'SpineMRI_DBMS';
GO
