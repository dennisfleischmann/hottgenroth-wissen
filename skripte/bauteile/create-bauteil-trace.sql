-- Trace-Session neu erstellen (optimiert fuer Bauteil-Writes)
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'HottgenrothTrace')
BEGIN
    ALTER EVENT SESSION [HottgenrothTrace] ON SERVER STATE = STOP;
    DROP EVENT SESSION [HottgenrothTrace] ON SERVER;
END
GO

CREATE EVENT SESSION [HottgenrothTrace] ON SERVER
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(
        sqlserver.database_name,
        sqlserver.client_app_name,
        sqlserver.sql_text
    )
),
ADD EVENT sqlserver.rpc_completed(
    ACTION(
        sqlserver.database_name,
        sqlserver.client_app_name,
        sqlserver.sql_text
    )
),
ADD EVENT sqlserver.sql_batch_completed(
    ACTION(
        sqlserver.database_name,
        sqlserver.client_app_name,
        sqlserver.sql_text
    )
)
ADD TARGET package0.ring_buffer(SET max_memory=8192)
WITH (MAX_DISPATCH_LATENCY=1 SECONDS, TRACK_CAUSALITY=ON);
GO

ALTER EVENT SESSION [HottgenrothTrace] ON SERVER STATE = START;
GO

PRINT 'Trace HottgenrothTrace gestartet - bereit zum Monitoring';
