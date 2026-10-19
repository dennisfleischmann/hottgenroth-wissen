-- Trace-Session v2: File-Target statt Ring Buffer (schneller lesbar)
-- Filtert nur INSERT/UPDATE/DELETE und Hottgenroth-App Events

CREATE EVENT SESSION [HottgenrothTrace] ON SERVER
ADD EVENT sqlserver.sql_statement_completed(
    SET collect_statement = 1
    ACTION(
        sqlserver.database_name,
        sqlserver.client_app_name,
        sqlserver.sql_text
    )
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
    ACTION(
        sqlserver.database_name,
        sqlserver.client_app_name,
        sqlserver.sql_text
    )
    WHERE (
        sqlserver.client_app_name <> N'SQLCMD'
    )
)
ADD TARGET package0.ring_buffer(SET max_memory=2048)
WITH (MAX_DISPATCH_LATENCY=1 SECONDS, TRACK_CAUSALITY=ON);
GO

ALTER EVENT SESSION [HottgenrothTrace] ON SERVER STATE = START;
GO

PRINT 'Trace v2 gestartet - nur INSERT/UPDATE/DELETE/MERGE werden erfasst';
