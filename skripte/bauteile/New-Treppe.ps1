# New-Treppe.ps1 -- eine Treppe in ein Geschoss setzen (Kopiermuster)
#
# WARUM EINE KOPIE UND KEIN FREIER AUFBAU
# Eine gezeichnete Treppe traegt in der CADXMLData ein komplettes parametrisches
# Assistentenmodell (<assistant_data>: Form, Laufbreite, Steigungen, Wangen,
# Gelaender -- als escaped UTF-16-XML). Das von Grund auf zu erzeugen hiesse,
# den Treppenassistenten nachzubauen. Stattdessen wird eine VORHANDENE Treppe
# kopiert und an den Zielort angepasst -- dasselbe Prinzip wie beim Bootstrap
# (Fremdkopie mit Ueberschreibung der projektgebundenen Spalten).
#
# EINE TREPPE SIND FUENF ZEILEN (gemessen am 17.10.2026 an zwei handgezeichneten
# Treppen in 3QHTK_Lennart Krause_MiWo_WLS035):
#   BmElement                  ElementType 10, RepositoryType 3
#   BmElementStair             Fachdaten: Stufenzahl, Steigung, Auftritt, Wangen
#   BmElementDimensioning
#   BmElementEnergyConsulting  (Treppe ist NIE Huellflaeche)
#   BmData 'CADXMLData'        <stair ...> mit Einfuegepunkt, rotation (BOGENMASS),
#                              floor-GUID, repositories-Verweis, assistant_data
#
# DECKENOEFFNUNGEN: Die Vorlage traegt <OpeningGuidKeys> mit Verweisen auf die
# Deckendurchbrueche IHRES Projekts. Beim Kopieren werden sie GELEERT -- die
# Hypothese (noch nicht in der Oberflaeche bestaetigt): HottCAD erzeugt den
# Durchbruch beim Oeffnen selbst neu, weil OpeningRemoveWellHole=true im
# Assistentenmodell steht. Bis zur Wirkungsprobe gilt: nach dem ersten Echtlauf
# in der Oberflaeche pruefen, ob die Decke ueber der Treppe geoeffnet ist.
#
# MATERIAL: Der Stufenbelag steckt in BmElementStair.TreadCoveringType und wird
# von der Vorlage uebernommen. Konstruktion/EPD fuers Rechenmodell bzw. die
# Oekobilanz sind davon getrennt (Zuweisung nach der Uebernahme bzw. ECO-CAD).
#
# ERPROBUNGSSTAND: 17.10.2026 gebaut; Probelauf an zwei Projekten, Echtlauf und
# Wirkungsprobe in der Oberflaeche stehen aus (Deckenoeffnungs-Frage!).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    # Zielgeschoss, z. B. 'EG' (LongDesc in BmFloor).
    [Parameter(Mandatory = $true)][string]$Geschoss,
    # Einfuegepunkt "x,y" in Geschosskoordinaten (siehe Show-Projekt -MitKoordinaten).
    [Parameter(Mandatory = $true)][string]$Punkt,
    # Drehung in GRAD (im XML steht Bogenmass; 90 = Lauf in +y).
    [double]$DrehungGrad = 0,
    [string]$Name = '',
    # 0 = Geschosshoehe des Zielgeschosses (FloorHeight). Passt Height, ClearHeight,
    # FloorHeight, StepHeight im Assistentenmodell und RiserHeight in BmElementStair an.
    [double]$Hoehe = 0,
    # 0 = Stufenzahl der Vorlage behalten.
    [int]$Stufen = 0,
    # Vorlagetreppe: Namensteil (z. B. 'Treppe 001'). Leer = erste Treppe des Projekts.
    [string]$Vorlage = '',
    # Projekt der Vorlagetreppe (GUID oder Namensteil). Leer = Zielprojekt selbst.
    [string]$VorlageProjekt = '',
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture
$NZ = [char]13 + [char]10

if (-not $OhneSoftwarepruefung) {
    . (Join-Path $PSScriptRoot 'Test-SoftwareLaeuft.ps1')
    if ($Probelauf) {
        try { Assert-SoftwareZu } catch { Write-Warning "Anwendung laeuft, der Probelauf schreibt aber nichts: $_" }
    } else { Assert-SoftwareZu }
}

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()

function Abfrage([string]$sql, [hashtable]$p) {
    $c = $con.CreateCommand(); $c.CommandText = $sql
    foreach ($k in $p.Keys) { [void]$c.Parameters.AddWithValue($k, $p[$k]) }
    $t = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($t)
    return ,$t
}

function LoeseProjekt([string]$angabe) {
    $g = [guid]::Empty
    if ([guid]::TryParse($angabe, [ref]$g)) {
        $t = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE UUID = @p" @{ '@p' = $g }
    } else {
        $sicher = $angabe -replace '([%_\[])', '[$1]'
        $t = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p" @{ '@p' = "%$sicher%" }
    }
    if ($t.Rows.Count -eq 0) { throw "Kein Projekt passt auf '$angabe'." }
    if ($t.Rows.Count -gt 1) { throw "Projekt nicht eindeutig ($($t.Rows.Count)): $(@($t.Rows | ForEach-Object { $_.LongDesc }) -join ' | ')" }
    return $t.Rows[0]
}

function Kopiere($Tx, [string]$Tabelle, [hashtable]$Schluessel, [hashtable]$Neu) {
    $wo = (($Schluessel.Keys | ForEach-Object { "[$_] = @k_$_" }) -join ' AND ')
    $c = $con.CreateCommand(); if ($Tx) { $c.Transaction = $Tx }
    $c.CommandText = "SELECT * FROM [$Tabelle] WHERE $wo"
    foreach ($k in $Schluessel.Keys) { [void]$c.Parameters.AddWithValue("@k_$k", $Schluessel[$k]) }
    $tab = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)
    if ($tab.Rows.Count -ne 1) { throw "Vorlage in $Tabelle nicht eindeutig ($($tab.Rows.Count) Zeilen)." }
    $q = $tab.Rows[0]
    $spalten = @($tab.Columns | Where-Object { $_.ColumnName -ne 'SyncRowVersion' } | ForEach-Object { $_.ColumnName })
    foreach ($k in $Neu.Keys) { if ($spalten -notcontains $k) { throw "$Tabelle hat keine Spalte '$k'." } }
    if (-not $Tx) { Write-Host "  [Probelauf] $Tabelle : wuerde kopiert"; return }
    $i = $con.CreateCommand(); $i.Transaction = $Tx
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

try {
    # ---- Ziel aufloesen ------------------------------------------------------
    $prj = LoeseProjekt $Projekt
    $ziel = Abfrage ("SELECT f.UUID, f.LongDesc, f.ElevationOfRefHeight, f.FloorHeight, " +
        "CAST(d.ClassValue AS nvarchar(max)) AS XML FROM BmFloor f " +
        "LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.LongDesc = 'CADXMLData' " +
        "WHERE f.ProjectUUID = @p AND f.LongDesc = @g") @{ '@p' = $prj.UUID; '@g' = $Geschoss }
    if ($ziel.Rows.Count -ne 1) {
        $alle = Abfrage "SELECT LongDesc FROM BmFloor WHERE ProjectUUID = @p" @{ '@p' = $prj.UUID }
        throw "Geschoss '$Geschoss' nicht gefunden. Vorhanden: $(@($alle.Rows | ForEach-Object { $_.LongDesc }) -join ', ')"
    }
    $zf = $ziel.Rows[0]
    if ($zf.XML -isnot [string] -or $zf.XML -notmatch '<floor GUID="([0-9a-fA-F-]{36})"') {
        throw "Zielgeschoss '$Geschoss' hat keine Zeichnungs-GUID (CADXMLData fehlt)."
    }
    $floorGid = $Matches[1].ToLower()
    $gebaeude = Abfrage "SELECT TOP 1 BIMUUID FROM BmBuilding WHERE ProjectUUID = @p" @{ '@p' = $prj.UUID }
    if ($gebaeude.Rows.Count -ne 1) { throw "Kein (eindeutiges) Gebaeude im Zielprojekt." }
    $zielBim = $gebaeude.Rows[0].BIMUUID

    $teile = $Punkt -split '[,;]'
    if ($teile.Count -lt 2) { throw "-Punkt braucht die Form 'x,y'." }
    $px = [double]::Parse($teile[0].Trim(), $inv); $py = [double]::Parse($teile[1].Trim(), $inv)

    # ---- Vorlage finden ------------------------------------------------------
    $quellPrj = if ($VorlageProjekt) { LoeseProjekt $VorlageProjekt } else { $prj }
    $vorlSicher = $Vorlage -replace '([%_\[])', '[$1]'
    $vt = Abfrage ("SELECT e.UUID, e.LongDesc, CAST(d.ClassValue AS nvarchar(max)) AS XML FROM BmElement e " +
        "JOIN BmData d ON d.ReferenceUUID = e.UUID AND d.LongDesc = 'CADXMLData' " +
        "WHERE e.ProjectUUID = @p AND e.ElementType = 10 AND e.RepositoryType = 3 " +
        "AND (@v = '' OR e.LongDesc LIKE @vl) ORDER BY e.LongDesc") @{ '@p' = $quellPrj.UUID; '@v' = $Vorlage; '@vl' = "%$vorlSicher%" }
    if ($vt.Rows.Count -eq 0) { throw "Keine Vorlagetreppe in '$($quellPrj.LongDesc)' gefunden. Erst eine Treppe von Hand zeichnen oder -VorlageProjekt angeben." }
    $vq = $vt.Rows[0]
    if ($vt.Rows.Count -gt 1) { Write-Host "Hinweis: $($vt.Rows.Count) Vorlagen gefunden, genommen wird '$($vq.LongDesc)'." }

    # ---- Name und Kenngroessen ----------------------------------------------
    if (-not $Name) {
        $maxNr = Abfrage ("SELECT ISNULL(MAX(CAST(RIGHT(LongDesc,3) AS int)),0) AS n FROM BmElement " +
            "WHERE ProjectUUID = @p AND ElementType = 10 AND LongDesc LIKE 'Treppe %'") @{ '@p' = $prj.UUID }
        $Name = 'Treppe {0:000}' -f ([int]$maxNr.Rows[0].n + 1)
    }
    $neuId  = [guid]::NewGuid()
    $cadGid = [guid]::NewGuid().ToString().ToLower()
    $rotRad = $DrehungGrad * [Math]::PI / 180.0
    $jetzt  = Get-Date

    # Hoehe: 0 = FloorHeight des Zielgeschosses
    $zielHoehe = if ($Hoehe -gt 0) { $Hoehe } else { [double]$zf.FloorHeight }
    $xml = [string]$vq.XML
    $vorlHoehe = 0.0
    if ($xml -match 'height="([0-9.]+)"') { $vorlHoehe = [double]::Parse($Matches[1], $inv) }
    $vorlStufen = 0
    if ($xml -match '&lt;NumberSteps&gt;(\d+)&lt;/NumberSteps&gt;') { $vorlStufen = [int]$Matches[1] }
    $zielStufen = if ($Stufen -gt 0) { $Stufen } else { $vorlStufen }
    if ($zielStufen -lt 3) { throw "Stufenzahl unplausibel ($zielStufen)." }
    $steigung = [Math]::Round($zielHoehe / $zielStufen, 4)
    if ($steigung -gt 0.20 -or $steigung -lt 0.14) {
        Write-Warning ("Steigung {0:N3} m liegt ausserhalb 0,14-0,20 - Stufenzahl pruefen (-Stufen)." -f $steigung)
    }

    # ---- XML anpassen --------------------------------------------------------
    $zS = { param($d) $d.ToString('0.################', $inv) }
    # PS 5.1: -replace kennt kein Zaehl-Argument - deshalb gezielt auf das
    # <stair>-Tag ankern (name= kommt sonst nirgends als Attribut vor).
    $xml = $xml -replace '<stair name="[^"]*"', ('<stair name="' + $Name + '"')
    $xml = $xml -replace '<stair ([^>]*?)GUID="[0-9a-fA-F-]{36}"', ('<stair $1GUID="' + $cadGid + '"')
    $xml = $xml -replace 'floor="[0-9a-fA-F-]{36}"', ('floor="' + $floorGid + '"')
    $xml = $xml -replace 'rotation="[-0-9.E]+"', ('rotation="' + (& $zS $rotRad) + '"')
    $xml = $xml -replace '<points count="1">\s*<p>[^<]*</p>', ('<points count="1">' + $NZ + '        <p>' + (& $zS $px) + ';' + (& $zS $py) + ';0</p>')
    $xml = $xml -replace '<repositories count="1">\s*<val>[0-9a-fA-F-]{36}</val>', ('<repositories count="1">' + $NZ + '        <val>' + $neuId.ToString().ToLower() + '</val>')
    # Deckenoeffnungs-Verweise der Vorlage gehoeren zu DEREN Projekt - leeren.
    $xml = [regex]::Replace($xml, '<OpeningGuidKeys>.*?</OpeningGuidKeys>', '<OpeningGuidKeys />', 'Singleline')
    if ([Math]::Abs($zielHoehe - $vorlHoehe) -gt 0.005 -or $zielStufen -ne $vorlStufen) {
        $diffFloor = 0.14
        if ($xml -match '&lt;FloorHeight&gt;([0-9.]+)&lt;/FloorHeight&gt;') { $diffFloor = [double]::Parse($Matches[1], $inv) - $vorlHoehe }
        $xml = $xml -replace 'height="[0-9.]+"', ('height="' + (& $zS $zielHoehe) + '"')
        $xml = $xml -replace '&lt;Height&gt;[0-9.]+&lt;/Height&gt;', ('&lt;Height&gt;' + (& $zS $zielHoehe) + '&lt;/Height&gt;')
        $xml = $xml -replace '&lt;ClearHeight&gt;[0-9.]+&lt;/ClearHeight&gt;', ('&lt;ClearHeight&gt;' + (& $zS $zielHoehe) + '&lt;/ClearHeight&gt;')
        $xml = $xml -replace '&lt;FloorHeight&gt;[0-9.]+&lt;/FloorHeight&gt;', ('&lt;FloorHeight&gt;' + (& $zS ($zielHoehe + $diffFloor)) + '&lt;/FloorHeight&gt;')
        $xml = $xml -replace '&lt;NumberSteps&gt;\d+&lt;/NumberSteps&gt;', ('&lt;NumberSteps&gt;' + $zielStufen + '&lt;/NumberSteps&gt;')
        $xml = $xml -replace '&lt;StepHeight&gt;[0-9.]+&lt;/StepHeight&gt;', ('&lt;StepHeight&gt;' + (& $zS $steigung) + '&lt;/StepHeight&gt;')
    }

    Write-Host "Projekt : $($prj.LongDesc)"
    Write-Host "Vorlage : $($vq.LongDesc) aus '$($quellPrj.LongDesc)'"
    Write-Host "Neu     : $Name   Geschoss $Geschoss (z=$($zf.ElevationOfRefHeight))   Punkt $(& $zS $px);$(& $zS $py)   Drehung $DrehungGrad Grad"
    Write-Host ("Hoehe   : {0:N2} m, {1} Steigungen a {2:N3} m" -f $zielHoehe, $zielStufen, $steigung)
    Write-Host ""

    # ---- Schreiben -----------------------------------------------------------
    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        Kopiere $tx 'BmElement' @{ UUID = $vq.UUID } @{
            UUID = $neuId; GId = $neuId; ProjectUUID = $prj.UUID
            ReferenceUUID = $zielBim; BIMUUID = $zielBim
            ShortDesc = ''; LongDesc = $Name
            StampCreate = $jetzt; StampEdit = $jetzt }
        $stairNeu = @{ UUID = $neuId; GId = $neuId; ProjectUUID = $prj.UUID
            ShortDesc = ''; LongDesc = $Name; StampCreate = $jetzt; StampEdit = $jetzt }
        if ([Math]::Abs($zielHoehe - $vorlHoehe) -gt 0.005 -or $zielStufen -ne $vorlStufen) {
            $stairNeu['NumberOfRiser'] = $zielStufen
            $stairNeu['RiserHeight'] = $steigung
        }
        Kopiere $tx 'BmElementStair' @{ UUID = $vq.UUID } $stairNeu
        foreach ($t in 'BmElementDimensioning', 'BmElementEnergyConsulting') {
            Kopiere $tx $t @{ UUID = $vq.UUID } @{
                UUID = $neuId; GId = $neuId; ProjectUUID = $prj.UUID
                ShortDesc = ''; LongDesc = $Name
                StampCreate = $jetzt; StampEdit = $jetzt }
        }
        Kopiere $tx 'BmData' @{ ReferenceUUID = $vq.UUID; LongDesc = 'CADXMLData' } @{
            ReferenceUUID = $neuId; ProjectUUID = $prj.UUID; ClassValue = $xml
            StampCreate = $jetzt; StampEdit = $jetzt }
        if ($tx) { $tx.Commit(); Write-Host "`n'$Name' angelegt. Wirkungsprobe: Projekt oeffnen und pruefen, ob die Deckenoeffnung entsteht." -ForegroundColor Green }
        else { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
    } catch { if ($tx) { $tx.Rollback() }; throw }
} finally { $con.Close() }
