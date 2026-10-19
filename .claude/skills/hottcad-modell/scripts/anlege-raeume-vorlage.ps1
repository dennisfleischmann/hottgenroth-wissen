# =============================================================================
# VORLAGE (erprobt am 14.10.2026 an 3QHTK_Lennart Krause) -- NICHT direkt
# ausfuehren. Je Projekt eine Kopie ins Scratchpad legen und anpassen:
#   1. $P          = PrProject.UUID des Zielprojekts
#   2. $donorRoom  = ein vorhandener Raum eines anderen Projekts (Zeilenmuster)
#   3. Innenrechteck $x1/$y1/$x2/$y2 = Aussenmass minus Wandstaerke
#   4. Geschossliste im foreach (Namen wie in BmFloor.LongDesc)
# Ein Raum je Geschoss genuegt fuers Einzonenmodell; Raumart/Stempel setzt
# danach Setup-Wohngebaeude.ps1. HottCAD traegt Begrenzungsverweise selbst nach.
# =============================================================================
# anlege-raeume-krause.ps1 -- je Geschoss einen Raum (Innenrechteck des Rings)
# in 3QHTK_Lennart Krause anlegen. Muster: Pohlstrasse 17.08.2026 (BmRoom +
# BmRoomData + Zeichnung; Begrenzungsverweise traegt HottCAD selbst nach).
# Zeilenspender: Raum "Essen" des alten Modells 260929. Idempotent ueber ShortDesc.
param([switch]$Probelauf)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

$P = 'ea94920b-8917-49d9-bcc4-fadc8d510712'
$donorRoom = '0ceea001-1635-4874-8672-d8cf177cf10b'  # EG-R1 "Essen" 260929

$con = New-Object System.Data.SqlClient.SqlConnection "Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true;TrustServerCertificate=true"
$con.Open()

function Kopiere {
    param($Con, $Tx, [string]$Tabelle, [hashtable]$Schluessel, [hashtable]$Neu)
    $wo = (($Schluessel.Keys | ForEach-Object { "[$_] = @k_$_" }) -join ' AND ')
    $c = $Con.CreateCommand(); if ($Tx) { $c.Transaction = $Tx }
    $c.CommandText = "SELECT * FROM [$Tabelle] WHERE $wo"
    foreach ($k in $Schluessel.Keys) { [void]$c.Parameters.AddWithValue("@k_$k", $Schluessel[$k]) }
    $tab = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)
    if ($tab.Rows.Count -ne 1) { throw "Vorlage in $Tabelle nicht eindeutig ($($tab.Rows.Count) Zeilen)." }
    $q = $tab.Rows[0]
    $spalten = @($tab.Columns | Where-Object { $_.ColumnName -ne 'SyncRowVersion' } | ForEach-Object { $_.ColumnName })
    foreach ($k in $Neu.Keys) { if ($spalten -notcontains $k) { throw "$Tabelle hat keine Spalte '$k'." } }
    if (-not $Tx) { Write-Host "  [Probelauf] $Tabelle : wuerde kopiert"; return }
    $i = $Con.CreateCommand(); $i.Transaction = $Tx
    $i.CommandText = "INSERT INTO [$Tabelle] (" + (($spalten | ForEach-Object { "[$_]" }) -join ', ') +
                     ") VALUES (" + (($spalten | ForEach-Object { "@$_" }) -join ', ') + ")"
    foreach ($s in $spalten) {
        $wert = if ($Neu.ContainsKey($s)) { $Neu[$s] } else { $q[$s] }
        if ($null -eq $wert) { $wert = [DBNull]::Value }
        [void]$i.Parameters.AddWithValue("@$s", $wert)
    }
    if ($i.ExecuteNonQuery() -ne 1) { throw "INSERT in $Tabelle schlug fehl." }
    Write-Host "  + $Tabelle"
}

function Wert([string]$sql) {
    $c = $con.CreateCommand(); $c.CommandText = $sql
    return $c.ExecuteScalar()
}

$NZ = [char]13 + [char]10
$inv = [Globalization.CultureInfo]::InvariantCulture
$jetzt = Get-Date

# Innenrechteck des Rings: 0,32 .. 6,95 / 0,32 .. 10,895
$x1 = 0.32; $y1 = 0.32; $x2 = 6.95; $y2 = 10.895
$flaeche = [Math]::Round(($x2 - $x1) * ($y2 - $y1), 4)   # 70,1129
$hoehe = 2.65
$volumen = [Math]::Round($flaeche * $hoehe, 4)

foreach ($g in 'EG', 'OG1', 'DG') {
    $kurz = "$g-R1"
    $schon = [int](Wert "SELECT COUNT(*) FROM BmRoom WHERE ProjectUUID='$P' AND ShortDesc='$kurz'")
    if ($schon -gt 0) { Write-Host "$kurz existiert schon - uebersprungen."; continue }

    $floorUuid = Wert "SELECT UUID FROM BmFloor WHERE ProjectUUID='$P' AND LongDesc='$g'"
    if ($null -eq $floorUuid) { throw "Geschoss $g nicht gefunden." }
    $elev = [double](Wert "SELECT ElevationOfRefHeight FROM BmFloor WHERE UUID='$floorUuid'")
    $floorXml = Wert "SELECT CAST(ClassValue AS nvarchar(max)) FROM BmData WHERE ReferenceUUID='$floorUuid' AND LongDesc='CADXMLData'"
    if ($floorXml -notmatch '<floor GUID="([0-9a-fA-F-]{36})"') { throw "Floor-GUID fuer $g nicht gefunden." }
    $floorGid = $Matches[1].ToLower()

    $roomUuid = [guid]::NewGuid()
    $roomGid  = [guid]::NewGuid().ToString().ToLower()
    $z = $elev.ToString('0.####', $inv)
    $pkt = @("$x1;$y1", "$x2;$y1", "$x2;$y2", "$x1;$y2", "$x1;$y1") |
        ForEach-Object { '            <p>' + ($_ -replace ',', '.') + ";$z</p>" }
    $pktBlock = $pkt -join $NZ
    $fs = $flaeche.ToString('0.####', $inv); $vs = $volumen.ToString('0.####', $inv)

    $xml = @(
        '<?xml version="1.0"?>', '<geometry>', '  <Room count="1">'
        ('    <room name="Wohnraum" GUID="' + $roomGid + '" floor="' + $floorGid + '" number="' + $kurz + '" helpLinesOffset="0" room_type="mrtLivingRoom" component_type="Room" temperature="20" air_change="0.5" heating_type="Heated" short_name="' + $kurz + '" area="' + $fs + '" volume="' + $vs + '" height="2.65" userDefinedLivingArea="">')
        '      <points count="5">', $pktBlock, '      </points>'
        '      <polygons count="1">'
        '        <plg height="2.65" type="MRoomPolygon" with_holes="False">'
        '          <extensions count="0" />'
        '          <points count="5">', $pktBlock, '          </points>'
        '        </plg>', '      </polygons>'
        '    </room>', '  </Room>', '</geometry>'
    ) -join $NZ

    Write-Host "Raum $kurz (Geschoss $g, z=$z):"
    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        Kopiere $con $tx 'BmRoom' @{ UUID = $donorRoom } @{
            UUID = $roomUuid; GId = $roomUuid; ProjectUUID = $P; FloorUUID = $floorUuid
            ShortDesc = $kurz; LongDesc = 'Wohnraum'; RoomType = 1
            Area = $flaeche; HeatingType = 1
            StampCreate = $jetzt; StampEdit = $jetzt }
        Kopiere $con $tx 'BmRoomData' @{ UUID = $donorRoom } @{
            UUID = $roomUuid; GId = $roomUuid; ProjectUUID = $P
            ShortDesc = $kurz; LongDesc = 'Wohnraum'
            StampCreate = $jetzt; StampEdit = $jetzt }
        Kopiere $con $tx 'BmData' @{ ReferenceUUID = $donorRoom; LongDesc = 'CADXMLData' } @{
            ReferenceUUID = $roomUuid; ProjectUUID = $P; ClassValue = $xml
            StampCreate = $jetzt; StampEdit = $jetzt }
        if ($tx) { $tx.Commit() }
    } catch { if ($tx) { $tx.Rollback() }; throw }
}

if ($Probelauf) { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
else { Write-Host "`nFertig." -ForegroundColor Green }
$con.Close()
