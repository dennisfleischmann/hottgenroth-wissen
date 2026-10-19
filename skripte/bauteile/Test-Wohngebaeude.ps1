# Test-Wohngebaeude.ps1 — prüft die Invarianten eines Einzonen-Wohngebäudes
#
# Rein lesend. Jederzeit gefahrlos aufrufbar, auch bei laufender Software
# (dann zeigt es den gespeicherten Stand).
#
# Geprüft werden die Aussagen, die nach dem Ablauf gelten MÜSSEN. Jede einzelne
# ist an einem echten Projekt schon einmal verletzt gewesen — die Liste ist
# nicht theoretisch.
#
# Beispiel:
#   .\Test-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller

param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string[]]$Beheizt,
    [string[]]$Unbeheizt = @(),
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = "Stop"

# Listenparameter geradeziehen -- MUSS vor jeder Verwendung stehen.
#
# Ueber "powershell.exe -File skript.ps1 -Beheizt EG,DG1,DG2" kommt der Wert als
# EIN Element an: der -File-Binder trennt Arrays nicht, weder mit Komma noch mit
# Doppelpunkt noch als getrennte Argumente (alle drei gemessen, 21.08.2026).
# Ueber "& .skript.ps1 -Beheizt EG,DG1" trennt PowerShell dagegen sauber.
#
# Ohne diese Zeilen sucht das Skript ein Geschoss namens "EG,DG1,DG2", findet
# keines, und meldet einen Fehler, der nach einem Datenproblem aussieht statt
# nach einem Uebergabeproblem. Der Agent ruft ausschliesslich ueber -File auf --
# Mehrgeschossmodelle waren damit von aussen unbenutzbar.
#
# Idempotent: eine bereits getrennte Liste geht unveraendert durch.
function Trenne([string[]]$Werte) {
    return @($Werte | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$Beheizt = Trenne $Beheizt
if ($Unbeheizt) { $Unbeheizt = Trenne $Unbeheizt } else { $Unbeheizt = @() }

Add-Type -AssemblyName System.Data

$script:Fehler = 0
$script:Warnungen = 0
function Pruefe {
    param([string]$Was, [bool]$Erfuellt, [string]$Befund = "", [switch]$NurWarnung)
    if ($Erfuellt) {
        Write-Host ("  [ok]   " + $Was) -ForegroundColor Green
    } elseif ($NurWarnung) {
        Write-Host ("  [warn] " + $Was) -ForegroundColor Yellow
        if ($Befund) { Write-Host ("         " + $Befund) -ForegroundColor DarkYellow }
        $script:Warnungen++
    } else {
        Write-Host ("  [FEHL] " + $Was) -ForegroundColor Red
        if ($Befund) { Write-Host ("         " + $Befund) -ForegroundColor DarkYellow }
        $script:Fehler++
    }
}

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    function Abfrage([string]$Sql, [hashtable]$P = @{}) {
        $c = $con.CreateCommand(); $c.CommandText = $Sql; $c.CommandTimeout = 300
        foreach ($k in $P.Keys) { [void]$c.Parameters.AddWithValue($k, $P[$k]) }
        $t = New-Object System.Data.DataTable; $t.Load($c.ExecuteReader()); return , $t
    }

    # --- Projekt ---
    $g = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$g)) { $tp = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE UUID=@p" @{ '@p' = $g } }
    else { $tp = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p" @{ '@p' = "%$Projekt%" } }
    if ($tp.Rows.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Rows.Count) Treffer." }
    $pid_ = [guid]$tp.Rows[0].UUID
    Write-Host "Projekt: $($tp.Rows[0].LongDesc)" -ForegroundColor Cyan
    Write-Host "beheizt: $($Beheizt -join ', ')   unbeheizt: $(if ($Unbeheizt) { $Unbeheizt -join ', ' } else { '(keine)' })" -ForegroundColor Gray
    Write-Host ""

    # --- 1. Geschosse vollständig zugeteilt ---
    Write-Host "Geschosse" -ForegroundColor Cyan
    $tf = Abfrage "SELECT ShortDesc, (SELECT COUNT(*) FROM BmRoom r WHERE r.FloorUUID=f.UUID) AS raeume FROM BmFloor f WHERE f.ProjectUUID=@p" @{ '@p' = $pid_ }
    $alle = @($tf.Rows | ForEach-Object { [string]$_.ShortDesc })
    $genannt = @($Beheizt) + @($Unbeheizt)
    $vergessen = @($tf.Rows | Where-Object { $genannt -notcontains [string]$_.ShortDesc -and [int]$_.raeume -gt 0 } | ForEach-Object { "$($_.ShortDesc) ($($_.raeume) Raeume)" })
    Pruefe "jedes Geschoss mit Raeumen ist beheizt oder unbeheizt zugeteilt" ($vergessen.Count -eq 0) ("nicht zugeteilt: " + ($vergessen -join ', '))
    $doppelt = @($Beheizt | Where-Object { $Unbeheizt -contains $_ })
    Pruefe "kein Geschoss in beiden Listen" ($doppelt.Count -eq 0) ("doppelt: " + ($doppelt -join ', '))
    $unbekannt = @($genannt | Where-Object { $alle -notcontains $_ })
    Pruefe "alle genannten Geschosse existieren" ($unbekannt.Count -eq 0) ("unbekannt: " + ($unbekannt -join ', '))

    # --- 2. Zone ---
    Write-Host "`nZone" -ForegroundColor Cyan
    $tz = Abfrage "SELECT UUID, LongDesc, ISNULL(InfoDesc,'') AS InfoDesc, HeatingType, ParentClassType FROM BmZone WHERE ProjectUUID=@p AND ZoneType=5" @{ '@p' = $pid_ }
    Pruefe "genau eine DIN-18599-Zone (ZoneType 5)" ($tz.Rows.Count -eq 1) "gefunden: $($tz.Rows.Count)"
    if ($tz.Rows.Count -eq 1) {
        $zone = $tz.Rows[0]
        $zid = [guid]$zone.UUID
        Pruefe "Zone haengt am Gebaeude (ParentClassType 4)" ([int]$zone.ParentClassType -eq 4) "ist $($zone.ParentClassType)"
        Pruefe "Zone ist beheizt (HeatingType 1)" ([int]$zone.HeatingType -eq 1) "ist $($zone.HeatingType)"
        $td = Abfrage "SELECT COUNT(*) AS n FROM BmZoneData WHERE UUID=@z" @{ '@z' = $zid }
        Pruefe "BmZoneData zur Zone vorhanden" ([int]$td.Rows[0].n -eq 1) "gefunden: $($td.Rows[0].n)"

        # InfoDesc: Naht zum EE-Berater. Fehlt sie, ist das kein Fehler (bei
        # Werner Grotz gemessen), aber die 18599-Rechnung sieht die Zone nicht.
        . (Join-Path $PSScriptRoot "Get-EberaterZone.ps1")
        $eb = Get-EberaterZone -ProjektId $pid_ -Instanz $Instanz -Datenbank $Datenbank
        if ($null -eq $eb) {
            Pruefe "Zonenkennung im EE-Berater lesbar" $false "keine eberater.zip mit TableHuellfl gefunden - EE-Berater noch nicht benutzt?" -NurWarnung
        } else {
            Pruefe "BmZone.InfoDesc = Zonenkennung des EE-Beraters" ($zone.InfoDesc -eq $eb.ZoneID) "BmZone: '$($zone.InfoDesc)'   EE-Berater: '$($eb.ZoneID)' ($($eb.Saetze) Huellflaechen)" -NurWarnung
            Pruefe "EE-Berater fuehrt genau eine Zone" ($eb.Alle.Count -eq 1) "gefunden: $($eb.Alle -join ', ')"
        }

        # --- 3. Nutzungsprofil ---
        Write-Host "`nNutzungsprofil" -ForegroundColor Cyan
        $tpr = Abfrage @"
SELECT r.LongDesc AS Profil, u.ProfileUsageType, pf.StandardType, pf.ProfileType
FROM PdProfileReference r
LEFT JOIN PdProfileUsage u ON u.UUID = r.UUID
LEFT JOIN PdProfile pf ON pf.UUID = r.UUID
WHERE r.ProjectUUID=@p AND r.ReferenceClass='TModelZone' AND r.ReferenceToUUID=@z
"@ @{ '@p' = $pid_; '@z' = $zid }
        Pruefe "genau ein Nutzungsprofil an der Zone" ($tpr.Rows.Count -eq 1) "gefunden: $($tpr.Rows.Count)"
        if ($tpr.Rows.Count -eq 1) {
            $pr = $tpr.Rows[0]
            Write-Host "         $($pr.Profil)  (ProfileUsageType $($pr.ProfileUsageType))" -ForegroundColor Gray
            Pruefe "PdProfileUsage zum Profil vorhanden" ($pr.ProfileUsageType -isnot [DBNull])
            Pruefe "PdProfile zum Profil vorhanden" ($pr.ProfileType -isnot [DBNull])
            Pruefe "Standardprofil (StandardType 2)" ($pr.StandardType -isnot [DBNull] -and [int]$pr.StandardType -eq 2) "ist $($pr.StandardType)"
        }
    } else { $zid = [guid]::Empty }

    # --- 4. Raeume: Heizstatus beidseitig, Zonenzugehoerigkeit ---
    Write-Host "`nRaeume" -ForegroundColor Cyan
    $tr = Abfrage @"
SELECT f.ShortDesc AS Gesch, r.ShortDesc AS Nr, r.LongDesc AS Raum, r.RoomType, r.HeatingType,
       CAST(d.ClassValue AS nvarchar(max)) AS Xml,
       (SELECT COUNT(*) FROM BmZoneReference x JOIN BmZone z2 ON z2.UUID=x.UUID AND z2.ZoneType=5 WHERE x.ReferenceToUUID=r.UUID) AS zonen
FROM BmRoom r
LEFT JOIN BmFloor f ON f.UUID = r.FloorUUID
LEFT JOIN BmData d ON d.ReferenceUUID = r.UUID AND d.LongDesc='CADXMLData'
WHERE r.ProjectUUID=@p
"@ @{ '@p' = $pid_ }
    Pruefe "das Projekt hat Raeume" ($tr.Rows.Count -gt 0) "keine - Raeume muessen in HottCAD gezeichnet werden"

    $xmlZuHt = @{ 'Heated' = 1; 'Unheated' = 2; 'SeparatelyHeated' = 4 }
    $falschHeiz = @(); $unstimmig = @(); $falschZone = @(); $mehrfach = @(); $ohneXml = @()
    foreach ($r in $tr.Rows) {
        $gesch = [string]$r.Gesch; $ht = [int]$r.HeatingType
        $sollHt = if ($Beheizt -contains $gesch) { 1 } elseif ($Unbeheizt -contains $gesch) { 2 } else { $null }
        if ($null -ne $sollHt -and $ht -ne $sollHt) { $falschHeiz += "$($r.Nr) ($gesch): HT $ht, erwartet $sollHt" }

        $xml = if ($r.Xml -is [DBNull]) { "" } else { [string]$r.Xml }
        if (-not $xml) { $ohneXml += [string]$r.Nr }
        elseif ($xml -match 'heating_type="([^"]*)"') {
            $ausXml = $xmlZuHt[$Matches[1]]
            if ($ausXml -ne $ht) { $unstimmig += "$($r.Nr): BmRoom $ht, XML $($Matches[1])" }
        }

        $inZone = [int]$r.zonen
        if ($inZone -gt 1) { $mehrfach += "$($r.Nr): in $inZone Zonen" }
        $sollZone = if ($Beheizt -contains $gesch) { 1 } elseif ($Unbeheizt -contains $gesch) { 0 } else { $null }
        if ($null -ne $sollZone -and $inZone -ne $sollZone) {
            $falschZone += "$($r.Nr) ($gesch): $(if ($inZone) {'in Zone'} else {'nicht in Zone'}), erwartet $(if ($sollZone) {'in Zone'} else {'nicht in Zone'})"
        }
    }
    Pruefe "Heizstatus je Geschoss wie vorgegeben" ($falschHeiz.Count -eq 0) ($falschHeiz -join "; ")
    Pruefe "BmRoom.HeatingType und XML heating_type stimmen ueberein" ($unstimmig.Count -eq 0) ($unstimmig -join "; ")
    Pruefe "beheizte Raeume in der Zone, unbeheizte nicht" ($falschZone.Count -eq 0) ($falschZone -join "; ")
    Pruefe "kein Raum in mehr als einer DIN-18599-Zone" ($mehrfach.Count -eq 0) ($mehrfach -join "; ")
    Pruefe "jeder Raum hat ein CAD-XML" ($ohneXml.Count -eq 0) ("ohne XML: " + ($ohneXml -join ', ')) -NurWarnung

    # --- 5. Waisen ---
    Write-Host "`nVollstaendigkeit" -ForegroundColor Cyan
    $tw = Abfrage @"
SELECT
 (SELECT COUNT(*) FROM BmRoom r WHERE r.ProjectUUID=@p AND NOT EXISTS (SELECT 1 FROM BmRoomData d WHERE d.UUID=r.UUID)) AS ohneRoomData,
 (SELECT COUNT(*) FROM BmZoneReference x WHERE x.ProjectUUID=@p AND NOT EXISTS (SELECT 1 FROM BmRoom r WHERE r.UUID=x.ReferenceToUUID)) AS refOhneRaum,
 (SELECT COUNT(*) FROM BmZoneReference x WHERE x.ProjectUUID=@p AND NOT EXISTS (SELECT 1 FROM BmZone z WHERE z.UUID=x.UUID)) AS refOhneZone,
 (SELECT COUNT(*) FROM BmElement e WHERE e.ProjectUUID=@p AND e.RepositoryType=1) AS repo1
"@ @{ '@p' = $pid_ }
    $w = $tw.Rows[0]
    Pruefe "jeder Raum hat seinen BmRoomData-Satz" ([int]$w.ohneRoomData -eq 0) "ohne: $($w.ohneRoomData)"
    Pruefe "keine Zonenzuordnung ohne Raum" ([int]$w.refOhneRaum -eq 0) "Waisen: $($w.refOhneRaum)"
    Pruefe "keine Zonenzuordnung ohne Zone" ([int]$w.refOhneZone -eq 0) "Waisen: $($w.refOhneZone)"
    Pruefe "das gerechnete Gebaeude (RepositoryType 1) ist vorhanden" ([int]$w.repo1 -gt 0) "Repo-1-Elemente: $($w.repo1)"

    Write-Host ""
    if ($script:Fehler -eq 0 -and $script:Warnungen -eq 0) { Write-Host "Alles in Ordnung." -ForegroundColor Green }
    elseif ($script:Fehler -eq 0) { Write-Host "Keine Fehler, $($script:Warnungen) Hinweis(e)." -ForegroundColor Yellow }
    else { Write-Host "$($script:Fehler) Fehler, $($script:Warnungen) Hinweis(e)." -ForegroundColor Red }
} finally { $con.Close() }

exit $script:Fehler
