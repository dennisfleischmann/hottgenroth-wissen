# Entfernt Felder aus den Bauteilsaetzen einer Variante - nicht nullen, ENTFERNEN.
#
# WOZU
# setze-massnahme.ps1 -Loeschen setzt die acht Felder einer Massnahme auf 0 bzw.
# Leerstring, laesst sie aber im Satz stehen. Das genuegt nicht:
#
#   - uwerte-uebernehmen.ps1 nimmt "SANK_ZAHL wenn vorhanden" woertlich und
#     traegt dann U = 0,000 ins Rechenmodell ein.
#   - Ein Bauteil gilt der Software als saniert, sobald SANK_ZAHL existiert -
#     die Variante zeigt also eine Sanierung auf U 0,00.
#
# Gemessen am Ist-Zustand, den die Software selbst schreibt: ein Bauteil ohne
# Massnahme fuehrt die acht Felder GAR NICHT.
#
# WIE
# Die Anwesenheitskarte am Satzanfang traegt zwei Bit je Feld: 0 = steht im
# Satz, sonst fehlt es. Die Software schreibt fuer ein fehlendes Feld die 2 -
# nachgemessen an TableHuellfl der Variante 2 in V4DZX_Nadine Klenke.
# Weil dabei Satzlaengen schrumpfen, wird der gesamte Datenteil neu geschrieben.
#
#   .\entferne-bauteilfeld.ps1 -Ordner .\arbeit -Proj 3 -Kennzeichen OG -Massnahme
#   .\entferne-bauteilfeld.ps1 -Ordner .\arbeit -Proj 3 -Kennzeichen OG `
#                              -Felder SANDURCHLASSGR -Vorschau
#
# Danach IMMER uwerte-uebernehmen.ps1 fuer dieselbe Variante laufen lassen -
# sonst rechnet der Blob weiter mit dem sanierten Wert.

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [Parameter(Mandatory)] [int]    $Proj,
    [Parameter(Mandatory)] [string] $Kennzeichen,
    [string[]] $Felder,
    [switch]   $Massnahme,          # die acht Felder einer Sanierungsmassnahme
    [switch]   $Vorschau
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$ACHT = @('SANBEZ','SANK_ZAHL','SANKOSTEN','SANKOSTENQM',
          'SANKOSTEN_EE','SANKOSTENQM_EE','SANDICKE','SANLAMBDA')
if ($Massnahme) { $Felder = @($Felder) + $ACHT | Where-Object { $_ } | Select-Object -Unique }
if (-not $Felder) { throw '-Felder oder -Massnahme angeben.' }

$datei = Join-Path $Ordner 'TableHuellfl.BDExit'
if (-not (Test-Path $datei)) { throw "$datei gibt es nicht" }

$b = [System.IO.File]::ReadAllBytes($datei)
$k = BdeKopf $b
$bekannt = $k.Felder | ForEach-Object { $_.Name }
foreach ($f in $Felder) {
    if ($bekannt -notcontains $f) { throw "Feld '$f' gibt es in TableHuellfl nicht." }
}

# Satz neu bauen und dabei Felder als FEHLEND markieren.
function BdeSchreibOhne([byte[]] $b, $k, $gelesen, [string[]] $Weg) {
    $karte = New-Object byte[] $k.Vorspann
    [Array]::Copy($b, $gelesen.Satz, $karte, 0, $k.Vorspann)
    $strom = New-Object System.Collections.Generic.List[byte]
    foreach ($w in $gelesen.Werte) {
        $f = $k.Felder[$w.Nr]
        if ($Weg -contains $f.Name) {
            $i  = $w.Nr
            $bi = 1 + [math]::Floor($i / 4)
            $sh = ($i % 4) * 2
            $karte[$bi] = [byte] ((($karte[$bi] -band (-bnot (3 -shl $sh))) -bor (2 -shl $sh)) -band 0xFF)
            continue                                  # Bytes weglassen
        }
        if (-not $w.Da) { continue }
        $strom.AddRange($w.Roh)
    }
    return ,[byte[]] ($karte + $strom.ToArray())
}

$saetze = @(); $o = $k.Daten
while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $saetze += $r; $o = $r.Ende }
if ($saetze.Count -ne $k.Satzzahl) { throw "$($saetze.Count) Saetze gelesen, Kopf sagt $($k.Satzzahl)" }

function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }
function Da($r, $n) { ($r.Werte | Where-Object Name -eq $n).Da }

$strom = New-Object System.Collections.Generic.List[byte]
$treffer = @()
foreach ($s in $saetze) {
    $gilt = (Wert $s 'PROJ_ID') -eq $Proj -and (Wert $s 'KENNZEICHEN') -eq $Kennzeichen
    if ($gilt) {
        $hatte = @($Felder | Where-Object { Da $s $_ })
        $treffer += [pscustomobject]@{
            Id = Wert $s 'HUELL_ID'; Bez = Wert $s 'BAUTEILBEZ'; Hatte = $hatte
        }
        $strom.AddRange([byte[]] (BdeSchreibOhne $b $k $s $Felder))
    } else {
        $strom.AddRange([byte[]] (BdeSchreib $b $k $s @{}))
    }
}

if (-not $treffer) { throw "kein Bauteil '$Kennzeichen' in PROJ_ID $Proj" }

"{0} Bauteile '{1}' in PROJ_ID {2}: {3} Feld(er) entfernen" -f $treffer.Count, $Kennzeichen, $Proj, $Felder.Count
$treffer | ForEach-Object {
    "  HUELL_ID {0,4}  {1,-46} vorhanden: {2}" -f $_.Id, $_.Bez,
        $(if ($_.Hatte) { $_.Hatte -join ', ' } else { '(keines)' })
}

if ($Vorschau) { 'Vorschau - nichts geschrieben'; return }

$kopf = New-Object byte[] $k.Daten
[Array]::Copy($b, 0, $kopf, 0, $k.Daten)
[System.IO.File]::WriteAllBytes($datei, ($kopf + $strom.ToArray()))

# Gegenprobe am geschriebenen Stand
$b2 = [System.IO.File]::ReadAllBytes($datei)
$k2 = BdeKopf $b2
$n = 0; $o = $k2.Daten
while ($o -lt $b2.Length) {
    $r = BdeLies $b2 $k2 $o -1
    if ((Wert $r 'PROJ_ID') -eq $Proj -and (Wert $r 'KENNZEICHEN') -eq $Kennzeichen) {
        foreach ($f in $Felder) {
            if (Da $r $f) { throw "Gegenprobe: $f steht noch an HUELL_ID $(Wert $r 'HUELL_ID')" }
        }
    }
    $n++; $o = $r.Ende
}
if ($n -ne $k2.Satzzahl) { throw "Gegenprobe: $n statt $($k2.Satzzahl) Saetze" }
"Tabelle {0} -> {1} Bytes, Satzzahl unveraendert {2}, Gegenprobe bestanden" -f $b.Length, $b2.Length, $k2.Satzzahl
