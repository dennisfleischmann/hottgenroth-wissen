# Zieht die Leitungslage nach, die das Austauschformat nicht kennt:
# je Rohr erst die Zone in die Verweisliste anhaengen, DANN enumAmbientType=2.
# Umgekehrt behauptet das Modell "in Zone" und schreibt die Verluste niemandem gut.
param(
    [Parameter(Mandatory)][string] $Blob,
    [Parameter(Mandatory)][string] $Ziel,
    [Parameter(Mandatory)][string] $Zone,
    [int] $Rohre = 3
)
$ErrorActionPreference = 'Stop'
$ibp = 'C:\Projekte_Dev\hsetu-decompiled\werkzeuge\ibp'
$tmp = [System.IO.Path]::GetDirectoryName($Ziel)
$ein = $Blob
for ($i = 0; $i -lt $Rohre; $i++) {
    $p = "CircuitHeatWater[0].Distributions[0].Pipes[$i].AmbientTemperature"
    $a = Join-Path $tmp "rz-$i-a.bin"
    $b = if ($i -eq $Rohre - 1) { $Ziel } else { Join-Path $tmp "rz-$i-b.bin" }
    & "$ibp\ibp-sammlung.exe"   $ein $a "$p.AmbientZone" anhaengen $Zone | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "anhaengen fehlgeschlagen bei Pipes[$i]" }
    & "$ibp\ibp-feld-setzen.exe" $a  $b "$p.enumAmbientType" 2 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "enumAmbientType fehlgeschlagen bei Pipes[$i]" }
    $ein = $b
}
# Gegenprobe
for ($i = 0; $i -lt $Rohre; $i++) {
    $p = "CircuitHeatWater[0].Distributions[0].Pipes[$i].AmbientTemperature"
    $t = ((& "$ibp\ibp-feld-setzen.exe" $Ziel - "$p.enumAmbientType") -join ' ') -replace '.*= *',''
    $z = ((& "$ibp\ibp-sammlung.exe"  $Ziel - "$p.AmbientZone" zeigen) -join ' ')
    $c = if ($z -match 'Count = (\d+)') { $Matches[1] } else { '?' }
    if ($t -ne '2' -or $c -ne '1') { throw "Pipes[$i] steht auf Typ=$t Count=$c statt 2/1" }
    "  Pipes[$i]  enumAmbientType=$t  AmbientZone Count=$c  ok"
}
