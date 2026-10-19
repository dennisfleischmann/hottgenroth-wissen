# Loest den IBP-Blob aus dem Feld Kernel18599V5 eines TableZusatz-Satzes heraus.
# Gegenstueck zu setze-kernel.ps1.
#
# Bisher stand dieser Griff zweimal einkodiert in anderen Skripten
# (uwerte-uebernehmen.ps1, schnappschuss.ps1). Er gehoert hierher, weil jede
# Arbeit an der Anlagentechnik damit anfaengt:
#
#   .\hole-kernel.ps1 -Ordner .\arbeit -Proj 2 -Blob .\blob.bin
#   ibp-anlage-lesen.exe .\blob.bin > anlage.json
#   ... anlage.json bearbeiten ...
#   ibp-anlage-setzen.exe .\blob.bin .\blob-neu.bin anlage.json
#   .\setze-kernel.ps1 -Ordner .\arbeit -Proj 2 -Blob .\blob-neu.bin
#
# Das Feld ist ein 4/75-Memo: die ersten VIER Bytes sind die Laenge, nicht
# Nutzdaten. Wer sie mitnimmt, gibt dem BinaryFormatter einen Strom, der nicht
# mit seiner Kennung beginnt - und bekommt eine unverstaendliche Ausnahme.
#
# Ohne -Proj werden alle Saetze aufgelistet, die einen Blob fuehren. Das ist
# der schnellste Weg zu der Frage "welche Variante hat ueberhaupt ein Modell".
#
#   .\hole-kernel.ps1 -Ordner .\arbeit                      # nur auflisten
#   .\hole-kernel.ps1 -Ordner .\arbeit -Proj 2 -Blob .\b.bin

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [int]    $Proj,
    [string] $Blob
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$datei = Join-Path $Ordner 'TableZusatz.BDExit'
if (-not (Test-Path $datei)) { throw "$datei fehlt - ist der Container entpackt?" }

$b = [System.IO.File]::ReadAllBytes($datei)
$k = BdeKopf $b

$gefunden = @()
$o = $k.Daten
while ($o -lt $b.Length) {
    $r = BdeLies $b $k $o -1
    $id = ($r.Werte | Where-Object Name -eq 'PROJ_ID').Wert
    $feld = $r.Werte | Where-Object Name -eq 'Kernel18599V5'
    $gefunden += [pscustomobject] @{
        Proj  = [int] $id
        Bytes = $(if ($feld.Da) { $feld.Roh.Length - 4 } else { 0 })
        Feld  = $feld
    }
    $o = $r.Ende
}

if (-not $Proj) {
    $gefunden | ForEach-Object {
        '  PROJ_ID {0,-4} {1}' -f $_.Proj, $(if ($_.Bytes) { '{0:N0} Bytes' -f $_.Bytes } else { 'kein Modell' })
    }
    'Ein Blob heisst: die Variante FUEHRT ein DIN-18599-Modell. Er wird beim'
    'Anlegen einer Variante mitkopiert und sagt NICHT, dass sie gerechnet wurde -'
    'das steht in TableHeizung, siehe zeige-heizung.ps1.'
    return
}

$satz = @($gefunden | Where-Object Proj -eq $Proj)
if ($satz.Count -ne 1) { throw "TableZusatz fuehrt $($satz.Count) Saetze fuer PROJ_ID $Proj" }
if (-not $satz[0].Feld.Da) { throw "PROJ_ID $Proj hat keinen Kernel18599V5 - die Variante fuehrt kein DIN-18599-Modell" }
if (-not $Blob) { throw '-Blob fehlt: wohin soll der Blob geschrieben werden?' }

# Die ersten vier Bytes sind die Memo-Laenge, nicht Nutzdaten.
$roh = $satz[0].Feld.Roh
$bin = New-Object byte[] ($roh.Length - 4)
[Array]::Copy($roh, 4, $bin, 0, $bin.Length)
[System.IO.File]::WriteAllBytes($Blob, $bin)

# Gegenprobe: ein BinaryFormatter-Strom beginnt mit 0x00 0x01 0x00 0x00 0x00.
if ($bin.Length -lt 5 -or $bin[0] -ne 0 -or $bin[1] -ne 1) {
    Write-Warning ('Der Strom beginnt mit {0:X2} {1:X2} - das sieht nicht nach BinaryFormatter aus.' -f $bin[0], $bin[1])
}

'PROJ_ID {0}: {1:N0} Bytes -> {2}' -f $Proj, $bin.Length, $Blob
