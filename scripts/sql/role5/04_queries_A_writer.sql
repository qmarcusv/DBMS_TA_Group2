-- ============================================================================
-- Scenario 04 - Q1/Q2/Q3 UNDER CONCURRENT WRITE   SESSION A (writer) -> F5 FIRST
-- A technician re-labels ONE slice of patient 0002 (ScanID = 80) and keeps the
-- transaction open for 10 s, then rolls back (data unchanged afterwards).
-- Patient 0002 is NOT part of the result of Q1/Q2 (patient 0001), but its row
-- may still be on the access path that SQL Server chose for the query.
-- Then run 04_queries_B_Q1.sql / _Q2.sql / _Q3.sql in Session B.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;

BEGIN TRANSACTION;
    UPDATE dbo.MRI_Scans
    SET SeriesDescription = 'T1_TSE_SAG_RELABEL'      -- touches the clustered index
    WHERE ScanID = 80;                                -- AND every index keyed on SeriesDescription
    EXEC dbo.usp_Role5_Log N'A: ScanID 80 (patient 0002) re-labelled, X locks held';

    -- >>> Switch to Session B and run one of 04_queries_B_Q1/Q2/Q3.sql <<<
    WAITFOR DELAY '00:00:10';

ROLLBACK TRANSACTION;
EXEC dbo.usp_Role5_Log N'A: ROLLBACK (data restored)';
GO
