# Entfernt eine oder mehrere Varianten vollstaendig aus eberater.zip.
#
# Gegenstueck zu variante-bauen.ps1 und nach derselben Regel gebaut: je Tabelle
# wird der Bezug hergeleitet, nicht geraten.
#
#   Bezug   heisst ein Feld PROJ_ID oder ProjektID -> dieses Feld,
#           sonst ist das ERSTE Feld selbst die Projektnummer.
#
# Geloescht wird in ALLEN Tabellen des Ordners. Eine Variante, die nur aus
# TableProjekt verschwindet, laesst ihre Bauteile, ihre Anlagentechnik und ihren
# IBP-Blob als Waisen zurueck - der Container waere in sich unstimmig.
#
# Der Satzzaehler an Offset 14 wird mitgefuehrt. AUTOINCVALUE bleibt stehen:
# er ist eine Hochwassermarke und darf nie sinken, sonst werden Schluessel ein
# zweites Mal vergeben.
#
#   .\variante-loeschen.ps1 -Ordner .\entpackt -Proj 3,4,5,6
#   .\variante-loeschen.ps1 -Ordner .\entpackt -Proj 3 -Vorschau

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [Parameter(Mandatory)] [int[]]  $Proj,
    [switch] $Vorschau
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

function Tabelle([string] $Datei) {
    $b = [System.IO.File]::ReadAllBytes($Datei)
    $k = BdeKopf $b
    $s = @(); $o = $k.Daten
    while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $s += $r; $o = $r.Ende }
    if ($s.Count -ne $k.Satzzahl) { throw "$(Split-Path $Datei -Leaf): $($s.Count) Saetze gelesen, Kopf sagt $($k.Satzzahl)" }

    $bezug = [string] ($k.Felder | Where-Object { $_.Name -eq 'PROJ_ID' -or $_.Name -eq 'ProjektID' } |
               ForEach-Object { $_.Name } | Select-Object -First 1)
    if (-not $bezug) { $bezug = [string] $k.Felder[0].Name }

    [pscustomobject]@{ Bytes = $b; Kopf = $k; Saetze = $s; Datei = $Datei; Bezug = $bezug }
}
function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }

$tabellen = @{}
foreach ($f in Get-ChildItem $Ordner -Filter *.BDExit) { $tabellen[$f.BaseName] = Tabelle $f.FullName }

# Der Ist-Zustand ist die Variante mit der kleinsten Nummer. Ohne ihn haette der
# Container keinen Ausgangszustand mehr, aus dem sich Varianten ableiten lassen -
# und die Software steht vor einem Projekt ohne Gebaeude.
$tp = $tabellen['TableProjekt']
if (-not $tp) { throw "TableProjekt fehlt in $Ordner" }
$alle = @($tp.Saetze | ForEach-Object { Wert $_ $tp.Bezug })
$bleibt = @($alle | Where-Object { $Proj -notcontains $_ })
if (-not $bleibt) { throw "das wuerde alle $($alle.Count) Varianten loeschen - mindestens der Ist-Zustand muss bleiben" }

$fehlt = @($Proj | Where-Object { $alle -notcontains $_ })
if ($fehlt) { throw "Variante(n) $($fehlt -join ', ') gibt es nicht (vorhanden: $($alle -join ', '))" }

$ist = ($alle | Measure-Object -Minimum).Minimum
if ($Proj -contains $ist) { Write-Warning "Variante $ist ist die kleinste Nummer und damit vermutlich der Ist-Zustand" }

"loesche Variante(n) {0}   es bleiben: {1}" -f ($Proj -join ', '), ($bleibt -join ', ')
foreach ($s in $tp.Saetze) {
    $n = Wert $s $tp.Bezug
    if ($Proj -contains $n) { "  {0,-3} '{1}'" -f $n, (Wert $s 'VarianteBez') }
}
""
"Tabelle           Bezug          vorher  entfernt  nachher"

foreach ($n in ($tabellen.Keys | Sort-Object)) {
    $t = $tabellen[$n]
    $behalten = @($t.Saetze | Where-Object { $Proj -notcontains (Wert $_ $t.Bezug) })
    $weg = $t.Saetze.Count - $behalten.Count

    $strom = New-Object System.Collections.Generic.List[byte]
    foreach ($s in $behalten) { $strom.AddRange([byte[]] (BdeSchreib $t.Bytes $t.Kopf $s @{})) }

    $kopf = New-Object byte[] $t.Kopf.Daten
    [Array]::Copy($t.Bytes, 0, $kopf, 0, $t.Kopf.Daten)
    [BitConverter]::GetBytes([uint16] $behalten.Count).CopyTo($kopf, 14)
    if (-not $Vorschau) { [System.IO.File]::WriteAllBytes($t.Datei, ($kopf + $strom.ToArray())) }

    "{0,-16} {1,-13} {2,7}  {3,8}  {4,7}" -f $n, $t.Bezug, $t.Saetze.Count, $weg, $behalten.Count
}

if ($Vorschau) { ""; "Vorschau - nichts geschrieben"; return }

""
"Gegenprobe:"
foreach ($f in Get-ChildItem $Ordner -Filter *.BDExit | Sort-Object Name) {
    $t = Tabelle $f.FullName
    $rest = @($t.Saetze | Where-Object { $Proj -contains (Wert $_ $t.Bezug) }).Count
    if ($rest) { throw "$($f.BaseName): $rest Saetze der geloeschten Varianten sind noch da" }
    "  {0,-16} {1,8} B  {2,4} Saetze  vollstaendig lesbar" -f $f.BaseName, $t.Bytes.Length, $t.Saetze.Count
}
