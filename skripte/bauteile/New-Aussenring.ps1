# New-Aussenring.ps1 -- den geschlossenen Aussenwandring eines Geschosses anlegen
#
# Damit faengt ein Grundriss an. Danach traegt jede weitere Wand sich selbst,
# weil New-Innenwand.ps1 dann eine Vorlage im Projekt findet.
#
# GEHRUNG -- ALLGEMEIN, NICHT NUR FUER RECHTECKE
# Jede Wand ist ein Trapez zwischen der Aussenkontur und der um die Wandstaerke
# nach innen versetzten Innenkontur:
#
#   p1, p2   die beiden AEUSSEREN Eckpunkte dieser Wand
#   p3, p4   die zugehoerigen INNEREN Eckpunkte
#
# Die inneren Ecken sind nicht "aussen minus Wandstaerke in x und y", sondern der
# SCHNITTPUNKT der beiden nach innen versetzten Kantenlinien. Beim Rechteck laeuft
# das auf dasselbe hinaus; bei einer L-Form nicht. An der einspringenden Ecke
# liegt die innere Ecke weiter AUSSEN als die aeussere, und nur die
# Schnittpunktrechnung trifft das. Deshalb ist sie hier allgemein formuliert und
# nicht als Sonderfall.
#
# Nachgerechnet an den vier Waenden, die HottCAD in Test0001 selbst gezeichnet
# hat: alle sechzehn Punkte stimmen mit dieser Regel ueberein.
#
# UMLAUFSINN
# Die Rechnung setzt Gegenuhrzeigersinn voraus, damit die Normale (-uy, ux) nach
# innen zeigt. Ein im Uhrzeigersinn angegebenes Polygon wird stillschweigend
# umgedreht -- gemessen wird ueber die Flaechenformel, nicht geraten.
#
# KETTE
# prev/next verweisen auf die CAD-GUID der Nachbarwand, ringsum. HottCAD zieht
# das NICHT nach; steht die Kette falsch, bleibt sie falsch.
#
# DIRECTION
# Der Winkel laeuft gegen den Uhrzeigersinn von +y: atan2(-dx, dy) mod 2*pi.
# Bei 0 (Laufrichtung Norden) laesst HottCAD das Attribut weg -- das ahmt dieses
# Skript nach, damit die Zeile aussieht wie eine gezeichnete.
#
# KEINE PLATTEN
# Boden und Decke legt dieses Skript nicht an. Das ist gemessen und nicht
# vermutet: nach dem ersten Lauf an Test0001 hat HottCAD beide Platten beim
# Oeffnen selbst erzeugt, mit exakt dem geschriebenen Umriss.
#
# VORLAGE AUS EINER ANDEREN DATENBANK
# -VorlageDatenbank holt die Musterzeilen aus einer eingespielten Sicherung.
# Das ist der Weg, wenn im Projekt selbst nichts mehr steht: so stimmen
# ProjectUUID, ParentUUID, BIMUUID und die Katalogverweise weiter, ohne dass man
# wissen muss, welche der 152 Spalten projektgebunden sind.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [string]$Geschoss = '',
    # Beliebiger Grundriss als "x1,y1;x2,y2;..." -- AEUSSERE Kontur, offen
    # angegeben (der Ring wird geschlossen). Fuer L-Formen und alles andere.
    [string]$Polygon = '',
    # Bequemlichkeit fuer den Rechteckfall: suedwestliche Ecke, Breite, Tiefe.
    [string]$Ecke = '',
    [double]$Breite = 0,
    [double]$Tiefe = 0,
    [double]$Wandstaerke = 0.365,
    [string]$VorlageDatenbank = '',
    [string]$VorlageWand = '',
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

# Gelesen wird aus $ConV, geschrieben nach $Con.
function Kopiere {
    param($ConV, $Con, $Tx, [string]$Tabelle, [hashtable]$Schluessel, [hashtable]$Neu, [bool]$NurZeigen)
    $wo = (($Schluessel.Keys | ForEach-Object { "[$_] = @k_$_" }) -join ' AND ')
    $c = $ConV.CreateCommand()
    $c.CommandText = "SELECT * FROM [$Tabelle] WHERE $wo"
    foreach ($k in $Schluessel.Keys) { [void]$c.Parameters.AddWithValue("@k_$k", $Schluessel[$k]) }
    $tab = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)
    if ($tab.Rows.Count -ne 1) { throw "Vorlage in $Tabelle nicht eindeutig ($($tab.Rows.Count) Zeilen)." }
    $q = $tab.Rows[0]
    # SyncRowVersion fuehrt die Datenbank selbst.
    $spalten = @($tab.Columns | Where-Object { $_.ColumnName -ne 'SyncRowVersion' } | ForEach-Object { $_.ColumnName })
    foreach ($k in $Neu.Keys) { if ($spalten -notcontains $k) { throw "$Tabelle hat keine Spalte '$k'." } }
    if ($NurZeigen) { return }
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

if (-not $OhneSoftwarepruefung) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

# ---- Aussenkontur bestimmen ------------------------------------------------
$d = $Wandstaerke
if ($Polygon) {
    $ecken = @($Polygon -split ';' | ForEach-Object {
        $q = $_ -split ','
        if ($q.Count -ne 2) { throw "Polygonpunkt '$_' muss die Form x,y haben." }
        , @([double]::Parse($q[0].Trim(), $inv), [double]::Parse($q[1].Trim(), $inv))
    })
    if ($ecken.Count -lt 3) { throw "Ein Grundriss braucht mindestens drei Ecken." }
} else {
    if (-not $Ecke -or $Breite -le 0 -or $Tiefe -le 0) { throw "Ohne -Polygon werden -Ecke, -Breite und -Tiefe gebraucht." }
    $tt = $Ecke -split ','
    if ($tt.Count -ne 2) { throw "Ecke muss die Form x,y haben." }
    $x0 = [double]::Parse($tt[0].Trim(), $inv); $y0 = [double]::Parse($tt[1].Trim(), $inv)
    if ($Breite -le 2 * $d -or $Tiefe -le 2 * $d) { throw "Rechteck ist kleiner als zweimal die Wandstaerke." }
    # Klammern um jede Komponente sind Pflicht: in PowerShell bindet das Komma
    # STAERKER als das Plus, "@($x0 + $Breite, $y0)" waere "$x0 + ($Breite, $y0)".
    $e1 = @($x0, $y0)
    $e2 = @(($x0 + $Breite), $y0)
    $e3 = @(($x0 + $Breite), ($y0 + $Tiefe))
    $e4 = @($x0, ($y0 + $Tiefe))
    $ecken = @($e1, $e2, $e3, $e4)
}

# Umlaufsinn messen. Positive Flaeche = gegen den Uhrzeigersinn.
$flaeche = 0.0
for ($i = 0; $i -lt $ecken.Count; $i++) {
    $a = $ecken[$i]; $b = $ecken[($i + 1) % $ecken.Count]
    $flaeche += $a[0] * $b[1] - $b[0] * $a[1]
}
$umgedreht = $false
if ($flaeche -lt 0) { [array]::Reverse($ecken); $umgedreht = $true }

# Innenkontur: jede Kante um die Wandstaerke nach innen versetzen, dann die
# benachbarten versetzten Linien schneiden.
$n = $ecken.Count
$ux = New-Object double[] $n; $uy = New-Object double[] $n
$px = New-Object double[] $n; $py = New-Object double[] $n
for ($i = 0; $i -lt $n; $i++) {
    $a = $ecken[$i]; $b = $ecken[($i + 1) % $n]
    $vx = $b[0] - $a[0]; $vy = $b[1] - $a[1]
    $len = [Math]::Sqrt($vx * $vx + $vy * $vy)
    if ($len -lt 1e-9) { throw "Zwei Ecken liegen aufeinander (Punkt $($i + 1))." }
    $ux[$i] = $vx / $len; $uy[$i] = $vy / $len
    # Nach innen bei Gegenuhrzeigersinn.
    $px[$i] = $a[0] + (-$uy[$i]) * $d
    $py[$i] = $a[1] + ( $ux[$i]) * $d
}
$innen = New-Object 'object[]' $n
for ($i = 0; $i -lt $n; $i++) {
    $j = ($i + $n - 1) % $n
    $kreuz = $ux[$j] * $uy[$i] - $uy[$j] * $ux[$i]
    if ([Math]::Abs($kreuz) -lt 1e-9) {
        # Kanten laufen parallel -- kein Knick, der Versatzpunkt selbst gilt.
        $innen[$i] = @($px[$i], $py[$i])
    } else {
        $dx = $px[$i] - $px[$j]; $dy = $py[$i] - $py[$j]
        $s = ($dx * $uy[$i] - $dy * $ux[$i]) / $kreuz
        $innen[$i] = @(($px[$j] + $s * $ux[$j]), ($py[$j] + $s * $uy[$j]))
    }
}

function Richtung($von, $nach) {
    $w = [Math]::Atan2(-($nach[0] - $von[0]), $nach[1] - $von[1])
    if ($w -lt 0) { $w += 2 * [Math]::PI }
    return $w
}

$waende = @()
for ($i = 0; $i -lt $n; $i++) {
    $a = $ecken[$i]; $b = $ecken[($i + 1) % $n]
    $ia = $innen[$i]; $ib = $innen[($i + 1) % $n]
    $ilen = [Math]::Sqrt(($ib[0] - $ia[0]) * ($ib[0] - $ia[0]) + ($ib[1] - $ia[1]) * ($ib[1] - $ia[1]))
    $waende += @{
        Name = ("AW {0:000}" -f ($i + 1))
        P = @($a, $b, $ib, $ia)
        Laenge = $ilen
        Richtung = (Richtung $a $b)
        CadId = [guid]::NewGuid()
        ElemId = [guid]::NewGuid()
    }
}
for ($i = 0; $i -lt $n; $i++) {
    $waende[$i].Prev = $waende[($i + $n - 1) % $n].CadId
    $waende[$i].Next = $waende[($i + 1) % $n].CadId
}

# ---- Schreiben --------------------------------------------------------------
$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
$vdb = if ($VorlageDatenbank) { $VorlageDatenbank } else { $Datenbank }
$conV = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$vdb;Integrated Security=true;TrustServerCertificate=true"
$conV.Open()
try {
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
    [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Count) Treffer. $($tp.Name -join ' | ')" }
    $prj = $tp[0]

    $c = $con.CreateCommand()
    $c.CommandText = "SELECT TOP 1 CAST(f.UUID AS varchar(40)), f.LongDesc, f.Height, f.ElevationOfRefHeight, CASE WHEN CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) > 0 THEN LOWER(SUBSTRING(CAST(d.ClassValue AS nvarchar(max)), CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) + 13, 36)) ELSE NULL END FROM BmFloor f LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.LongDesc = 'CADXMLData' " +
                     "WHERE f.ProjectUUID=@p AND (@g='' OR f.LongDesc LIKE @gl) ORDER BY f.SortNum DESC"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    [void]$c.Parameters.AddWithValue("@g", $Geschoss)
    [void]$c.Parameters.AddWithValue("@gl", "%$Geschoss%")
    $l = $c.ExecuteReader()
    if (-not $l.Read()) { $l.Close(); throw "Kein passendes Geschoss (BmFloor) gefunden." }
    $floorZeile = $l.GetString(0)
    $floor = $(if ($l.IsDBNull(4)) { $floorZeile.ToLower() } else { $l.GetString(4) })
    $floorName = $l.GetString(1)
    $floorHoehe = [double]$l.GetValue(2)   # lichte Hoehe des Geschosses
    $floorZ = [double]$l.GetValue(3)       # Hoehenlage des Geschosses
    $l.Close()

    $c = $conV.CreateCommand()
    $c.CommandText = "SELECT TOP 1 e.UUID, e.LongDesc, CAST(dd.ClassValue AS nvarchar(max)) " +
                     "FROM BmElement e JOIN BmElementWall w ON w.UUID=e.UUID " +
                     "JOIN BmData dd ON dd.ReferenceUUID=e.UUID AND dd.LongDesc='CADXMLData' " +
                     "WHERE e.ProjectUUID=@p AND e.RepositoryType=3 AND (@v='' OR e.LongDesc=@v) ORDER BY e.LongDesc"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    [void]$c.Parameters.AddWithValue("@v", $VorlageWand)
    $l = $c.ExecuteReader()
    if (-not $l.Read()) { $l.Close(); throw "Keine Vorlagenwand in Datenbank '$vdb' gefunden." }
    $vlId = $l.GetGuid(0); $vlName = $l.GetString(1); $vlXml = $l.GetString(2)
    $l.Close()

    # U-Wert-Angaben der Vorlage uebernehmen -- sie haengen an der Typologie.
    $uAttr = (([regex]::Matches($vlXml, '(u_value\w*)="([^"]*)"') |
               ForEach-Object { $_.Groups[1].Value + '="' + $_.Groups[2].Value + '"' }) -join ' ')
    # Wandhoehe und z gehoeren zum ZIELGESCHOSS, nicht zur Vorlagenwand. Die
    # Vorlage liefert Typologie und U-Werte; ihre Hoehe ist die ihres eigenen
    # Geschosses. Wer sie uebernimmt, baut jeden Ring in der Hoehe des Musters --
    # am 24.08.2026 bekamen so alle Geschosse dieselben 2,60 m aus der Vorlage.
    $zWert = Z $floorZ
    $hStr  = Z $floorHoehe

    Write-Host "Projekt : $($prj.Name)"
    Write-Host "Vorlage : $vlName aus '$vdb'"
    Write-Host "Geschoss: $floorName, Wandhoehe $hStr, z=$zWert"
    Write-Host "Kontur  : $n Ecken, Wandstaerke $(Z $d) m$(if ($umgedreht) { '  (Umlaufsinn umgedreht)' })"
    Write-Host ""

    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        foreach ($w in $waende) {
            $pkt = @($w.P | ForEach-Object { '        <p>' + (Z $_[0]) + ';' + (Z $_[1]) + ';' + $zWert + '</p>' }) -join $NZ
            # Bei Laufrichtung Norden laesst HottCAD direction weg.
            $rich = if ([Math]::Abs($w.Richtung) -lt 1e-9) { '' } else { ' direction="' + (Z $w.Richtung) + '"' }
            $kopf = '    <wall name="' + $w.Name + '" GUID="' + $w.CadId + '" floor="' + $floor + '" ' + $uAttr +
                    ' height="' + $hStr + '" wall_type="OuterContour" outer_wall="True"' +
                    ' fireProtectionWall_type="Standard"' + $rich +
                    ' prev="' + $w.Prev + '" next="' + $w.Next + '">'
            $xml = @(
                '<?xml version="1.0"?>', '<geometry>', '  <Wall count="1">', $kopf
                '      <points count="4">', $pkt, '      </points>'
                '      <repositories count="1">', '        <val>' + $w.ElemId + '</val>', '      </repositories>'
                '      <WallDrawInfo drawSideP1P4="True" drawSideP2P3="True" connectedSideP1P4="True" connectedSideP2P3="True" wallIntersectionTypeP1P4="Miter" wallIntersectionTypeP2P3="Miter" intersectionUserDefinedP1P4="False" intersectionUserDefinedP2P3="False" />'
                '    </wall>', '  </Wall>', '</geometry>'
            ) -join $NZ

            $flaecheW = $w.Laenge * [double]::Parse($hStr, $inv)
            $gem = @{ UUID = $w.ElemId; GId = $w.ElemId; LongDesc = $w.Name; ShortDesc = $w.Name
                      StampCreate = (Get-Date); StampEdit = (Get-Date) }
            $elem = $gem.Clone()
            $elem['Width'] = $w.Laenge; $elem['Thickness'] = $d
            $elem['GrossArea'] = $flaecheW; $elem['NetArea'] = $flaecheW
            $elem['Volume'] = $flaecheW * $d; $elem['AddInsOutSideUUID'] = [guid]::NewGuid()

            Write-Host ("  {0}  innen {1,7:N3} m  Richtung {2,-18}" -f $w.Name, $w.Laenge, (Z $w.Richtung))
            $w.P | ForEach-Object { Write-Host ("      {0};{1}" -f (Z $_[0]), (Z $_[1])) }

            Kopiere $conV $con $tx 'BmElement'                 @{ UUID = $vlId } $elem $Probelauf
            Kopiere $conV $con $tx 'BmElementWall'             @{ UUID = $vlId } $gem  $Probelauf
            Kopiere $conV $con $tx 'BmElementDimensioning'     @{ UUID = $vlId } $gem  $Probelauf
            Kopiere $conV $con $tx 'BmElementEnergyConsulting' @{ UUID = $vlId } $gem  $Probelauf
            Kopiere $conV $con $tx 'BmData' @{ ReferenceUUID = $vlId; LongDesc = 'CADXMLData' } @{
                ReferenceUUID = $w.ElemId; ClassValue = $xml
                StampCreate = (Get-Date); StampEdit = (Get-Date)
            } $Probelauf
        }
        if ($Probelauf) { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
        else { $tx.Commit(); Write-Host "`nAussenring angelegt: $n Waende, $($n * 5) Zeilen." -ForegroundColor Green }
    } catch { if ($tx) { $tx.Rollback() }; throw }
}
finally { $con.Close(); $conV.Close() }
