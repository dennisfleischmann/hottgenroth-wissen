# Export-Waermebruecken.ps1 -- die 408 Details aus DIN 4108 Beiblatt 2 (2019-06)
# samt beider Zeichnungen als JSON.
#
# Je Detail haengen drei Bilder am Bauteil (TcMediaReference.UId = Dimension.UId):
#   Rolle  2   300x300  Vorschau der Konstruktionszeichnung
#   Rolle  9   900x900  Konstruktionszeichnung mit Bemassung und Schichtnummern
#   Rolle 36   900x900  Temperaturfeld aus der Waermebrueckenberechnung
# Uebernommen werden 9 und 36; die Vorschau waere nur eine dritte Fassung
# derselben Zeichnung.
#
# Verkleinert wird mit NearestNeighbor und als GIF gespeichert: Strichzeichnungen
# haben wenige Farben, und jede Glaettung verdoppelt die Dateigroesse, weil sie
# Zwischentoene erzeugt. Gemessen an einem Detail: 450px bikubisch als PNG 32 kB,
# nearest-neighbour als GIF 9 kB -- bei gleicher Lesbarkeit.
#
# Nur lesend, in einer zurueckgerollten Transaktion.

[CmdletBinding()]
param(
    [string]$Instanz = "(localdb)\HSETU",
    [Parameter(Mandatory = $true)][string]$Ziel,
    [int]$BreiteZeichnung = 450,
    [int]$BreiteFeld = 360
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
Add-Type -AssemblyName System.Drawing
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

function Verkleinern([byte[]]$roh, [int]$px) {
    if ($null -eq $roh) { return $null }
    $ein = New-Object System.IO.MemoryStream(, $roh)
    $bild = [System.Drawing.Image]::FromStream($ein)
    $neu = New-Object System.Drawing.Bitmap($px, $px)
    $g = [System.Drawing.Graphics]::FromImage($neu)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($bild, 0, 0, $px, $px)
    $aus = New-Object System.IO.MemoryStream
    $neu.Save($aus, [System.Drawing.Imaging.ImageFormat]::Gif)
    $bytes = $aus.ToArray()
    $aus.Dispose(); $g.Dispose(); $neu.Dispose(); $bild.Dispose(); $ein.Dispose()
    return $bytes
}

$abfrage = @"
WITH platz AS (
    SELECT cs.BasisUId, MIN(COALESCE(k.LongDesc, N'')) AS Katalog
    FROM TcCatalogContents cs
    JOIN TcCatalogContent cc ON cc.UId = cs.CatalogContentUId
    LEFT JOIN TcCatalog k ON k.UId = cc.CatalogUId
    GROUP BY cs.BasisUId
),
det AS (
    SELECT d.UId, b.ShortDesc AS Nr, b.LongDesc AS Gruppe,
           b.ConstructionInfo AS Konstruktion,
           NULLIF(d.PsiValue, -987654321.99) AS Psi
    FROM TcBuildingElementDimension d
    JOIN TcBasis b ON b.UId = d.BasisUId
    JOIN platz pl ON pl.BasisUId = d.BasisUId
    WHERE pl.Katalog = N'DIN 4108 Bbl 2: 2019-06'
)
SELECT det.Nr, det.Gruppe, det.Konstruktion, det.Psi,
       (SELECT TOP 1 m.Media FROM TcMediaReference r
        JOIN TcMedia m ON m.UId = r.MediaUId
        WHERE r.UId = det.UId AND m.CatalogMediaType = 9 AND m.Media IS NOT NULL) AS Zeichnung,
       (SELECT TOP 1 m.Media FROM TcMediaReference r
        JOIN TcMedia m ON m.UId = r.MediaUId
        WHERE r.UId = det.UId AND m.CatalogMediaType = 36 AND m.Media IS NOT NULL) AS Feld
FROM det
ORDER BY det.Gruppe, det.Psi, det.Nr
"@

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=HsetuAppTimData;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
$tx = $con.BeginTransaction()
try {
    $c = $con.CreateCommand(); $c.Transaction = $tx; $c.CommandTimeout = 600
    $c.CommandText = $abfrage
    $tab = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)

    $liste = New-Object System.Collections.ArrayList
    $bytesZ = 0; $bytesF = 0; $ohneBild = 0
    foreach ($r in $tab.Rows) {
        $z = if ($r['Zeichnung'] -is [System.DBNull]) { $null } else { Verkleinern ([byte[]]$r['Zeichnung']) $BreiteZeichnung }
        $f = if ($r['Feld'] -is [System.DBNull]) { $null } else { Verkleinern ([byte[]]$r['Feld']) $BreiteFeld }
        if ($null -eq $z) { $ohneBild++ }
        if ($z) { $bytesZ += $z.Length }
        if ($f) { $bytesF += $f.Length }

        [void]$liste.Add([ordered]@{
            nr    = [string]$r['Nr']
            grp   = [string]$r['Gruppe']
            kon   = [string]$r['Konstruktion']
            psi   = if ($r['Psi'] -is [System.DBNull]) { $null } else { [math]::Round([double]$r['Psi'], 3) }
            z     = if ($z) { [Convert]::ToBase64String($z) } else { $null }
            f     = if ($f) { [Convert]::ToBase64String($f) } else { $null }
        })
    }

    $json = $liste | ConvertTo-Json -Depth 4 -Compress
    [System.IO.File]::WriteAllText($Ziel, $json, (New-Object System.Text.UTF8Encoding $false))

    Write-Output ("{0} Details, {1} ohne Zeichnung" -f $tab.Rows.Count, $ohneBild)
    Write-Output ("Zeichnungen {0:N1} MB, Temperaturfelder {1:N1} MB, JSON {2:N1} MB" -f
        ($bytesZ/1MB), ($bytesF/1MB), ((Get-Item $Ziel).Length/1MB))
}
finally { try { $tx.Rollback() } catch {}; $con.Close() }
