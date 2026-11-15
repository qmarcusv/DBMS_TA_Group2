-- ============================================================================
-- Scenario 04 - INDEX STATE 1: baseline (only the PK clustered indexes, exactly
-- as in data/SpineMRI_DBMS.bak). Drops the Role 2 covering index if present.
-- ============================================================================
USE SpineMRI_DBMS;
GO
DROP INDEX IF EXISTS IX_MRIScans_PatientID_Covering ON dbo.MRI_Scans;
GO
SELECT OBJECT_NAME(object_id) AS TableName, name AS IndexName, type_desc
FROM sys.indexes
WHERE object_id IN (OBJECT_ID('dbo.Patients'), OBJECT_ID('dbo.MRI_Scans'), OBJECT_ID('dbo.Image_Features'))
  AND index_id > 0;
GO
