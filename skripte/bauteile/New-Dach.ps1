# New-Dach.ps1 -- eine Dachflaeche anlegen
#
# EIN DACH TRAEGT ZWEI VERSCHIEDENE POLYGONE
# Diese Unterscheidung ist der Kern. Der erste Versuch mit diesem Skript ist
# daran gescheitert, dass ich sie uebersehen hatte -- HottCAD zeichnete die
# Steigung, aber keine Flaeche.
#
#   <roof><points>              DER DACHUMRISS, dreidimensional. Die eigentliche
#                               Dachflaeche. Jeder Punkt traegt sein z aus dem
#                               Abstand zur Traufe. Fehlt der Block oder steht er
#                               auf count="0", entsteht keine Flaeche.
#                               In 50 von 53 gezeichneten Daechern ist er belegt:
#                               18 mal mit 4 Punkten, 17 mal mit 6 (L-Form).
#
#   <plane_definition><points>  Das kleine Rechteck an der Traufe, zweidimensional
#                               auf z = 0. Es legt nur fest, WO die Ebene beginnt
#                               und in welche Richtung sie steigt.
#
# Die Rechenregel fuer z, nachgerechnet am Dach 001 von Jan Malte Strackerjan:
#
#   z = Geschosshoehe + Hoehe1 + tan(Neigung) * Abstand von der Traufkante
#
# Dort: Traufe bei y=12,6086 auf z=3,6 (Geschoss 3,1 + Hoehe1 0,5); der Punkt
# 2,068 m bergauf steht auf 3,6 + 2,068 * tan(50 Grad) = 6,064 -- exakt der
# Wert in der Datei.
#
# Der First steht nirgends. Wo sich zwei Ebenen schneiden, findet ihn HottCAD
# selbst -- <intersections> ist in ALLEN 53 Faellen leer, auch bei fertigen
# Satteldaechern. Ebenso sind <segments> und <side_types> Rechenergebnisse.
#
# Die Anstiegsrichtung wird nicht abgefragt, sondern aus der Lage der
# Aussenwaende bestimmt: senkrecht zur Traufe, zum Schwerpunkt des Grundrisses.
#
# ZEILEN
# Derselbe Fuenfersatz wie bei einer Wand, nur mit BmElementRoof statt
# BmElementWall und ElementType 5 statt 1. Von den dachspezifischen Feldern
# traegt nur RoofSlope einen Wert; RidgeHeight, RoofArea, H1/H2, S1/S2 und
# Overhang stehen auch bei einem von Hand gezeichneten Dach auf dem Sentinel
# -987654321,99 und werden von der Software gerechnet.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Geschoss,
    # Traufkante als "x1,y1,x2,y2" in Modellkoordinaten.
    [Parameter(Mandatory = $true)][string]$Traufe,
    [double]$Neigung = 45,
    [double]$Hoehe1 = 0,
    [double]$Dicke = 0.25,
    # Tiefe des Markierungsrechtecks. Nur ein Hinweis auf die Richtung, die
    # Dachflaeche wird davon nicht begrenzt.
    [double]$Tiefe = 2.0,
    # Dachumriss als "x1,y1;x2,y2;..." -- fuer L-Formen und alles, was kein
    # Rechteck ist. Leer = umschliessendes Rechteck der Aussenwaende.
    [string]$Umriss = '',
    [string]$Name = '',
    # Vorlagendatenbank, falls im Projekt selbst keine Dachflaeche mehr steht.
    [string]$VorlageDatenbank = '',
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture
$NZ = [char]13 + [char]10
function Z([double]$w) { $w.ToString('R', $inv) }

if (-not $OhneSoftwarepruefung -and -not $Probelauf) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

# Gelesen wird aus $ConV, geschrieben nach $Con. Beide koennen dieselbe
# Verbindung sein; getrennt sind sie, wenn die Vorlage aus einer eingespielten
# Sicherung kommt, weil im Projekt selbst nichts mehr steht.
function Kopiere {
    param($ConV, $Con, $Tx, [string]$Tabelle, [hashtable]$Schluessel, [hashtable]$Neu)
    $wo = (($Schluessel.Keys | ForEach-Object { "[$_] = @k_$_" }) -join ' AND ')
    $c = $ConV.CreateCommand()
    $c.CommandText = "SELECT * FROM [$Tabelle] WHERE $wo"
    foreach ($k in $Schluessel.Keys) { [void]$c.Parameters.AddWithValue("@k_$k", $Schluessel[$k]) }
    $tab = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)
    if ($tab.Rows.Count -ne 1) { throw "Vorlage in $Tabelle nicht eindeutig ($($tab.Rows.Count) Zeilen)." }
    $q = $tab.Rows[0]
    $spalten = @($tab.Columns | Where-Object { $_.ColumnName -ne 'SyncRowVersion' } | ForEach-Object { $_.ColumnName })
    foreach ($k in $Neu.Keys) { if ($spalten -notcontains $k) { throw "$Tabelle hat keine Spalte '$k'." } }
    if (-not $Tx) { return }
    $i = $Con.CreateCommand(); $i.Transaction = $Tx
    $i.CommandText = "INSERT INTO [$Tabelle] (" + (($spalten | ForEach-Object { "[$_]" }) -join ', ') +
                     ") VALUES (" + (($spalten | ForEach-Object { "@$_" }) -join ', ') + ")"
    foreach ($s in $spalten) {
        $wert = if ($Neu.ContainsKey($s)) { $Neu[$s] } else { $q[$s] }
        if ($null -eq $wert) { $wert = [DBNull]::Value }
        [void]$i.Parameters.AddWithValue("@$s", $wert)
    }
    if ($i.ExecuteNonQuery() -ne 1) { throw "INSERT in $Tabelle schlug fehl." }
}

$t = $Traufe -split ','
if ($t.Count -ne 4) { throw "Traufe muss die Form x1,y1,x2,y2 haben." }
$ax = [double]::Parse($t[0].Trim(), $inv); $ay = [double]::Parse($t[1].Trim(), $inv)
$bx = [double]::Parse($t[2].Trim(), $inv); $by = [double]::Parse($t[3].Trim(), $inv)
$lx = $bx - $ax; $ly = $by - $ay
$llen = [Math]::Sqrt($lx * $lx + $ly * $ly)
if ($llen -lt 0.1) { throw "Die Traufkante ist zu kurz." }

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$vdb = if ($VorlageDatenbank) { $VorlageDatenbank } else { $Datenbank }
$conV = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$vdb;Integrated Security=true;TrustServerCertificate=true"
$conV.Open()
$con.Open()
try {
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
    [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Count) Treffer." }
    $prj = $tp[0]

    $c = $con.CreateCommand()
    # Das floor-Attribut zeigt auf die GUID der GESCHOSSZEICHNUNG, nicht auf
    # BmFloor.UUID. Beide sind nur gleich, wenn New-Geschoss.ps1 das Geschoss
    # angelegt hat. In jedem importierten oder in HottCAD gebauten Projekt weichen
    # sie ab -- die Bauteile haengen dann an keinem Geschoss und sind in der
    # Software unsichtbar, waehrend in der Datenbank alles zu stimmen scheint.
    # Gemessen am 24.08.2026 an XWSKQ_Holger Hoffmann: EG und DG kamen aus einer
    # importierten Vorlage, 10 Bauteile blieben unsichtbar. Siehe den Kommentar
    # in Get-Wandsilhouette.ps1, der das seit Langem beschreibt.
    $c.CommandText = "SELECT CASE WHEN CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) > 0 THEN LOWER(SUBSTRING(CAST(d.ClassValue AS nvarchar(max)), CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) + 13, 36)) ELSE NULL END, f.LongDesc, f.ElevationOfRefHeight, CAST(f.UUID AS varchar(40)) " +
                     "FROM BmFloor f LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.LongDesc = 'CADXMLData' " +
                     "WHERE f.ProjectUUID=@p AND f.LongDesc LIKE @g"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    [void]$c.Parameters.AddWithValue("@g", "%$Geschoss%")
    $gf = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $gf += [pscustomobject]@{
        Id = $(if ($l.IsDBNull(0)) { $l.GetString(3).ToLower() } else { $l.GetString(0) })
        Name = $l.GetString(1); Bezug = [double]$l.GetValue(2) } }
    $l.Close()
    if ($gf.Count -ne 1) { throw "Geschoss nicht eindeutig: $($gf.Count) Treffer fuer '$Geschoss'." }
    $gf = $gf[0]

    # Vorlage: eine vorhandene Dachflaeche - notfalls aus der Vorlagendatenbank.
    $c = $conV.CreateCommand()
    $c.CommandText = "SELECT TOP 1 e.UUID, e.LongDesc, CAST(d.ClassValue AS nvarchar(max)) " +
                     "FROM BmElementRoof r JOIN BmElement e ON e.UUID=r.UUID " +
                     "JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' " +
                     "WHERE e.ProjectUUID=@p AND e.RepositoryType=3 ORDER BY e.LongDesc"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $l = $c.ExecuteReader()
    if (-not $l.Read()) { $l.Close(); throw "Keine Dachflaeche als Vorlage im Projekt." }
    $vlId = $l.GetGuid(0); $vlName = $l.GetString(1); $vlXml = $l.GetString(2)
    $l.Close()
    $uAttr = (([regex]::Matches($vlXml, '(u_value\w*)="([^"]*)"') |
               ForEach-Object { $_.Groups[1].Value + '="' + $_.Groups[2].Value + '"' }) -join ' ')

    # Alle Geschosse mit Hoehenlage -- fuer den Rueckfall weiter unten.
    $c = $con.CreateCommand()
    # Schluessel ist die Zeichnungs-GUID -- $proG wird aus dem floor-Attribut befuellt.
    $c.CommandText = "SELECT ISNULL(CASE WHEN CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) > 0 THEN LOWER(SUBSTRING(CAST(d.ClassValue AS nvarchar(max)), CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) + 13, 36)) ELSE NULL END, LOWER(CAST(f.UUID AS varchar(40)))), f.LongDesc, f.ElevationOfRefHeight " +
                     "FROM BmFloor f LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.LongDesc = 'CADXMLData' " +
                     "WHERE f.ProjectUUID=@p"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $alleG = @{}; $l = $c.ExecuteReader()
    while ($l.Read()) { $alleG[$l.GetString(0).ToLower()] = [pscustomobject]@{ Name = $l.GetString(1); Bezug = [double]$l.GetValue(2) } }
    $l.Close()

    # Anstiegsrichtung: zum Schwerpunkt der Aussenwaende.
    #
    # Ein Dachgeschoss hat oft gar keine Waende -- dann gibt es dort nichts zu
    # mitteln. In dem Fall wird das naechste Geschoss DARUNTER genommen, das
    # welche hat: der Umriss, den das Dach ueberdeckt, ist ohnehin der des
    # Baukoerpers, nicht der des leeren Dachraums.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT CAST(d.ClassValue AS nvarchar(max)) FROM BmElement e " +
                     "JOIN BmElementWall w ON w.UUID=e.UUID " +
                     "JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' WHERE e.ProjectUUID=@p"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $sx = 0.0; $sy = 0.0; $sn = 0
    $xmin = [double]::MaxValue; $xmax = [double]::MinValue
    $ymin = [double]::MaxValue; $ymax = [double]::MinValue
    # Erst je Geschoss sammeln, dann entscheiden.
    $proG = @{}
    $l = $c.ExecuteReader()
    while ($l.Read()) {
        $w = $l.GetString(0)
        if ($w -notmatch 'wall_type="OuterContour"') { continue }
        $fm = [regex]::Match($w, 'floor="([^"]+)"')
        if (-not $fm.Success) { continue }
        $fk = $fm.Groups[1].Value.ToLower()
        if (-not $proG.ContainsKey($fk)) { $proG[$fk] = New-Object System.Collections.ArrayList }
        foreach ($m in [regex]::Matches($w, '<p>([-\d.eE+]+);([-\d.eE+]+);')) {
            [void]$proG[$fk].Add(@([double]::Parse($m.Groups[1].Value, $inv), [double]::Parse($m.Groups[2].Value, $inv)))
        }
    }
    $l.Close()

    $quelle = $gf.Id.ToString().ToLower()
    $quelleName = $gf.Name
    if (-not $proG.ContainsKey($quelle)) {
        $kand = @($proG.Keys | Where-Object { $alleG.ContainsKey($_) -and $alleG[$_].Bezug -le $gf.Bezug } |
                  Sort-Object { -$alleG[$_].Bezug })
        if ($kand.Count -eq 0) { throw "Weder '$($gf.Name)' noch ein Geschoss darunter hat Aussenwaende -- Umriss nicht bestimmbar." }
        $quelle = $kand[0]; $quelleName = $alleG[$quelle].Name
        Write-Host "Hinweis : '$($gf.Name)' hat keine Aussenwaende, Umriss kommt aus '$quelleName'." -ForegroundColor Yellow
    }
    foreach ($p in $proG[$quelle]) {
        $sx += $p[0]; $sy += $p[1]; $sn++
        if ($p[0] -lt $xmin) { $xmin = $p[0] }; if ($p[0] -gt $xmax) { $xmax = $p[0] }
        if ($p[1] -lt $ymin) { $ymin = $p[1] }; if ($p[1] -gt $ymax) { $ymax = $p[1] }
    }
    $cx = $sx / $sn; $cy = $sy / $sn

    # Normale auf der Traufkante, Vorzeichen zum Schwerpunkt hin.
    $nx = -$ly / $llen; $ny = $lx / $llen
    $mx = ($ax + $bx) / 2; $my = ($ay + $by) / 2
    if ((($cx - $mx) * $nx + ($cy - $my) * $ny) -lt 0) { $nx = -$nx; $ny = -$ny }

    if (-not $Name) {
        $c = $con.CreateCommand()
        $c.CommandText = "SELECT LongDesc FROM BmElement WHERE ProjectUUID=@p AND LongDesc LIKE 'Dach %'"
        [void]$c.Parameters.AddWithValue("@p", $prj.Id)
        $max = 0; $l = $c.ExecuteReader()
        while ($l.Read()) {
            $n = 0
            if ([int]::TryParse(($l.GetString(0) -replace '^Dach\s*', ''), [ref]$n) -and $n -gt $max) { $max = $n }
        }
        $l.Close()
        $Name = "Dach {0:000}" -f ($max + 1)
    }

    $neuId = [guid]::NewGuid(); $cadId = [guid]::NewGuid(); $jetzt = Get-Date
    $bogen = $Neigung * [Math]::PI / 180
    # p1/p2 auf der Traufkante, p3/p4 um die Tiefe nach innen versetzt.
    # Erst einzeln, dann in EINER Kommaliste zusammensetzen. Ueber mehrere
    # Zeilen verteilt wuerde @( ... ) die vier Punkte zu acht Zahlen abflachen.
    $p1 = @($ax, $ay)
    $p2 = @($bx, $by)
    $p3 = @(($bx + $nx * $Tiefe), ($by + $ny * $Tiefe))
    $p4 = @(($ax + $nx * $Tiefe), ($ay + $ny * $Tiefe))
    $pkt = @($p1, $p2, $p3, $p4)
    $pZeilen = ($pkt | ForEach-Object { '          <p>' + (Z $_[0]) + ';' + (Z $_[1]) + ';0</p>' }) -join $NZ

    # DER DACHUMRISS -- das aeussere <points> direkt unter <roof>.
    #
    # Das ist NICHT dasselbe wie das Rechteck in <plane_definition>. Es ist die
    # Dachflaeche selbst, in DREI Dimensionen: dieselben Grundrisspunkte, jeder
    # mit dem z, das sich aus seinem Abstand zur Traufe ergibt. Fehlt dieser
    # Block, zeichnet HottCAD die Steigung, aber keine Flaeche -- an Test0001
    # gemessen, ein Pultdach mit count="0" blieb ohne Umriss.
    #
    # Nachgerechnet am Dach 001 von Jan Malte Strackerjan: Traufe bei y=12,6086
    # auf z=3,6 (Geschoss 3,1 + Hoehe1 0,5); der Punkt 2,068 m bergauf steht auf
    # 3,6 + 2,068 * tan(50 Grad) = 6,064 -- genau der Wert in der Datei.
    if ($Umriss) {
        $uPkt = @($Umriss -split ';' | ForEach-Object {
            $q = $_ -split ','
            if ($q.Count -ne 2) { throw "Umriss-Punkt '$_' muss die Form x,y haben." }
            , @([double]::Parse($q[0].Trim(), $inv), [double]::Parse($q[1].Trim(), $inv))
        })
        if ($uPkt.Count -lt 3) { throw "Der Umriss braucht mindestens drei Punkte." }
    } else {
        # Umschliessendes Rechteck der Aussenwaende. Traegt bei rechteckigem
        # Grundriss; alles andere gehoert ueber -Umriss angegeben.
        $e1 = @($xmin, $ymin); $e2 = @($xmax, $ymin); $e3 = @($xmax, $ymax); $e4 = @($xmin, $ymax)
        $uPkt = @($e1, $e2, $e3, $e4)
    }
    $tang = [Math]::Tan($bogen)
    $uZeilen = ($uPkt | ForEach-Object {
        # Abstand von der Traufkante in Anstiegsrichtung.
        $dist = ($_[0] - $ax) * $nx + ($_[1] - $ay) * $ny
        $zz = $gf.Bezug + $Hoehe1 + $tang * $dist
        '        <p>' + (Z $_[0]) + ';' + (Z $_[1]) + ';' + (Z $zz) + '</p>'
    }) -join $NZ

    $xml = @(
        '<?xml version="1.0"?>', '<geometry>', '  <Roof count="1">'
        ('    <roof name="' + $Name + '" GUID="' + $cadId + '" floor="' + $gf.Id + '" ' + $uAttr +
         ' type="Polygonal" thickness="' + (Z $Dicke) + '" partitial="False"' +
         ' gable_mode="OrthogonalToPlane" gable_mode2="OrthogonalToPlane">')
        '      <points count="' + $uPkt.Count + '">', $uZeilen, '      </points>'
        '      <repositories count="1">', '        <val>' + $neuId + '</val>', '      </repositories>'
        '      <intersections count="0" />'
        '      <plane_definition type="Height1AndSlope" visible="True">'
        '        <values count="2">', '          <val>' + (Z $Hoehe1) + '</val>', '          <val>' + (Z $bogen) + '</val>', '        </values>'
        '        <points count="4">', $pZeilen, '        </points>'
        '      </plane_definition>'
        '    </roof>', '  </Roof>', '</geometry>'
    ) -join $NZ

    Write-Host "Projekt : $($prj.Name)"
    Write-Host "Vorlage : $vlName"
    Write-Host "Geschoss: $($gf.Name) (Bezug $(Z $gf.Bezug) m)"
    Write-Host "Neu     : $Name   Neigung $(Z $Neigung) Grad = $(Z ([Math]::Round($bogen,12))) rad   Hoehe1 $(Z $Hoehe1)   Dicke $(Z $Dicke)"
    Write-Host "Traufe  : $(Z $ax);$(Z $ay) -> $(Z $bx);$(Z $by)   Laenge $(Z ([Math]::Round($llen,3))) m"
    Write-Host "Anstieg : nach $(Z ([Math]::Round($nx,3))) / $(Z ([Math]::Round($ny,3)))  (Schwerpunkt $(Z ([Math]::Round($cx,2))) / $(Z ([Math]::Round($cy,2))))"
    Write-Host ""
    Write-Host "  Traufrechteck (plane_definition, flach auf z=0):"
    $pkt | ForEach-Object { Write-Host ("      {0};{1};0" -f (Z $_[0]), (Z $_[1])) }
    Write-Host "  Dachumriss ($($uPkt.Count) Punkte, dreidimensional):"
    for ($k = 0; $k -lt $uPkt.Count; $k++) {
        $dd = ($uPkt[$k][0] - $ax) * $nx + ($uPkt[$k][1] - $ay) * $ny
        Write-Host ("      {0,-20} {1,-20} z={2,-9}  ({3,5:N2} m ab Traufe)" -f (Z $uPkt[$k][0]), (Z $uPkt[$k][1]),
                    (Z ([Math]::Round($gf.Bezug + $Hoehe1 + $tang * $dd, 4))), $dd)
    }
    Write-Host ""

    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        $gem = @{ UUID = $neuId; GId = $neuId; LongDesc = $Name; ShortDesc = $Name; StampCreate = $jetzt; StampEdit = $jetzt }
        $elem = $gem.Clone(); $elem['Slope'] = $Neigung; $elem['Thickness'] = $Dicke
        Kopiere $conV $con $tx 'BmElement'                 @{ UUID = $vlId } $elem
        $rf = $gem.Clone(); $rf['RoofSlope'] = $Neigung
        Kopiere $conV $con $tx 'BmElementRoof'             @{ UUID = $vlId } $rf
        Kopiere $conV $con $tx 'BmElementDimensioning'     @{ UUID = $vlId } $gem
        Kopiere $conV $con $tx 'BmElementEnergyConsulting' @{ UUID = $vlId } $gem
        Kopiere $conV $con $tx 'BmData' @{ ReferenceUUID = $vlId; LongDesc = 'CADXMLData' } @{
            ReferenceUUID = $neuId; ClassValue = $xml; StampCreate = $jetzt; StampEdit = $jetzt }

        if ($Probelauf) { Write-Host "[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
        else { $tx.Commit(); Write-Host "Dachflaeche '$Name' angelegt ($neuId)." -ForegroundColor Green }
    } catch { if ($tx) { $tx.Rollback() }; throw }
}
finally { $con.Close(); $conV.Close() }
