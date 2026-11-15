-- ============================================================================
-- Scenario 01 - Retrieve the DEADLOCK GRAPH captured by the Deadlock Monitor
-- The built-in Extended Events session "system_health" records every
-- xml_deadlock_report. Click the XML cell in SSMS -> File > Save As ... .xdl
-- -> reopen the .xdl in SSMS to see the graphical Deadlock Graph.
-- GUI alternative: Object Explorer > Management > Extended Events > Sessions >
--   system_health > package0.event_file (double-click) > filter
--   name = xml_deadlock_report > tab "Deadlock".
-- Note: the event file is flushed asynchronously; if the newest deadlock does
-- not appear yet, wait a little and run again.
-- ============================================================================
USE master;
GO
SET QUOTED_IDENTIFIER ON;   -- required by XML methods (already ON in SSMS, OFF in sqlcmd)
GO
SELECT TOP (5)
       x.ev.value('(event/@timestamp)[1]', 'datetime2') AS DeadlockTimeUtc,
       x.ev.value('(event/data/value/deadlock/victim-list/victimProcess/@id)[1]', 'varchar(50)') AS VictimProcess,
       x.ev.query('(event/data/value/deadlock)[1]') AS DeadlockGraphXml
FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL) f
CROSS APPLY (SELECT CAST(f.event_data AS XML)) AS x(ev)
WHERE f.object_name = 'xml_deadlock_report'
ORDER BY DeadlockTimeUtc DESC;
GO
