# =============================================================================
# VORLAGE (erprobt am 14.10.2026 an 3QHTK_Lennart Krause) -- NICHT direkt
# ausfuehren. Je Projekt eine Kopie ins Scratchpad legen und VIER Stellen
# anpassen:
#   1. $P          = PrProject.UUID des ZIELprojekts
#   2. $donor*     = Spenderzeilen eines VOLLSTAENDIGEN Projekts derselben
#                    Maschine (Gebaeude, EG-Floor, eine Repo-3-Wand MIT
#                    CADXMLData, eine Repo-3-Dachflaeche MIT CADXMLData --
#                    nicht jede Dachflaeche hat eine eigene!)
#   3. $bXml       = TerrainContour um den neuen Grundriss, WallWidth,
#                    GroundLevelElevation/LowestPlatformHeight (= EG-Ebene)
#   4. $floorXml / BmFloor-Werte = EG-Hoehenlage, FloorHeight, lichte Hoehe,
#                    Deckenstaerke des neuen Gebaeudes
#   5. Umbenennung: Arbeitsname und WHERE-Klausel auf den echten Projektnamen
# Noetig ist das Bootstrap nur, wenn das Projekt LEER ist (kein BmBuilding --
# der Fall, wenn es in der Software angelegt, aber HottCAD nie geoeffnet wurde).
# =============================================================================
# bootstrap-krause.ps1 -- Gebaeude, EG-Geschoss, Vorlagenwand und Vorlagedach in
# das leere Projekt "3QHTK_Lennart Krause" kopieren. Einmalskript nach dem Muster
# bootstrap-simic.ps1 (13.10.2026). Quelle der Musterzeilen: das alte Modell
# 3QHTK_Lennart Krause_260929 im selben Haus -- nur Zeilenmuster, keine Geometrie.
# Projektgebundene Spalten werden ueberschrieben; Katalogverweise sind global.
param([switch]$Probelauf)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

$P   = 'ea94920b-8917-49d9-bcc4-fadc8d510712'  # PrProject 3QHTK_Lennart Krause (frisch)
$donorB     = '0ceea001-1135-ad7e-8058-49cce4696063'  # BmBuilding 260929
$donorFloor = '0ceea001-1535-627b-997c-202b2b828db1'  # EG 260929
$donorWall  = '0ceea001-1e35-997f-8fba-2b4e19477dd6'  # Wand Repo3 260929
$donorRoof  = '0ceea001-1e35-6173-bcda-69d73293f611'  # Dachflaeche 25 Grad Repo3 260929 (mit CADXMLData)

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

$NZ = [char]13 + [char]10
$jetzt = Get-Date
$newB   = [guid]::NewGuid()
$newBIM = [guid]::NewGuid()
$egId   = [guid]::NewGuid()
$wandId = [guid]::NewGuid()
$dachId = [guid]::NewGuid()

# building_data frisch: Haus 7,27 x 11,215 bei (0,0), EG-Ebene 0,25.
# BasePlatform/FloorAboveMostTopCeiling duerfen ins Leere zeigen (Simic-Beweis);
# HottCAD normalisiert beim ersten Oeffnen.
$bXml = @(
    '<?xml version="1.0"?>'
    ('<building_data building_name="Building" AutoGenerateCeilings="True" SplitLevelMode="False" SoilMode="AttachedToGroundfloor" SoilRefHeight1="0" SoilRefHeight2="0" IFCBuilding="False" IFCIsReadOnlyImport="False" Origin="Native" VerticalPlanOffset="0" ActiveMode="Templates" ActiveSubMode="Scan" WallWidth="0.32" LowestPlatformHeight="0.25" FloorHeigth="2.79" FloorCount="0" FlapTile="0" ActiveFloor="' + $egId.ToString().ToLower() + '" OuterContourMethod="StackedStoreyAndWallThickness" GroundLevelElevation="0.25" Direction="0" BuildingForm="bformFree" BuildingFormOrig="bformFree" RoofForm="bformFree" StringView="False">')
    '  <TerrainContour count="4">'
    '    <p>-11.365;-9.3925;0</p>'
    '    <p>18.635;-9.3925;0</p>'
    '    <p>18.635;20.6075;0</p>'
    '    <p>-11.365;20.6075;0</p>'
    '  </TerrainContour>'
    '</building_data>'
) -join $NZ

$floorXml = @(
    '<?xml version="1.0"?>', '<geometry>', '  <Floor count="1">'
    ('    <floor GUID="' + $egId.ToString().ToLower() + '" name="EG" username="" elevation="0.25" type="Standard" height="2.79" ceiling="0.14">')
    '      <templates count="1" />', '    </floor>', '  </Floor>', '</geometry>'
) -join $NZ

$tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
try {
    # Arbeits-Umbenennung: der frische Name ist Praefix der drei Altprojekte,
    # die Werkzeuge loesen per LIKE auf. Am Ende der Pipeline wird zurueckbenannt.
    if ($tx) {
        $r = $con.CreateCommand(); $r.Transaction = $tx
        $r.CommandText = "UPDATE PrProject SET LongDesc = '3QHTK-IMPORT_Lennart Krause' WHERE UUID = @p AND LongDesc = '3QHTK_Lennart Krause'"
        [void]$r.Parameters.AddWithValue("@p", $P)
        Write-Host "Projekt umbenannt fuer den Import: $($r.ExecuteNonQuery()) Zeile(n) -> 3QHTK-IMPORT_Lennart Krause"
    }
    Write-Host "Gebaeude ($newB, BIM $newBIM):"
    Kopiere $con $tx 'BmBuilding' @{ UUID = $donorB } @{
        UUID = $newB; GId = $newB; ProjectUUID = $P; BIMUUID = $newBIM
        ShortDesc = 'Building'; LongDesc = 'Building'
        StampCreate = $jetzt; StampEdit = $jetzt }
    Kopiere $con $tx 'BmBuildingData' @{ UUID = $donorB } @{
        UUID = $newB; GId = $newB; ProjectUUID = $P
        StampCreate = $jetzt; StampEdit = $jetzt }
    Kopiere $con $tx 'BmBuildingDimensioning' @{ UUID = $donorB } @{
        UUID = $newB; GId = $newB; ProjectUUID = $P
        StampCreate = $jetzt; StampEdit = $jetzt }
    Kopiere $con $tx 'BmBuildingEnergyConsulting' @{ UUID = $donorB } @{
        UUID = $newB; GId = $newB; ProjectUUID = $P
        StampCreate = $jetzt; StampEdit = $jetzt }
    Kopiere $con $tx 'BmData' @{ ReferenceUUID = $donorB; LongDesc = 'CADXMLData' } @{
        ReferenceUUID = $newB; ProjectUUID = $P; ClassValue = $bXml
        StampCreate = $jetzt; StampEdit = $jetzt }
    foreach ($d in 'plot_head', 'plot_properties', 'save_type') {
        Kopiere $con $tx 'BmData' @{ ReferenceUUID = $donorB; LongDesc = $d } @{
            ReferenceUUID = $newB; ProjectUUID = $P; StampCreate = $jetzt; StampEdit = $jetzt }
    }

    Write-Host "EG-Geschoss ($egId):"
    Kopiere $con $tx 'BmFloor' @{ UUID = $donorFloor } @{
        UUID = $egId; GId = $egId; ProjectUUID = $P; BuildingUUID = $newB
        ShortDesc = 'EG'; LongDesc = 'EG'; FloorType = 3; SortNum = 1
        ElevationOfRefHeight = 0.25; Height = 2.65; FloorHeight = 2.79; CeilingThickness = 0.14
        StampCreate = $jetzt; StampEdit = $jetzt }
    Kopiere $con $tx 'BmFloorData' @{ UUID = $donorFloor } @{
        UUID = $egId; GId = $egId; ProjectUUID = $P
        ShortDesc = 'EG'; LongDesc = 'EG'; StampCreate = $jetzt; StampEdit = $jetzt }
    Kopiere $con $tx 'BmData' @{ ReferenceUUID = $donorFloor; LongDesc = 'CADXMLData' } @{
        ReferenceUUID = $egId; ProjectUUID = $P; ClassValue = $floorXml
        StampCreate = $jetzt; StampEdit = $jetzt }
    Kopiere $con $tx 'BmData' @{ ReferenceUUID = $donorFloor; LongDesc = 'is_auto_generated' } @{
        ReferenceUUID = $egId; ProjectUUID = $P; StampCreate = $jetzt; StampEdit = $jetzt }

    Write-Host "Vorlagenwand VORLAGE ($wandId):"
    Kopiere $con $tx 'BmElement' @{ UUID = $donorWall } @{
        UUID = $wandId; GId = $wandId; ProjectUUID = $P
        ReferenceUUID = $newBIM; BIMUUID = $newBIM
        ShortDesc = 'VORLAGE'; LongDesc = 'VORLAGE'
        StampCreate = $jetzt; StampEdit = $jetzt }
    foreach ($t in 'BmElementWall', 'BmElementDimensioning', 'BmElementEnergyConsulting') {
        Kopiere $con $tx $t @{ UUID = $donorWall } @{
            UUID = $wandId; GId = $wandId; ProjectUUID = $P
            ShortDesc = 'VORLAGE'; LongDesc = 'VORLAGE'
            StampCreate = $jetzt; StampEdit = $jetzt }
    }
    Kopiere $con $tx 'BmData' @{ ReferenceUUID = $donorWall; LongDesc = 'CADXMLData' } @{
        ReferenceUUID = $wandId; ProjectUUID = $P; StampCreate = $jetzt; StampEdit = $jetzt }

    Write-Host "Vorlagedach VORLAGEDACH ($dachId):"
    Kopiere $con $tx 'BmElement' @{ UUID = $donorRoof } @{
        UUID = $dachId; GId = $dachId; ProjectUUID = $P
        ReferenceUUID = $newBIM; BIMUUID = $newBIM
        ShortDesc = 'VORLAGEDACH'; LongDesc = 'VORLAGEDACH'
        StampCreate = $jetzt; StampEdit = $jetzt }
    foreach ($t in 'BmElementRoof', 'BmElementDimensioning', 'BmElementEnergyConsulting') {
        Kopiere $con $tx $t @{ UUID = $donorRoof } @{
            UUID = $dachId; GId = $dachId; ProjectUUID = $P
            ShortDesc = 'VORLAGEDACH'; LongDesc = 'VORLAGEDACH'
            StampCreate = $jetzt; StampEdit = $jetzt }
    }
    Kopiere $con $tx 'BmData' @{ ReferenceUUID = $donorRoof; LongDesc = 'CADXMLData' } @{
        ReferenceUUID = $dachId; ProjectUUID = $P; StampCreate = $jetzt; StampEdit = $jetzt }

    if ($tx) { $tx.Commit(); Write-Host "`nFertig. Gebaeude=$newB  EG=$egId  VORLAGE=$wandId  VORLAGEDACH=$dachId" -ForegroundColor Green }
    else { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
} catch { if ($tx) { $tx.Rollback() }; throw }
finally { $con.Close() }
