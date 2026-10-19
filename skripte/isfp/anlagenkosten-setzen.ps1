# Traegt die Anlagenkosten je Variante in TableAnlage.InvestKostenText ein.
#
# Warum ausgerechnet dieses Feld: Die iSFP-Maske legt die Anlagen-Komponenten
# (Heizung, Warmwasser, Lueftung, PV) NICHT aus dem Rechenmodell an, sondern aus
# den Kostenzeilen der Sanierungsvariante. Ist das Feld leer, meldet sie
# "Dieses Massnahmenpaket enthaelt keine Massnahmenkomponenten" - und kein Text
# der Welt kommt dann in dieses Paket, auch keiner, den man direkt in die
# iSFP2.xml schreibt. An Hesse nachgemessen:
#
#   ANLAGE_ID 12 (MP2): "Lüftungsanlage mit WRG, dezentral"  -> MP2 bekommt SK_LUEFTUNG
#   ANLAGE_ID 14 (MP4): PV + Waermepumpe + Hydr. Abgleich    -> MP4 bekommt SK_HEIZUNG
#                                                               mit drei Ausfuehrungen
#                                                               und SK_WARMWASSER
#
# Varianten sind kumulativ: eine Zeile, die ab Paket n gilt, steht auch in allen
# folgenden. Neu ist sie nur in Paket n - und genau dort entsteht die Komponente.
#
#   .\anlagenkosten-setzen.ps1 -Projekt 'Klenke'              # Vorschau
#   .\anlagenkosten-setzen.ps1 -Projekt 'Klenke' -Schreiben
#
# Geschrieben wird ueber container.ps1 -Zurueck, also mit Sicherung, Pruefstein
# und Gegenprobe aus der Datenbank. Energie.exe muss geschlossen sein.

param(
    [Parameter(Mandatory)] [string] $Projekt,
    [string] $Werkzeug = $PSScriptRoot,
    [string] $Bdexit   = 'C:\Projekte_Dev\hsetu-decompiled\werkzeuge\bdexit',
    [string] $Ablage,
    [switch] $Schreiben,
    [switch] $Vorschau
)

$ErrorActionPreference = 'Stop'
if (-not $Schreiben) { $Vorschau = $true }
if (-not $Ablage) { $Ablage = Join-Path $Werkzeug 'laeufe' }
. (Join-Path $Bdexit 'bde.ps1')
. (Join-Path $Bdexit 'satz.ps1')

$kosten = Get-Content (Join-Path $Werkzeug 'anlagenkosten.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# --- Container holen
$stempel = Get-Date -Format 'yyyyMMdd-HHmmss'
$arbeit  = Join-Path $Ablage "anlagenkosten_$stempel"
New-Item -ItemType Directory -Force -Path $arbeit | Out-Null
& (Join-Path $Bdexit 'container.ps1') -Projekt $Projekt -Ordner $arbeit | Out-Host

# --- Projektname bestimmen und Kostenzeilen dazu finden
$roh  = [System.IO.File]::ReadAllBytes((Join-Path $arbeit 'TableProjekt.BDExit'))
$kopf = BdeKopf $roh; $pos = $kopf.Daten
# Bewusst KEINE [ordered]-Hashtable: die deutet einen ganzzahligen Index als
# Position, nicht als Schluessel - $namen[3] waere dann der dritte Eintrag.
$namen = @{}; $projektName = $null
while ($pos -lt $roh.Length) {
    $s = BdeLies $roh $kopf $pos -1; $h = @{}
    foreach ($v in $s.Werte) { $h[$v.Name] = $v.Wert }
    $namen[[int]$h['PROJEKT_ID']] = [string]$h['VarianteBez']
    if (-not $projektName) { $projektName = [string]$h['BEZEICHNUNG'] }
    $pos = $s.Ende
}
$eintrag = $kosten.PSObject.Properties | Where-Object { $_.Name -eq $projektName } | Select-Object -First 1
if (-not $eintrag) { throw "In anlagenkosten.json gibt es keinen Eintrag fuer '$projektName'." }
$zeilen = $eintrag.Value.zeilen
Write-Host "`nProjekt: $projektName   ($($zeilen.Count) Kostenzeilen hinterlegt)" -ForegroundColor Cyan

# --- Varianten ordnen: erste ID = Ist, danach Paket 1..n
$ids = @($namen.Keys | Sort-Object)
$istId = $ids[0]
$paketIds = @($ids | Where-Object { $_ -ne $istId })

# --- je Variante den kumulativen Text bauen
$plan = @{}
for ($i = 0; $i -lt $paketIds.Count; $i++) {
    $paket = $i + 1
    $gueltig = @($zeilen | Where-Object { [int]$_.ab -le $paket })
    if (-not $gueltig) { continue }
    $text = ($gueltig | ForEach-Object {
        '{0}|{1}|{2}|{3}' -f $_.bezeichnung, $_.invest, $_.invest_ee, $_.betrieb
    }) -join "`r`n"
    # Neben dem Text fuehrt die Software zwei SUMMEN mit. Ohne sie legt die
    # iSFP-Maske keine Anlagen-Komponente an - der Text allein genuegt nicht.
    # An allen sechs Varianten von Hesse nachgerechnet:
    #   InvestKosten    = Summe der Invest-Spalte
    #   InvestKosten_EE = Summe der Invest_EE-Spalte
    $plan[$paketIds[$i]] = [pscustomobject]@{
        Paket = $paket; Name = $namen[$paketIds[$i]]; Text = $text
        Summe   = ($gueltig | Measure-Object -Property invest    -Sum).Sum
        SummeEE = ($gueltig | Measure-Object -Property invest_ee -Sum).Sum
        Neu = @($zeilen | Where-Object { [int]$_.ab -eq $paket })
    }
}

Write-Host ""
foreach ($id in ($plan.Keys | Sort-Object)) {
    $p = $plan[$id]
    Write-Host ("ANLAGE_ID {0}  MP{1} {2}" -f $id, $p.Paket, $p.Name) -ForegroundColor Yellow
    foreach ($z in ($p.Text -split "`r`n")) {
        $f = $z -split '\|'
        $istNeu = $p.Neu | Where-Object { $_.bezeichnung -eq $f[0] }
        Write-Host ("     {0,-46} {1,8} EUR   davon energiebedingt {2,8} EUR  {3}" -f `
            $f[0], $f[1], $f[2], $(if ($istNeu) { '<- neu in diesem Paket' } else { '' }))
    }
    Write-Host ("     {0,-46} {1,8:N0} EUR   davon energiebedingt {2,8:N0} EUR" -f 'SUMME (InvestKosten / _EE)', $p.Summe, $p.SummeEE) -ForegroundColor DarkGray
}

if ($Vorschau) {
    Write-Host "`nVORSCHAU - nichts geschrieben. Zum Schreiben denselben Aufruf mit -Schreiben." -ForegroundColor Magenta
    Write-Host "Arbeitsordner: $arbeit"
    return
}

# --- schreiben
foreach ($id in ($plan.Keys | Sort-Object)) {
    & (Join-Path $Bdexit 'setze-feld.ps1') -Ordner $arbeit -Tabelle 'TableAnlage' `
        -Feld 'InvestKostenText' -Wert $plan[$id].Text -Proj $id | Out-Host
    & (Join-Path $Bdexit 'setze-feld.ps1') -Ordner $arbeit -Tabelle 'TableAnlage' `
        -Feld 'InvestKosten'    -Wert $plan[$id].Summe   -Proj $id | Out-Host
    & (Join-Path $Bdexit 'setze-feld.ps1') -Ordner $arbeit -Tabelle 'TableAnlage' `
        -Feld 'InvestKosten_EE' -Wert $plan[$id].SummeEE -Proj $id | Out-Host
}
& (Join-Path $Bdexit 'container.ps1') -Projekt $Projekt -Ordner $arbeit -Zurueck | Out-Host

Write-Host "`nGeschrieben. Jetzt im Energieberater die iSFP-Maske oeffnen und die Daten" -ForegroundColor Green
Write-Host "aktualisieren (Knopf 'iSFP-Daten ...' unten links) - dann legt sie die"
Write-Host "Anlagen-Komponenten in MP2, MP4 und MP5 an."
