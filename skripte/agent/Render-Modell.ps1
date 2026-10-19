<#
    Render-Modell.ps1 - zeichnet die Bauteilflaechen aus BmElement.GeoDesc als Bild.

    Kein Ersatz fuer einen Viewer, sondern ein Diagnosewerkzeug: damit laesst
    sich von hier aus nachsehen, wo das Modell offen ist, statt es aus
    Bildschirmfotos zu erraten. Maleralgorithmus, flache Schattierung.
#>

param(
    [string] $ProjectGuid = '79A52ACD-0032-4BCF-9DC2-4051CC08AD6C',
    [string] $Out         = 'modell.png',
    [double] $Azimut      = 225,   # Blickrichtung in Grad, 0 = von Norden
    [double] $Hoehe       = 20,    # Kamerahoehe in Grad ueber dem Horizont
    [int]    $Breite      = 1400,
    [int]    $Hoch        = 1000,
    [string] $Hervorheben = '',    # Bauteilname, der farbig markiert wird
    [string] $Konvention  = 'DIN18599_2011',
    # Ausschnitt: nur Flaechen zeichnen, deren Mittelpunkt darin liegt.
    [double] $XVon = -99999, [double] $XBis = 99999,
    [double] $YVon = -99999, [double] $YBis = 99999,
    [double] $ZVon = -99999, [double] $ZBis = 99999,
    [switch] $Beschriften,
    <#
        Koerper statt Flaechen zeichnen - nach denselben Regeln wie
        Export-Ifc.ps1 mit -SaubereEcken.

        Ohne das zeigt der Renderer die Bezugsflaechen, das IFC aber Koerper mit
        Dicke. Genau in dieser Luecke sassen die Fehler, die nur im Viewer
        auffielen: Eckwuerfel, Rippen, Naehte. Mit -Koerper laesst sich von hier
        aus nachsehen, was tatsaechlich entsteht.
    #>
    [switch] $Koerper,
    [string] $Server      = '(localdb)\HSETU',
    [string] $Database    = 'HsetuPrjData'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$INV = [System.Globalization.CultureInfo]::InvariantCulture

# ------------------------------------------------------------------ Daten holen

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
SELECT e.LongDesc, e.ElementType, e.Thickness, e.GeoDesc,
       CAST(ISNULL(c.CladdingSurface,0) AS int) AS Huelle
FROM BmElement e LEFT JOIN BmElementEnergyConsulting c ON c.UUID = e.UUID
WHERE e.ProjectUUID=@p AND e.RepositoryType=1
"@
$null = $cmd.Parameters.AddWithValue('@p', [guid] $ProjectGuid)
$r = $cmd.ExecuteReader()

$flaechen = New-Object System.Collections.ArrayList
while ($r.Read()) {
    $gd = $r['GeoDesc']
    if ([string]::IsNullOrWhiteSpace($gd)) { continue }
    $x = New-Object System.Xml.XmlDocument
    try { $x.LoadXml($gd) } catch { continue }

    $pk = @{}
    foreach ($p in $x.SelectNodes('//geoPointData')) {
        $k = $p.GetAttribute('ParentUUID')
        if (-not $pk.ContainsKey($k)) { $pk[$k] = New-Object System.Collections.ArrayList }
        $null = $pk[$k].Add([pscustomobject]@{
            S = [int] $p.GetAttribute('SortNum')
            X = [double]::Parse($p.GetAttribute('Px'), $INV)
            Y = [double]::Parse($p.GetAttribute('Py'), $INV)
            Z = [double]::Parse($p.GetAttribute('Pz'), $INV)
        })
    }
    $saetze = @{}
    foreach ($l in $x.SelectNodes('//geoLoopData')) {
        $s = ($l.GetAttribute('LongDesc') -replace '\s*\d+$', ''); if ($s -eq '') { $s = '(ohne)' }
        $u = $l.GetAttribute('UUID'); if (-not $pk.ContainsKey($u)) { continue }
        if (-not $saetze.ContainsKey($s)) { $saetze[$s] = New-Object System.Collections.ArrayList }
        $null = $saetze[$s].Add(@($pk[$u] | Sort-Object S))
    }
    $wahl = $null
    foreach ($k in @($Konvention,'DIN18599_2011','Inner','DIN18599','EN12831')) { if ($saetze.ContainsKey($k)) { $wahl = $saetze[$k]; break } }
    if ($null -eq $wahl) { continue }

    $dicke = [double] $r['Thickness']
    if ($dicke -le 0.005 -or $dicke -gt 5.0) { $dicke = 0.05 }
    $typ = [int] $r['ElementType']

    foreach ($ps in $wahl) {
        if ($ps.Count -lt 3) { continue }
        $mx = 0.0; $my = 0.0; $mz = 0.0
        foreach ($p in $ps) { $mx += $p.X; $my += $p.Y; $mz += $p.Z }
        $mx /= $ps.Count; $my /= $ps.Count; $mz /= $ps.Count
        if ($mx -lt $XVon -or $mx -gt $XBis -or $my -lt $YVon -or $my -gt $YBis -or $mz -lt $ZVon -or $mz -gt $ZBis) { continue }

        $satz = @{
            Name = [string] $r['LongDesc']
            Typ = $typ
            Huelle = [int] $r['Huelle']
            P = $ps
            MX = $mx; MY = $my; MZ = $mz
        }

        if (-not $Koerper) { $null = $flaechen.Add([pscustomobject] $satz); continue }

        # --- Koerper: Normale, Versatz nach denselben Regeln wie der Exporter
        $nx=0.0;$ny=0.0;$nz=0.0
        for ($i = 0; $i -lt $ps.Count; $i++) {
            $a = $ps[$i]; $b = $ps[($i+1) % $ps.Count]
            $nx += ($a.Y*$b.Z)-($b.Y*$a.Z); $ny += ($a.Z*$b.X)-($b.Z*$a.X); $nz += ($a.X*$b.Y)-($b.X*$a.Y)
        }
        $nl = [math]::Sqrt(($nx*$nx)+($ny*$ny)+($nz*$nz))
        if ($nl -lt 1e-9) { continue }
        $nx/=$nl; $ny/=$nl; $nz/=$nl

        $vor = -0.5 * $dicke
        if ($saetze.ContainsKey('Inner') -and $saetze['Inner'].Count -gt 0) {
            $ci = $saetze['Inner'][0]
            $ix=0.0;$iy=0.0;$iz=0.0; foreach ($p in $ci) { $ix+=$p.X;$iy+=$p.Y;$iz+=$p.Z }
            $ix/=$ci.Count; $iy/=$ci.Count; $iz/=$ci.Count
            $ab = (($ix-$mx)*$nx)+(($iy-$my)*$ny)+(($iz-$mz)*$nz)
            $vh = $ab / $dicke

            if ($typ -in @(1,2,3)) {
                if ([math]::Abs([math]::Abs($vh)-0.5) -lt 0.2) { $vor = -0.5*$dicke }
                elseif ([math]::Abs($vh-1.0) -lt 0.3) { $vor = 0.0 }
                elseif ([math]::Abs($vh+1.0) -lt 0.3) { $vor = -1.0*$dicke }
                elseif ([math]::Abs($vh) -gt 1.5) {
                    $ri = if ($ab -ge 0) { 1.0 } else { -1.0 }
                    $vor = ($ab - ($ri*$dicke)) / 2.0
                }
            }
            elseif ($typ -in @(4,11) -and [math]::Abs($nz) -gt 0.9) {
                $vor = if ($nz -gt 0) { -$dicke } else { 0.0 }
            }
        }

        # Vorder- und Rueckseite plus die Seitenflaechen dazwischen.
        $seiten = @()
        foreach ($s in @($vor, ($vor + $dicke))) {
            $e = @()
            foreach ($p in $ps) {
                $e += [pscustomobject]@{ X = $p.X + ($nx*$s); Y = $p.Y + ($ny*$s); Z = $p.Z + ($nz*$s) }
            }
            $seiten += ,$e
        }

        # Kopie statt Zusammenfuehren: '+' auf zwei Hashtables mit gleichem
        # Schluessel 'P' wirft, statt zu ueberschreiben.
        function Flaeche($vorlage, $punkte) {
            $k = $vorlage.Clone()
            $k.P = $punkte
            return [pscustomobject] $k
        }

        foreach ($e in $seiten) { $null = $flaechen.Add((Flaeche $satz $e)) }

        for ($i = 0; $i -lt $ps.Count; $i++) {
            $j = ($i + 1) % $ps.Count
            $null = $flaechen.Add((Flaeche $satz @($seiten[0][$i], $seiten[0][$j], $seiten[1][$j], $seiten[1][$i])))
        }
    }
}
$r.Close(); $conn.Close()

Write-Host ("{0} Flaechen geladen" -f $flaechen.Count)

# -------------------------------------------------------------------- Kamera

$az = $Azimut * [math]::PI / 180.0
$el = $Hoehe * [math]::PI / 180.0

# Blickrichtung: vom Betrachter zum Modell
$dx = [math]::Sin($az) * [math]::Cos($el)
$dy = [math]::Cos($az) * [math]::Cos($el)
$dz = [math]::Sin($el)

# Rechtshaendiges Kamerasystem: rechts, oben, hinein
$rx = [math]::Cos($az); $ry = -[math]::Sin($az); $rz = 0.0
$ux = -[math]::Sin($az) * [math]::Sin($el)
$uy = -[math]::Cos($az) * [math]::Sin($el)
$uz = [math]::Cos($el)

function Projiziere($p) {
    return @{
        U = $p.X * $rx + $p.Y * $ry + $p.Z * $rz
        V = $p.X * $ux + $p.Y * $uy + $p.Z * $uz
        T = $p.X * $dx + $p.Y * $dy + $p.Z * $dz   # Tiefe: gross = weit weg
    }
}

$minU = [double]::MaxValue; $maxU = [double]::MinValue
$minV = [double]::MaxValue; $maxV = [double]::MinValue
foreach ($f in $flaechen) {
    foreach ($p in $f.P) {
        $q = Projiziere $p
        if ($q.U -lt $minU) { $minU = $q.U }; if ($q.U -gt $maxU) { $maxU = $q.U }
        if ($q.V -lt $minV) { $minV = $q.V }; if ($q.V -gt $maxV) { $maxV = $q.V }
    }
}
$rand = 40
$skala = [math]::Min(($Breite - 2*$rand) / ($maxU - $minU), ($Hoch - 2*$rand) / ($maxV - $minV))

# ------------------------------------------------------------------- Zeichnen

$bmp = New-Object System.Drawing.Bitmap($Breite, $Hoch)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::FromArgb(232, 235, 238))

# Von hinten nach vorne malen.
$sortiert = $flaechen | Sort-Object -Property @{Expression={
    $t = 0.0; foreach ($p in $_.P) { $t += (Projiziere $p).T }; $t / $_.P.Count }} -Descending

$lichtX = 0.4; $lichtY = -0.5; $lichtZ = 0.75

foreach ($f in $sortiert) {
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    foreach ($p in $f.P) {
        $q = Projiziere $p
        $px = $rand + ($q.U - $minU) * $skala
        $py = $Hoch - $rand - ($q.V - $minV) * $skala
        $pts.Add((New-Object System.Drawing.PointF([float]$px, [float]$py)))
    }
    if ($pts.Count -lt 3) { continue }

    # Normale fuer die Schattierung
    $nx=0.0;$ny=0.0;$nz=0.0
    for ($i=0; $i -lt $f.P.Count; $i++) {
        $a=$f.P[$i]; $b=$f.P[($i+1)%$f.P.Count]
        $nx += $a.Y*$b.Z - $b.Y*$a.Z; $ny += $a.Z*$b.X - $b.Z*$a.X; $nz += $a.X*$b.Y - $b.X*$a.Y
    }
    $nl = [math]::Sqrt($nx*$nx+$ny*$ny+$nz*$nz)
    $hell = 0.55
    if ($nl -gt 1e-9) {
        $hell = 0.35 + 0.6 * [math]::Abs(($nx*$lichtX + $ny*$lichtY + $nz*$lichtZ) / $nl)
    }
    if ($hell -gt 1) { $hell = 1.0 }

    if ($Hervorheben -ne '' -and $f.Name -eq $Hervorheben) {
        $farbe = [System.Drawing.Color]::FromArgb(230, [int](235*$hell), [int](40*$hell), [int](150*$hell))
    } elseif ($f.Typ -eq 5) {
        $farbe = [System.Drawing.Color]::FromArgb(255, [int](120*$hell), [int](120*$hell), [int](130*$hell))
    } elseif ($f.Typ -eq 3) {
        $farbe = [System.Drawing.Color]::FromArgb(255, [int](150*$hell), [int](190*$hell), [int](225*$hell))
    } else {
        $farbe = [System.Drawing.Color]::FromArgb(255, [int](215*$hell), [int](212*$hell), [int](205*$hell))
    }

    $brush = New-Object System.Drawing.SolidBrush($farbe)
    $g.FillPolygon($brush, $pts.ToArray())
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 60, 60, 60), 0.7)
    $g.DrawPolygon($pen, $pts.ToArray())
    $brush.Dispose(); $pen.Dispose()

    if ($Beschriften) {
        $cx = 0.0; $cy = 0.0
        foreach ($pt in $pts) { $cx += $pt.X; $cy += $pt.Y }
        $cx /= $pts.Count; $cy /= $pts.Count
        $f2 = New-Object System.Drawing.Font('Segoe UI', 8)
        $b2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 200, 20, 20))
        $g.DrawString($f.Name, $f2, $b2, [float]($cx - 18), [float]($cy - 6))
        $f2.Dispose(); $b2.Dispose()
    }
}

$schrift = New-Object System.Drawing.Font('Segoe UI', 13)
$sb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,40,40,40))
$g.DrawString(("Azimut {0} Grad, Hoehe {1} Grad - {2} Flaechen" -f $Azimut, $Hoehe, $flaechen.Count), $schrift, $sb, 12, 10)
$schrift.Dispose(); $sb.Dispose()

$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host ("Bild: {0}" -f (Resolve-Path $Out))
