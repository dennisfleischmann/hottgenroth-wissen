<#
    Export-Ifc.ps1 - schreibt ein HSETU-Projekt als IFC4-Datei.

    Die Geometrie steht in BmElement.GeoDesc: je Bauteil ein XML-Baum mit
    planaren Schleifen in Weltkoordinaten (geoLoopData + geoPointData). Die
    Tabellen GeoPoint/GeoLine/GeoLoop sind leer - das ist kein fehlendes Modell,
    sondern eine andere Ablage derselben Daten.

    Jedes Bauteil traegt mehrere Schleifensaetze, benannt nach der Konvention,
    in der die Flaeche gemessen wird (Inner, DIN18599_2011, DIN18599, EN12831).
    Genommen wird DIN18599_2011: dessen Summe trifft ueber das ganze Projekt
    die gemeldete Bruttoflaeche.

    Aufruf:
      powershell -ExecutionPolicy Bypass -File Export-Ifc.ps1 -ProjectGuid <GUID> -Out datei.ifc
#>

param(
    [string] $ProjectGuid = '79A52ACD-0032-4BCF-9DC2-4051CC08AD6C',
    [string] $Out         = 'projekt.ifc',
    [string] $Server      = '(localdb)\HSETU',
    [string] $Database    = 'HsetuPrjData',
    [string] $Konvention  = 'DIN18599_2011',
    # Nur die thermische Huelle ausgeben - also das, was die Software als
    # Huellflaeche A fuehrt, statt aller Bauteile einschliesslich Innenwaenden.
    [switch] $NurHuelle,
    # Bauteile als nackte Flaechen statt als Koerper mit Dicke ausgeben.
    [switch] $Flaechenmodell,
    <#
        Waende und ihre Oeffnungen dort aufdicken, wo sie hingehoeren, statt
        immer beidseitig. Betrifft NUR Waende, Fenster und Tueren - Daecher und
        Decken bleiben unangetastet.

        Das ist die kleinstmoegliche Fassung: sie beseitigt den Wuerfel an der
        Gebaeudeecke, ohne irgendetwas zu verschneiden und ohne Dach oder Decke
        zu verschieben. Standardmaessig aus.
    #>
    [switch] $SaubereEcken,
    <#
        Die Dachflaechen zu einem Koerper vereinigen - ohne die Gaube.

        Das Dach besteht in der Datenbank aus mehreren Teilflaechen je Ebene
        (Dach 001-1 bis -5, Dach 003-1 bis -6, ...), die einander teils
        ueberdecken. Vereinigt ergeben sie ein durchgehendes Stueck ohne Fugen.

        Die Gaube ('Dach DG 001' samt Wangen und Fenster) bleibt eigenstaendig.
    #>
    [switch] $DachVerschmelzen,
    <#
        Splitter nicht als Koerper zeichnen.

        Einzelne Bauteile sind schmaler als sie dick sind - 'Dach 001-2' ist
        1,70 m lang, 16 cm breit und 30 cm dick, 'EW 001' 2,80 m lang und 3 cm
        breit bei 24 cm Dicke. Aufgedickt werden daraus Rippen und Klingen, die
        quer aus Dach und Wand ragen.

        Sie bleiben als Bauteil im Modell - mit Flaeche, U-Wert und Merkmalen,
        die Berechnung braucht sie -, nur ihr Koerper wird weggelassen. Das ist
        der Unterschied zum Loeschen: nichts geht verloren, es wird nur nicht
        gezeichnet, was ohnehin kein Bauteil darstellt.

        Der Wert ist die Grenzbreite in Metern; 0 schaltet die Regel ab.
    #>
    [double] $SplitterAb = 0.0
)

$ErrorActionPreference = 'Stop'
$INV = [System.Globalization.CultureInfo]::InvariantCulture
$SENTINEL = -1e8

# ---------------------------------------------------------------- Datenzugriff

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
$conn.Open()

function Query([string] $sql) {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = 300
    $null = $cmd.Parameters.AddWithValue('@p', [guid] $ProjectGuid)
    $tbl = New-Object System.Data.DataTable
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $null = $adapter.Fill($tbl)
    return ,$tbl
}

function Val($row, [string] $col) {
    $v = $row[$col]
    if ($v -is [DBNull]) { return $null }
    return $v
}

function Flt($row, [string] $col) {
    $v = Val $row $col
    if ($null -eq $v) { return $null }
    $d = [double] $v
    if ($d -le $SENTINEL) { return $null }
    return $d
}

# ------------------------------------------------------------ STEP-Grundlagen

$sb = New-Object System.Text.StringBuilder
$script:nextId = 0

function Add([string] $body) {
    $script:nextId++
    $null = $sb.AppendLine("#$($script:nextId)=$body;")
    return "#$($script:nextId)"
}

function N($v) {
    if ($null -eq $v) { return '$' }
    $s = [string]::Format($INV, '{0:0.######}', [double] $v)
    if ($s -notmatch '[.E]') { $s += '.' }
    return $s
}

function S($text) {
    if ($null -eq $text -or $text -eq '') { return '$' }
    $t = [string] $text
    $out = New-Object System.Text.StringBuilder
    $hex = $null
    foreach ($ch in $t.ToCharArray()) {
        $code = [int] $ch
        if ($code -lt 32) { continue }
        if ($code -lt 127) {
            if ($null -ne $hex) { $null = $out.Append("\X2\$hex\X0\"); $hex = $null }
            if ($ch -eq "'") { $null = $out.Append("''") }
            elseif ($ch -eq '\') { $null = $out.Append('\\') }
            else { $null = $out.Append($ch) }
        }
        else {
            if ($null -eq $hex) { $hex = '' }
            $hex += '{0:X4}' -f $code
        }
    }
    if ($null -ne $hex) { $null = $out.Append("\X2\$hex\X0\") }
    return "'" + $out.ToString() + "'"
}

$B64 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$'

function IfcGuid([guid] $g) {
    $b = $g.ToByteArray()
    $d1 = ([uint32] $b[3] -shl 24) -bor ([uint32] $b[2] -shl 16) -bor ([uint32] $b[1] -shl 8) -bor [uint32] $b[0]
    $d2 = ([uint32] $b[5] -shl 8) -bor [uint32] $b[4]
    $d3 = ([uint32] $b[7] -shl 8) -bor [uint32] $b[6]
    $num = @(
        [uint32] ([math]::Floor($d1 / 16777216)),
        [uint32] ($d1 % 16777216),
        [uint32] ($d2 * 256 + [math]::Floor($d3 / 256)),
        [uint32] (($d3 % 256) * 65536 + [uint32] $b[8] * 256 + [uint32] $b[9]),
        [uint32] ([uint32] $b[10] * 65536 + [uint32] $b[11] * 256 + [uint32] $b[12]),
        [uint32] ([uint32] $b[13] * 65536 + [uint32] $b[14] * 256 + [uint32] $b[15])
    )
    $len = @(2, 4, 4, 4, 4, 4)
    $res = ''
    for ($i = 0; $i -lt 6; $i++) {
        $act = $num[$i]; $chunk = ''
        for ($k = 0; $k -lt $len[$i]; $k++) {
            $chunk = $B64[[int] ($act % 64)] + $chunk
            $act = [math]::Floor($act / 64)
        }
        $res += $chunk
    }
    return $res
}

$script:guidCounter = 0
function NewGuid22 {
    $script:guidCounter++
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$ProjectGuid-$($script:guidCounter)"))
    return IfcGuid ([guid] $hash)
}

# ------------------------------------------------------------------ Daten holen

Write-Host 'Lese Projektdaten ...'

$projekt = (Query "SELECT UUID, ShortDesc, LongDesc FROM PrProject WHERE UUID=@p").Rows[0]

# CladdingSurface sagt, ob eine Flaeche zur thermischen Huelle gehoert. Das Flag
# haengt ueber dieselbe UUID am Element und ist NICHT aus Typ und Angrenzung
# herzuleiten: gleiche Aussenwand, gleicher Aufbau, einmal Huelle, einmal nicht
# (unbeheizter Anbau). Die Software zeigt in ihrer Bauteilliste genau diese
# markierten Flaechen - am Beispielprojekt 88 von 198, 435,37 von 1119,35 m2.
$elemente = Query @"
SELECT e.UUID, e.ParentUUID, e.ElementType, e.AdjacentType, e.LongDesc,
       e.Height, e.Width, e.Thickness, e.Orientation, e.Slope,
       e.GrossArea, e.NetArea, e.NumberOfElements, e.UValue, e.R,
       e.CatalogDimUUID, e.AdjacentTemperature, e.GeoDesc,
       CAST(ISNULL(c.CladdingSurface, 0) AS int) AS Huelle,
       CAST(ISNULL(c.FxElementType, 0) AS int) AS Fx
FROM BmElement e
LEFT JOIN BmElementEnergyConsulting c ON c.UUID = e.UUID
WHERE e.ProjectUUID=@p AND e.RepositoryType=1
ORDER BY e.ElementType, e.LongDesc
"@

$gebaeude = Query @"
SELECT TOP 1 b.BuildingBasicFloorArea AS Grundflaeche, b.Area AS Bruttogrundflaeche,
       b.UsefulArea AS Nettogrundflaeche, b.Height AS Hoehe,
       b.HeatedVolumeOfBuilding AS Bruttovolumen,
       d.DIN18599V2011NetHeatedVolumeOfBuilding AS Luftvolumen
FROM BmBuilding b
LEFT JOIN BmBuildingDimensioning d ON d.UUID = b.UUID
WHERE b.ProjectUUID=@p
"@

$raeume = Query @"
SELECT UUID, ShortDesc, LongDesc, Area, Height, Volume,
       InsideTemperature, HeatingLoad
FROM BmRoom WHERE ProjectUUID=@p ORDER BY ShortDesc
"@

$grenzen = Query @"
SELECT ReferenceFromUUID AS RaumUUID, ReferenceToUUID AS ElementUUID
FROM BmElementReference WHERE ProjectUUID=@p
"@

$schichten = Query @"
SELECT l.DimensionUId, l.SortNum, l.LongDesc, l.ShortDesc, l.Thickness
FROM TcBuildingElementDimensionLayer l
WHERE l.DimensionUId IN (
    SELECT DISTINCT CatalogDimUUID FROM BmElement
    WHERE ProjectUUID=@p AND RepositoryType=1 AND CatalogDimUUID IS NOT NULL)
ORDER BY l.DimensionUId, l.SortNum
"@

$hoehen = Query @"
SELECT DISTINCT s.ElevationOfRefHeight
FROM BmElementStorey s
WHERE s.ProjectUUID=@p AND s.ElevationOfRefHeight > $SENTINEL
ORDER BY s.ElevationOfRefHeight
"@

$bauteile = @($elemente.Rows)

$huelleFlaeche = 0.0
$huelleAnzahl = 0
foreach ($e in $bauteile) {
    if ([int] (Val $e 'Huelle') -ne 1) { continue }
    $huelleAnzahl++
    $a = Flt $e 'NetArea'
    if ($null -ne $a) { $huelleFlaeche += $a }
}

if ($NurHuelle) {
    $bauteile = @($bauteile | Where-Object { [int] (Val $_ 'Huelle') -eq 1 })
}

Write-Host ("  {0} Bauteile ({1} davon Huelle, {2:N2} m2), {3} Raeume, {4} Schichten" -f `
    $elemente.Rows.Count, $huelleAnzahl, $huelleFlaeche, $raeume.Rows.Count, $schichten.Rows.Count)
if ($NurHuelle) { Write-Host ("  Ausgegeben werden nur die {0} Huellflaechen." -f $bauteile.Count) }

# ------------------------------------------------------- Geometrie einlesen

<#
    Ein GeoDesc-Baum sieht so aus:

      GEO/geoData/geoDataData        Lagematrix M11..M33 + Mx/My/Mz
      GEO/geoLoop/geoLoopData        eine Schleife, LongDesc nennt die Konvention
      GEO/geoLoop/geoPoint/geoPointData   Punkte, ueber ParentUUID an der Schleife

    Die Schleifen sind eben und tragen Weltkoordinaten in Metern.
#>
function SchleifenAus([string] $geoDesc, [string] $bevorzugt) {
    if ([string]::IsNullOrWhiteSpace($geoDesc)) { return @() }

    $x = New-Object System.Xml.XmlDocument
    try { $x.LoadXml($geoDesc) } catch { return @() }

    $punkteJeSchleife = @{}
    foreach ($p in $x.SelectNodes('//geoPointData')) {
        $k = $p.GetAttribute('ParentUUID')
        if (-not $punkteJeSchleife.ContainsKey($k)) { $punkteJeSchleife[$k] = New-Object System.Collections.ArrayList }
        $null = $punkteJeSchleife[$k].Add([pscustomobject]@{
            Sort = [int] $p.GetAttribute('SortNum')
            X = [double]::Parse($p.GetAttribute('Px'), $INV)
            Y = [double]::Parse($p.GetAttribute('Py'), $INV)
            Z = [double]::Parse($p.GetAttribute('Pz'), $INV)
        })
    }

    # Nach Konvention gruppieren: "DIN18599_2011 0", "Inner 2" -> Satzname.
    $saetze = @{}
    foreach ($l in $x.SelectNodes('//geoLoopData')) {
        $u = $l.GetAttribute('UUID')
        if (-not $punkteJeSchleife.ContainsKey($u)) { continue }
        $satz = ($l.GetAttribute('LongDesc') -replace '\s*\d+$', '')
        if ($satz -eq '') { $satz = '(ohne)' }
        if (-not $saetze.ContainsKey($satz)) { $saetze[$satz] = New-Object System.Collections.ArrayList }
        $punkte = @($punkteJeSchleife[$u] | Sort-Object Sort)
        if ($punkte.Count -ge 3) { $null = $saetze[$satz].Add($punkte) }
    }

    # Das fuehrende Komma ist Pflicht: ohne es loest PowerShell die Liste von
    # Schleifen zu einer Liste von Punkten auf, und jede Schleife bestuende
    # danach aus einem einzigen Punkt.
    if ($saetze.Count -eq 0) { return ,@() }
    if ($saetze.ContainsKey($bevorzugt)) { return ,$saetze[$bevorzugt] }

    foreach ($ersatz in @('DIN18599_2011', 'Inner', 'DIN18599', 'EN12831')) {
        if ($saetze.ContainsKey($ersatz)) { return ,$saetze[$ersatz] }
    }

    foreach ($k in $saetze.Keys) { return ,$saetze[$k] }
    return ,@()
}

function SchleifenFlaeche($punkte) {
    $ax = 0.0; $ay = 0.0; $az = 0.0
    for ($i = 0; $i -lt $punkte.Count; $i++) {
        $a = $punkte[$i]; $b = $punkte[($i + 1) % $punkte.Count]
        $ax += $a.Y * $b.Z - $b.Y * $a.Z
        $ay += $a.Z * $b.X - $b.Z * $a.X
        $az += $a.X * $b.Y - $b.X * $a.Y
    }
    return [math]::Sqrt($ax * $ax + $ay * $ay + $az * $az) / 2.0
}

<#
    Macht aus ebenen Schleifen Volumenkoerper.

    Jede Flaeche wird um die uebergebene Dicke aufgedickt, mittig zur
    Bezugsebene. Erst damit sieht das Modell aus wie ein Haus statt wie ein
    Kartenhaus. Dieselbe Rechnung erzeugt spaeter die Aussparungen fuer Fenster
    und Tueren - dort mit der Dicke der Wand statt der des Fensters.
#>
$script:flaecheGeschrieben = 0.0

<#
    Wo beginnt der Koerper vor der Bezugsflaeche?

    Nur fuer -SaubereEcken. Gemessen wird der Abstand zwischen
    'DIN18599_2011' und 'Inner' derselben Flaeche:

      Aussenwand   Abstand = 1,0 x Dicke   Bezugsflaeche ist die Aussenflaeche
      Innenwand    Abstand = 0,5 x Dicke   Bezugsflaeche ist die Mitte
      Fenster      Abstand = Wandstaerke   Scheibe sitzt in der Laibung

    Beidseitig aufzudicken ist nur im zweiten Fall richtig. Bei einer
    Aussenwand ragt der Koerper sonst eine halbe Dicke vor die Aussenflaeche -
    an einer Ecke tun das beide Waende, und es bleibt ein Wuerfel von 12 x 12 cm
    stehen. Gemessen an EW 005 x EW 006: die Bezugsumlaeufe treffen sich auf
    0,000 m genau, der Ueberstand betraegt je 0,120 m.

    Zurueckgegeben wird ein Mass in Metern entlang der Normalen.
#>
function VersatzFuer([string] $geoDesc, $schleifen, [double] $dicke) {
    if ($schleifen.Count -eq 0 -or $dicke -le 1e-6) { return (-0.5 * $dicke) }

    $innen = SchleifenAus $geoDesc 'Inner'
    if ($innen.Count -eq 0) { return (-0.5 * $dicke) }

    $bezug = $schleifen[0]
    $nx = 0.0; $ny = 0.0; $nz = 0.0
    for ($i = 0; $i -lt $bezug.Count; $i++) {
        $a = $bezug[$i]; $b = $bezug[($i + 1) % $bezug.Count]
        $nx += ($a.Y * $b.Z) - ($b.Y * $a.Z)
        $ny += ($a.Z * $b.X) - ($b.Z * $a.X)
        $nz += ($a.X * $b.Y) - ($b.X * $a.Y)
    }
    $nl = [math]::Sqrt(($nx*$nx) + ($ny*$ny) + ($nz*$nz))
    if ($nl -lt 1e-9) { return (-0.5 * $dicke) }
    $nx /= $nl; $ny /= $nl; $nz /= $nl

    $sx=0.0;$sy=0.0;$sz=0.0; foreach ($p in $bezug) { $sx+=$p.X; $sy+=$p.Y; $sz+=$p.Z }
    $sx/=$bezug.Count; $sy/=$bezug.Count; $sz/=$bezug.Count
    $ix=0.0;$iy=0.0;$iz=0.0; foreach ($p in $innen[0]) { $ix+=$p.X; $iy+=$p.Y; $iz+=$p.Z }
    $ix/=$innen[0].Count; $iy/=$innen[0].Count; $iz/=$innen[0].Count

    $abstand = (($ix-$sx)*$nx) + (($iy-$sy)*$ny) + (($iz-$sz)*$nz)
    $verh = $abstand / $dicke

    if ([math]::Abs([math]::Abs($verh) - 0.5) -lt 0.2) { return (-0.5 * $dicke) }
    if ([math]::Abs($verh - 1.0) -lt 0.3) { return 0.0 }
    if ([math]::Abs($verh + 1.0) -lt 0.3) { return (-1.0 * $dicke) }

    # Deutlich weiter als die eigene Dicke: das Bauteil sitzt in einer Laibung
    # (Fenster, Tuer). Mittig hineinsetzen, nicht mittig auf die Bezugsflaeche -
    # sonst laege die halbe Scheibe vor der Wand, deckungsgleich mit deren
    # Aussenflaeche, und der Viewer flackert.
    if ([math]::Abs($verh) -gt 1.5) {
        $richtung = if ($abstand -ge 0) { 1.0 } else { -1.0 }
        return (($abstand - ($richtung * $dicke)) / 2.0)
    }

    return (-0.5 * $dicke)
}

function KoerperAus($schleifen, [double] $dicke, [double] $elev, [bool] $zaehlen, $versatz = $null) {
    $koerper = @()
    foreach ($s in $schleifen) {
        $flaeche = SchleifenFlaeche $s
        if ($flaeche -le 1e-6) { continue }

        # Normale der ebenen Schleife (Newell), danach ein lokales Achsenkreuz
        # in dieser Ebene.
        $nx = 0.0; $ny = 0.0; $nz = 0.0
        for ($i = 0; $i -lt $s.Count; $i++) {
            $a = $s[$i]; $b = $s[($i + 1) % $s.Count]
            $nx += $a.Y * $b.Z - $b.Y * $a.Z
            $ny += $a.Z * $b.X - $b.Z * $a.X
            $nz += $a.X * $b.Y - $b.X * $a.Y
        }
        $nl = [math]::Sqrt($nx*$nx + $ny*$ny + $nz*$nz)
        if ($nl -lt 1e-9) { continue }
        $nx /= $nl; $ny /= $nl; $nz /= $nl

        $ux = $s[1].X - $s[0].X; $uy = $s[1].Y - $s[0].Y; $uz = $s[1].Z - $s[0].Z
        $ul = [math]::Sqrt($ux*$ux + $uy*$uy + $uz*$uz)
        if ($ul -lt 1e-9) { continue }
        $ux /= $ul; $uy /= $ul; $uz /= $ul

        $vx = $ny*$uz - $nz*$uy
        $vy = $nz*$ux - $nx*$uz
        $vz = $nx*$uy - $ny*$ux

        $zweiD = @()
        foreach ($p in $s) {
            $dx = $p.X - $s[0].X; $dy = $p.Y - $s[0].Y; $dz = $p.Z - $s[0].Z
            $zweiD += Add ("IFCCARTESIANPOINT(({0},{1}))" -f `
                (N ($dx*$ux + $dy*$uy + $dz*$uz)), (N ($dx*$vx + $dy*$vy + $dz*$vz)))
        }
        # Geschlossene Kurve: der erste Punkt steht am Ende noch einmal.
        $linie = Add ("IFCPOLYLINE(({0},{1}))" -f ($zweiD -join ','), $zweiD[0])
        $profil = Add "IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,`$,$linie)"

        # Ursprung um eine halbe Dicke gegen die Normale versetzt, damit die
        # Bezugsebene in der Mitte des Koerpers liegt - sofern nichts anderes
        # uebergeben wurde (siehe VersatzFuer, nur bei -SaubereEcken).
        $vor = if ($null -ne $versatz) { [double] $versatz } else { -0.5 * $dicke }

        $ox = $s[0].X - $offsetX + ($nx * $vor)
        $oy = $s[0].Y - $offsetY + ($ny * $vor)
        $oz = $s[0].Z - $elev    + ($nz * $vor)

        $ort = Add ("IFCCARTESIANPOINT(({0},{1},{2}))" -f (N $ox), (N $oy), (N $oz))
        $achse = Add ("IFCDIRECTION(({0},{1},{2}))" -f (N $nx), (N $ny), (N $nz))
        $refr = Add ("IFCDIRECTION(({0},{1},{2}))" -f (N $ux), (N $uy), (N $uz))
        $lage = Add "IFCAXIS2PLACEMENT3D($ort,$achse,$refr)"
        $hoch = Add "IFCDIRECTION((0.,0.,1.))"
        $koerper += Add ("IFCEXTRUDEDAREASOLID({0},{1},{2},{3})" -f $profil, $lage, $hoch, (N $dicke))

        if ($zaehlen) { $script:flaecheGeschrieben += $flaeche }
    }
    return ,$koerper
}

Write-Host 'Lese Geometrie ...'

$geo = @{}
$versatz = @{}
$ohneGeometrie = 0
$minX = [double]::MaxValue; $minY = [double]::MaxValue; $minZ = [double]::MaxValue
$maxX = [double]::MinValue; $maxY = [double]::MinValue; $maxZ = [double]::MinValue
$flaecheGeo = 0.0

foreach ($e in $bauteile) {
    $schleifen = SchleifenAus ([string] (Val $e 'GeoDesc')) $Konvention
    if ($schleifen.Count -eq 0) { $ohneGeometrie++; continue }

    foreach ($s in $schleifen) {
        $flaecheGeo += SchleifenFlaeche $s
        foreach ($p in $s) {
            if ($p.X -lt $minX) { $minX = $p.X }; if ($p.X -gt $maxX) { $maxX = $p.X }
            if ($p.Y -lt $minY) { $minY = $p.Y }; if ($p.Y -gt $maxY) { $maxY = $p.Y }
            if ($p.Z -lt $minZ) { $minZ = $p.Z }; if ($p.Z -gt $maxZ) { $maxZ = $p.Z }
        }
    }
    $uuBt = [string] (Val $e 'UUID')
    $geo[$uuBt] = $schleifen

    if ($SaubereEcken) {
        $etBt = [int] (Val $e 'ElementType')
        $dBt = Flt $e 'Thickness'
        if ($null -eq $dBt -or $dBt -le 0.005 -or $dBt -gt 5.0) { $dBt = 0.05 }

        if ($etBt -in @(1, 2, 3)) {
            $v = VersatzFuer ([string] (Val $e 'GeoDesc')) $schleifen ([double] $dBt)
            if ([math]::Abs($v + (0.5 * $dBt)) -gt 1e-9) { $versatz[$uuBt] = $v }
        }
        elseif ($etBt -in @(4, 11)) {
            <#
                Decken unter ihre Bezugsflaeche legen.

                Gemessen am Beispielprojekt: die Bezugsflaeche der Kellerdecke
                liegt auf 0,20 m, dort endet der 20 cm hohe Wandstreifen der
                Deckenstirn (0,00 bis 0,20 m) und dort beginnt die EG-Wand. Sie
                ist also die Oberkante. Mittig aufgedickt spannte die Decke von
                0,10 bis 0,30 m - durchstiess also den Streifen von unten und
                ragte oben in die Wand.
            #>
            $bez = $schleifen[0]
            $nxD = 0.0; $nyD = 0.0; $nzD = 0.0
            for ($i = 0; $i -lt $bez.Count; $i++) {
                $a = $bez[$i]; $b = $bez[($i + 1) % $bez.Count]
                $nxD += ($a.Y * $b.Z) - ($b.Y * $a.Z)
                $nyD += ($a.Z * $b.X) - ($b.Z * $a.X)
                $nzD += ($a.X * $b.Y) - ($b.X * $a.Y)
            }
            $nlD = [math]::Sqrt(($nxD*$nxD) + ($nyD*$nyD) + ($nzD*$nzD))

            # Nur waagerechte Platten - eine senkrechte Bodenplatte gibt es
            # nicht, aber die Regel soll nicht auf krumme Faelle durchschlagen.
            if ($nlD -gt 1e-9 -and ([math]::Abs($nzD) / $nlD) -gt 0.9) {
                $versatz[$uuBt] = if ($nzD -gt 0) { -$dBt } else { 0.0 }
            }
        }
    }
}

if ($SaubereEcken) {
    Write-Host ("  Saubere Ecken: {0} von {1} Bauteilen anders aufgedickt" -f $versatz.Count, $geo.Count)
}

<#
    Schneidkoerper: die Fassadenwaende.

    Gesammelt werden nur Waende gegen aussen (3) und gegen Erdreich (5) - sie
    bilden die Huelle, hinter der die Decke enden soll. Innenwaende bleiben
    aussen vor: die stehen AUF der Decke und duerfen sie nicht durchtrennen.
#>
$schneider = New-Object System.Collections.ArrayList

if ($SaubereEcken) {
    foreach ($e in $bauteile) {
        if (([int] (Val $e 'ElementType')) -ne 1) { continue }
        if (([int] (Val $e 'AdjacentType')) -notin @(3, 5)) { continue }

        $uuW = [string] (Val $e 'UUID')
        if (-not $geo.ContainsKey($uuW)) { continue }

        $dW = Flt $e 'Thickness'
        if ($null -eq $dW -or $dW -le 0.005 -or $dW -gt 5.0) { $dW = 0.05 }
        $vW = if ($versatz.ContainsKey($uuW)) { [double] $versatz[$uuW] } else { -0.5 * $dW }

        foreach ($s in $geo[$uuW]) {
            if ($s.Count -lt 3) { continue }

            $xs = @($s | ForEach-Object { $_.X }); $ys = @($s | ForEach-Object { $_.Y }); $zs = @($s | ForEach-Object { $_.Z })

            $null = $schneider.Add([pscustomobject]@{
                Pts = $s; T = $dW; Vor = $vW
                XMin = ($xs | Measure-Object -Minimum).Minimum - $dW
                XMax = ($xs | Measure-Object -Maximum).Maximum + $dW
                YMin = ($ys | Measure-Object -Minimum).Minimum - $dW
                YMax = ($ys | Measure-Object -Maximum).Maximum + $dW
                ZMin = ($zs | Measure-Object -Minimum).Minimum
                ZMax = ($zs | Measure-Object -Maximum).Maximum
            })
        }
    }

    Write-Host ("  {0} Fassadenflaechen stehen als Schneidkoerper bereit" -f $schneider.Count)
}

<#
    Doppelt belegte Flaechen aufloesen.

    Die groesste Flackerquelle sind nicht die Anschluesse, sondern
    Bauteile, die einander ueberdecken. Gemessen am Beispielprojekt liegen
    30 Deckenpaare mit zusammen 48,6 m2 in derselben Ebene uebereinander -
    'Ground GF 002-9' und '-10' allein mit 7,23 m2. Hottgenroth legt die
    Geschossdecke raumweise ab, und diese Teilflaechen ueberschneiden sich.

    Im Grundriss faellt das nicht auf. Im Modell liegen zwei Flaechen an
    derselben Stelle, und der Viewer kann nicht entscheiden, welche vorn ist.

    Aufgeloest wird, indem bei jedem Paar eine der beiden die andere abzieht.
    Wer weicht, entscheidet die Groesse: die kleinere Platte wird beschnitten,
    damit die grosse Flaeche zusammenhaengend bleibt. Bei gleicher Groesse
    entscheidet der Name, damit die Regel eindeutig bleibt und nicht beide
    einander wegschneiden.
#>
$doppelt = @{}

if ($SaubereEcken) {
    $platten = New-Object System.Collections.ArrayList

    foreach ($e in $bauteile) {
        $uuP = [string] (Val $e 'UUID')
        if (-not $geo.ContainsKey($uuP)) { continue }

        $typP = [int] (Val $e 'ElementType')
        $dP = Flt $e 'Thickness'
        if ($null -eq $dP -or $dP -le 0.005 -or $dP -gt 5.0) { $dP = 0.05 }
        $vP = if ($versatz.ContainsKey($uuP)) { [double] $versatz[$uuP] } else { -0.5 * $dP }

        foreach ($s in $geo[$uuP]) {
            if ($s.Count -lt 3) { continue }

            $nx=0.0;$ny=0.0;$nz=0.0
            for ($i = 0; $i -lt $s.Count; $i++) {
                $a = $s[$i]; $b = $s[($i+1) % $s.Count]
                $nx += ($a.Y*$b.Z)-($b.Y*$a.Z); $ny += ($a.Z*$b.X)-($b.Z*$a.X); $nz += ($a.X*$b.Y)-($b.X*$a.Y)
            }
            $nl = [math]::Sqrt(($nx*$nx)+($ny*$ny)+($nz*$nz))
            if ($nl -lt 1e-9) { continue }

            $null = $platten.Add([pscustomobject]@{
                Uu = $uuP; Name = [string] (Val $e 'LongDesc'); Typ = $typP
                Pts = $s; T = $dP; Vor = $vP
                N = @(($nx/$nl), ($ny/$nl), ($nz/$nl))
                A = $nl / 2.0
            })
        }
    }

    # Umlauf in die Ebene einer anderen Platte projizieren, Achsen entlang
    # deren erster Kante - in Weltachsen waere das Huellrechteck bei einem um
    # 45 Grad gedrehten Gebaeude viel zu gross.
    function Rechteck($basis, $pts) {
        $o = $basis.Pts[0]
        $ux = $basis.Pts[1].X - $o.X; $uy = $basis.Pts[1].Y - $o.Y; $uz = $basis.Pts[1].Z - $o.Z
        $ul = [math]::Sqrt(($ux*$ux)+($uy*$uy)+($uz*$uz))
        if ($ul -lt 1e-9) { return $null }
        $ux/=$ul; $uy/=$ul; $uz/=$ul
        $n = $basis.N
        $vx = ($n[1]*$uz)-($n[2]*$uy); $vy = ($n[2]*$ux)-($n[0]*$uz); $vz = ($n[0]*$uy)-($n[1]*$ux)

        $u1 = [double]::MaxValue; $u2 = [double]::MinValue
        $v1 = [double]::MaxValue; $v2 = [double]::MinValue
        foreach ($p in $pts) {
            $dx=$p.X-$o.X; $dy=$p.Y-$o.Y; $dz=$p.Z-$o.Z
            $a = ($dx*$ux)+($dy*$uy)+($dz*$uz)
            $b = ($dx*$vx)+($dy*$vy)+($dz*$vz)
            if ($a -lt $u1) { $u1 = $a }; if ($a -gt $u2) { $u2 = $a }
            if ($b -lt $v1) { $v1 = $b }; if ($b -gt $v2) { $v2 = $b }
        }
        return @{ U1=$u1; U2=$u2; V1=$v1; V2=$v2 }
    }

    $paare = 0; $flaecheDoppelt = 0.0

    for ($i = 0; $i -lt $platten.Count; $i++) {
        for ($j = $i+1; $j -lt $platten.Count; $j++) {
            $A = $platten[$i]; $B = $platten[$j]
            if ($A.Uu -eq $B.Uu -or $A.Typ -ne $B.Typ) { continue }

            $k = ($A.N[0]*$B.N[0]) + ($A.N[1]*$B.N[1]) + ($A.N[2]*$B.N[2])
            if ([math]::Abs($k) -lt 0.999) { continue }        # nicht parallel

            # Liegen sie in derselben Ebene?
            $ab = (($B.Pts[0].X - $A.Pts[0].X) * $A.N[0]) +
                  (($B.Pts[0].Y - $A.Pts[0].Y) * $A.N[1]) +
                  (($B.Pts[0].Z - $A.Pts[0].Z) * $A.N[2])
            if ([math]::Abs($ab) -gt 0.005) { continue }

            $ra = Rechteck $A $A.Pts
            $rb = Rechteck $A $B.Pts
            if ($null -eq $ra -or $null -eq $rb) { continue }

            $du = [math]::Min($ra.U2, $rb.U2) - [math]::Max($ra.U1, $rb.U1)
            $dv = [math]::Min($ra.V2, $rb.V2) - [math]::Max($ra.V1, $rb.V1)
            if ($du -le 0.01 -or $dv -le 0.01) { continue }

            $paare++
            $flaecheDoppelt += ($du * $dv)

            # Die kleinere weicht; bei gleicher Groesse der spaetere Name.
            $weicht = if ([math]::Abs($A.A - $B.A) -gt 1e-6) {
                          if ($A.A -lt $B.A) { $A } else { $B }
                      } elseif ($A.Name -gt $B.Name) { $A } else { $B }
            $bleibt = if ($weicht -eq $A) { $B } else { $A }

            if (-not $doppelt.ContainsKey($weicht.Uu)) { $doppelt[$weicht.Uu] = New-Object System.Collections.ArrayList }
            $null = $doppelt[$weicht.Uu].Add($bleibt)
        }
    }

    Write-Host ("  {0} doppelt belegte Paare ({1:N1} m2) werden aufgeloest" -f $paare, $flaecheDoppelt)
}

$script:deckenSchnitte = 0
$script:doppelSchnitte = 0
$script:dachVereint = @{}
$script:splitterZahl = 0
$script:splitterFlaeche = 0.0
$script:dachOhneKoerper = 0

<#
    Einen Schneidkoerper im Bezugssystem eines anderen Bauteils aufbauen.

    Dieselbe Extrusion wie bei einer Wand, nur mit der Geschosshoehe des
    Bauteils, von dem abgezogen wird - sonst sitzt der Schnitt um die Differenz
    der Geschosse daneben.
#>
function QuaderAus($sk, [double] $elev) {
    $s = $sk.Pts

    $nx = 0.0; $ny = 0.0; $nz = 0.0
    for ($i = 0; $i -lt $s.Count; $i++) {
        $a = $s[$i]; $b = $s[($i + 1) % $s.Count]
        $nx += ($a.Y * $b.Z) - ($b.Y * $a.Z)
        $ny += ($a.Z * $b.X) - ($b.Z * $a.X)
        $nz += ($a.X * $b.Y) - ($b.X * $a.Y)
    }
    $nl = [math]::Sqrt(($nx*$nx) + ($ny*$ny) + ($nz*$nz))
    if ($nl -lt 1e-9) { return $null }
    $nx /= $nl; $ny /= $nl; $nz /= $nl

    $ux = $s[1].X - $s[0].X; $uy = $s[1].Y - $s[0].Y; $uz = $s[1].Z - $s[0].Z
    $ul = [math]::Sqrt(($ux*$ux) + ($uy*$uy) + ($uz*$uz))
    if ($ul -lt 1e-9) { return $null }
    $ux /= $ul; $uy /= $ul; $uz /= $ul

    $vx = ($ny*$uz) - ($nz*$uy); $vy = ($nz*$ux) - ($nx*$uz); $vz = ($nx*$uy) - ($ny*$ux)

    $zweiD = @()
    foreach ($p in $s) {
        $dx = $p.X - $s[0].X; $dy = $p.Y - $s[0].Y; $dz = $p.Z - $s[0].Z
        $zweiD += Add ("IFCCARTESIANPOINT(({0},{1}))" -f `
            (N (($dx*$ux) + ($dy*$uy) + ($dz*$uz))), (N (($dx*$vx) + ($dy*$vy) + ($dz*$vz))))
    }
    $linie = Add ("IFCPOLYLINE(({0},{1}))" -f ($zweiD -join ','), $zweiD[0])
    $profil = Add "IFCARBITRARYCLOSEDPROFILEDEF(.AREA.,`$,$linie)"

    $ort = Add ("IFCCARTESIANPOINT(({0},{1},{2}))" -f `
        (N ($s[0].X - $offsetX + ($nx * $sk.Vor))),
        (N ($s[0].Y - $offsetY + ($ny * $sk.Vor))),
        (N ($s[0].Z - $elev    + ($nz * $sk.Vor))))
    $achse = Add ("IFCDIRECTION(({0},{1},{2}))" -f (N $nx), (N $ny), (N $nz))
    $refr = Add ("IFCDIRECTION(({0},{1},{2}))" -f (N $ux), (N $uy), (N $uz))
    $lage = Add "IFCAXIS2PLACEMENT3D($ort,$achse,$refr)"
    $hoch = Add "IFCDIRECTION((0.,0.,1.))"

    return Add ("IFCEXTRUDEDAREASOLID({0},{1},{2},{3})" -f $profil, $lage, $hoch, (N $sk.T))
}

Write-Host ("  {0} Bauteile mit Geometrie, {1} ohne" -f $geo.Count, $ohneGeometrie)
Write-Host ("  Ausdehnung {0:F1} x {1:F1} m, Hoehe {2:F2} bis {3:F2} m" -f ($maxX-$minX), ($maxY-$minY), $minZ, $maxZ)
Write-Host ("  Flaechensumme der Geometrie: {0:N2} m2" -f $flaecheGeo)

# Der Nullpunkt des Modells liegt bei x~640/y~640. Die Verschiebung wandert in
# die Lage des Grundstuecks, damit das Gebaeude selbst nahe am Ursprung sitzt
# und die Weltkoordinaten trotzdem erhalten bleiben.
$offsetX = [math]::Floor($minX)
$offsetY = [math]::Floor($minY)

<#
    Der Nordwinkel des Modells.

    Das Feld Orientation gibt die echte Himmelsrichtung eines Bauteils an, die
    Flaechennormale die Richtung im Modellnetz. Beide unterscheiden sich um einen
    festen Winkel, weil das Modellnetz nicht nach Norden ausgerichtet ist - hier
    um 45 Grad. Ohne diesen Wert im IFC rechnet jedes Werkzeug, das Ausrichtungen
    aus der Geometrie ableitet, um genau diesen Betrag daneben.

    Der Winkel wird aus den Daten bestimmt, nicht angenommen: haeufigster
    Unterschied ueber alle Flaechen mit lesbarer Richtung.
#>
$haeufig = @{}
foreach ($e in $bauteile) {
    $o = Flt $e 'Orientation'
    if ($null -eq $o) { continue }
    $uu = [string] (Val $e 'UUID')
    if (-not $geo.ContainsKey($uu)) { continue }
    foreach ($s in $geo[$uu]) {
        $nx = 0.0; $ny = 0.0; $nz = 0.0
        for ($i = 0; $i -lt $s.Count; $i++) {
            $a = $s[$i]; $b = $s[($i + 1) % $s.Count]
            $nx += $a.Y * $b.Z - $b.Y * $a.Z
            $ny += $a.Z * $b.X - $b.Z * $a.X
            $nz += $a.X * $b.Y - $b.X * $a.Y
        }
        # Waagerechte Flaechen haben keine Himmelsrichtung.
        $waag = [math]::Sqrt($nx*$nx + $ny*$ny)
        if ($waag -lt 1e-6) { continue }
        $modell = ([math]::Atan2($nx, $ny) * 180.0 / [math]::PI + 360.0) % 360.0
        $diff = [int] [math]::Round((($o - $modell) % 360.0 + 360.0) % 360.0)
        if (-not $haeufig.ContainsKey($diff)) { $haeufig[$diff] = 0 }
        $haeufig[$diff]++
    }
}
$nordWinkel = 0.0
if ($haeufig.Count -gt 0) {
    $beste = ($haeufig.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
    $nordWinkel = [double] $beste.Key
    $anteil = [math]::Round(100.0 * $beste.Value / ($haeufig.Values | Measure-Object -Sum).Sum)
    Write-Host ("  Nordwinkel des Modells: {0} Grad (bei {1}% der Flaechen)" -f $nordWinkel, $anteil)
}
# Richtung, die im Modellnetz nach Norden zeigt.
$nordX = [math]::Sin(-$nordWinkel * [math]::PI / 180.0)
$nordY = [math]::Cos(-$nordWinkel * [math]::PI / 180.0)

# ---------------------------------------------------------- Geschosse ableiten

function LevelRank([string] $name) {
    switch -regex ($name) {
        '^(KG|Keller)' { return -1 }
        '^EG'          { return 0 }
        '^OG(\d+)'     { return [int] $matches[1] }
        '^(DG|RF|SB)'  { return 90 }
        default        { return 0 }
    }
}

$levelVonRaum = @{}
$levels = @{}
foreach ($r in $raeume.Rows) {
    $name = [string] (Val $r 'ShortDesc')
    $key = ($name -split '-')[0]
    if ($key -eq '') { $key = 'EG' }
    $levelVonRaum[[string] (Val $r 'UUID')] = $key
    if (-not $levels.ContainsKey($key)) {
        $levels[$key] = [pscustomobject]@{ Key = $key; Rank = (LevelRank $key); Elev = $null; Hoehe = 2.6; Raeume = @() }
    }
    $levels[$key].Raeume += $r
    $h = Flt $r 'Height'
    if ($null -ne $h -and $h -gt 0) { $levels[$key].Hoehe = $h }
}

$geschosse = @($levels.Values | Sort-Object Rank)
$echteHoehen = @($hoehen.Rows | ForEach-Object { [double] $_[0] } | Sort-Object)

$zuordnung = [math]::Min($geschosse.Count, $echteHoehen.Count)
for ($i = 0; $i -lt $zuordnung; $i++) {
    $geschosse[$geschosse.Count - 1 - $i].Elev = $echteHoehen[$echteHoehen.Count - 1 - $i]
}
for ($i = $geschosse.Count - $zuordnung - 1; $i -ge 0; $i--) {
    $geschosse[$i].Elev = [math]::Round($geschosse[$i + 1].Elev - $geschosse[$i].Hoehe - 0.25, 2)
}
foreach ($g in $geschosse) { if ($null -eq $g.Elev) { $g.Elev = 0.0 } }

Write-Host ('  Geschosse: ' + (($geschosse | ForEach-Object { "$($_.Key) @ $($_.Elev) m" }) -join ', '))

$elemVonUuid = @{}
foreach ($e in $bauteile) { $elemVonUuid[[string] (Val $e 'UUID')] = $e }

$raeumeVonElement = @{}
foreach ($b in $grenzen.Rows) {
    $eu = [string] (Val $b 'ElementUUID'); $ru = [string] (Val $b 'RaumUUID')
    if (-not $raeumeVonElement.ContainsKey($eu)) { $raeumeVonElement[$eu] = @() }
    if ($levelVonRaum.ContainsKey($ru)) { $raeumeVonElement[$eu] += $levelVonRaum[$ru] }
}

# Mit echter Geometrie entscheidet die Hoehenlage, nicht mehr der Raumname:
# das Bauteil gehoert in das oberste Geschoss, das nicht ueber ihm liegt.
function GeschossVon($e) {
    $uu = [string] (Val $e 'UUID')

    if ($geo.ContainsKey($uu)) {
        $zmin = [double]::MaxValue
        foreach ($s in $geo[$uu]) { foreach ($p in $s) { if ($p.Z -lt $zmin) { $zmin = $p.Z } } }
        $treffer = $geschosse[0]
        foreach ($g in $geschosse) { if ($g.Elev -le $zmin + 0.3) { $treffer = $g } }
        return $treffer.Key
    }

    $such = $uu
    $pu = [string] (Val $e 'ParentUUID')
    if ($elemVonUuid.ContainsKey($pu)) { $such = $pu }
    if ($raeumeVonElement.ContainsKey($such) -and @($raeumeVonElement[$such]).Count -gt 0) {
        return @($raeumeVonElement[$such] | Sort-Object { $levels[$_].Rank })[0]
    }
    return $geschosse[0].Key
}

# --------------------------------------------------------- Bauteiltypen

$TYP = @{
    1  = @{ Ifc = 'IFCWALL';                 Pset = 'Pset_WallCommon';   Qto = 'Qto_WallBaseQuantities';   QA = 'NetSideArea'; QG = 'GrossSideArea'; Pre = '.SOLIDWALL.' }
    2  = @{ Ifc = 'IFCDOOR';                 Pset = 'Pset_DoorCommon';   Qto = 'Qto_DoorBaseQuantities';   QA = 'Area';        QG = $null;           Pre = $null }
    3  = @{ Ifc = 'IFCWINDOW';               Pset = 'Pset_WindowCommon'; Qto = 'Qto_WindowBaseQuantities'; QA = 'Area';        QG = $null;           Pre = $null }
    4  = @{ Ifc = 'IFCSLAB';                 Pset = 'Pset_SlabCommon';   Qto = 'Qto_SlabBaseQuantities';   QA = 'NetArea';     QG = 'GrossArea';     Pre = '.FLOOR.' }
    5  = @{ Ifc = 'IFCROOF';                 Pset = 'Pset_RoofCommon';   Qto = 'Qto_RoofBaseQuantities';   QA = 'NetArea';     QG = 'GrossArea';     Pre = '.NOTDEFINED.' }
    8  = @{ Ifc = 'IFCBUILDINGELEMENTPROXY'; Pset = $null;               Qto = 'Qto_HSETU_Flaeche';        QA = 'NetArea';     QG = 'GrossArea';     Pre = '.NOTDEFINED.' }
    11 = @{ Ifc = 'IFCSLAB';                 Pset = 'Pset_SlabCommon';   Qto = 'Qto_SlabBaseQuantities';   QA = 'NetArea';     QG = 'GrossArea';     Pre = '.BASESLAB.' }
    13 = @{ Ifc = 'IFCOPENINGELEMENT';       Pset = $null;               Qto = 'Qto_HSETU_Flaeche';        QA = 'NetArea';     QG = 'GrossArea';     Pre = '.OPENING.' }
    15 = @{ Ifc = 'IFCBUILDINGELEMENTPROXY'; Pset = $null;               Qto = 'Qto_HSETU_Flaeche';        QA = 'NetArea';     QG = 'GrossArea';     Pre = '.NOTDEFINED.' }
}

$ANGRENZUNG = @{
    0 = 'ohne'; 1 = 'gegen beheizt'; 2 = 'gegen unbeheizt'; 3 = 'gegen Aussenluft'
    4 = 'innen'; 5 = 'gegen Erdreich'; 6 = 'oberste Geschossdecke'; 7 = 'Kellerdecke'; 8 = 'Gebaeude'
}
$AUSSEN = @(3, 5)

<#
    Die Fx-Kategorie nach DIN V 18599 (TDIN18599ReductionFactorType) steht in
    BmElementEnergyConsulting.FxElementType. Sie sagt, als was das Bauteil
    energetisch gerechnet wird - und Kategorie 19 heisst ausdruecklich
    "nicht zur Huellflaeche".

    Texte woertlich aus Hsetu.FW.Resources.dll, EnumModResources,
    IdsTDIN18599ReductionFactorEnumNNDescType.
#>
$FXTEXT = @{
    1  = 'Aussenwand, Fenster, Decke ueber Aussenluft, Decke ueber Tiefgarage'
    2  = 'Dach (als Systemgrenze)'
    3  = 'Dachgeschossdecke (Dachraum zur Aussenluft nicht waermegedaemmt)'
    4  = 'Wand und Decke zu Abseiten (Drempel)'
    5  = 'Wand und Decke zu unbeheiztem Raum (ausser Kellerraeumen)'
    6  = 'Wand und Fenster zu unbeheiztem Glasvorbau - mit Einfachglas'
    7  = 'Wand und Fenster zu unbeheiztem Glasvorbau - mit Zweischeibenglas'
    8  = 'Wand und Fenster zu unbeheiztem Glasvorbau - mit Waermeschutzglas'
    9  = 'Fussboden des beheizten Kellers gegen Erdreich'
    10 = 'Wand des beheizten Kellers gegen Erdreich'
    11 = 'Fussboden auf dem Erdreich ohne zusaetzliche Randdaemmung'
    12 = 'Fussboden auf dem Erdreich mit Randdaemmung - 5 m breit, waagerecht'
    13 = 'Fussboden auf dem Erdreich mit Randdaemmung - 2 m tief, senkrecht'
    14 = 'Kellerdecke und Kellerinnenwand zum unbeheizten Keller - mit Perimeterdaemmung'
    15 = 'Kellerdecke und Kellerinnenwand zum unbeheizten Keller - ohne Perimeterdaemmung'
    16 = 'Bodenplatte von niedrig beheizten Raeumen'
    17 = 'Aufgestaenderter Fussboden (z.B. belueftete Kriechkeller)'
    18 = 'Bauteil des unteren Gebaeudeabschlusses (vereinfacht)'
    19 = 'Innenwand, Innendecke, Innenfenster, Innentuer - nicht zur Huellflaeche'
    20 = 'Wand und Decke zu niedrig beheizten Raeumen'
    21 = 'Wand und Decke zu geschlossener Tiefgarage'
    22 = 'Wand und Decke zu geschlossener Garage'
    23 = 'Wand und Decke zu unkonditioniertem, ungedaemmtem Keller'
    24 = 'Wand und Decke zu unkonditioniertem, gedaemmtem Keller'
    25 = 'Wand zu unkonditioniertem, aussenluftexponiertem Stiegenhaus'
    26 = 'Wand zu Innenhof mit Glasueberdachung (Atrium)'
    27 = 'Erdanliegende Wand oder erdanliegender Fussboden (<= 1,5 m unter Erdreich)'
    28 = 'Erdanliegende Wand oder erdanliegender Fussboden (> 1,5 m unter Erdreich)'
}

# ----------------------------------------------------------------- IFC schreiben

Write-Host 'Schreibe IFC ...'

$jetzt = Get-Date
$stamp = [int][double]::Parse((Get-Date -Date $jetzt.ToUniversalTime() -UFormat %s))

$person = Add "IFCPERSON(`$,'Fleischmann','Dennis',`$,`$,`$,`$,`$)"
$orga   = Add "IFCORGANIZATION(`$,'FS Energieberater',`$,`$,`$)"
$perorg = Add "IFCPERSONANDORGANIZATION($person,$orga,`$)"
$app    = Add "IFCAPPLICATION($orga,'1.1','HSETU IFC Export','HSETU-IFC')"
$owner  = Add "IFCOWNERHISTORY($perorg,$app,`$,.ADDED.,$stamp,$perorg,$app,$stamp)"

$uLen  = Add "IFCSIUNIT(*,.LENGTHUNIT.,`$,.METRE.)"
$uArea = Add "IFCSIUNIT(*,.AREAUNIT.,`$,.SQUARE_METRE.)"
$uVol  = Add "IFCSIUNIT(*,.VOLUMEUNIT.,`$,.CUBIC_METRE.)"
$uAng  = Add "IFCSIUNIT(*,.PLANEANGLEUNIT.,`$,.RADIAN.)"
$uTime = Add "IFCSIUNIT(*,.TIMEUNIT.,`$,.SECOND.)"
$uTemp = Add "IFCSIUNIT(*,.THERMODYNAMICTEMPERATUREUNIT.,`$,.KELVIN.)"
$uPow  = Add "IFCSIUNIT(*,.POWERUNIT.,`$,.WATT.)"
$de1   = Add "IFCDERIVEDUNITELEMENT($uPow,1)"
$de2   = Add "IFCDERIVEDUNITELEMENT($uArea,-1)"
$de3   = Add "IFCDERIVEDUNITELEMENT($uTemp,-1)"
$uTher = Add "IFCDERIVEDUNIT(($de1,$de2,$de3),.THERMALTRANSMITTANCEUNIT.,`$)"
$units = Add "IFCUNITASSIGNMENT(($uLen,$uArea,$uVol,$uAng,$uTime,$uTemp,$uPow,$uTher))"

$p000  = Add "IFCCARTESIANPOINT((0.,0.,0.))"
$ax0   = Add "IFCAXIS2PLACEMENT3D($p000,`$,`$)"
$north = Add ("IFCDIRECTION(({0},{1}))" -f (N $nordX), (N $nordY))
$ctx   = Add "IFCGEOMETRICREPRESENTATIONCONTEXT(`$,'Model',3,1.E-05,$ax0,$north)"
$body  = Add "IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,$ctx,`$,.MODEL_VIEW.,`$)"

<#
    Oberflaechenstile.

    Transparency laeuft von 0 (undurchsichtig) bis 1 (unsichtbar); 0,7 ist der
    Wert, bei dem Glas als Glas gelesen wird, ohne dass der Rahmen dahinter
    verschwindet. Angehaengt wird der Stil ueber IFCSTYLEDITEM direkt an den
    Koerper - in IFC4 der vorgesehene Weg, ohne das veraltete
    IfcPresentationStyleAssignment.
#>
function NeuerStil([string] $name, [double] $r, [double] $g, [double] $b,
                  [double] $transparenz, [double] $glanz, [double] $schaerfe) {
    $farbe = Add ("IFCCOLOURRGB(`$,{0},{1},{2})" -f (N $r), (N $g), (N $b))
    $render = Add ("IFCSURFACESTYLERENDERING({0},{1},`$,`$,`$,`$,IFCNORMALISEDRATIOMEASURE({2}),IFCSPECULAREXPONENT({3}),.NOTDEFINED.)" -f `
        $farbe, (N $transparenz), (N $glanz), (N $schaerfe))
    return Add ("IFCSURFACESTYLE({0},.BOTH.,({1}))" -f (S $name), $render)
}

$glasStil     = NeuerStil 'Glas'                0.53 0.71 0.85  0.70 0.40 96
$tuerStil     = NeuerStil 'Tuer'                0.55 0.38 0.24  0.00 0.15 16
$dachStil     = NeuerStil 'Dachflaeche'         0.24 0.25 0.27  0.00 0.10 12
$fassadeStil  = NeuerStil 'Fassade'             0.82 0.80 0.75  0.00 0.05  8
$erdreichStil = NeuerStil 'gegen Erdreich'      0.38 0.32 0.26  0.00 0.03  6
$innenStil    = NeuerStil 'Innenbauteil'        0.90 0.89 0.87  0.00 0.05  8

<#
    Welcher Stil zu welchem Bauteil gehoert.

    Die Angrenzung schlaegt den Typ: eine Wand gegen Erdreich wird erdfarben,
    egal ob sie AW oder EW heisst. Alles ohne eigenen Stil bleibt in der
    Vorgabefarbe des Viewers.
#>
function StilFuer([int] $et, [int] $at) {
    if ($et -eq 3) { return $glasStil }
    if ($et -eq 2) { return $tuerStil }
    if ($et -eq 5) { return $dachStil }
    if ($at -eq 5) { return $erdreichStil }          # Erdreich, Wand wie Bodenplatte
    if ($et -eq 1 -and $at -eq 3) { return $fassadeStil }
    if ($et -eq 1 -or $et -eq 4) { return $innenStil }
    return $null
}

function Einfaerben($items, $stil) {
    if ($null -eq $stil) { return }
    foreach ($i in $items) {
        $null = Add ("IFCSTYLEDITEM({0},({1}),`$)" -f $i, $stil)
    }
}

$adresse = [string] (Val $projekt 'LongDesc')
$projName = if ($adresse) { $adresse } else { [string] (Val $projekt 'ShortDesc') }

$hinweis = 'Aus dem Gebaeudemodell der Hottgenroth-/ETU-Software erzeugt. Die Geometrie stammt aus ' +
           "BmElement.GeoDesc, Schleifensatz $Konvention - planare Huellflaechen in Weltkoordinaten. " +
           'Bauteile sind Flaechenmodelle ohne Volumenkoerper; die Dicke steht als Merkmal daneben.'

$proj = Add ("IFCPROJECT('{0}',{1},{2},{3},`$,`$,`$,({4}),{5})" -f `
    (IfcGuid ([guid] $ProjectGuid)), $owner, (S $projName), (S $hinweis), $ctx, $units)

function Placement($rel, $x, $y, $z) {
    $pt = Add ("IFCCARTESIANPOINT(({0},{1},{2}))" -f (N $x), (N $y), (N $z))
    $a2 = Add "IFCAXIS2PLACEMENT3D($pt,`$,`$)"
    if ($null -eq $rel) { return Add "IFCLOCALPLACEMENT(`$,$a2)" }
    return Add "IFCLOCALPLACEMENT($rel,$a2)"
}

# Die Verschiebung des Modells sitzt am Grundstueck, nicht an den Punkten.
$sitePl = Placement $null $offsetX $offsetY 0
$site = Add ("IFCSITE('{0}',{1},{2},`$,`$,{3},`$,`$,.ELEMENT.,`$,`$,`$,`$,`$)" -f `
    (NewGuid22), $owner, (S 'Grundstueck'), $sitePl)

$bldPl = Placement $sitePl 0 0 0
$bld = Add ("IFCBUILDING('{0}',{1},{2},`$,`$,{3},`$,{4},.ELEMENT.,`$,`$,`$)" -f `
    (NewGuid22), $owner, (S $projName), $bldPl, (S $adresse))

$null = Add ("IFCRELAGGREGATES('{0}',{1},`$,`$,{2},({3}))" -f (NewGuid22), $owner, $proj, $site)
$null = Add ("IFCRELAGGREGATES('{0}',{1},`$,`$,{2},({3}))" -f (NewGuid22), $owner, $site, $bld)

# Die Kennzahlen, die die Software auf der Seite "Gebaeudegeometrie" zeigt.
# Sie kommen aus BmBuilding/BmBuildingDimensioning, damit die Datei dieselben
# Werte fuehrt wie das Programm - und man den Export dagegen halten kann.
$gp = @()
if ($gebaeude.Rows.Count -gt 0) {
    $gz = $gebaeude.Rows[0]
    $paare = @(
        @('Grundflaeche_je_Geschoss', (Flt $gz 'Grundflaeche'), 'IFCAREAMEASURE', $uArea),
        @('Bruttogrundflaeche',       (Flt $gz 'Bruttogrundflaeche'), 'IFCAREAMEASURE', $uArea),
        @('Nettogrundflaeche',        (Flt $gz 'Nettogrundflaeche'), 'IFCAREAMEASURE', $uArea),
        @('Hoehe',                    (Flt $gz 'Hoehe'), 'IFCLENGTHMEASURE', $uLen),
        @('Bruttovolumen_beheizt_Ve', (Flt $gz 'Bruttovolumen'), 'IFCVOLUMEMEASURE', $uVol),
        @('Luftvolumen_beheizt_VL',   (Flt $gz 'Luftvolumen'), 'IFCVOLUMEMEASURE', $uVol)
    )
    foreach ($paar in $paare) {
        if ($null -eq $paar[1]) { continue }
        $gp += Add ("IFCPROPERTYSINGLEVALUE('{0}',`$,{1}({2}),{3})" -f $paar[0], $paar[2], (N $paar[1]), $paar[3])
    }

    # Huellflaeche A: keine gespeicherte Spalte, sondern die Summe der Flaechen
    # mit CladdingSurface = 1. Nutzflaeche A_N ist die GEG-Regel 0,32 * Ve fuer
    # Wohngebaeude - beides hier ausgerechnet, beides gegen die Oberflaeche geprueft.
    $gp += Add ("IFCPROPERTYSINGLEVALUE('Huellflaeche_A',`$,IFCAREAMEASURE({0}),{1})" -f (N $huelleFlaeche), $uArea)
    $ve = Flt $gz 'Bruttovolumen'
    if ($null -ne $ve) {
        $gp += Add ("IFCPROPERTYSINGLEVALUE('Nutzflaeche_AN_GEG',`$,IFCAREAMEASURE({0}),{1})" -f (N ([math]::Round(0.32 * $ve, 2))), $uArea)
        if ($ve -gt 0) {
            $gp += Add ("IFCPROPERTYSINGLEVALUE('AV_Verhaeltnis',`$,IFCREAL({0}),`$)" -f (N ([math]::Round($huelleFlaeche / $ve, 4))))
        }
    }
}
$gp += Add ("IFCPROPERTYSINGLEVALUE('Anzahl_Raeume',`$,IFCINTEGER({0}),`$)" -f $raeume.Rows.Count)
$gp += Add ("IFCPROPERTYSINGLEVALUE('Anzahl_Bauteile',`$,IFCINTEGER({0}),`$)" -f $elemente.Rows.Count)
$gp += Add ("IFCPROPERTYSINGLEVALUE('Anzahl_Huellflaechen',`$,IFCINTEGER({0}),`$)" -f $huelleAnzahl)
$gpset = Add ("IFCPROPERTYSET('{0}',{1},'Pset_HSETU_Gebaeude',`$,({2}))" -f (NewGuid22), $owner, ($gp -join ','))
$null = Add ("IFCRELDEFINESBYPROPERTIES('{0}',{1},`$,`$,({2}),{3})" -f (NewGuid22), $owner, $bld, $gpset)

$storeyRef = @{}; $storeyPl = @{}
foreach ($g in $geschosse) {
    $pl = Placement $bldPl 0 0 $g.Elev
    $st = Add ("IFCBUILDINGSTOREY('{0}',{1},{2},`$,`$,{3},`$,`$,.ELEMENT.,{4})" -f `
        (NewGuid22), $owner, (S $g.Key), $pl, (N $g.Elev))
    $storeyRef[$g.Key] = $st; $storeyPl[$g.Key] = $pl
}
$null = Add ("IFCRELAGGREGATES('{0}',{1},`$,`$,{2},({3}))" -f `
    (NewGuid22), $owner, $bld, (($geschosse | ForEach-Object { $storeyRef[$_.Key] }) -join ','))

# ------------------------------------------------------------------------ Raeume

foreach ($g in $geschosse) {
    $spaceIds = @()
    foreach ($r in @($g.Raeume)) {
        # Raeume tragen keine Geometrie - sie bekommen daher keine Darstellung,
        # sondern nur ihre Kennzahlen. Ein erfundener Quader waere schlechter
        # als gar keiner.
        $pl = Placement $storeyPl[$g.Key] 0 0 0
        $sp = Add ("IFCSPACE('{0}',{1},{2},`$,`$,{3},`$,{4},.ELEMENT.,.SPACE.,{5})" -f `
            (IfcGuid ([guid] (Val $r 'UUID'))), $owner, (S ([string] (Val $r 'ShortDesc'))), $pl, (S ([string] (Val $r 'LongDesc'))), (N $g.Elev))
        $spaceIds += $sp

        $props = @()
        $a = Flt $r 'Area'
        if ($null -ne $a) { $props += Add ("IFCPROPERTYSINGLEVALUE('NetFloorArea',`$,IFCAREAMEASURE({0}),{1})" -f (N $a), $uArea) }
        $h = Flt $r 'Height'
        if ($null -ne $h) { $props += Add ("IFCPROPERTYSINGLEVALUE('Height',`$,IFCLENGTHMEASURE({0}),{1})" -f (N $h), $uLen) }
        $v = Flt $r 'Volume'
        if ($null -ne $v) { $props += Add ("IFCPROPERTYSINGLEVALUE('GrossVolume',`$,IFCVOLUMEMEASURE({0}),{1})" -f (N $v), $uVol) }
        $ti = Flt $r 'InsideTemperature'
        if ($null -ne $ti) { $props += Add ("IFCPROPERTYSINGLEVALUE('Raumtemperatur',`$,IFCTHERMODYNAMICTEMPERATUREMEASURE({0}),`$)" -f (N $ti)) }
        $hl = Flt $r 'HeatingLoad'
        if ($null -ne $hl) { $props += Add ("IFCPROPERTYSINGLEVALUE('Heizlast',`$,IFCPOWERMEASURE({0}),{1})" -f (N $hl), $uPow) }
        if ($props.Count -gt 0) {
            $ps = Add ("IFCPROPERTYSET('{0}',{1},'Pset_HSETU_Raum',`$,({2}))" -f (NewGuid22), $owner, ($props -join ','))
            $null = Add ("IFCRELDEFINESBYPROPERTIES('{0}',{1},`$,`$,({2}),{3})" -f (NewGuid22), $owner, $sp, $ps)
        }
    }
    if ($spaceIds.Count -gt 0) {
        $null = Add ("IFCRELAGGREGATES('{0}',{1},`$,`$,{2},({3}))" -f `
            (NewGuid22), $owner, $storeyRef[$g.Key], ($spaceIds -join ','))
    }
}

# ----------------------------------------------------------- Schichtaufbauten

$layerSetVonDim = @{}
$dimGruppen = @{}
foreach ($l in $schichten.Rows) {
    $d = [string] (Val $l 'DimensionUId')
    if (-not $dimGruppen.ContainsKey($d)) { $dimGruppen[$d] = @() }
    $dimGruppen[$d] += $l
}
foreach ($d in $dimGruppen.Keys) {
    $ids = @()
    foreach ($l in $dimGruppen[$d]) {
        $t = Flt $l 'Thickness'
        if ($null -eq $t -or $t -le 0) { continue }
        $nm = [string] (Val $l 'LongDesc')
        if ($nm -eq '') { $nm = [string] (Val $l 'ShortDesc') }
        if ($nm -eq '') { $nm = 'Schicht' }
        $mat = Add ("IFCMATERIAL({0},`$,`$)" -f (S $nm))
        $ids += Add ("IFCMATERIALLAYER({0},{1},`$,{2},`$,`$,`$)" -f $mat, (N $t), (S $nm))
    }
    if ($ids.Count -gt 0) {
        $layerSetVonDim[$d] = Add ("IFCMATERIALLAYERSET(({0}),`$,`$)" -f ($ids -join ','))
    }
}

# ---------------------------------------------------------------------- Bauteile

$inGeschoss = @{}
foreach ($g in $geschosse) { $inGeschoss[$g.Key] = @() }

$geschrieben = 0
$script:flaecheGeschrieben = 0.0
$ifcRef = @{}

<#
    Welche Dachflaechen werden vereinigt?

    Erkannt am Namen: 'Dach 001-4' gehoert dazu, 'Dach DG 001' nicht - DG steht
    fuer die Gaube, die eigenstaendig bleiben soll. 'Ground UF1-1' faellt
    ebenfalls heraus: als Dach gefuehrt, aber weder Dachflaeche noch Gaube.

    Traeger ist die groesste Flaeche; sie bekommt den vereinigten Koerper und
    behaelt ihre Merkmale. Die uebrigen werden nicht mehr geschrieben.
#>
$dachTraegerVon = @{}    # Traeger-UUID -> Liste der zu vereinigenden UUIDs
$dachGehoertZu = @{}     # jede beteiligte UUID -> ihre Traeger-UUID

if ($DachVerschmelzen) {
    $kandidaten = @($bauteile | Where-Object {
        ([int] (Val $_ 'ElementType')) -eq 5 -and
        ([string] (Val $_ 'LongDesc')) -match '^Dach\s' -and
        ([string] (Val $_ 'LongDesc')) -notmatch '\sDG\s' })

    <#
        Getrennt nach thermischer Huelle.

        Neun der vierzehn Dachflaechen gehoeren zur Huelle, fuenf nicht. Alle in
        einen Koerper zu legen hiesse, diese Unterscheidung aufzugeben - die
        Huellflaeche A verlaere dabei 58,77 m2, und die ist keine Nebensache,
        sondern die Grundlage der Berechnung.

        Die Trennung ist ohnehin die richtige: das gedaemmte Dach ueber dem
        beheizten Teil ist ein anderes Bauteil als das Dach ueber dem kalten
        Spitzboden. Es entstehen also zwei Koerper statt vierzehn Flaechen.
    #>
    if ($kandidaten.Count -gt 1) {
        $ids = @($kandidaten | ForEach-Object { [string] (Val $_ 'UUID') })
        $groesste = ($kandidaten | Sort-Object { [double] (Flt $_ 'NetArea') } -Descending)[0]
        $tr = [string] (Val $groesste 'UUID')

        $dachTraegerVon[$tr] = $ids
        foreach ($id in $ids) { $dachGehoertZu[$id] = $tr }

        Write-Host ("  Dach: {0} Teilflaechen zu einem Koerper (Traeger: {1})" -f
            $ids.Count, [string] (Val $groesste 'LongDesc'))
    }
}

foreach ($e in $bauteile) {
    $et = [int] (Val $e 'ElementType')
    if (-not $TYP.ContainsKey($et)) { continue }

    $uu = [string] (Val $e 'UUID')

    <#
        Vereinigte Dachflaechen ausser dem Traeger behalten alles ausser ihrem
        Koerper.

        Der erste Anlauf hat sie ganz weggelassen und dafuer nach thermischer
        Huelle getrennt verschmolzen, damit die Huellflaeche A stimmt. Das war
        falsch: die Klassen verlaufen quer durch dieselbe Dachebene - 'Dach
        001-1' ist Nicht-Huelle, 'Dach 001-3' bis '-5' sind Huelle, alle in
        einer Ebene. Zwei getrennte Koerper zeigen an dieser Naht ihre 30 cm
        Stirnflaeche: eine weisse Klinge quer ueber dem Dach.

        Also alles in einen Koerper, und die Buchhaltung anders erhalten: die
        Teilflaechen bleiben als Bauteil mit Flaeche, U-Wert und Huellen-Flag,
        nur ohne eigene Darstellung. Dieselbe Trennung wie bei den Splittern -
        was gerechnet wird, bleibt; was gezeichnet wird, entfaellt.
    #>
    $ohneKoerper = ($dachGehoertZu.ContainsKey($uu) -and $dachGehoertZu[$uu] -ne $uu)
    if ($ohneKoerper) { $script:dachOhneKoerper++ }
    $def = $TYP[$et]
    $gk = GeschossVon $e
    $elev = $levels[$gk].Elev
    $name = [string] (Val $e 'LongDesc')
    $at = [int] (Val $e 'AdjacentType')

    <#
        Splitter: Flaeche geteilt durch die laengste Kante ergibt die mittlere
        Breite. Liegt die unter der Grenze, wird kein Koerper gezeichnet - das
        Bauteil selbst bleibt mit allen Merkmalen erhalten.
    #>
    $splitter = $false
    if ($SplitterAb -gt 0 -and $geo.ContainsKey($uu)) {
        $flS = 0.0; $langS = 0.0
        foreach ($s in $geo[$uu]) {
            $flS += SchleifenFlaeche $s
            foreach ($p1 in $s) {
                foreach ($p2 in $s) {
                    $dd = [math]::Sqrt([math]::Pow($p1.X-$p2.X, 2) + [math]::Pow($p1.Y-$p2.Y, 2) + [math]::Pow($p1.Z-$p2.Z, 2))
                    if ($dd -gt $langS) { $langS = $dd }
                }
            }
        }
        if ($langS -gt 1e-6 -and ($flS / $langS) -lt $SplitterAb) {
            $splitter = $true
            $script:splitterZahl++
            $script:splitterFlaeche += $flS
        }
    }

    # ---- Darstellung: die echten Huellflaechen, relativ zum Geschoss
    $shape = '$'
    if ($geo.ContainsKey($uu) -and -not $splitter -and -not $ohneKoerper) {
        if ($Flaechenmodell) {
            # Nackte Huellflaechen ohne Dicke - naeher an der Quelle, aber im
            # Viewer nur papierduenne Ebenen.
            $faces = @()
            foreach ($s in $geo[$uu]) {
                $ptIds = @()
                foreach ($p in $s) {
                    $ptIds += Add ("IFCCARTESIANPOINT(({0},{1},{2}))" -f `
                        (N ($p.X - $offsetX)), (N ($p.Y - $offsetY)), (N ($p.Z - $elev)))
                }
                $loop = Add ("IFCPOLYLOOP(({0}))" -f ($ptIds -join ','))
                $bound = Add "IFCFACEOUTERBOUND($loop,.T.)"
                $faces += Add "IFCFACE(($bound))"
                $script:flaecheGeschrieben += SchleifenFlaeche $s
            }
            $cfs = Add ("IFCCONNECTEDFACESET(({0}))" -f ($faces -join ','))
            $fbsm = Add "IFCFACEBASEDSURFACEMODEL(($cfs))"
            $rep = Add "IFCSHAPEREPRESENTATION($body,'Body','SurfaceModel',($fbsm))"
            $shape = Add "IFCPRODUCTDEFINITIONSHAPE(`$,`$,($rep))"
            Einfaerben @($fbsm) (StilFuer $et $at)
        }
        else {
            $dicke = Flt $e 'Thickness'
            if ($null -eq $dicke -or $dicke -le 0.005) { $dicke = 0.05 }

            $koerper = KoerperAus $geo[$uu] $dicke $elev $true $versatz[$uu]

            <#
                Traeger des vereinigten Dachs: die Koerper aller Teilflaechen
                dazunehmen und zu einem verschmelzen.

                Alle im Bezugssystem des Traegers, sonst sitzt jede Flaeche um
                die Differenz der Geschosshoehen daneben. Vereinigt (.UNION.)
                statt nur zusammengelegt: nur so verschwinden die inneren
                Fugen und die Ueberdeckungen zwischen den Teilflaechen.
            #>
            if ($dachTraegerVon.ContainsKey($uu)) {
                foreach ($tid in $dachTraegerVon[$uu]) {
                    if ($tid -eq $uu -or -not $geo.ContainsKey($tid)) { continue }

                    $tE = $elemVonUuid[$tid]
                    $tD = Flt $tE 'Thickness'
                    if ($null -eq $tD -or $tD -le 0.005) { $tD = 0.05 }

                    $koerper += KoerperAus $geo[$tid] $tD $elev $true $versatz[$tid]
                }

                if ($koerper.Count -gt 1) {
                    $vereint = $koerper[0]
                    for ($ki = 1; $ki -lt $koerper.Count; $ki++) {
                        $vereint = Add "IFCBOOLEANRESULT(.UNION.,$vereint,$($koerper[$ki]))"
                    }
                    $koerper = @($vereint)
                    $script:dachVereint[$uu] = $dachTraegerVon[$uu].Count
                }
            }

            <#
                Decke hinter die Fassade zuruecknehmen.

                Umriss und Aussenwand enden beide am selben Aussenmass - die
                DIN misst so. Der Deckenrand liegt damit exakt in der
                Fassadenebene, deckungsgleich mit dem Wandstreifen davor: zwei
                Flaechen an derselben Stelle, und der Viewer flackert.

                Statt den Umriss einzuziehen (das aendert die Flaechensumme, an
                der Test-Ifc.ps1 die Geometrie prueft) wird die Wand vom
                Deckenkoerper abgezogen. Das Profil bleibt unangetastet, nur der
                gezeigte Koerper endet an der Wandinnenseite - so, wie eine
                Decke am Bau auch endet.
            #>
            if ($SaubereEcken -and $et -in @(4, 11) -and $koerper.Count -gt 0) {
                $minXTeil = [double]::MaxValue; $maxXTeil = [double]::MinValue
                $minYTeil = [double]::MaxValue; $maxYTeil = [double]::MinValue
                $minZTeil = [double]::MaxValue; $maxZTeil = [double]::MinValue
                foreach ($s in $geo[$uu]) { foreach ($p in $s) {
                    if ($p.X -lt $minXTeil) { $minXTeil = $p.X }; if ($p.X -gt $maxXTeil) { $maxXTeil = $p.X }
                    if ($p.Y -lt $minYTeil) { $minYTeil = $p.Y }; if ($p.Y -gt $maxYTeil) { $maxYTeil = $p.Y }
                    if ($p.Z -lt $minZTeil) { $minZTeil = $p.Z }; if ($p.Z -gt $maxZTeil) { $maxZTeil = $p.Z }
                } }
                # Die Platte ist duenn; ihr Koerper reicht um die Dicke tiefer.
                $minZTeil -= $dicke; $maxZTeil += $dicke

                $abgezogen = 0
                foreach ($sk in $schneider) {
                    if ($sk.ZMax -lt ($minZTeil - 0.02) -or $sk.ZMin -gt ($maxZTeil + 0.02)) { continue }
                    if ($sk.XMax -lt ($minXTeil - 0.02) -or $sk.XMin -gt ($maxXTeil + 0.02)) { continue }
                    if ($sk.YMax -lt ($minYTeil - 0.02) -or $sk.YMin -gt ($maxYTeil + 0.02)) { continue }

                    $quader = QuaderAus $sk $elev
                    if ($null -eq $quader) { continue }

                    for ($ki = 0; $ki -lt $koerper.Count; $ki++) {
                        $koerper[$ki] = Add "IFCBOOLEANRESULT(.DIFFERENCE.,$($koerper[$ki]),$quader)"
                    }
                    $abgezogen++
                }
                if ($abgezogen -gt 0) { $script:deckenSchnitte += $abgezogen }
            }

            # Doppelt belegte Flaeche: die andere Platte abziehen.
            if ($SaubereEcken -and $doppelt.ContainsKey($uu) -and $koerper.Count -gt 0) {
                foreach ($andere in $doppelt[$uu]) {
                    $quader = QuaderAus $andere $elev
                    if ($null -eq $quader) { continue }

                    for ($ki = 0; $ki -lt $koerper.Count; $ki++) {
                        $koerper[$ki] = Add "IFCBOOLEANRESULT(.DIFFERENCE.,$($koerper[$ki]),$quader)"
                    }
                    $script:doppelSchnitte++
                }
            }

            if ($koerper.Count -gt 0) {
                $csg = ($SaubereEcken -and (($et -in @(4, 11)) -or $doppelt.ContainsKey($uu))) -or $dachTraegerVon.ContainsKey($uu)
                $art = if ($csg) { 'CSG' } else { 'SweptSolid' }
                $rep = Add ("IFCSHAPEREPRESENTATION({0},'Body','{1}',({2}))" -f $body, $art, ($koerper -join ','))
                $shape = Add "IFCPRODUCTDEFINITIONSHAPE(`$,`$,($rep))"
                Einfaerben $koerper (StilFuer $et $at)
            }
        }
    }

    $pl = Placement $storeyPl[$gk] 0 0 0
    $rumpf = "'{0}',{1},{2},{3},`$,{4},{5},{6}" -f `
        (IfcGuid ([guid] $uu)), $owner, (S $name), (S $ANGRENZUNG[$at]), $pl, $shape, (S $name)

    # Fenster und Tueren fuehren OverallHeight und OverallWidth vor dem
    # Typkennzeichen - alle uebrigen Typen haben nur das Kennzeichen.
    if ($def.Ifc -eq 'IFCWINDOW' -or $def.Ifc -eq 'IFCDOOR') {
        $art = if ($def.Ifc -eq 'IFCWINDOW') { '.WINDOW.' } else { '.DOOR.' }
        $ref = Add ("{0}({1},{2},{3},{4},.NOTDEFINED.,`$)" -f `
            $def.Ifc, $rumpf, (N (Flt $e 'Height')), (N (Flt $e 'Width')), $art)
    }
    elseif ($null -ne $def.Pre) {
        $ref = Add ("{0}({1},{2})" -f $def.Ifc, $rumpf, $def.Pre)
    }
    else {
        $ref = Add ("{0}({1},`$)" -f $def.Ifc, $rumpf)
    }

    $geschrieben++
    $inGeschoss[$gk] += $ref
    $ifcRef[$uu] = @{ Ref = $ref; Dicke = $(if ($null -ne (Flt $e 'Thickness')) { Flt $e 'Thickness' } else { 0.24 }); Elev = $elev; Typ = $et }

    # ---- Merkmale
    $props = @()
    $u = Flt $e 'UValue'
    if ($null -ne $u -and $u -gt 0) { $props += Add ("IFCPROPERTYSINGLEVALUE('ThermalTransmittance',`$,IFCTHERMALTRANSMITTANCEMEASURE({0}),{1})" -f (N $u), $uTher) }
    $props += Add ("IFCPROPERTYSINGLEVALUE('IsExternal',`$,IFCBOOLEAN(.{0}.),`$)" -f $(if ($AUSSEN -contains $at) { 'T' } else { 'F' }))
    $props += Add ("IFCPROPERTYSINGLEVALUE('Reference',`$,IFCIDENTIFIER({0}),`$)" -f (S $name))
    if ($def.Pset) {
        $ps = Add ("IFCPROPERTYSET('{0}',{1},{2},`$,({3}))" -f (NewGuid22), $owner, (S $def.Pset), ($props -join ','))
        $null = Add ("IFCRELDEFINESBYPROPERTIES('{0}',{1},`$,`$,({2}),{3})" -f (NewGuid22), $owner, $ref, $ps)
    }

    $hp = @()
    $hp += Add ("IFCPROPERTYSINGLEVALUE('Bauteil',`$,IFCLABEL({0}),`$)" -f (S $name))
    $hp += Add ("IFCPROPERTYSINGLEVALUE('Angrenzung',`$,IFCLABEL({0}),`$)" -f (S $ANGRENZUNG[$at]))
    # Das Merkmal, an dem sich die Huellflaeche A wieder aufsummieren laesst.
    $hp += Add ("IFCPROPERTYSINGLEVALUE('Huellflaeche',`$,IFCBOOLEAN(.{0}.),`$)" -f `
        $(if ([int] (Val $e 'Huelle') -eq 1) { 'T' } else { 'F' }))
    # Der Traeger des vereinigten Dachs haelt fest, woraus er entstanden ist -
    # sonst zaehlt jede Pruefung 13 Bauteile zu wenig und weiss nicht, warum.
    if ($dachTraegerVon.ContainsKey($uu)) {
        $hp += Add ("IFCPROPERTYSINGLEVALUE('Verschmolzen_aus',`$,IFCINTEGER({0}),`$)" -f $script:dachVereint[$uu])
        $hp += Add ("IFCPROPERTYSINGLEVALUE('Verschmolzen_Bauteile',`$,IFCLABEL({0}),`$)" -f `
            (S (($dachTraegerVon[$uu] | ForEach-Object { [string] (Val $elemVonUuid[$_] 'LongDesc') } | Sort-Object) -join ', ')))
    }

    $fx = [int] (Val $e 'Fx')
    if ($fx -gt 0) {
        $hp += Add ("IFCPROPERTYSINGLEVALUE('Fx_Kategorie',`$,IFCINTEGER({0}),`$)" -f $fx)
        if ($FXTEXT.ContainsKey($fx)) {
            $hp += Add ("IFCPROPERTYSINGLEVALUE('Fx_Bedeutung',`$,IFCLABEL({0}),`$)" -f (S $FXTEXT[$fx]))
        }
    }
    foreach ($paar in @(@('Dicke', (Flt $e 'Thickness')), @('Hoehe', (Flt $e 'Height')), @('Breite', (Flt $e 'Width')))) {
        if ($null -ne $paar[1]) { $hp += Add ("IFCPROPERTYSINGLEVALUE('{0}',`$,IFCLENGTHMEASURE({1}),{2})" -f $paar[0], (N $paar[1]), $uLen) }
    }
    $o = Flt $e 'Orientation'
    if ($null -ne $o) { $hp += Add ("IFCPROPERTYSINGLEVALUE('Orientierung',`$,IFCPLANEANGLEMEASURE({0}),`$)" -f (N ($o * [math]::PI / 180))) }
    $sl = Flt $e 'Slope'
    if ($null -ne $sl) { $hp += Add ("IFCPROPERTYSINGLEVALUE('Neigung',`$,IFCPLANEANGLEMEASURE({0}),`$)" -f (N ($sl * [math]::PI / 180))) }
    $rw = Flt $e 'R'
    if ($null -ne $rw) { $hp += Add ("IFCPROPERTYSINGLEVALUE('RWert',`$,IFCTHERMALRESISTANCEMEASURE({0}),`$)" -f (N $rw)) }
    $ta = Flt $e 'AdjacentTemperature'
    if ($null -ne $ta) { $hp += Add ("IFCPROPERTYSINGLEVALUE('Angrenzungstemperatur',`$,IFCTHERMODYNAMICTEMPERATUREMEASURE({0}),`$)" -f (N $ta)) }
    $pu = [string] (Val $e 'ParentUUID')
    if ($elemVonUuid.ContainsKey($pu)) {
        $hp += Add ("IFCPROPERTYSINGLEVALUE('InBauteil',`$,IFCLABEL({0}),`$)" -f (S ([string] (Val $elemVonUuid[$pu] 'LongDesc'))))
    }
    $hp += Add ("IFCPROPERTYSINGLEVALUE('HSETU_UUID',`$,IFCIDENTIFIER('{0}'),`$)" -f $uu)
    $hp += Add ("IFCPROPERTYSINGLEVALUE('Geschoss',`$,IFCLABEL({0}),`$)" -f (S $gk))
    $ps2 = Add ("IFCPROPERTYSET('{0}',{1},'Pset_HSETU_Bauteil',`$,({2}))" -f (NewGuid22), $owner, ($hp -join ','))
    $null = Add ("IFCRELDEFINESBYPROPERTIES('{0}',{1},`$,`$,({2}),{3})" -f (NewGuid22), $owner, $ref, $ps2)

    # ---- Mengen
    $q = @()
    $na = Flt $e 'NetArea'; if ($null -eq $na) { $na = 0.0 }
    $ga = Flt $e 'GrossArea'

    # Der Traeger erbt KEINE fremden Mengen: die Teilflaechen bleiben als
    # eigene Bauteile mit eigenen Mengen erhalten, nur ohne Darstellung.
    # Sie zusaetzlich hier aufzuaddieren zaehlte sie ein zweites Mal - gemessen
    # 115,68 m2 zuviel in der Nettoflaeche.
    $q += Add ("IFCQUANTITYAREA('{0}',`$,{1},{2},`$)" -f $def.QA, $uArea, (N $na))
    if ($def.QG -and $null -ne $ga) { $q += Add ("IFCQUANTITYAREA('{0}',`$,{1},{2},`$)" -f $def.QG, $uArea, (N $ga)) }
    foreach ($paar in @(@('Height', (Flt $e 'Height')), @('Width', (Flt $e 'Width')), @('Thickness', (Flt $e 'Thickness')))) {
        if ($null -ne $paar[1]) { $q += Add ("IFCQUANTITYLENGTH('{0}',`$,{1},{2},`$)" -f $paar[0], $uLen, (N $paar[1])) }
    }
    $eq = Add ("IFCELEMENTQUANTITY('{0}',{1},{2},`$,`$,({3}))" -f (NewGuid22), $owner, (S $def.Qto), ($q -join ','))
    $null = Add ("IFCRELDEFINESBYPROPERTIES('{0}',{1},`$,`$,({2}),{3})" -f (NewGuid22), $owner, $ref, $eq)

    # ---- Schichtaufbau
    $dim = [string] (Val $e 'CatalogDimUUID')
    if ($dim -and $layerSetVonDim.ContainsKey($dim)) {
        $null = Add ("IFCRELASSOCIATESMATERIAL('{0}',{1},`$,`$,({2}),{3})" -f `
            (NewGuid22), $owner, $ref, $layerSetVonDim[$dim])
    }
}

# ---------------------------------------------- Fenster und Tueren aussparen

<#
    Die Wandpolygone enthalten die Fensterflaechen: ueber das ganze Projekt ist
    SUM(GrossArea) - SUM(NetArea) genau die Flaeche der Fenster, Tueren und
    Oeffnungen. Ein 2 cm dickes Fenster steckt daher unsichtbar in einer 24 cm
    dicken Wand.

    Ausgespart wird mit dem Polygon des Fensters selbst - nichts wird erfunden -,
    aufgedickt auf die Wandstaerke mit etwas Zugabe, damit der Schnitt sauber
    durchgeht. Danach zeigt die Wand ihre Nettoflaeche, und das Fenster sitzt in
    der Oeffnung statt darin zu verschwinden.
#>
$ausgespart = 0
foreach ($e in $bauteile) {
    $uu = [string] (Val $e 'UUID')
    $pu = [string] (Val $e 'ParentUUID')
    if (-not $ifcRef.ContainsKey($uu) -or -not $ifcRef.ContainsKey($pu)) { continue }
    if ($ifcRef[$pu].Typ -ne 1) { continue }          # nur Waende werden durchbrochen
    if (-not $geo.ContainsKey($uu)) { continue }

    $wand = $ifcRef[$pu]

    <#
        Die Aussparung muss dort sitzen, wo die WAND sitzt - nicht dort, wo
        ihre Bezugsflaeche liegt.

        Mittig aufgedickt fielen beide zusammen, mit -SaubereEcken nicht mehr:
        die Wand reicht dann von 0,000 bis 0,240 m vor ihrer Bezugsflaeche, das
        mittig gesetzte Loch aber nur von -0,168 bis 0,168 m. Die inneren
        7,2 cm blieben stehen, und hinter jedem Fenster stand ein Rest Wand -
        was aussieht, als waere die Scheibe dicker als die Wand.

        Also die Lage der Wand uebernehmen und beidseitig ueberstehen lassen,
        damit der Schnitt sicher durchgeht.
    #>
    $rand = 0.05
    $tiefe = [math]::Max($wand.Dicke * 1.4, 0.1)
    $vorO = $null

    if ($SaubereEcken) {
        $vorW = if ($versatz.ContainsKey($pu)) { [double] $versatz[$pu] } else { -0.5 * $wand.Dicke }
        $tiefe = $wand.Dicke + (2.0 * $rand)
        $vorO = $vorW - $rand
    }

    $koerper = KoerperAus $geo[$uu] $tiefe $wand.Elev $false $vorO
    if ($koerper.Count -eq 0) { continue }

    $rep = Add ("IFCSHAPEREPRESENTATION({0},'Body','SweptSolid',({1}))" -f $body, ($koerper -join ','))
    $form = Add "IFCPRODUCTDEFINITIONSHAPE(`$,`$,($rep))"
    $oPl = Placement $storeyPl[(GeschossVon $e)] 0 0 0
    $oeff = Add ("IFCOPENINGELEMENT('{0}',{1},'Oeffnung {2}',`$,`$,{3},{4},`$,.OPENING.)" -f `
        (NewGuid22), $owner, ([string] (Val $e 'LongDesc')), $oPl, $form)

    $null = Add ("IFCRELVOIDSELEMENT('{0}',{1},`$,`$,{2},{3})" -f (NewGuid22), $owner, $wand.Ref, $oeff)
    $null = Add ("IFCRELFILLSELEMENT('{0}',{1},`$,`$,{2},{3})" -f (NewGuid22), $owner, $oeff, $ifcRef[$uu].Ref)
    $ausgespart++
}
Write-Host ("  {0} Oeffnungen in Waende geschnitten" -f $ausgespart)
$ohneDarstellung = $script:splitterZahl + $script:dachOhneKoerper

if ($ohneDarstellung -gt 0) {
    if ($script:splitterZahl -gt 0) {
        Write-Host ("  {0} Splitter ohne Koerper ausgegeben ({1:N2} m2) - schmaler als {2:N2} m" -f
            $script:splitterZahl, $script:splitterFlaeche, $SplitterAb)
    }
    if ($script:dachOhneKoerper -gt 0) {
        Write-Host ("  {0} Dachteilflaechen ohne eigenen Koerper - sie stecken im vereinigten Dach" -f
            $script:dachOhneKoerper)
    }

    <#
        Am Gebaeude festhalten, wieviele Bauteile bewusst ohne Darstellung
        blieben und wieviel Flaeche dabei nicht gezeichnet wurde. Ohne diese
        Werte meldete jede Pruefung eine Abweichung, die keine ist.

        Nur die Splitterflaeche fehlt wirklich - die Dachteilflaechen stecken
        im vereinigten Koerper und sind mitgezaehlt.
    #>
    $sp = @()
    $sp += Add ("IFCPROPERTYSINGLEVALUE('Splitter_Anzahl',`$,IFCINTEGER({0}),`$)" -f $ohneDarstellung)
    $sp += Add ("IFCPROPERTYSINGLEVALUE('Splitter_Flaeche',`$,IFCAREAMEASURE({0}),{1})" -f (N $script:splitterFlaeche), $uArea)
    $sp += Add ("IFCPROPERTYSINGLEVALUE('Splitter_Grenzbreite',`$,IFCLENGTHMEASURE({0}),{1})" -f (N $SplitterAb), $uLen)
    $spset = Add ("IFCPROPERTYSET('{0}',{1},'Pset_HSETU_Darstellung',`$,({2}))" -f (NewGuid22), $owner, ($sp -join ','))
    $null = Add ("IFCRELDEFINESBYPROPERTIES('{0}',{1},`$,`$,({2}),{3})" -f (NewGuid22), $owner, $bld, $spset)
}

foreach ($g in $geschosse) {
    $liste = @($inGeschoss[$g.Key])
    if ($liste.Count -eq 0) { continue }
    $null = Add ("IFCRELCONTAINEDINSPATIALSTRUCTURE('{0}',{1},`$,`$,({2}),{3})" -f `
        (NewGuid22), $owner, ($liste -join ','), $storeyRef[$g.Key])
}

# ------------------------------------------------------------------ Datei bauen

$dateiName = [System.IO.Path]::GetFileName($Out)
$zeit = $jetzt.ToString('yyyy-MM-ddTHH:mm:ss')

$kopf = @"
ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('ViewDefinition [CoordinationView_V2.0]','$($hinweis -replace "'", "''")'),'2;1');
FILE_NAME('$dateiName','$zeit',('Dennis Fleischmann'),('FS Energieberater'),'HSETU IFC Export 1.1','Hottgenroth Energieberater 8.5','');
FILE_SCHEMA(('IFC4'));
ENDSEC;
DATA;
"@

$writer = New-Object System.IO.StreamWriter($Out, $false, (New-Object System.Text.UTF8Encoding($false)))
$writer.Write($kopf.Replace("`r`n", "`n")); $writer.Write("`n")
$writer.Write($sb.ToString().Replace("`r`n", "`n"))
$writer.Write("ENDSEC;`nEND-ISO-10303-21;`n")
$writer.Close()
$conn.Close()

$info = Get-Item $Out
Write-Host ''
Write-Host ("Fertig: {0}" -f $info.FullName)
Write-Host ("  {0} Bauteile, {1} Entitaeten, {2:N0} KB" -f $geschrieben, $script:nextId, ($info.Length / 1KB))
Write-Host ("  Geometrieflaeche geschrieben: {0:N2} m2" -f $script:flaecheGeschrieben)





