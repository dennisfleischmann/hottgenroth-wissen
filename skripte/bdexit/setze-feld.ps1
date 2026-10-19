# Setzt ein einzelnes Feld in einer .BDExit-Tabelle - fuer eine Variante oder
# fuer alle.
#
# Gedacht fuer Angaben, die zum Gebaeude gehoeren und deshalb in JEDER Variante
# gleich stehen muessen: Baujahr, Liegenschaft, Hoehe ueber NN. Wer sie nur in
# einer Variante nachtraegt, bekommt einen Fahrplan, dessen Stufen sich in einer
# Eigenschaft unterscheiden, die sich gar nicht saniert.
#
# Legt das Feld an, wenn es im Satz noch fehlt - das ist der Normalfall bei
# nie ausgefuellten Angaben, und dabei aendert sich die Satzlaenge. Deshalb
# wird der gesamte Datenteil neu geschrieben, nicht an Ort und Stelle geflickt.
#
#   .\setze-feld.ps1 -Ordner .\entpackt -Tabelle TableHausDat -Feld BAUJAHR -Wert 1977
#   .\setze-feld.ps1 -Ordner .\entpackt -Tabelle TableProjekt -Feld LIEGENSCHAFT_ORT `
#                    -Wert 'Musterstadt' -Proj 2
#   .\setze-feld.ps1 ... -Vorschau

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [Parameter(Mandatory)] [string] $Tabelle,
    [Parameter(Mandatory)] [string] $Feld,
    [Parameter(Mandatory)] $Wert,
    [int[]] $Proj,
    [switch] $Vorschau
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$datei = Join-Path $Ordner "$Tabelle.BDExit"
if (-not (Test-Path $datei)) { throw "$datei gibt es nicht" }

$b = [System.IO.File]::ReadAllBytes($datei)
$k = BdeKopf $b

$def = @($k.Felder | Where-Object { $_.Name -eq $Feld })
if (-not $def) {
    throw ("Feld '$Feld' gibt es in $Tabelle nicht. Vorhanden: " +
           (($k.Felder | ForEach-Object { $_.Name }) -join ', '))
}

$saetze = @(); $o = $k.Daten
while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $saetze += $r; $o = $r.Ende }
if ($saetze.Count -ne $k.Satzzahl) { throw "$Tabelle : $($saetze.Count) Saetze, Kopf sagt $($k.Satzzahl)" }

# Bezug herleiten, nicht raten - dieselbe Regel wie in variante-bauen.ps1.
$bezug = [string] ($k.Felder | Where-Object { $_.Name -eq 'PROJ_ID' -or $_.Name -eq 'ProjektID' } |
           ForEach-Object { $_.Name } | Select-Object -First 1)
if (-not $bezug) { $bezug = [string] $k.Felder[0].Name }

function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }
function Da($r, $n) { ($r.Werte | Where-Object Name -eq $n).Da }

$strom = New-Object System.Collections.Generic.List[byte]
$treffer = @()
foreach ($s in $saetze) {
    $nr = Wert $s $bezug
    $gilt = (-not $Proj) -or ($Proj -contains $nr)
    $setze = @{}
    if ($gilt) {
        $setze[$Feld] = $Wert
        $treffer += [pscustomobject]@{
            Bezug = $nr
            Vorher = $(if (Da $s $Feld) { Wert $s $Feld } else { 'fehlt' })
        }
    }
    $strom.AddRange([byte[]] (BdeSchreib $b $k $s $setze))
}

if (-not $treffer) { throw "kein Satz getroffen (Bezug $bezug, gesucht: $($Proj -join ', '))" }

# ${bezug} statt $bezug: ein Doppelpunkt hinter einem Variablennamen liest
# PowerShell als Laufwerksangabe ($bezug: wird zu "Laufwerk bezug").
"$Tabelle.$Feld = $Wert   (${bezug}: $(($treffer | ForEach-Object { $_.Bezug }) -join ', '))"
$treffer | ForEach-Object { "  {0,-6} vorher {1}" -f $_.Bezug, $_.Vorher }

if ($Vorschau) { "Vorschau - nichts geschrieben"; return }

$kopf = New-Object byte[] $k.Daten
[Array]::Copy($b, 0, $kopf, 0, $k.Daten)
[System.IO.File]::WriteAllBytes($datei, ($kopf + $strom.ToArray()))

# Gegenprobe am geschriebenen Stand: vollstaendig lesbar, Satzzahl unveraendert,
# und der Wert steht wirklich drin.
$b2 = [System.IO.File]::ReadAllBytes($datei)
$k2 = BdeKopf $b2
$s2 = @(); $o = $k2.Daten
while ($o -lt $b2.Length) { $r = BdeLies $b2 $k2 $o -1; $s2 += $r; $o = $r.Ende }
if ($s2.Count -ne $saetze.Count) { throw "Gegenprobe: $($s2.Count) statt $($saetze.Count) Saetze" }
foreach ($s in $s2) {
    $nr = Wert $s $bezug
    if ((-not $Proj) -or ($Proj -contains $nr)) {
        if (-not (Da $s $Feld)) { throw "Gegenprobe: $Feld fehlt in Satz $nr" }
        if ("$(Wert $s $Feld)" -ne "$Wert") { throw "Gegenprobe: Satz $nr traegt $(Wert $s $Feld) statt $Wert" }
    }
}
"Tabelle {0} -> {1} Bytes, Satzzahl unveraendert {2}, Gegenprobe bestanden" -f $b.Length, $b2.Length, $k2.Satzzahl
