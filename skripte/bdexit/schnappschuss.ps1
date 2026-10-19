# Nimmt den vollstaendigen Stand eines Projekts auf - oder vergleicht zwei
# Aufnahmen.
#
# Wozu: um herauszufinden, welches Feld hinter einer Einstellung der Oberflaeche
# steckt. Schnappschuss machen, Einstellung in der Software aendern, zweiten
# Schnappschuss machen, vergleichen. Die Differenz nennt das Feld.
#
# Das schlaegt jedes Suchen im dekompilierten Quelltext: es setzt kein Vorwissen
# voraus, findet auch Felder, die niemand vermutet haette, und beweist
# gleichzeitig, dass es WIRKLICH das Feld ist - denn nichts anderes hat sich
# geaendert.
#
# Aufgenommen wird beides:
#   - alle neun .BDExit-Tabellen, Satz fuer Satz, Feld fuer Feld
#   - jeder IBP-Blob (je Variante) flach als Pfad = Wert
#
#   .\schnappschuss.ps1 -Projekt efdb6c6e-… -Ziel .\schnapp -Name vorher
#   .\schnappschuss.ps1 -Vergleiche .\schnapp\vorher, .\schnapp\nachher

#   .\schnappschuss.ps1 -Quelle .\entpackt -Ziel .\schnapp -Name vorher
#
# Mit -Quelle wird ein bereits entpackter Container aufgenommen statt der Stand
# aus der Datenbank. Damit laesst sich ein Vergleich auch dann fuehren, wenn der
# "vorher"-Stand nur noch als Sicherung oder Arbeitsordner vorliegt - und
# waehrend Energie.exe laeuft, denn die Datenbank wird dabei nicht angefasst.

[CmdletBinding(DefaultParameterSetName = 'Aufnehmen')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Aufnehmen')] [string] $Projekt,
    [Parameter(Mandatory, ParameterSetName = 'AusOrdner')] [string] $Quelle,
    [Parameter(Mandatory, ParameterSetName = 'Aufnehmen')]
    [Parameter(Mandatory, ParameterSetName = 'AusOrdner')] [string] $Ziel,
    [Parameter(Mandatory, ParameterSetName = 'Aufnehmen')]
    [Parameter(Mandatory, ParameterSetName = 'AusOrdner')] [string] $Name,
    [Parameter(Mandatory, ParameterSetName = 'Vergleichen')] [string[]] $Vergleiche,
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')
$flach = Join-Path (Split-Path $PSScriptRoot -Parent) 'ibp\ibp-flach.exe'

if ($PSCmdlet.ParameterSetName -eq 'Vergleichen') {
    if ($Vergleiche.Count -ne 2) { throw "genau zwei Ordner angeben" }
    $a, $b = $Vergleiche
    $dateien = @(Get-ChildItem $a -Filter *.txt | ForEach-Object { $_.Name }) +
               @(Get-ChildItem $b -Filter *.txt | ForEach-Object { $_.Name }) | Sort-Object -Unique

    $gesamt = 0
    foreach ($d in $dateien) {
        $pa = Join-Path $a $d; $pb = Join-Path $b $d
        $ta = if (Test-Path $pa) { Get-Content $pa } else { @() }
        $tb = if (Test-Path $pb) { Get-Content $pb } else { @() }
        $u = Compare-Object $ta $tb
        if (-not $u) { continue }

        # Nach Schluessel zusammenfuehren, damit "vorher/nachher" nebeneinander
        # steht statt als zwei getrennte Listen.
        $links = @{}; $rechts = @{}
        foreach ($z in $u) {
            $s = "$($z.InputObject)"
            $i = $s.IndexOf(' = ')
            if ($i -lt 0) { $i = $s.IndexOf(' | ') }
            $sch = if ($i -ge 0) { $s.Substring(0, $i) } else { $s }
            $wert = if ($i -ge 0) { $s.Substring($i + 3) } else { '' }
            if ($z.SideIndicator -eq '<=') { $links[$sch] = $wert } else { $rechts[$sch] = $wert }
        }
        $alle = @($links.Keys + $rechts.Keys | Sort-Object -Unique)
        "=== $d : $($alle.Count) Unterschiede ==="
        foreach ($s in $alle) {
            $v1 = if ($links.ContainsKey($s)) { $links[$s] } else { '(fehlt)' }
            $v2 = if ($rechts.ContainsKey($s)) { $rechts[$s] } else { '(fehlt)' }
            "  {0}`n      vorher : {1}`n      nachher: {2}" -f $s, $v1, $v2
        }
        ""
        $gesamt += $alle.Count
    }
    if ($gesamt -eq 0) { "kein Unterschied - hat die Software den Stand schon gespeichert?" }
    else { "$gesamt Unterschiede insgesamt" }
    return
}

# ---------------------------------------------------------------- aufnehmen
$ausDatenbank = $PSCmdlet.ParameterSetName -eq 'Aufnehmen'
if ($ausDatenbank -and (Get-Process -Name Energie -ErrorAction SilentlyContinue)) {
    throw "Energie.exe laeuft. Der Stand ist erst nach dem Schliessen in der Datenbank - sonst nimmt der Schnappschuss den ALTEN Stand auf."
}
if (-not (Test-Path $flach)) { throw "$flach fehlt - erst bauen" }

$ordner = Join-Path $Ziel $Name
if (Test-Path $ordner) { [IO.Directory]::Delete($ordner, $true) }
New-Item -ItemType Directory -Force -Path $ordner | Out-Null
$roh = Join-Path $ordner 'roh'
New-Item -ItemType Directory -Force -Path $roh | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($ausDatenbank) {
    $c = New-Object System.Data.SqlClient.SqlConnection $Verbindung
    $c.Open()
    try {
        $k = $c.CreateCommand()
        $k.CommandText = "SELECT Media FROM PrMedia WHERE ProjectUUID=@p AND MediaName='eberater.zip'"
        [void] $k.Parameters.AddWithValue('@p', [Guid] $Projekt)
        $daten = $k.ExecuteScalar()
        if ($null -eq $daten) { throw "Projekt $Projekt hat kein eberater.zip" }
        [IO.File]::WriteAllBytes((Join-Path $ordner 'eberater.zip'), $daten)
    } finally { $c.Close() }

    $z = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $ordner 'eberater.zip'))
    foreach ($e in $z.Entries) { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $roh $e.Name), $true) }
    $z.Dispose()
}
else {
    $quellen = @(Get-ChildItem $Quelle -Filter *.BDExit)
    if (-not $quellen) { throw "$Quelle enthaelt keine .BDExit-Tabellen" }
    foreach ($f in $quellen) { [IO.File]::Copy($f.FullName, (Join-Path $roh $f.Name), $true) }
}

function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }

# ---- Tabellen flach
$zeilen = New-Object System.Collections.ArrayList
foreach ($f in Get-ChildItem $roh -Filter *.BDExit | Sort-Object Name) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    $kp = BdeKopf $b
    $bezug = [string] ($kp.Felder | Where-Object { $_.Name -eq 'PROJ_ID' -or $_.Name -eq 'ProjektID' } |
               ForEach-Object { $_.Name } | Select-Object -First 1)
    if (-not $bezug) { $bezug = [string] $kp.Felder[0].Name }
    $schluessel = if ($bezug -ne $kp.Felder[0].Name) { $kp.Felder[0].Name } else { $null }

    $o = $kp.Daten
    while ($o -lt $b.Length) {
        $r = BdeLies $b $kp $o -1
        $id = "$(Wert $r $bezug)"
        if ($schluessel) { $id += "/$(Wert $r $schluessel)" }
        foreach ($w in $r.Werte) {
            if ($w.Name -eq 'Kernel18599V5') { continue }   # steckt in den Blobs
            $v = if ($w.Da) { "$($w.Wert)" } else { '(fehlt)' }
            if ($v.Length -gt 200) { $v = $v.Substring(0, 200) + '…' }
            [void] $zeilen.Add("$($f.BaseName)[$id].$($w.Name) = $v")
        }
        $o = $r.Ende
    }
}
$zeilen.Sort()
[System.IO.File]::WriteAllLines((Join-Path $ordner 'tabellen.txt'), $zeilen)

# ---- IBP-Blobs je Variante flach
$b = [System.IO.File]::ReadAllBytes((Join-Path $roh 'TableZusatz.BDExit'))
$kp = BdeKopf $b
$o = $kp.Daten
$n = 0
while ($o -lt $b.Length) {
    $r = BdeLies $b $kp $o -1
    $p = Wert $r 'PROJ_ID'
    $feld = $r.Werte | Where-Object Name -eq 'Kernel18599V5'
    if ($feld.Da) {
        $bin = New-Object byte[] ($feld.Roh.Length - 4)
        [Array]::Copy($feld.Roh, 4, $bin, 0, $bin.Length)
        $bd = Join-Path $roh "blob-$p.bin"
        [System.IO.File]::WriteAllBytes($bd, $bin)
        & $flach $bd > (Join-Path $ordner "modell-$p.txt")
        $n++
    }
    $o = $r.Ende
}

"Schnappschuss '$Name' in $ordner"
"  tabellen.txt   $((Get-Content (Join-Path $ordner 'tabellen.txt')).Count) Zeilen"
Get-ChildItem $ordner -Filter 'modell-*.txt' | Sort-Object Name | ForEach-Object {
    "  $($_.Name)  $((Get-Content $_.FullName).Count) Zeilen"
}
