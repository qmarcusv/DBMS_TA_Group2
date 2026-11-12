-- ============================================================================
-- Role 3: Query Optimization
-- Supporting SQL for Q1 and Q3
-- ============================================================================

USE SpineMRI_DBMS;
GO

-- Q1: PatientID Statistics
-- Display statistics header and histogram for PatientID.
DBCC SHOW_STATISTICS (
    'dbo.MRI_Scans',
    '_WA_Sys_00000002_4BAC3F29'
);
GO


-- Q3: ScanID Statistics
-- Display statistics header and histogram for the unique ScanID index.
DBCC SHOW_STATISTICS (
    'dbo.Image_Features',
    'UQ__Image_Fe__63B32660DF05EFC2'
);
GO
