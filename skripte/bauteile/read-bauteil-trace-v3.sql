-- Liest die Statements der Session HottgenrothTrace (v3) aus dem Ring-Buffer.
-- Zeigt nur schreibende Statements, neueste zuerst.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

WITH E AS (
    SELECT
        ed.value('(@timestamp)[1]', 'datetime2') AS ts,
        ed.value('(@name)[1]', 'nvarchar(50)')   AS event_type,
        ed.value('(action[@name="database_name"]/value)[1]', 'nvarchar(128)') AS db_name,
        COALESCE(
            ed.value('(data[@name="batch_text"]/value)[1]', 'nvarchar(max)'),
            ed.value('(data[@name="statement"]/value)[1]', 'nvarchar(max)'),
            ed.value('(action[@name="sql_text"]/value)[1]', 'nvarchar(max)')
        ) AS txt
    FROM (
        SELECT CAST(target_data AS xml) AS tx
        FROM sys.dm_xe_session_targets st
        JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
        WHERE s.name = 'HottgenrothTrace' AND st.target_name = 'ring_buffer'
    ) r
    CROSS APPLY tx.nodes('RingBufferTarget/event') n(ed)
)
SELECT ts, db_name, LEFT(txt, 3000) AS statement_text
FROM E
WHERE txt LIKE '%INSERT%' OR txt LIKE '%UPDATE%' OR txt LIKE '%DELETE%'
ORDER BY ts;
GO
