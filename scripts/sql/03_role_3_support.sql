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
