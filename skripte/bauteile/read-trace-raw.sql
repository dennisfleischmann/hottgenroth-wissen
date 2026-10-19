SET QUOTED_IDENTIFIER ON;
GO
-- Raw ring buffer content (first 4000 chars)
SELECT LEFT(CAST(target_data AS nvarchar(max)), 4000) AS raw_xml
FROM sys.dm_xe_session_targets st
JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
WHERE s.name = 'HottgenrothTrace'
  AND st.target_name = 'ring_buffer';
