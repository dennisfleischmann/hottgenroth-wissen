# Set-Raum-Heizstatus.ps1 — Heizstatus von Räumen setzen
#
# Der Heizstatus eines Raums steht an ZWEI Stellen, die zusammenpassen müssen:
#   BmRoom.HeatingType        1 = Heated, 2 = Unheated, 4 = SeparatelyHeated
#   BmData.ClassValue         Attribut heating_type im CAD-XML des Raums
# Wer nur eine der beiden setzt, hinterlässt ein Modell, das sich selbst
# widerspricht — und die Oberfläche zeigt die eine, gerechnet wird die andere.
# Dieses Skript setzt immer beide.
#
# PmSpace führt den Heizstatus NICHT mit (HeatingType dort durchweg NULL,
# InsideTemperature 0) — die Anlagenseite bleibt deshalb unangetastet.
#
# Beispiele:
#   .\Set-Raum-Heizstatus.ps1 -Projekt "Pohlstra" -Geschoss EG,DG1,DG2 -Status beheizt -Probelauf
#   .\Set-Raum-Heizstatus.ps1 -Projekt "Pohlstra" -Geschoss Keller     -Status unbeheizt

param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    # Geschosse nach BmFloor.ShortDesc, oder '*' für alle
    [Parameter(Mandatory = $true)][string[]]$Geschoss,
    # Einzelne Raeume ueber ShortDesc (z. B. EG-R9). Mit "-Geschoss *" kombinieren,
    # um geschossunabhaengig genau diese Raeume zu treffen - fuer Ausnahmen,
    # die nicht dem Geschoss folgen.
    [string[]]$Raum = @(),
    [Parameter(Mandatory = $true)][ValidateSet('beheizt', 'unbeheizt', 'separat')][string]$Status,
    # Ohne Angabe: 20 °C bei beheizt, 10 °C bei unbeheizt, 15 °C bei separat.
    # Räume, die schon einen abweichenden Wert tragen (Bäder mit 24 °C), werden
    # mit -TemperaturNurWennAbweichend nicht angefasst.
    [double]$Temperatur = [double]::NaN,
    [switch]$TemperaturNichtAendern,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData",
    [switch]$Probelauf
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Data

# Die drei Zustände, wie die Software sie führt.
$abbildung = @{
    'beheizt'   = @{ HeatingType = 1; Xml = 'Heated';           Temperatur = 20 }
    'unbeheizt' = @{ HeatingType = 2; Xml = 'Unheated';         Temperatur = 10 }
    'separat'   = @{ HeatingType = 4; Xml = 'SeparatelyHeated'; Temperatur = 15 }
}
$ziel = $abbildung[$Status]
if ([double]::IsNaN($Temperatur)) { $Temperatur = $ziel.Temperatur }

$verbindung = "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"

. (Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1")
Assert-SoftwareZu -Erlaubt:$Probelauf

$con = New-Object System.Data.SqlClient.SqlConnection $verbindung
$con.Open()
try {
    # --- Projekt aufloesen ---
    $cmd = $con.CreateCommand()
    $alsGuid = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$alsGuid)) {
        $cmd.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE UUID = @p"
    } else {
        $cmd.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
        $Projekt = "%$Projekt%"
    }
    [void]$cmd.Parameters.AddWithValue("@p", $Projekt)
    $tp = New-Object System.Data.DataTable; $tp.Load($cmd.ExecuteReader())
    if ($tp.Rows.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Rows.Count) Treffer." }
    $projektId = [guid]$tp.Rows[0].UUID
    Write-Host "Projekt: $($tp.Rows[0].LongDesc)" -ForegroundColor Cyan

    # --- Betroffene Raeume finden ---
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
       r.HeatingType, r.InsideTemperature
FROM BmRoom r LEFT JOIN BmFloor f ON f.UUID = r.FloorUUID
WHERE r.ProjectUUID = @p$filter
ORDER BY f.SortNum, r.ShortDesc
"@
    [void]$cmd.Parameters.AddWithValue("@p", $projektId)
    $tr = New-Object System.Data.DataTable; $tr.Load($cmd.ExecuteReader())
    if ($tr.Rows.Count -eq 0) { throw "Keine Raeume gefunden fuer Geschoss $($Geschoss -join ', ')." }

    # Ausgewaehlt wird NUR nach Heizstatus. Die Temperatur mit in die Bedingung
    # zu nehmen waere ein Fehler: dann geraten auch Raeume in die Liste, die
    # laengst richtig stehen und nur eine abweichende Temperatur fuehren - die
    # Baeder mit 24 C etwa wuerden auf 20 C plattgemacht.
    $zuTun = @($tr.Rows | Where-Object { [int]$_.HeatingType -ne $ziel.HeatingType })

    Write-Host "Gefunden: $($tr.Rows.Count) Raeume, davon $($zuTun.Count) zu aendern -> $Status (HeatingType $($ziel.HeatingType), $($ziel.Xml), $Temperatur C)"
    Write-Host ""
    if ($zuTun.Count -eq 0) { Write-Host "Nichts zu tun." -ForegroundColor Green; return }

    $tx = $null
    if (-not $Probelauf) { $tx = $con.BeginTransaction() }
    $jetzt = Get-Date
    $xmlOhne = 0

    foreach ($r in $zuTun) {
        $uuid = [guid]$r.UUID
        $altHt = [int]$r.HeatingType
        $altT = [double]$r.InsideTemperature

        # 1) BmRoom
        if (-not $Probelauf) {
            $u = $con.CreateCommand(); $u.Transaction = $tx
            if ($TemperaturNichtAendern) {
                $u.CommandText = "UPDATE BmRoom SET HeatingType=@h, StampEdit=@s WHERE UUID=@u"
            } else {
                $u.CommandText = "UPDATE BmRoom SET HeatingType=@h, InsideTemperature=@t, StampEdit=@s WHERE UUID=@u"
                [void]$u.Parameters.AddWithValue("@t", $Temperatur)
            }
            [void]$u.Parameters.AddWithValue("@h", $ziel.HeatingType)
            [void]$u.Parameters.AddWithValue("@s", $jetzt)
            [void]$u.Parameters.AddWithValue("@u", $uuid)
            [void]$u.ExecuteNonQuery()
        }

        # 2) Das CAD-XML in BmData — dieselbe Aussage, zweite Stelle
        $g = $con.CreateCommand(); $g.Transaction = $tx
        $g.CommandText = "SELECT CAST(ClassValue AS nvarchar(max)) FROM BmData WHERE ReferenceUUID=@u AND LongDesc='CADXMLData'"
        [void]$g.Parameters.AddWithValue("@u", $uuid)
        $xml = $g.ExecuteScalar()

        $xmlAlt = "-"
        if ([string]::IsNullOrEmpty([string]$xml)) {
            $xmlOhne++
        } else {
            if ($xml -match 'heating_type="([^"]*)"') { $xmlAlt = $Matches[1] }
            $neu = [regex]::Replace($xml, 'heating_type="[^"]*"', "heating_type=""$($ziel.Xml)""")
            if (-not $TemperaturNichtAendern) {
                $tTxt = $Temperatur.ToString([Globalization.CultureInfo]::InvariantCulture)
                $neu = [regex]::Replace($neu, '(?<![\w_])temperature="[^"]*"', "temperature=""$tTxt""")
            }
            if (-not $Probelauf -and $neu -ne $xml) {
                $u2 = $con.CreateCommand(); $u2.Transaction = $tx
                $u2.CommandText = "UPDATE BmData SET ClassValue=@v, StampEdit=@s WHERE ReferenceUUID=@u AND LongDesc='CADXMLData'"
                [void]$u2.Parameters.AddWithValue("@v", $neu)
                [void]$u2.Parameters.AddWithValue("@s", $jetzt)
                [void]$u2.Parameters.AddWithValue("@u", $uuid)
                [void]$u2.ExecuteNonQuery()
            }
        }

        $tMeldung = if ($TemperaturNichtAendern) { "$altT (unveraendert)" } else { "$altT -> $Temperatur" }
        "  {0,-11} {1,-24} {2,-7} HT {3} -> {4}   T {5,-18} xml {6} -> {7}" -f `
            $r.Nr, $r.Raum, $r.Gesch, $altHt, $ziel.HeatingType, $tMeldung, $xmlAlt, $ziel.Xml
    }

    if ($Probelauf) {
        Write-Host ""
        Write-Host "Probelauf — nichts geschrieben." -ForegroundColor Yellow
    } else {
        $tx.Commit()
        Write-Host ""
        Write-Host "$($zuTun.Count) Raeume geaendert." -ForegroundColor Green
    }
    if ($xmlOhne -gt 0) { Write-Warning "$xmlOhne Raeume ohne CADXMLData — dort steht der Status nur in BmRoom." }
} finally { $con.Close() }
