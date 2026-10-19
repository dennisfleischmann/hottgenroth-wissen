<#
    Liest die oeffentliche Schnittstelle aus den dekompilierten Dateien.

    ILSpy formatiert vorhersagbar: namespace auf Spalte 0, Typen eine
    Tabulatorstufe tiefer, deren Mitglieder wieder eine tiefer. Damit reicht die
    Einrueckung zur Gliederung — kein Parser noetig.

    Ausgewertet werden nur die kanonischen Dateien (ohne ~hash im Namen): je
    Modulname eine Fassung, sonst stuenden dieselben Typen vielfach da.

    Ergebnis:
      api\<Modul>.api.txt   je Modul: Namensraeume, Typen, oeffentliche Mitglieder
      api-typen.csv         jeder oeffentliche Typ, durchsuchbar
      api-mitglieder.csv    jedes oeffentliche Mitglied, durchsuchbar
#>
[CmdletBinding()]
param(
    [string] $Quelle = 'C:\Projekte_Dev\hsetu-decompiled\eigen',
    [string] $Ziel   = 'C:\Projekte_Dev\hsetu-decompiled',

    # Unterscheidet die Ausgaben, wenn mehrere Bestaende indiziert werden.
    # Ohne Marke entsteht api\ + api-typen.csv (der eigene Code), mit Marke
    # 'fremd' entsprechend api-fremd\ + api-typen-fremd.csv. Sonst
    # ueberschriebe der zweite Lauf den ersten.
    [string] $Marke  = ''
)

$ErrorActionPreference = 'Stop'

$anhang = if ($Marke -ne '') { "-$Marke" } else { '' }

$ausgabe = Join-Path $Ziel ('api' + $anhang)
New-Item -ItemType Directory -Force -Path $ausgabe | Out-Null

$dateien = @(Get-ChildItem -LiteralPath $Quelle -Filter *.cs -File | Where-Object { $_.Name -notmatch '~' } | Sort-Object Name)

Write-Host "$($dateien.Count) kanonische Module"

$artWorte = @(' class ', ' interface ', ' struct ', ' enum ', ' delegate ')

$typen = New-Object System.Collections.ArrayList
$mitglieder = New-Object System.Collections.ArrayList

$n = 0

foreach ($d in $dateien) {
    $n++
    if ($n % 50 -eq 0) { Write-Host "  $n/$($dateien.Count) ..." }

    $modul = $d.BaseName
    $zeilen = New-Object System.Collections.ArrayList
    [void] $zeilen.Add("# $modul")

    $ns = ''
    $nsGeschrieben = ''
    $typ = $null
    $typArt = ''
    $istEnum = $false

    foreach ($z in [System.IO.File]::ReadLines($d.FullName)) {
        if ($z.Length -eq 0) { continue }

        if ($z[0] -ne "`t") {
            if ($z.StartsWith('namespace ')) { $ns = $z.Substring(10).Trim() }
            continue
        }

        # Einrueckungstiefe zaehlen.
        $t = 0
        while ($t -lt $z.Length -and $z[$t] -eq "`t") { $t++ }
        $rest = $z.Substring($t).TrimEnd()

        if ($rest.Length -eq 0 -or $rest[0] -eq '[' -or $rest[0] -eq '{' -or $rest[0] -eq '}') { continue }

        if ($t -eq 1) {
            $typ = $null

            if (-not $rest.StartsWith('public')) { continue }

            $art = ''
            foreach ($w in $artWorte) {
                if ($rest.Contains($w)) { $art = $w.Trim(); break }
            }
            if ($art -eq '') { continue }

            # Name steht hinter dem Art-Wort, bis Klammer, Doppelpunkt oder Ende.
            $p = $rest.IndexOf(" $art ") + $art.Length + 2
            $name = $rest.Substring($p)
            foreach ($stop in @(' :', '(', ' where')) {
                $i = $name.IndexOf($stop)
                if ($i -ge 0) { $name = $name.Substring(0, $i) }
            }
            $name = $name.Trim()

            $typ = $name
            $typArt = $art
            $istEnum = ($art -eq 'enum')

            if ($ns -ne $nsGeschrieben) {
                [void] $zeilen.Add('')
                [void] $zeilen.Add("## namespace $ns")
                $nsGeschrieben = $ns
            }

            [void] $zeilen.Add('')
            [void] $zeilen.Add($rest)

            [void] $typen.Add([pscustomobject]@{
                Modul = $modul; Namensraum = $ns; Art = $art; Typ = $name; Deklaration = $rest
            })

            continue
        }

        if ($t -eq 2 -and $typ) {
            # Enum-Werte tragen kein 'public'.
            if ($istEnum) {
                $wert = $rest.TrimEnd(',')
                if ($wert -match '^[A-Za-z_]') {
                    [void] $zeilen.Add("    $wert")
                    [void] $mitglieder.Add([pscustomobject]@{
                        Modul = $modul; Namensraum = $ns; Typ = $typ; Art = 'Wert'; Deklaration = $wert
                    })
                }
                continue
            }

            if (-not ($rest.StartsWith('public ') -or $rest.StartsWith('protected '))) { continue }

            # Methode oder Eigenschaft/Feld: entscheidend ist die Klammer vor
            # einem etwaigen Rumpf.
            $kl = $rest.IndexOf('(')
            $gs = $rest.IndexOf('{')
            $art = if ($kl -ge 0 -and ($gs -lt 0 -or $kl -lt $gs)) { 'Methode' } else { 'Eigenschaft' }

            [void] $zeilen.Add("    $rest")
            [void] $mitglieder.Add([pscustomobject]@{
                Modul = $modul; Namensraum = $ns; Typ = $typ; Art = $art; Deklaration = $rest
            })
        }
    }

    Set-Content -LiteralPath (Join-Path $ausgabe "$modul.api.txt") -Value $zeilen -Encoding utf8
}

$typen | Export-Csv (Join-Path $Ziel "api-typen$anhang.csv") -NoTypeInformation -Encoding utf8
$mitglieder | Export-Csv (Join-Path $Ziel "api-mitglieder$anhang.csv") -NoTypeInformation -Encoding utf8

Write-Host ''
Write-Host ("{0} oeffentliche Typen, {1} oeffentliche Mitglieder" -f $typen.Count, $mitglieder.Count)
$typen | Group-Object Art | Sort-Object Count -Descending | ForEach-Object { "  {0,-10} {1,7}" -f $_.Name, $_.Count }
$mitglieder | Group-Object Art | Sort-Object Count -Descending | ForEach-Object { "  {0,-12} {1,7}" -f $_.Name, $_.Count }
