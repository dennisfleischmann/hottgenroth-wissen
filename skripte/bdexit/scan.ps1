# Sucht laengenpraefigierte Namen im Kopf und zeigt, was zwischen ihnen steht.
#
# Bewusst ohne Annahme ueber den Eintragsaufbau: erst sehen, welche Bytefolgen
# ueberhaupt vorkommen, dann die Regel ableiten. Raten hat zweimal danebengelegen.

param([string] $Datei, [int] $Max = 200)

$b = [System.IO.File]::ReadAllBytes($Datei)

# Ein Name: Laengenbyte 2..40, danach so viele druckbare Namenszeichen, und das
# Zeichen davor darf kein Namenszeichen sein (sonst trifft man Namensteile).
$namen = New-Object System.Collections.ArrayList
for ($i = 24; $i -lt [Math]::Min($b.Length, 100000) - 2; $i++) {
    $len = $b[$i]
    if ($len -lt 2 -or $len -gt 40 -or $i + $len -ge $b.Length) { continue }

    $ok = $true
    for ($k = 1; $k -le $len; $k++) {
        $c = $b[$i + $k]
        if (-not (($c -ge 65 -and $c -le 90) -or ($c -ge 97 -and $c -le 122) -or
                  ($c -ge 48 -and $c -le 57) -or $c -eq 95)) { $ok = $false; break }
    }
    if (-not $ok) { continue }

    # erstes Zeichen kein Ziffernstart
    $c0 = $b[$i+1]
    if ($c0 -ge 48 -and $c0 -le 57) { continue }

    [void] $namen.Add([pscustomobject]@{
        Offset = $i
        Name = -join ($b[($i+1)..($i+$len)] | ForEach-Object { [char]$_ })
        Ende = $i + 1 + $len
    })
    $i += $len
}

"$($namen.Count) Namen gefunden"
""
"Name                       Ende   Luecke  Bytes bis zum naechsten Namen"
for ($n = 0; $n -lt [Math]::Min($namen.Count, $Max); $n++) {
    $e = $namen[$n]
    $bis = if ($n + 1 -lt $namen.Count) { $namen[$n+1].Offset } else { $e.Ende + 16 }
    $luecke = $bis - $e.Ende
    $roh = if ($luecke -gt 0 -and $luecke -lt 60) {
        -join ($b[$e.Ende..($bis-1)] | ForEach-Object { $_.ToString('x2') + ' ' })
    } else { "($luecke Bytes)" }

    "{0,-26} {1,6} {2,6}  {3}" -f $e.Name, $e.Ende, $luecke, $roh
}
