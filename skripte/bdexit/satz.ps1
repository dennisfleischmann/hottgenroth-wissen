# Liest und schreibt einen .BDExit-Satz feldweise.
#
# Satzaufbau
#   Anwesenheitskarte   ceil(Feldzahl*2/8) + 1 Byte. Das erste Byte gehoert
#                       NICHT zu den Feldern. Feld i liegt danach in Byte
#                       1 + floor(i/4), Schiebung (i%4)*2.
#                       Bitwert 1 = Feld FEHLT, 0 = Feld steht im Satz.
#   Werte               nur die vorhandenen Felder, in Feldreihenfolge
#
# Feldbreiten - eine einzige Regel deckt alle Typen ab:
#   Code 73 oder 75  -> Text. Die LAENGE steht in "Typ" Bytes davor.
#                       1/73 = 1 Byte Laenge, 2/73 = 2 Bytes, 4/75 = 4 Bytes.
#   sonst            -> feste Breite "Typ" Bytes.
#                       2/1 int16, 4/1 int32, 8/4 double, 2/3 kurz, 4/6 Datum.
#
# Werte, die hier nicht gedeutet werden (Datum), reisen als Rohbytes mit und
# werden unveraendert zurueckgeschrieben.
#
# Geprueft: alle Saetze aller neun Tabellen lesen exakt bis zum Dateiende, und
# unveraendert neu aufgebaut sind sie Byte fuer Byte identisch.

function BdeFeldGroesse($f, [byte[]] $b, [int] $o) {
    if ($f.Code -eq 73 -or $f.Code -eq 75) {
        $l = switch ($f.Typ) {
            1 { $b[$o] }
            2 { [BitConverter]::ToUInt16($b,$o) }
            default { [BitConverter]::ToUInt32($b,$o) }
        }
        return @{ Kopf = $f.Typ; Nutz = [int] $l; Text = $true }
    }
    return @{ Kopf = 0; Nutz = [int] $f.Typ; Text = $false }
}

function BdeLies([byte[]] $b, $k, [int] $satz, [int] $ende) {
    $o = $satz + $k.Vorspann
    $werte = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $k.Felder.Count; $i++) {
        $f = $k.Felder[$i]
        $fehlt = (($b[$satz + 1 + [math]::Floor($i/4)] -shr (($i % 4) * 2)) -band 3) -ne 0
        if ($fehlt) {
            [void] $werte.Add([pscustomobject]@{ Nr=$i; Name=$f.Name; Typ="$($f.Typ)/$($f.Code)"; Da=$false; Pos=-1; Roh=$null; Wert=$null })
            continue
        }
        $g = BdeFeldGroesse $f $b $o
        $pos = $o
        $ganz = $g.Kopf + $g.Nutz
        if ($pos + $ganz -gt $b.Length) { throw "Feld $($f.Name) laeuft ueber das Dateiende" }
        $roh = New-Object byte[] $ganz
        [Array]::Copy($b, $pos, $roh, 0, $ganz)

        $w = if ($g.Text) {
            if ($g.Nutz) { [System.Text.Encoding]::GetEncoding(1252).GetString($b, $pos + $g.Kopf, $g.Nutz) } else { '' }
        } else {
            switch ("$($f.Typ)/$($f.Code)") {
                '4/1' { [BitConverter]::ToInt32($b,$pos) }
                '2/1' { [BitConverter]::ToInt16($b,$pos) }
                '8/4' { [BitConverter]::ToDouble($b,$pos) }
                '2/3' { [BitConverter]::ToUInt16($b,$pos) }
                default { $null }          # Datum und Unbekanntes: nur roh
            }
        }
        $o += $ganz
        [void] $werte.Add([pscustomobject]@{ Nr=$i; Name=$f.Name; Typ="$($f.Typ)/$($f.Code)"; Da=$true; Pos=$pos; Roh=$roh; Wert=$w })
    }
    return [pscustomobject]@{ Satz=$satz; Ende=$o; Werte=$werte; Passt=($ende -lt 0 -or $o -eq $ende) }
}

# Baut einen Satz neu auf. $Setze ist eine Hashtabelle Feldname -> Wert;
# ein Feld, das bisher fehlte, wird dabei in der Karte freigeschaltet.
# Alles, was nicht in $Setze steht, wandert als Rohbytes durch - so bleiben
# auch ungedeutete Felder unversehrt.
function BdeSchreib([byte[]] $b, $k, $gelesen, [hashtable] $Setze) {
    $karte = New-Object byte[] $k.Vorspann
    [Array]::Copy($b, $gelesen.Satz, $karte, 0, $k.Vorspann)
    $strom = New-Object System.Collections.Generic.List[byte]

    foreach ($w in $gelesen.Werte) {
        $f = $k.Felder[$w.Nr]
        $neu = $Setze.ContainsKey($f.Name)
        if (-not $w.Da -and -not $neu) { continue }
        if (-not $neu) { $strom.AddRange($w.Roh); continue }

        $i = $w.Nr
        $bi = 1 + [math]::Floor($i/4)
        $karte[$bi] = $karte[$bi] -band (-bnot (3 -shl (($i % 4) * 2)))   # 0 = steht im Satz

        $wert = $Setze[$f.Name]
        if ($f.Code -eq 73 -or $f.Code -eq 75) {
            # Rohbytes durchreichen, wenn welche uebergeben wurden. Noetig fuer
            # Kernel18599V5: das Feld traegt einen BinaryFormatter-Graphen, und
            # CP1252 bildet fuenf Bytewerte (81 8D 8F 90 9D) nicht ab - der Weg
            # ueber eine Zeichenkette wuerde den Graphen zerstoeren.
            # Zuweisung DIREKT in den Zweigen. Ein "$t = if (...) { $feld }"
            # faltet das Feld beim Zuweisen in Einzelwerte auf, und heraus
            # kaeme ein Object[].
            if ($wert -is [byte[]]) { $t = $wert }
            else { $t = [System.Text.Encoding]::GetEncoding(1252).GetBytes([string] $wert) }
            switch ($f.Typ) {
                1 { $strom.Add([byte] $t.Length) }
                2 { $strom.AddRange([BitConverter]::GetBytes([uint16] $t.Length)) }
                default { $strom.AddRange([BitConverter]::GetBytes([uint32] $t.Length)) }
            }
            $strom.AddRange($t)
        } else {
            switch ("$($f.Typ)/$($f.Code)") {
                '4/1' { $strom.AddRange([BitConverter]::GetBytes([int]    $wert)) }
                '2/1' { $strom.AddRange([BitConverter]::GetBytes([int16]  $wert)) }
                '8/4' { $strom.AddRange([BitConverter]::GetBytes([double] $wert)) }
                '2/3' { $strom.AddRange([BitConverter]::GetBytes([uint16] $wert)) }
                default { throw "Feld $($f.Name) hat Typ $($f.Typ)/$($f.Code) - dafuer gibt es keinen Schreibweg" }
            }
        }
    }
    # Das fuehrende Komma ist noetig: sonst faltet PowerShell das Feld beim
    # Zurueckgeben in Einzelbytes auf, und der Aufrufer bekommt ein Object[].
    return ,[byte[]] ($karte + $strom.ToArray())
}
