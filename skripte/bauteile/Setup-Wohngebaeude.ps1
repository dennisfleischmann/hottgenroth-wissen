# Setup-Wohngebaeude.ps1 — Einzonenmodell für ein Wohngebäude herstellen
#
# EIN Aufruf für den ganzen Ablauf, damit die Reihenfolge nicht im Kopf gehalten
# werden muss:
#
#   0. Vorbedingungen prüfen (Software zu, Geschosse vollständig, Räume da)
#   1. Sicherung
#   2. DIN-18599-Zone anlegen, falls keine existiert
#   3. Nutzungsprofil an die Zone hängen, falls keines dran ist
#   4. Raumstempel setzen — beheizte Geschosse auf eine Raumart, unbeheizte auf
#      unbeheizt
#   5. Räume der Zone zuordnen, unbeheizte daraus entfernen
#   6. Invarianten prüfen (Test-Wohngebaeude.ps1)
#
# WAS DIESES SKRIPT NICHT KANN: Räume anlegen. Das Polygon und die Verweise auf
# die umschließenden Bauteile rechnet HottCAD aus der Zeichnung. Ohne Räume
# bricht der Ablauf mit einem Hinweis ab statt etwas Halbes zu bauen.
#
# Beispiele:
#   .\Setup-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller -Probelauf
#   .\Setup-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller

param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string[]]$Beheizt,
    [string[]]$Unbeheizt = @(),
    # Raumart für die beheizten Räume. 1 = Wohnraum. 0 lässt die vorhandene stehen.
    [int]$Raumart = 1,
    [string]$Name = 'Wohnraum',
    # Zonenname beim Anlegen. ACHTUNG: die Software benennt die Zone beim
    # Zuweisen des Nutzungsprofils nach dem Profil um ("Wohnung Einfamilienhaus").
    # Deshalb wird spaeter ueber die UUID zugeordnet, nicht ueber den Namen.
    [string]$ZoneName = 'Wohnen',
    # Nutzungsprofil der Zone. Die Zahl im Namen ist NICHT ProfileUsageType!
    [string]$Profil = '42 - Wohnung Einfamilienhaus',
    [int]$ProfileUsageType = 34,
    [string]$Sicherungsordner,
    [switch]$OhneSicherung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData",
    [switch]$Probelauf
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
$werkzeuge = $PSScriptRoot
. (Join-Path $werkzeuge "Test-SoftwareLaeuft.ps1")
. (Join-Path $werkzeuge "Get-EberaterZone.ps1")

function Schritt([string]$Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }

# ---------------------------------------------------------------- 0. Vorbedingungen
Schritt "0. Vorbedingungen"
Assert-SoftwareZu -Erlaubt:$Probelauf

$verbindung = "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con = New-Object System.Data.SqlClient.SqlConnection $verbindung
$con.Open()
function Abfrage([string]$Sql, [hashtable]$P = @{}, $Tx = $null) {
    $c = $con.CreateCommand(); $c.CommandText = $Sql; $c.CommandTimeout = 300
    if ($Tx) { $c.Transaction = $Tx }
    foreach ($k in $P.Keys) { [void]$c.Parameters.AddWithValue($k, $P[$k]) }
    $t = New-Object System.Data.DataTable; $t.Load($c.ExecuteReader()); return , $t
}
function Befehl([string]$Sql, [hashtable]$P = @{}, $Tx = $null) {
    $c = $con.CreateCommand(); $c.CommandText = $Sql; $c.CommandTimeout = 300
    if ($Tx) { $c.Transaction = $Tx }
    foreach ($k in $P.Keys) { [void]$c.Parameters.AddWithValue($k, $P[$k]) }
    return $c.ExecuteNonQuery()
}

try {
    $g = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$g)) { $tp = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE UUID=@p" @{ '@p' = $g } }
    else { $tp = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p" @{ '@p' = "%$Projekt%" } }
    if ($tp.Rows.Count -ne 1) {
        $namen = ($tp.Rows | ForEach-Object { "  " + $_.LongDesc }) -join "`n"
        throw "Projekt nicht eindeutig: $($tp.Rows.Count) Treffer.`n$namen"
    }
    $projektId = [guid]$tp.Rows[0].UUID
    $projektName = [string]$tp.Rows[0].LongDesc
    Write-Host "   Projekt   : $projektName"
    Write-Host "   beheizt   : $($Beheizt -join ', ')"
    Write-Host "   unbeheizt : $(if ($Unbeheizt) { $Unbeheizt -join ', ' } else { '(keine)' })"

    # Geschosse: keines vergessen, keines doppelt, alle vorhanden
    $tf = Abfrage "SELECT f.ShortDesc, (SELECT COUNT(*) FROM BmRoom r WHERE r.FloorUUID=f.UUID) AS raeume FROM BmFloor f WHERE f.ProjectUUID=@p" @{ '@p' = $projektId }
    $alle = @($tf.Rows | ForEach-Object { [string]$_.ShortDesc })
    $genannt = @($Beheizt) + @($Unbeheizt)
    $unbekannt = @($genannt | Where-Object { $alle -notcontains $_ })
    if ($unbekannt.Count) { throw "Diese Geschosse gibt es nicht: $($unbekannt -join ', '). Vorhanden: $($alle -join ', ')." }
    $doppelt = @($Beheizt | Where-Object { $Unbeheizt -contains $_ })
    if ($doppelt.Count) { throw "Geschoss in beiden Listen: $($doppelt -join ', ')." }
    $vergessen = @($tf.Rows | Where-Object { $genannt -notcontains [string]$_.ShortDesc -and [int]$_.raeume -gt 0 } | ForEach-Object { "$($_.ShortDesc) ($($_.raeume))" })
    if ($vergessen.Count) { throw "Diese Geschosse haben Raeume, sind aber nicht zugeteilt: $($vergessen -join ', '). Jedes Geschoss mit Raeumen muss in -Beheizt oder -Unbeheizt stehen." }

    $tr = Abfrage "SELECT COUNT(*) AS n FROM BmRoom WHERE ProjectUUID=@p" @{ '@p' = $projektId }
    if ([int]$tr.Rows[0].n -eq 0) {
        throw "Das Projekt hat keine Raeume. Raeume muessen in HottCAD gezeichnet werden - Polygon und Bauteilverweise kann dieses Skript nicht erzeugen."
    }
    Write-Host "   Raeume    : $($tr.Rows[0].n)"
    Write-Host "   [ok] Vorbedingungen erfuellt" -ForegroundColor Green

    # ------------------------------------------------------------ 1. Sicherung
    Schritt "1. Sicherung"
    if ($Probelauf) { Write-Host "   uebersprungen (Probelauf)" -ForegroundColor Yellow }
    elseif ($OhneSicherung) { Write-Warning "   uebersprungen auf ausdruecklichen Wunsch" }
    else {
        if (-not $Sicherungsordner) { $Sicherungsordner = Join-Path $env:TEMP "hottgenroth-sicherung" }
        New-Item -ItemType Directory -Path $Sicherungsordner -Force | Out-Null
        $datei = Join-Path $Sicherungsordner ("$Datenbank-" + (Get-Date).ToString('yyyyMMdd-HHmmss') + ".bak")
        [void](Befehl "BACKUP DATABASE [$Datenbank] TO DISK = N'$datei' WITH INIT, NAME = N'vor Setup-Wohngebaeude'")
        Write-Host "   $datei" -ForegroundColor Green
    }

    $tx = $null
    if (-not $Probelauf) { $tx = $con.BeginTransaction() }
    $jetzt = Get-Date
    $nullGuid = [guid]'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'

    # ------------------------------------------------------------ 2. Zone
    Schritt "2. DIN-18599-Zone"
    $tz = Abfrage "SELECT UUID, LongDesc, ISNULL(InfoDesc,'') AS InfoDesc FROM BmZone WHERE ProjectUUID=@p AND ZoneType=5" @{ '@p' = $projektId } $tx
    if ($tz.Rows.Count -gt 1) { throw "Das Projekt hat $($tz.Rows.Count) DIN-18599-Zonen. Ein Wohngebaeude braucht genau eine - bitte in der Software aufloesen." }

    $eb = Get-EberaterZone -ProjektId $projektId -Instanz $Instanz -Datenbank $Datenbank
    $kennung = if ($eb) { $eb.ZoneID } else { '' }
    if ($eb) { Write-Host "   EE-Berater fuehrt: $($eb.ZoneID)  ($($eb.Saetze) Huellflaechen)" }
    else { Write-Warning "   Keine Zonenkennung im EE-Berater lesbar - InfoDesc bleibt leer." }

    if ($tz.Rows.Count -eq 1) {
        $zoneId = [guid]$tz.Rows[0].UUID; $script:ZoneId = $zoneId
        Write-Host "   vorhanden: $($tz.Rows[0].LongDesc)"
        if ($kennung -and $tz.Rows[0].InfoDesc -ne $kennung) {
            if (-not $Probelauf) { [void](Befehl "UPDATE BmZone SET InfoDesc=@i, StampEdit=@s WHERE UUID=@z" @{ '@i' = $kennung; '@s' = $jetzt; '@z' = $zoneId } $tx) }
            Write-Host "   InfoDesc nachgetragen: '$($tz.Rows[0].InfoDesc)' -> '$kennung'" -ForegroundColor Yellow
        }
    } else {
        # Vorlage aus demselben Projekt - so stimmen BIMUUID, ParentUUID und
        # alle Sentinels ohne Zutun.
        $tv = Abfrage "SELECT TOP 1 UUID FROM BmZone WHERE ProjectUUID=@p ORDER BY SortNum" @{ '@p' = $projektId } $tx
        if ($tv.Rows.Count -eq 0) {
            throw "Keine Zone als Vorlage im Projekt. Das Projekt einmal in der Software oeffnen und speichern - dabei legt sie die Brandschutzzonen an, die als Vorlage dienen."
        }
        $vorlage = [guid]$tv.Rows[0].UUID
        $zoneId = [guid]::NewGuid(); $script:ZoneId = $zoneId
        $kurz = $ZoneName
        if (-not $Probelauf) {
            [void](Befehl @"
SELECT * INTO #z FROM BmZone WHERE UUID = @v;
UPDATE #z SET UUID=@neu, GId=@neu, SortNum=(SELECT MAX(SortNum)+1 FROM BmZone WHERE ProjectUUID=@p),
    ShortDesc=N'', LongDesc=@n, InfoDesc=@i, ZoneType=5, HeatingType=1, VariantRoot='',
    StampCreate=@s, StampEdit=@s, SyncRowVersion=NEWID();
INSERT INTO BmZone SELECT * FROM #z;
SELECT * INTO #zd FROM BmZoneData WHERE UUID = @v;
UPDATE #zd SET UUID=@neu, GId=@neu, StampCreate=@s, StampEdit=@s, SyncRowVersion=NEWID();
INSERT INTO BmZoneData SELECT * FROM #zd;
"@ @{ '@v' = $vorlage; '@neu' = $zoneId; '@p' = $projektId; '@n' = $kurz; '@i' = $kennung; '@s' = $jetzt } $tx)
        }
        if ($Probelauf) {
            Write-Host "   wuerde angelegt: '$kurz', ZoneType 5, InfoDesc '$kennung' (Vorlage: $vorlage)" -ForegroundColor Yellow
            # Im Probelauf existiert die Zone nicht - die spaeteren Schritte
            # koennen sie nicht finden und wuerden abbrechen.
            $script:ZoneFehltNoch = $true
        } else {
            Write-Host "   angelegt: '$kurz', ZoneType 5, InfoDesc '$kennung'" -ForegroundColor Green
        }
    }

    # ------------------------------------------------------------ 3. Nutzungsprofil
    Schritt "3. Nutzungsprofil"
    $tpr = Abfrage "SELECT r.UUID, r.LongDesc FROM PdProfileReference r WHERE r.ProjectUUID=@p AND r.ReferenceClass='TModelZone' AND r.ReferenceToUUID=@z" @{ '@p' = $projektId; '@z' = $zoneId } $tx
    if ($tpr.Rows.Count -gt 1) { throw "Die Zone hat $($tpr.Rows.Count) Nutzungsprofile. Genau eines ist erlaubt." }
    if ($tpr.Rows.Count -eq 1) {
        Write-Host "   vorhanden: $($tpr.Rows[0].LongDesc)"
    } elseif ($Probelauf) {
        Write-Host "   wuerde angelegt: $Profil (ProfileUsageType $ProfileUsageType)" -ForegroundColor Yellow
    } else {
        # Vorlage: irgendein Profil dieses Typs aus der Datenbank. Die
        # projektgebundenen Felder werden ueberschrieben.
        $tv = Abfrage "SELECT TOP 1 UUID FROM PdProfileUsage WHERE ProfileUsageType=@t ORDER BY StampCreate DESC" @{ '@t' = $ProfileUsageType } $tx
        if ($tv.Rows.Count -eq 0) { throw "Kein Profil mit ProfileUsageType $ProfileUsageType als Vorlage in der Datenbank gefunden." }
        $pv = [guid]$tv.Rows[0].UUID
        $tpdm = Abfrage "SELECT UUID FROM PrXim WHERE ProjectUUID=@p AND ContainerType=5" @{ '@p' = $projektId } $tx
        if ($tpdm.Rows.Count -ne 1) { throw "PDM-Container (PrXim.ContainerType = 5) nicht eindeutig: $($tpdm.Rows.Count)." }
        $pdm = [guid]$tpdm.Rows[0].UUID
        $neu = [guid]::NewGuid()
        $kurz = ($Profil -replace '^[0-9.]+[ ]*-[ ]*', '')
        [void](Befehl @"
SELECT * INTO #pf FROM PdProfile WHERE UUID=@v;
UPDATE #pf SET UUID=@neu, GId=@neu, ProjectUUID=@p, PDMUUID=@pdm, ShortDesc=@k, LongDesc=@l,
    StampCreate=@s, StampEdit=@s, SyncRowVersion=NEWID();
INSERT INTO PdProfile SELECT * FROM #pf;
SELECT * INTO #pu FROM PdProfileUsage WHERE UUID=@v;
UPDATE #pu SET UUID=@neu, GId=@neu, ProjectUUID=@p, ShortDesc=@k, LongDesc=@l,
    StampCreate=@s, StampEdit=@s, SyncRowVersion=NEWID();
INSERT INTO PdProfileUsage SELECT * FROM #pu;
"@ @{ '@v' = $pv; '@neu' = $neu; '@p' = $projektId; '@pdm' = $pdm; '@k' = $kurz; '@l' = $Profil; '@s' = $jetzt } $tx)
        [void](Befehl @"
INSERT INTO PdProfileReference
 (UUID, Id, SortNum, ShortDesc, LongDesc, ReferenceToUUID, ReferenceClassType, ReferenceClass,
  ReferenceContainerType, GeneratorType, StampEdit, StampCreate, SyncType, SyncCreate, SyncEdit,
  SyncVersion, SyncMeta, ProjectUUID, StampSync, GId, MId, SyncStamp, SyncRowVersion)
VALUES (@neu, -1, -1, @k, @l, @z, 2, 'TModelZone', 2, 2, @s, @s, 1, @ng, @ng,
  '1.1.2.3', '{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}', @p, '18991230', @neu, @ng, @s, NEWID())
"@ @{ '@neu' = $neu; '@k' = $kurz; '@l' = $Profil; '@z' = $zoneId; '@s' = $jetzt; '@ng' = $nullGuid; '@p' = $projektId } $tx)
        Write-Host "   angelegt: $Profil (ProfileUsageType $ProfileUsageType)" -ForegroundColor Green
    }

    if ($tx) { $tx.Commit(); $tx = $null }
} finally {
    if ($tx) { $tx.Rollback() }
    $con.Close()
}

# --------------------------------------------------- 4./5. Raeume, ueber die Werkzeuge
$probeArg = @{}
if ($Probelauf) { $probeArg['Probelauf'] = $true }

Schritt "4. Raumstempel"
if ($Raumart -ne 0) {
    & (Join-Path $werkzeuge "Set-Raumstempel.ps1") -Projekt $Projekt -Geschoss $Beheizt -Raumart $Raumart -Name $Name -Instanz $Instanz -Datenbank $Datenbank @probeArg
} else {
    & (Join-Path $werkzeuge "Set-Raum-Heizstatus.ps1") -Projekt $Projekt -Geschoss $Beheizt -Status beheizt -Instanz $Instanz -Datenbank $Datenbank @probeArg
}
if ($Unbeheizt.Count) {
    & (Join-Path $werkzeuge "Set-Raumstempel.ps1") -Projekt $Projekt -Geschoss $Unbeheizt -Status unbeheizt -Instanz $Instanz -Datenbank $Datenbank @probeArg
}

Schritt "5. Zonenzuordnung"
# Zuordnung ueber die UUID, nicht den Namen: die Software benennt die Zone beim
# Zuweisen des Nutzungsprofils um, ein Namensnachlauf faende sie dann nicht mehr.
$zn = $script:ZoneId
if ($script:ZoneFehltNoch) {
    Write-Host "   uebersprungen: die Zone entsteht erst beim echten Lauf." -ForegroundColor Yellow
    Write-Host "   Danach wuerden alle Raeume aus $($Beheizt -join ', ') zugeordnet" -ForegroundColor Yellow
    if ($Unbeheizt.Count) { Write-Host "   und die aus $($Unbeheizt -join ', ') aus der Zone gehalten." -ForegroundColor Yellow }
} else {
    & (Join-Path $werkzeuge "Set-Raum-Zone.ps1") -Projekt $Projekt -Zone $zn -Geschoss $Beheizt -Instanz $Instanz -Datenbank $Datenbank @probeArg
    if ($Unbeheizt.Count) {
        & (Join-Path $werkzeuge "Set-Raum-Zone.ps1") -Projekt $Projekt -Zone $zn -Geschoss $Unbeheizt -Entfernen -Instanz $Instanz -Datenbank $Datenbank @probeArg
    }
}

# ------------------------------------------------------------ 6. Invarianten
Schritt "6. Invarianten"
if ($Probelauf) {
    Write-Host "   Probelauf - die Pruefung sieht den UNVERAENDERTEN Stand." -ForegroundColor Yellow
    Write-Host "   Rote Zeilen hier sind erwartet und verschwinden nach dem echten Lauf." -ForegroundColor Yellow
}
& (Join-Path $werkzeuge "Test-Wohngebaeude.ps1") -Projekt $Projekt -Beheizt $Beheizt -Unbeheizt $Unbeheizt -Instanz $Instanz -Datenbank $Datenbank
exit $LASTEXITCODE
