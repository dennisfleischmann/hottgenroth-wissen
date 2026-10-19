# Get-Wandsilhouette.ps1 -- den Umriss des Gebaeudes auf der Ebene einer Wand
#
# WOFUER
# Ein Nebengebaeude braucht als Umriss die Silhouette des eigenen Hauses auf der
# Trennwandebene. HottCAD rechnet die selbst, wenn man in der Oberflaeche
# zeichnet; von aussen muss sie hergeleitet werden. Das ist der Grund, warum
# Set-Nebengebaeude.ps1 ohne dieses Skript nur die halbe Miete war -- den
# schwierigen Teil haette jedes Mal ein Mensch von Hand rechnen muessen.
#
# WIE
# Die Silhouette ist die Vereinigung von zwei Sorten Flaechen, gesehen in der
# Ebene (t, z), wobei t die Laufkoordinate entlang der Wand ist:
#
#   je Geschoss   ein Rechteck [t0,t1] x [z_unten, z_oben]
#   je Dachflaeche ein schraeges Stueck, wo sie die Ebene beruehrt
#
# Beides wird aus den KANTEN gewonnen, die AUF der Ebene liegen -- keine
# Polygonverschneidung noetig, und damit auch bei L-Formen richtig, solange die
# Wand achsparallel ist.
#
# DIE HOEHEN, an Test0001 nachgerechnet
#   z_oben(g)   = ElevationOfRefHeight + FloorHeight
#   z_unten(g)  = ElevationOfRefHeight - CeilingThickness des Geschosses DARUNTER
#                 (beim untersten: seine eigene -- das ist die Bodenplatte)
# Beispiel EG: 0,25 + 2,75 = 3,00 oben; 0,25 - 0,25 (KG) = 0 unten.
#
# DAS DACHGESCHOSS ZAEHLT NICHT ALS RECHTECK, wenn Dachflaechen auf der Ebene
# liegen -- sonst entstuende ein Kasten bis zur rechnerischen Geschossoberkante
# statt eines Giebels. Gibt es keine, zaehlt es normal mit.
#
# GRENZEN
# Nur achsparallele Waende (x = fest oder y = fest). Schraege Waende brauchen
# eine Projektion auf die Wandrichtung; nicht gebaut, weil nicht gebraucht und
# damit auch nicht pruefbar.
#
# ERPROBUNGSSTAND
# Gegen die Silhouette geprueft, die HottCAD an Test0001 SELBST gezeichnet hat:
# dieselben sieben Punkte, Abweichung nur 5 mm an zwei z-Werten (HottCAD 5,755
# gegen gerechnet 5,75 -- Herkunft der 5 mm ungeklaert).

[CmdletBinding()]
param(
    # Namensteil (LongDesc) oder PrProject-UUID -- wie Set-Nebengebaeude.ps1,
    # das hierher durchreicht.
    [Parameter(Mandatory = $true)][string]$Projekt,
    # CAD-GUID der Wand aus der Zeichnung (Attribut GUID am <wall>).
    [Parameter(Mandatory = $true)][string]$Wand,
    # Erst ab diesem Geschoss aufwaerts. Leer = vom untersten an.
    [string]$AbGeschoss = '',
    [double]$Toleranz = 0.001,
    # Zwei Umrisspunkte gelten darunter als derselbe. Koordinaten aus zwei
    # verschiedenen Flaechen treffen sich nie exakt.
    [double]$Punktgleich = 0.0005,
    [switch]$Ausfuehrlich,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture
function Z([double]$w) { [Math]::Round($w, 4).ToString('0.####', $inv) }
function D([string]$s) { [double]::Parse($s, $inv) }

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    $c = $con.CreateCommand()
    # GUID zuerst, dann Namensteil -- Muster wie Setup-Wohngebaeude.ps1.
    $pg = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$pg)) {
        $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE UUID = @p"
        [void]$c.Parameters.AddWithValue("@p", $pg)
    }
    else {
        $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
        [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    }
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -ne 1) { throw "Projekt nicht eindeutig ($($tp.Count) Treffer)." }
    $prj = $tp[0]

    # --- Geschosse ----------------------------------------------------------
    $c = $con.CreateCommand()
    # WORAUF `wall floor="..."` ZEIGT -- und es ist NICHT BmFloor.UUID.
    # Ein Geschoss hat zwei Kennungen: die Zeilen-UUID in BmFloor und eine eigene
    # GUID in seiner Zeichnung (<floor GUID="...">, ueber ReferenceUUID am
    # Geschoss haengend). Die Bauteile verweisen auf die ZEICHNUNGS-GUID.
    # In Projekten, die unsere Skripte gebaut haben, sind beide gleich
    # (New-Geschoss.ps1 schreibt dieselbe UUID in beide) -- deshalb ist es an
    # Test0001 nie aufgefallen. In jedem von HottCAD selbst angelegten Projekt
    # sind sie verschieden: Werner Grotz, Gauting und alle anderen.
    $c.CommandText = @"
SELECT CAST(f.UUID AS varchar(40)), f.LongDesc, f.FloorType, f.ElevationOfRefHeight, f.FloorHeight, f.CeilingThickness,
       CASE WHEN CHARINDEX('<floor GUID="', CAST(d.ClassValue AS nvarchar(max))) > 0
            THEN LOWER(SUBSTRING(CAST(d.ClassValue AS nvarchar(max)),
                       CHARINDEX('<floor GUID="', CAST(d.ClassValue AS nvarchar(max))) + 13, 36))
            ELSE NULL END
FROM BmFloor f
LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.LongDesc = 'CADXMLData'
WHERE f.ProjectUUID=@p ORDER BY f.ElevationOfRefHeight
"@
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $ge = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $zeichnung = if ($l.IsDBNull(6)) { $null } else { $l.GetString(6) }
        $ge += [pscustomobject]@{ Id = $(if ($zeichnung) { $zeichnung } else { $l.GetString(0).ToLower() })
                                  Zeile = $l.GetString(0).ToLower(); Name = $l.GetString(1); Typ = [int]$l.GetValue(2)
                                  Bezug = [double]$l.GetValue(3); Gh = [double]$l.GetValue(4); Decke = [double]$l.GetValue(5) }
    }
    $l.Close()
    if (-not $ge.Count) { throw "Keine Geschosse gefunden." }
    # Die Unterkante des UNTERSTEN Geschosses ist die Bodenplatte, und deren
    # Staerke steht in building_data als LowestPlatformHeight -- nicht in der
    # CeilingThickness des Geschosses. An Test0001 sind beide 0,25 und damit
    # nicht zu unterscheiden; an Gauting 0,10 gegen 0,16, und HottCADs eigener
    # Umriss endet dort bei -2,465 = -2,365 - 0,10.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT TOP 1 CAST(ClassValue AS nvarchar(max)) FROM BmData " +
                     "WHERE ProjectUUID=@p AND CAST(ClassValue AS nvarchar(max)) LIKE '%building_data%'"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $bd = $c.ExecuteScalar()
    $platte = $null
    if ($bd) {
        $t2 = [regex]::Match([string]$bd, 'LowestPlatformHeight="([^"]*)"')
        if ($t2.Success) { $platte = D $t2.Groups[1].Value }
    }
    for ($i = 0; $i -lt $ge.Count; $i++) {
        $unten = if ($i -gt 0) { $ge[$i - 1].Decke } elseif ($null -ne $platte) { $platte } else { $ge[$i].Decke }
        $ge[$i] | Add-Member ZUnten ($ge[$i].Bezug - $unten)
        $ge[$i] | Add-Member ZOben  ($ge[$i].Bezug + $ge[$i].Gh)
    }

    # --- Zeichnungen: Waende und Daecher ------------------------------------
    $c = $con.CreateCommand()
    # NUR RepositoryType 3 -- die Zeichnung. Repo 1 ist das gerechnete Modell und
    # haelt dieselben Bauteile ein zweites Mal. Ohne diesen Filter mischen sich
    # beide Bestaende, und die obere Kante bekommt Zacken aus Flaechen, die im
    # Grundriss gar nicht so liegen. An Test0001 unsichtbar (dort gibt es kein
    # Repo 1), an Gauting sofort: 4 Dachflaechen in Repo 1 gegen 2 in Repo 3.
    $c.CommandText = "SELECT e.ElementType, CAST(d.ClassValue AS nvarchar(max)) FROM BmElement e " +
                     "JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' " +
                     "WHERE e.ProjectUUID=@p AND e.ElementType IN (1,5) AND e.RepositoryType=3"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $teile = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $x = $l.GetString(1)
        # NUR DER ERSTE <points>-BLOCK. Ein Bauteil traegt mehrere: eine Wand hat
        # neben dem Trapez noch <bottom_planes>, ein Dach neben dem Umriss das
        # Traufrechteck in <plane_definition> -- flach auf z = 0 und in x/y ganz
        # woanders. Wer alle <p> als EIN Polygon liest, erzeugt Kanten zwischen
        # Umriss und Markierung; die kreuzen die Wandebene und liefern Punkte,
        # die es nicht gibt. An Gauting standen die beiden Dachhaelften dadurch
        # versetzt und mit einer Luecke. An Test0001 unsichtbar, weil dort die
        # Giebelkante genau auf der Ebene lag und der andere Zweig griff.
        $ur = [regex]::Match($x, '<points[^>]*>(.*?)</points>', 'Singleline').Groups[1].Value
        $pkt = @()
        foreach ($m in [regex]::Matches($ur, '<p>([-0-9.eE+]+);([-0-9.eE+]+);([-0-9.eE+]+)</p>')) {
            $pkt += , @((D $m.Groups[1].Value), (D $m.Groups[2].Value), (D $m.Groups[3].Value))
        }
        $teile += [pscustomobject]@{
            Art      = [int]$l.GetValue(0)
            Guid     = ([regex]::Match($x, 'GUID="([^"]+)"')).Groups[1].Value.ToLower()
            Geschoss = ([regex]::Match($x, 'floor="([^"]+)"')).Groups[1].Value.ToLower()
            Aussen   = $x -match 'wall_type="OuterContour"'
            Xml      = $x
            P        = $pkt
        }
    }
    $l.Close()

    # --- Gehoert die Zeichnung ueberhaupt zu diesem Projekt? ----------------
    # Bei einer wortwoertlich kopierten Zeichnung nicht: die Kopie bekommt neue
    # BmFloor-UUIDs, die <wall floor="..."> zeigen aber weiter aufs Original.
    # Gemessen an "82131 Gauting, Am Einfang 10 07.02.2026_Fertig (1)" -- alle
    # 26 Aussenwaende verwiesen auf die Geschosse des Ausgangsprojekts. Ohne
    # diese Pruefung meldet das Skript "keine Wand auf der Ebene" und schickt
    # damit an die falsche Stelle.
    $bekannt = @{}; foreach ($x in $ge) { $bekannt[$x.Id] = $true }
    $verwiesen = @{}
    foreach ($t in $teile) { if ($t.Geschoss) { $verwiesen[$t.Geschoss] = $true } }
    $fremd = @($verwiesen.Keys | Where-Object { -not $bekannt.ContainsKey($_) })
    $eigen = @($verwiesen.Keys | Where-Object { $bekannt.ContainsKey($_) })
    if ($verwiesen.Count -and -not $eigen.Count) {
        throw ("Die Zeichnung gehoert nicht zu diesem Projekt: alle $($verwiesen.Count) verwiesenen " +
               "Geschoss-GUIDs sind hier unbekannt (z. B. $($fremd[0])), waehrend das Projekt " +
               "$($ge.Count) Geschosse fuehrt ($(($ge.Name) -join ', ')). Typisch fuer eine " +
               "wortwoertlich kopierte Zeichnung. Erst die floor-Verweise richtigstellen.")
    }
    if ($fremd.Count) {
        Write-Warning "$($fremd.Count) von $($verwiesen.Count) floor-Verweisen zeigen auf fremde Geschosse -- diese Bauteile fehlen in der Silhouette."
    }

    # --- Die Ebene aus der Bezugswand ---------------------------------------
    $bezug = @($teile | Where-Object { $_.Guid -eq $Wand.ToLower() })
    if ($bezug.Count -ne 1) { throw "Wand '$Wand' nicht eindeutig gefunden ($($bezug.Count) Treffer)." }
    $bw = $bezug[0]
    if ($bw.P.Count -lt 2) { throw "Bezugswand hat keine Aussenkante." }
    $p1 = $bw.P[0]; $p2 = $bw.P[1]
    if ([Math]::Abs($p1[0] - $p2[0]) -lt $Toleranz)      { $achse = 'x'; $ebene = $p1[0]; $ti = 1 }
    elseif ([Math]::Abs($p1[1] - $p2[1]) -lt $Toleranz)  { $achse = 'y'; $ebene = $p1[1]; $ti = 0 }
    else { throw "Wand ist nicht achsparallel (von $($p1[0]),$($p1[1]) nach $($p2[0]),$($p2[1])). Nicht unterstuetzt." }
    $ai = if ($achse -eq 'x') { 0 } else { 1 }

    Write-Verbose "Ebene $achse = $(Z $ebene), Laufkoordinate $(if($ti -eq 0){'x'}else{'y'})"

    # Ab welchem Geschoss?
    $abZ = [double]::NegativeInfinity
    if ($AbGeschoss) {
        $g0 = @($ge | Where-Object { $_.Name -like "*$AbGeschoss*" })
        if ($g0.Count -ne 1) { throw "Geschoss '$AbGeschoss' nicht eindeutig ($($g0.Count))." }
        $abZ = $g0[0].ZUnten
    }

    # --- Stuecke sammeln: waagerecht aus Geschossen, schraeg aus Daechern ----
    $stuecke = @()   # @{T0;Z0;T1;Z1}

    # Dachflaechen zuerst -- sie entscheiden, ob das oberste Geschoss zaehlt.
    $dachGeschosse = @{}
    # ZWEI FAELLE, und der zweite ist der haeufigere.
    # Liegt eine Dachkante genau AUF der Ebene (Giebelseite), nimm sie. Sonst
    # DURCHSTOESST die Ebene die Dachflaeche, und die Schnittfigur einer ebenen
    # Flaeche mit einer Ebene ist eine Strecke zwischen den aeussersten
    # Durchstosspunkten. Ohne diesen zweiten Fall fehlt das Dach still und die
    # Silhouette wird ein Kasten bis zur rechnerischen Geschossoberkante --
    # aufgefallen an Gauting, wo die Wand 25 cm innerhalb der Dachkante steht.
    foreach ($t in ($teile | Where-Object { $_.Art -eq 5 })) {
        $auf = @(); $kreuz = @()
        for ($k = 0; $k -lt $t.P.Count; $k++) {
            $a = $t.P[$k]; $b = $t.P[($k + 1) % $t.P.Count]
            $da = $a[$ai] - $ebene; $db = $b[$ai] - $ebene
            if ([Math]::Abs($da) -le $Toleranz -and [Math]::Abs($db) -le $Toleranz) {
                if ([Math]::Abs($a[$ti] - $b[$ti]) -gt $Toleranz) {
                    $auf += @{ T0 = $a[$ti]; Z0 = $a[2]; T1 = $b[$ti]; Z1 = $b[2] }
                }
                continue
            }
            if ($da * $db -ge 0) { continue }          # kein Durchstoss
            $f = $da / ($da - $db)
            $kreuz += [pscustomobject]@{ T = ($a[$ti] + $f * ($b[$ti] - $a[$ti])); Z = ($a[2] + $f * ($b[2] - $a[2])) }
        }
        if ($auf.Count) {
            foreach ($s in $auf) { $stuecke += $s }
            $dachGeschosse[$t.Geschoss] = $true
        }
        elseif ($kreuz.Count -ge 2) {
            $s = @($kreuz | Sort-Object T)
            $stuecke += @{ T0 = $s[0].T; Z0 = $s[0].Z; T1 = $s[-1].T; Z1 = $s[-1].Z }
            $dachGeschosse[$t.Geschoss] = $true
        }
    }

    foreach ($g in $ge) {
        if ($g.ZOben -le $abZ) { continue }
        if ($dachGeschosse.ContainsKey($g.Id)) { continue }    # Giebel statt Kasten
        $iv = @()
        foreach ($w in ($teile | Where-Object { $_.Art -eq 1 -and $_.Aussen -and $_.Geschoss -eq $g.Id })) {
            if ($w.P.Count -lt 2) { continue }
            $a = $w.P[0]; $b = $w.P[1]
            if ([Math]::Abs($a[$ai] - $ebene) -gt $Toleranz) { continue }
            if ([Math]::Abs($b[$ai] - $ebene) -gt $Toleranz) { continue }
            $iv += , @([Math]::Min($a[$ti], $b[$ti]), [Math]::Max($a[$ti], $b[$ti]))
        }
        foreach ($v in $iv) {
            $z0 = [Math]::Max($g.ZUnten, $abZ)
            $stuecke += @{ T0 = $v[0]; Z0 = $g.ZOben; T1 = $v[1]; Z1 = $g.ZOben; Boden = $z0 }
        }
        if ($Ausfuehrlich -and $iv.Count) {
            Write-Host ("  {0,-6} t {1} .. {2}   z {3} .. {4}" -f $g.Name, (Z $iv[0][0]), (Z $iv[0][1]), (Z $g.ZUnten), (Z $g.ZOben))
        }
    }
    if (-not $stuecke.Count) { throw "Keine Wand und keine Dachflaeche liegt auf der Ebene $achse = $(Z $ebene)." }
    if ($Ausfuehrlich) {
        Write-Host ""
        Write-Host "  Stuecke auf der Ebene:"
        foreach ($s in $stuecke) {
            Write-Host ("    t {0,9} -> {1,-9}  z {2,8} -> {3,-8} {4}" -f (Z $s.T0), (Z $s.T1), (Z $s.Z0), (Z $s.Z1),
                        $(if ($null -ne $s.Boden) { "(Geschoss, Boden $(Z $s.Boden))" } else { "(Dach)" }))
        }
    }

    # --- Obere Kante als Maximum aller Stuecke -------------------------------
    # DIE BREITE BESTIMMEN DIE WAENDE, NICHT DAS DACH. Ein Dachueberstand ragt
    # ueber die Flucht hinaus; das Nachbargebaeude tut das nicht. HottCAD haelt
    # sich an die Wandflucht -- an Gauting begann sein Umriss bei 4,6394 (Wand),
    # meiner bei 4,3894 (Dachkante). An Test0001 nicht zu unterscheiden, weil
    # das Dach dort genau auf der Wandflucht endet.
    $wandStuecke = @($stuecke | Where-Object { $null -ne $_.Boden })
    $quelle = if ($wandStuecke.Count) { $wandStuecke } else { $stuecke }
    $tMin = ($quelle | ForEach-Object { [Math]::Min($_.T0, $_.T1) } | Measure-Object -Minimum).Minimum
    $tMax = ($quelle | ForEach-Object { [Math]::Max($_.T0, $_.T1) } | Measure-Object -Maximum).Maximum
    $zMin = ($stuecke | ForEach-Object { if ($null -ne $_.Boden) { $_.Boden } else { [Math]::Min($_.Z0, $_.Z1) } } | Measure-Object -Minimum).Minimum
    if ($abZ -gt [double]::NegativeInfinity) { $zMin = [Math]::Max($zMin, $abZ) }

    function ZAn($s, [double]$t) {
        $lo = [Math]::Min($s.T0, $s.T1); $hi = [Math]::Max($s.T0, $s.T1)
        if ($t -lt $lo - 1e-9 -or $t -gt $hi + 1e-9) { return $null }
        if ([Math]::Abs($s.T1 - $s.T0) -lt 1e-9) { return [Math]::Max($s.Z0, $s.Z1) }
        return $s.Z0 + ($s.Z1 - $s.Z0) * (($t - $s.T0) / ($s.T1 - $s.T0))
    }

    # Stuetzstellen: Enden aller Stuecke plus Schnittpunkte je Paar.
    $stellen = New-Object System.Collections.Generic.List[double]
    foreach ($s in $stuecke) { $stellen.Add($s.T0); $stellen.Add($s.T1) }
    for ($i = 0; $i -lt $stuecke.Count; $i++) {
        for ($j = $i + 1; $j -lt $stuecke.Count; $j++) {
            $a = $stuecke[$i]; $b = $stuecke[$j]
            $ma = if ([Math]::Abs($a.T1 - $a.T0) -lt 1e-9) { 0 } else { ($a.Z1 - $a.Z0) / ($a.T1 - $a.T0) }
            $mb = if ([Math]::Abs($b.T1 - $b.T0) -lt 1e-9) { 0 } else { ($b.Z1 - $b.Z0) / ($b.T1 - $b.T0) }
            if ([Math]::Abs($ma - $mb) -lt 1e-12) { continue }
            $t = (($b.Z0 - $mb * $b.T0) - ($a.Z0 - $ma * $a.T0)) / ($ma - $mb)
            if ($t -gt $tMin -and $t -lt $tMax) { $stellen.Add($t) }
        }
    }
    $stellen.Add($tMin); $stellen.Add($tMax)
    $st = @($stellen | Sort-Object -Unique | Where-Object { $_ -ge $tMin - 1e-9 -and $_ -le $tMax + 1e-9 })

    $oben = @()
    for ($i = 0; $i -lt $st.Count - 1; $i++) {
        $mitte = ($st[$i] + $st[$i + 1]) / 2
        $best = $null; $bz = [double]::NegativeInfinity
        foreach ($s in $stuecke) { $v = ZAn $s $mitte; if ($null -ne $v -and $v -gt $bz) { $bz = $v; $best = $s } }
        if ($null -eq $best) { continue }
        $oben += , @($st[$i], (ZAn $best $st[$i]))
        $oben += , @($st[$i + 1], (ZAn $best $st[$i + 1]))
    }

    # Doppelte und kollineare Punkte zusammenfassen.
    $glatt = @()
    foreach ($p in $oben) {
        if ($glatt.Count -ge 1) {
            $l1 = $glatt[$glatt.Count - 1]
            if ([Math]::Abs($p[0] - $l1[0]) -lt $Punktgleich -and [Math]::Abs($p[1] - $l1[1]) -lt $Punktgleich) { continue }
        }
        if ($glatt.Count -ge 2) {
            $l1 = $glatt[$glatt.Count - 1]; $l2 = $glatt[$glatt.Count - 2]
            $kreuz = ($l1[0] - $l2[0]) * ($p[1] - $l2[1]) - ($l1[1] - $l2[1]) * ($p[0] - $l2[0])
            if ([Math]::Abs($kreuz) -lt 1e-9) { $glatt[$glatt.Count - 1] = $p; continue }
        }
        $glatt += , $p
    }

    # --- Umriss zusammensetzen: Unterkante hin, Oberkante zurueck ------------
    $roh = @()
    $roh += , @($tMin, $zMin)
    $roh += , @($tMax, $zMin)
    for ($i = $glatt.Count - 1; $i -ge 0; $i--) { $roh += , $glatt[$i] }

    $ergebnis = @()
    foreach ($p in $roh) {
        if ($ergebnis.Count) {
            $v = $ergebnis[$ergebnis.Count - 1]
            if ([Math]::Abs($p[0] - $v[0]) -lt $Punktgleich -and [Math]::Abs($p[1] - $v[1]) -lt $Punktgleich) { continue }
        }
        $ergebnis += , $p
    }

    $aus = @()
    foreach ($p in $ergebnis) {
        if ($achse -eq 'x') { $aus += "$(Z $ebene),$(Z $p[0]),$(Z $p[1])" }
        else                { $aus += "$(Z $p[0]),$(Z $ebene),$(Z $p[1])" }
    }
    if ($Ausfuehrlich) {
        Write-Host ""
        Write-Host "Ebene $achse = $(Z $ebene), $($ergebnis.Count) Punkte, t von $(Z $tMin) bis $(Z $tMax), z ab $(Z $zMin)"
        foreach ($a in $aus) { Write-Host "    $a" }
        Write-Host ""
    }
    return ($aus -join ';')
}
finally { $con.Close() }
