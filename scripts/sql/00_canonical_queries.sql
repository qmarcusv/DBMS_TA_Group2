-- ============================================================================
-- Canonical Queries Contract (Q1, Q2, Q3)
-- Shared across Role 1 to Role 5 for benchmarking and optimization analysis.
-- ============================================================================

USE SpineMRI_DBMS;
GO

-- ----------------------------------------------------------------------------
-- Query 1 (Point Lookup & Relational Join):
-- Retrieve clinical diagnosis and all associated MRI slices for a given patient.
-- Benchmark focus: Clustered Index Seek vs Table Scan; Nested Loops join behavior.
-- ----------------------------------------------------------------------------
SELECT 
    p.PatientID,
    p.PatientName,
    p.ClinicalNotes,
    s.ScanID,
    s.SeriesDescription,
    s.ImagePath
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001';
GO

-- ----------------------------------------------------------------------------
-- Query 2 (Filtered Composite Predicate):
-- Retrieve T2 Sagittal scans for a target patient.
-- Benchmark focus: Multi-attribute selectivity, Non-clustered / Filtered Index,
--                  cardinality estimation via statistics histogram.
-- ----------------------------------------------------------------------------
SELECT 
    p.PatientID,
    p.PatientName,
    p.ClinicalNotes,
    s.ScanID,
    s.SeriesDescription,
    s.ImagePath
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';
GO

-- ----------------------------------------------------------------------------
-- Query 3 (AI Feature Similarity Retrieval):
-- Retrieve top-3 most similar MRI slices to a reference slice (ScanID = 1).
-- Benchmark focus: Vector distance computation (Euclidean metric), Top-N Sort,
--                  Rowstore vs Columnstore vector aggregation.
-- ----------------------------------------------------------------------------
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
GO
