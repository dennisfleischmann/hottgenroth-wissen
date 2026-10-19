# Gemeinsame Bausteine fuer .BDExit. Hier stehen nur gemessene Groessen.
#
# Kopf   00 Magic | 08 uint32 Beginn Feldtabelle | 12 uint16 Feldzahl
#        14 uint16 SATZZAHL | 24 Feldtabelle
# Feld   byte Laenge | Name | uint16 Typ | uint16 Code | uint16 ? | uint16 Unter
#        Untereintraege SUBTYPE/WIDTH haengen ohne die letzten 4 Bytes dran.
# Ende   hinter der Feldtabelle steht 01 00, dann - falls die Tabelle einen
#        Autowert fuehrt - der Eintrag AUTOINCVALUE mit dem naechsten freien
#        Schluessel. Erst dahinter faengt Satz 1 an.
# Satz   Anwesenheitskarte, 2 Bit je Feld, aufgerundet + 1 Byte. Dann die Werte.
#
# Feldnamen koennen EIN Zeichen lang sein (TableZusatz: A, B, B1, B2A, B2B) -
# eine Mindestlaenge von 2 bricht den Leser dort ab.

function BdeKopf([byte[]] $b) {
    $p = [BitConverter]::ToUInt32($b, 8)
    $felder = New-Object System.Collections.ArrayList
    while ($p -lt $b.Length - 8) {
        $len = $b[$p]
        if ($len -lt 1 -or $len -gt 40) { break }
        $name = -join ($b[($p+1)..($p+$len)] | ForEach-Object { [char]$_ })
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { break }
        $q = $p + 1 + $len
        $code = [BitConverter]::ToUInt16($b, $q+2)
        if ($name -eq 'SUBTYPE' -or $name -eq 'WIDTH') {
            $q += 4
            if ($code -eq 0x49) {
                $l = [BitConverter]::ToUInt16($b,$q); $q += 2 + $l
            } else {
                if ($name -eq 'WIDTH' -and $felder.Count) { $felder[$felder.Count-1].Breite = [BitConverter]::ToUInt16($b,$q) }
                $q += 2
            }
        } else {
            $typ = [BitConverter]::ToUInt16($b, $q)
            $q += 8
            [void] $felder.Add([pscustomobject]@{
                Name = $name; Typ = $typ; Code = $code; Breite = 0
            })
        }
        $p = $q
    }

    # Hinter der Feldtabelle stehen IMMER zwei Bytes - bei TableProjekt 01 00,
    # bei TableHausDat 00 00. Danach optional der Autowert.
    $auto = -1
    $q = $p + 2
    if ($b[$q] -eq 12) {
        $n = -join ($b[($q+1)..($q+12)] | ForEach-Object { [char]$_ })
        if ($n -eq 'AUTOINCVALUE') { $auto = $q + 1 + 12 + 4; $q = $auto + 4 }
    }

    $fz = [BitConverter]::ToUInt16($b, 12)
    return [pscustomobject]@{
        Feldzahl  = $fz
        Satzzahl  = [BitConverter]::ToUInt16($b, 14)
        Felder    = $felder
        Vorspann  = [math]::Ceiling($fz * 2 / 8) + 1
        Daten     = $q
        AutoPos   = $auto
        AutoWert  = $(if ($auto -ge 0) { [BitConverter]::ToInt32($b, $auto) } else { -1 })
    }
}

# Satzanfaenge einer Tabelle mit wenigen, gleich gebauten Saetzen.
# Kennzeichen: gleiche Anwesenheitskarte wie Satz 1 und fortlaufender Schluessel.
function BdeSaetze([byte[]] $b, $k) {
    $H = $k.Daten; $V = $k.Vorspann
    $id1 = [BitConverter]::ToInt32($b, $H + $V)
    $anf = @($H)
    for ($p = $H + $V + 8; $p -lt $b.Length - $V - 4; $p++) {
        if ([BitConverter]::ToInt32($b, $p + $V) -ne $id1 + $anf.Count) { continue }
        $gleich = $true
        for ($i = 0; $i -lt $V; $i++) { if ($b[$p+$i] -ne $b[$H+$i]) { $gleich = $false; break } }
        if ($gleich) { $anf += $p }
    }
    return $anf
}
