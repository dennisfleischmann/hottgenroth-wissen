# Schreibt einen IBP-Blob in das Feld Kernel18599V5 eines TableZusatz-Satzes.
#
# Wichtig: DAS ist die Quelle, nicht der Anhang. PrMedia/Kernel18599V5.bin ist
# nur eine Kopie des gerade aktiven Modells. Jede Variante fuehrt ihr eigenes
# vollstaendiges DIN-18599-Modell in ihrem TableZusatz-Satz, Feld
# Kernel18599V5 (Typ 4/75, Memo mit uint32-Laenge).
#
# Wer nur den Anhang schreibt, sieht in der Software nichts - genau so
# geschehen beim ersten Versuch.

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [Parameter(Mandatory)] [int]    $Proj,
    [Parameter(Mandatory)] [string] $Blob
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$neu = [System.IO.File]::ReadAllBytes($Blob)
$datei = Join-Path $Ordner 'TableZusatz.BDExit'
$b = [System.IO.File]::ReadAllBytes($datei)
$k = BdeKopf $b

$saetze = @(); $o = $k.Daten
while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $saetze += $r; $o = $r.Ende }
if ($saetze.Count -ne $k.Satzzahl) { throw "$($saetze.Count) Saetze gelesen, Kopf sagt $($k.Satzzahl)" }
function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }

$strom = New-Object System.Collections.Generic.List[byte]
$getroffen = $false
foreach ($s in $saetze) {
    $setze = @{}
    if ((Wert $s 'PROJ_ID') -eq $Proj) {
        $alt = ($s.Werte | Where-Object Name -eq 'Kernel18599V5')
        "PROJ_ID {0}: Kernel18599V5 {1} -> {2} Bytes" -f $Proj, $(if($alt.Da){$alt.Roh.Length - 4}else{'fehlt'}), $neu.Length
        $setze['Kernel18599V5'] = $neu
        $getroffen = $true
    }
    $strom.AddRange([byte[]] (BdeSchreib $b $k $s $setze))
}
if (-not $getroffen) { throw "kein Satz mit PROJ_ID $Proj" }

$kopf = New-Object byte[] $k.Daten
[Array]::Copy($b, 0, $kopf, 0, $k.Daten)
[System.IO.File]::WriteAllBytes($datei, ($kopf + $strom.ToArray()))
"TableZusatz: {0} -> {1} Bytes, Satzzahl unveraendert {2}" -f $b.Length, ($k.Daten + $strom.Count), $k.Satzzahl

# Gegenprobe: neu einlesen und die Rohbytes des Feldes vergleichen
$c = [System.IO.File]::ReadAllBytes($datei)
$k2 = BdeKopf $c
$o = $k2.Daten; $ok = $false
while ($o -lt $c.Length) {
    $r = BdeLies $c $k2 $o -1
    if ((Wert $r 'PROJ_ID') -eq $Proj) {
        $f = $r.Werte | Where-Object Name -eq 'Kernel18599V5'
        $roh = New-Object byte[] ($f.Roh.Length - 4)
        [Array]::Copy($f.Roh, 4, $roh, 0, $roh.Length)
        $ok = $roh.Length -eq $neu.Length
        if ($ok) { for ($i = 0; $i -lt $roh.Length; $i++) { if ($roh[$i] -ne $neu[$i]) { $ok = $false; "Abweichung bei Byte $i"; break } } }
    }
    $o = $r.Ende
}
"Gegenprobe: $(if($ok){'Feld byte-identisch zurueckgelesen'}else{'ABWEICHUNG'})"
