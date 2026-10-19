# Set-Raum-Zone.ps1 — Räume einer DIN-18599-Zone zuordnen
#
# Die Zuordnung ist eine Zeile in BmZoneReference:
#   UUID            = die ZONE  (nicht die Zeile! die Tabelle hat keine eigene Identität)
#   ReferenceToUUID = der RAUM
#   ReferenceClass  = 'TModelRoom', ReferenceClassType = 1
# Primärschlüssel ist das Paar (ReferenceToUUID, UUID).
#
# Aus dem dekompilierten TBORoom.MoveToDIN18599Zone:
#     if (DIN18599Zone != null) DeleteRef(DIN18599Zone, this);
#     CreateRef(AZone, this);
# Ein Raum hängt also in GENAU EINER DIN-18599-Zone. Dieses Skript führt
# dieselbe Regel: vorhandene Zuordnung zu einer anderen ZoneType-5-Zone wird
# gelöst, bevor die neue entsteht. Zonen anderer Art (Brandschutz = ZoneType 10,
# Lüftung, Wohneinheit) bleiben unangetastet — sie sind eigene Achsen.
#
# Beispiele:
#   .\Set-Raum-Zone.ps1 -Projekt "Pohlstra" -Zone "Einfamilienhaus" -Geschoss EG,DG1,DG2 -Probelauf
#   .\Set-Raum-Zone.ps1 -Projekt "Pohlstra" -Zone "Einfamilienhaus" -Geschoss EG,DG1,DG2

param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Zone,
    [Parameter(Mandatory = $true)][string[]]$Geschoss,
    # Einzelne Raeume ueber ShortDesc (z. B. EG-R9). Mit "-Geschoss *" kombinieren,
    # um geschossunabhaengig genau diese Raeume zu treffen - fuer Ausnahmen,
    # die nicht dem Geschoss folgen.
    [string[]]$Raum = @(),
    [int]$ZoneType = 5,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData",
    [switch]$Entfernen,
    [switch]$Probelauf
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Data
$verbindung = "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"

. (Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1")
Assert-SoftwareZu -Erlaubt:$Probelauf

$con = New-Object System.Data.SqlClient.SqlConnection $verbindung
$con.Open()
try {
    # --- Projekt ---
    $cmd = $con.CreateCommand()
    $g = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$g)) { $cmd.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE UUID=@p" }
    else { $cmd.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"; $Projekt = "%$Projekt%" }
    [void]$cmd.Parameters.AddWithValue("@p", $Projekt)
    $tp = New-Object System.Data.DataTable; $tp.Load($cmd.ExecuteReader())
    if ($tp.Rows.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Rows.Count) Treffer." }
    $projektId = [guid]$tp.Rows[0].UUID
    Write-Host "Projekt: $($tp.Rows[0].LongDesc)" -ForegroundColor Cyan

    # --- Zone ---
    $cmd = $con.CreateCommand()
    $gz = [guid]::Empty
    if ([guid]::TryParse($Zone, [ref]$gz)) {
        $cmd.CommandText = "SELECT UUID, LongDesc, InfoDesc FROM BmZone WHERE ProjectUUID=@p AND UUID=@z"
        [void]$cmd.Parameters.AddWithValue("@z", $gz)
    } else {
        $cmd.CommandText = "SELECT UUID, LongDesc, InfoDesc FROM BmZone WHERE ProjectUUID=@p AND ZoneType=@t AND LongDesc LIKE @z"
        [void]$cmd.Parameters.AddWithValue("@z", "%$Zone%")
        [void]$cmd.Parameters.AddWithValue("@t", $ZoneType)
    }
    [void]$cmd.Parameters.AddWithValue("@p", $projektId)
    $tz = New-Object System.Data.DataTable; $tz.Load($cmd.ExecuteReader())
    if ($tz.Rows.Count -ne 1) { throw "Zone nicht eindeutig: $($tz.Rows.Count) Treffer fuer '$Zone' (ZoneType $ZoneType)." }
    $zoneId = [guid]$tz.Rows[0].UUID
    Write-Host "Zone   : $($tz.Rows[0].LongDesc)   $($tz.Rows[0].InfoDesc)" -ForegroundColor Cyan

    # --- Raeume ---
    $cmd = $con.CreateCommand()
    $filter = ""
    if ($Geschoss -notcontains '*') {
        $liste = ($Geschoss | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ","
        $filter = " AND f.ShortDesc IN ($liste)"
    }
    if ($Raum.Count) {
        $rliste = ($Raum | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ","
        $filter += " AND r.ShortDesc IN ($rliste)"
    }
    $cmd.CommandText = @"
SELECT r.UUID, r.ShortDesc AS Nr, r.LongDesc AS Raum, f.ShortDesc AS Gesch,
       (SELECT TOP 1 CAST(x.UUID AS varchar(40)) FROM BmZoneReference x
          JOIN BmZone z2 ON z2.UUID = x.UUID AND z2.ZoneType = @t
         WHERE x.ReferenceToUUID = r.UUID) AS AktuelleZone
FROM BmRoom r LEFT JOIN BmFloor f ON f.UUID = r.FloorUUID
WHERE r.ProjectUUID = @p$filter
ORDER BY f.SortNum, r.ShortDesc
"@
    [void]$cmd.Parameters.AddWithValue("@p", $projektId)
    [void]$cmd.Parameters.AddWithValue("@t", $ZoneType)
    $tr = New-Object System.Data.DataTable; $tr.Load($cmd.ExecuteReader())
    if ($tr.Rows.Count -eq 0) { throw "Keine Raeume in Geschoss $($Geschoss -join ', ')." }

    $tx = $null
    if (-not $Probelauf) { $tx = $con.BeginTransaction() }
    $jetzt = Get-Date
    $neu = 0; $geloest = 0; $schonDa = 0; $entfernt = 0

    foreach ($r in $tr.Rows) {
        $raumId = [guid]$r.UUID
        $aktuell = if ($r.AktuelleZone -is [DBNull]) { $null } else { [string]$r.AktuelleZone }

        if ($Entfernen) {
            if ($null -eq $aktuell) { continue }
            if (-not $Probelauf) {
                $d = $con.CreateCommand(); $d.Transaction = $tx
                $d.CommandText = "DELETE FROM BmZoneReference WHERE ReferenceToUUID=@r AND UUID IN (SELECT UUID FROM BmZone WHERE ProjectUUID=@p AND ZoneType=@t)"
                [void]$d.Parameters.AddWithValue("@r", $raumId)
                [void]$d.Parameters.AddWithValue("@p", $projektId)
                [void]$d.Parameters.AddWithValue("@t", $ZoneType)
                [void]$d.ExecuteNonQuery()
            }
            "  - {0,-11} {1,-24} {2}" -f $r.Nr, $r.Raum, "aus Zone geloest"
            $entfernt++
            continue
        }

        if ($aktuell -and [guid]$aktuell -eq $zoneId) {
            $schonDa++
            continue
        }

        # Alte Zuordnung loesen - ein Raum hat genau eine DIN-18599-Zone
        if ($aktuell) {
            if (-not $Probelauf) {
                $d = $con.CreateCommand(); $d.Transaction = $tx
                $d.CommandText = "DELETE FROM BmZoneReference WHERE ReferenceToUUID=@r AND UUID=@z"
                [void]$d.Parameters.AddWithValue("@r", $raumId)
                [void]$d.Parameters.AddWithValue("@z", [guid]$aktuell)
                [void]$d.ExecuteNonQuery()
            }
            $geloest++
        }

        if (-not $Probelauf) {
            $i = $con.CreateCommand(); $i.Transaction = $tx
            $i.CommandText = @"
INSERT INTO BmZoneReference
 (UUID, Id, SortNum, ShortDesc, LongDesc, ReferenceToUUID, ReferenceClassType, ReferenceClass,
  GeneratorType, StampEdit, StampCreate, SyncType, SyncCreate, SyncEdit, SyncVersion, SyncMeta,
  ProjectUUID, StampSync, GId, MId, SyncStamp, SyncRowVersion)
VALUES
 (@z, NULL, NULL, NULL, NULL, @r, 1, 'TModelRoom',
  2, @now, @now, 2, @nullg, @nullg, '1.5.6', '{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}',
  @p, '18991230', NULL, @nullg, @now, @rv)
"@
            [void]$i.Parameters.AddWithValue("@z", $zoneId)
            [void]$i.Parameters.AddWithValue("@r", $raumId)
            [void]$i.Parameters.AddWithValue("@now", $jetzt)
            [void]$i.Parameters.AddWithValue("@nullg", [guid]'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA')
            [void]$i.Parameters.AddWithValue("@p", $projektId)
            [void]$i.Parameters.AddWithValue("@rv", [guid]::NewGuid())
            [void]$i.ExecuteNonQuery()
        }
        $hinweis = if ($geloest -and $aktuell) { "  (alte Zone geloest)" } else { "" }
        "  + {0,-11} {1,-24} {2}{3}" -f $r.Nr, $r.Raum, $r.Gesch, $hinweis
        $neu++
    }

    Write-Host ""
    if ($Entfernen) { Write-Host "$entfernt Zuordnungen geloest." }
    else { Write-Host "$neu neu zugeordnet, $schonDa schon in dieser Zone, $geloest aus einer anderen geloest." }

    if ($Probelauf) { Write-Host "Probelauf - nichts geschrieben." -ForegroundColor Yellow }
    else { $tx.Commit(); Write-Host "Geschrieben." -ForegroundColor Green }
} finally { $con.Close() }
