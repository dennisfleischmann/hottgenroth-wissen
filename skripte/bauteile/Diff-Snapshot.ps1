# Diff-Snapshot.ps1 — zwei Momentaufnahmen spaltengenau vergleichen
#
# Zeigt je Tabelle, welche Zeilen neu sind, welche fehlen und welche sich
# geaendert haben — bei geaenderten Zeilen nur die Spalten, die sich wirklich
# unterscheiden. PrMedia-Blobs werden ueber ihren Hash verglichen.
#
# Beispiel:
#   .\Diff-Snapshot.ps1 -Vorher .\snapshots\vorher -Nachher .\snapshots\nachher
#   .\Diff-Snapshot.ps1 -Vorher .\snapshots\vorher -Nachher .\snapshots\nachher -Bericht diff.txt

param(
    [Parameter(Mandatory = $true)][string]$Vorher,
    [Parameter(Mandatory = $true)][string]$Nachher,
    [int]$Zeilen = 40,
    [string]$Bericht,
    [switch]$NurZusammenfassung,
    [switch]$Alles
)

$ErrorActionPreference = "Stop"

# Spalten, die sich bei jedem Speichern mitbewegen, ohne etwas zu bedeuten.
# Sie werden nicht unterdrueckt, aber eine Zeile, in der sich NUR sie aendern,
# wird als "nur Zeitstempel" gemeldet statt ausgebreitet.
$rauschen = @('StampEdit', 'StampSync', 'StampCreate', 'SyncEdit', 'SyncCreate',
    'SyncMeta', 'SyncStamp', 'SyncRowVersion', 'SyncType', 'SyncVersion')

# Werte, die "nicht belegt" heissen. Die Software fuellt damit hunderte Spalten;
# eine neue Zeile ungefiltert auszugeben macht sie unlesbar. Sie werden gezaehlt
# und die Zahl gemeldet - unterschlagen wird nichts.
$leerwerte = @('\N', '', '0', 'False', '-987654321.99', '987654321.99',
    '-987654321,99', '987654321,99', '-999', '-1',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '1899-12-30 00:00:00.000')

function Ist-Leer {
    param([string]$Wert)
    if ($Alles) { return $false }
    return ($leerwerte -contains $Wert.ToLowerInvariant() -or $leerwerte -contains $Wert)
}

$ausgabe = New-Object System.Collections.ArrayList
function Schreib {
    param([string]$Text = "", [string]$Farbe = "White")
    [void]$ausgabe.Add($Text)
    Write-Host $Text -ForegroundColor $Farbe
}

function Lies-Tabelle {
    param([string]$Pfad)
    $zeilen = [IO.File]::ReadAllLines($Pfad)
    if ($zeilen.Count -eq 0) { return $null }
    $spalten = $zeilen[0] -split "`t"
    $saetze = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $zeilen.Count; $i++) {
        [void]$saetze.Add(($zeilen[$i] -split "`t"))
    }
    return [pscustomobject]@{ Spalten = $spalten; Saetze = $saetze }
}

function Lies-Schluessel {
    param([string]$Ordner)
    $map = @{}
    $datei = Join-Path $Ordner "_schluessel.tsv"
    if (-not (Test-Path $datei)) { return $map }
    $zeilen = [IO.File]::ReadAllLines($datei)
    for ($i = 1; $i -lt $zeilen.Count; $i++) {
        $teile = $zeilen[$i] -split "`t"
        if ($teile.Count -ge 2) { $map[$teile[0]] = $teile[1] }
    }
    return $map
}

function Schluessel-Von {
    param($Satz, [int[]]$Index)
    return (($Index | ForEach-Object { $Satz[$_] }) -join "|")
}

# --- Kopfdaten ---------------------------------------------------------------

foreach ($o in @($Vorher, $Nachher)) {
    if (-not (Test-Path $o)) { throw "Ordner fehlt: $o" }
}
$metaV = Get-Content (Join-Path $Vorher "_meta.json") -Raw | ConvertFrom-Json
$metaN = Get-Content (Join-Path $Nachher "_meta.json") -Raw | ConvertFrom-Json

Schreib "=== $($metaV.projekt) ===" "Cyan"
Schreib "vorher : $($metaV.zeitpunkt)   $($metaV.tabellen) Tabellen, $($metaV.zeilen) Zeilen" "Gray"
Schreib "nachher: $($metaN.zeitpunkt)   $($metaN.tabellen) Tabellen, $($metaN.zeilen) Zeilen" "Gray"
Schreib ""

$schluesselMap = Lies-Schluessel $Nachher
foreach ($k in (Lies-Schluessel $Vorher).Keys) {
    if (-not $schluesselMap.ContainsKey($k)) { $schluesselMap[$k] = (Lies-Schluessel $Vorher)[$k] }
}

$alleTabellen = @()
$alleTabellen += (Get-ChildItem $Vorher -Filter "*.tsv" | Where-Object { $_.Name -notlike "_*" } | ForEach-Object { $_.BaseName })
$alleTabellen += (Get-ChildItem $Nachher -Filter "*.tsv" | Where-Object { $_.Name -notlike "_*" } | ForEach-Object { $_.BaseName })
$alleTabellen = $alleTabellen | Sort-Object -Unique

$zusammenfassung = New-Object System.Collections.ArrayList

foreach ($tabelle in $alleTabellen) {
    $pfadV = Join-Path $Vorher "$tabelle.tsv"
    $pfadN = Join-Path $Nachher "$tabelle.tsv"

    $tabV = $null; $tabN = $null
    if (Test-Path $pfadV) { $tabV = Lies-Tabelle $pfadV }
    if (Test-Path $pfadN) { $tabN = Lies-Tabelle $pfadN }

    $spalten = $null
    if ($tabN) { $spalten = $tabN.Spalten } else { $spalten = $tabV.Spalten }

    $pkNamen = @()
    if ($schluesselMap.ContainsKey($tabelle) -and $schluesselMap[$tabelle] -ne "-") {
        $pkNamen = $schluesselMap[$tabelle] -split ","
    }
    $pkIndex = @()
    foreach ($n in $pkNamen) {
        $i = [Array]::IndexOf($spalten, $n)
        if ($i -ge 0) { $pkIndex += $i }
    }

    # Ohne Primaerschluessel: ganze Zeile als Schluessel — dann gibt es nur
    # "neu" und "weg", keine Spaltenaenderung. Ehrlicher als zu raten.
    $ohnePk = ($pkIndex.Count -eq 0)
    if ($ohnePk) { $pkIndex = 0..($spalten.Count - 1) }

    $vorherMap = @{}
    if ($tabV) {
        foreach ($s in $tabV.Saetze) {
            $k = Schluessel-Von $s $pkIndex
            $vorherMap[$k] = $s
        }
    }
    $nachherMap = @{}
    if ($tabN) {
        foreach ($s in $tabN.Saetze) {
            $k = Schluessel-Von $s $pkIndex
            $nachherMap[$k] = $s
        }
    }

    $neu = @($nachherMap.Keys | Where-Object { -not $vorherMap.ContainsKey($_) })
    $weg = @($vorherMap.Keys | Where-Object { -not $nachherMap.ContainsKey($_) })
    $geaendert = New-Object System.Collections.ArrayList
    $nurStempel = 0

    if (-not $ohnePk) {
        foreach ($k in $nachherMap.Keys) {
            if (-not $vorherMap.ContainsKey($k)) { continue }
            $a = $vorherMap[$k]; $b = $nachherMap[$k]
            $unterschiede = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $spalten.Count; $i++) {
                $altWert = "\N"; $neuWert = "\N"
                if ($i -lt $a.Count) { $altWert = $a[$i] }
                if ($i -lt $b.Count) { $neuWert = $b[$i] }
                if ($altWert -cne $neuWert) {
                    [void]$unterschiede.Add([pscustomobject]@{ Spalte = $spalten[$i]; Alt = $altWert; Neu = $neuWert })
                }
            }
            if ($unterschiede.Count -eq 0) { continue }
            $echte = @($unterschiede | Where-Object { $rauschen -notcontains $_.Spalte })
            if ($echte.Count -eq 0) { $nurStempel++; continue }
            [void]$geaendert.Add([pscustomobject]@{ Schluessel = $k; Spalten = $echte })
        }
    }

    if ($neu.Count -eq 0 -and $weg.Count -eq 0 -and $geaendert.Count -eq 0 -and $nurStempel -eq 0) { continue }

    [void]$zusammenfassung.Add([pscustomobject]@{
            Tabelle = $tabelle; Neu = $neu.Count; Weg = $weg.Count
            Geaendert = $geaendert.Count; NurStempel = $nurStempel
        })

    if ($NurZusammenfassung) { continue }

    Schreib ""
    $kopf = "--- $tabelle ---  +$($neu.Count) neu, -$($weg.Count) weg, ~$($geaendert.Count) geaendert"
    if ($nurStempel -gt 0) { $kopf += ", $nurStempel nur Zeitstempel" }
    if ($ohnePk) { $kopf += "  [kein Primaerschluessel — nur neu/weg]" }
    Schreib $kopf "Yellow"

    $gezeigt = 0
    foreach ($k in $neu) {
        if ($gezeigt -ge $Zeilen) { Schreib "  … weitere $($neu.Count - $gezeigt) neue Zeilen" "DarkGray"; break }
        $s = $nachherMap[$k]
        $paare = New-Object System.Collections.ArrayList
        $verschwiegen = 0
        for ($i = 0; $i -lt $spalten.Count; $i++) {
            $w = "\N"
            if ($i -lt $s.Count) { $w = $s[$i] }
            if ($rauschen -contains $spalten[$i]) { continue }
            if (Ist-Leer $w) { $verschwiegen++; continue }
            [void]$paare.Add([pscustomobject]@{ Spalte = $spalten[$i]; Wert = $w })
        }
        Schreib "  + $k" "Green"
        foreach ($p in $paare) { Schreib "      $($p.Spalte) = $($p.Wert)" }
        if ($verschwiegen -gt 0) { Schreib "      ($verschwiegen weitere Spalten unbelegt — -Alles zeigt sie)" "DarkGray" }
        $gezeigt++
    }

    $gezeigt = 0
    foreach ($k in $weg) {
        if ($gezeigt -ge $Zeilen) { Schreib "  … weitere $($weg.Count - $gezeigt) entfernte Zeilen" "DarkGray"; break }
        Schreib "  - $k" "Red"
        $gezeigt++
    }

    $gezeigt = 0
    foreach ($g in $geaendert) {
        if ($gezeigt -ge $Zeilen) { Schreib "  … weitere $($geaendert.Count - $gezeigt) geaenderte Zeilen" "DarkGray"; break }
        Schreib "  ~ $($g.Schluessel)" "Magenta"
        foreach ($u in $g.Spalten) {
            Schreib "      $($u.Spalte): $($u.Alt)  ->  $($u.Neu)"
        }
        $gezeigt++
    }
}

# --- Blobs -------------------------------------------------------------------

$medienV = Join-Path $Vorher "media"
$medienN = Join-Path $Nachher "media"
if ((Test-Path $medienV) -and (Test-Path $medienN)) {
    $hashV = @{}; $groesseV = @{}
    Get-ChildItem $medienV -Filter "*.bin" | ForEach-Object {
        $hashV[$_.BaseName] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $groesseV[$_.BaseName] = $_.Length
    }
    $hashN = @{}; $groesseN = @{}
    Get-ChildItem $medienN -Filter "*.bin" | ForEach-Object {
        $hashN[$_.BaseName] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $groesseN[$_.BaseName] = $_.Length
    }

    $blobMeldungen = New-Object System.Collections.ArrayList
    foreach ($k in $hashN.Keys) {
        if (-not $hashV.ContainsKey($k)) {
            [void]$blobMeldungen.Add("  + $k  $($groesseN[$k]) B")
        } elseif ($hashV[$k] -ne $hashN[$k]) {
            [void]$blobMeldungen.Add("  ~ $k  $($groesseV[$k]) B  ->  $($groesseN[$k]) B")
        }
    }
    foreach ($k in $hashV.Keys) {
        if (-not $hashN.ContainsKey($k)) { [void]$blobMeldungen.Add("  - $k") }
    }

    if ($blobMeldungen.Count -gt 0) {
        Schreib ""
        Schreib "--- PrMedia (Blobs) ---" "Yellow"
        foreach ($m in $blobMeldungen) { Schreib $m }
        [void]$zusammenfassung.Add([pscustomobject]@{
                Tabelle = "PrMedia.Media"; Neu = 0; Weg = 0
                Geaendert = $blobMeldungen.Count; NurStempel = 0
            })
    }
}

# --- Zusammenfassung ---------------------------------------------------------

Schreib ""
Schreib "=== Zusammenfassung ===" "Cyan"
if ($zusammenfassung.Count -eq 0) {
    Schreib "Kein Unterschied." "Gray"
} else {
    Schreib ("{0,-42} {1,5} {2,5} {3,6} {4,8}" -f "Tabelle", "neu", "weg", "geaend", "stempel")
    foreach ($z in ($zusammenfassung | Sort-Object Tabelle)) {
        Schreib ("{0,-42} {1,5} {2,5} {3,6} {4,8}" -f $z.Tabelle, $z.Neu, $z.Weg, $z.Geaendert, $z.NurStempel)
    }
}

if ($Bericht) {
    [IO.File]::WriteAllLines($Bericht, $ausgabe, [Text.UTF8Encoding]::new($false))
    Write-Host ""
    Write-Host "Bericht: $Bericht" -ForegroundColor Green
}
