-- ============================================================================
-- Role 3: Query Optimization
-- Supporting SQL for Q1 - Q3
-- ============================================================================

USE SpineMRI_DBMS;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Q1 Hash Match for comparison (baseline = nested loop)
SELECT p.PatientID, p.PatientName, p.ClinicalNotes,
       s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
OPTION (HASH JOIN);
GO

-- Q1: PatientID Statistics
-- Display statistics header and histogram for PatientID.
DBCC SHOW_STATISTICS (
    'dbo.MRI_Scans',
    '_WA_Sys_00000002_4BAC3F29'
);
GO

-- Q2: SeriesDescription statistics (look up the auto-stat name by column)
DECLARE @PatientIDStat SYSNAME;
  SELECT @PatientIDStat = s.name FROM sys.stats s
  JOIN sys.stats_columns sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
  JOIN sys.columns c ON c.object_id = s.object_id AND c.column_id = sc.column_id
  WHERE s.object_id = OBJECT_ID('dbo.MRI_Scans') AND c.name = 'PatientID';
  EXEC('DBCC SHOW_STATISTICS (N''dbo.MRI_Scans'', N'''+QUOTENAME(@PatientIDStat)+''');');
  GO

-- Q3: ScanID Statistics
-- Display statistics header and histogram for the unique ScanID index.
DBCC SHOW_STATISTICS (
    'dbo.Image_Features',
    'UQ__Image_Fe__63B32660DF05EFC2'
);
GO

-- Q3 loop join for comparison (baseline = hash join)
DECLARE @TargetScanID INT = 1;
DECLARE @T1 FLOAT, @T2 FLOAT, @T3 FLOAT, @T4 FLOAT;

-- Fetch reference feature vector
SELECT @T1 = V_Dim1, @T2 = V_Dim2, @T3 = V_Dim3, @T4 = V_Dim4 
FROM Image_Features 
WHERE ScanID = @TargetScanID;

-- Retrieve top 3 nearest slices
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
ORDER BY EuclideanDistance ASC;
OPTION (LOOP JOIN);
GO

-- Q3: Compare workload without and with Euclidean distance calculation

-- V1: Join + Top 3 baseline (without distance calculation)
SELECT TOP 3
    f.ScanID,
    f.V_Dim1
FROM Image_Features f
INNER JOIN MRI_Scans s ON f.ScanID = s.ScanID
WHERE f.ScanID <> @TargetScanID
ORDER BY f.V_Dim1 ASC
OPTION (HASH JOIN, MAXDOP 8);


-- V2: Join + Euclidean distance + Top 3
SELECT TOP 3
    f.ScanID,
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
OPTION (HASH JOIN, MAXDOP 8);