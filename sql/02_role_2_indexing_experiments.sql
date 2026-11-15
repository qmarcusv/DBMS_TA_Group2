-- ============================================================================
-- Role 2: Indexing experiments (Q1, Q2, Q3) -- SSMS script
-- Database: SpineMRI_DBMS. Reproduces Chapter 2 of the report.
-- Measurement protocol (dev instance only), repeated before EVERY measurement:
--     CHECKPOINT; DBCC DROPCLEANBUFFERS;
--     ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
-- (DBCC FREEPROCCACHE clears the plan cache of the whole instance; the scoped
--  command above does the same for this database only.)
-- Read the Messages tab: logical reads, physical reads, read-ahead reads, CPU time.
-- Section 5 drops every index again so that the other roles start from the
-- baseline database.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;   -- required to create filtered / columnstore indexes (sqlcmd default is OFF; SSMS is ON)
SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; SET NUMERIC_ROUNDABORT OFF;
SET STATISTICS IO ON; SET STATISTICS TIME ON;
GO

-- ---------------------------------------------------------------------------
-- SECTION 1 - Baseline (clustered primary keys only)
-- ---------------------------------------------------------------------------
SELECT OBJECT_NAME(i.object_id) AS tbl, i.name AS idx, i.type_desc, ps.index_depth, ps.page_count, ps.avg_fragmentation_in_percent
FROM sys.indexes i
CROSS APPLY sys.dm_db_index_physical_stats(DB_ID(), i.object_id, i.index_id, NULL, 'DETAILED') ps
WHERE i.object_id IN (OBJECT_ID('dbo.Patients'), OBJECT_ID('dbo.MRI_Scans'), OBJECT_ID('dbo.Image_Features'))
  AND ps.index_level = 0;
GO
-- Baseline measurements (Include Actual Execution Plan = Ctrl+M)
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
PRINT '## BASELINE Q1';
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001';
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
PRINT '## BASELINE Q2';
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001' AND s.SeriesDescription LIKE '%T2%SAG%';
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
PRINT '## BASELINE Q3';
DECLARE @T1 FLOAT, @T2 FLOAT, @T3 FLOAT, @T4 FLOAT;
SELECT @T1 = V_Dim1, @T2 = V_Dim2, @T3 = V_Dim3, @T4 = V_Dim4 FROM Image_Features WHERE ScanID = 1;
SELECT TOP 3 s.ScanID, s.PatientID, s.SeriesDescription, s.ImagePath,
       SQRT(SQUARE(f.V_Dim1-@T1)+SQUARE(f.V_Dim2-@T2)+SQUARE(f.V_Dim3-@T3)+SQUARE(f.V_Dim4-@T4)) AS EuclideanDistance
FROM Image_Features f INNER JOIN MRI_Scans s ON f.ScanID = s.ScanID
WHERE f.ScanID <> 1 ORDER BY EuclideanDistance ASC;
GO

-- ---------------------------------------------------------------------------
-- SECTION 2 - Covering B-tree indexes (Q1, Q2)
-- ---------------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_MRIScans_SeriesDescription
ON dbo.MRI_Scans (SeriesDescription ASC) INCLUDE (PatientID, ImagePath);
GO
CREATE NONCLUSTERED INDEX IX_MRIScans_PatientID_Covering
ON dbo.MRI_Scans (PatientID ASC, SeriesDescription ASC) INCLUDE (ImagePath);
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
PRINT '## COVERING INDEX Q1';
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001';
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
PRINT '## COVERING INDEX Q2';
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001' AND s.SeriesDescription LIKE '%T2%SAG%';
GO

-- ---------------------------------------------------------------------------
-- SECTION 3 - Filtered index (T2 sagittal series only; LIKE with a leading
--             wildcard is not allowed in a filtered-index predicate, Msg 10735)
-- ---------------------------------------------------------------------------
CREATE NONCLUSTERED INDEX IX_MRIScans_T2Sag_Filtered
ON dbo.MRI_Scans (PatientID ASC, SeriesDescription ASC)
INCLUDE (ImagePath)
WHERE SeriesDescription IN (
    'I_T2_TSE_SAG_P2_384_0002', 'POSDISP_[2]_T2_TSE_SAG_384_5001',
    'POSDISP_[2]_T2_TSE_SAG_384_5002', 'POSDISP_[3]_T2_TSE_SAG_384_5001',
    'POSDISP_[4]_T2_TSE_SAG_384_5001', 'POSDISP_[6]_T2_TIRM_SAG_P2_5002',
    'POSDISP_[7]_T2_TIRM_SAG_P2_5003', 'T2_CISS3D_SAG_ISO_0006',
    'T2_TIRM_SAG_BOX_0008', 'T2_TIRM_SAG_P2_0004', 'T2_TIRM_SAG_P2_0005',
    'T2_TIRM_SAG_P2_0006', 'T2_TIRM_SAG_P2_0007', 'T2_TIRM_SAG_P2_0008',
    'T2_TIRM_SAG_P2_0009', 'T2_TIRM_SAG_P2_0010', 'T2_TSE_SAG_256_0006',
    'T2_TSE_SAG_256_0007', 'T2_TSE_SAG_320_0002', 'T2_TSE_SAG_320_0003',
    'T2_TSE_SAG_380_0006', 'T2_TSE_SAG_380_0008', 'T2_TSE_SAG_384_0002',
    'T2_TSE_SAG_384_0003', 'T2_TSE_SAG_384_0004', 'T2_TSE_SAG_384_0005',
    'T2_TSE_SAG_384_0006', 'T2_TSE_SAG_384_0007', 'T2_TSE_SAG_384_0008',
    'T2_TSE_SAG_384_0009', 'T2_TSE_SAG_448_0006', 'T2_TSE_SAG_448_0013'
);
GO
SELECT i.name, ps.page_count, ps.page_count * 8 / 1024.0 AS size_mb
FROM sys.indexes i CROSS APPLY sys.dm_db_index_physical_stats(DB_ID(), i.object_id, i.index_id, NULL, 'LIMITED') ps
WHERE i.object_id = OBJECT_ID('dbo.MRI_Scans');
GO

-- ---------------------------------------------------------------------------
-- SECTION 4 - Non-clustered columnstore index (Q3, batch mode)
-- ---------------------------------------------------------------------------
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_ImageFeatures_Dims
ON dbo.Image_Features (ScanID, V_Dim1, V_Dim2, V_Dim3, V_Dim4);
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
PRINT '## COLUMNSTORE Q3';
DECLARE @T1 FLOAT, @T2 FLOAT, @T3 FLOAT, @T4 FLOAT;
SELECT @T1 = V_Dim1, @T2 = V_Dim2, @T3 = V_Dim3, @T4 = V_Dim4 FROM Image_Features WHERE ScanID = 1;
SELECT TOP 3 s.ScanID, s.PatientID, s.SeriesDescription, s.ImagePath,
       SQRT(SQUARE(f.V_Dim1-@T1)+SQUARE(f.V_Dim2-@T2)+SQUARE(f.V_Dim3-@T3)+SQUARE(f.V_Dim4-@T4)) AS EuclideanDistance
FROM Image_Features f INNER JOIN MRI_Scans s ON f.ScanID = s.ScanID
WHERE f.ScanID <> 1 ORDER BY EuclideanDistance ASC;
GO

-- ---------------------------------------------------------------------------
-- SECTION 5 - Clean up: back to the baseline database
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS IX_MRIScans_SeriesDescription     ON dbo.MRI_Scans;
DROP INDEX IF EXISTS IX_MRIScans_PatientID_Covering    ON dbo.MRI_Scans;
DROP INDEX IF EXISTS IX_MRIScans_T2Sag_Filtered        ON dbo.MRI_Scans;
DROP INDEX IF EXISTS NCCI_ImageFeatures_Dims           ON dbo.Image_Features;
GO
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
GO
