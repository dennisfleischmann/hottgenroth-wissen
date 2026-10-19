# Get-EberaterZone.ps1 — die Zonenkennung des EE-Beraters aus einem Projekt lesen
#
# Der EE-Berater führt seine Zone in TableHuellfl.ZoneID der eberater.zip, einem
# ZIP-Blob in PrMedia. Format `P0Zone_<n>[HASH8]`. Die acht Hexzeichen sind nicht
# nachbildbar — sie MÜSSEN von dort gelesen werden.
#
# Zwei Dinge, die ein zweites Projekt (Werner Grotz) zutage gebracht hat und die
# beim ersten nicht auffielen:
#
#  1. Ein Projekt kann MEHRERE eberater-Container führen — dort zwei, 80 KB vom
#     11.08. und 398 KB vom 14.08. Wer den ersten nimmt, den die Datenbank
#     liefert, liest je nach Laune den Überrest. Maßgeblich ist der mit dem
#     jüngsten StampEdit.
#  2. Der Satzdurchlauf über eine .BDExit-Tabelle kann auf einen unplausiblen
#     Wert laufen und mit einer Typumwandlung abbrechen. Das darf die
#     aufrufende Prüfung nicht mitreißen — deshalb liefert die Funktion dann,
#     was sie bis dahin hat, plus eine Warnung.
#
# Rückgabe: Objekt mit ZoneID, ZoneBez, Saetze, Alle, Quelle — oder $null.

function Get-EberaterZone {
    param(
        [Parameter(Mandatory = $true)][guid]$ProjektId,
        [string]$Instanz = "(localdb)\HSETU",
        [string]$Datenbank = "HsetuPrjData",
        [string]$BdexitWerkzeuge = "C:\Projekte_Dev\hsetu-decompiled\werkzeuge\bdexit"
    )

    if (-not (Test-Path (Join-Path $BdexitWerkzeuge "bde.ps1"))) {
        Write-Warning "BDExit-Leser nicht gefunden unter $BdexitWerkzeuge — Zonenkennung nicht lesbar."
        return $null
    }

    Add-Type -AssemblyName System.Data
    Add-Type -AssemblyName System.IO.Compression

    # Kandidaten nach Zeitstempel, jüngster zuerst.
    $con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
    $con.Open()
    $kandidaten = New-Object System.Collections.ArrayList
    try {
        $cmd = $con.CreateCommand()
        $cmd.CommandText = "SELECT CAST(UUID AS varchar(40)) AS u, StampEdit, Media FROM PrMedia WHERE ProjectUUID = @p AND Media IS NOT NULL ORDER BY StampEdit DESC"
        $cmd.CommandTimeout = 300
        [void]$cmd.Parameters.AddWithValue("@p", $ProjektId)
        $leser = $cmd.ExecuteReader()
        while ($leser.Read()) {
            $b = $leser.GetValue(2)
            if ($b.Length -lt 4) { continue }
            if (-not ($b[0] -eq 0x50 -and $b[1] -eq 0x4B -and $b[2] -eq 3 -and $b[3] -eq 4)) { continue }
            [void]$kandidaten.Add([pscustomobject]@{ UUID = $leser.GetString(0); Stand = $leser.GetValue(1); Bytes = $b })
        }
        $leser.Close()
    } finally { $con.Close() }

    if ($kandidaten.Count -eq 0) { return $null }

    # Ersten Kandidaten mit TableHuellfl nehmen — die Liste ist schon sortiert.
    $roh = $null; $quelle = $null
    foreach ($k in $kandidaten) {
        $ms = [IO.MemoryStream]::new($k.Bytes, $false)
        $zip = $null
        try {
            $zip = [IO.Compression.ZipArchive]::new($ms)
            $eintrag = $zip.Entries | Where-Object { $_.Name -eq 'TableHuellfl.BDExit' } | Select-Object -First 1
            if ($eintrag) {
                $aus = [IO.MemoryStream]::new()
                $s = $eintrag.Open(); $s.CopyTo($aus); $s.Close()
                $roh = $aus.ToArray()
                $quelle = "$($k.UUID) ($($k.Stand.ToString('dd.MM.yyyy HH:mm')), $($k.Bytes.Length) B)"
                if ($kandidaten.Count -gt 1) {
                    Write-Verbose "Mehrere eberater-Container ($($kandidaten.Count)); genommen wird der jüngste: $quelle"
                }
                break
            }
        } catch {
            Write-Verbose "Container $($k.UUID) nicht lesbar: $_"
        } finally { if ($zip) { $zip.Dispose() } }
    }
    if ($null -eq $roh) { return $null }

    . (Join-Path $BdexitWerkzeuge "bde.ps1")
    . (Join-Path $BdexitWerkzeuge "satz.ps1")

    $gefunden = @{}
    $abgebrochen = $false
    try {
        $k = BdeKopf $roh
        $o = $k.Daten
        if ($o -le 0 -or $o -ge $roh.Length) { throw "Datenanfang $o liegt ausserhalb der Datei ($($roh.Length) B)" }
        while ($o -lt $roh.Length) {
            $r = BdeLies $roh $k $o -1
            # Satzende muss vorwaerts gehen und in der Datei liegen, sonst ist
            # die Deutung falsch und der Rest waere geraten.
            if ($null -eq $r) { break }
            $ende = $r.Ende
            if ($ende -le $o -or $ende -gt $roh.Length) { $abgebrochen = $true; break }
            $id = ($r.Werte | Where-Object Name -eq 'ZoneID').Wert
            $bez = ($r.Werte | Where-Object Name -eq 'ZoneBez').Wert
            if ($id) {
                $schl = "$id`t$bez"
                if (-not $gefunden.ContainsKey($schl)) { $gefunden[$schl] = 0 }
                $gefunden[$schl]++
            }
            $o = $ende
        }
    } catch {
        $abgebrochen = $true
        Write-Warning "TableHuellfl liess sich nicht vollstaendig lesen ($($_.Exception.Message.Split([char]10)[0])). Ergebnis kann unvollstaendig sein."
    }
    if ($abgebrochen -and $gefunden.Count -eq 0) { return $null }
    if ($gefunden.Count -eq 0) { return $null }

    # Bei einem Wohngebaeude gibt es nur eine Zone; sonst die mit den meisten
    # Huellflaechen als die tragende.
    $best = ($gefunden.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
    $teile = $best.Key -split "`t"
    return [pscustomobject]@{
        ZoneID       = $teile[0]
        ZoneBez      = if ($teile.Count -gt 1) { $teile[1] } else { '' }
        Saetze       = $best.Value
        Alle         = @($gefunden.Keys | ForEach-Object { ($_ -split "`t")[0] })
        Quelle       = $quelle
        Unvollstaendig = $abgebrochen
    }
}
