-- ============================================================================
-- Course: Database Management Systems (CO3021) - Semester 261
-- Group: Group 02
-- Role: Role 5.1 (Concurrency Control, Lock Manager Internals, Isolation Levels)
-- Database Engine: Microsoft SQL Server 2025
-- Target Database: SpineMRI_DBMS (575 Patients, 48,345 Scans, 48,345 Features)
-- 
-- WORKLOAD-DRIVEN CONCURRENCY CONTROL BENCHMARK
-- Organized sequentially by CANONICAL QUERY CASE (Case 1, Case 2, Case 3, Case 4).
-- For each case, the script clearly separates:
--   - [SESSION 1]: Workload / Holding Transaction (Query Window 1)
--   - [SESSION 2]: Concurrent Access / Conflict Attempt (Query Window 2)
--   - [MONITOR]: Dynamic Management View (DMV) Lock Inspector (Query Window 3)
-- ============================================================================

USE SpineMRI_DBMS;
GO


-- ============================================================================
-- CASE 1: CANONICAL QUERY 1 (Patient Point Lookup & Scan Retrieval)
-- Clinical Context: Single-patient clinical narrative and MRI slice lookup.
-- Engine Concept: Clustered Index Seek on PK_Patients, fine-grained KEY: S locks,
--                 and lock lifecycle comparison:
--                 - READ COMMITTED: S-locks dropped immediately after statement.
--                 - REPEATABLE READ: S-locks held until transaction COMMIT.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- [CASE 1 - STEP 1]: Open Transaction in [SESSION 1] (Query Window 1)
-- ----------------------------------------------------------------------------
/* Execute this in Query Window 1: */
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;

-- Canonical Query 1
SELECT 
    p.PatientID, p.PatientName, p.ClinicalNotes,
    s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001';

-- [PAUSE HERE - DO NOT COMMIT YET]
-- Transaction remains active. Session 1 is currently holding shared locks.


-- ----------------------------------------------------------------------------
-- [CASE 1 - STEP 2]: Inspect Locks in [MONITOR WINDOW] (Query Window 3)
-- -> USE THIS CAPTURE FOR FIGURE 2.3 IN YOUR TECHNICAL REPORT!
-- ----------------------------------------------------------------------------
/* 
   OPTION A (RECOMMENDED FOR FIGURE 2.3 - Hierarchical MGL Order):
   Orders locks in true Top-Down Multiple Granularity Locking (MGL) hierarchy:
   DATABASE -> OBJECT (IS) -> PAGE (IS) -> KEY (S)
   Correctly resolves OBJECT table names for publication quality!
*/
SELECT 
    tl.resource_type AS [Resource],
    tl.request_mode AS [LockMode],
    CASE 
        WHEN tl.resource_type = 'OBJECT' THEN OBJECT_NAME(tl.resource_associated_entity_id)
        WHEN tl.resource_type = 'DATABASE' THEN DB_NAME(tl.resource_database_id)
        ELSE OBJECT_NAME(p.object_id)
    END AS [EntityName],
    ISNULL(i.name, 'N/A') AS [IndexName],
    COUNT(*) AS [LockCount]
FROM sys.dm_tran_locks tl
LEFT JOIN sys.partitions p 
    ON tl.resource_associated_entity_id = p.hobt_id
LEFT JOIN sys.indexes i 
    ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE tl.resource_database_id = DB_ID('SpineMRI_DBMS')
  AND tl.request_session_id <> @@SPID -- Exclude monitoring session
GROUP BY 
    tl.resource_type, 
    tl.request_mode, 
    CASE 
        WHEN tl.resource_type = 'OBJECT' THEN OBJECT_NAME(tl.resource_associated_entity_id)
        WHEN tl.resource_type = 'DATABASE' THEN DB_NAME(tl.resource_database_id)
        ELSE OBJECT_NAME(p.object_id)
    END,
    i.name
ORDER BY 
    CASE tl.resource_type 
        WHEN 'DATABASE' THEN 1
        WHEN 'OBJECT'   THEN 2
        WHEN 'PAGE'     THEN 3
        WHEN 'KEY'      THEN 4
        ELSE 5 
    END ASC,
    [EntityName] ASC,
    [LockCount] ASC;

/* 
   OPTION B (Granular View - Filter by your Session 1 SPID, e.g., 53):
   Replace 53 with your actual SPID from Window 1:
*/
/*
SELECT 
    tl.request_session_id AS [SPID],
    tl.resource_type AS [Resource],
    tl.request_mode AS [LockMode],
    tl.request_status AS [Status],
    OBJECT_NAME(p.object_id) AS [TableName],
    i.name AS [IndexName]
FROM sys.dm_tran_locks tl
LEFT JOIN sys.partitions p 
    ON tl.resource_associated_entity_id = p.hobt_id
LEFT JOIN sys.indexes i 
    ON p.object_id = i.object_id AND p.index_id = i.index_id
WHERE tl.resource_database_id = DB_ID('SpineMRI_DBMS')
  AND tl.request_session_id = 53 -- Replace with your Session 1 SPID!
ORDER BY tl.resource_type;
*/

-- [EXPECTED OBSERVATION FOR FIGURE 2.3]:
-- 1. TableName = Patients  | Resource = OBJECT | LockMode = IS (Intention Shared)
-- 2. TableName = Patients  | Resource = KEY    | LockMode = S  | IndexName = PK_Patients
-- 3. TableName = MRI_Scans | Resource = OBJECT | LockMode = IS
-- 4. TableName = MRI_Scans | Resource = KEY    | LockMode = S  (for scan rows of Patient 0001)


-- ----------------------------------------------------------------------------
-- [CASE 1 - STEP 3]: Concurrent Conflict Attempt in [SESSION 2] (Query Window 2)
-- ----------------------------------------------------------------------------
/* Execute this in Query Window 2 while Session 1 is still open: */
/*
    USE SpineMRI_DBMS;
    -- This update requires an Exclusive KEY: X lock, which conflicts with Session 1's KEY: S:
    UPDATE Patients 
    SET PatientName = 'Patient 0001 (Modified Name)' 
    WHERE PatientID = '0001';
    -- [OBSERVE]: Session 2 HANGS in a blocked state waiting for Session 1 to release locks!
*/


-- ----------------------------------------------------------------------------
-- [CASE 1 - STEP 4]: Complete Session 1 in [SESSION 1] (Query Window 1)
-- ----------------------------------------------------------------------------
/* Back in Query Window 1, release the lock: */
COMMIT TRANSACTION;

-- [OBSERVE]: As soon as Session 1 commits, Session 2 immediately unblocks and succeeds!
-- Revert the patient name back to clean state:
UPDATE Patients SET PatientName = 'Patient 0001' WHERE PatientID = '0001';
GO



-- ============================================================================
-- CASE 2: CANONICAL QUERY 2 (Filtered T2 Sagittal Scan Retrieval & Key-Range)
-- Clinical Context: Radiologist queries T2 Sagittal pulse sequences for herniation.
-- Engine Concept: Non-key predicate (%T2%SAG%), Phantom Read vulnerability under
--                 REPEATABLE READ, and Phantom Elimination via Key-Range Locks
--                 (RangeS-S) on B-Tree index intervals under SERIALIZABLE.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- [CASE 2A]: REPRODUCING PHANTOM READ UNDER REPEATABLE READ
-- ----------------------------------------------------------------------------

-- [STEP 2A.1 - SESSION 1 (Query Window 1)]: Count qualifying T2 sagittal scans
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN TRANSACTION;

SELECT COUNT(*) AS [Initial_T2_Scan_Count]
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';

-- [PAUSE HERE - DO NOT COMMIT YET]


-- [STEP 2A.2 - SESSION 2 (Query Window 2)]: Insert a new slice for Patient 0001
/* Execute in Query Window 2: */
/*
    USE SpineMRI_DBMS;
    INSERT INTO MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath)
    VALUES ('0001', 'STUDY_TEST_PHANTOM', 'T2_TSE_SAG_NEW', '01_MRI_Data/phantom_slice.dcm');
*/


-- [STEP 2A.3 - SESSION 1 (Query Window 1)]: Re-read the exact same query
SELECT COUNT(*) AS [T2_Scan_Count_After_Concurrent_Insert]
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';

-- [OBSERVE PHANTOM READ]:
-- The count increased by 1! REPEATABLE READ only locked EXISTING rows;
-- it could not prevent the insertion of a new row (a Phantom) into the gap!

COMMIT TRANSACTION;

-- Cleanup phantom row:
DELETE FROM MRI_Scans WHERE StudyInstanceUID = 'STUDY_TEST_PHANTOM';
GO


-- ----------------------------------------------------------------------------
-- [CASE 2B]: ELIMINATING PHANTOM READS UNDER SERIALIZABLE (KEY-RANGE LOCKS)
-- ----------------------------------------------------------------------------

-- [STEP 2B.1 - SESSION 1 (Query Window 1)]: Execute Query 2 under SERIALIZABLE
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;

SELECT 
    p.PatientID, p.PatientName, p.ClinicalNotes,
    s.ScanID, s.SeriesDescription, s.ImagePath
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';

-- [PAUSE HERE - DO NOT COMMIT YET]


-- [STEP 2B.2 - SESSION 2 (Query Window 2)]: Attempt concurrent insert
/* Execute in Query Window 2: */
/*
    USE SpineMRI_DBMS;
    -- This insert will BLOCK immediately because Session 1 holds RangeS-S locks:
    INSERT INTO MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath)
    VALUES ('0001', 'STUDY_TEST_SERIAL', 'T2_TSE_SAG_SERIAL', '01_MRI_Data/serial_slice.dcm');
*/


-- [STEP 2B.3 - MONITOR WINDOW (Query Window 3)]:
-- -> USE THIS CAPTURE FOR FIGURE 2.4 IN YOUR TECHNICAL REPORT!
SELECT 
    wt.session_id AS [BlockedSessionID],
    wt.wait_duration_ms AS [WaitDuration_MS],
    wt.wait_type AS [WaitType],
    wt.blocking_session_id AS [BlockingSessionID],
    tl.resource_type AS [ResourceType],
    tl.request_mode AS [LockModeHeldBySession1]
FROM sys.dm_os_waiting_tasks wt
JOIN sys.dm_tran_locks tl 
    ON wt.blocking_session_id = tl.request_session_id
WHERE wt.blocking_session_id IS NOT NULL;

-- [EXPECTED OBSERVATION FOR FIGURE 2.4]:
-- Session 2 is BLOCKED with WaitType = LCK_M_RANGEI_N.
-- Session 1 holds LockMode = RangeS-S protecting the B-Tree interval.
-- Phantom insertion is completely prevented!

-- [STEP 2B.4 - SESSION 1 (Query Window 1)]: Release transaction
COMMIT TRANSACTION;

-- Cleanup if Session 2's insert went through after commit:
DELETE FROM MRI_Scans WHERE StudyInstanceUID = 'STUDY_TEST_SERIAL';
GO



-- ============================================================================
-- CASE 3: CANONICAL QUERY 3 (AI Feature Similarity Retrieval & Lock Escalation)
-- Clinical Context: Content-Based Image Retrieval (CBIR) across 48,345 slices.
-- Engine Concept: Exhaustive Clustered Index Scan on Image_Features, CPU Vector
--                 Euclidean Distance computation, and Lock Escalation Dynamics
--                 (Converting >5,000 fine row/page locks to an OBJECT: S table lock).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- [CASE 3 - STEP 1]: Canonical Query 3 Execution & Execution Plan
-- Enable "Include Actual Execution Plan" (Ctrl + M) in SSMS before running!
-- ----------------------------------------------------------------------------
DECLARE @TargetScanID INT = 1;
DECLARE @T1 FLOAT, @T2 FLOAT, @T3 FLOAT, @T4 FLOAT;

-- 1. Fetch reference embedding dimensions
SELECT @T1 = V_Dim1, @T2 = V_Dim2, @T3 = V_Dim3, @T4 = V_Dim4 
FROM Image_Features 
WHERE ScanID = @TargetScanID;

-- 2. Brute-force 48,345-row vector distance comparison
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

-- [EXECUTION PLAN OBSERVATION FOR FIGURE 2.5]:
-- Observe the Clustered Index Scan operator across all 48,345 rows in Image_Features,
-- followed by Compute Scalar (distance formula) and Top N Sort.


-- ----------------------------------------------------------------------------
-- [CASE 3 - STEP 2]: Simulating Lock Escalation on Image_Features
-- When a query accumulates >5,000 discrete locks, SQL Server escalates fine locks
-- to a single table-level lock (OBJECT: S) to save memory.
-- ----------------------------------------------------------------------------
/* Execute this in [SESSION 1] (Query Window 1): */
BEGIN TRANSACTION;

-- Read > 5,000 rows under REPEATABLE READ to trigger escalation threshold:
SELECT TOP 6000 FeatureID, V_Dim1
FROM Image_Features WITH (REPEATABLEREAD)
ORDER BY FeatureID;

-- [PAUSE HERE - DO NOT ROLLBACK YET]


-- ----------------------------------------------------------------------------
-- [CASE 3 - STEP 3]: Monitor Lock Escalation in [MONITOR WINDOW] (Query Window 3)
-- -> USE THIS CAPTURE FOR FIGURE 2.5 IN YOUR TECHNICAL REPORT!
-- ----------------------------------------------------------------------------
/* Execute this in Query Window 3: */
SELECT 
    tl.request_session_id AS [SPID],
    tl.resource_type AS [Resource],
    tl.request_mode AS [LockMode],
    tl.request_status AS [Status],
    OBJECT_NAME(p.object_id) AS [TableName]
FROM sys.dm_tran_locks tl
LEFT JOIN sys.partitions p 
    ON tl.resource_associated_entity_id = p.hobt_id
WHERE tl.resource_database_id = DB_ID('SpineMRI_DBMS')
  AND tl.request_session_id <> @@SPID;

-- [EXPECTED OBSERVATION FOR FIGURE 2.5]:
-- SQL Server has converted individual row/page locks into:
-- Resource = OBJECT | LockMode = S | TableName = Image_Features
-- Memory is saved, but concurrent writes to Image_Features are now blocked!


-- ----------------------------------------------------------------------------
-- [CASE 3 - STEP 4]: Cleanup in [SESSION 1] (Query Window 1)
-- ----------------------------------------------------------------------------
/* Release the transaction in Query Window 1: */
ROLLBACK TRANSACTION;
GO



-- ============================================================================
-- CASE 4: CLASSICAL CONCURRENCY ANOMALIES & DEADLOCK LABORATORY
-- Clinical Context: Diagnostic record updates, concurrent clinician edits.
-- Engine Concept: Temporary Update (Dirty Read) and Deadlock Detection (Victim 1205).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- [CASE 4.1]: DIRTY READ ANOMALY (READ UNCOMMITTED)
-- ----------------------------------------------------------------------------

-- [STEP 4.1A - SESSION 1 (Query Window 1)]: Uncommitted modification
BEGIN TRANSACTION;
UPDATE Patients 
SET ClinicalNotes = 'CRITICAL CORRECTION: Severe disc herniation with nerve root impingement.'
WHERE PatientID = '0001';
-- [PAUSE - DO NOT COMMIT]


-- [STEP 4.1B - SESSION 2 (Query Window 2)]: Dirty read via READ UNCOMMITTED
/* Execute in Query Window 2: */
/*
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
    SELECT PatientID, ClinicalNotes 
    FROM Patients 
    WHERE PatientID = '0001';
    -- [OBSERVE]: Session 2 reads the uncommitted note ('CRITICAL CORRECTION')!
*/


-- [STEP 4.1C - SESSION 1 (Query Window 1)]: Transaction aborts
ROLLBACK TRANSACTION;


-- [STEP 4.1D - SESSION 2 (Query Window 2)]: Re-read
/*
    SELECT PatientID, ClinicalNotes 
    FROM Patients 
    WHERE PatientID = '0001';
    -- [OBSERVE]: Value has reverted. Session 2 had processed false "dirty" data!
*/
GO


-- ----------------------------------------------------------------------------
-- [CASE 4.2]: DEADLOCK REPRODUCTION & AUTOMATIC RESOLUTION (ERROR 1205)
-- ----------------------------------------------------------------------------

-- [STEP 4.2A - INSTRUCTIONS]:
-- 1. Open Query Window 1 ([SESSION 1]) and Query Window 2 ([SESSION 2]).
-- 2. Execute Block 1 in Window 1, then IMMEDIATELY execute Block 2 in Window 2.

-- [SESSION 1 SCRIPT (Query Window 1)]:
/*
    BEGIN TRANSACTION;
    UPDATE Patients SET DiagnosisStatus = 'Reviewing' WHERE PatientID = '0001';
    WAITFOR DELAY '00:00:05'; -- Pause 5 seconds to let Session 2 acquire its lock
    UPDATE MRI_Scans SET SeriesDescription = SeriesDescription WHERE ScanID = 1;
    COMMIT TRANSACTION;
*/

-- [SESSION 2 SCRIPT (Query Window 2)]:
/*
    BEGIN TRANSACTION;
    UPDATE MRI_Scans SET SeriesDescription = SeriesDescription WHERE ScanID = 1;
    WAITFOR DELAY '00:00:05'; -- Pause 5 seconds to let Session 1 acquire its lock
    UPDATE Patients SET DiagnosisStatus = 'Reviewing' WHERE PatientID = '0001';
    COMMIT TRANSACTION;
*/

-- [ENGINE DEADLOCK RESOLUTION]:
-- After 5 seconds, SQL Server's background Deadlock Monitor thread detects the cycle:
-- "Msg 1205, Level 13, State 45: Transaction (Process ID ...) was deadlocked on 
--  lock resources with another process and has been chosen as the deadlock victim. 
--  Rerun the transaction."
-- The engine rolls back the lower-cost transaction and allows the other to commit!
GO
