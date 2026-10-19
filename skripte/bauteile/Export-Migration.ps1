# Export-Migration.ps1 -- alles, was migriert wird: die deutsche
# Bestandstypologie in voller Breite (Vergleichsband) und daraus der Ausschnitt,
# der als Aufbau in die Bauteilliste geht.
#
# Nur lesend, jede Abfrage in einer zurueckgerollten Transaktion.

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
    $con.Open(); $tx = $null
    try {
        $tx = $con.BeginTransaction()
        $c = $con.CreateCommand(); $c.Transaction = $tx; $c.CommandTimeout = 300; $c.CommandText = $Abfrage
        $tab = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)
        $sw = New-Object System.IO.StreamWriter((Join-Path $Ziel $Datei), $false, (New-Object System.Text.UTF8Encoding $false))
        try {
            $sp = @($tab.Columns | ForEach-Object { $_.ColumnName })
            $sw.WriteLine((($sp | ForEach-Object { '"' + ($_ -replace '"','""') + '"' }) -join ';'))
            foreach ($r in $tab.Rows) { $sw.WriteLine((($sp | ForEach-Object { '"' + ((Feld $r[$_]) -replace '"','""') + '"' }) -join ';')) }
        } finally { $sw.Close() }
        Write-Output ("{0,-26} {1,5} Zeilen" -f $Datei, $tab.Rows.Count)
    } finally { if ($tx) { try { $tx.Rollback() } catch {} }; $con.Close() }
}

# Deutsche Bestandstypologie: beide Typologie-Teilkataloge, ohne die
# oesterreichischen Ordner. Bewusst OHNE Einschraenkung auf die sechs
# FS-Bauteilarten -- das Vergleichsband soll gerade die Lagen beantworten,
# die die Bauteilliste nicht halten kann (Fenster, Innenwand, Kellerwand).
Schreibe @"
WITH pfad AS (
    SELECT cc.UId, cc.CatalogUId, COALESCE(p.LongDesc, N'') AS Eltern, cc.LongDesc AS Kind
    FROM TcCatalogContent cc LEFT JOIN TcCatalogContent p ON p.UId = cc.ReferenceUId
),
platz AS (
    SELECT cs.BasisUId, MIN(pf.Eltern) AS Eltern, MIN(pf.Kind) AS Kind,
           MIN(COALESCE(k.LongDesc, N'')) AS Katalog
    FROM TcCatalogContents cs
    JOIN pfad pf ON pf.UId = cs.CatalogContentUId
    LEFT JOIN TcCatalog k ON k.UId = pf.CatalogUId
    GROUP BY cs.BasisUId
)
SELECT CONVERT(nvarchar(36), d.UId) AS Ref,
       b.GroupType, b.UsageType, b.LongDesc AS Bezeichnung,
       d.UValue AS UWert, d.Thickness AS Dicke,
       pl.Eltern, pl.Kind, pl.Katalog,
       CASE WHEN EXISTS (SELECT 1 FROM TcBuildingElementDimensionLayer l WHERE l.DimensionUId = d.UId)
            THEN 1 ELSE 0 END AS HatAufbau,
       (SELECT COUNT(DISTINCT s.UId) FROM TcBuildingElementDimensionLayerSection s
        WHERE s.DimensionUId = d.UId) AS Gefache,
       d.InfoDesc AS Beschreibung
FROM TcBuildingElementDimension d
JOIN TcBasis b ON b.UId = d.BasisUId
JOIN platz pl ON pl.BasisUId = b.UId
WHERE pl.Katalog IN (N'Typologien', N'BauteileTypologie')
  AND pl.Kind NOT LIKE N'%sterreich%' AND pl.Kind NOT LIKE N'%Burgenland%'
  AND pl.Kind NOT LIKE N'%rnten%'      AND pl.Kind NOT LIKE N'%Salzburg%'
  AND pl.Kind NOT LIKE N'%Steiermark%' AND pl.Kind NOT LIKE N'%Tirol%'
  AND pl.Kind NOT LIKE N'%Vorarlberg%' AND pl.Kind NOT LIKE N'%Wien%'
ORDER BY b.GroupType, b.UsageType, pl.Eltern, pl.Kind
"@ 'migration-band.csv'

# ---------------------------------------------------------------------------
# Zielaufbauten: Neubau-, Hersteller- und Passivhauskataloge, nur die mit
# Schichten und nur die Lagen, fuer die es in der FS-Liste eine Bauteilart gibt.
# Sie gehen in DIESELBE Tabelle wie der Bestand, unterschieden durch rolle='ziel',
# und sind in der Suche nur sichtbar, wenn man sie ausdruecklich dazuschaltet.
# ---------------------------------------------------------------------------

$zielAuswahl = @"
WITH platz AS (
    SELECT cs.BasisUId, MIN(COALESCE(k.LongDesc, N'')) AS Katalog, MIN(cc.LongDesc) AS Ordner
    FROM TcCatalogContents cs
    JOIN TcCatalogContent cc ON cc.UId = cs.CatalogContentUId
    LEFT JOIN TcCatalog k ON k.UId = cc.CatalogUId
    GROUP BY cs.BasisUId
),
gewaehlt AS (
    SELECT d.UId, b.GroupType, b.UsageType, b.LongDesc AS Bez, d.UValue, d.Thickness,
           pl.Katalog, pl.Ordner, d.InfoDesc
    FROM TcBuildingElementDimension d
    JOIN TcBasis b ON b.UId = d.BasisUId
    JOIN platz pl ON pl.BasisUId = b.UId
    WHERE pl.Katalog IN (N'BauteileNeubau', N'BauteileHersteller', N'BauteilePassivhaus')
      AND ((b.GroupType=1 AND b.UsageType=2) OR (b.GroupType=5 AND b.UsageType=2)
        OR (b.GroupType=4 AND b.UsageType IN (4,7,8)))
      AND EXISTS (SELECT 1 FROM TcBuildingElementDimensionLayer l WHERE l.DimensionUId = d.UId)
)
"@

Schreibe @"
$zielAuswahl
SELECT CONVERT(nvarchar(36), g.UId) AS Ref, g.GroupType, g.UsageType, g.Bez AS Bezeichnung,
       g.UValue AS UWert, g.Thickness AS Dicke, g.Katalog, g.Ordner, g.InfoDesc AS Beschreibung,
       (SELECT COUNT(DISTINCT s.UId) FROM TcBuildingElementDimensionLayerSection s
        WHERE s.DimensionUId = g.UId) AS Gefache
FROM gewaehlt g
ORDER BY g.GroupType, g.UsageType, g.UValue
"@ 'ziel-bauteile.csv'

Schreibe @"
$zielAuswahl
SELECT CONVERT(nvarchar(36), l.DimensionUId) AS Ref,
       COALESCE(sek.SectionNum, 1) AS Sektion, sek.SectionShareValve AS Anteil,
       l.SortNum AS Nr, l.LongDesc AS Schicht,
       l.Thickness AS Dicke, l.ThermalConductivity AS Lambda
FROM TcBuildingElementDimensionLayer l
JOIN gewaehlt g ON g.UId = l.DimensionUId
LEFT JOIN TcBuildingElementDimensionLayerSection sek ON sek.UId = l.LayerSectionUId
ORDER BY l.DimensionUId, COALESCE(sek.SectionNum, 1), l.SortNum
"@ 'ziel-schichten.csv'
