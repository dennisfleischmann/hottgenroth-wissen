# Read-SQL-Trace: Liest Hottgenroth SQL Queries aus Extended Events
# Usage: .\read-sql-trace.ps1           → letzte Queries anzeigen
#        .\read-sql-trace.ps1 -Loop     → kontinuierlich neue Queries zeigen
#        .\read-sql-trace.ps1 -Export   → alles in CSV exportieren

param(
    [switch]$Loop,
    [switch]$Export,
    [int]$IntervalSec = 3
)

$instance = "(localdb)\HSETU"

$query = @"
SELECT
    event_data.value('(event/@timestamp)[1]', 'datetime2') AS ts,
    event_data.value('(event/action[@name="database_name"]/value)[1]', 'nvarchar(128)') AS db_name,
    event_data.value('(event/@name)[1]', 'nvarchar(50)') AS event_type,
    event_data.value('(event/data[@name="duration"]/value)[1]', 'bigint') AS duration_us,
    event_data.value('(event/data[@name="row_count"]/value)[1]', 'bigint') AS row_count,
    event_data.value('(event/data[@name="cpu_time"]/value)[1]', 'bigint') AS cpu_us,
    event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text
FROM (
    SELECT CAST(target_data AS xml) AS target_xml
    FROM sys.dm_xe_session_targets st
    JOIN sys.dm_xe_sessions s ON s.address = st.event_session_address
    WHERE s.name = 'HottgenrothTrace'
      AND st.target_name = 'ring_buffer'
) AS raw
CROSS APPLY target_xml.nodes('RingBufferTarget/event') AS n(event_data)
ORDER BY ts DESC
"@

function Read-Trace {
    $result = sqlcmd -S $instance -Q $query -W -s "|" -h -1 2>$null
    return $result | Where-Object { $_ -and $_.Trim() -ne "" -and $_ -notmatch '^\s*$' -and $_ -notmatch 'Zeilen betroffen' }
}

if ($Export) {
    $outPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "hottgenroth_sql_trace.csv"
    $csvQuery = $query -replace 'ORDER BY ts DESC', 'ORDER BY ts ASC'
    sqlcmd -S $instance -Q $csvQuery -W -s "," -o $outPath
    Write-Host "Exported to: $outPath"
    exit
}

$seen = @{}
Write-Host "=== Hottgenroth SQL Trace ===" -ForegroundColor Cyan
Write-Host "Warte auf SQL Queries... (Ctrl+C zum Beenden)" -ForegroundColor Gray
Write-Host ""

if ($Loop) {
    while ($true) {
        $lines = Read-Trace
        foreach ($line in $lines) {
            $hash = $line.GetHashCode()
            if (-not $seen.ContainsKey($hash)) {
                $seen[$hash] = $true
                $parts = $line -split '\|'
                if ($parts.Count -ge 7) {
                    $ts = $parts[0].Trim()
                    $db = $parts[1].Trim()
                    $evt = $parts[2].Trim()
                    $dur = $parts[3].Trim()
                    $rows = $parts[4].Trim()
                    $sql = $parts[6].Trim()

                    if ($sql -and $sql -ne "NULL" -and $sql.Length -gt 5) {
                        Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
                        Write-Host "$db " -NoNewline -ForegroundColor Yellow
                        Write-Host "(${dur}us, ${rows} rows) " -NoNewline -ForegroundColor DarkCyan
                        Write-Host $sql -ForegroundColor White
                    }
                }
            }
        }
        Start-Sleep -Seconds $IntervalSec
    }
} else {
    $lines = Read-Trace
    Write-Host "Gefundene Queries: $($lines.Count)" -ForegroundColor Green
    Write-Host ""
    foreach ($line in $lines | Select-Object -First 50) {
        $parts = $line -split '\|'
        if ($parts.Count -ge 7) {
            $ts = $parts[0].Trim()
            $db = $parts[1].Trim()
            $dur = $parts[3].Trim()
            $rows = $parts[4].Trim()
            $sql = $parts[6].Trim()

            if ($sql -and $sql -ne "NULL" -and $sql.Length -gt 5) {
                Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
                Write-Host "$db " -NoNewline -ForegroundColor Yellow
                Write-Host "(${dur}us, ${rows} rows)" -ForegroundColor DarkCyan
                Write-Host "  $sql" -ForegroundColor White
                Write-Host ""
            }
        }
    }
}
