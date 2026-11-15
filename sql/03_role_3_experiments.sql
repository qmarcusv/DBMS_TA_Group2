-- ============================================================================
-- Role 3: Query Processing & Optimization -- experiment script (SSMS)
-- Database : SpineMRI_DBMS  (SQL Server 2022/2025, compatibility level >= 150)
-- How to run in SSMS
--   * Turn on "Include Actual Execution Plan" (Ctrl+M) before sections 1, 2, 4, 6, 7.
--   * Run ONE section at a time (select the section, press F5).
--   * Every section that creates objects removes them again (ROLLBACK / DROP),
--     so the database is back to the baseline state of Role 1 afterwards.
-- Cold-cache protocol used before each measurement (dev instance only):
--     CHECKPOINT; DBCC DROPCLEANBUFFERS;
--     ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;   -- this DB only
-- The numbers quoted in the report come from this script; Estimated rows of
-- Q1/Q2 differ a little between machines because auto-created statistics are
-- built from a SAMPLE (see section 3).
-- ============================================================================
USE SpineMRI_DBMS;
GO

-- ============================================================================
-- SECTION 1 -- Baseline of the three canonical queries (cold cache)
--   Look at: operators, Estimated vs Actual rows, Estimated Subtree Cost,
--            logical reads, CPU time (Messages tab).
-- ============================================================================
SET STATISTICS IO ON; SET STATISTICS TIME ON;
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- Q1
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001';
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- Q2
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001' AND s.SeriesDescription LIKE '%T2%SAG%';
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
-- Q3
DECLARE @T1 FLOAT, @T2 FLOAT, @T3 FLOAT, @T4 FLOAT;
SELECT @T1 = V_Dim1, @T2 = V_Dim2, @T3 = V_Dim3, @T4 = V_Dim4 FROM Image_Features WHERE ScanID = 1;
SELECT TOP 3 s.ScanID, s.PatientID, s.SeriesDescription, s.ImagePath,
       SQRT(SQUARE(f.V_Dim1-@T1)+SQUARE(f.V_Dim2-@T2)+SQUARE(f.V_Dim3-@T3)+SQUARE(f.V_Dim4-@T4)) AS EuclideanDistance
FROM Image_Features f INNER JOIN MRI_Scans s ON f.ScanID = s.ScanID
WHERE f.ScanID <> 1
ORDER BY EuclideanDistance ASC;
GO

-- ============================================================================
-- SECTION 2 -- Join algorithm comparison with query hints
--   The optimizer's own choice is Nested Loops (Q1, Q2) and Hash Match (Q3).
--   Each hint FORCES the algorithm so that Estimated Subtree Cost, memory grant
--   and logical reads can be compared on identical inputs.
--   Repeat each statement with: OPTION (LOOP JOIN) / (HASH JOIN) / (MERGE JOIN)
-- ============================================================================
CHECKPOINT; DBCC DROPCLEANBUFFERS; ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
OPTION (HASH JOIN);          -- try LOOP JOIN, MERGE JOIN
GO
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001' AND s.SeriesDescription LIKE '%T2%SAG%'
OPTION (MERGE JOIN);         -- try LOOP JOIN, HASH JOIN
GO
DECLARE @T1 FLOAT, @T2 FLOAT, @T3 FLOAT, @T4 FLOAT;
SELECT @T1 = V_Dim1, @T2 = V_Dim2, @T3 = V_Dim3, @T4 = V_Dim4 FROM Image_Features WHERE ScanID = 1;
SELECT TOP 3 s.ScanID, SQRT(SQUARE(f.V_Dim1-@T1)+SQUARE(f.V_Dim2-@T2)+SQUARE(f.V_Dim3-@T3)+SQUARE(f.V_Dim4-@T4)) AS d
FROM Image_Features f INNER JOIN MRI_Scans s ON f.ScanID = s.ScanID
WHERE f.ScanID <> 1 ORDER BY d
OPTION (LOOP JOIN);          -- 48,344 inner seeks into MRI_Scans: ~148,000 logical reads
GO

-- ============================================================================
-- SECTION 3 -- Statistics and histograms (names looked up, not hard-coded)
-- ============================================================================
SELECT OBJECT_NAME(s.object_id) AS tbl, s.name AS stat_name, c.name AS col, s.auto_created,
       sp.rows, sp.rows_sampled, sp.steps, sp.modification_counter, sp.last_updated
FROM sys.stats s
JOIN sys.stats_columns sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
JOIN sys.columns c        ON c.object_id = sc.object_id AND c.column_id = sc.column_id
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id IN (OBJECT_ID('dbo.Patients'), OBJECT_ID('dbo.MRI_Scans'), OBJECT_ID('dbo.Image_Features'));
GO
-- Histogram of MRI_Scans.PatientID (Q1) and MRI_Scans.SeriesDescription (Q2)
DECLARE @s1 SYSNAME, @s2 SYSNAME, @s3 SYSNAME;
SELECT @s1 = s.name FROM sys.stats s JOIN sys.stats_columns sc ON sc.object_id=s.object_id AND sc.stats_id=s.stats_id
  JOIN sys.columns c ON c.object_id=sc.object_id AND c.column_id=sc.column_id
  WHERE s.object_id=OBJECT_ID('dbo.MRI_Scans') AND c.name='PatientID' AND sc.stats_column_id=1;
SELECT @s2 = s.name FROM sys.stats s JOIN sys.stats_columns sc ON sc.object_id=s.object_id AND sc.stats_id=s.stats_id
  JOIN sys.columns c ON c.object_id=sc.object_id AND c.column_id=sc.column_id
  WHERE s.object_id=OBJECT_ID('dbo.MRI_Scans') AND c.name='SeriesDescription' AND sc.stats_column_id=1;
SELECT @s3 = s.name FROM sys.stats s JOIN sys.stats_columns sc ON sc.object_id=s.object_id AND sc.stats_id=s.stats_id
  JOIN sys.columns c ON c.object_id=sc.object_id AND c.column_id=sc.column_id
  WHERE s.object_id=OBJECT_ID('dbo.Image_Features') AND c.name='ScanID' AND sc.stats_column_id=1;
DBCC SHOW_STATISTICS('dbo.MRI_Scans', @s1);
DBCC SHOW_STATISTICS('dbo.MRI_Scans', @s2);
DBCC SHOW_STATISTICS('dbo.Image_Features', @s3);
GO
-- Ground truth for Q2 (what the optimizer has to guess for LIKE '%T2%SAG%')
SELECT COUNT(*) AS q2_all_patients   FROM dbo.MRI_Scans WHERE SeriesDescription LIKE '%T2%SAG%';
SELECT COUNT(*) AS q2_patient_0001   FROM dbo.MRI_Scans WHERE PatientID='0001' AND SeriesDescription LIKE '%T2%SAG%';
SELECT COUNT(DISTINCT SeriesDescription) AS distinct_series FROM dbo.MRI_Scans;
GO

-- ============================================================================
-- SECTION 4 -- Seek versus Scan and the tipping point
--   A temporary index is created inside a transaction and rolled back.
-- ============================================================================
BEGIN TRAN;
CREATE NONCLUSTERED INDEX IX_R3_Scans_PatientID ON dbo.MRI_Scans(PatientID);
GO
-- (CLEAR PROCEDURE_CACHE is not allowed inside a transaction -> OPTION (RECOMPILE) is used instead)
-- 4a. Q1 / Q2 with the index: Index Seek + Key Lookup instead of Clustered Index Scan
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID WHERE p.PatientID = '0001' OPTION (RECOMPILE);
GO
SELECT p.PatientID, p.PatientName, p.ClinicalNotes, s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001' AND s.SeriesDescription LIKE '%T2%SAG%' OPTION (RECOMPILE);
GO
-- 4b. Tipping point: 100 patients (~9,060 rows) -> the optimizer returns to Scan + Hash Match
SELECT p.PatientID, s.ScanID, s.SeriesDescription
FROM Patients p INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID WHERE p.PatientID <= '0100' OPTION (RECOMPILE);
GO
ROLLBACK TRAN;
GO

-- ============================================================================
-- SECTION 5 -- Heuristic cut-off ("good enough plan") instead of exhaustive search
--   Compile only (SHOWPLAN): check StatementOptmEarlyAbortReason in the XML
--   (Plan Properties -> Reason For Early Termination Of Statement Optimization)
--   and the optimizer counters before/after.
-- ============================================================================
SELECT counter, occurrence FROM sys.dm_exec_query_optimizer_info
WHERE counter IN ('optimizations','trivial plan','search 0','search 1','search 2','timeout','memory limit exceeded');
GO
SET SHOWPLAN_XML ON;
GO
-- 14 tables -> the join-order search space explodes; the optimizer stops on TIMEOUT
SELECT COUNT(*)
FROM Image_Features f0
INNER JOIN MRI_Scans s0 ON f0.ScanID = s0.ScanID
INNER JOIN MRI_Scans s1 ON s1.PatientID = s0.PatientID AND s1.ScanID = f0.ScanID
INNER JOIN MRI_Scans s2 ON s2.PatientID = s0.PatientID AND s2.ScanID = f0.ScanID
INNER JOIN MRI_Scans s3 ON s3.PatientID = s0.PatientID AND s3.ScanID = f0.ScanID
INNER JOIN MRI_Scans s4 ON s4.PatientID = s0.PatientID AND s4.ScanID = f0.ScanID
INNER JOIN MRI_Scans s5 ON s5.PatientID = s0.PatientID AND s5.ScanID = f0.ScanID
INNER JOIN MRI_Scans s6 ON s6.PatientID = s0.PatientID AND s6.ScanID = f0.ScanID
INNER JOIN MRI_Scans s7 ON s7.PatientID = s0.PatientID AND s7.ScanID = f0.ScanID
INNER JOIN MRI_Scans s8 ON s8.PatientID = s0.PatientID AND s8.ScanID = f0.ScanID
INNER JOIN Patients p1 ON p1.PatientID = s1.PatientID
INNER JOIN Patients p2 ON p2.PatientID = s2.PatientID
INNER JOIN Patients p3 ON p3.PatientID = s3.PatientID
INNER JOIN Patients p4 ON p4.PatientID = s4.PatientID
WHERE s0.PatientID = '0001';
GO
SET SHOWPLAN_XML OFF;
GO
SELECT counter, occurrence FROM sys.dm_exec_query_optimizer_info
WHERE counter IN ('optimizations','trivial plan','search 0','search 1','search 2','timeout','memory limit exceeded');
GO

-- ============================================================================
-- SECTION 6 -- Spill to tempdb caused by wrong cardinality (stale statistics)
--   R3_Scans is a throw-away copy of MRI_Scans; its statistics are falsified to
--   "100 rows" so that the Sort / Hash Match receives a ~1 MB memory grant.
--   Look for the yellow warning triangle on Sort / Hash Match in the actual plan.
-- ============================================================================
IF OBJECT_ID('dbo.R3_Scans') IS NOT NULL DROP TABLE dbo.R3_Scans;
SELECT ScanID, PatientID, SeriesDescription, ImagePath INTO dbo.R3_Scans FROM dbo.MRI_Scans;
CREATE CLUSTERED INDEX CX_R3 ON dbo.R3_Scans(ScanID);
GO
-- 6a. Healthy statistics: ~37 MB grant, no spill
SELECT ScanID, ImagePath FROM dbo.R3_Scans ORDER BY ImagePath OPTION (MAXDOP 1, RECOMPILE);
GO
-- 6b. Stale statistics (table believed to hold 100 rows): 1 MB grant -> Sort spills
UPDATE STATISTICS dbo.R3_Scans WITH ROWCOUNT = 100, PAGECOUNT = 10;
GO
SELECT ScanID, ImagePath FROM dbo.R3_Scans ORDER BY ImagePath OPTION (MAXDOP 1, RECOMPILE);
GO
-- 6c. Same lie, Hash Match: spill level 3 and a Workfile in the I/O messages
SELECT COUNT(*) FROM dbo.R3_Scans a INNER JOIN dbo.R3_Scans b ON a.ImagePath = b.ImagePath
OPTION (HASH JOIN, MAXDOP 1, RECOMPILE);
GO
DROP TABLE dbo.R3_Scans;      -- clean up
GO

-- ============================================================================
-- SECTION 7 -- Adaptive Join (Intelligent Query Processing, batch mode)
--   A rowstore index + a columnstore index are created temporarily so that the
--   join can run in batch mode; both are rolled back at the end.
-- ============================================================================
BEGIN TRAN;
CREATE NONCLUSTERED INDEX IX_R3_Scans_PatientID ON dbo.MRI_Scans(PatientID) INCLUDE (SeriesDescription);
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_R3_Feat ON dbo.Image_Features(ScanID, V_Dim1, V_Dim2, V_Dim3, V_Dim4);
GO
-- Parameterised on purpose: the plan must work for few rows AND many rows.
EXEC sp_executesql
  N'SELECT s.SeriesDescription, COUNT(*) c, AVG(f.V_Dim1) a
    FROM dbo.Image_Features f INNER JOIN dbo.MRI_Scans s ON f.ScanID = s.ScanID
    WHERE s.PatientID <= @p GROUP BY s.SeriesDescription',
  N'@p VARCHAR(20)', @p = '0500';     -- many rows
GO
EXEC sp_executesql
  N'SELECT s.SeriesDescription, COUNT(*) c, AVG(f.V_Dim1) a
    FROM dbo.Image_Features f INNER JOIN dbo.MRI_Scans s ON f.ScanID = s.ScanID
    WHERE s.PatientID <= @p GROUP BY s.SeriesDescription',
  N'@p VARCHAR(20)', @p = '0003';     -- few rows: same plan, join type decided at run time
GO
-- In the plan, open the "Adaptive Join" operator: Adaptive Threshold Rows,
-- Estimated Join Type, Actual Join Type.
ROLLBACK TRAN;
GO

-- ============================================================================
-- SECTION 8 -- Verify that the database is back to its baseline
-- ============================================================================
SELECT OBJECT_NAME(object_id) AS tbl, name AS idx, type_desc
FROM sys.indexes
WHERE object_id IN (OBJECT_ID('dbo.Patients'), OBJECT_ID('dbo.MRI_Scans'), OBJECT_ID('dbo.Image_Features'))
ORDER BY 1, 2;
SELECT OBJECT_ID('dbo.R3_Scans') AS r3_scans_should_be_null;
SET STATISTICS IO OFF; SET STATISTICS TIME OFF;
GO
