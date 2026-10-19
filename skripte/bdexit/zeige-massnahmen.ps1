# Liest die Sanierungsmassnahmen eines Projekts aus und stellt sie je Variante
# gegenueber: Bauteile, Flaeche, Ziel-U-Wert, Kosten, Sowieso-Kosten und
# energiebedingte Mehrkosten.
#
# Die Sowieso-Kosten stehen nirgends gespeichert - sie sind
# SANKOSTEN - SANKOSTEN_EE. Genau diese Differenz entscheidet ueber die
# Foerderung im iSFP, und genau sie ist die Zahl, die man beim Pruefen sucht.
#
# Die Betraege je Variante sind KUMULATIV: ein Massnahmenpaket enthaelt die
# Massnahmen der vorangehenden. Deshalb wird zusaetzlich der Zuwachs je Paket
# ausgewiesen - das ist die Zahl, die im iSFP als Investition des Pakets steht.
#
#   .\zeige-massnahmen.ps1 -Ordner .\arbeit
#   .\zeige-massnahmen.ps1 -Ordner .\arbeit -Proj 21        # nur eine Variante
#   .\zeige-massnahmen.ps1 -Ordner .\arbeit -JeBauteil      # Bauteile einzeln
#   .\zeige-massnahmen.ps1 -Ordner .\arbeit -Csv .\massnahmen.csv

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [int[]]  $Proj,
    [switch] $JeBauteil,
    [string] $Csv
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$hf = Join-Path $Ordner 'TableHuellfl.BDExit'
$tp = Join-Path $Ordner 'TableProjekt.BDExit'
if (-not (Test-Path $hf)) { throw "$hf fehlt - ist der Container entpackt?" }

# Variantennamen aus TableProjekt, damit die Pakete beim Namen genannt werden.
$namen = @{}
if (Test-Path $tp) {
    $b = [System.IO.File]::ReadAllBytes($tp); $k = BdeKopf $b; $o = $k.Daten
    while ($o -lt $b.Length) {
        $r = BdeLies $b $k $o -1
        $id = ($r.Werte | Where-Object Name -eq 'PROJEKT_ID').Wert
        $bez = [string] ($r.Werte | Where-Object Name -eq 'VarianteBez').Wert
        $namen[[int] $id] = $(if ($bez) { $bez } else { 'Ist-Zustand' })
        $o = $r.Ende
    }
}

$b = [System.IO.File]::ReadAllBytes($hf); $k = BdeKopf $b; $o = $k.Daten
$zeilen = New-Object System.Collections.ArrayList
while ($o -lt $b.Length) {
    $r = BdeLies $b $k $o -1
    $g = @{}; foreach ($v in $r.Werte) { $g[$v.Name] = $v.Wert }
    if ($g['SANBEZ']) {
        $br = [double] $g['FLAECHE_BR']; if ($br -le 0) { $br = [double] $g['FLAECHE'] }
        $ges = [double] $g['SANKOSTEN']; $ee = [double] $g['SANKOSTEN_EE']
        $x = New-Object psobject
        $x | Add-Member NoteProperty Proj    ([int] $g['PROJ_ID'])
        $x | Add-Member NoteProperty Paket   ($namen[[int] $g['PROJ_ID']])
        $x | Add-Member NoteProperty Massnahme ([string] $g['SANBEZ'])
        $x | Add-Member NoteProperty Kz      ([string] $g['KENNZEICHEN'])
        $x | Add-Member NoteProperty Bauteil ([string] $g['BAUTEILBEZ'])
        $x | Add-Member NoteProperty Brutto  ([math]::Round($br, 2))
        $x | Add-Member NoteProperty UIst    ([double] $g['K_ZAHL'])
        $x | Add-Member NoteProperty UZiel   ([double] $g['SANK_ZAHL'])
        $x | Add-Member NoteProperty Gesamt  ([math]::Round($ges, 2))
        $x | Add-Member NoteProperty Sowieso ([math]::Round($ges - $ee, 2))
        $x | Add-Member NoteProperty Mehrkosten ([math]::Round($ee, 2))
        $null = $zeilen.Add($x)
    }
    $o = $r.Ende
}
if (-not $zeilen.Count) { throw "Keine Bauteile mit SANBEZ im Container - noch keine Massnahmen hinterlegt." }

$varianten = @($zeilen | Select-Object -ExpandProperty Proj -Unique | Sort-Object)
if ($Proj) { $varianten = @($varianten | Where-Object { $Proj -contains $_ }) }
if (-not $varianten) { throw "Keine der angegebenen Varianten hat Massnahmen." }

if ($Csv) { $zeilen | Export-Csv -Path $Csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'; "CSV: $Csv ($($zeilen.Count) Zeilen)" }

$vorG = 0.0; $vorS = 0.0; $vorE = 0.0
foreach ($v in $varianten) {
    $d = @($zeilen | Where-Object Proj -eq $v)
    $sg = ($d | Measure-Object Gesamt -Sum).Sum
    $ss = ($d | Measure-Object Sowieso -Sum).Sum
    $se = ($d | Measure-Object Mehrkosten -Sum).Sum
    ""
    "PROJ_ID {0} - {1}   {2} Bauteile, {3} Massnahmen" -f $v, $namen[$v], $d.Count, (@($d | Select-Object -ExpandProperty Massnahme -Unique).Count)
    "{0,-46} {1,3} {2,9} {3,6} {4,11} {5,11} {6,11}" -f 'Massnahme','n','Brutto m2','Ziel-U','Gesamt','Sowieso','Mehrkosten'
    foreach ($m in ($d | Group-Object Massnahme | Sort-Object { -(($_.Group | Measure-Object Gesamt -Sum).Sum) })) {
        $g2 = $m.Group
        "{0,-46} {1,3} {2,9:N2} {3,6:N2} {4,11:N2} {5,11:N2} {6,11:N2}" -f `
            $m.Name.Substring(0, [Math]::Min(45, $m.Name.Length)), $g2.Count,
            (($g2 | Measure-Object Brutto -Sum).Sum), $g2[0].UZiel,
            (($g2 | Measure-Object Gesamt -Sum).Sum), (($g2 | Measure-Object Sowieso -Sum).Sum), (($g2 | Measure-Object Mehrkosten -Sum).Sum)
        if ($JeBauteil) {
            $g2 | Sort-Object Bauteil | ForEach-Object {
                "    {0,-42} {1,3} {2,9:N2} {3,6:N2} {4,11:N2} {5,11:N2} {6,11:N2}" -f `
                    $_.Bauteil.Substring(0, [Math]::Min(41, $_.Bauteil.Length)), $_.Kz, $_.Brutto, $_.UZiel, $_.Gesamt, $_.Sowieso, $_.Mehrkosten
            }
        }
    }
    "{0,-46} {1,3} {2,9} {3,6} {4,11:N2} {5,11:N2} {6,11:N2}" -f 'SUMME kumulativ', $d.Count, '', '', $sg, $ss, $se
    "{0,-46} {1,3} {2,9} {3,6} {4,11:N2} {5,11:N2} {6,11:N2}" -f '  davon neu in diesem Paket', '', '', '', ($sg - $vorG), ($ss - $vorS), ($se - $vorE)
    if ($sg -gt 0) { "  energiebedingter Anteil: {0:N0} % der Investition" -f ($se / $sg * 100) }
    $vorG = $sg; $vorS = $ss; $vorE = $se
}
