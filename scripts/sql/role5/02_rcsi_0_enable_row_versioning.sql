-- ============================================================================
-- Scenario 02 - MVCC: enable row versioning (run AFTER the locking baseline)
-- 99_reset.sql turns it OFF again.
-- ============================================================================
USE master;
GO
-- READ COMMITTED silently becomes "Read Committed Snapshot" (RCSI).
-- Needs exclusive access -> roll back other sessions' open transactions.
ALTER DATABASE SpineMRI_DBMS SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
-- SNAPSHOT isolation level becomes available (must be requested per session)
ALTER DATABASE SpineMRI_DBMS SET ALLOW_SNAPSHOT_ISOLATION ON;
GO
SELECT name, snapshot_isolation_state_desc AS SnapshotIsolation,
       is_read_committed_snapshot_on AS RCSI
FROM sys.databases WHERE name = 'SpineMRI_DBMS';
GO
