<#
    Test-Ifc.ps1 - liest die erzeugte Datei zurueck und prueft sie gegen die
    Datenbank. Kein Schemapruefer: das bleibt einem echten Validator vorbehalten.

    Die wichtigste Pruefung ist die letzte: aus den geschriebenen Polygonen wird
    die Flaeche neu berechnet und gegen die Bruttoflaeche der Software gehalten.
    Zaehlungen allein haetten die erste, unbrauchbare Fassung durchgewinkt.
#>

param(
    [string] $Ifc         = 'projekt.ifc',
    [string] $ProjectGuid = '79A52ACD-0032-4BCF-9DC2-4051CC08AD6C',
    [string] $Server      = '(localdb)\HSETU',
    [string] $Database    = 'HsetuPrjData'
)

$ErrorActionPreference = 'Stop'
$INV = [System.Globalization.CultureInfo]::InvariantCulture
$fehler = 0
function Pruefe([string] $name, [bool] $ok, [string] $detail) {
    $mark = if ($ok) { '  OK  ' } else { ' FEHL ' }
    if (-not $ok) { $script:fehler++ }
    Write-Host ("[{0}] {1,-32} {2}" -f $mark, $name, $detail)
}

$text = [System.IO.File]::ReadAllText($Ifc, [System.Text.Encoding]::UTF8)
$entitaeten = @{}
foreach ($z in ($text -split "`n")) {
    if ($z -match '^#(\d+)=([A-Z0-9_]+)\((.*)\);\s*$') {
        $entitaeten[[int] $matches[1]] = @{ Typ = $matches[2]; Args = $matches[3] }
    }
}

Write-Host ''
Write-Host "Datei:   $Ifc"
Write-Host ("Groesse: {0:N0} KB, {1} Entitaeten" -f ((Get-Item $Ifc).Length / 1KB), $entitaeten.Count)
Write-Host ''

Pruefe 'Kopf ISO-10303-21' ($text.StartsWith('ISO-10303-21;')) ''
Pruefe 'Abschluss'         ($text.TrimEnd().EndsWith('END-ISO-10303-21;')) ''
Pruefe 'Schema IFC4'       ($text -match "FILE_SCHEMA\(\('IFC4'\)\)") ''

$offen = New-Object System.Collections.Generic.HashSet[int]
foreach ($id in $entitaeten.Keys) {
    foreach ($m in [regex]::Matches($entitaeten[$id].Args, '#(\d+)')) {
        $ziel = [int] $m.Groups[1].Value
        if (-not $entitaeten.ContainsKey($ziel)) { $null = $offen.Add($ziel) }
    }
}
Pruefe 'Alle Verweise aufloesbar' ($offen.Count -eq 0) "$($entitaeten.Count) Zeilen"

$guids = New-Object System.Collections.Generic.List[string]
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Args -match "^'([^']{22})',#\d+") { $guids.Add($matches[1]) }
}
$eindeutig = ($guids | Select-Object -Unique).Count
Pruefe 'GlobalId eindeutig' ($eindeutig -eq $guids.Count) "$eindeutig von $($guids.Count)"
Pruefe 'GlobalId Zeichensatz' (@($guids | Where-Object { $_ -notmatch '^[0-9A-Za-z_$]{22}$' }).Count -eq 0) ''

function Zaehle([string] $typ) { return @($entitaeten.Values | Where-Object { $_.Typ -eq $typ }).Count }

Write-Host ''
Write-Host 'Bestand:'
foreach ($t in @('IFCPROJECT','IFCSITE','IFCBUILDING','IFCBUILDINGSTOREY','IFCSPACE',
                 'IFCWALL','IFCWINDOW','IFCDOOR','IFCSLAB','IFCROOF','IFCOPENINGELEMENT',
                 'IFCFACEBASEDSURFACEMODEL','IFCPOLYLOOP','IFCMATERIALLAYERSET')) {
    Write-Host ("    {0,-28} {1,6}" -f $t, (Zaehle $t))
}
Write-Host ''

# --------------------------------------------------- Raeumliche Einordnung

# Aussparungen zaehlen nicht als Bauteil: sie entstehen beim Schreiben, stehen
# in keiner Bauteilliste und haengen an ihrer Wand statt am Geschoss.
$bauteilTypen = @('IFCWALL','IFCWINDOW','IFCDOOR','IFCSLAB','IFCROOF','IFCBUILDINGELEMENTPROXY','IFCOPENINGELEMENT')
$ausgespart = New-Object System.Collections.Generic.HashSet[int]
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCRELVOIDSELEMENT') { continue }
    if ($entitaeten[$id].Args -match '(#\d+),(#\d+)$') { $null = $ausgespart.Add([int] $matches[2].TrimStart('#')) }
}
$soll = @($entitaeten.Keys | Where-Object { $bauteilTypen -contains $entitaeten[$_].Typ -and -not $ausgespart.Contains($_) })
$ist = @{}
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCRELCONTAINEDINSPATIALSTRUCTURE') { continue }
    if ($entitaeten[$id].Args -match '\(((?:#\d+,?)+)\),#\d+$') {
        foreach ($r in $matches[1] -split ',') { $ist[[int] $r.TrimStart('#')] = $true }
    }
}
$ohne = @($soll | Where-Object { -not $ist.ContainsKey($_) })
Pruefe 'Jedes Bauteil in einem Geschoss' ($ohne.Count -eq 0) "$($soll.Count) Bauteile"

# Jedes Bauteil braucht eine Darstellung - sonst ist es im Viewer unsichtbar.
$ohneForm = @($soll | Where-Object { $entitaeten[$_].Args -match ',\$,\$\)$|,\$,\$,' -and $entitaeten[$_].Args -notmatch '#\d+,#\d+,' })
$mitForm = @($soll | Where-Object { $entitaeten[$_].Typ -ne 'IFCOPENINGELEMENT' })
$fehlt = 0
foreach ($id in $mitForm) {
    # Attribut 7 (Representation) ist der zweite Verweis nach der Platzierung.
    $a = $entitaeten[$id].Args
    if ($a -match "^'[^']{22}',#\d+,[^,]*,[^,]*,\`$,#\d+,\`$") { $fehlt++ }
}
<#
    Splitter duerfen ohne Koerper dastehen.

    Mit -SplitterAb bleiben Bauteile, die schmaler sind als sie dick sind,
    bewusst ohne Darstellung - als Rippe gezeichnet richteten sie mehr Schaden
    an, als ihr Fehlen. Wieviele es sind, steht am Gebaeude; nur was darueber
    hinaus fehlt, ist ein Befund.
#>
$splitterZahl = 0
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCPROPERTYSINGLEVALUE') { continue }
    if ($entitaeten[$id].Args -match "^'Splitter_Anzahl',\`$,IFCINTEGER\((\d+)\)") { $splitterZahl += [int] $matches[1] }
}

$ohneGrund = $fehlt - $splitterZahl

Pruefe 'Jedes Bauteil hat Geometrie' ($ohneGrund -le 0) $(
    if ($ohneGrund -gt 0) { "$ohneGrund ohne Darstellung" }
    elseif ($splitterZahl -gt 0) { "$($mitForm.Count - $fehlt) mit Darstellung, $splitterZahl Splitter bewusst ohne" }
    else { "$($mitForm.Count) mit Darstellung" })

# ------------------------------------------- Flaeche aus der Geometrie

$punkte = @{}
$punkte2D = @{}
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCCARTESIANPOINT') { continue }
    $a = $entitaeten[$id].Args
    if ($a -match '^\(([-0-9.E+]+),([-0-9.E+]+),([-0-9.E+]+)\)$') {
        $punkte[$id] = @(
            [double]::Parse($matches[1].TrimEnd('.'), $INV),
            [double]::Parse($matches[2].TrimEnd('.'), $INV),
            [double]::Parse($matches[3].TrimEnd('.'), $INV))
    }
    elseif ($a -match '^\(([-0-9.E+]+),([-0-9.E+]+)\)$') {
        $punkte2D[$id] = @(
            [double]::Parse($matches[1].TrimEnd('.'), $INV),
            [double]::Parse($matches[2].TrimEnd('.'), $INV))
    }
}

# Koerpermodell: die Flaeche steckt im Profil der Extrusion. Der letzte Punkt
# wiederholt den ersten und wird beim Aufsummieren uebersprungen.
$profilFlaeche = 0.0
$profilAnzahl = 0

# Die Profile der Aussparungen wiederholen die Fensterflaechen und duerfen nicht
# mitgezaehlt werden - sonst steht jede Oeffnung zweimal in der Summe.
$oeffnungsLinien = New-Object System.Collections.Generic.HashSet[int]
foreach ($id in $ausgespart) {
    if (-not $entitaeten.ContainsKey($id)) { continue }
    foreach ($m in [regex]::Matches($entitaeten[$id].Args, '#(\d+)')) {
        $stack = New-Object System.Collections.Stack
        $stack.Push([int] $m.Groups[1].Value)
        $tiefe = 0
        while ($stack.Count -gt 0 -and $tiefe -lt 4000) {
            $tiefe++
            $k = $stack.Pop()
            if (-not $entitaeten.ContainsKey($k)) { continue }
            if ($entitaeten[$k].Typ -eq 'IFCPOLYLINE') { $null = $oeffnungsLinien.Add($k); continue }
            if ($entitaeten[$k].Typ -notmatch '^IFC(PRODUCTDEFINITIONSHAPE|SHAPEREPRESENTATION|EXTRUDEDAREASOLID|ARBITRARYCLOSEDPROFILEDEF)$') { continue }
            foreach ($m2 in [regex]::Matches($entitaeten[$k].Args, '#(\d+)')) { $stack.Push([int] $m2.Groups[1].Value) }
        }
    }
}

<#
    Schneidkoerper zaehlen nicht mit.

    Der zweite Operand eines IFCBOOLEANRESULT ist abgezogenes Material - er
    beschreibt, was NICHT da ist. Sein Profil in die Flaechensumme zu nehmen,
    zaehlte Wandflaechen ein zweites Mal; im Beispielprojekt kamen so 1.595 m2
    zuviel zusammen.
#>
$schnittLinien = New-Object System.Collections.Generic.HashSet[int]
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCBOOLEANRESULT') { continue }

    # Nur bei der Differenz ist der zweite Operand abgezogenes Material. Bei
    # einer Vereinigung gehoert er zum Koerper und muss mitgezaehlt werden.
    if ($entitaeten[$id].Args -notmatch '^\.DIFFERENCE\.') { continue }

    $teile = @([regex]::Matches($entitaeten[$id].Args, '#(\d+)') | ForEach-Object { [int] $_.Groups[1].Value })
    if ($teile.Count -lt 2) { continue }

    $stack = New-Object System.Collections.Stack
    $stack.Push($teile[1])
    $tiefe = 0
    while ($stack.Count -gt 0 -and $tiefe -lt 4000) {
        $tiefe++
        $k = $stack.Pop()
        if (-not $entitaeten.ContainsKey($k)) { continue }
        if ($entitaeten[$k].Typ -eq 'IFCPOLYLINE') { $null = $schnittLinien.Add($k); continue }
        if ($entitaeten[$k].Typ -notmatch '^IFC(EXTRUDEDAREASOLID|ARBITRARYCLOSEDPROFILEDEF|BOOLEANRESULT)$') { continue }
        foreach ($m2 in [regex]::Matches($entitaeten[$k].Args, '#(\d+)')) { $stack.Push([int] $m2.Groups[1].Value) }
    }
}

foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCPOLYLINE') { continue }
    if ($oeffnungsLinien.Contains($id)) { continue }
    if ($schnittLinien.Contains($id)) { continue }
    $ids = @([regex]::Matches($entitaeten[$id].Args, '#(\d+)') | ForEach-Object { [int] $_.Groups[1].Value })
    $ps = New-Object System.Collections.ArrayList
    foreach ($i in $ids) { if ($punkte2D.ContainsKey($i)) { $null = $ps.Add($punkte2D[$i]) } }
    if ($ps.Count -ge 2 -and $ps[0][0] -eq $ps[$ps.Count-1][0] -and $ps[0][1] -eq $ps[$ps.Count-1][1]) {
        $null = $ps.RemoveAt($ps.Count - 1)
    }
    if ($ps.Count -lt 3) { continue }
    $profilAnzahl++
    $summe = 0.0
    for ($i = 0; $i -lt $ps.Count; $i++) {
        $a2 = $ps[$i]; $b2 = $ps[($i + 1) % $ps.Count]
        $summe += $a2[0] * $b2[1] - $b2[0] * $a2[1]
    }
    $profilFlaeche += [math]::Abs($summe) / 2.0
}

$flaeche = 0.0
$schleifen = 0
$benutzt = New-Object System.Collections.ArrayList
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCPOLYLOOP') { continue }
    $ids = @([regex]::Matches($entitaeten[$id].Args, '#(\d+)') | ForEach-Object { [int] $_.Groups[1].Value })
    # Kein ForEach-Object mit Pipeline: die loest die Punkt-Tripel in einzelne
    # Zahlen auf, und der Flaecheninhalt kommt als Null heraus.
    $ps = New-Object System.Collections.ArrayList
    foreach ($i in $ids) { if ($punkte.ContainsKey($i)) { $null = $ps.Add($punkte[$i]); $null = $benutzt.Add($punkte[$i]) } }
    if ($ps.Count -lt 3) { continue }
    $schleifen++
    $ax = 0.0; $ay = 0.0; $az = 0.0
    for ($i = 0; $i -lt $ps.Count; $i++) {
        $a = $ps[$i]; $b = $ps[($i + 1) % $ps.Count]
        $ax += $a[1]*$b[2] - $b[1]*$a[2]
        $ay += $a[2]*$b[0] - $b[2]*$a[0]
        $az += $a[0]*$b[1] - $b[0]*$a[1]
    }
    $flaeche += [math]::Sqrt($ax*$ax + $ay*$ay + $az*$az) / 2.0
}

# Beim Koerpermodell sitzt die Lage im Ursprung der Extrusion und nicht in
# Polyloop-Punkten - diese UrsprÃ¼nge kommen daher hinzu.
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCEXTRUDEDAREASOLID') { continue }
    $refs = @([regex]::Matches($entitaeten[$id].Args, '#(\d+)') | ForEach-Object { [int] $_.Groups[1].Value })
    if ($refs.Count -lt 2) { continue }
    $lage = $refs[1]
    if (-not $entitaeten.ContainsKey($lage) -or $entitaeten[$lage].Typ -ne 'IFCAXIS2PLACEMENT3D') { continue }
    if ($entitaeten[$lage].Args -match '^#(\d+)') {
        $o = [int] $matches[1]
        if ($punkte.ContainsKey($o)) { $null = $benutzt.Add($punkte[$o]) }
    }
}

# Ausdehnung des Modells - ein Haus, kein Kilometer. Gemessen wird nur an
# Punkten, die zur Geometrie gehoeren; die Verschiebung des Grundstuecks steckt
# in einem Platzierungspunkt und wuerde die Spannweite sonst aufblaehen.
$xs = @($benutzt | ForEach-Object { $_[0] })
$ys = @($benutzt | ForEach-Object { $_[1] })
$spanX = ($xs | Measure-Object -Maximum).Maximum - ($xs | Measure-Object -Minimum).Minimum
$spanY = ($ys | Measure-Object -Maximum).Maximum - ($ys | Measure-Object -Minimum).Minimum

# ------------------------------------------------------- Abgleich mit der DB

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
$conn.Open()
function Skalar([string] $sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql
    $null = $cmd.Parameters.AddWithValue('@p', [guid] $ProjectGuid)
    return $cmd.ExecuteScalar()
}
$dbHuelle = [double] (Skalar @"
SELECT SUM(e.NetArea) FROM BmElement e
JOIN BmElementEnergyConsulting c ON c.UUID = e.UUID
WHERE e.ProjectUUID=@p AND e.RepositoryType=1 AND c.CladdingSurface=1
"@)
$dbBrutto = [double] (Skalar "SELECT SUM(GrossArea) FROM BmElement WHERE ProjectUUID=@p AND RepositoryType=1 AND GrossArea > -1e8")
$dbNetto  = [double] (Skalar "SELECT SUM(NetArea) FROM BmElement WHERE ProjectUUID=@p AND RepositoryType=1")
$dbAnzahl = [int]    (Skalar "SELECT COUNT(*) FROM BmElement WHERE ProjectUUID=@p AND RepositoryType=1")
$dbRaeume = [int]    (Skalar "SELECT COUNT(*) FROM BmRoom WHERE ProjectUUID=@p")

# Eine Datei aus -NurHuelle enthaelt nur die markierten Flaechen. Dann sind die
# Sollwerte des ganzen Projekts der falsche Massstab - verglichen wird gegen die
# Huelle. Erkannt an der Bauteilzahl.
$dbHuelleAnzahl = [int] (Skalar @"
SELECT COUNT(*) FROM BmElement e JOIN BmElementEnergyConsulting c ON c.UUID=e.UUID
WHERE e.ProjectUUID=@p AND e.RepositoryType=1 AND c.CladdingSurface=1
"@)
$nurHuelle = ($soll.Count -eq $dbHuelleAnzahl -and $dbHuelleAnzahl -ne $dbAnzahl)
if ($nurHuelle) {
    $dbAnzahl = $dbHuelleAnzahl
    $dbNetto  = $dbHuelle
    $dbBrutto = [double] (Skalar @"
SELECT SUM(e.GrossArea) FROM BmElement e JOIN BmElementEnergyConsulting c ON c.UUID=e.UUID
WHERE e.ProjectUUID=@p AND e.RepositoryType=1 AND c.CladdingSurface=1 AND e.GrossArea > -1e8
"@)
    Write-Host 'Datei enthaelt nur die Huellflaechen - geprueft wird gegen die Huelle.'
    Write-Host ''
}

$ifcNetto = 0.0
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCQUANTITYAREA') { continue }
    if ($entitaeten[$id].Args -match "^'(NetSideArea|NetArea|Area)',\`$,#\d+,([-0-9.E+]+)") {
        $ifcNetto += [double]::Parse($matches[2].TrimEnd('.'), $INV)
    }
}
$conn.Close()

# Die Huellflaeche A der Software: Summe der Bauteile, deren Merkmal
# 'Huellflaeche' wahr ist. Genau diese Zahl steht in der Oberflaeche.
$ifcHuelle = 0.0
$huellenIds = New-Object System.Collections.Generic.HashSet[int]
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCPROPERTYSET') { continue }
    if ($entitaeten[$id].Args -notmatch "'Pset_HSETU_Bauteil'") { continue }
    if ($entitaeten[$id].Args -notmatch '\(((?:#\d+,?)+)\)\s*$') { continue }
    $istHuelle = $false
    foreach ($r in $matches[1] -split ',') {
        $merkmalId = [int] $r.TrimStart('#')
        if ($entitaeten.ContainsKey($merkmalId) -and $entitaeten[$merkmalId].Args -match "^'Huellflaeche',\`$,IFCBOOLEAN\(\.T\.\)") { $istHuelle = $true }
    }
    if ($istHuelle) { $null = $huellenIds.Add($id) }
}
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCRELDEFINESBYPROPERTIES') { continue }
    if ($entitaeten[$id].Args -notmatch '\((#\d+)\),(#\d+)$') { continue }
    $ziel = [int] $matches[1].TrimStart('#'); $satz = [int] $matches[2].TrimStart('#')
    if (-not $huellenIds.Contains($satz)) { continue }
    # Mengensatz desselben Bauteils suchen und dessen Flaeche nehmen.
    foreach ($id2 in $entitaeten.Keys) {
        if ($entitaeten[$id2].Typ -ne 'IFCRELDEFINESBYPROPERTIES') { continue }
        if ($entitaeten[$id2].Args -notmatch "\(#$ziel\),(#\d+)`$") { continue }
        $q = [int] $matches[1].TrimStart('#')
        if (-not $entitaeten.ContainsKey($q) -or $entitaeten[$q].Typ -ne 'IFCELEMENTQUANTITY') { continue }
        foreach ($m in [regex]::Matches($entitaeten[$q].Args, '#(\d+)')) {
            $qi = [int] $m.Groups[1].Value
            if ($entitaeten.ContainsKey($qi) -and $entitaeten[$qi].Typ -eq 'IFCQUANTITYAREA' -and
                $entitaeten[$qi].Args -match "^'(NetSideArea|NetArea|Area)',\`$,#\d+,([-0-9.E+]+)") {
                $ifcHuelle += [double]::Parse($matches[2].TrimEnd('.'), $INV)
            }
        }
    }
}

<#
    Vereinigte Bauteile zurueckrechnen.

    Mit -DachVerschmelzen werden die Dachteilflaechen zu einem Koerper
    vereinigt; im IFC steht danach ein Bauteil, wo in der Datenbank vierzehn
    stehen. Der Traeger haelt das im Merkmal 'Verschmolzen_aus' fest, damit die
    Zahl nachvollziehbar bleibt statt einfach nicht zu stimmen.
#>
$verschmolzen = 0
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCPROPERTYSINGLEVALUE') { continue }
    if ($entitaeten[$id].Args -match "^'Verschmolzen_aus',\`$,IFCINTEGER\((\d+)\)") {
        $verschmolzen += ([int] $matches[1] - 1)
    }
}

<#
    Verschmolzene Teilflaechen zaehlen NICHT dazu.

    Sie bleiben als eigene Bauteile im Modell, nur ohne Darstellung - sie sind
    in $soll.Count also schon enthalten. 'Verschmolzen_aus' sagt lediglich, aus
    wievielen der gezeigte Koerper besteht; als Zuschlag gezaehlt kaeme man auf
    211 statt 198.
#>
$ifcAnzahl = $soll.Count

<#
    Splitter zurueckrechnen.

    Mit -SplitterAb werden Bauteile, die schmaler sind als sie dick sind, ohne
    Koerper ausgegeben - sie bleiben im Modell, nur ihre Geometrie fehlt. Wieviel
    Flaeche das war, steht am Gebaeude; ohne diesen Wert meldete die Pruefung
    eine Abweichung, die keine ist.
#>
$splitterFlaeche = 0.0
foreach ($id in $entitaeten.Keys) {
    if ($entitaeten[$id].Typ -ne 'IFCPROPERTYSINGLEVALUE') { continue }
    if ($entitaeten[$id].Args -match "^'Splitter_Flaeche',\`$,IFCAREAMEASURE\(([-0-9.E+]+)\)") {
        $splitterFlaeche += [double]::Parse($matches[1].TrimEnd('.'), $INV)
    }
}

Write-Host 'Abgleich gegen die Datenbank:'
Write-Host ("    Huellflaeche A  DB {0,8:N2}    IFC {1,8:N2}  m2" -f $dbHuelle, $ifcHuelle)
if ($verschmolzen -gt 0) {
    Write-Host ("    Bauteile        DB {0,8}    IFC {1,8}   (davon {2} im vereinigten Dach)" -f
        $dbAnzahl, $ifcAnzahl, ($verschmolzen + 1))
} else {
    Write-Host ("    Bauteile        DB {0,8}    IFC {1,8}" -f $dbAnzahl, $soll.Count)
}
Write-Host ("    Raeume          DB {0,8}    IFC {1,8}" -f $dbRaeume, (Zaehle 'IFCSPACE'))
Write-Host ("    Nettoflaeche    DB {0,8:N2}    IFC {1,8:N2}  m2" -f $dbNetto, $ifcNetto)
$geoFlaeche = $flaeche + $profilFlaeche + $splitterFlaeche
$geoTeile = $schleifen + $profilAnzahl
Write-Host ("    Geometrieflaeche DB {0,7:N2}    IFC {1,8:N2}  m2   ({2} Polygone)" -f $dbBrutto, $geoFlaeche, $geoTeile)
Write-Host ("    Ausdehnung                     {0,8:N1} x {1:N1} m" -f $spanX, $spanY)
Write-Host ''

Pruefe 'Bauteilzahl stimmt'  ($ifcAnzahl -eq $dbAnzahl) "$ifcAnzahl von $dbAnzahl"
Pruefe 'Raumzahl stimmt'     ((Zaehle 'IFCSPACE') -eq $dbRaeume) ''
Pruefe 'Nettoflaeche stimmt' ([math]::Abs($ifcNetto - $dbNetto) -lt 0.01) `
    ("Abweichung {0:N4} m2" -f [math]::Abs($ifcNetto - $dbNetto))
Pruefe 'Geometrie trifft Brutto' ([math]::Abs($geoFlaeche - $dbBrutto) -lt 0.5) `
    ("Abweichung {0:N4} m2" -f [math]::Abs($geoFlaeche - $dbBrutto))
Pruefe 'Ausdehnung plausibel' ($spanX -gt 3 -and $spanX -lt 200 -and $spanY -gt 3 -and $spanY -lt 200) `
    ("{0:N1} x {1:N1} m" -f $spanX, $spanY)
Pruefe 'Huellflaeche A stimmt' ([math]::Abs($ifcHuelle - $dbHuelle) -lt 0.01) `
    ("Abweichung {0:N4} m2" -f [math]::Abs($ifcHuelle - $dbHuelle))

Write-Host ''
if ($fehler -eq 0) {
    Write-Host 'Alle Pruefungen bestanden.' -ForegroundColor Green
    Write-Host 'Offen bleibt die Schemapruefung mit einem externen Validator.'
} else {
    Write-Host "$fehler Pruefung(en) fehlgeschlagen." -ForegroundColor Red
    exit 1
}

