# =============================================================================
# VORLAGE (erprobt am 14.10.2026 an 3QHTK_Lennart Krause) -- NICHT direkt
# ausfuehren. Je Projekt eine Kopie ins Scratchpad legen und anpassen:
#   1. $P / $Pn / $NameOriginal / $NameImport  (Projekt + Arbeitsname; der
#      Arbeitsname muss gegen ALLE Projektnamen eindeutig per LIKE sein)
#   2. Geschosse: Namen, Hoehenlagen, Deckenstaerken (Set-Geschoss-Aufrufe)
#   3. Ringe: -Ecke/-Breite/-Tiefe/-Wandstaerke je Geschoss
#   4. $fenster: die bestaetigte Fensterliste (N/B/H/Bruestung/Art je Element;
#      Pos = linke Kante ab Suedwest-Ursprung laengs der Wand; >=0,5 m Abstand
#      von Ecken, sonst verschneidet das Dach/die Ecke das Fenster)
#   5. Satteldach: -Grundriss/-Firsthoehe/-Hoehe1/-First/-Dicke
# Die Funktion "Waende" klassifiziert Richtungen ueber Schwellen des
# KRAUSE-Rings (Ursprung 0,0, 7,27 x 11,215) -- bei anderem Grundriss zuerst
# die Schwellen anpassen (BoundingBox statt Festwerte).
# Wiederanlauf-sicher: jeder Schritt prueft, was schon existiert.
# =============================================================================
# krause-import.ps1 -- kompletter Gebaeude-Import 3QHTK_Lennart Krause
# Ablauf: Bootstrap -> Geschosse OG1/DG -> drei Aussenringe -> 15 Fenster +
# Haustuer -> Satteldach 25 Grad -> Vorlagen loeschen -> Projekt zurueckbenennen.
# Jeder Schritt ist mit Wiederanlauf-Schutz versehen: zweimal laufen lassen
# legt nichts doppelt an. Protokoll: krause-import.log neben diesem Skript.
param([switch]$Probelauf)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

$skriptOrdner = Split-Path -Parent $MyInvocation.MyCommand.Path
Start-Transcript -Path (Join-Path $skriptOrdner 'krause-import.log') -Append | Out-Null

$tools = 'C:\Projekte_Dev\energieberatung\bauteile\tools'
$P  = 'ea94920b-8917-49d9-bcc4-fadc8d510712'   # PrProject 3QHTK_Lennart Krause
$Pn = '3QHTK-IMPORT'                            # eindeutiger Arbeitsname (Teiltext)
$NameOriginal = '3QHTK_Lennart Krause'
$NameImport   = '3QHTK-IMPORT_Lennart Krause'

# Software-Lage pruefen (wie die Werkzeuge selbst)
. "$tools\Test-SoftwareLaeuft.ps1"
Assert-SoftwareZu
Write-Host "Software ist zu - weiter." -ForegroundColor Green

$con = New-Object System.Data.SqlClient.SqlConnection "Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
function Sql([string]$sql) {
    $c = $con.CreateCommand(); $c.CommandText = $sql
    $t = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($t)
    return ,$t
}
function SqlWert([string]$sql) { $t = Sql $sql; if ($t.Rows.Count -gt 0) { return $t.Rows[0][0] } return $null }
function SqlTu([string]$sql) {
    if ($Probelauf) { Write-Host "  [Probelauf] $($sql.Substring(0, [Math]::Min(90, $sql.Length)))..."; return 0 }
    $c = $con.CreateCommand(); $c.CommandText = $sql; return $c.ExecuteNonQuery()
}

# ---- 1. Bootstrap (Gebaeude, EG, Vorlagen) -----------------------------------
$hatGebaeude = [int](SqlWert "SELECT COUNT(*) FROM BmBuilding WHERE ProjectUUID='$P'")
if ($hatGebaeude -eq 0) {
    Write-Host "`n=== 1. Bootstrap (Gebaeude + EG + Vorlagen) ===" -ForegroundColor Cyan
    if ($Probelauf) { & (Join-Path $skriptOrdner 'bootstrap-krause.ps1') -Probelauf }
    else            { & (Join-Path $skriptOrdner 'bootstrap-krause.ps1') }
} else { Write-Host "1. Bootstrap: Gebaeude existiert schon - uebersprungen." }

# Arbeitsname sicherstellen (Bootstrap benennt nur beim ersten Lauf um)
$nameJetzt = SqlWert "SELECT LongDesc FROM PrProject WHERE UUID='$P'"
if ($nameJetzt -eq $NameOriginal) {
    [void](SqlTu "UPDATE PrProject SET LongDesc='$NameImport' WHERE UUID='$P' AND LongDesc='$NameOriginal'")
    Write-Host "Projekt fuer den Import umbenannt: $NameImport"
}

if ($Probelauf) { Write-Host "`n[Probelauf] Ab hier braucht es die echten Zeilen - Ende."; $con.Close(); Stop-Transcript | Out-Null; exit 0 }

# ---- 2. Geschosse ------------------------------------------------------------
Write-Host "`n=== 2. Geschosse OG1 + DG ===" -ForegroundColor Cyan
$geschosse = Sql "SELECT LongDesc FROM BmFloor WHERE ProjectUUID='$P'"
$gNamen = @($geschosse.Rows | ForEach-Object { $_.LongDesc })
if ($gNamen -notcontains 'OG1') { & "$tools\New-Geschoss.ps1" -Projekt $Pn -Name 'OG1' -Typ OG -Bezug 'EG' }
else { Write-Host "OG1 existiert schon." }
$geschosse = Sql "SELECT LongDesc FROM BmFloor WHERE ProjectUUID='$P'"
$gNamen = @($geschosse.Rows | ForEach-Object { $_.LongDesc })
if ($gNamen -notcontains 'DG') { & "$tools\New-Geschoss.ps1" -Projekt $Pn -Name 'DG' -Typ DG -Bezug 'OG1' }
else { Write-Host "DG existiert schon." }

# Hoehenlagen festziehen (Plan: EG 0,25 / OG1 3,04 / DG 5,83; DG ohne Decke)
& "$tools\Set-Geschoss.ps1" -Projekt $Pn -Geschoss 'OG1' -Hoehenlage 3.04
& "$tools\Set-Geschoss.ps1" -Projekt $Pn -Geschoss 'DG'  -Hoehenlage 5.83 -Deckenstaerke 0
Sql "SELECT LongDesc, ElevationOfRefHeight, FloorHeight, CeilingThickness FROM BmFloor WHERE ProjectUUID='$P' ORDER BY SortNum" |
    ForEach-Object { $_.Rows | Format-Table -AutoSize | Out-String | Write-Host }

# ---- 3. Aussenringe ----------------------------------------------------------
Write-Host "`n=== 3. Aussenringe 7,27 x 11,215 (Wandstaerke 0,32) ===" -ForegroundColor Cyan
function FloorGid([string]$name) {
    $x = SqlWert "SELECT CAST(d.ClassValue AS nvarchar(max)) FROM BmFloor f JOIN BmData d ON d.ReferenceUUID=f.UUID AND d.LongDesc='CADXMLData' WHERE f.ProjectUUID='$P' AND f.LongDesc='$name'"
    if ($x -match '<floor GUID="([0-9a-fA-F-]{36})"') { return $Matches[1].ToLower() }
    throw "Floor-GUID fuer $name nicht gefunden."
}
foreach ($g in 'EG', 'OG1', 'DG') {
    $gid = FloorGid $g
    $n = [int](SqlWert "SELECT COUNT(*) FROM BmElement e JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' WHERE e.ProjectUUID='$P' AND e.ElementType=1 AND e.RepositoryType=3 AND e.ShortDesc<>'VORLAGE' AND CAST(d.ClassValue AS nvarchar(max)) LIKE '%floor=`"$gid`"%'")
    if ($n -ge 4) { Write-Host "$($g): Ring existiert schon ($n Waende)."; continue }
    & "$tools\New-Aussenring.ps1" -Projekt $Pn -Geschoss $g -Ecke '0,0' -Breite 7.27 -Tiefe 11.215 -Wandstaerke 0.32 -VorlageWand 'VORLAGE'
}

# ---- 4. Fenster und Haustuer -------------------------------------------------
Write-Host "`n=== 4. Fenster + Haustuer ===" -ForegroundColor Cyan
# Wandnamen je Geschoss und Himmelsrichtung aus der Zeichnung ableiten
function Waende([string]$g) {
    $gid = FloorGid $g
    $t = Sql "SELECT e.LongDesc, CAST(d.ClassValue AS nvarchar(max)) AS X FROM BmElement e JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' WHERE e.ProjectUUID='$P' AND e.ElementType=1 AND e.RepositoryType=3 AND e.ShortDesc<>'VORLAGE' AND CAST(d.ClassValue AS nvarchar(max)) LIKE '%floor=`"$gid`"%'"
    $map = @{}
    foreach ($r in $t.Rows) {
        if ($r.X -notmatch '<points count="\d+">\s*<p>([-0-9.,;]+?)</p>\s*<p>([-0-9.,;]+?)</p>') { continue }
        $p1 = $Matches[1] -split ';'; $p2 = $Matches[2] -split ';'
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $x1=[double]::Parse($p1[0],$inv); $y1=[double]::Parse($p1[1],$inv)
        $x2=[double]::Parse($p2[0],$inv); $y2=[double]::Parse($p2[1],$inv)
        $richtung = ''
        if ([Math]::Abs($y1) -lt 0.01 -and [Math]::Abs($y2) -lt 0.01)           { $richtung = 'S' }
        elseif ($y1 -gt 11.2 -and $y2 -gt 11.2)                                   { $richtung = 'N' }
        elseif ($x1 -gt 7.26 -and $x2 -gt 7.26)                                   { $richtung = 'O' }
        elseif ([Math]::Abs($x1) -lt 0.01 -and [Math]::Abs($x2) -lt 0.01)        { $richtung = 'W' }
        if ($richtung) { $map[$richtung] = @{ Name = $r.LongDesc; P1 = @($x1, $y1); P2 = @($x2, $y2) } }
    }
    return $map
}
# Abstand vom ERSTEN Wandpunkt: Lage des Fensters als Koordinate laengs der Wand
function Abstand($wand, [double]$posVonUrsprung, [double]$breite, [double]$laenge) {
    $p1 = $wand.P1; $p2 = $wand.P2
    # Laeuft die Wand in positiver Achsrichtung, ist der Abstand die Position selbst,
    # sonst von der anderen Ecke aus gemessen.
    $dx = $p2[0] - $p1[0]; $dy = $p2[1] - $p1[1]
    if (($dx + $dy) -gt 0) { return $posVonUrsprung }
    return $laenge - $posVonUrsprung - $breite
}
# Fensterliste (bestaetigte Masse; Position = linke Kante ab Suedwest-Ursprung)
$fenster = @(
    @{N='F 001';G='EG'; R='S'; Pos=1.00; B=1.80; H=2.20; Br=0.00; Art='Fenster'},  # Terrassentuer Wohnen
    @{N='F 002';G='EG'; R='S'; Pos=4.30; B=1.80; H=1.20; Br=0.90; Art='Fenster'},  # Fenster Wohnen Sued
    @{N='F 003';G='OG1';R='S'; Pos=1.00; B=1.80; H=2.20; Br=0.00; Art='Fenster'},  # Balkontuer Kind 1
    @{N='F 004';G='OG1';R='S'; Pos=4.30; B=1.80; H=2.20; Br=0.00; Art='Fenster'},  # Balkontuer Kind 2
    @{N='F 005';G='EG'; R='O'; Pos=0.80; B=2.00; H=0.90; Br=1.20; Art='Fenster'},  # Wohnen Ost
    @{N='F 006';G='EG'; R='O'; Pos=4.20; B=2.00; H=0.90; Br=1.20; Art='Fenster'},  # Kueche Ost
    @{N='F 007';G='EG'; R='O'; Pos=8.80; B=0.60; H=0.90; Br=1.35; Art='Fenster'},  # kleines Fenster Ost
    @{N='F 008';G='OG1';R='O'; Pos=1.00; B=1.80; H=1.20; Br=0.90; Art='Fenster'},
    @{N='F 009';G='OG1';R='O'; Pos=5.20; B=0.90; H=1.20; Br=0.90; Art='Fenster'},
    @{N='F 010';G='OG1';R='O'; Pos=8.20; B=1.80; H=1.20; Br=0.90; Art='Fenster'},
    @{N='F 011';G='DG'; R='O'; Pos=4.71; B=1.80; H=2.10; Br=0.50; Art='Fenster'},  # Giebelelement DG
    @{N='F 012';G='EG'; R='N'; Pos=1.00; B=0.75; H=1.00; Br=1.35; Art='Fenster'},
    @{N='AT 001';G='EG';R='N'; Pos=3.00; B=1.15; H=2.20; Br=0.00; Art='Tuer'},     # Haustuer
    @{N='F 013';G='EG'; R='N'; Pos=5.50; B=0.75; H=1.00; Br=1.35; Art='Fenster'},
    @{N='F 014';G='OG1';R='N'; Pos=1.00; B=1.80; H=1.20; Br=0.90; Art='Fenster'},
    @{N='F 015';G='OG1';R='N'; Pos=4.40; B=1.80; H=1.20; Br=0.90; Art='Fenster'}
)
$karten = @{}
foreach ($g in 'EG', 'OG1', 'DG') { $karten[$g] = Waende $g }
foreach ($f in $fenster) {
    $gibtEs = [int](SqlWert "SELECT COUNT(*) FROM BmElement WHERE ProjectUUID='$P' AND ShortDesc='$($f.N)' AND RepositoryType=3")
    if ($gibtEs -gt 0) { Write-Host "$($f.N) existiert schon."; continue }
    $wand = $karten[$f.G][$f.R]
    if (-not $wand) { throw "Keine $($f.R)-Wand im $($f.G) gefunden." }
    $laenge = 7.27; if ($f.R -eq 'O' -or $f.R -eq 'W') { $laenge = 11.215 }
    $a = Abstand $wand $f.Pos $f.B $laenge
    Write-Host ("{0}: {1} {2} an {3}, Abstand {4:N2}" -f $f.N, $f.G, $f.R, $wand.Name, $a)
    & "$tools\New-Fenster.ps1" -Projekt $Pn -Wand $wand.Name -Geschoss $f.G -Abstand $a `
        -Breite $f.B -Hoehe $f.H -Bruestung $f.Br -Art $f.Art -Name $f.N
}

# ---- 5. Satteldach -----------------------------------------------------------
Write-Host "`n=== 5. Satteldach 25 Grad (First Ost-West) ===" -ForegroundColor Cyan
$daecher = [int](SqlWert "SELECT COUNT(*) FROM BmElement WHERE ProjectUUID='$P' AND ElementType=5 AND RepositoryType=3 AND ShortDesc<>'VORLAGEDACH'")
if ($daecher -eq 0) {
    & "$tools\New-Satteldach.ps1" -Projekt $Pn -Geschoss 'DG' -Grundriss '0,0;7.27,0;7.27,11.215;0,11.215' `
        -Firsthoehe 2.62 -Hoehe1 0.68 -First 'OW' -Dicke 0.39
} else { Write-Host "Dach existiert schon ($daecher Flaechen)." }

# ---- 6. Vorlagen entfernen ---------------------------------------------------
Write-Host "`n=== 6. Vorlagen loeschen ===" -ForegroundColor Cyan
$vorlagen = Sql "SELECT UUID FROM BmElement WHERE ProjectUUID='$P' AND ShortDesc IN ('VORLAGE','VORLAGEDACH')"
foreach ($v in $vorlagen.Rows) {
    $u = $v.UUID
    foreach ($t in 'BmData') { [void](SqlTu "DELETE FROM BmData WHERE ReferenceUUID='$u'") }
    foreach ($t in 'BmElementWall','BmElementRoof','BmElementDimensioning','BmElementEnergyConsulting','BmElement') {
        [void](SqlTu "DELETE FROM $t WHERE UUID='$u'")
    }
    Write-Host "Vorlage entfernt."
}

# ---- 7. Zurueckbenennen und Ergebnis -----------------------------------------
Write-Host "`n=== 7. Ergebnis ===" -ForegroundColor Cyan
& "$tools\Show-Projekt.ps1" -Projekt $Pn
[void](SqlTu "UPDATE PrProject SET LongDesc='$NameOriginal' WHERE UUID='$P'")
Write-Host "`nProjekt zurueckbenannt auf '$NameOriginal'. Fertig." -ForegroundColor Green
$con.Close()
Stop-Transcript | Out-Null
