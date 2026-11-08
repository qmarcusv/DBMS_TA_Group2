-- ============================================================================
-- Scenario 04 - INDEX STATE 2: with the Role 2 covering index on the FK
-- (same definition as Role 2's IX_MRIScans_PatientID_Covering).
-- ============================================================================
USE SpineMRI_DBMS;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_MRIScans_PatientID_Covering'
                 AND object_id = OBJECT_ID('dbo.MRI_Scans'))
    CREATE NONCLUSTERED INDEX IX_MRIScans_PatientID_Covering
    ON dbo.MRI_Scans (PatientID ASC, SeriesDescription ASC)
    INCLUDE (ImagePath);
GO
SELECT OBJECT_NAME(object_id) AS TableName, name AS IndexName, type_desc
FROM sys.indexes
WHERE object_id IN (OBJECT_ID('dbo.Patients'), OBJECT_ID('dbo.MRI_Scans'), OBJECT_ID('dbo.Image_Features'))
  AND index_id > 0;
GO
