<#
    Export-Grundriss.ps1 - zeichnet einen Geschossgrundriss aus BmElement.GeoDesc
    als DXF, dazu eine PNG-Vorschau.

    Ein Grundriss ist ein waagerechter Schnitt: genommen wird alles, dessen
    Hoehenbereich die Schnitthoehe enthaelt. Mit -Ebenenhoehe sucht sich das
    Skript diese Hoehe selbst - noetig ueberall dort, wo die Waende eines
    Geschosses niedriger sind als der uebliche Meter ueber der Rohdecke.

    Gezeichnet wird wie in einem Bauplan und nicht wie eine Strichliste:

      * Fenster und Tueren unterbrechen die Wand, statt darauf zu liegen. Die
        Wandflaechen werden an der Laibung abgesetzt, dazwischen steht das
        Bauteilsymbol.
      * Tueren bekommen Blatt und Anschlagbogen.
      * Wandenden, an denen eine andere Wand ansetzt, bleiben offen - sonst
        kreuzen sich an jeder Ecke vier Linien.
      * Optional Schraffur der geschnittenen Wandflaechen.

    Was hier nicht entstehen kann: Raumstempel. BmRoom traegt keine Geometrie,
    also gibt es keine Koordinate, an die Name und Flaeche gehoerten.

    DXF ist R12-ASCII (LINE, ARC, TEXT). Aeltestes Format, dafuer von allem
    lesbar.
#>

param(
    [string] $ProjectGuid  = 'B31EDE65-5426-4BD6-9960-0D3A0D609347',
    [double] $Schnitthoehe = 1.20,
    # Rohdeckenhoehe der Ebene. Ist sie gesetzt, sucht sich das Skript die
    # Schnitthoehe selbst - siehe "Schnitthoehe finden" weiter unten. Ohne sie
    # gilt -Schnitthoehe unveraendert.
    [double] $Ebenenhoehe = -1e9,
    [string] $Name         = 'EG',
    [string] $Out          = 'grundriss.dxf',
    [string] $Bild         = '',
    [switch] $Schraffur,
    [ValidateSet('Rot','Schwarz','Blau','Gelb')]
    [string] $StempelFarbe = 'Rot',
    # Schrifthoehe im Modell, in Metern. Bei 1:100 sind 0,14 m rund 1,4 mm auf
    # dem Blatt - klein, aber lesbar.
    [double] $Schriftgroesse = 0.14,
    [string] $Schriftart = 'arial.ttf',
    [string] $Server       = '(localdb)\HSETU',
    [string] $Database     = 'HsetuPrjData'
)

$ErrorActionPreference = 'Stop'
$INV = [System.Globalization.CultureInfo]::InvariantCulture

# ------------------------------------------------------------------ Daten holen

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
SELECT e.UUID, e.ParentUUID, e.LongDesc, e.ElementType, e.AdjacentType,
       e.Thickness, e.NetArea, e.GeoDesc
FROM BmElement e
WHERE e.ProjectUUID=@p AND e.RepositoryType=1 AND e.ElementType IN (1,2,3,5,13)
"@
$null = $cmd.Parameters.AddWithValue('@p', [guid] $ProjectGuid)
$r = $cmd.ExecuteReader()

$roh = New-Object System.Collections.ArrayList
$daecher = New-Object System.Collections.ArrayList
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
            X = [double]::Parse($p.GetAttribute('Px'), $INV)
            Y = [double]::Parse($p.GetAttribute('Py'), $INV)
            Z = [double]::Parse($p.GetAttribute('Pz'), $INV)
        })
    }
    # Waende brauchen nur die Punktwolke (daraus wird die Achse), Dachflaechen
    # den Umlauf in seiner Reihenfolge - sonst laesst sich nicht sagen, welche
    # Kante die Schnittebene kreuzt.
    $punkte = New-Object System.Collections.ArrayList
    $schleifen = New-Object System.Collections.ArrayList
    foreach ($l in $x.SelectNodes('//geoLoopData')) {
        if (($l.GetAttribute('LongDesc') -replace '\s*\d+$','') -ne 'DIN18599_2011') { continue }
        $u = $l.GetAttribute('UUID'); if (-not $pk.ContainsKey($u)) { continue }
        $null = $schleifen.Add(@($pk[$u]))
        foreach ($p in $pk[$u]) { $null = $punkte.Add($p) }
    }
    if ($punkte.Count -lt 3) { continue }

    <#
        Dachflaechen.

        Im Dachgeschoss bildet nicht die Wand den Umriss, sondern die Schraege:
        die Linie, an der die Dachflaeche die Schnitthoehe kreuzt. Ohne sie
        stehen im Plan nur die Kniestoecke, und der Raum ist nach oben offen -
        genau das Bild, das ein Spitzboden bisher abgab.

        Die Flaeche wird deshalb nicht als Bauteil gezeichnet, sondern
        geschnitten. Was davon uebrig bleibt, ist eine Strecke je Umlauf.
    #>
    if ([int] $r['ElementType'] -eq 5) {
        $zsD = @($punkte | ForEach-Object { $_.Z })

        $null = $daecher.Add([pscustomobject]@{
            Id        = [string] $r['UUID']
            Name      = [string] $r['LongDesc']
            Schleifen = @($schleifen)
            ZMin      = ($zsD | Measure-Object -Minimum).Minimum
            ZMax      = ($zsD | Measure-Object -Maximum).Maximum
        })

        continue
    }

    # Die Hoehenspanne wird mitgefuehrt, nicht sofort gefiltert: welche Hoehe
    # geschnitten wird, steht erst fest, wenn alle Spannen bekannt sind.
    $zs = @($punkte | ForEach-Object { $_.Z })
    $zMin = ($zs | Measure-Object -Minimum).Minimum
    $zMax = ($zs | Measure-Object -Maximum).Maximum

    $bestD = 0.0; $a1 = $null; $a2 = $null
    for ($i = 0; $i -lt $punkte.Count; $i++) {
        for ($j = $i + 1; $j -lt $punkte.Count; $j++) {
            $dx = $punkte[$i].X - $punkte[$j].X; $dy = $punkte[$i].Y - $punkte[$j].Y
            $d = $dx*$dx + $dy*$dy
            if ($d -gt $bestD) { $bestD = $d; $a1 = $punkte[$i]; $a2 = $punkte[$j] }
        }
    }
    if ($bestD -lt 1e-6) { continue }

    [double] $dicke = $r['Thickness']
    if ($dicke -le 0.005 -or $dicke -le -1e8) { $dicke = 0.1 }

    $null = $roh.Add([pscustomobject]@{
        Id     = [string] $r['UUID']
        Eltern = [string] $r['ParentUUID']
        Name   = [string] $r['LongDesc']
        Typ    = [int] $r['ElementType']
        Angr   = [int] $r['AdjacentType']
        X1 = [double] $a1.X; Y1 = [double] $a1.Y
        X2 = [double] $a2.X; Y2 = [double] $a2.Y
        Dicke  = $dicke
        ZMin   = [double] $zMin
        ZMax   = [double] $zMax
    })
}
$r.Close()

<#
    Bauteile ihrer Ebene zuordnen.

    Die Hoehe allein genuegt nicht. Eine Giebelwand laeuft von 3,00 bis 6,05 m;
    im Dachplan bei 6,00 m wird sie geschnitten, gehoert aber zum Obergeschoss
    und begrenzt keinen Raum unterm Dach. Gezeichnet stand sie als freier Strich
    neben dem Grundriss - vier von zehn "Waenden" des Dachplans waren solche.

    Die Zuordnung steht in BmElementReference: jedes Bauteil haengt an den
    Raeumen, die es begrenzt, und der Raumname traegt die Ebene ("RF-R1").
    Ausgeschlossen wird nur, was nachweislich woanders hingehoert - ein Bauteil
    ohne jede Raumreferenz bleibt drin, sonst verschwaende ein freistehendes
    Mauerstueck ohne Not.
#>
$cmdE = $conn.CreateCommand()
$cmdE.CommandText = @"
SELECT DISTINCT CAST(br.ReferenceToUUID AS nvarchar(40)) AS BauteilId,
       LEFT(rm.ShortDesc, CHARINDEX('-', rm.ShortDesc + '-') - 1) AS Ebene
FROM BmRoom rm
JOIN BmElementReference br ON br.ReferenceFromUUID = rm.UUID
WHERE rm.ProjectUUID=@p
"@
$null = $cmdE.Parameters.AddWithValue('@p', [guid] $ProjectGuid)
$re = $cmdE.ExecuteReader()

$ebenenVonId = @{}
$alleEbenen = @{}
while ($re.Read()) {
    $bid = [string] $re['BauteilId']
    $eb  = [string] $re['Ebene']
    if ($eb -eq '') { continue }
    if (-not $ebenenVonId.ContainsKey($bid)) { $ebenenVonId[$bid] = New-Object System.Collections.ArrayList }
    if (-not $ebenenVonId[$bid].Contains($eb)) { $null = $ebenenVonId[$bid].Add($eb) }
    $alleEbenen[$eb] = $true
}
$re.Close()
$conn.Close()

if ($alleEbenen.ContainsKey($Name)) {
    function GehoertHierher($id) {
        if (-not $ebenenVonId.ContainsKey($id)) { return $true }   # keine Aussage
        return $ebenenVonId[$id].Contains($Name)
    }

    $vorher = $roh.Count
    $behalten = @($roh | Where-Object { $_.Typ -ne 1 -or (GehoertHierher $_.Id) })

    # Fenster und Tueren folgen ihrer Wand: faellt die weg, faellt auch das
    # Loch darin weg.
    $wandIds = @{}
    foreach ($e in $behalten) { if ($e.Typ -eq 1) { $wandIds[$e.Id] = $true } }
    $roh = @($behalten | Where-Object { $_.Typ -eq 1 -or $_.Eltern -eq '' -or $wandIds.ContainsKey($_.Eltern) })

    $daecher = @($daecher | Where-Object { GehoertHierher $_.Id })

    if ($vorher -ne $roh.Count) {
        Write-Host ("{0} Bauteile gehoeren zu anderen Ebenen und bleiben draussen." -f ($vorher - $roh.Count))
    }
}

<#
    Schnitthoehe finden.

    Ein fester Griff - "einen Meter ueber der Rohdecke" - trifft im Erd- und
    Kellergeschoss, versagt aber ueberall dort, wo die Waende niedriger sind als
    ein Meter. Im Dachgeschoss sind die Kniestoecke oft nur 40 cm hoch, im
    Spitzboden die Giebelwaende kaum mehr; der Schnitt liegt dann ueber dem
    halben Geschoss, und der Grundriss verliert genau die Waende, die seinen
    Umriss schliessen.

    Deshalb wird die Hoehe gesucht statt gesetzt: von knapp ueber der Rohdecke
    bis 1,60 m darueber wird gezaehlt, wie viele WAENDE eine Hoehe schneidet -
    Fenster und Tueren zaehlen nicht mit, sonst gewaenne ein hoher Schnitt allein
    durch Fensterbaender, waehrend die Wand darunter fehlt. Gewinnt mehr als eine
    Hoehe, entscheidet die Naehe zur ueblichen Schnitthoehe.

    Der Beginn knapp UEBER der Rohdecke ist wichtig: genau auf ihr enden die
    Waende des Geschosses darunter und beginnen die darueber - dort zaehlten
    beide mit, und der Grundriss zeigte zwei Geschosse uebereinander.
#>
if ($Ebenenhoehe -gt -1e8) {
    $wunsch = $Ebenenhoehe + 1.00
    $bestN = -1
    $bestH = $wunsch

    $bestD = -1

    for ($h = $Ebenenhoehe + 0.05; $h -le $Ebenenhoehe + 1.60; $h += 0.05) {
        $n = 0
        foreach ($e in $roh) {
            if ($e.Typ -eq 1 -and $h -ge $e.ZMin -and $h -le $e.ZMax) { $n++ }
        }

        # Dachflaechen entscheiden nur bei Gleichstand. Sie gleichrangig zu
        # zaehlen war ein Rueckschritt: im Dachgeschoss gewann dann eine Hoehe
        # mit vielen Schraegen, aber ohne die Kniestoecke - und die
        # Raumerkennung laeuft ueber Waende, nicht ueber Schraegen. Von neun
        # geschlossenen Raeumen blieben vier.
        $nd = 0
        foreach ($d in $daecher) {
            if ($h -ge $d.ZMin -and $h -le $d.ZMax) { $nd++ }
        }

        $naeher = [math]::Abs($h - $wunsch) -lt [math]::Abs($bestH - $wunsch)

        $besser = $n -gt $bestN `
            -or ($n -eq $bestN -and $nd -gt $bestD) `
            -or ($n -eq $bestN -and $nd -eq $bestD -and $naeher)

        if ($besser) { $bestN = $n; $bestD = $nd; $bestH = $h }
    }

    $gewaehlt = [math]::Round($bestH, 2)

    if ([math]::Abs($gewaehlt - $wunsch) -gt 0.001) {
        $beiWunsch = @($roh | Where-Object { $_.Typ -eq 1 -and $wunsch -ge $_.ZMin -and $wunsch -le $_.ZMax }).Count

        Write-Host ("Schnitt auf {0:F2} m gelegt statt {1:F2} m: dort schneiden {2} Waende statt {3}." -f
            $gewaehlt, $wunsch, $bestN, $beiWunsch)
    }

    $Schnitthoehe = $gewaehlt
}

$roh = @($roh | Where-Object { $Schnitthoehe -ge $_.ZMin -and $Schnitthoehe -le $_.ZMax })

<#
    Dachschraegen schneiden.

    Je Umlauf werden die Kanten gesucht, die die Ebene z = Schnitthoehe
    kreuzen, und der Kreuzungspunkt linear bestimmt. Bei einer ebenen Flaeche
    sind das genau zwei Punkte - eine Strecke. Faellt die Flaeche anders aus,
    werden die Treffer entlang ihrer Hauptrichtung sortiert und paarweise
    verbunden; so entstehen auch bei einem Umlauf mit Ausschnitt keine Linien
    quer durch die Oeffnung.
#>
$dachlinien = New-Object System.Collections.ArrayList

foreach ($d in $daecher) {
    if ($Schnitthoehe -lt $d.ZMin -or $Schnitthoehe -gt $d.ZMax) { continue }

    foreach ($schleife in $d.Schleifen) {
        $anzahl = $schleife.Count
        if ($anzahl -lt 3) { continue }

        $treffer = New-Object System.Collections.ArrayList
        # Kein zweistelliges for: PowerShell kennt kein "for ($i=0, $j=n-1; …)".
        $vor = $anzahl - 1

        for ($i = 0; $i -lt $anzahl; $i++) {
            $a = $schleife[$vor]
            $b = $schleife[$i]
            $vor = $i

            $za = $a.Z - $Schnitthoehe
            $zb = $b.Z - $Schnitthoehe

            if (($za -lt 0 -and $zb -lt 0) -or ($za -gt 0 -and $zb -gt 0)) { continue }
            if ([math]::Abs($zb - $za) -lt 1e-9) { continue }

            $t = -$za / ($zb - $za)
            if ($t -lt 0 -or $t -gt 1) { continue }

            $null = $treffer.Add([pscustomobject]@{
                X = $a.X + $t * ($b.X - $a.X)
                Y = $a.Y + $t * ($b.Y - $a.Y)
            })
        }

        if ($treffer.Count -lt 2) { continue }

        # Hauptrichtung aus der groessten Ausdehnung, danach sortieren.
        $spanX = ($treffer | Measure-Object -Property X -Maximum).Maximum - ($treffer | Measure-Object -Property X -Minimum).Minimum
        $spanY = ($treffer | Measure-Object -Property Y -Maximum).Maximum - ($treffer | Measure-Object -Property Y -Minimum).Minimum
        $sortiert = @(if ($spanX -ge $spanY) { $treffer | Sort-Object X, Y } else { $treffer | Sort-Object Y, X })

        for ($k = 0; $k + 1 -lt $sortiert.Count; $k += 2) {
            $p1 = $sortiert[$k]; $p2 = $sortiert[$k + 1]
            if ([math]::Abs($p1.X - $p2.X) -lt 1e-4 -and [math]::Abs($p1.Y - $p2.Y) -lt 1e-4) { continue }

            $null = $dachlinien.Add([pscustomobject]@{
                Name = $d.Name
                X1 = $p1.X; Y1 = $p1.Y; X2 = $p2.X; Y2 = $p2.Y
            })
        }
    }
}

<#
    Raumstempel.

    Die Raumumrisse stehen nirgends in der Datenbank - HottCAD rechnet sie zur
    Laufzeit aus den Waenden (FindeRoomContour im GraphicKernel). Was es gibt,
    ist die Zuordnung Raum -> begrenzende Bauteile in BmElementReference.

    Daraus laesst sich eine Stempellage ableiten: der mit der Wandlaenge
    gewichtete Schwerpunkt der Mittelpunkte aller begrenzenden Waende. Bei
    rechteckigen und L-foermigen Raeumen liegt der Punkt im Raum. Es ist eine
    Naeherung und nicht die Position, die HottCAD waehlt.
#>
$conn2 = New-Object System.Data.SqlClient.SqlConnection
$conn2.ConnectionString = $conn.ConnectionString
$conn2.Open()
$cmd2 = $conn2.CreateCommand()
$cmd2.CommandText = @"
SELECT rm.UUID AS RaumId, rm.ShortDesc, rm.LongDesc, rm.Area, rm.Volume,
       rm.LivingArea, rm.InsideTemperature, rm.HeatingType,
       CAST(br.ReferenceToUUID AS nvarchar(40)) AS BauteilId
FROM BmRoom rm
JOIN BmElementReference br ON br.ReferenceFromUUID = rm.UUID
WHERE rm.ProjectUUID=@p
"@
$null = $cmd2.Parameters.AddWithValue('@p', [guid] $ProjectGuid)
$rr = $cmd2.ExecuteReader()
$raeume = @{}
while ($rr.Read()) {
    $id = [string] $rr['RaumId']
    if (-not $raeume.ContainsKey($id)) {
        $raeume[$id] = [pscustomobject]@{
            Kurz  = [string] $rr['ShortDesc']
            Lang  = [string] $rr['LongDesc']
            Flaeche = [double] $rr['Area']
            Volumen = [double] $rr['Volume']
            WoFl  = [double] $rr['LivingArea']
            Temp  = [double] $rr['InsideTemperature']
            Heiz  = [int] $rr['HeatingType']
            Teile = New-Object System.Collections.ArrayList
        }
    }
    $null = $raeume[$id].Teile.Add([string] $rr['BauteilId'])
}
$rr.Close(); $conn2.Close()

$HEIZUNG = @{ 0 = ''; 1 = 'beheizt'; 2 = 'unbeheizt'; 3 = 'teilweise beheizt'; 4 = 'fremd beheizt' }

$waende  = @($roh | Where-Object { $_.Typ -eq 1 })
$kinder  = @($roh | Where-Object { $_.Typ -ne 1 })
Write-Host ("Schnitt bei {0:F2} m: {1} Waende, {2} Oeffnungsbauteile, {3} Dachschraegen" -f
    $Schnitthoehe, $waende.Count, $kinder.Count, $dachlinien.Count)
if ($waende.Count -eq 0 -and $kinder.Count -eq 0 -and $dachlinien.Count -eq 0) { Write-Host 'Nichts zu zeichnen.'; return }

# --------------------------------------------------------------- DXF-Geruest

function D([double] $v) { return [string]::Format($INV, '{0:0.####}', $v) }

$dxf = New-Object System.Text.StringBuilder
function Paar([int] $code, [string] $wert) { $null = $dxf.AppendLine($code.ToString()); $null = $dxf.AppendLine($wert) }

# $farbe ueberschreibt die Layerfarbe fuer dieses eine Objekt (DXF-Gruppe 62).
function Linie([string] $layer, [double] $x1, [double] $y1, [double] $x2, [double] $y2, $farbe = $null) {
    Paar 0 'LINE'; Paar 8 $layer
    if ($null -ne $farbe) { Paar 62 ([string] $farbe) }
    Paar 10 (D $x1); Paar 20 (D $y1); Paar 30 '0'
    Paar 11 (D $x2); Paar 21 (D $y2); Paar 31 '0'
}
function Bogen([string] $layer, [double] $cx, [double] $cy, [double] $rad, [double] $von, [double] $bis) {
    Paar 0 'ARC'; Paar 8 $layer
    Paar 10 (D $cx); Paar 20 (D $cy); Paar 30 '0'
    Paar 40 (D $rad); Paar 50 (D $von); Paar 51 (D $bis)
}
function Schrift([string] $layer, [double] $x, [double] $y, [double] $halb, [string] $txt, $farbe = $null) {
    Paar 0 'TEXT'; Paar 8 $layer
    if ($null -ne $farbe) { Paar 62 ([string] $farbe) }
    Paar 10 (D $x); Paar 20 (D $y); Paar 30 '0'; Paar 40 (D $halb); Paar 1 $txt
    # Ohne Stilverweis nimmt jeder Betrachter seine eigene Vorgabe - meist eine
    # Strichschrift. Mit STANDARD steht Arial in der Datei.
    Paar 7 'STANDARD'
}

$LAYER = [ordered]@{
    'AW-SCHNITT'   = 7    # Aussenwand, geschnitten
    'IW-SCHNITT'   = 8    # Innenwand, geschnitten
    'SCHRAFFUR'    = 9
    'FENSTER'      = 5
    'TUEREN'       = 3
    'OEFFNUNGEN'   = 6
    'DACHSCHRAEGE' = 8    # Linie, an der das Dach die Schnitthoehe kreuzt
    'BESCHRIFTUNG' = 2
    'SCHRIFTFELD'  = 7
    'RAUMSTEMPEL'  = 1
}

# DXF-Farbnummer und Vorschaufarbe des Raumstempels.
$STEMPEL = switch ($StempelFarbe) {
    'Rot'     { @{ Dxf = 1; R = 200; G =  30; B =  30 } }
    'Schwarz' { @{ Dxf = 7; R =  20; G =  20; B =  20 } }
    'Blau'    { @{ Dxf = 5; R =  20; G =  60; B = 190 } }
    'Gelb'    { @{ Dxf = 2; R = 170; G = 140; B =  20 } }
}
$LAYER['RAUMSTEMPEL'] = $STEMPEL.Dxf

# ------------------------------------------------------- Geometrie-Hilfsmittel

function Achse($w) {
    [double] $dx = $w.X2 - $w.X1
    [double] $dy = $w.Y2 - $w.Y1
    [double] $L = [math]::Sqrt($dx*$dx + $dy*$dy)
    return @{ EX = $dx/$L; EY = $dy/$L; NX = -($dy/$L); NY = $dx/$L; L = $L }
}

# Punkt auf die Wandachse projizieren: Ergebnis ist der Abstand ab X1/Y1.
function AufAchse($w, $a, [double] $px, [double] $py) {
    return ($px - $w.X1) * $a.EX + ($py - $w.Y1) * $a.EY
}

# Frei ist ein Wandende, an dem keine andere Wand ansetzt. Nur dort wird der
# Abschluss gezeichnet - sonst entstuenden an jeder Ecke doppelte Linien.
function EndeFrei($w, [double] $px, [double] $py) {
    foreach ($v in $waende) {
        if ($v.Id -eq $w.Id) { continue }
        foreach ($e in @(@($v.X1,$v.Y1), @($v.X2,$v.Y2))) {
            $dx = $e[0] - $px; $dy = $e[1] - $py
            if (($dx*$dx + $dy*$dy) -lt 0.36) { return $false }   # 60 cm
        }
    }
    return $true
}

# ------------------------------------------------------------------- Zeichnen

Paar 0 'SECTION'; Paar 2 'HEADER'
Paar 9 '$ACADVER'; Paar 1 'AC1009'
Paar 9 '$INSUNITS'; Paar 70 '6'
Paar 0 'ENDSEC'

Paar 0 'SECTION'; Paar 2 'TABLES'
Paar 0 'TABLE'; Paar 2 'LAYER'; Paar 70 ([string] $LAYER.Count)
foreach ($ln in $LAYER.Keys) { Paar 0 'LAYER'; Paar 2 $ln; Paar 70 '0'; Paar 62 ([string] $LAYER[$ln]); Paar 6 'CONTINUOUS' }
Paar 0 'ENDTAB'

# Textstil: ohne diesen Eintrag steht in den TEXT-Objekten ein Stilname, den
# die Datei nicht kennt, und der Betrachter faellt auf eine Strichschrift zurueck.
Paar 0 'TABLE'; Paar 2 'STYLE'; Paar 70 '1'
Paar 0 'STYLE'; Paar 2 'STANDARD'; Paar 70 '0'
Paar 40 '0.0'; Paar 41 '1.0'; Paar 50 '0.0'; Paar 71 '0'; Paar 42 (D $Schriftgroesse)
Paar 3 $Schriftart; Paar 4 ''
Paar 0 'ENDTAB'
Paar 0 'ENDSEC'

Paar 0 'SECTION'; Paar 2 'ENTITIES'

# Kinder ihrer Wand zuordnen.
$proWand = @{}
foreach ($k in $kinder) {
    if ($k.Eltern -eq '') { continue }
    if (-not $proWand.ContainsKey($k.Eltern)) { $proWand[$k.Eltern] = New-Object System.Collections.ArrayList }
    $null = $proWand[$k.Eltern].Add($k)
}

$zahlWand = 0; $zahlOeffnung = 0; $zahlLos = 0
$alleX = New-Object System.Collections.ArrayList
$alleY = New-Object System.Collections.ArrayList
function Merken([double] $x, [double] $y) { $null = $alleX.Add($x); $null = $alleY.Add($y) }

# Zuerst die Dachschraegen: sie liegen unter allem anderen, damit eine Wand,
# die auf der Schraege steht, die Linie ueberdeckt und nicht umgekehrt.
foreach ($dl in $dachlinien) {
    Linie 'DACHSCHRAEGE' $dl.X1 $dl.Y1 $dl.X2 $dl.Y2
    Merken $dl.X1 $dl.Y1
    Merken $dl.X2 $dl.Y2
}

foreach ($w in $waende) {
    $a = Achse $w
    [double] $halb = $w.Dicke / 2.0
    $lay = if ($w.Angr -eq 3 -or $w.Angr -eq 5) { 'AW-SCHNITT' } else { 'IW-SCHNITT' }

    # Oeffnungsintervalle entlang der Achse sammeln und zusammenfassen.
    $intervalle = New-Object System.Collections.ArrayList
    if ($proWand.ContainsKey($w.Id)) {
        foreach ($k in $proWand[$w.Id]) {
            $t1 = AufAchse $w $a $k.X1 $k.Y1
            $t2 = AufAchse $w $a $k.X2 $k.Y2
            $von = [math]::Max(0.0, [math]::Min($t1, $t2))
            $bis = [math]::Min($a.L, [math]::Max($t1, $t2))
            if (($bis - $von) -lt 0.05) { continue }
            $null = $intervalle.Add([pscustomobject]@{ Von = $von; Bis = $bis; Typ = $k.Typ; Name = $k.Name })
        }
    }
    $sortiert = @($intervalle | Sort-Object Von)

    # Wandflaechen abschnittsweise zeichnen, an den Laibungen abgesetzt.
    foreach ($s in @($halb, -$halb)) {
        [double] $pos = 0.0
        foreach ($iv in $sortiert) {
            if ($iv.Von -gt $pos + 0.01) {
                Linie $lay ($w.X1 + $a.EX*$pos + $a.NX*$s) ($w.Y1 + $a.EY*$pos + $a.NY*$s) `
                           ($w.X1 + $a.EX*$iv.Von + $a.NX*$s) ($w.Y1 + $a.EY*$iv.Von + $a.NY*$s)
            }
            if ($iv.Bis -gt $pos) { $pos = $iv.Bis }
        }
        if ($pos -lt $a.L - 0.01) {
            Linie $lay ($w.X1 + $a.EX*$pos + $a.NX*$s) ($w.Y1 + $a.EY*$pos + $a.NY*$s) `
                       ($w.X1 + $a.EX*$a.L + $a.NX*$s) ($w.Y1 + $a.EY*$a.L + $a.NY*$s)
        }
    }
    Merken ($w.X1 + $a.NX*$halb) ($w.Y1 + $a.NY*$halb)
    Merken ($w.X2 - $a.NX*$halb) ($w.Y2 - $a.NY*$halb)

    # Abschluesse nur an freien Enden.
    if (EndeFrei $w $w.X1 $w.Y1) {
        Linie $lay ($w.X1 + $a.NX*$halb) ($w.Y1 + $a.NY*$halb) ($w.X1 - $a.NX*$halb) ($w.Y1 - $a.NY*$halb)
    }
    if (EndeFrei $w $w.X2 $w.Y2) {
        Linie $lay ($w.X2 + $a.NX*$halb) ($w.Y2 + $a.NY*$halb) ($w.X2 - $a.NX*$halb) ($w.Y2 - $a.NY*$halb)
    }

    # Laibungen und Bauteilsymbole.
    foreach ($iv in $sortiert) {
        $olay = switch ($iv.Typ) { 3 { 'FENSTER' } 2 { 'TUEREN' } default { 'OEFFNUNGEN' } }
        foreach ($t in @($iv.Von, $iv.Bis)) {
            Linie $olay ($w.X1 + $a.EX*$t + $a.NX*$halb) ($w.Y1 + $a.EY*$t + $a.NY*$halb) `
                        ($w.X1 + $a.EX*$t - $a.NX*$halb) ($w.Y1 + $a.EY*$t - $a.NY*$halb)
        }
        $breite = $iv.Bis - $iv.Von

        if ($iv.Typ -eq 3) {
            # Fenster: zwei duenne Scheibenlinien in der Laibung.
            # Die Klammern sind Pflicht: in @($a/3, -$a/3) bindet das Komma
            # staerker als die Division, und PowerShell teilt durch ein Array.
            foreach ($s in @(($halb/3.0), (-$halb/3.0))) {
                Linie 'FENSTER' ($w.X1 + $a.EX*$iv.Von + $a.NX*$s) ($w.Y1 + $a.EY*$iv.Von + $a.NY*$s) `
                                ($w.X1 + $a.EX*$iv.Bis + $a.NX*$s) ($w.Y1 + $a.EY*$iv.Bis + $a.NY*$s)
            }
        }
        elseif ($iv.Typ -eq 2) {
            # Tuer: Blatt am Anschlag, dazu der Bogen ueber 90 Grad.
            $ax = $w.X1 + $a.EX*$iv.Von; $ay = $w.Y1 + $a.EY*$iv.Von
            Linie 'TUEREN' $ax $ay ($ax + $a.NX*$breite) ($ay + $a.NY*$breite)
            $startWinkel = [math]::Atan2($a.NY, $a.NX) * 180.0 / [math]::PI
            $endWinkel = [math]::Atan2($a.EY, $a.EX) * 180.0 / [math]::PI
            if ($endWinkel -lt $startWinkel) { $endWinkel += 360.0 }
            if (($endWinkel - $startWinkel) -gt 180.0) { $h1 = $startWinkel; $startWinkel = $endWinkel - 360.0; $endWinkel = $h1 }
            Bogen 'TUEREN' $ax $ay $breite $startWinkel $endWinkel
            Merken ($ax + $a.NX*$breite) ($ay + $a.NY*$breite)
        }
        $zahlOeffnung++
    }

    # Schraffur der geschnittenen Flaeche: 45-Grad-Striche im Wandkoerper.
    if ($Schraffur) {
        $abstand = 0.12
        for ([double] $t = 0.0; $t -lt $a.L; $t += $abstand) {
            $belegt = $false
            foreach ($iv in $sortiert) { if ($t -ge $iv.Von -and $t -le $iv.Bis) { $belegt = $true } }
            if ($belegt) { continue }
            Linie 'SCHRAFFUR' ($w.X1 + $a.EX*$t + $a.NX*$halb) ($w.Y1 + $a.EY*$t + $a.NY*$halb) `
                              ($w.X1 + $a.EX*([math]::Min($t + 2*$halb, $a.L)) - $a.NX*$halb) ($w.Y1 + $a.EY*([math]::Min($t + 2*$halb, $a.L)) - $a.NY*$halb)
        }
    }
    $zahlWand++
}

# Bauteile ohne Wand: als Rechteck, damit sie nicht verschwinden.
foreach ($k in $kinder) {
    if ($k.Eltern -ne '' -and $proWand.ContainsKey($k.Eltern)) { continue }
    $a = Achse $k
    [double] $halb = $k.Dicke / 2.0
    $olay = switch ($k.Typ) { 3 { 'FENSTER' } 2 { 'TUEREN' } default { 'OEFFNUNGEN' } }
    $ecken = @(
        @(($k.X1 + $a.NX*$halb), ($k.Y1 + $a.NY*$halb)),
        @(($k.X2 + $a.NX*$halb), ($k.Y2 + $a.NY*$halb)),
        @(($k.X2 - $a.NX*$halb), ($k.Y2 - $a.NY*$halb)),
        @(($k.X1 - $a.NX*$halb), ($k.Y1 - $a.NY*$halb)))
    for ($i = 0; $i -lt 4; $i++) {
        $p = $ecken[$i]; $q = $ecken[($i+1) % 4]
        Linie $olay $p[0] $p[1] $q[0] $q[1]
        Merken $p[0] $p[1]
    }
    $zahlLos++
}

# ------------------------------------------------------------- Raumstempel

<#
    Echte Raumsuche statt Schwerpunkt der Wandmitten.

    Aus den Wandachsen wird ein ebener Graph gebaut: Strecken an ihren
    Schnittpunkten teilen, Endpunkte innerhalb einer Toleranz zu gemeinsamen
    Knoten zusammenziehen. Anschliessend werden die kleinsten geschlossenen
    Umlaeufe gesucht - jeder davon ist ein Raum. Das ist dieselbe Rechnung, die
    HottCAD unter FindeRoomContour macht.

    Zugeordnet wird nicht ueber die Flaeche, sondern ueber die Bauteile: aus
    BmElementReference ist bekannt, welche Waende einen Raum begrenzen, und
    jeder Umlauf besteht aus Stuecken bestimmter Waende. Genommen wird der
    Umlauf mit der groessten Uebereinstimmung.
#>
$SNAP = 0.30

function Schluessel([double] $x, [double] $y) {
    # Klammern noetig: sonst bindet das Komma staerker als die Multiplikation.
    return ("{0:0.00}|{1:0.00}" -f ([math]::Round($x / $SNAP) * $SNAP), ([math]::Round($y / $SNAP) * $SNAP))
}

# 1. Wandachsen an allen Schnittpunkten teilen.
$teilStellen = @{}
for ($i = 0; $i -lt $waende.Count; $i++) { $teilStellen[$i] = New-Object System.Collections.ArrayList }
for ($i = 0; $i -lt $waende.Count; $i++) {
    $wi = $waende[$i]
    $r1x = $wi.X2 - $wi.X1; $r1y = $wi.Y2 - $wi.Y1
    for ($j = $i + 1; $j -lt $waende.Count; $j++) {
        $wj = $waende[$j]
        $r2x = $wj.X2 - $wj.X1; $r2y = $wj.Y2 - $wj.Y1
        $nenner = $r1x * $r2y - $r1y * $r2x
        if ([math]::Abs($nenner) -lt 1e-9) { continue }
        $t = (($wj.X1 - $wi.X1) * $r2y - ($wj.Y1 - $wi.Y1) * $r2x) / $nenner
        $u = (($wj.X1 - $wi.X1) * $r1y - ($wj.Y1 - $wi.Y1) * $r1x) / $nenner
        if ($t -lt -0.02 -or $t -gt 1.02 -or $u -lt -0.02 -or $u -gt 1.02) { continue }
        $null = $teilStellen[$i].Add([math]::Max(0.0, [math]::Min(1.0, $t)))
        $null = $teilStellen[$j].Add([math]::Max(0.0, [math]::Min(1.0, $u)))
    }
}

# 2. Knoten und Kanten aufbauen.
$knoten = @{}      # Schluessel -> @{ X; Y; Nachbarn = Liste }
function KnotenId([double] $x, [double] $y) {
    $k = Schluessel $x $y
    if (-not $knoten.ContainsKey($k)) { $knoten[$k] = [pscustomobject]@{ X = $x; Y = $y; Nachbarn = New-Object System.Collections.ArrayList } }
    return $k
}

$kanten = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $waende.Count; $i++) {
    $w = $waende[$i]
    $ts = @(0.0) + @($teilStellen[$i]) + @(1.0)
    $ts = @($ts | Sort-Object -Unique)
    for ($k = 0; $k -lt $ts.Count - 1; $k++) {
        $ta = $ts[$k]; $tb = $ts[$k+1]
        if (($tb - $ta) -lt 0.02) { continue }
        $ax = $w.X1 + ($w.X2 - $w.X1) * $ta; $ay = $w.Y1 + ($w.Y2 - $w.Y1) * $ta
        $bx = $w.X1 + ($w.X2 - $w.X1) * $tb; $by = $w.Y1 + ($w.Y2 - $w.Y1) * $tb
        $ka = KnotenId $ax $ay; $kb = KnotenId $bx $by
        if ($ka -eq $kb) { continue }
        $id = $kanten.Count
        $null = $kanten.Add([pscustomobject]@{ A = $ka; B = $kb; WandId = $w.Id })
        $null = $knoten[$ka].Nachbarn.Add(@($kb, $id))
        $null = $knoten[$kb].Nachbarn.Add(@($ka, $id))
    }
}

function Winkel([string] $von, [string] $nach) {
    return [math]::Atan2($knoten[$nach].Y - $knoten[$von].Y, $knoten[$nach].X - $knoten[$von].X)
}

# 3. Kleinste Umlaeufe suchen: an jedem Knoten die naechste Kante im Uhrzeigersinn.
$besucht = @{}
$flaechen = New-Object System.Collections.ArrayList
foreach ($startK in $knoten.Keys) {
    foreach ($nb in $knoten[$startK].Nachbarn) {
        $marke = "$startK>$($nb[0])"
        if ($besucht.ContainsKey($marke)) { continue }
        $weg = New-Object System.Collections.ArrayList
        $wandIds = @{}
        $akt = $startK; $naechst = $nb[0]; $ok = $true
        for ($schritt = 0; $schritt -lt 400; $schritt++) {
            $m = "$akt>$naechst"
            if ($besucht.ContainsKey($m)) { $ok = $false; break }
            $besucht[$m] = $true
            $null = $weg.Add($akt)
            foreach ($e in $knoten[$akt].Nachbarn) { if ($e[0] -eq $naechst) { $wandIds[$kanten[$e[1]].WandId] = $true } }
            $zurueck = Winkel $naechst $akt
            $beste = $null; $besterDelta = 9.9
            foreach ($e in $knoten[$naechst].Nachbarn) {
                if ($e[0] -eq $akt -and $knoten[$naechst].Nachbarn.Count -gt 1) { continue }
                $d = $zurueck - (Winkel $naechst $e[0])
                while ($d -le 0.0001) { $d += 2 * [math]::PI }
                while ($d -gt 2 * [math]::PI) { $d -= 2 * [math]::PI }
                if ($d -lt $besterDelta) { $besterDelta = $d; $beste = $e[0] }
            }
            if ($null -eq $beste) { $ok = $false; break }
            $akt = $naechst; $naechst = $beste
            if ($akt -eq $startK -and $naechst -eq $nb[0]) { break }
        }
        if (-not $ok -or $weg.Count -lt 3) { continue }
        $flaeche = 0.0
        for ($k = 0; $k -lt $weg.Count; $k++) {
            $p = $knoten[$weg[$k]]; $q = $knoten[$weg[($k+1) % $weg.Count]]
            $flaeche += $p.X * $q.Y - $q.X * $p.Y
        }
        $flaeche = $flaeche / 2.0
        if ($flaeche -lt 1.0 -or $flaeche -gt 400.0) { continue }   # Aussenumlauf ist negativ
        $null = $flaechen.Add([pscustomobject]@{ Weg = @($weg); Flaeche = $flaeche; Waende = @($wandIds.Keys) })
    }
}
Write-Host ("  {0} geschlossene Flaechen gefunden" -f $flaechen.Count)

function PunktInnen($poly, [double] $px, [double] $py) {
    # PowerShell kennt kein Komma im for-Kopf - der Vorgaengerindex wird
    # deshalb am Schleifenende mitgefuehrt.
    $drin = $false; $n = $poly.Count; $j = $n - 1
    for ($i = 0; $i -lt $n; $i++) {
        $a = $knoten[$poly[$i]]; $b = $knoten[$poly[$j]]
        if ((($a.Y -gt $py) -ne ($b.Y -gt $py)) -and
            ($px -lt ($b.X - $a.X) * ($py - $a.Y) / ($b.Y - $a.Y) + $a.X)) { $drin = -not $drin }
        $j = $i
    }
    return $drin
}

function StempelPunkt($poly) {
    $sx = 0.0; $sy = 0.0; $f = 0.0
    for ($i = 0; $i -lt $poly.Count; $i++) {
        $p = $knoten[$poly[$i]]; $q = $knoten[$poly[($i+1) % $poly.Count]]
        $kreuz = $p.X * $q.Y - $q.X * $p.Y
        $f += $kreuz; $sx += ($p.X + $q.X) * $kreuz; $sy += ($p.Y + $q.Y) * $kreuz
    }
    if ([math]::Abs($f) -lt 1e-9) { return $null }
    $cx = $sx / (3.0 * $f); $cy = $sy / (3.0 * $f)
    if (PunktInnen $poly $cx $cy) { return @($cx, $cy) }
    # Schwerpunkt liegt draussen: das Innere abrastern.
    $xs = @($poly | ForEach-Object { $knoten[$_].X }); $ys = @($poly | ForEach-Object { $knoten[$_].Y })
    $x0 = ($xs | Measure-Object -Minimum).Minimum; $x1 = ($xs | Measure-Object -Maximum).Maximum
    $y0 = ($ys | Measure-Object -Minimum).Minimum; $y1 = ($ys | Measure-Object -Maximum).Maximum
    for ($gy = $y0 + 0.2; $gy -lt $y1; $gy += 0.25) {
        for ($gx = $x0 + 0.2; $gx -lt $x1; $gx += 0.25) {
            if (PunktInnen $poly $gx $gy) { return @($gx, $gy) }
        }
    }
    return $null
}

$wandNachId = @{}
foreach ($w in $waende) { $wandNachId[$w.Id] = $w }

<#
    Nur die Raeume dieser Ebene stempeln.

    Ein Raum kommt in den Plan, weil eine seiner Waende geschnitten wird. Das
    genuegt als Kriterium nicht: Giebelwaende laufen ueber zwei Geschosse, im
    Dachplan wird also auch eine Wand des Obergeschosses geschnitten - und mit
    ihr stuenden die Raeume des Obergeschosses im Dachplan.

    Die Ebene steht im Raumnamen ("OG1-R4"), nach demselben Praefix, aus dem
    Export-Projekt.ps1 die Ebenenliste bildet. Gibt es zu diesem Namen keinen
    einzigen Raum, wird nicht gefiltert - dann ist das Skript von Hand
    aufgerufen worden und -Name ist nur eine Beschriftung.
#>
$eigene = @($raeume.Values | Where-Object { (([string] $_.Kurz) -split '-')[0] -eq $Name })
if ($eigene.Count -eq 0) { $eigene = @($raeume.Values) }

$zahlStempel = 0
$vergeben = @{}
foreach ($raum in $eigene) {
    $imSchnitt = @($raum.Teile | Where-Object { $wandNachId.ContainsKey($_) })
    if ($imSchnitt.Count -eq 0) { continue }

    # Umlauf mit der groessten Uebereinstimmung der begrenzenden Waende.
    $beste = $null; $besterWert = 0.0
    for ($fi = 0; $fi -lt $flaechen.Count; $fi++) {
        if ($vergeben.ContainsKey($fi)) { continue }
        $treffer = 0
        foreach ($wid in $flaechen[$fi].Waende) { if ($imSchnitt -contains $wid) { $treffer++ } }
        if ($treffer -eq 0) { continue }
        $wert = $treffer / [double] $flaechen[$fi].Waende.Count
        # Flaechenaehnlichkeit als Feinabstimmung.
        $abw = [math]::Abs($flaechen[$fi].Flaeche - $raum.Flaeche) / [math]::Max(1.0, $raum.Flaeche)
        $wert = $wert * 2.0 - $abw
        if ($wert -gt $besterWert) { $besterWert = $wert; $beste = $fi }
    }

    if ($null -ne $beste) {
        $pkt = StempelPunkt $flaechen[$beste].Weg
        if ($null -ne $pkt) { $vergeben[$beste] = $true; $mx = $pkt[0]; $my = $pkt[1] }
    }
    if ($null -eq $beste -or $null -eq $pkt) {
        # Rueckfall: gewichteter Schwerpunkt der begrenzenden Wandmitten.
        $sx = 0.0; $sy = 0.0; $gewicht = 0.0
        foreach ($tid in $imSchnitt) {
            $w = $wandNachId[$tid]; $a = Achse $w
            $sx += (($w.X1 + $w.X2) / 2.0) * $a.L; $sy += (($w.Y1 + $w.Y2) / 2.0) * $a.L; $gewicht += $a.L
        }
        if ($gewicht -lt 0.5) { continue }
        $mx = $sx / $gewicht; $my = $sy / $gewicht
    }

    # Sonderzeichen ueber ihren Codepunkt, nicht als Literal: PowerShell 5.1
    # liest diese Datei als ANSI, ein direktes "m²" kaeme verstuemmelt an.
    $hoch2 = [string][char]0xB2; $hoch3 = [string][char]0xB3; $grad = [string][char]0xB0

    $zeilen = @(
        ("{0}; {1}" -f $raum.Kurz, $raum.Lang),
        ("{0:N2} m{1}/{2:N2} m{3}" -f $raum.Flaeche, $hoch2, $raum.Volumen, $hoch3))
    if ($raum.WoFl -gt 0 -and $raum.WoFl -le 1e8) { $zeilen += ("WoFl: {0:N2} m{1}" -f $raum.WoFl, $hoch2) }
    if ($HEIZUNG.ContainsKey($raum.Heiz) -and $HEIZUNG[$raum.Heiz] -ne '') { $zeilen += $HEIZUNG[$raum.Heiz] }
    if ($raum.Temp -gt -100 -and $raum.Temp -le 1e8) { $zeilen += ("{0:N0} {1}C" -f $raum.Temp, $grad) }

    $th = $Schriftgroesse; $za = $Schriftgroesse * 1.45
    $hoeheGesamt = $zeilen.Count * $za
    $breiteGesamt = 0.0
    foreach ($zl in $zeilen) { $breiteGesamt = [math]::Max($breiteGesamt, $zl.Length * $th * 0.58) }

    # Unbeheizte Raeume heben sich hellblau ab - die Farbe steht am Objekt und
    # ueberschreibt die des Layers.
    $farbe = $null
    if ($raum.Heiz -eq 2) { $farbe = 141 }

    $x0 = $mx - $breiteGesamt/2.0 - 0.12
    $y0 = $my - $hoeheGesamt/2.0 - 0.10
    $x1 = $mx + $breiteGesamt/2.0 + 0.12
    $y1 = $my + $hoeheGesamt/2.0 + 0.10
    Linie 'RAUMSTEMPEL' $x0 $y0 $x1 $y0 $farbe
    Linie 'RAUMSTEMPEL' $x1 $y0 $x1 $y1 $farbe
    Linie 'RAUMSTEMPEL' $x1 $y1 $x0 $y1 $farbe
    Linie 'RAUMSTEMPEL' $x0 $y1 $x0 $y0 $farbe
    Merken $x0 $y0; Merken $x1 $y1

    for ($i = 0; $i -lt $zeilen.Count; $i++) {
        $zy = $y1 - 0.10 - ($i + 1) * $za + 0.06
        Schrift 'RAUMSTEMPEL' ($mx - ($zeilen[$i].Length * $th * 0.58) / 2.0) $zy $th $zeilen[$i] $farbe
    }
    $zahlStempel++
}

# --------------------------------------------------------- Schriftfeld, Norden

$minX = ($alleX | Measure-Object -Minimum).Minimum; $maxX = ($alleX | Measure-Object -Maximum).Maximum
$minY = ($alleY | Measure-Object -Minimum).Minimum; $maxY = ($alleY | Measure-Object -Maximum).Maximum

$fx = $maxX - 5.6; $fy = $minY - 3.2
Linie 'SCHRIFTFELD' $fx $fy ($fx+5.6) $fy
Linie 'SCHRIFTFELD' $fx ($fy+1.9) ($fx+5.6) ($fy+1.9)
Linie 'SCHRIFTFELD' $fx $fy $fx ($fy+1.9)
Linie 'SCHRIFTFELD' ($fx+5.6) $fy ($fx+5.6) ($fy+1.9)
Schrift 'SCHRIFTFELD' ($fx+0.15) ($fy+1.35) ($Schriftgroesse*1.8) ("Grundriss {0}" -f $Name)
Schrift 'SCHRIFTFELD' ($fx+0.15) ($fy+0.80) ($Schriftgroesse*1.2) ("Schnitt {0:F2} m   Massstab 1:100" -f $Schnitthoehe)
Schrift 'SCHRIFTFELD' ($fx+0.15) ($fy+0.30) ($Schriftgroesse*1.2) ("{0} Waende, {1} Oeffnungen" -f $zahlWand, $zahlOeffnung)

# Nordpfeil. Das Modellnetz steht 45 Grad gegen Norden: die Richtung, die im
# Netz nach Norden zeigt, hat den Azimut 315 Grad.
$nx0 = $minX - 1.8; $ny0 = $maxY - 1.6
$nw = 315.0 * [math]::PI / 180.0
$ndx = [math]::Sin($nw); $ndy = [math]::Cos($nw)
Linie 'BESCHRIFTUNG' $nx0 $ny0 ($nx0 + $ndx*1.2) ($ny0 + $ndy*1.2)
Linie 'BESCHRIFTUNG' ($nx0 + $ndx*1.2) ($ny0 + $ndy*1.2) ($nx0 + $ndx*0.85 - $ndy*0.22) ($ny0 + $ndy*0.85 + $ndx*0.22)
Linie 'BESCHRIFTUNG' ($nx0 + $ndx*1.2) ($ny0 + $ndy*1.2) ($nx0 + $ndx*0.85 + $ndy*0.22) ($ny0 + $ndy*0.85 - $ndx*0.22)
Schrift 'BESCHRIFTUNG' ($nx0 + $ndx*1.4) ($ny0 + $ndy*1.4) ($Schriftgroesse*2.0) 'N'

Paar 0 'ENDSEC'
Paar 0 'EOF'

[System.IO.File]::WriteAllText($Out, $dxf.ToString(), [System.Text.Encoding]::GetEncoding(1252))
$info = Get-Item $Out
Write-Host ("DXF: {0} ({1:N0} KB) - {2} Waende, {3} Oeffnungen, {4} Raumstempel" -f `
    $info.FullName, ($info.Length/1KB), $zahlWand, $zahlOeffnung, $zahlStempel)

# ------------------------------------------------------------- PNG-Vorschau

if ($Bild -ne '') {
    Add-Type -AssemblyName System.Drawing
    if (($maxX - $minX) -lt 0.5) { $maxX = $minX + 0.5 }
    if (($maxY - $minY) -lt 0.5) { $maxY = $minY + 0.5 }
    $rand = 70; $breite = 1800
    $skala = [math]::Min(($breite - 2*$rand) / ($maxX - $minX + 7.0), 400.0)
    $hoch = [int][math]::Min((($maxY - $minY + 5.0) * $skala + 2*$rand), 4000)

    $bmp = New-Object System.Drawing.Bitmap($breite, $hoch)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::White)

    # Dieselben Entitaeten noch einmal, diesmal auf die Leinwand.
    $stift = @{
        'AW-SCHNITT'   = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,10,10,10), 3.0))
        'IW-SCHNITT'   = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,70,70,70), 2.0))
        'SCHRAFFUR'    = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,180,180,180), 0.6))
        # Die Dachschraege ist keine geschnittene Wand, sondern eine Kante
        # darueber - im Bauplan duenn und gestrichelt, nicht ausgezogen.
        'DACHSCHRAEGE' = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,120,120,120), 1.2))
        'FENSTER'      = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,30,90,200), 1.4))
        'TUEREN'       = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,170,110,20), 1.4))
        'OEFFNUNGEN'   = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,200,40,40), 1.4))
        'BESCHRIFTUNG' = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,60,60,60), 1.2))
        'SCHRIFTFELD'  = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,30,30,30), 1.2))
        'RAUMSTEMPEL'  = (New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, $STEMPEL.R, $STEMPEL.G, $STEMPEL.B), 1.2))
    }
    $stift['DACHSCHRAEGE'].DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash

    # Sonderfarbe fuer unbeheizte Raeume (DXF-Farbe 141).
    $stiftHellblau = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 90, 160, 230), 1.2)
    function PX([double] $x) { return [float]($rand + ($x - $minX + 3.0) * $skala) }
    function PY([double] $y) { return [float]($hoch - $rand - ($y - $minY + 3.5) * $skala) }

    # DXF zurueckparsen - so zeigt die Vorschau garantiert das, was in der Datei steht.
    $zeilen = $dxf.ToString() -split "`r?`n"
    $i = 0
    while ($i -lt $zeilen.Count - 1) {
        if ($zeilen[$i].Trim() -eq '0' -and $zeilen[$i+1] -eq 'LINE') {
            $lay=''; $x1=0.0;$y1=0.0;$x2=0.0;$y2=0.0; $farbNr=0
            for ($k = $i+2; $k -lt $zeilen.Count-1; $k += 2) {
                if ($zeilen[$k].Trim() -eq "0") { break }   # naechstes Objekt
                switch ($zeilen[$k].Trim()) {
                    '8'  { $lay = $zeilen[$k+1] }
                    '62' { $farbNr = [int] $zeilen[$k+1] }
                    '10' { $x1 = [double]::Parse($zeilen[$k+1], $INV) }
                    '20' { $y1 = [double]::Parse($zeilen[$k+1], $INV) }
                    '11' { $x2 = [double]::Parse($zeilen[$k+1], $INV) }
                    '21' { $y2 = [double]::Parse($zeilen[$k+1], $INV) }
                }
            }
            if ($farbNr -eq 141) {
                $g.DrawLine($stiftHellblau, (PX $x1), (PY $y1), (PX $x2), (PY $y2))
            } elseif ($stift.ContainsKey($lay)) {
                $g.DrawLine($stift[$lay], (PX $x1), (PY $y1), (PX $x2), (PY $y2))
            }
        }
        elseif ($zeilen[$i].Trim() -eq '0' -and $zeilen[$i+1] -eq 'ARC') {
            $lay=''; $cx=0.0;$cy=0.0;$rad=0.0;$v=0.0;$b=0.0
            for ($k = $i+2; $k -lt $zeilen.Count-1; $k += 2) {
                if ($zeilen[$k].Trim() -eq "0") { break }
                switch ($zeilen[$k].Trim()) {
                    '8'  { $lay = $zeilen[$k+1] }
                    '10' { $cx = [double]::Parse($zeilen[$k+1], $INV) }
                    '20' { $cy = [double]::Parse($zeilen[$k+1], $INV) }
                    '40' { $rad = [double]::Parse($zeilen[$k+1], $INV) }
                    '50' { $v = [double]::Parse($zeilen[$k+1], $INV) }
                    '51' { $b = [double]::Parse($zeilen[$k+1], $INV) }
                }
            }
            if ($stift.ContainsKey($lay) -and $rad -gt 0) {
                $rp = [float]($rad * $skala)
                $g.DrawArc($stift[$lay], (PX ($cx-$rad)), (PY ($cy+$rad)), 2*$rp, 2*$rp, [float](-$b), [float]($b - $v))
            }
        }
        elseif ($zeilen[$i].Trim() -eq '0' -and $zeilen[$i+1] -eq 'TEXT') {
            $lay=''; $tx=0.0; $ty=0.0; $th=0.3; $txt=''; $farbNr=0
            for ($k = $i+2; $k -lt $zeilen.Count-1; $k += 2) {
                if ($zeilen[$k].Trim() -eq "0") { break }
                switch ($zeilen[$k].Trim()) {
                    '8'  { $lay = $zeilen[$k+1] }
                    '62' { $farbNr = [int] $zeilen[$k+1] }
                    '10' { $tx = [double]::Parse($zeilen[$k+1], $INV) }
                    '20' { $ty = [double]::Parse($zeilen[$k+1], $INV) }
                    '40' { $th = [double]::Parse($zeilen[$k+1], $INV) }
                    '1'  { $txt = $zeilen[$k+1] }
                }
            }
            if ($txt -ne '') {
                $gr = [float][math]::Max(7.0, $th * $skala * 0.75)
                $ft = New-Object System.Drawing.Font('Segoe UI', $gr, [System.Drawing.GraphicsUnit]::Pixel)
                $tf = if ($farbNr -eq 141) { [System.Drawing.Color]::FromArgb(255, 90, 160, 230) }
                      elseif ($lay -eq 'RAUMSTEMPEL') { [System.Drawing.Color]::FromArgb(255, $STEMPEL.R, $STEMPEL.G, $STEMPEL.B) }
                      else { [System.Drawing.Color]::FromArgb(255,20,20,20) }
                $br = New-Object System.Drawing.SolidBrush($tf)
                $g.DrawString($txt, $ft, $br, (PX $tx), ((PY $ty) - $gr))
                $ft.Dispose(); $br.Dispose()
            }
        }
        $i += 2
    }
    $f = New-Object System.Drawing.Font('Segoe UI', 13)
    $sb2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
    $g.DrawString(("Grundriss {0}  -  Schnitt {1:F2} m  -  {2} Waende, {3} Oeffnungen" -f $Name, $Schnitthoehe, $zahlWand, $zahlOeffnung), $f, $sb2, 16, 14)
    $f.Dispose(); $sb2.Dispose()
    foreach ($p in $stift.Values) { $p.Dispose() }; $stiftHellblau.Dispose()
    $g.Dispose()
    $bmp.Save($Bild, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("PNG: {0}" -f (Resolve-Path $Bild))
}
