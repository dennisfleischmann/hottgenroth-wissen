# New-Satteldach.ps1 -- ein vollstaendiges Satteldach ueber einem Grundriss
#
# New-Dach.ps1 schreibt EINE Flaeche. Dieses Skript rechnet aus, welche Flaechen
# ein Satteldach braucht, und ruft es dafuer auf. Zwei Grundrissformen:
#
#   Rechteck (4 Ecken)  -> 2 Flaechen, ein First, Giebel an beiden Enden
#   L-Form   (6 Ecken)  -> 4 Flaechen, zwei Firste, Giebel an den beiden
#                          Schenkelenden, dazwischen Kehle und Grat
#
# DIE REGEL, DIE MAN NICHT UEBERSEHEN DARF
# Bei einer L-Form sind die Schenkel verschieden breit. Mit derselben Neigung
# laegen die beiden Firste dann verschieden hoch, und das Dach haette einen
# Versatz. Damit sie sich treffen, wird EINE Firstueberhoehung fuer beide
# festgelegt und die Neigung je Schenkel daraus gerechnet:
#
#   Neigung = atan(Firstueberhoehung / halbe Schenkelbreite)
#
# Beim erprobten Beispiel: Riegel 6 m tief (Halbspanne 3), Fluegel 8 m breit
# (Halbspanne 4), Ueberhoehung 3 m -> 45 Grad und 36,87 Grad, First einheitlich
# 3 m ueber der Traufe.
#
# KEHLE UND GRAT
# Beide laufen vom Firstknoten aus, und beide muessen nicht extra angegeben
# werden: sie ergeben sich, weil die Umrisse der vier Flaechen dort aneinander
# stossen. Die Kehle liegt an der einspringenden Ecke, der Grat an der
# gegenueberliegenden Aussenecke. HottCAD schneidet selbst -- <intersections>
# bleibt leer, das ist in allen 53 gemessenen Daechern so.
#
# ERPROBUNGSSTAND
# Die Rechnung ist gegen ein in der Oberflaeche bestaetigtes L-Dach geprueft:
# sie liefert exakt dieselben sechzehn Punkte. Der Rechteckfall folgt derselben
# Formel mit nur einem Schenkel, ist aber noch nicht in der Software gesehen.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Geschoss,
    # Aeussere Kontur, "x1,y1;x2,y2;..." -- 4 Ecken (Rechteck) oder 6 (L-Form).
    [Parameter(Mandatory = $true)][string]$Grundriss,
    # Hoehe des Firsts UEBER der Traufe. 0 = automatisch: halbe Breite des
    # schmaleren Schenkels, was dort 45 Grad ergibt.
    [double]$Firsthoehe = 0,
    # Traufhoehe ueber der Geschossebene. 0 = Traufe auf Geschossebene.
    [double]$Hoehe1 = 0,
    [double]$Dicke = 0.25,
    # Nur beim Rechteck: Firstrichtung. Leer = laengs der laengeren Seite.
    [ValidateSet('', 'OW', 'NS')][string]$First = '',
    [string]$VorlageDatenbank = '',
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
# Einmal hier pruefen; die Einzelaufrufe von New-Dach.ps1 verzichten dann darauf,
# damit die Meldung nicht viermal kommt. Ein Probelauf schreibt nichts und
# braucht die Pruefung nicht -- so laesst sich rechnen, waehrend die Software
# offen ist, und das ist genau dann nuetzlich, wenn man etwas nachsehen will.
if (-not $OhneSoftwarepruefung -and -not $Probelauf) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}
$inv = [Globalization.CultureInfo]::InvariantCulture
function Z([double]$w) { $w.ToString('R', $inv) }
function Pkt($a) { (Z $a[0]) + ',' + (Z $a[1]) }

$ecken = @($Grundriss -split ';' | ForEach-Object {
    $q = $_ -split ','
    if ($q.Count -ne 2) { throw "Grundrisspunkt '$_' muss die Form x,y haben." }
    , @([double]::Parse($q[0].Trim(), $inv), [double]::Parse($q[1].Trim(), $inv))
})
if ($ecken.Count -ne 4 -and $ecken.Count -ne 6) {
    throw "Dieses Skript kann Rechtecke (4 Ecken) und L-Formen (6 Ecken). Fuer andere Formen die Flaechen einzeln mit New-Dach.ps1 setzen."
}

$xmin = ($ecken | ForEach-Object { $_[0] } | Measure-Object -Minimum).Minimum
$xmax = ($ecken | ForEach-Object { $_[0] } | Measure-Object -Maximum).Maximum
$ymin = ($ecken | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum
$ymax = ($ecken | ForEach-Object { $_[1] } | Measure-Object -Maximum).Maximum
$eps = 1e-6

$flaechen = @()   # je Eintrag: Name, Traufe (2 Punkte), Umriss (Punkte), Neigung

if ($ecken.Count -eq 4) {
    # ---- Rechteck: ein First, zwei Flaechen -------------------------------
    $laengsOW = if ($First) { $First -eq 'OW' } else { ($xmax - $xmin) -ge ($ymax - $ymin) }
    if ($laengsOW) {
        $halb = ($ymax - $ymin) / 2
        $h = if ($Firsthoehe -gt 0) { $Firsthoehe } else { $halb }
        $yr = ($ymin + $ymax) / 2
        $n = [Math]::Atan2($h, $halb) * 180 / [Math]::PI
        $flaechen += @{ Name = 'Sued'; Neigung = $n
                        Traufe = @(@($xmin, $ymin), @($xmax, $ymin))
                        Umriss = @(@($xmin, $ymin), @($xmax, $ymin), @($xmax, $yr), @($xmin, $yr)) }
        $flaechen += @{ Name = 'Nord'; Neigung = $n
                        Traufe = @(@($xmax, $ymax), @($xmin, $ymax))
                        Umriss = @(@($xmin, $ymax), @($xmax, $ymax), @($xmax, $yr), @($xmin, $yr)) }
    } else {
        $halb = ($xmax - $xmin) / 2
        $h = if ($Firsthoehe -gt 0) { $Firsthoehe } else { $halb }
        $xr = ($xmin + $xmax) / 2
        $n = [Math]::Atan2($h, $halb) * 180 / [Math]::PI
        $flaechen += @{ Name = 'West'; Neigung = $n
                        Traufe = @(@($xmin, $ymin), @($xmin, $ymax))
                        Umriss = @(@($xmin, $ymin), @($xmin, $ymax), @($xr, $ymax), @($xr, $ymin)) }
        $flaechen += @{ Name = 'Ost'; Neigung = $n
                        Traufe = @(@($xmax, $ymax), @($xmax, $ymin))
                        Umriss = @(@($xmax, $ymin), @($xmax, $ymax), @($xr, $ymax), @($xr, $ymin)) }
    }
} else {
    # ---- L-Form -----------------------------------------------------------
    #
    # Statt vier Lagen der Einbuchtung einzeln zu behandeln, wird der Grundriss
    # so gespiegelt, dass die Einbuchtung immer NORDOSTEN liegt. Gerechnet wird
    # nur dieser eine Fall, danach wird zurueckgespiegelt. Weniger Code, und
    # jeder Zweig ist derselbe erprobte.
    $fehlt = $null
    foreach ($k in @(@($xmin, $ymin), @($xmax, $ymin), @($xmax, $ymax), @($xmin, $ymax))) {
        $da = $false
        foreach ($e in $ecken) { if ([Math]::Abs($e[0] - $k[0]) -lt $eps -and [Math]::Abs($e[1] - $k[1]) -lt $eps) { $da = $true } }
        if (-not $da) { $fehlt = $k }
    }
    if ($null -eq $fehlt) { throw "Das ist keine L-Form: alle vier Eckpunkte des umschliessenden Rechtecks sind belegt." }
    $spiegelX = [Math]::Abs($fehlt[0] - $xmin) -lt $eps     # Einbuchtung im Westen -> x spiegeln
    $spiegelY = [Math]::Abs($fehlt[1] - $ymin) -lt $eps     # Einbuchtung im Sueden -> y spiegeln
    function Hin($p) {
        $a = if ($script:spiegelX) { $script:xmin + $script:xmax - $p[0] } else { $p[0] }
        $b = if ($script:spiegelY) { $script:ymin + $script:ymax - $p[1] } else { $p[1] }
        return , @($a, $b)
    }
    # Die Ruecktransformation ist dieselbe Spiegelung -- sie ist ihre eigene Umkehrung.

    # Einspringende Ecke: der Punkt, der weder auf einer Bounding-Box-Ecke noch
    # auf deren Kante liegt.
    $R = $null
    foreach ($e in $ecken) {
        $g = Hin $e
        if ($g[0] -gt $xmin + $eps -and $g[0] -lt $xmax - $eps -and $g[1] -gt $ymin + $eps -and $g[1] -lt $ymax - $eps) { $R = $g }
    }
    if ($null -eq $R) { throw "Keine einspringende Ecke gefunden -- ist das wirklich eine L-Form?" }
    $rx = $R[0]; $ry = $R[1]

    # Riegel: volle Breite, von Sueden bis zur einspringenden Ecke.
    # Fluegel: volle Tiefe, von Westen bis zur einspringenden Ecke.
    $halbR = ($ry - $ymin) / 2
    $halbF = ($rx - $xmin) / 2
    if ($halbR -le 0 -or $halbF -le 0) { throw "Die Schenkel haben keine Breite -- Grundriss pruefen." }
    $h = if ($Firsthoehe -gt 0) { $Firsthoehe } else { [Math]::Min($halbR, $halbF) }
    $yr = $ymin + $halbR          # First des Riegels, laeuft in x
    $xr = $xmin + $halbF          # First des Fluegels, laeuft in y
    $nR = [Math]::Atan2($h, $halbR) * 180 / [Math]::PI
    $nF = [Math]::Atan2($h, $halbF) * 180 / [Math]::PI

    $flaechen += @{ Name = 'Riegel aussen'; Neigung = $nR
                    Traufe = @((Hin @($xmin, $ymin)), (Hin @($xmax, $ymin)))
                    Umriss = @((Hin @($xmin, $ymin)), (Hin @($xmax, $ymin)), (Hin @($xmax, $yr)), (Hin @($xr, $yr))) }
    $flaechen += @{ Name = 'Riegel innen'; Neigung = $nR
                    Traufe = @((Hin @($xmax, $ry)), (Hin @($rx, $ry)))
                    Umriss = @((Hin @($rx, $ry)), (Hin @($xmax, $ry)), (Hin @($xmax, $yr)), (Hin @($xr, $yr))) }
    $flaechen += @{ Name = 'Fluegel aussen'; Neigung = $nF
                    Traufe = @((Hin @($xmin, $ymin)), (Hin @($xmin, $ymax)))
                    Umriss = @((Hin @($xmin, $ymin)), (Hin @($xmin, $ymax)), (Hin @($xr, $ymax)), (Hin @($xr, $yr))) }
    $flaechen += @{ Name = 'Fluegel innen'; Neigung = $nF
                    Traufe = @((Hin @($rx, $ry)), (Hin @($rx, $ymax)))
                    Umriss = @((Hin @($rx, $ry)), (Hin @($rx, $ymax)), (Hin @($xr, $ymax)), (Hin @($xr, $yr))) }
}

Write-Host "Grundriss    : $($ecken.Count) Ecken, $(Z ([Math]::Round($xmax-$xmin,3))) x $(Z ([Math]::Round($ymax-$ymin,3))) m umschliessend"
Write-Host "Firsthoehe   : $(Z ([Math]::Round($h,3))) m ueber der Traufe$(if ($Firsthoehe -le 0) { '  (automatisch)' })"
Write-Host "Dachflaechen : $($flaechen.Count)"
Write-Host ""
foreach ($f in $flaechen) {
    Write-Host ("  {0,-16} Neigung {1,6:N2} Grad   Traufe {2} -> {3}" -f $f.Name, $f.Neigung, (Pkt $f.Traufe[0]), (Pkt $f.Traufe[1]))
    Write-Host ("  {0,-16} Umriss  {1}" -f '', (($f.Umriss | ForEach-Object { Pkt $_ }) -join ' | '))
}
Write-Host ""

$dach = Join-Path $PSScriptRoot "New-Dach.ps1"
if (-not (Test-Path $dach)) { throw "New-Dach.ps1 nicht gefunden neben diesem Skript." }
foreach ($f in $flaechen) {
    $arg = @{
        Projekt = $Projekt; Geschoss = $Geschoss
        Traufe  = ((Pkt $f.Traufe[0]) + ',' + (Pkt $f.Traufe[1]))
        Umriss  = (($f.Umriss | ForEach-Object { Pkt $_ }) -join ';')
        Neigung = $f.Neigung; Hoehe1 = $Hoehe1; Dicke = $Dicke
        Probelauf = $Probelauf; OhneSoftwarepruefung = $true
        Instanz = $Instanz; Datenbank = $Datenbank
    }
    if ($VorlageDatenbank) { $arg['VorlageDatenbank'] = $VorlageDatenbank }
    & $dach @arg | Select-Object -Last 1
}
