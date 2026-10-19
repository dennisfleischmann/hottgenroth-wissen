# Liest die Saetze einer .BDExit-Datei.
#
# Satzaufbau, an bekannten Werten geprueft (Roof 001-1: Flaeche 5,48 / U 0,24):
#   Typ 4 / Code 01   int32,  4 Bytes
#   Typ 8 / Code 04   double, 8 Bytes
#   Typ 1 / Code 49   Text: 1 Byte Laenge, dann so viele Zeichen
#   Typ 4 / Code 4B   Text ("_BER"-Felder), ebenso
#   Typ 2 / Code 03   1 Byte
#
# Saetze sind variabel lang - ein fester Teiler existiert nicht.

param([string] $Datei, [int] $Saetze = 3, [int] $Start = -1, [switch] $Dump)

$b = [System.IO.File]::ReadAllBytes($Datei)

# --- Kopf durchlaufen, gibt Felder und den Offset dahinter -------------------
$p = [BitConverter]::ToUInt32($b, 8)
$felder = New-Object System.Collections.ArrayList
$aktuell = $null

while ($p -lt $b.Length - 8) {
    $len = $b[$p]
    if ($len -lt 2 -or $len -gt 40) { break }

    $name = -join ($b[($p+1)..($p+$len)] | ForEach-Object { [char]$_ })
    if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { break }

    $q = $p + 1 + $len
    $typ  = [BitConverter]::ToUInt16($b, $q)
    $code = [BitConverter]::ToUInt16($b, $q+2)

    if ($name -eq 'SUBTYPE' -or $name -eq 'WIDTH') {
        $q += 4
        if ($code -eq 0x49) {
            $l = [BitConverter]::ToUInt16($b, $q); $q += 2 + $l
        } else {
            $wert = [BitConverter]::ToUInt16($b, $q); $q += 2
            if ($aktuell -and $name -eq 'WIDTH') { $aktuell.Breite = [int] $wert }
        }
    } else {
        $q += 8
        $aktuell = [pscustomobject]@{ Name = $name; Typ = $typ; Code = $code; Breite = 0 }
        [void] $felder.Add($aktuell)
    }
    $p = $q
}

$hinterKopf = $p
if ($Start -ge 0) { $p = $Start }

"Felder: $($felder.Count)   hinter dem Kopf: $hinterKopf   Lesebeginn: $p"

if ($Dump) {
    ""
    for ($z = $hinterKopf; $z -lt [Math]::Min($hinterKopf + 96, $b.Length); $z += 16) {
        $hex = -join (0..15 | ForEach-Object { if ($z+$_ -lt $b.Length) { $b[$z+$_].ToString('x2') + ' ' } })
        $txt = -join (0..15 | ForEach-Object { if ($z+$_ -lt $b.Length) { $c=$b[$z+$_]; if ($c -ge 32 -and $c -lt 127) { [char]$c } else { '.' } } })
        "{0,6}  {1} {2}" -f $z, $hex, $txt
    }
}

# --- Saetze lesen -----------------------------------------------------------
for ($s = 0; $s -lt $Saetze -and $p -lt $b.Length - 4; $s++) {
    ""
    "--- Satz $($s+1)  ab $p"
    foreach ($f in $felder) {
        if ($p -ge $b.Length - 1) { break }

        switch ("$($f.Typ)/$($f.Code)") {
            '4/1'  { $w = [BitConverter]::ToInt32($b, $p);  $p += 4 }
            '8/4'  { $w = [BitConverter]::ToDouble($b, $p); $p += 8 }
            '1/73' { $l = $b[$p]; $p++; $w = if ($l -gt 0 -and $p+$l -le $b.Length) { -join ($b[$p..($p+$l-1)] | ForEach-Object { [char]$_ }) } else { '' }; $p += $l }
            '4/75' { $l = $b[$p]; $p++; $w = if ($l -gt 0 -and $p+$l -le $b.Length) { -join ($b[$p..($p+$l-1)] | ForEach-Object { [char]$_ }) } else { '' }; $p += $l }
            '2/3'  { $w = $b[$p]; $p += 1 }
            default { $w = '??' }
        }

        $leer = ("$w" -eq '') -or ("$w" -eq '0')
        if (-not $leer) { "   {0,-22} {1}" -f $f.Name, $w }
    }
}
