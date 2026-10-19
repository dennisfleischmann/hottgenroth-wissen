# Export-Bilder.ps1 -- Bilder aus dem Hottgenroth-Katalog als Dateien herausziehen.
#
# Die Bilder liegen als Blob in TcMedia.Media und haengen ueber TcMediaReference
# am Bauteil (die Referenzzeile traegt dieselbe UId wie die Dimension).
# BMP wird nach PNG gewandelt, damit es sich ueberall ansehen laesst.
#
# Nur lesend, in einer zurueckgerollten Transaktion.

[CmdletBinding()]
param(
    [string]$Instanz = "(localdb)\HSETU",
    [Parameter(Mandatory = $true)][string]$Ziel,
    [Parameter(Mandatory = $true)][string]$Katalog,
    [int]$Anzahl = 6,
    [string]$Muster = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
Add-Type -AssemblyName System.Drawing
if (-not (Test-Path $Ziel)) { New-Item -ItemType Directory -Path $Ziel | Out-Null }

$abfrage = @"
WITH platz AS (
    SELECT cs.BasisUId, MIN(COALESCE(k.LongDesc, N'')) AS Katalog
    FROM TcCatalogContents cs
    JOIN TcCatalogContent cc ON cc.UId = cs.CatalogContentUId
    LEFT JOIN TcCatalog k ON k.UId = cc.CatalogUId
    GROUP BY cs.BasisUId
),
gereiht AS (
    SELECT b.ShortDesc AS Nr, b.LongDesc AS Bez, b.GroupType AS gt, b.UsageType AS ut,
           NULLIF(d.UValue, -987654321.99) AS U,
           NULLIF(d.PsiValue, -987654321.99) AS Psi,
           m.CatalogMediaType AS Rolle, m.Media, DATALENGTH(m.Media) AS Bytes,
           ROW_NUMBER() OVER (PARTITION BY b.LongDesc, m.CatalogMediaType ORDER BY d.UValue) AS rn
    FROM TcBuildingElementDimension d
    JOIN TcBasis b ON b.UId = d.BasisUId
    JOIN platz pl ON pl.BasisUId = d.BasisUId
    JOIN TcMediaReference r ON r.UId = d.UId
    JOIN TcMedia m ON m.UId = r.MediaUId AND m.Media IS NOT NULL
    WHERE pl.Katalog = @kat
      AND (@muster = '' OR b.LongDesc LIKE '%' + @muster + '%')
)
SELECT TOP (@n) Nr, Bez, gt, ut, U, Psi, Rolle, Bytes, Media
FROM gereiht WHERE rn = 1
ORDER BY Bez, Rolle
"@

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=HsetuAppTimData;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
$tx = $con.BeginTransaction()
try {
    $c = $con.CreateCommand(); $c.Transaction = $tx; $c.CommandTimeout = 300
    $c.CommandText = $abfrage
    [void]$c.Parameters.AddWithValue('@kat', $Katalog)
    [void]$c.Parameters.AddWithValue('@muster', $Muster)
    [void]$c.Parameters.AddWithValue('@n', $Anzahl)

    $tab = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)

    $i = 0
    foreach ($r in $tab.Rows) {
        $i++
        $bytes = [byte[]]$r['Media']
        # Format am Dateikopf erkennen, nicht am Namen -- MediaName ist leer.
        $kopf = ($bytes[0..1] | ForEach-Object { $_.ToString('X2') }) -join ''
        $bmp = $kopf -eq '424D'

        # Zeichenklasse bewusst ohne Umlaute im Quelltext: PowerShell 5.1 liest
        # .ps1 ohne BOM als ANSI, dann steht hier nicht mehr, was hier steht.
        $name = ($r['Bez'] -replace '[^\p{L}\p{N}\s-]', '' -replace '\s+', '-')
        if ($name.Length -gt 48) { $name = $name.Substring(0, 48) }
        $nr = if ([string]::IsNullOrWhiteSpace([string]$r['Nr'])) { '' } else { "$($r['Nr'])-" }
        $basis = Join-Path $Ziel ("{0:D2}-{1}{2}-rolle{3}" -f $i, $nr, $name, $r['Rolle'])

        if ($bmp) {
            # BMP nach PNG: unkomprimiert ~30 KB je 100x100, als PNG ein Bruchteil.
            $ms = New-Object System.IO.MemoryStream(, $bytes)
            $bild = [System.Drawing.Image]::FromStream($ms)
            $bild.Save("$basis.png", [System.Drawing.Imaging.ImageFormat]::Png)
            $gr = "$($bild.Width)x$($bild.Height)"
            $bild.Dispose(); $ms.Dispose()
            $datei = "$basis.png"
        } else {
            [System.IO.File]::WriteAllBytes("$basis.jpg", $bytes)
            $ms = New-Object System.IO.MemoryStream(, $bytes)
            $bild = [System.Drawing.Image]::FromStream($ms)
            $gr = "$($bild.Width)x$($bild.Height)"
            $bild.Dispose(); $ms.Dispose()
            $datei = "$basis.jpg"
        }

        $kennwert = if ($r['Psi'] -isnot [System.DBNull]) { "Psi $([math]::Round([double]$r['Psi'],3))" }
                    elseif ($r['U'] -isnot [System.DBNull]) { "U $([math]::Round([double]$r['U'],2))" }
                    else { '' }
        Write-Output ("{0,-8} {1,5} px  {2,7} B  {3,-12} {4}" -f
            $(if ($bmp) { 'BMP-PNG' } else { 'JPEG' }), $gr, $r['Bytes'], $kennwert, (Split-Path $datei -Leaf))
    }
}
finally { try { $tx.Rollback() } catch {}; $con.Close() }
