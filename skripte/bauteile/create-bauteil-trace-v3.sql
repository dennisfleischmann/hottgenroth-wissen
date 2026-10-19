-- Trace-Session v3 fuer das Mitschneiden inhomogener Bauteile (LayerSection).
-- Gegenueber v2: sql_batch_completed ist mit drin - darueber schreibt die Software
-- tatsaechlich (im alten Mitschnitt 451 Batches gegenueber 32 RPCs).
-- Puffer auf 32 MB, damit nichts aus dem Ring faellt.

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'HottgenrothTrace')
BEGIN
    ALTER EVENT SESSION [HottgenrothTrace] ON SERVER STATE = STOP;
    DROP EVENT SESSION [HottgenrothTrace] ON SERVER;
END
GO

CREATE EVENT SESSION [HottgenrothTrace] ON SERVER
ADD EVENT sqlserver.sql_batch_completed(
    ACTION(sqlserver.database_name, sqlserver.client_app_name, sqlserver.sql_text)
    WHERE (
        sqlserver.client_app_name <> N'SQLCMD'
        AND (
            sqlserver.sql_text LIKE N'%INSERT%'
            OR sqlserver.sql_text LIKE N'%UPDATE%'
            OR sqlserver.sql_text LIKE N'%DELETE%'
            OR sqlserver.sql_text LIKE N'%MERGE%'
        )
    )
),
ADD EVENT sqlserver.sql_statement_completed(
    SET collect_statement = 1
    ACTION(sqlserver.database_name, sqlserver.client_app_name, sqlserver.sql_text)
    WHERE (
        sqlserver.client_app_name <> N'SQLCMD'
        AND (
            sqlserver.sql_text LIKE N'%INSERT%'
            OR sqlserver.sql_text LIKE N'%UPDATE%'
            OR sqlserver.sql_text LIKE N'%DELETE%'
            OR sqlserver.sql_text LIKE N'%MERGE%'
        )
    )
),
ADD EVENT sqlserver.rpc_completed(
    ACTION(sqlserver.database_name, sqlserver.client_app_name, sqlserver.sql_text)
    WHERE (sqlserver.client_app_name <> N'SQLCMD')
)
ADD TARGET package0.ring_buffer(SET max_memory = 32768)
WITH (MAX_DISPATCH_LATENCY = 1 SECONDS, TRACK_CAUSALITY = ON, MAX_MEMORY = 32768 KB);
GO

ALTER EVENT SESSION [HottgenrothTrace] ON SERVER STATE = START;
GO

SELECT name, CASE WHEN EXISTS (SELECT 1 FROM sys.dm_xe_sessions s WHERE s.name = e.name)
                  THEN 'LAEUFT' ELSE 'GESTOPPT' END AS Status
FROM sys.server_event_sessions e WHERE e.name = 'HottgenrothTrace';
GO
