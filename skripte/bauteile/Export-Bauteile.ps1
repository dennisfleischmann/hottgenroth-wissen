# Export-Bauteile.ps1 -- liest den Bauteilbestand der Hottgenroth-/ETU-Installation
# und legt ihn als CSV ab. Nur lesend: jede Abfrage laeuft in einer Transaktion,
# die am Ende zurueckgerollt wird -- wie in Query-Datenbank.ps1.
#
# Quellen
#   HsetuAppTimData  ausgelieferter Bauteilkatalog der Software
#   HsetuUsrData     "Meine Bauteile", projektuebergreifend
#   HsetuPrjData     Bauteile in den Projekten

[CmdletBinding()]
param(
    [string]$Instanz = "(localdb)\HSETU",
    [Parameter(Mandatory = $true)][string]$Ziel
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

# Zahlen muessen mit Punkt herauskommen, sonst zerbricht das Einlesen.
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

if (-not (Test-Path $Ziel)) { New-Item -ItemType Directory -Path $Ziel | Out-Null }

# Die Software traegt -987654321.99 ein, wo nichts angegeben ist.
$Leerwert = -987654321.99

function Feld($w) {
    if ($null -eq $w -or $w -is [System.DBNull]) { return '' }
    if ($w -is [double] -or $w -is [single]) {
        if ([double]$w -le -1000000) { return '' }
        return ([double]$w).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($w -is [datetime]) { return ([datetime]$w).ToString('yyyy-MM-dd HH:mm:ss') }
    $s = [string]$w
    return $s
}

function Schreibe($Datenbank, $Abfrage, $Datei) {
    $con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
    $con.Open()
    $tx = $null
    try {
        $tx = $con.BeginTransaction()
        $c = $con.CreateCommand()
        $c.Transaction = $tx
        $c.CommandTimeout = 600
        $c.CommandText = $Abfrage

        $tab = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)

        $pfad = Join-Path $Ziel $Datei
        $sw = New-Object System.IO.StreamWriter($pfad, $false, (New-Object System.Text.UTF8Encoding $true))
        try {
            $spalten = @($tab.Columns | ForEach-Object { $_.ColumnName })
            $sw.WriteLine((($spalten | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ';'))
            foreach ($r in $tab.Rows) {
                $werte = foreach ($sp in $spalten) { '"' + ((Feld $r[$sp]) -replace '"', '""') + '"' }
                $sw.WriteLine(($werte -join ';'))
            }
        } finally { $sw.Close() }

        Write-Output ("{0,-28} {1,7} Zeilen" -f $Datei, $tab.Rows.Count)
    }
    finally {
        if ($tx) { try { $tx.Rollback() } catch {} }
        $con.Close()
    }
}

# --------------------------------------------------------------------------
# Der Ordnerbaum ist zwei Ebenen tief (ContentLevel 2 und 3). Ein Bauteil kann
# an mehreren Stellen im Baum haengen -- deshalb ein Hauptplatz plus die Liste
# aller Plaetze, statt das Bauteil mehrfach aufzufuehren.
# --------------------------------------------------------------------------
$baumCte = @"
WITH pfad AS (
    SELECT cc.UId,
           cc.CatalogUId,
           cc.SortNum,
           LTRIM(RTRIM(COALESCE(p.LongDesc + N' > ', N'') + COALESCE(cc.LongDesc, N''))) AS Ordner
    FROM TcCatalogContent cc
    LEFT JOIN TcCatalogContent p ON p.UId = cc.ReferenceUId
),
platz AS (
    SELECT cs.BasisUId,
           COALESCE(k.LongDesc, N'') AS Katalog,
           pf.Ordner,
           ROW_NUMBER() OVER (PARTITION BY cs.BasisUId ORDER BY pf.SortNum) AS rn,
           COUNT(*)     OVER (PARTITION BY cs.BasisUId)                     AS anzahl
    FROM TcCatalogContents cs
    JOIN pfad pf ON pf.UId = cs.CatalogContentUId
    LEFT JOIN TcCatalog k ON k.UId = pf.CatalogUId
),
alle AS (
    SELECT BasisUId, STRING_AGG(CONVERT(nvarchar(max), Katalog + N': ' + Ordner), N' | ') WITHIN GROUP (ORDER BY rn) AS AlleOrdner
    FROM platz GROUP BY BasisUId
),
schicht AS (
    SELECT DimensionUId,
           COUNT(*) AS SchichtZeilen,
           COUNT(DISTINCT CASE WHEN LayerSectionUId <> '00000000-0000-0000-0000-000000000000'
                               THEN LayerSectionUId END) AS Sektionen
    FROM TcBuildingElementDimensionLayer GROUP BY DimensionUId
)
"@

$bauteilSpalten = @"
    CONVERT(nvarchar(36), d.UId)        AS BauteilId,
    b.GroupType                         AS ArtNr,
    COALESCE(b.LongDesc, d.LongDesc)    AS Bezeichnung,
    COALESCE(b.ShortDesc, d.ShortDesc)  AS Kurzzeichen,
    d.InfoDesc                          AS Beschreibung,
    d.UValue                            AS UWert,
    d.RValue                            AS RWert,
    d.Thickness                         AS Dicke,
    d.GValue                            AS GWert,
    d.FrameUValue                       AS UWertRahmen,
    d.FractionOfFrame                   AS Rahmenanteil,
    COALESCE(s.SchichtZeilen, 0)        AS SchichtZeilen,
    COALESCE(s.Sektionen, 0)            AS Sektionen
"@

# 1 -- ausgelieferter Katalog
Schreibe 'HsetuAppTimData' @"
$baumCte
SELECT
    COALESCE(pl.Katalog, N'(nicht im Katalogbaum)') AS Katalog,
    COALESCE(pl.Ordner, N'')                        AS Ordner,
    COALESCE(pl.anzahl, 0)                          AS Einordnungen,
    COALESCE(al.AlleOrdner, N'')                    AS AlleOrdner,
$bauteilSpalten
FROM TcBuildingElementDimension d
LEFT JOIN TcBasis b       ON b.UId = d.BasisUId
LEFT JOIN schicht s       ON s.DimensionUId = d.UId
LEFT JOIN platz pl        ON pl.BasisUId = b.UId AND pl.rn = 1
LEFT JOIN alle  al        ON al.BasisUId = b.UId
ORDER BY Katalog, Ordner, b.GroupType, Bezeichnung
"@ 'katalog-bauteile.csv'

# 2 -- Schichten dazu
Schreibe 'HsetuAppTimData' @"
SELECT
    CONVERT(nvarchar(36), l.DimensionUId) AS BauteilId,
    COALESCE(sek.SectionNum, 1)           AS Sektion,
    COALESCE(sek.LongDesc, N'')           AS SektionName,
    sek.SectionShareValve                 AS SektionAnteil,
    l.SortNum                             AS Nr,
    l.LongDesc                            AS Schicht,
    l.LayerType                           AS SchichtartNr,
    l.MaterialGroupType                   AS StoffgruppeNr,
    l.Thickness                           AS Dicke,
    l.ThermalConductivity                 AS Lambda,
    l.RValue                              AS RWert,
    l.Density                             AS Rohdichte,
    l.HeatCapacity                        AS Waermekapazitaet,
    l.DiffusionResistanceCoefficient      AS my
FROM TcBuildingElementDimensionLayer l
LEFT JOIN TcBuildingElementDimensionLayerSection sek ON sek.UId = l.LayerSectionUId
ORDER BY l.DimensionUId, COALESCE(sek.SectionNum, 1), l.SortNum
"@ 'katalog-schichten.csv'

# 3 -- "Meine Bauteile"
Schreibe 'HsetuUsrData' @"
$baumCte
SELECT
    COALESCE(pl.Katalog, N'(nicht im Katalogbaum)') AS Katalog,
    COALESCE(pl.Ordner, N'')                        AS Ordner,
    COALESCE(pl.anzahl, 0)                          AS Einordnungen,
    COALESCE(al.AlleOrdner, N'')                    AS AlleOrdner,
$bauteilSpalten,
    d.StampCreate                       AS Angelegt,
    d.StampEdit                         AS Geaendert
FROM TcBuildingElementDimension d
LEFT JOIN TcBasis b       ON b.UId = d.BasisUId
LEFT JOIN schicht s       ON s.DimensionUId = d.UId
LEFT JOIN platz pl        ON pl.BasisUId = b.UId AND pl.rn = 1
LEFT JOIN alle  al        ON al.BasisUId = b.UId
ORDER BY b.GroupType, Bezeichnung
"@ 'meine-bauteile.csv'

Schreibe 'HsetuUsrData' @"
SELECT
    CONVERT(nvarchar(36), l.DimensionUId) AS BauteilId,
    COALESCE(sek.SectionNum, 1)           AS Sektion,
    COALESCE(sek.LongDesc, N'')           AS SektionName,
    sek.SectionShareValve                 AS SektionAnteil,
    l.SortNum                             AS Nr,
    l.LongDesc                            AS Schicht,
    l.LayerType                           AS SchichtartNr,
    l.MaterialGroupType                   AS StoffgruppeNr,
    l.Thickness                           AS Dicke,
    l.ThermalConductivity                 AS Lambda,
    l.RValue                              AS RWert,
    l.Density                             AS Rohdichte,
    l.HeatCapacity                        AS Waermekapazitaet,
    l.DiffusionResistanceCoefficient      AS my
FROM TcBuildingElementDimensionLayer l
LEFT JOIN TcBuildingElementDimensionLayerSection sek ON sek.UId = l.LayerSectionUId
ORDER BY l.DimensionUId, COALESCE(sek.SectionNum, 1), l.SortNum
"@ 'meine-schichten.csv'

# 4 -- Bauteile in den Projekten
Schreibe 'HsetuPrjData' @"
WITH schicht AS (
    SELECT DimensionUId,
           COUNT(*) AS SchichtZeilen,
           COUNT(DISTINCT CASE WHEN LayerSectionUId <> '00000000-0000-0000-0000-000000000000'
                               THEN LayerSectionUId END) AS Sektionen
    FROM TcBuildingElementDimensionLayer GROUP BY DimensionUId
)
SELECT
    COALESCE(pr.LongDesc, N'(ohne Projekt)') AS Projekt,
$bauteilSpalten,
    d.StampCreate                       AS Angelegt,
    d.StampEdit                         AS Geaendert
FROM TcBuildingElementDimension d
LEFT JOIN TcBasis b   ON b.UId = d.BasisUId
LEFT JOIN schicht s   ON s.DimensionUId = d.UId
LEFT JOIN PrProject pr ON pr.UUID = d.ProjectUId
ORDER BY Projekt, b.GroupType, Bezeichnung
"@ 'projekt-bauteile.csv'

Write-Output ""
Write-Output "Fertig. Dateien in: $Ziel"
