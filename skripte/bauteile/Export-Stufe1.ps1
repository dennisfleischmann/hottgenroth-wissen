# Export-Stufe1.ps1 -- genau die 143 Bauteile, die nach dem Schnitt vom
# 11.09.2026 in die FS-Bauteilliste gehen, plus ihre Schichten.
#
# Nur lesend, alles in einer zurueckgerollten Transaktion.

[CmdletBinding()]
param(
    [string]$Instanz = "(localdb)\HSETU",
    [Parameter(Mandatory = $true)][string]$Ziel
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

if (-not (Test-Path $Ziel)) { New-Item -ItemType Directory -Path $Ziel | Out-Null }

function Feld($w) {
    if ($null -eq $w -or $w -is [System.DBNull]) { return '' }
    if ($w -is [double] -or $w -is [single]) {
        if ([double]$w -le -1000000) { return '' }
        return ([double]$w).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    return ([string]$w)
}

function Schreibe($Abfrage, $Datei) {
    $con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=HsetuAppTimData;Integrated Security=true;TrustServerCertificate=true"
    $con.Open()
    $tx = $null
    try {
        $tx = $con.BeginTransaction()
        $c = $con.CreateCommand(); $c.Transaction = $tx; $c.CommandTimeout = 300; $c.CommandText = $Abfrage
        $tab = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)

        $sw = New-Object System.IO.StreamWriter((Join-Path $Ziel $Datei), $false, (New-Object System.Text.UTF8Encoding $false))
        try {
            $spalten = @($tab.Columns | ForEach-Object { $_.ColumnName })
            $sw.WriteLine((($spalten | ForEach-Object { '"' + ($_ -replace '"','""') + '"' }) -join ';'))
            foreach ($r in $tab.Rows) {
                $sw.WriteLine((($spalten | ForEach-Object { '"' + ((Feld $r[$_]) -replace '"','""') + '"' }) -join ';'))
            }
        } finally { $sw.Close() }
        Write-Output ("{0,-24} {1,5} Zeilen" -f $Datei, $tab.Rows.Count)
    } finally {
        if ($tx) { try { $tx.Rollback() } catch {} }
        $con.Close()
    }
}

# Der Schnitt als eine wiederverwendbare Definition -- beide Abfragen benutzen sie.
$auswahl = @"
WITH pfad AS (
    SELECT cc.UId, cc.CatalogUId,
           LTRIM(RTRIM(COALESCE(p.LongDesc + N' > ', N'') + COALESCE(cc.LongDesc, N''))) AS Ordner
    FROM TcCatalogContent cc LEFT JOIN TcCatalogContent p ON p.UId = cc.ReferenceUId
),
platz AS (
    SELECT cs.BasisUId, MIN(pf.Ordner) AS Ordner, MIN(COALESCE(k.LongDesc, N'')) AS Katalog
    FROM TcCatalogContents cs
    JOIN pfad pf ON pf.UId = cs.CatalogContentUId
    LEFT JOIN TcCatalog k ON k.UId = pf.CatalogUId
    GROUP BY cs.BasisUId
),
gewaehlt AS (
    SELECT d.UId, d.BasisUId, b.GroupType, b.UsageType, b.LongDesc AS Bez,
           d.UValue, d.RValue, d.Thickness, pl.Ordner, pl.Katalog, d.InfoDesc
    FROM TcBuildingElementDimension d
    JOIN TcBasis b ON b.UId = d.BasisUId
    JOIN platz pl ON pl.BasisUId = b.UId
    WHERE ((b.GroupType=1 AND b.UsageType=2) OR (b.GroupType=5 AND b.UsageType=2)
        OR (b.GroupType=4 AND b.UsageType IN (4,7,8)))
      AND pl.Katalog = N'Typologien'
      AND pl.Ordner NOT LIKE N'%sterreich%' AND pl.Ordner NOT LIKE N'%Burgenland%'
      AND pl.Ordner NOT LIKE N'%rnten%'     AND pl.Ordner NOT LIKE N'%Salzburg%'
      AND pl.Ordner NOT LIKE N'%Steiermark%' AND pl.Ordner NOT LIKE N'%Tirol%'
      AND pl.Ordner NOT LIKE N'%Vorarlberg%' AND pl.Ordner NOT LIKE N'%Wien%'
      AND EXISTS (SELECT 1 FROM TcBuildingElementDimensionLayer l WHERE l.DimensionUId = d.UId)
)
"@

Schreibe @"
$auswahl
SELECT CONVERT(nvarchar(36), g.UId) AS Ref,
       g.GroupType, g.UsageType, g.Bez AS Bezeichnung,
       g.UValue AS UWert, g.RValue AS RWert, g.Thickness AS Dicke,
       g.Ordner, g.InfoDesc AS Beschreibung,
       (SELECT COUNT(DISTINCT s.UId) FROM TcBuildingElementDimensionLayerSection s
        WHERE s.DimensionUId = g.UId) AS Gefache
FROM gewaehlt g
ORDER BY g.GroupType, g.UsageType, g.Bez, g.Ordner
"@ 'stufe1-bauteile.csv'

Schreibe @"
$auswahl
SELECT CONVERT(nvarchar(36), l.DimensionUId) AS Ref,
       COALESCE(sek.SectionNum, 1) AS Sektion,
       sek.SectionShareValve AS Anteil,
       l.SortNum AS Nr, l.LongDesc AS Schicht,
       l.Thickness AS Dicke, l.ThermalConductivity AS Lambda, l.Density AS Rohdichte
FROM TcBuildingElementDimensionLayer l
JOIN gewaehlt g ON g.UId = l.DimensionUId
LEFT JOIN TcBuildingElementDimensionLayerSection sek ON sek.UId = l.LayerSectionUId
ORDER BY l.DimensionUId, COALESCE(sek.SectionNum, 1), l.SortNum
"@ 'stufe1-schichten.csv'
