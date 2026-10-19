# Setzt SANK_ZAHL fuer alle Bauteile einer Art in einer vorhandenen Variante.
#
# Anders als sanieren.ps1 (fester Abstand hinter dem Bauteilnamen) arbeitet das
# hier feldweise. Nur so lassen sich Bauteile sanieren, bei denen SANK_ZAHL
# noch gar nicht existiert - und das ist der Normalfall: ein unsaniertes
# Bauteil fuehrt das Feld nicht mit.
#
# Weil sich dabei die Satzlaenge aendert, wird der gesamte Datenteil der
# Tabelle neu geschrieben, nicht an Ort und Stelle geflickt.
#
# Kennzeichen: DA Dach | WA Aussenwand | FA Fenster | TA Tuer
#              BA Bodenplatte | BE Kellerdecke | WE Wand zu unbeheizt | WK Wand kalt

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [Parameter(Mandatory)] [int]    $Proj,
    [Parameter(Mandatory)] [string] $Kennzeichen,
    [Parameter(Mandatory)] [double] $Wert
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$datei = Join-Path $Ordner 'TableHuellfl.BDExit'
$b = [System.IO.File]::ReadAllBytes($datei)
$k = BdeKopf $b

$saetze = @(); $o = $k.Daten
while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $saetze += $r; $o = $r.Ende }
if ($saetze.Count -ne $k.Satzzahl) { throw "$($saetze.Count) Saetze gelesen, Kopf sagt $($k.Satzzahl)" }
function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }

$strom = New-Object System.Collections.Generic.List[byte]
$trefferliste = @()
foreach ($s in $saetze) {
    $treffer = (Wert $s 'PROJ_ID') -eq $Proj -and (Wert $s 'KENNZEICHEN') -eq $Kennzeichen
    $setze = @{}
    if ($treffer) {
        $setze['SANK_ZAHL'] = $Wert
        # REDFAKTOR gehoert dazu - das saniert erfasste Bauteil traegt beide.
        if (-not ($s.Werte | Where-Object { $_.Name -eq 'REDFAKTOR' -and $_.Da })) { $setze['REDFAKTOR'] = 1.0 }
        $trefferliste += [pscustomobject]@{
            Id = Wert $s 'HUELL_ID'; Bez = Wert $s 'BAUTEILBEZ'
            Flaeche = [math]::Round((Wert $s 'FLAECHE'),2); K = Wert $s 'K_ZAHL'
            Vorher = $(if (($s.Werte | Where-Object Name -eq 'SANK_ZAHL').Da) { Wert $s 'SANK_ZAHL' } else { 'fehlt' })
        }
    }
    $strom.AddRange((BdeSchreib $b $k $s $setze))
}

if (-not $trefferliste) { throw "kein Bauteil '$Kennzeichen' in PROJ_ID $Proj gefunden" }

$kopf = New-Object byte[] $k.Daten
[Array]::Copy($b, 0, $kopf, 0, $k.Daten)
[System.IO.File]::WriteAllBytes($datei, ($kopf + $strom.ToArray()))

"{0} Bauteile '{1}' in PROJ_ID {2} auf SANK_ZAHL {3} gesetzt" -f $trefferliste.Count, $Kennzeichen, $Proj, $Wert
$trefferliste | ForEach-Object { "  HUELL_ID {0,3}  {1,-46} {2,7} m²  U {3}  ->  {4}" -f $_.Id, $_.Bez, $_.Flaeche, $_.K, $Wert }
"Tabelle {0} -> {1} Bytes, Satzzahl unveraendert {2}" -f $b.Length, ($k.Daten + $strom.Count), $k.Satzzahl
