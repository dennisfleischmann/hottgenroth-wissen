<#
    Dekompiliert alle verwalteten Assemblies aller HSETU-Installationen.

    Der Vorlaeufer bearbeitete nur Energieberater2022. Ueber alle Produkte
    hinweg liegen dieselben Assemblies vielfach vor (DevExpress und die
    Hsetu-Module stecken in fast jedem Produkt), deshalb ist der Lauf
    INHALTSADRESSIERT: dekompiliert wird je SHA-256 genau einmal, unabhaengig
    davon, in wie vielen Produkten die Datei liegt.

    Eine .cs je Assembly statt ilspycmd-Projektstruktur: fuer die Suche ueber
    den Gesamtbestand ist eine Datei je Modul handlicher als zehntausende
    Einzeldateien.

    Reihenfolge nach Nutzen: Energieberater2022 zuerst — damit behalten die
    bereits vorhandenen Dateien ihre Namen und der Bestand bleibt vergleichbar.
    Danach eigener Code der uebrigen Produkte, dann Fremdbibliotheken.

    Ergebnis neben den .cs-Dateien:
      vorkommen.csv   jede gefundene Binaerdatei -> Hash, Produkt, Einstufung
      index.csv       jede eindeutige Assembly   -> Zieldatei, Version, Anzahl Fundorte
      fortschritt.log Gesamtprotokoll, je Arbeiter zusaetzlich ein eigenes Log

    Wiederaufnehmbar: fertige Zieldateien werden uebersprungen.
#>
[CmdletBinding()]
param(
    [string[]] $Basen = @('C:\Program Files\HSETU', 'C:\Program Files (x86)\HSETU', 'C:\ProgramData\HSETU'),
    [string]   $Ziel = 'C:\Projekte_Dev\hsetu-decompiled',
    [int]      $Arbeiter = 6,
    [switch]   $NurPlanen,
    [switch]   $AusInventar
)

$ErrorActionPreference = 'Continue'

$log = Join-Path $Ziel 'fortschritt.log'

function Schreibe([string] $text) {
    $zeile = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $text
    Add-Content -LiteralPath $log -Value $zeile -Encoding utf8
    Write-Host $zeile
}

New-Item -ItemType Directory -Force -Path $Ziel | Out-Null

Schreibe "=== Gesamtlauf ueber alle HSETU-Installationen ==="

# ---------------------------------------------------------------- Inventar --

# Produktreihenfolge bestimmt, welche Variante den unverzierten Dateinamen
# bekommt. Energieberater2022 zuerst: dessen Dateien liegen bereits vor.
function Rang-Produkt([string] $produkt) {
    if ($produkt -eq 'Energieberater2022') { return 0 }
    return 1
}

# Einstufung bestimmt Zielordner und Bearbeitungsreihenfolge.
function Einstufung([string] $name) {
    # Satelliten-Assemblies enthalten nur uebersetzte Zeichenketten, keinen Code —
    # ein Viertel des Gesamtbestands. Sie gehoeren nicht nach eigen/, sonst
    # verwaessern sie genau den Ordner, in dem gesucht wird.
    if ($name -match '\.resources$') { return 'ressourcen' }
    if ($name -match '^(Hsetu|Hstac|Hott)') { return 'eigen' }
    if ($name -match 'Resources?\.|res_|\.Videos\.|\.Images\.') { return 'ressourcen' }
    return 'fremd'
}

function Rang-Gruppe([string] $gruppe) {
    switch ($gruppe) {
        'eigen' { 1 }
        'fremd' { 2 }
        'ressourcen' { 3 }
        default { 4 }
    }
}

$vorkommenDatei = Join-Path $Ziel 'vorkommen.csv'

if ($AusInventar) {

# Aus dem letzten Lauf weiterrechnen: Hashes ueber ~20 GB kosten eine
# Viertelstunde, und an den Dateien aendert sich zwischen zwei Plaenen nichts.
# Die Einstufung wird trotzdem neu bestimmt — sie ist die Stellschraube.
Schreibe "Nutze vorhandenes Inventar: $vorkommenDatei"

$inventar = @(Import-Csv -LiteralPath $vorkommenDatei | ForEach-Object {
    [pscustomobject]@{
        Pfad    = $_.Pfad
        Name    = $_.Name
        Produkt = $_.Produkt
        Groesse = [long] $_.Groesse
        Gruppe  = if ($_.Gruppe -eq 'nativ') { 'nativ' } else { Einstufung $_.Name }
        Version = $_.Version
        Sha256  = $_.Sha256
    }
})

Schreibe "$($inventar.Count) Eintraege uebernommen"

} else {

Schreibe "Suche Binaerdateien ..."

$dateien = foreach ($b in $Basen) {
    if (-not (Test-Path -LiteralPath $b)) { continue }

    foreach ($f in Get-ChildItem -LiteralPath $b -Include *.dll, *.exe -File -Recurse -ErrorAction SilentlyContinue) {
        # Produkt = erster Ordner unterhalb der Basis.
        $rest = $f.FullName.Substring($b.Length).TrimStart('\')
        $produkt = ($rest -split '\\')[0]

        [pscustomobject]@{
            Pfad    = $f.FullName
            Name    = $f.BaseName
            Produkt = $produkt
            Groesse = $f.Length
        }
    }
}

$dateien = @($dateien)
Schreibe "$($dateien.Count) Binaerdateien gefunden"

Schreibe "Bestimme Art und Hash ... (dauert einige Minuten)"

$inventar = foreach ($d in $dateien) {
    $version = $null

    try {
        $an = [System.Reflection.AssemblyName]::GetAssemblyName($d.Pfad)
        $verwaltet = $true
        $version = $an.Version.ToString()
    } catch {
        $verwaltet = $false
    }

    $hash = $null

    try {
        $hash = (Get-FileHash -LiteralPath $d.Pfad -Algorithm SHA256).Hash
    } catch {
        # Gesperrte Datei: ohne Hash keine Deduplizierung, also aussen vor.
        $hash = $null
    }

    [pscustomobject]@{
        Pfad     = $d.Pfad
        Name     = $d.Name
        Produkt  = $d.Produkt
        Groesse  = $d.Groesse
        Gruppe   = if ($verwaltet) { Einstufung $d.Name } else { 'nativ' }
        Version  = $version
        Sha256   = $hash
    }
}

$inventar = @($inventar)

}

$inventar | Select-Object Produkt, Name, Gruppe, Version, Groesse, Sha256, Pfad |
    Sort-Object Produkt, Name |
    Export-Csv $vorkommenDatei -NoTypeInformation -Encoding utf8

$nativ = @($inventar | Where-Object Gruppe -eq 'nativ')
$verwaltet = @($inventar | Where-Object { $_.Gruppe -ne 'nativ' -and $_.Sha256 })
$ohneHash = @($inventar | Where-Object { $_.Gruppe -ne 'nativ' -and -not $_.Sha256 })

Schreibe ("verwaltet: {0} Dateien / {1} eindeutig, nativ: {2}, ohne Hash: {3}" -f
    $verwaltet.Count, (@($verwaltet | Group-Object Sha256).Count), $nativ.Count, $ohneHash.Count)

if ($ohneHash.Count -gt 0) {
    $ohneHash | ForEach-Object { Schreibe "  ohne Hash (gesperrt?): $($_.Pfad)" }
}

# Native Dateien nur protokollieren — ilspycmd kann damit nichts anfangen.
$nativ | Group-Object Sha256 | ForEach-Object {
    $e = $_.Group[0]
    "{0,-42} {1,10:N0} KB  {2}x  {3}" -f $e.Name, ($e.Groesse / 1KB), $_.Count, $e.Produkt
} | Sort-Object | Set-Content (Join-Path $Ziel 'nativ-nicht-dekompilierbar.txt') -Encoding utf8

# ---------------------------------------------------------------- Planung ---

# Je Hash ein Auftrag. Der Vertreter ist die Datei mit dem besten Rang; sein
# Produkt entscheidet, ob er den unverzierten Namen bekommt.
$auftraege = New-Object System.Collections.ArrayList
$vergeben = @{}   # Zielname (klein) -> Hash, zur Kollisionserkennung

$gruppen = $verwaltet | Group-Object Sha256 | ForEach-Object {
    $vertreter = $_.Group | Sort-Object { Rang-Produkt $_.Produkt }, { Rang-Gruppe $_.Gruppe }, Produkt | Select-Object -First 1

    [pscustomobject]@{
        Sha256    = $_.Name
        Vertreter = $vertreter
        Anzahl    = $_.Count
        Produkte  = (($_.Group | Select-Object -ExpandProperty Produkt -Unique | Sort-Object) -join ';')
    }
}

$gruppen = @($gruppen | Sort-Object { Rang-Produkt $_.Vertreter.Produkt }, { Rang-Gruppe $_.Vertreter.Gruppe }, { $_.Vertreter.Groesse })

foreach ($g in $gruppen) {
    $v = $g.Vertreter
    $ordner = Join-Path $Ziel $v.Gruppe

    # Gleicher Name, anderer Inhalt: die zweite Fassung bekommt den Hash
    # angehaengt. Welche welche ist, steht in index.csv.
    $basis = $v.Name
    $schluessel = "$($v.Gruppe)/$($basis.ToLowerInvariant())"

    if ($vergeben.ContainsKey($schluessel)) {
        $basis = "{0}~{1}" -f $v.Name, $g.Sha256.Substring(0, 8).ToLowerInvariant()
    } else {
        $vergeben[$schluessel] = $g.Sha256
    }

    $zielDatei = Join-Path $ordner ($basis + '.cs')

    [void] $auftraege.Add([pscustomobject]@{
        Sha256   = $g.Sha256
        Name     = $v.Name
        Version  = $v.Version
        Gruppe   = $v.Gruppe
        Produkt  = $v.Produkt
        Produkte = $g.Produkte
        Anzahl   = $g.Anzahl
        Quelle   = $v.Pfad
        ZielDatei = $zielDatei
    })
}

$auftraege | Select-Object Name, Version, Gruppe, ZielDatei, Anzahl, Produkt, Produkte, Sha256, Quelle |
    Export-Csv (Join-Path $Ziel 'index.csv') -NoTypeInformation -Encoding utf8

# Bereits erledigte ueberspringen — der Lauf ist damit wiederaufnehmbar.
$offen = @($auftraege | Where-Object {
    -not ((Test-Path -LiteralPath $_.ZielDatei) -and (Get-Item -LiteralPath $_.ZielDatei).Length -gt 0)
})

Schreibe ("{0} eindeutige Assemblies, davon {1} bereits vorhanden, {2} offen" -f
    $auftraege.Count, ($auftraege.Count - $offen.Count), $offen.Count)

foreach ($gr in @('eigen', 'fremd', 'ressourcen')) {
    $n = @($offen | Where-Object Gruppe -eq $gr).Count
    if ($n) { Schreibe "  offen in ${gr}: $n" }
}

if ($offen.Count -eq 0) {
    Schreibe 'Nichts zu tun.'
    return
}

$auftragsdatei = Join-Path $Ziel 'auftrag.csv'
$offen | Select-Object Sha256, Name, Gruppe, Quelle, ZielDatei |
    Export-Csv $auftragsdatei -NoTypeInformation -Encoding utf8

if ($NurPlanen) {
    Schreibe "Nur geplant. Auftrag: $auftragsdatei"
    return
}

# --------------------------------------------------------------- Ausfuehren -

foreach ($gr in @('eigen', 'fremd', 'ressourcen')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Ziel $gr) | Out-Null
}

$teilSkript = Join-Path $PSScriptRoot 'dekompiliere-teil.ps1'
$n = [Math]::Min($Arbeiter, $offen.Count)

Schreibe "Starte $n Arbeiter"

$prozesse = @()

for ($k = 0; $k -lt $n; $k++) {
    $prozesse += Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$teilSkript`"",
        '-Auftrag', "`"$auftragsdatei`"", '-Ziel', "`"$Ziel`"", '-Teil', $k, '-Von', $n
    )
}

Schreibe ("Arbeiter laufen: {0}" -f (($prozesse | Select-Object -ExpandProperty Id) -join ', '))

$prozesse | Wait-Process

$fertig = @($auftraege | Where-Object {
    (Test-Path -LiteralPath $_.ZielDatei) -and (Get-Item -LiteralPath $_.ZielDatei).Length -gt 0
})

$mb = [math]::Round((Get-ChildItem $Ziel -Filter *.cs -Recurse | Measure-Object Length -Sum).Sum / 1MB, 0)

Schreibe ("Fertig. {0}/{1} Assemblies liegen vor, {2} MB Quelltext." -f $fertig.Count, $auftraege.Count, $mb)

$fehlend = @($auftraege | Where-Object { $_.ZielDatei -notin $fertig.ZielDatei })

if ($fehlend.Count) {
    Schreibe "$($fehlend.Count) ohne Ergebnis:"
    $fehlend | ForEach-Object { Schreibe "  $($_.Name)  ($($_.Produkt))" }
}
