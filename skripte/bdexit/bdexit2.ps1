# Liest den Kopf einer .BDExit-Datei vollstaendig.
#
# Aufbau (aus dem Bytevergleich abgeleitet, nicht geraten):
#
#   00  96 19 E0 BD     Magic
#   04  uint32          Version
#   08  uint32          Kopflaenge (24) - dahinter die Feldtabelle
#   12  uint32          Zahl der Eintraege
#   16  8 Bytes         unklar
#   24  Feldtabelle
#
# FELD (oberste Ebene):   byte Laenge | Name | uint16 Typ | uint16 Code
#                         | uint16 ? | uint16 Zahl der Untereintraege
#
# UNTEREINTRAG:           byte Laenge | Name | uint16 Typ | uint16 Code
#                         Code 0x02 -> uint16 Wert
#                         Code 0x49 -> uint16 Laenge, dann so viele Bytes Text
#
# Typen, wie sie vorkommen:
#   Typ 1  / Code 49   Text, Laenge steht im Untereintrag WIDTH
#   Typ 2  / Code 03   Kurzfeld (vermutlich logisch)
#   Typ 4  / Code 01   Ganzzahl
#   Typ 4  / Code 4B   Text mit SUBTYPE=Text und WIDTH  (die "_BER"-Felder)
#   Typ 8  / Code 04   Gleitkomma

param([string] $Datei, [switch] $Leise)

$b = [System.IO.File]::ReadAllBytes($Datei)
$U16 = { param($o) [BitConverter]::ToUInt16($b, $o) }

$p = [BitConverter]::ToUInt32($b, 8)
$anzahl = [BitConverter]::ToUInt32($b, 12)

$felder = New-Object System.Collections.ArrayList
$aktuell = $null

while ($p -lt $b.Length - 8) {
    $len = $b[$p]
    if ($len -lt 2 -or $len -gt 40) { break }

    $name = -join ($b[($p+1)..($p+$len)] | ForEach-Object { [char]$_ })
    if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { break }

    $q = $p + 1 + $len
    $typ = & $U16 $q
    $code = & $U16 ($q+2)

    if ($name -eq 'SUBTYPE' -or $name -eq 'WIDTH') {
        # Untereintrag
        $q += 4
        if ($code -eq 0x49) {
            $l = & $U16 $q; $q += 2
            $wert = -join ($b[$q..($q+$l-1)] | ForEach-Object { if ($_ -ge 32) { [char]$_ } else { '' } })
            $q += $l
        } else {
            $wert = & $U16 $q; $q += 2
        }
        if ($aktuell) {
            if ($name -eq 'WIDTH') { $aktuell.Breite = [int] $wert } else { $aktuell.Subtyp = "$wert" }
        }
    } else {
        # Feld
        $unter = & $U16 ($q+6)
        $q += 8
        $aktuell = [pscustomobject]@{
            Name = $name; Typ = $typ; Code = $code; Unter = $unter
            Breite = 0; Subtyp = ''; Bytes = 0
        }
        [void] $felder.Add($aktuell)
    }

    $p = $q
}

# Satzbreite je Feld, aus Typ und Code
foreach ($f in $felder) {
    $f.Bytes = switch ("$($f.Typ)/$($f.Code)") {
        '1/73' { $f.Breite }      # Text
        '4/75' { $f.Breite }      # Text ueber SUBTYPE=Text
        '4/1'  { 4 }              # Ganzzahl
        '8/4'  { 4 }              # Gleitkomma (einfach)
        '2/3'  { 2 }              # Kurzfeld
        default { -1 }
    }
}

if (-not $Leise) {
    "Datei     : $(Split-Path $Datei -Leaf)  ($($b.Length) Bytes)"
    "Kopfangabe: $anzahl Eintraege"
    "gelesen   : $($felder.Count) Felder, Daten ab Offset $p"
    ""
    $unbekannt = @($felder | Where-Object { $_.Bytes -lt 0 })
    if ($unbekannt) {
        "UNBEKANNTE Typen: " + (($unbekannt | ForEach-Object { "$($_.Name)=$($_.Typ)/$($_.Code)" }) -join ', ')
    }
    $satz = ($felder | Where-Object { $_.Bytes -ge 0 } | Measure-Object Bytes -Sum).Sum
    $daten = $b.Length - $p
    "Satzbreite (Summe der Felder): $satz"
    "Datenteil : $daten Bytes  ->  $([Math]::Round($daten / [Math]::Max($satz,1), 2)) Saetze"
    ""
    $felder | ForEach-Object {
        "{0,-24} Typ={1}/{2,-3} Breite={3,-4} {4,-6} Bytes={5}" -f $_.Name, $_.Typ, $_.Code, $_.Breite, $_.Subtyp, $_.Bytes
    }
}

$felder
