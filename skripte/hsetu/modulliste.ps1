<#
    Erzeugt MODULE-ALLE.md - die vollstaendige Modulliste, maschinell.

    Bewusst getrennt vom Katalog (MODULE.md): dort steht, was gelesen und
    beschrieben wurde, hier steht ohne Ausnahme jedes Modul mit seinen Zahlen.
    Eine Liste, die beides mischt, laesst nicht mehr erkennen, welcher Satz
    geprueft ist und welcher gezaehlt.

    Quelle ist steckbriefe.csv (werkzeuge\steckbriefe.ps1).
#>
[CmdletBinding()]
param(
    [string] $Ziel = 'C:\Projekte_Dev\hsetu-decompiled'
)

$ErrorActionPreference = 'Stop'

$s = Import-Csv (Join-Path $Ziel 'steckbriefe.csv')

# Welche Module cross-kompiliert sind, verraet der Typ __Global - der Abdruck
# einer Delphi-Unit, deren globale Prozeduren zu einer Klasse werden.
$delphi = @{}
Get-ChildItem (Join-Path $Ziel 'api') -Filter *.api.txt | ForEach-Object {
    # 'public static class __Global' - der Zusatz static gehoert dazu, ein
    # engeres Muster findet nichts.
    if (Select-String -LiteralPath $_.FullName -Pattern '^public static class __Global' -Quiet) {
        $delphi[$_.BaseName -replace '\.api$', ''] = $true
    }
}

$zeilen = New-Object System.Collections.ArrayList

[void] $zeilen.Add('# Alle Module - vollstaendige Liste')
[void] $zeilen.Add('')
[void] $zeilen.Add('Maschinell erzeugt aus `steckbriefe.csv`. Die **Selbstauskunft** ist der Text,')
[void] $zeilen.Add('den die Assembly selbst mitbringt (`AssemblyDescription`) - leer, wo Hottgenroth')
[void] $zeilen.Add('keinen gepflegt hat. **D** markiert cross-kompilierte Delphi-Module (erkennbar am')
[void] $zeilen.Add('Typ `__Global`). Beschreibungen in Worten stehen im [Modulkatalog](MODULE.md).')
[void] $zeilen.Add('')

$familien = $s | Group-Object Familie | Sort-Object { $_.Group | Measure-Object -Property Typen -Sum | Select-Object -ExpandProperty Sum } -Descending

foreach ($f in $familien) {
    $summeTypen = ($f.Group | Measure-Object -Property Typen -Sum).Sum
    $summeMitglieder = ($f.Group | Measure-Object -Property Mitglieder -Sum).Sum

    [void] $zeilen.Add("## $($f.Name)")
    [void] $zeilen.Add('')
    [void] $zeilen.Add("$($f.Count) Module, $summeTypen Typen, $summeMitglieder Mitglieder.")
    [void] $zeilen.Add('')
    [void] $zeilen.Add('| Modul | Typen | Mitgl. | KB | D | Selbstauskunft / groesste Typen |')
    [void] $zeilen.Add('|---|---:|---:|---:|:-:|---|')

    foreach ($m in ($f.Group | Sort-Object { [int] $_.Typen } -Descending)) {
        $text = $m.Beschreibung

        # Ohne Selbstauskunft: die drei groessten Typen sagen mehr als nichts.
        if ($text -eq '' -or $text -eq 'HSETU Framework') {
            $gross = ($m.Grosse_Typen -split ';' | Select-Object -First 3 |
                ForEach-Object { ($_ -replace '\(\d+\)', '').Trim() }) -join ', '
            # $($gross) mit Klammern: sonst liest PowerShell den Unterstrich als
            # Teil des Variablennamens und setzt eine leere Zeichenkette ein.
            $text = if ($gross) { "_$($gross)_" } else { '' }
        }

        $text = $text -replace '\|', '\'

        [void] $zeilen.Add(('| `{0}` | {1} | {2} | {3} | {4} | {5} |' -f
            $m.Modul, $m.Typen, $m.Mitglieder, $m.Groesse_KB,
            $(if ($delphi.ContainsKey($m.Modul)) { 'D' } else { '' }),
            $text))
    }

    [void] $zeilen.Add('')
}

Set-Content -LiteralPath (Join-Path $Ziel 'MODULE-ALLE.md') -Value $zeilen -Encoding utf8

Write-Host ("MODULE-ALLE.md: {0} Module in {1} Familien, {2} cross-kompiliert" -f
    $s.Count, $familien.Count, $delphi.Count)
