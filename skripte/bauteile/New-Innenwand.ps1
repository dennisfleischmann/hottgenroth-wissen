# New-Innenwand.ps1 -- eine Innenwand in ein gezeichnetes Geschoss schreiben
#
# GRUNDLAGE
# HottCAD liest die Zeichnung aus BmData/CADXMLData zurueck und rechnet alles
# Abgeleitete selbst nach (an Test0001 gemessen, 18.08.2026). Deshalb schreibt
# dieses Werkzeug die Geometrie und nur ein knappes Geruest daneben -- Flaechen
# und Volumen holt sich die Software beim naechsten Oeffnen selbst.
#
# WAS EINE INNENWAND VON EINER AUSSENWAND UNTERSCHEIDET
# Nicht geraten, sondern an 84 vorhandenen Innenwaenden ausgezaehlt:
#
#   wall_type="Inner"  outer_wall="False"
#   kein prev/next     -- Innenwaende haengen nicht im Aussenring
#   kein direction     -- die schlanke Bauform fuehrt es nicht
#   u_valueDimGuid ist OPTIONAL -- 43 von 84 haben keine; der Marker
#                         (IW_24_0 = Innenwand 24,0 cm) traegt die Konstruktion
#   BmElementEnergyConsulting.CladdingSurface = 0 -- nicht Teil der Huelle
#
# WIE DIE ZEILEN ENTSTEHEN
# Durch Kopie einer vorhandenen Wand desselben Projekts, Spalte fuer Spalte.
# Das ist dieselbe Technik, die schon bei der BmZone getragen hat: so stimmen
# auch die Spalten, die ich nicht kenne, und die Sentinels von selbst.
# Ueberschrieben wird nur, was sich unterscheiden MUSS.
#
# BmData.UUID bleibt dabei stehen. Die Spalte ist nicht der Zeilenschluessel,
# sondern die Kennung der Datenart -- alle CADXMLData-Zeilen der Datenbank
# teilen sie sich. Der Schluessel ist das Paar (ReferenceUUID, UUID).
#
# GRENZE
# Raumzuschnitt macht das nicht. Die Wand steht danach im Grundriss; ob HottCAD
# daraus zwei Raeume bildet, entscheidet es beim Zeichnen der Raeume selbst.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    # Mittellinie der Wand, je "x,y" in Modellkoordinaten.
    [Parameter(Mandatory = $true)][string]$Von,
    [Parameter(Mandatory = $true)][string]$Bis,
    [double]$Dicke = 0.24,
    [double]$UValue = 0.3,
    [string]$Name = '',
    # Vorlage: vorhandene Wand desselben Projekts. Leer = die erste gefundene.
    [string]$Vorlage = '',
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
function Punkt([string]$s) {
    $t = $s -split ','
    if ($t.Count -ne 2) { throw "Punkt '$s' muss die Form x,y haben." }
    return @([double]::Parse($t[0].Trim(), $inv), [double]::Parse($t[1].Trim(), $inv))
}

# Eine Zeile Spalte fuer Spalte kopieren und dabei gezielt ueberschreiben.
function Kopiere-Zeile {
    param($Con, $Tx, [string]$Tabelle, [hashtable]$Schluessel, [hashtable]$Neu, [switch]$NurZeigen)
    $wo = (($Schluessel.Keys | ForEach-Object { "[$_] = @k_$_" }) -join ' AND ')
    $c = $Con.CreateCommand(); if ($Tx) { $c.Transaction = $Tx }
    $c.CommandText = "SELECT * FROM [$Tabelle] WHERE $wo"
    foreach ($k in $Schluessel.Keys) { [void]$c.Parameters.AddWithValue("@k_$k", $Schluessel[$k]) }
    $tab = New-Object System.Data.DataTable
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $c
    [void]$da.Fill($tab)
    if ($tab.Rows.Count -ne 1) { throw "Vorlage in $Tabelle nicht eindeutig ($($tab.Rows.Count) Zeilen)." }
    $q = $tab.Rows[0]

    # SyncRowVersion fuehrt die Datenbank selbst, die darf nicht mitgeschrieben werden.
    $spalten = @($tab.Columns | Where-Object { $_.ColumnName -ne 'SyncRowVersion' } | ForEach-Object { $_.ColumnName })
    foreach ($k in $Neu.Keys) { if ($spalten -notcontains $k) { throw "$Tabelle hat keine Spalte '$k'." } }

    if ($NurZeigen) {
        $zeig = @($Neu.Keys | Sort-Object | ForEach-Object { "$_=$($Neu[$_])" }) -join '  '
        Write-Host ("  + {0,-28} {1}" -f $Tabelle, $zeig)
        return
    }
    $i = $Con.CreateCommand(); $i.Transaction = $Tx
    $i.CommandText = "INSERT INTO [$Tabelle] (" + (($spalten | ForEach-Object { "[$_]" }) -join ', ') +
                     ") VALUES (" + (($spalten | ForEach-Object { "@$_" }) -join ', ') + ")"
    foreach ($s in $spalten) {
        $w = if ($Neu.ContainsKey($s)) { $Neu[$s] } else { $q[$s] }
        if ($null -eq $w) { $w = [DBNull]::Value }
        [void]$i.Parameters.AddWithValue("@$s", $w)
    }
    if ($i.ExecuteNonQuery() -ne 1) { throw "INSERT in $Tabelle schlug fehl." }
    Write-Host ("  + {0}" -f $Tabelle)
}

if (-not $OhneSoftwarepruefung) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

$A = Punkt $Von
$B = Punkt $Bis
$vx = $B[0] - $A[0]; $vy = $B[1] - $A[1]
$len = [Math]::Sqrt($vx * $vx + $vy * $vy)
if ($len -lt 0.01) { throw "Von und Bis liegen aufeinander." }
# Rechte Normale, halbe Dicke -- so entstehen die vier Ecken in der Reihenfolge,
# die die vorhandenen Innenwaende fuehren: p1/p2 die eine Seite, p3/p4 die andere.
$mx = ($vy / $len) * ($Dicke / 2); $my = (-$vx / $len) * ($Dicke / 2)

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
    [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Count) Treffer. $($tp.Name -join ' | ')" }
    $prj = $tp[0]

    # Vorlagenwand samt ihrer Zeichnung holen.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT TOP 1 e.UUID, e.LongDesc, CAST(d.ClassValue AS nvarchar(max)) AS Xml " +
                     "FROM BmElement e JOIN BmElementWall w ON w.UUID = e.UUID " +
                     "JOIN BmData d ON d.ReferenceUUID = e.UUID AND d.LongDesc = 'CADXMLData' " +
                     "WHERE e.ProjectUUID = @p AND e.RepositoryType = 3 AND (@v = '' OR e.LongDesc = @v) " +
                     "ORDER BY e.LongDesc"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    [void]$c.Parameters.AddWithValue("@v", $Vorlage)
    $l = $c.ExecuteReader()
    if (-not $l.Read()) { $l.Close(); throw "Keine Vorlagenwand in '$($prj.Name)' gefunden." }
    $vlId = $l.GetGuid(0); $vlName = $l.GetString(1); $vlXml = $l.GetString(2)
    $l.Close()

    # Aus der Vorlage uebernehmen: Geschoss, Hoehe, Auflageflaechen.
    $floor  = [regex]::Match($vlXml, 'floor="([^"]+)"').Groups[1].Value
    $hoehe  = [regex]::Match($vlXml, '\sheight="([^"]+)"').Groups[1].Value
    $zWert  = [regex]::Match($vlXml, '<p>[-\d.eE+]+;[-\d.eE+]+;([-\d.eE+]+)</p>').Groups[1].Value
    $planes = ([regex]::Matches($vlXml, '<(top|bottom)_planes count="\d+">.*?</\1_planes>', 'Singleline') |
               ForEach-Object { '      ' + ($_.Value.Trim()) }) -join $NZ
    if (-not $floor -or -not $hoehe) { throw "Vorlage '$vlName' fuehrt kein floor/height -- ungeeignet." }

    if (-not $Name) {
        $c = $con.CreateCommand()
        $c.CommandText = "SELECT LongDesc FROM BmElement WHERE ProjectUUID=@p AND LongDesc LIKE 'IW %'"
        [void]$c.Parameters.AddWithValue("@p", $prj.Id)
        $max = 0; $l = $c.ExecuteReader()
        while ($l.Read()) {
            $n = 0
            if ([int]::TryParse(($l.GetString(0) -replace '^IW\s*', ''), [ref]$n) -and $n -gt $max) { $max = $n }
        }
        $l.Close()
        $Name = "IW {0:000}" -f ($max + 1)
    }

    $neuId  = [guid]::NewGuid()
    $cadId  = [guid]::NewGuid()   # CAD-interne Wandkennung, NICHT die BmElement-UUID
    $addIn  = [guid]::NewGuid()
    $jetzt  = Get-Date
    # Abschneiden, nicht runden: 0,115 m ist IW_11_5, nicht IW_12_5. An den
    # vorhandenen Markern geprueft: IW_11_5, IW_17_5, IW_24_0, AW_36_5.
    $marker = "IW_{0}_{1}" -f [Math]::Truncate($Dicke * 100), [int]([Math]::Round($Dicke * 1000) % 10)
    $flaeche = $len * [double]::Parse($hoehe, $inv)

    $punkte = @(
        (Z ($A[0] + $mx)) + ';' + (Z ($A[1] + $my)) + ';' + $zWert
        (Z ($B[0] + $mx)) + ';' + (Z ($B[1] + $my)) + ';' + $zWert
        (Z ($B[0] - $mx)) + ';' + (Z ($B[1] - $my)) + ';' + $zWert
        (Z ($A[0] - $mx)) + ';' + (Z ($A[1] - $my)) + ';' + $zWert
    )
    $pZeilen = ($punkte | ForEach-Object { '        <p>' + $_ + '</p>' }) -join $NZ

    $kopf = '    <wall name="' + $Name + '" GUID="' + $cadId + '" floor="' + $floor +
            '" u_value="' + (Z $UValue) + '" u_value_marker="' + $marker +
            '" height="' + $hoehe + '" wall_type="Inner" outer_wall="False" fireProtectionWall_type="Standard">'
    $zeichnung = @(
        '<?xml version="1.0"?>'
        '<geometry>'
        '  <Wall count="1">'
        $kopf
        '      <points count="4">'
        $pZeilen
        '      </points>'
        '      <repositories count="1">'
        '        <val>' + $neuId + '</val>'
        '      </repositories>'
        $planes
        '      <WallDrawInfo drawSideP1P4="True" drawSideP2P3="True" connectedSideP1P4="True" connectedSideP2P3="True" wallIntersectionTypeP1P4="Miter" wallIntersectionTypeP2P3="Miter" intersectionUserDefinedP1P4="False" intersectionUserDefinedP2P3="False" />'
        '    </wall>'
        '  </Wall>'
        '</geometry>'
    ) -join $NZ

    Write-Host "Projekt : $($prj.Name)"
    Write-Host "Vorlage : $vlName   Geschoss $floor   Hoehe $hoehe"
    Write-Host "Neu     : $Name   Laenge $(Z ([Math]::Round($len,4))) m   Dicke $(Z $Dicke) m   $marker   U=$(Z $UValue)"
    Write-Host ""
    $punkte | ForEach-Object { Write-Host "  $_" }
    Write-Host ""

    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        $gem = @{ UUID = $neuId; GId = $neuId; LongDesc = $Name; ShortDesc = $Name; StampCreate = $jetzt; StampEdit = $jetzt }
        $elem = $gem.Clone()
        $elem['Thickness'] = $Dicke; $elem['Width'] = $len
        $elem['GrossArea'] = $flaeche; $elem['NetArea'] = $flaeche
        $elem['Volume'] = $flaeche * $Dicke; $elem['AddInsOutSideUUID'] = $addIn
        Kopiere-Zeile $con $tx 'BmElement' @{ UUID = $vlId } $elem -NurZeigen:$Probelauf

        Kopiere-Zeile $con $tx 'BmElementWall'         @{ UUID = $vlId } $gem -NurZeigen:$Probelauf
        Kopiere-Zeile $con $tx 'BmElementDimensioning' @{ UUID = $vlId } $gem -NurZeigen:$Probelauf

        $ec = $gem.Clone(); $ec['CladdingSurface'] = 0
        Kopiere-Zeile $con $tx 'BmElementEnergyConsulting' @{ UUID = $vlId } $ec -NurZeigen:$Probelauf

        # BmData.UUID ist die Kennung der Datenart und bleibt stehen.
        Kopiere-Zeile $con $tx 'BmData' @{ ReferenceUUID = $vlId; LongDesc = 'CADXMLData' } @{
            ReferenceUUID = $neuId; ClassValue = $zeichnung; StampCreate = $jetzt; StampEdit = $jetzt
        } -NurZeigen:$Probelauf

        if ($Probelauf) { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
        else { $tx.Commit(); Write-Host "`nInnenwand '$Name' angelegt (BmElement $neuId)." -ForegroundColor Green }
    } catch { if ($tx) { $tx.Rollback() }; throw }
}
finally { $con.Close() }
