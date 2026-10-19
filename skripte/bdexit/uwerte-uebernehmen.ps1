# Traegt die U-Werte einer Variante aus TableHuellfl ins IBP-Rechenmodell ein.
#
# Das ist der Schritt, der zwischen saniere.ps1 und einem richtig gerechneten
# Ergebnis fehlt. saniere.ps1 setzt SANK_ZAHL - das ist der ANGEZEIGTE saniere
# U-Wert. Gerechnet wird aus dem Blob in TableZusatz.Kernel18599V5, und der
# wird beim Anlegen einer Variante unveraendert mitkopiert. Ohne diesen Schritt
# zeigt die Variante saniere Werte und rechnet mit den alten.
#
# Je Bauteil gilt: SANK_ZAHL wenn vorhanden, sonst K_ZAHL. So traegt der Blob
# immer genau den Zustand, den die Variante beschreibt.
#
# Fenster (KENNZEICHEN FA) haengen im Modell als FenestrationSystem am Bauteil
# und brauchen deshalb einen eigenen Schluessel.
#
#   .\uwerte-uebernehmen.ps1 -Ordner .\entpackt -Proj 5
#   .\uwerte-uebernehmen.ps1 -Ordner .\entpackt -Proj 5 -Vorschau

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [Parameter(Mandatory)] [int]    $Proj,
    [switch] $Vorschau
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$ibp = Join-Path (Split-Path $PSScriptRoot -Parent) 'ibp'
$werkzeug = Join-Path $ibp 'ibp-uwert-setzen.exe'
if (-not (Test-Path $werkzeug)) { throw "$werkzeug fehlt - erst bauen" }

function Lies([string] $Datei) {
    $b = [System.IO.File]::ReadAllBytes($Datei)
    $k = BdeKopf $b
    $s = @(); $o = $k.Daten
    while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $s += $r; $o = $r.Ende }
    if ($s.Count -ne $k.Satzzahl) { throw "$(Split-Path $Datei -Leaf) unstimmig" }
    @{ Bytes = $b; Kopf = $k; Saetze = $s }
}
function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }
function Da($r, $n) { ($r.Werte | Where-Object Name -eq $n).Da }

# ---- Bauteilliste der Variante, in Reihenfolge
$th = Lies (Join-Path $Ordner 'TableHuellfl.BDExit')
$bauteile = @($th.Saetze | Where-Object { (Wert $_ 'PROJ_ID') -eq $Proj })
if (-not $bauteile) { throw "PROJ_ID $Proj hat keine Bauteile" }

$eintraege = foreach ($s in $bauteile) {
    $u = if (Da $s 'SANK_ZAHL') { Wert $s 'SANK_ZAHL' } else { Wert $s 'K_ZAHL' }
    $schluessel = if ((Wert $s 'KENNZEICHEN') -eq 'FA') { 'fenster' } else { 'u' }
    [pscustomobject]@{
        Name = [string] (Wert $s 'BAUTEILBEZ'); Schluessel = $schluessel
        U = [double] $u; Kz = [string] (Wert $s 'KENNZEICHEN')
        Saniert = [bool] (Da $s 'SANK_ZAHL')
    }
}

"PROJ_ID {0}: {1} Bauteile, davon {2} saniert" -f $Proj, $eintraege.Count,
    @($eintraege | Where-Object Saniert).Count
$eintraege | Group-Object Kz | Sort-Object Name | ForEach-Object {
    $u = ($_.Group | ForEach-Object { $_.U } | Sort-Object -Unique) -join '/'
    "  {0}  {1,2} Stueck  U {2}" -f $_.Name, $_.Count, $u
}

if ($Vorschau) { ""; "Vorschau - nichts geschrieben"; return }

# ---- JSON fuer das Werkzeug
$json = '{ "bauteile": [' + (($eintraege | ForEach-Object {
    '{ "name": ' + ($_.Name | ConvertTo-Json) +
    ', "' + $_.Schluessel + '": ' + $_.U.ToString([System.Globalization.CultureInfo]::InvariantCulture) + ' }'
}) -join ',') + '] }'
$jdatei = Join-Path $env:TEMP ("uwerte-$Proj-" + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.json')
[System.IO.File]::WriteAllText($jdatei, $json, [System.Text.Encoding]::UTF8)

# ---- Blob der Variante herausloesen
$tz = Lies (Join-Path $Ordner 'TableZusatz.BDExit')
$satz = @($tz.Saetze | Where-Object { (Wert $_ 'PROJ_ID') -eq $Proj })
if ($satz.Count -ne 1) { throw "TableZusatz fuehrt $($satz.Count) Saetze fuer PROJ_ID $Proj" }
$feld = $satz[0].Werte | Where-Object Name -eq 'Kernel18599V5'
if (-not $feld.Da) { throw "PROJ_ID $Proj hat keinen Kernel18599V5" }
$roh = New-Object byte[] ($feld.Roh.Length - 4)
[Array]::Copy($feld.Roh, 4, $roh, 0, $roh.Length)

$alt = Join-Path $env:TEMP ("blob-$Proj-alt.bin")
$neu = Join-Path $env:TEMP ("blob-$Proj-neu.bin")
[System.IO.File]::WriteAllBytes($alt, $roh)

& $werkzeug $alt $neu $jdatei
if ($LASTEXITCODE -ne 0) { throw "ibp-uwert-setzen ist fehlgeschlagen" }

& (Join-Path $PSScriptRoot 'setze-kernel.ps1') -Ordner $Ordner -Proj $Proj -Blob $neu
