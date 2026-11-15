-- ============================================================================
-- Role 5.2 - LOCK MONITOR (third window). Run while Session A is waiting.
-- ============================================================================
USE SpineMRI_DBMS;
GO
SET NOCOUNT ON;

-- 1. Who is blocked by whom (live edges of the Waits-For Graph)
SELECT r.session_id            AS WaitingSession,
       r.blocking_session_id   AS BlockedBy,
       r.wait_type,
       r.wait_time             AS WaitMs,
       r.wait_resource,
       LTRIM(SUBSTRING(t.text, r.statement_start_offset / 2 + 1,
             (CASE r.statement_end_offset WHEN -1 THEN DATALENGTH(t.text)
                   ELSE r.statement_end_offset END - r.statement_start_offset) / 2 + 1))
                               AS WaitingStatement
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0;

-- 2. Lock table of the Lock Manager (exclude this monitoring session)
SELECT l.request_session_id                     AS SessionID,
       l.resource_type                          AS Resource,
       COALESCE(OBJECT_NAME(p.object_id),
                OBJECT_NAME(l.resource_associated_entity_id)) AS ObjectName,
       i.name                                   AS IndexName,
       RTRIM(l.resource_description)            AS KeyHashOrPage,
       l.request_mode                           AS Mode,      -- S, X, U, IS, IX ...
       l.request_status                         AS Status     -- GRANT / WAIT / CONVERT
FROM sys.dm_tran_locks l
LEFT JOIN sys.partitions p
       ON l.resource_type IN ('KEY', 'PAGE', 'RID', 'HOBT')
      AND p.hobt_id = l.resource_associated_entity_id
LEFT JOIN sys.indexes i
       ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE l.resource_database_id = DB_ID('SpineMRI_DBMS')
  AND l.request_session_id <> @@SPID
  AND l.resource_type <> 'DATABASE'
ORDER BY l.request_session_id, l.resource_type, l.request_mode;

-- 3. Isolation level and deadlock priority of every open user session
SELECT s.session_id,
       CASE s.transaction_isolation_level
            WHEN 1 THEN 'READ UNCOMMITTED' WHEN 2 THEN 'READ COMMITTED'
            WHEN 3 THEN 'REPEATABLE READ'  WHEN 4 THEN 'SERIALIZABLE'
            WHEN 5 THEN 'SNAPSHOT' END AS IsolationLevel,
       s.deadlock_priority,
       s.open_transaction_count
FROM sys.dm_exec_sessions s
WHERE s.database_id = DB_ID('SpineMRI_DBMS') AND s.session_id <> @@SPID;

-- 4. Row-version store usage in tempdb (scenario 02: RCSI / Snapshot)
SELECT DB_NAME(database_id) AS DatabaseName,
       reserved_page_count,
       reserved_space_kb
FROM sys.dm_tran_version_store_space_usage
WHERE database_id = DB_ID('SpineMRI_DBMS');
GO
