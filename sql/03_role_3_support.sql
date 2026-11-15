-- ============================================================================
-- Role 3: Query Optimization -- supporting SQL for Q1, Q2, Q3
--   * join-algorithm comparison (hash for Q1, loop for Q3 = the non-default plan)
--   * statistics / histogram of the join and filter columns
-- Statistics names are auto-generated (_WA_Sys_..., UQ__...) and DIFFER on every
-- machine, so they are looked up from the catalog instead of being hard-coded.
-- Full experiment set (Merge Join, Seek vs Scan, cut-off, spill, adaptive join):
--   scripts/sql/03_role_3_experiments.sql
-- ============================================================================

USE SpineMRI_DBMS;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Q1 with a forced Hash Match for comparison (baseline plan = Nested Loops)
SELECT p.PatientID, p.PatientName, p.ClinicalNotes,
       s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
OPTION (HASH JOIN);
GO

-- Statistics: Q1 (PatientID), Q2 (SeriesDescription), Q3 (ScanID, unique index of Image_Features)
DECLARE @q1 SYSNAME, @q2 SYSNAME, @q3 SYSNAME;

SELECT @q1 = s.name
FROM sys.stats s
JOIN sys.stats_columns sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
JOIN sys.columns c        ON c.object_id = sc.object_id AND c.column_id = sc.column_id
WHERE s.object_id = OBJECT_ID('dbo.MRI_Scans') AND c.name = 'PatientID' AND sc.stats_column_id = 1;

SELECT @q2 = s.name
FROM sys.stats s
JOIN sys.stats_columns sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
JOIN sys.columns c        ON c.object_id = sc.object_id AND c.column_id = sc.column_id
WHERE s.object_id = OBJECT_ID('dbo.MRI_Scans') AND c.name = 'SeriesDescription' AND sc.stats_column_id = 1;

SELECT @q3 = s.name
FROM sys.stats s
JOIN sys.stats_columns sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
JOIN sys.columns c        ON c.object_id = sc.object_id AND c.column_id = sc.column_id
WHERE s.object_id = OBJECT_ID('dbo.Image_Features') AND c.name = 'ScanID' AND sc.stats_column_id = 1
  AND s.name LIKE 'UQ%';

DBCC SHOW_STATISTICS ('dbo.MRI_Scans',      @q1);   -- Q1 histogram
DBCC SHOW_STATISTICS ('dbo.MRI_Scans',      @q2);   -- Q2 histogram
DBCC SHOW_STATISTICS ('dbo.Image_Features', @q3);   -- Q3 histogram
GO

-- Q3 with a forced Nested Loops join for comparison (baseline plan = Hash Match)
DECLARE @TargetScanID INT = 1;
DECLARE @T1 FLOAT, @T2 FLOAT, @T3 FLOAT, @T4 FLOAT;

-- Fetch reference feature vector
SELECT @T1 = V_Dim1, @T2 = V_Dim2, @T3 = V_Dim3, @T4 = V_Dim4
FROM Image_Features
WHERE ScanID = @TargetScanID;

-- Retrieve top 3 nearest slices (OPTION must come before the terminating semicolon)
SELECT TOP 3
    s.ScanID,
    s.PatientID,
    s.SeriesDescription,
    s.ImagePath,
    SQRT(
        SQUARE(f.V_Dim1 - @T1) +
        SQUARE(f.V_Dim2 - @T2) +
        SQUARE(f.V_Dim3 - @T3) +
        SQUARE(f.V_Dim4 - @T4)
    ) AS EuclideanDistance
FROM Image_Features f
INNER JOIN MRI_Scans s ON f.ScanID = s.ScanID
WHERE f.ScanID <> @TargetScanID
ORDER BY EuclideanDistance ASC
OPTION (LOOP JOIN);
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
