# Setzt ein beliebiges Feld fuer alle Bauteile einer Art in einer Variante.
#
# Verallgemeinerung von saniere.ps1, das dasselbe nur fuer SANK_ZAHL tut.
# Gebraucht zum Beispiel fuer REDFAKTOR: der Abminderungsfaktor eines Bauteils
# gegen Erdreich oder unbeheizte Raeume steht dort - und NICHT im Rechenmodell.
# Wer ihn im Blob setzt (enEnEV09ConstructionElementType), verliert die Aenderung
# beim naechsten Oeffnen: die Software leitet den Bauteiltyp aus dieser Tabelle
# ab und schreibt den Blob neu.
#
# Legt das Feld an, wenn es fehlt. Weil sich dabei die Satzlaenge aendert, wird
# der gesamte Datenteil neu geschrieben.
#
# Kennzeichen: DA Dach | WA Aussenwand | FA Fenster | TA Tuer
#              BA Bodenplatte | BE Kellerdecke | WE Wand zu unbeheizt | WK Wand kalt
#
#   .\setze-bauteilfeld.ps1 -Ordner .\entpackt -Proj 6 -Kennzeichen BA `
#                           -Feld REDFAKTOR -Wert 0.8

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [Parameter(Mandatory)] [int]    $Proj,
    [Parameter(Mandatory)] [string] $Kennzeichen,
    [Parameter(Mandatory)] [string] $Feld,
    [Parameter(Mandatory)] $Wert,
    [switch] $Vorschau
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$datei = Join-Path $Ordner 'TableHuellfl.BDExit'
$b = [System.IO.File]::ReadAllBytes($datei)
$k = BdeKopf $b

if (-not ($k.Felder | Where-Object { $_.Name -eq $Feld })) {
    throw ("Feld '$Feld' gibt es in TableHuellfl nicht. Vorhanden: " +
           (($k.Felder | ForEach-Object { $_.Name }) -join ', '))
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
    $setze = @{}
    if ($gilt) {
        $setze[$Feld] = $Wert
        $treffer += [pscustomobject]@{
            Id = Wert $s 'HUELL_ID'; Bez = Wert $s 'BAUTEILBEZ'
            Flaeche = [math]::Round((Wert $s 'FLAECHE'), 2)
            Vorher = $(if (Da $s $Feld) { Wert $s $Feld } else { 'fehlt' })
        }
    }
    $strom.AddRange([byte[]] (BdeSchreib $b $k $s $setze))
}

if (-not $treffer) { throw "kein Bauteil '$Kennzeichen' in PROJ_ID $Proj" }

"{0} Bauteile '{1}' in PROJ_ID {2}: {3} = {4}" -f $treffer.Count, $Kennzeichen, $Proj, $Feld, $Wert
$treffer | ForEach-Object { "  HUELL_ID {0,4}  {1,-44} {2,7} m²   {3} -> {4}" -f $_.Id, $_.Bez, $_.Flaeche, $_.Vorher, $Wert }

if ($Vorschau) { "Vorschau - nichts geschrieben"; return }

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
        if (-not (Da $r $Feld)) { throw "Gegenprobe: $Feld fehlt an HUELL_ID $(Wert $r 'HUELL_ID')" }
        if ("$(Wert $r $Feld)" -ne "$Wert") { throw "Gegenprobe: $(Wert $r $Feld) statt $Wert" }
    }
    $n++; $o = $r.Ende
}
if ($n -ne $k2.Satzzahl) { throw "Gegenprobe: $n statt $($k2.Satzzahl) Saetze" }
"Tabelle {0} -> {1} Bytes, Satzzahl unveraendert {2}, Gegenprobe bestanden" -f $b.Length, $b2.Length, $k2.Satzzahl
