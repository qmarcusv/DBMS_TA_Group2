-- ============================================================================
-- Course: Database Management Systems (CO3021) - Semester 261
-- Group: Group 02
-- Target Database: SpineMRI_DBMS (575 Patients, 48,345 Scans, 48,345 Features)
-- Target Engine: Microsoft SQL Server 2025
-- 
-- ROLE DIVISION SPECIFICATION:
-- ----------------------------------------------------------------------------
-- [PART I: ROLE 5.1 MANDATORY BENCHMARK]
--   Scope: Pessimistic Concurrency Control, Strict 2PL, Lock Manager Internals,
--          The 3 Read Phenomena (Dirty Read, Non-Repeatable Read, Phantom Read),
--          Key-Range Locks (SERIALIZABLE), and Lock Escalation (>5,000 locks).
--   Mapping:
--     - Case 1 (Canonical Query 1): Non-Repeatable Read & Clustered Index Seek
--     - Case 2 (Canonical Query 2): Phantom Read & Key-Range Locks (RangeS-S)
--     - Case 3 (Canonical Query 3): Lock Escalation on 48,345 Slices (OBJECT: S)
--     - Case 4 (Clinical Update):   Dirty Read Anomaly (READ UNCOMMITTED vs READ COMMITTED)
--   Outputs: Figures 2.3, 2.4, 2.5 and Table 2.2 in Chapter 6 Technical Report.
-- 
-- [PART II: ROLE 5.2 REFERENCE BENCHMARK]
--   Scope: Deadlock Cycle Detection (Msg 1205), SET DEADLOCK_PRIORITY,
--          Deadlock Graph (.xdl / system_health), MVCC / RCSI, and tempdb Version Store.
--   NOTE: Provided here for full group coordination. Member 5.1 DOES NOT need
--         to run or document Part II in Chapter 6!
-- ============================================================================

USE SpineMRI_DBMS;
GO


-- ============================================================================
-- ============================================================================
-- PART I: ROLE 5.1 MANDATORY SCOPE (READ PHENOMENA & PESSIMISTIC LOCKING)
-- ============================================================================
-- ============================================================================


-- ============================================================================
-- CASE 1 [ROLE 5.1]: CANONICAL QUERY 1 (NON-REPEATABLE READ BENCHMARK)
-- Clinical Context: Single-patient clinical narrative and MRI slice lookup.
-- Engine Concept: Clustered Index Seek on PK_Patients, fine-grained KEY: S locks,
--                 and Non-Repeatable Read demonstration:
--                 - READ COMMITTED: S-locks dropped immediately -> Row can be modified.
--                 - REPEATABLE READ: S-locks held until COMMIT -> Prevents Non-Repeatable Read.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- [CASE 1 - STEP 1]: Open Transaction in [SESSION 1] (Query Window 1)
-- ----------------------------------------------------------------------------
/* Execute in Query Window 1: */
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
-- -> USE THIS CAPTURE FOR FIGURE 2.3 IN CHAPTER 6!
-- ----------------------------------------------------------------------------
/* Execute in Query Window 3: */
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


-- ----------------------------------------------------------------------------
-- [CASE 1 - STEP 3]: Concurrent Conflict Attempt in [SESSION 2] (Query Window 2)
-- ----------------------------------------------------------------------------
/* Execute in Query Window 2 while Session 1 is open: */
/*
    USE SpineMRI_DBMS;
    -- Requires Exclusive KEY: X lock, which conflicts with Session 1's KEY: S:
    UPDATE Patients 
    SET PatientName = 'Patient 0001 (Modified Name)' 
    WHERE PatientID = '0001';
    -- [OBSERVE]: Session 2 BLOCKS waiting for Session 1 to release KEY: S!
*/


-- ----------------------------------------------------------------------------
-- [CASE 1 - STEP 4]: Complete Session 1 in [SESSION 1] (Query Window 1)
-- ----------------------------------------------------------------------------
/* Back in Query Window 1, release the transaction: */
COMMIT TRANSACTION;

-- [OBSERVE]: Session 2 immediately unblocks and returns "(1 row affected)".
-- Revert the patient name back to clean state:
UPDATE Patients SET PatientName = 'Patient 0001' WHERE PatientID = '0001';
GO



-- ============================================================================
-- CASE 2 [ROLE 5.1]: CANONICAL QUERY 2 (PHANTOM READ & KEY-RANGE LOCKS)
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


-- [STEP 2A.2 - SESSION 2 (Query Window 2)]: Insert a phantom slice for Patient 0001
/* Execute in Query Window 2: */

USE SpineMRI_DBMS;
INSERT INTO MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath)
VALUES ('0001', 'STUDY_TEST_PHANTOM', 'T2_TSE_SAG_NEW', '01_MRI_Data/phantom_slice.dcm');



-- [STEP 2A.3 - SESSION 1 (Query Window 1)]: Re-read the exact same query
SELECT COUNT(*) AS [T2_Scan_Count_After_Concurrent_Insert]
FROM Patients p
INNER JOIN MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';

-- [OBSERVE PHANTOM READ]:
-- The count increased by 1! REPEATABLE READ only locked existing rows;
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
USE SpineMRI_DBMS;
-- This insert will BLOCK immediately because Session 1 holds RangeS-S locks:
INSERT INTO MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath)
VALUES ('0001', 'STUDY_TEST_SERIAL', 'T2_TSE_SAG_SERIAL', '01_MRI_Data/serial_slice.dcm');


-- [STEP 2B.3 - MONITOR WINDOW (Query Window 3)]:
-- -> USE THIS CAPTURE FOR FIGURE 2.4 IN CHAPTER 6!
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

-- Cleanup if Session 2's insert finalized after commit:
DELETE FROM MRI_Scans WHERE StudyInstanceUID = 'STUDY_TEST_SERIAL';
GO



-- ============================================================================
-- CASE 3 [ROLE 5.1]: CANONICAL QUERY 3 (MASSIVE WORKLOAD & LOCK ESCALATION)
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
-- -> USE THIS CAPTURE FOR FIGURE 2.5 IN CHAPTER 6!
-- ----------------------------------------------------------------------------
/* Execute this in Query Window 3: */
SELECT 
    tl.request_session_id AS [SPID],
    tl.resource_type AS [Resource],
    tl.request_mode AS [LockMode],
    tl.request_status AS [Status],
    CASE tl.resource_type 
        WHEN 'OBJECT' THEN OBJECT_NAME(tl.resource_associated_entity_id)
        ELSE OBJECT_NAME(p.object_id)
    END AS [TableName]
FROM sys.dm_tran_locks tl
LEFT JOIN sys.partitions p 
    ON tl.resource_associated_entity_id = p.hobt_id
WHERE tl.resource_database_id = DB_ID('SpineMRI_DBMS')
  AND tl.request_session_id <> @@SPID;

-- [EXPECTED OBSERVATION FOR FIGURE 2.5]:
-- SQL Server has converted thousands of individual row/page locks into:
-- Resource = OBJECT | LockMode = S | TableName = Image_Features
-- Memory is saved, but concurrent writes to Image_Features are now blocked!


-- ----------------------------------------------------------------------------
-- [CASE 3 - STEP 4]: Cleanup in [SESSION 1] (Query Window 1)
-- ----------------------------------------------------------------------------
/* Release transaction in Query Window 1: */
ROLLBACK TRANSACTION;
GO



-- ============================================================================
-- CASE 4 [ROLE 5.1]: DIRTY READ ANOMALY (TEMPORARY UPDATE VIOLATION)
-- Clinical Context: Clinician modifies patient notes, then aborts transaction.
-- Engine Concept: READ UNCOMMITTED (dirty read allowed) vs READ COMMITTED (blocked).
-- ============================================================================

-- [STEP 4.1 - SESSION 1 (Query Window 1)]: Uncommitted modification
BEGIN TRANSACTION;
UPDATE Patients 
SET ClinicalNotes = 'CRITICAL CORRECTION: Severe disc herniation with nerve root impingement.'
WHERE PatientID = '0001';
-- [PAUSE - DO NOT COMMIT]


-- [STEP 4.2 - SESSION 2 (Query Window 2)]: Dirty read via READ UNCOMMITTED
/* Execute in Query Window 2: */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT PatientID, ClinicalNotes 
FROM Patients 
WHERE PatientID = '0001';
-- [OBSERVE]: Session 2 reads the uncommitted note ('CRITICAL CORRECTION')!


-- [STEP 4.3 - SESSION 1 (Query Window 1)]: Transaction aborts
ROLLBACK TRANSACTION;


-- [STEP 4.4 - SESSION 2 (Query Window 2)]: Re-read

SELECT PatientID, ClinicalNotes 
FROM Patients 
WHERE PatientID = '0001';
-- [OBSERVE]: Value has reverted. Session 2 had processed false "dirty" data!

GO




-- ============================================================================
-- ============================================================================
-- PART II: ROLE 5.2 SCOPE (FOR REFERENCE & GROUP COORDINATION ONLY)
-- ============================================================================
-- ATTENTION MEMBER 5.1:
-- The modules below belong strictly to the domain of MEMBER 5.2 (Deadlock & MVCC).
-- You DO NOT need to run, capture, or document these in your Chapter 6 report!
-- They are maintained here so your group shares a unified, single repository script.
-- ============================================================================

-- ============================================================================
-- CASE 5 [ROLE 5.2 SCOPE]: DEADLOCK REPRODUCTION & WAIT-FOR GRAPH (MSG 1205)
-- Assigned Member: Role 5.2
-- Engine Concept: Deadlock detection via Waits-For Graph cycle, SET DEADLOCK_PRIORITY,
--                 and Deadlock Graph (.xdl / Extended Events system_health).
-- ============================================================================

-- [STEP 5.1 - INSTRUCTIONS FOR ROLE 5.2]:
-- Execute Block 1 in Session 1, then IMMEDIATELY execute Block 2 in Session 2.

-- [SESSION 1 SCRIPT (Query Window 1)]:
/*
    USE SpineMRI_DBMS;
    SET DEADLOCK_PRIORITY NORMAL;
    BEGIN TRANSACTION;
    UPDATE Patients SET DiagnosisStatus = 'Reviewing' WHERE PatientID = '0001';
    WAITFOR DELAY '00:00:05'; -- Pause 5s to let Session 2 acquire its lock
    UPDATE MRI_Scans SET SeriesDescription = SeriesDescription WHERE ScanID = 1;
    COMMIT TRANSACTION;
*/

-- [SESSION 2 SCRIPT (Query Window 2)]:
/*
    USE SpineMRI_DBMS;
    SET DEADLOCK_PRIORITY LOW; -- Lower priority guarantees Session 2 is victim!
    BEGIN TRANSACTION;
    UPDATE MRI_Scans SET SeriesDescription = SeriesDescription WHERE ScanID = 1;
    WAITFOR DELAY '00:00:05'; -- Pause 5s to let Session 1 acquire its lock
    UPDATE Patients SET DiagnosisStatus = 'Reviewing' WHERE PatientID = '0001';
    COMMIT TRANSACTION;
*/

-- [ENGINE DEADLOCK RESOLUTION (ROLE 5.2 OUTPUT)]:
-- "Msg 1205, Level 13, State 45: Transaction (Process ID ...) was deadlocked on 
--  lock resources with another process and has been chosen as the deadlock victim. 
--  Rerun the transaction."
-- Role 5.2 extracts the Deadlock Graph from Extended Events system_health!
GO


-- ============================================================================
-- CASE 6 [ROLE 5.2 SCOPE]: ROW VERSIONING (RCSI) & TEMPDB VERSION STORE
-- Assigned Member: Role 5.2
-- Engine Concept: Read Committed Snapshot Isolation (RCSI), non-blocking reads,
--                 and tempdb Version Store monitoring.
-- ============================================================================

-- [STEP 6.1 - ENABLE RCSI AT DATABASE LEVEL (ROLE 5.2 ONLY)]:
/*
    ALTER DATABASE SpineMRI_DBMS SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
*/

-- [STEP 6.2 - NON-BLOCKING READ TEST (ROLE 5.2)]:
-- Session 1 modifies a row without committing:
/*
    BEGIN TRANSACTION;
    UPDATE Patients SET DiagnosisStatus = 'Evaluating' WHERE PatientID = '0001';
    -- Under RCSI, Session 2 can READ this row without waiting for Session 1!
*/

-- [STEP 6.3 - MONITOR TEMPDB VERSION STORE SPACE (ROLE 5.2)]:
/*
    SELECT 
        SUM(version_store_reserved_page_count) * 8 / 1024.0 AS [VersionStore_MB],
        SUM(user_object_reserved_page_count) * 8 / 1024.0 AS [UserObjects_MB]
    FROM sys.dm_db_file_space_usage;
*/

-- [REVERT RCSI BACK TO DEFAULT PESSIMISTIC LOCKING]:
/*
    ALTER DATABASE SpineMRI_DBMS SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
*/
GO
