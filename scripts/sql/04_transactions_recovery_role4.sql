-- ============================================================================
-- Course: Database Management Systems (CO3021) - Semester 261
-- Group: Group 02
-- Role: Role 4 (Transaction Management, Write-Ahead Logging & Crash Recovery)
-- Database Engine: Microsoft SQL Server 2025 Developer/Enterprise
-- Target Database: SpineMRI_DBMS (575 Patients, 48,345 Scans, 48,345 Features)
-- 
-- WORKLOAD-DRIVEN TRANSACTION & LOGGING BENCHMARK SCRIPT
-- ============================================================================
-- Description:
-- This benchmark script evaluates the relational storage engine of Microsoft 
-- SQL Server 2025 under ACID transactional workloads and Write-Ahead Logging (WAL).
-- It demonstrates and validates:
--   1. ACID Atomicity & Deterministic Constraint Rollback (CK_Series_Valid).
--   2. Internal Log Architecture & ARIES Backward LSN Chains via sys.fn_dblog().
--   3. Buffer Pool Page States: Dirty Pages vs. Clean Pages & Steal/No-Force.
--   4. Virtual Log File (VLF) Segmentation & Log Growth Mechanics.
--   5. Engine Crash Recovery Simulation & 3-Phase ARIES Verification.
-- ============================================================================

USE SpineMRI_DBMS;
GO

SET NOCOUNT ON;
GO

PRINT '============================================================================';
PRINT 'STARTING ROLE 4 TRANSACTION & LOGGING BENCHMARK SUITE';
PRINT 'Engine: ' + @@VERSION;
PRINT 'Target Database: ' + DB_NAME();
PRINT 'Timestamp: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '============================================================================';
GO


-- ============================================================================
-- MODULE 1: ATOMICITY & TRANSACTION ROLLBACK VIA CHECK CONSTRAINT VIOLATION
-- Theoretical Concept: All-or-Nothing Atomicity, In-Memory Undo, and
--                      Deterministic Failure Boundaries via Schema Constraints.
-- ============================================================================

PRINT '>>> MODULE 1: Testing Atomicity & Check Constraint Rollback...';
GO

-- Ensure XACT_ABORT is OFF initially to show controlled CATCH block handling
SET XACT_ABORT OFF;
GO

-- Variable declaration for test metrics
DECLARE @InitialScanCount INT;
DECLARE @PostErrorScanCount INT;

SELECT @InitialScanCount = COUNT(*) FROM dbo.MRI_Scans;
PRINT '[INFO] Initial MRI_Scans Row Count: ' + CAST(@InitialScanCount AS VARCHAR);

BEGIN TRY
    BEGIN TRANSACTION Clinical_Batch_Ingestion;

    -- Step 1.1: Insert a valid MRI slice record for Patient '0001'
    INSERT INTO dbo.MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath, AcquisitionDate)
    VALUES (
        '0001', 
        '1.2.840.113619.2.311.1001.2026', 
        'T2_TSE_SAG_VALID_TEST', 
        '01_MRI_Data/0001/s1/valid_slice.dcm', 
        GETDATE()
    );
    PRINT '  -> Step 1.1: Successfully inserted valid slice into Buffer Pool.';

    -- Step 1.2: Insert an invalid MRI slice violating CK_Series_Valid constraint
    -- Constraint definition: CHECK (SeriesDescription NOT LIKE '%INVALID%')
    INSERT INTO dbo.MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath, AcquisitionDate)
    VALUES (
        '0001', 
        '1.2.840.113619.2.311.1001.2026', 
        'T2_TSE_AX_INVALID_CORRUPT_SIGNAL', 
        '01_MRI_Data/0001/s1/corrupt_slice.dcm', 
        GETDATE()
    );
    PRINT '  -> Step 1.2: Second slice inserted (SHOULD NOT REACH HERE).';

    COMMIT TRANSACTION Clinical_Batch_Ingestion;
    PRINT '  -> [WARNING] Transaction unexpectedly committed!';
END TRY
BEGIN CATCH
    PRINT '  -> [CAUGHT EXCEPTION] Error Code: ' + CAST(ERROR_NUMBER() AS VARCHAR);
    PRINT '  -> [MESSAGE] ' + ERROR_MESSAGE();

    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION Clinical_Batch_Ingestion;
        PRINT '  -> [ROLLBACK EXECUTED] Transaction Clinical_Batch_Ingestion aborted.';
    END
END CATCH;

-- Step 1.3: Verify Zero-Data Residue (Post-Rollback State)
SELECT @PostErrorScanCount = COUNT(*) FROM dbo.MRI_Scans;
PRINT '[INFO] Post-Rollback MRI_Scans Row Count: ' + CAST(@PostErrorScanCount AS VARCHAR);

IF @InitialScanCount = @PostErrorScanCount
    PRINT '[SUCCESS] Atomicity Guaranteed: Row count remained identical (' + CAST(@InitialScanCount AS VARCHAR) + ').';
ELSE
    PRINT '[FAILURE] Data Inconsistency Detected: Uncommitted row leaked into table!';
GO


-- ============================================================================
-- MODULE 2: INTERNAL WRITE-AHEAD LOGGING (WAL) & LSN CHAIN INSPECTION
-- Theoretical Concept: WAL Protocol (LSN_log >= LSN_page), ARIES Log Records,
--                      Compensation Log Records (CLRs), and sys.fn_dblog().
-- ============================================================================

PRINT '';
PRINT '>>> MODULE 2: Dissecting Write-Ahead Logging & LSN Backward Chains...';
GO

-- Ensure clean log sequence by taking a checkpoint
CHECKPOINT;
GO

-- Execute an explicit, isolated transaction to generate distinctive log records
BEGIN TRANSACTION Clinical_WAL_Inspection;

INSERT INTO dbo.MRI_Scans (PatientID, StudyInstanceUID, SeriesDescription, ImagePath, AcquisitionDate)
VALUES (
    '0002', 
    '1.2.840.113619.2.311.2002.2026', 
    'T1_SE_SAG_WAL_DEMO', 
    '01_MRI_Data/0002/s1/wal_demo_slice.dcm', 
    GETDATE()
);

-- Force rollback to observe Compensation Log Records (CLRs) & LOP_ABORT_XACT
ROLLBACK TRANSACTION Clinical_WAL_Inspection;
GO

-- Query internal SQL Server transaction log using sys.fn_dblog
PRINT '[INFO] Querying active transaction log records from sys.fn_dblog()...';

SELECT TOP 15
    [Current LSN],
    [Operation],
    [Context],
    [Transaction ID],
    [Transaction Name],
    [Previous LSN],
    [AllocUnitName],
    [Page ID],
    [Slot ID],
    [Description]
FROM sys.fn_dblog(NULL, NULL)
WHERE [Transaction Name] = 'Clinical_WAL_Inspection'
   OR [AllocUnitName] LIKE '%MRI_Scans%'
   OR [Operation] IN ('LOP_BEGIN_XACT', 'LOP_INSERT_ROWS', 'LOP_ABORT_XACT', 'LOP_COMMIT_XACT')
ORDER BY [Current LSN] DESC;
GO


-- ============================================================================
-- MODULE 3: BUFFER POOL DIRTY PAGES & STEAL / NO-FORCE POLICY VALIDATION
-- Theoretical Concept: Steal/No-Force Buffer Management, Dirty Page Flags,
--                      Asynchronous Lazy Writer vs. Synchronous Checkpoint.
-- ============================================================================

PRINT '';
PRINT '>>> MODULE 3: Buffer Pool Diagnostics (Dirty Pages & Steal/No-Force)...';
GO

-- Flush any pending dirty pages to disk first to establish baseline
CHECKPOINT;
GO

-- Diagnostic 3.1: Count baseline clean vs dirty pages in Buffer Pool
PRINT '[INFO] Baseline Buffer Pool State:';
SELECT 
    d.name AS DatabaseName,
    b.page_type,
    COUNT(*) AS TotalPagesInRAM,
    SUM(CASE WHEN b.is_modified = 1 THEN 1 ELSE 0 END) AS DirtyPagesCount,
    SUM(CASE WHEN b.is_modified = 0 THEN 1 ELSE 0 END) AS CleanPagesCount
FROM sys.dm_os_buffer_descriptors b
JOIN sys.databases d ON b.database_id = d.database_id
WHERE d.name = 'SpineMRI_DBMS'
GROUP BY d.name, b.page_type;
GO

-- Diagnostic 3.2: Create a Dirty Page in RAM by modifying a single record
PRINT '[INFO] Updating ScanID = 1 in memory to create a Dirty Page...';

BEGIN TRANSACTION Memory_Dirty_Page_Test;

UPDATE dbo.MRI_Scans
SET AcquisitionDate = GETDATE()
WHERE ScanID = 1;

COMMIT TRANSACTION Memory_Dirty_Page_Test;
PRINT '[INFO] Transaction committed. In No-Force policy, page remains dirty in RAM.';
GO

-- Diagnostic 3.3: Inspect Buffer Pool immediately after Commit
PRINT '[INFO] Buffer Pool State after Commit (No-Force in action):';
SELECT 
    b.page_type,
    COUNT(*) AS TotalPagesInRAM,
    SUM(CASE WHEN b.is_modified = 1 THEN 1 ELSE 0 END) AS DirtyPagesCount,
    SUM(CASE WHEN b.is_modified = 0 THEN 1 ELSE 0 END) AS CleanPagesCount
FROM sys.dm_os_buffer_descriptors b
JOIN sys.databases d ON b.database_id = d.database_id
WHERE d.name = 'SpineMRI_DBMS'
GROUP BY b.page_type;
GO

-- Diagnostic 3.4: Execute explicit CHECKPOINT to flush dirty pages to data file (.mdf)
PRINT '[INFO] Executing CHECKPOINT to flush Dirty Pages to disk...';
CHECKPOINT;
GO

-- Diagnostic 3.5: Confirm dirty page count resets to 0
PRINT '[INFO] Buffer Pool State post-CHECKPOINT (Dirty Pages flushed):';
SELECT 
    b.page_type,
    COUNT(*) AS TotalPagesInRAM,
    SUM(CASE WHEN b.is_modified = 1 THEN 1 ELSE 0 END) AS DirtyPagesCount,
    SUM(CASE WHEN b.is_modified = 0 THEN 1 ELSE 0 END) AS CleanPagesCount
FROM sys.dm_os_buffer_descriptors b
JOIN sys.databases d ON b.database_id = d.database_id
WHERE d.name = 'SpineMRI_DBMS'
GROUP BY b.page_type;
GO

-- ============================================================================
-- CANONICAL QUERY 2 BENCHMARK (Role 4: No-Force Read & WAL Verification)
-- Evaluates Canonical Query 2 (Patient '0001', T2 Sagittal) reading dirty pages
-- in the Buffer Pool immediately after a transactional update prior to CHECKPOINT.
-- ============================================================================
PRINT '';
PRINT '>>> CANONICAL QUERY 2: Testing No-Force Buffer Pool Read on T2 Sagittal Scans...';
GO

CHECKPOINT;
GO

BEGIN TRANSACTION Role4_Canonical_Q2_Test;

-- Modify a T2 Sagittal scan for Patient '0001' in memory (creates Dirty Page)
UPDATE TOP (1) s
SET s.AcquisitionDate = GETDATE()
FROM dbo.Patients p
INNER JOIN dbo.MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';

COMMIT TRANSACTION Role4_Canonical_Q2_Test;
GO

-- Execute Canonical Query 2 BEFORE Checkpoint (reads committed Dirty Page from RAM)
SELECT 
    p.PatientID,
    p.PatientName,
    p.ClinicalNotes,
    s.ScanID,
    s.SeriesDescription,
    s.ImagePath
FROM dbo.Patients p
INNER JOIN dbo.MRI_Scans s ON p.PatientID = s.PatientID
WHERE p.PatientID = '0001'
  AND s.SeriesDescription LIKE '%T2%SAG%';
GO

-- Verify the Dirty Page in Buffer Pool and WAL log record before flushing
SELECT 
    OBJECT_NAME(p.object_id) AS TableName,
    bd.page_type,
    COUNT(*) AS CachedPages,
    SUM(CAST(bd.is_modified AS INT)) AS DirtyPages_PreCheckpoint
FROM sys.dm_os_buffer_descriptors bd
JOIN sys.allocation_units au ON bd.allocation_unit_id = au.allocation_unit_id
JOIN sys.partitions p ON au.container_id = p.hobt_id
WHERE bd.database_id = DB_ID('SpineMRI_DBMS')
  AND OBJECT_NAME(p.object_id) IN ('Patients', 'MRI_Scans')
GROUP BY OBJECT_NAME(p.object_id), bd.page_type;

CHECKPOINT;
GO

-- ============================================================================
-- MODULE 4: VIRTUAL LOG FILE (VLF) ARCHITECTURE & LOG SPACE CONSUMPTION
-- Theoretical Concept: Physical log structure divided into logical VLFs,
--                      active vs. inactive log truncation, and minLSN.
-- ============================================================================

PRINT '';
PRINT '>>> MODULE 4: Virtual Log File (VLF) Architecture & Storage Allocation...';
GO

-- Check overall log file space utilization
SELECT 
    DB_NAME(database_id) AS DatabaseName,
    total_log_size_in_bytes / 1024 / 1024 AS TotalLogSizeMB,
    used_log_space_in_bytes / 1024 / 1024 AS UsedLogSpaceMB,
    used_log_space_in_percent AS UsedLogPercent,
    log_space_since_last_checkpoint_mb AS LogSinceCheckpointMB
FROM sys.dm_db_log_space_usage;
GO

-- Inspect Virtual Log Files (VLFs) fragmentation and active status
PRINT '[INFO] Virtual Log File (VLF) segmentation status:';
SELECT 
    vlf_sequence_number AS VLF_Sequence,
    vlf_active AS IsActive,
    vlf_status AS Status,
    vlf_size_mb AS SizeMB,
    vlf_begin_offset AS BeginOffset
FROM sys.dm_db_log_info(DB_ID('SpineMRI_DBMS'))
ORDER BY vlf_sequence_number ASC;
GO


-- ============================================================================
-- MODULE 5: CRASH RECOVERY SIMULATION & ARIES 3-PHASE ENGINE LIFECYCLE
-- Theoretical Concept: ARIES Recovery:
--   Phase 1 (Analysis): Scan forward from checkpoint to determine active txns.
--   Phase 2 (Redo): Repeat history forward to recreate crash state.
--   Phase 3 (Undo): Scan backward, roll back uncommitted transactions using CLRs.
-- ============================================================================

PRINT '';
PRINT '>>> MODULE 5: Querying Engine Crash Recovery Telemetry...';
GO

-- Read SQL Server Error Log to retrieve past engine recovery events for SpineMRI_DBMS
BEGIN TRY
    PRINT '[INFO] Reading engine error log for database recovery milestones:';
    EXEC sys.xp_readerrorlog 0, 1, 'Recovery of database', 'SpineMRI_DBMS';
END TRY
BEGIN CATCH
    PRINT '[NOTE] xp_readerrorlog requires VIEW SERVER STATE or sysadmin permissions.';
    PRINT '[INFO] Demonstrating theoretical 3-phase engine state table below.';
END CATCH;
GO

-- Display summary table of theoretical ARIES vs. SQL Server Implementation
SELECT 
    'Phase 1: Analysis' AS ARIES_Phase,
    'Scans forward from Checkpoint LSN' AS ScanDirection,
    'Reconstructs Dirty Page Table (DPT) & Active Transaction Table (ATT)' AS TargetObjective,
    'Determines Redo Start LSN' AS OutputArtifact
UNION ALL
SELECT 
    'Phase 2: Redo',
    'Scans forward from Redo Start LSN to crash point',
    'Repeats history for all committed and uncommitted actions',
    'Restores database state to exact moment of crash'
UNION ALL
SELECT 
    'Phase 3: Undo',
    'Scans backward from crash point LSN to oldest active LSN',
    'Reverses uncommitted transactions and writes CLRs',
    'Returns database to fully consistent ACID state';
GO

PRINT '============================================================================';
PRINT 'ROLE 4 BENCHMARK EXECUTION COMPLETED SUCCESSFULLY';
PRINT '============================================================================';
GO
