SET QUOTED_IDENTIFIER ON;
GO
SELECT TOP 50
    event_data.value('(@timestamp)[1]', 'datetime2') AS ts,
    event_data.value('(@name)[1]', 'nvarchar(50)') AS event_type,
    event_data.value('(action[@name="database_name"]/value)[1]', 'nvarchar(128)') AS db_name,
    event_data.value('(action[@name="client_app_name"]/value)[1]', 'nvarchar(128)') AS app,
    event_data.value('(data[@name="duration"]/value)[1]', 'bigint') AS duration_us,
    event_data.value('(data[@name="row_count"]/value)[1]', 'bigint') AS rows_affected,
    event_data.value('(data[@name="logical_reads"]/value)[1]', 'bigint') AS logical_reads,
    LEFT(COALESCE(
        event_data.value('(data[@name="statement"]/value)[1]', 'nvarchar(max)'),
        event_data.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)')
    ), 500) AS sql_text
FROM (
    SELECT CAST(target_data AS xml) AS target_xml
    FROM sys.dm_xe_session_targets st
    JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
    WHERE s.name = 'HottgenrothTrace'
      AND st.target_name = 'ring_buffer'
) AS raw
CROSS APPLY target_xml.nodes('RingBufferTarget/event') AS n(event_data)
WHERE event_data.value('(action[@name="client_app_name"]/value)[1]', 'nvarchar(128)') != 'SQLCMD'
ORDER BY ts DESC;
