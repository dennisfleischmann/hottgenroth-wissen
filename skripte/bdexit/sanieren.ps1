# Setzt SANK_ZAHL (den U-Wert nach Sanierung) in TableHuellfl.
#
# Ohne den Satzaufbau vollstaendig aufzuloesen: SANK_ZAHL steht in festem
# Abstand hinter K_ZAHL, und K_ZAHL wiederum in festem Abstand hinter FLAECHE.
# Der Anker ist der Bauteilname - der steht laengenpraefigiert im Satz.
#
#   ... BAUTEILBEZ | FLAECHE(8) | K_ZAHL(8) | 8 | 8 | REDFAKTOR(8) | SANK_ZAHL(8)
#
# Belegt am Satz "EW 028-1 + ... + EW 045": Flaeche 54,82 / K_Zahl 0,24 /
# SanK_Zahl 0,20 - alle drei stimmen mit der Oberflaeche ueberein.

param(
    [Parameter(Mandatory)] [string] $Datei,
    [Parameter(Mandatory)] [string] $Ziel,
    [Parameter(Mandatory)] [string] $Bauteil,   # Teilzeichenkette des Namens
    [Parameter(Mandatory)] [double] $Neu,
    [switch] $NurZeigen
)

$b = [System.IO.File]::ReadAllBytes($Datei)
$text = [System.Text.Encoding]::GetEncoding(1252).GetString($b)

# Abstand vom Ende des Bauteilnamens bis SANK_ZAHL, aus dem Satz abgelesen.
$abstandKZahl = 16      # Ende Name -> K_ZAHL   (8 Byte Flaeche davor)
$abstandSanK  = 48      # Ende Name -> SANK_ZAHL

$i = 0
$treffer = 0
while (($i = $text.IndexOf($Bauteil, $i)) -ge 0) {
    $ende = $i + $Bauteil.Length

    $kz  = [BitConverter]::ToDouble($b, $ende + $abstandKZahl)
    $san = [BitConverter]::ToDouble($b, $ende + $abstandSanK)

    # Nur echte Satzstellen: K_ZAHL muss ein plausibler U-Wert sein.
    if ($kz -gt 0 -and $kz -lt 10) {
        $treffer++
        "Fund {0} bei {1}: K_ZAHL={2}  SANK_ZAHL={3}" -f $treffer, $i, $kz, $san

        if (-not $NurZeigen) {
            [BitConverter]::GetBytes($Neu).CopyTo($b, $ende + $abstandSanK)
        }
    }
    $i = $ende
}

if (-not $NurZeigen) {
    [System.IO.File]::WriteAllBytes($Ziel, $b)
    "geschrieben: $Ziel  ($($b.Length) Bytes, $treffer Saetze geaendert)"
}
