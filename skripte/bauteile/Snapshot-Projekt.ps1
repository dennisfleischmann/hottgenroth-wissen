# Snapshot-Projekt.ps1 — Momentaufnahme eines Hottgenroth-Projekts
#
# Schreibt je gefuellter Tabelle eine TSV-Datei mit allen Zeilen, die zum Projekt
# gehoeren, und legt die PrMedia-Blobs als eigene Dateien ab. Zwei solche Ordner
# lassen sich mit Diff-Snapshot.ps1 spaltengenau vergleichen.
#
# Beispiel:
#   .\Snapshot-Projekt.ps1 -Projekt "Pohlstra" -Marke vorher
#   ... in der Software arbeiten, speichern, Software schliessen ...
#   .\Snapshot-Projekt.ps1 -Projekt "Pohlstra" -Marke nachher
#   .\Diff-Snapshot.ps1 -Vorher .\snapshots\vorher -Nachher .\snapshots\nachher

param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Marke,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData",
    # LEER LASSEN, nicht (Join-Path $PSScriptRoot "snapshots").
    #
    # $PSScriptRoot ist beim Auswerten der Parametervorgaben noch NICHT belegt,
    # sobald der Block [Parameter(...)] oder [CmdletBinding()] traegt -- dann
    # bindet PowerShell die Parameter, bevor es die Variable setzt.
    #
    # WANN es wirft, ist der Punkt: nur ueber "powershell.exe -File". Ueber
    # "& .Snapshot-Projekt.ps1" laeuft derselbe Vorgabewert anstandslos, und
    # genau so steht das Beispiel im Kopf dieser Datei. Jeder Handtest bestand
    # also, und jeder Agentenlauf fiel -- die Bruecke ruft ausschliesslich mit
    # -File auf. Gefunden vom Agenten am 21.08.2026, beide Aufrufwege
    # nachgemessen.
    [string]$Ordner = '',
    # Leser fuer die .BDExit-Tabellen aus der eberater.zip. Liegt ausserhalb
    # dieses Repos im dekompilierten Korpus; fehlt er, bleibt der ZIP-Blob
    # undurchsichtig und der Vergleich meldet dort nur "geaendert".
    [string]$BdexitWerkzeuge = "C:\Projekte_Dev\hsetu-decompiled\werkzeuge\bdexit",
    [switch]$OhneBlobs
)

$ErrorActionPreference = "Stop"

# Vorgabe erst hier setzen -- siehe Anmerkung am Parameter.
if (-not $Ordner) { $Ordner = Join-Path $PSScriptRoot "snapshots" }
Add-Type -AssemblyName System.Data

$verbindung = "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"

function Invoke-Abfrage {
    param([string]$Sql, [hashtable]$Parameter = @{})
    $con = New-Object System.Data.SqlClient.SqlConnection $verbindung
    $con.Open()
    try {
        $cmd = $con.CreateCommand()
        $cmd.CommandText = $Sql
        $cmd.CommandTimeout = 300
        foreach ($k in $Parameter.Keys) { [void]$cmd.Parameters.AddWithValue($k, $Parameter[$k]) }
        $tab = New-Object System.Data.DataTable
        $tab.Load($cmd.ExecuteReader())
        # Das Komma ist Absicht: ohne es entrollt PowerShell die DataTable
        # beim Zurueckgeben in ihre Zeilen, und .Rows.Count ist danach 0.
        return , $tab
    } finally { $con.Close() }
}

# --- Projekt aufloesen -------------------------------------------------------

$alsGuid = [guid]::Empty
$istGuid = [guid]::TryParse($Projekt, [ref]$alsGuid)
if ($istGuid) {
    $treffer = Invoke-Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE UUID = @p" @{ "@p" = [guid]$Projekt }
} else {
    $treffer = Invoke-Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p" @{ "@p" = "%$Projekt%" }
}
if ($treffer.Rows.Count -eq 0) { throw "Kein Projekt gefunden fuer '$Projekt'." }
if ($treffer.Rows.Count -gt 1) {
    $namen = ($treffer.Rows | ForEach-Object { "  " + $_.LongDesc }) -join "`n"
    throw "Mehrdeutig — $($treffer.Rows.Count) Projekte passen auf '$Projekt':`n$namen"
}
$projektId = [guid]$treffer.Rows[0].UUID
$projektName = [string]$treffer.Rows[0].LongDesc

# --- Software darf nicht laufen ---------------------------------------------
# Eine offene Instanz schreibt beim Beenden zurueck; ein Snapshot waehrend des
# Laufs zeigt einen Stand, den es so nie gab.

. (Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1")
$laeuft = Get-HottgenrothAnwendungen
if ($laeuft.Count -gt 0) {
    $namen = ($laeuft | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ", "
    Write-Warning "Die Software laeuft: $namen — der Snapshot zeigt nur, was gespeichert ist."
}

# --- Zielordner --------------------------------------------------------------

$ziel = Join-Path $Ordner $Marke
if (Test-Path $ziel) { Remove-Item $ziel -Recurse -Force }
New-Item -ItemType Directory -Path $ziel -Force | Out-Null

Write-Host "Projekt : $projektName" -ForegroundColor Cyan
Write-Host "UUID    : $projektId" -ForegroundColor Gray
Write-Host "Ordner  : $ziel" -ForegroundColor Gray
Write-Host ""

# --- Tabellen finden: Projektspalte vorhanden UND Tabelle nicht leer ----------

$tabellen = Invoke-Abfrage @"
SELECT t.name AS tabelle, c.name AS spalte, p.zeilen
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id AND c.name IN ('ProjectUUID','ProjectUId')
JOIN (SELECT object_id, SUM(rows) AS zeilen FROM sys.partitions
      WHERE index_id IN (0,1) GROUP BY object_id) p ON p.object_id = t.object_id
WHERE p.zeilen > 0
ORDER BY t.name
"@

# Primaerschluessel je Tabelle — ohne den kann der Vergleich nicht spaltengenau werden
$schluessel = @{}
$pkZeilen = Invoke-Abfrage @"
SELECT t.name AS tabelle, c.name AS spalte, ic.key_ordinal
FROM sys.tables t
JOIN sys.indexes i ON i.object_id = t.object_id AND i.is_primary_key = 1
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = t.object_id AND c.column_id = ic.column_id
ORDER BY t.name, ic.key_ordinal
"@
foreach ($z in $pkZeilen.Rows) {
    $t = [string]$z.tabelle
    if (-not $schluessel.ContainsKey($t)) { $schluessel[$t] = @() }
    $schluessel[$t] += [string]$z.spalte
}

function ConvertTo-Feld {
    param($Wert)
    if ($null -eq $Wert -or $Wert -is [DBNull]) { return "\N" }
    if ($Wert -is [byte[]]) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return "0x" + [BitConverter]::ToString($sha.ComputeHash($Wert)).Replace("-", "").Substring(0, 16) + ":$($Wert.Length)B"
    }
    if ($Wert -is [double] -or $Wert -is [single]) { return $Wert.ToString("R", [Globalization.CultureInfo]::InvariantCulture) }
    if ($Wert -is [decimal]) { return $Wert.ToString([Globalization.CultureInfo]::InvariantCulture) }
    if ($Wert -is [datetime]) { return $Wert.ToString("yyyy-MM-dd HH:mm:ss.fff") }
    $s = [string]$Wert
    return $s.Replace("`t", "\t").Replace("`r", "\r").Replace("`n", "\n")
}

$geschrieben = 0
$zeilenGesamt = 0
$bericht = New-Object System.Collections.ArrayList

foreach ($t in $tabellen.Rows) {
    $name = [string]$t.tabelle
    $spalte = [string]$t.spalte

    $daten = Invoke-Abfrage "SELECT * FROM [$name] WHERE [$spalte] = @p" @{ "@p" = $projektId }
    if ($daten.Rows.Count -eq 0) { continue }

    $spalten = @($daten.Columns | ForEach-Object { $_.ColumnName })
    $zeilen = New-Object System.Collections.ArrayList
    [void]$zeilen.Add(($spalten -join "`t"))
    foreach ($r in $daten.Rows) {
        $felder = foreach ($s in $spalten) { ConvertTo-Feld $r[$s] }
        [void]$zeilen.Add(($felder -join "`t"))
    }
    $datei = Join-Path $ziel "$name.tsv"
    [IO.File]::WriteAllLines($datei, $zeilen, [Text.UTF8Encoding]::new($false))

    $pk = "-"
    if ($schluessel.ContainsKey($name)) { $pk = ($schluessel[$name] -join ",") }
    [void]$bericht.Add([pscustomobject]@{ Tabelle = $name; Zeilen = $daten.Rows.Count; Schluessel = $pk })
    $geschrieben++
    $zeilenGesamt += $daten.Rows.Count
}

$bericht | Sort-Object Tabelle | ForEach-Object {
    "{0,-42} {1,6}  {2}" -f $_.Tabelle, $_.Zeilen, $_.Schluessel
} | Write-Host

# --- Blobs aus PrMedia -------------------------------------------------------
# Die Energieberater-Daten (und damit die 18599-Zonen) stecken hier, nicht in
# den Bm*-Tabellen. Ohne die Blobs sieht ein Vergleich davon nichts.

$blobAnzahl = 0
if (-not $OhneBlobs) {
    $medienOrdner = Join-Path $ziel "media"
    New-Item -ItemType Directory -Path $medienOrdner -Force | Out-Null

    $con = New-Object System.Data.SqlClient.SqlConnection $verbindung
    $con.Open()
    try {
        $cmd = $con.CreateCommand()
        $cmd.CommandText = "SELECT UUID, LongDesc, ShortDesc, Media FROM PrMedia WHERE ProjectUUID = @p"
        $cmd.CommandTimeout = 300
        [void]$cmd.Parameters.AddWithValue("@p", $projektId)
        $leser = $cmd.ExecuteReader()
        while ($leser.Read()) {
            if ($leser.IsDBNull(3)) { continue }
            $uuid = $leser.GetGuid(0).ToString()
            $rohdaten = $leser.GetValue(3)
            [IO.File]::WriteAllBytes((Join-Path $medienOrdner "$uuid.bin"), $rohdaten)
            $blobAnzahl++
        }
        $leser.Close()
    } finally { $con.Close() }
    Write-Host ""
    Write-Host "PrMedia-Blobs: $blobAnzahl Dateien nach media\" -ForegroundColor Gray
}

# --- eberater.zip aufschluesseln ---------------------------------------------
# Der ZIP-Blob traegt die .BDExit-Tabellen des Energieberaters. Dort stehen die
# DIN-18599-Zonen und die Huellflaechen - in SQL steht davon nichts. Ohne diesen
# Schritt meldet der Vergleich nur "Blob geaendert".

$ebTabellen = 0
if (-not $OhneBlobs -and (Test-Path $BdexitWerkzeuge)) {
    . (Join-Path $BdexitWerkzeuge "bde.ps1")
    . (Join-Path $BdexitWerkzeuge "satz.ps1")
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    foreach ($blob in (Get-ChildItem (Join-Path $ziel "media") -Filter "*.bin")) {
        $kopf = New-Object byte[] 4
        $strom = [IO.File]::OpenRead($blob.FullName)
        [void]$strom.Read($kopf, 0, 4)
        $strom.Close()
        # PK\x03\x04 - nur ZIPs kommen infrage
        if (-not ($kopf[0] -eq 0x50 -and $kopf[1] -eq 0x4B -and $kopf[2] -eq 3 -and $kopf[3] -eq 4)) { continue }

        $ebOrdner = Join-Path $ziel "eberater"
        if (Test-Path $ebOrdner) { Remove-Item $ebOrdner -Recurse -Force }
        New-Item -ItemType Directory -Path $ebOrdner -Force | Out-Null
        try {
            [IO.Compression.ZipFile]::ExtractToDirectory($blob.FullName, $ebOrdner)
        } catch {
            Write-Warning "ZIP $($blob.BaseName) laesst sich nicht auspacken: $_"
            continue
        }

        foreach ($bd in (Get-ChildItem $ebOrdner -Filter "*.BDExit")) {
            $tabName = "eb." + $bd.BaseName
            try {
                $rohdaten = [IO.File]::ReadAllBytes($bd.FullName)
                $k = BdeKopf $rohdaten
                $namen = @($k.Felder | ForEach-Object { $_.Name })
                $saetze = New-Object System.Collections.ArrayList
                $o = $k.Daten
                while ($o -lt $rohdaten.Length) {
                    $r = BdeLies $rohdaten $k $o -1
                    if ($null -eq $r -or $r.Ende -le $o) { break }
                    $h = @{}
                    foreach ($w in $r.Werte) { $h[$w.Name] = $w.Wert }
                    [void]$saetze.Add($h)
                    $o = $r.Ende
                }
            } catch {
                Write-Warning "$tabName nicht lesbar: $_"
                continue
            }
            if ($saetze.Count -eq 0) { continue }

            # Schluessel suchen: das erste Feld, sonst die ersten beiden, sonst
            # die laufende Nummer. Geraten wird nichts - es wird geprueft.
            $kandidaten = @()
            if ($namen.Count -ge 1) { $kandidaten += , @($namen[0]) }
            if ($namen.Count -ge 2) { $kandidaten += , @($namen[0], $namen[1]) }
            if ($namen.Count -ge 3) { $kandidaten += , @($namen[0], $namen[1], $namen[2]) }
            $gewaehlt = $null
            foreach ($kand in $kandidaten) {
                $gesehen = @{}
                $eindeutig = $true
                foreach ($s in $saetze) {
                    $kk = ($kand | ForEach-Object { [string]$s[$_] }) -join "|"
                    if ($gesehen.ContainsKey($kk)) { $eindeutig = $false; break }
                    $gesehen[$kk] = $true
                }
                if ($eindeutig) { $gewaehlt = $kand; break }
            }
            if ($null -eq $gewaehlt) { $gewaehlt = @("_satz") }

            $spaltenEb = @("_satz") + $namen
            $zeilenEb = New-Object System.Collections.ArrayList
            [void]$zeilenEb.Add(($spaltenEb -join "`t"))
            for ($i = 0; $i -lt $saetze.Count; $i++) {
                $s = $saetze[$i]
                $felder = New-Object System.Collections.ArrayList
                [void]$felder.Add([string]$i)
                foreach ($n in $namen) {
                    if ($s.ContainsKey($n)) { [void]$felder.Add((ConvertTo-Feld $s[$n])) }
                    else { [void]$felder.Add("\N") }
                }
                [void]$zeilenEb.Add(($felder -join "`t"))
            }
            [IO.File]::WriteAllLines((Join-Path $ziel "$tabName.tsv"), $zeilenEb, [Text.UTF8Encoding]::new($false))
            [void]$bericht.Add([pscustomobject]@{
                    Tabelle = $tabName; Zeilen = $saetze.Count; Schluessel = ($gewaehlt -join ",")
                })
            $ebTabellen++
            $zeilenGesamt += $saetze.Count
            Write-Host ("{0,-42} {1,6}  {2}" -f $tabName, $saetze.Count, ($gewaehlt -join ",")) -ForegroundColor DarkCyan
        }
    }
}

# --- Schluesselverzeichnis fuer den Vergleich --------------------------------

$idx = New-Object System.Collections.ArrayList
[void]$idx.Add("tabelle`tschluessel")
foreach ($b in $bericht) { [void]$idx.Add("$($b.Tabelle)`t$($b.Schluessel)") }
[IO.File]::WriteAllLines((Join-Path $ziel "_schluessel.tsv"), $idx, [Text.UTF8Encoding]::new($false))

# --- Kopfdaten ---------------------------------------------------------------

$meta = [ordered]@{
    marke      = $Marke
    projekt    = $projektName
    projektId  = $projektId.ToString()
    datenbank  = $Datenbank
    zeitpunkt  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    tabellen   = $geschrieben
    ebTabellen = $ebTabellen
    zeilen     = $zeilenGesamt
    blobs      = $blobAnzahl
    softwareLief = [bool]$laeuft
}
$meta | ConvertTo-Json | Out-File (Join-Path $ziel "_meta.json") -Encoding utf8

Write-Host ""
Write-Host "Fertig: $geschrieben SQL-Tabellen + $ebTabellen aus eberater.zip, $zeilenGesamt Zeilen, $blobAnzahl Blobs." -ForegroundColor Green
