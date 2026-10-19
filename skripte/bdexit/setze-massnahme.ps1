# Hinterlegt eine SANIERUNGSMASSNAHME an einer Gruppe von Bauteilen: Bezeichnung,
# Ziel-U-Wert, Kosten und energiebedingte Mehrkosten in einem Aufruf.
#
# saniere.ps1 setzt nur SANK_ZAHL. Zu einer Massnahme gehoeren aber acht Felder,
# und ohne sie bleibt die Wirtschaftlichkeitstabelle leer:
#
#   SANBEZ            Bezeichnung - ohne sie steht in der Wirtschaftlichkeit kein Name
#   SANK_ZAHL         Ziel-U-Wert
#   SANKOSTENQM       Kosten je m2, gesamt
#   SANKOSTEN         = SANKOSTENQM * FLAECHE_BR      (gerechnet, nicht eingegeben)
#   SANKOSTENQM_EE    energiebedingte Mehrkosten je m2
#   SANKOSTEN_EE      = SANKOSTENQM_EE * FLAECHE_BR
#   SANDICKE          Daemmstoffdicke cm      (nur wenn angegeben)
#   SANLAMBDA         Waermeleitfaehigkeit    (nur wenn angegeben)
#
# Die Sowieso-Kosten stehen NIRGENDS: sie sind SANKOSTEN - SANKOSTEN_EE und
# werden von der Software daraus gebildet. Wer nur SANKOSTEN setzt, bekommt eine
# Massnahme, die zu 100 % als energiebedingt gilt - und damit eine zu hohe
# Foerderung im iSFP.
#
# Bezugsflaeche ist FLAECHE_BR (brutto), nicht FLAECHE (netto nach Abzug von
# Fenstern und Tueren). An 33 Bauteilen geprueft: SANKOSTEN / SANKOSTENQM trifft
# FLAECHE_BR auf die zweite Stelle. Fehlt das Feld, wird FLAECHE genommen und
# das gemeldet.
#
# AUSWAHL ueber Bauteilmuster, nicht nur ueber das Kennzeichen: an einem
# Kennzeichen haengen oft mehrere Massnahmen. Im Projekt Messinger tragen die
# WA-Bauteile "WDVS Aussendaemmung" (266 EUR/m2) UND "WDVS Kellerwand"
# (289 EUR/m2) - ein Aufruf je Kennzeichen wuerde beide gleich setzen.
#
#   .\setze-massnahme.ps1 -Ordner .\entpackt -Proj 19 -Kennzeichen WA `
#        -Bauteile 'AW 003*','AW 006*','AW 001-2*','AW 004-2*' `
#        -Bezeichnung 'WDVS Aussendaemmung, WLS035 12cm' `
#        -ZielU 0.19 -KostenQm 266 -MehrkostenQm 109 -Dicke 12 -Lambda 0.035
#
#   .\setze-massnahme.ps1 -Ordner .\entpackt -Proj 21 -Kennzeichen BE `
#        -Bezeichnung 'Fussbodendaemmung, Keller, WLS035 12cm' `
#        -ZielU 0.24 -KostenQm 150                      # ohne -MehrkostenQm: 100 % energiebedingt
#
#   .\setze-massnahme.ps1 -Ordner .rbeit -Proj 3 -Kennzeichen WA -Bezeichnung 'WDVS 16 cm' `
#        -ZielU 0.20 -Kosten 24200 -Mehrkosten 11000   # GESAMTbetraege, Skript rechnet um
#
#   ... -Vorschau        zeigt die Treffer und rechnet, schreibt aber nicht
#   ... -Loeschen        entfernt die Massnahme wieder (alle acht Felder)

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [Parameter(Mandatory)] [int]    $Proj,
    # Auswahl: Kennzeichen und/oder Muster auf BAUTEILBEZ. Beides zusammen = UND.
    [string]   $Kennzeichen,
    [string[]] $Bauteile,
    [string] $Bezeichnung,
    [double] $ZielU         = -1,
    [double] $KostenQm      = -1,
    # ohne Angabe = wie KostenQm, also 100 % energiebedingt und keine Sowieso-Kosten
    [double] $MehrkostenQm  = -1,
    # GESAMTbetraege in Euro statt Preise je Einheit. Das Skript summiert dann
    # FLAECHE_BR ueber alle getroffenen Bauteile und rechnet selbst um. Gedacht
    # fuer Aufrufer, die die Bezugsflaeche nicht kennen - der Sanierungsplan der
    # fs-app fuehrt Gesamtbetraege, weil ein Preis je m2 dort die NETTOflaeche
    # meinte und hier die BRUTTOflaeche gilt.
    [double] $Kosten        = -1,
    [double] $Mehrkosten    = -1,
    [double] $Dicke         = -1,
    [double] $Lambda        = -1,
    [switch] $Loeschen,
    [switch] $Vorschau
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

if (-not $Kennzeichen -and -not $Bauteile) {
    throw 'Ohne -Kennzeichen und ohne -Bauteile wuerde die Massnahme an ALLEN Bauteilen der Variante landen. Eines von beiden angeben.'
}
if (-not $Loeschen) {
    if (-not $Bezeichnung) { throw '-Bezeichnung fehlt. Ohne sie bleibt die Zeile in der Wirtschaftlichkeit namenlos.' }
    if ($ZielU -lt 0)      { throw '-ZielU fehlt.' }
    if ($Bezeichnung.Length -gt 255) { throw "-Bezeichnung ist $($Bezeichnung.Length) Zeichen lang, das Feld fasst 255." }
}
if ($Kosten -ge 0 -and $KostenQm -ge 0) {
    throw '-Kosten (Gesamtbetrag) und -KostenQm (Preis je Einheit) schliessen sich aus. Eines von beiden.'
}
if ($Mehrkosten -ge 0 -and $Kosten -lt 0) {
    throw '-Mehrkosten ohne -Kosten. Gesamtbetraege gehoeren zusammen.'
}
if ($Kosten -ge 0 -and $Mehrkosten -gt $Kosten) {
    throw "Mehrkosten ($Mehrkosten EUR) groesser als Gesamtkosten ($Kosten EUR) - das ergaebe negative Sowieso-Kosten."
}
if ($MehrkostenQm -lt 0 -and $KostenQm -ge 0) { $MehrkostenQm = $KostenQm }
if ($MehrkostenQm -gt $KostenQm -and $KostenQm -ge 0) {
    throw "Mehrkosten ($MehrkostenQm EUR/m2) groesser als Gesamtkosten ($KostenQm EUR/m2) - das ergaebe negative Sowieso-Kosten."
}

$datei = Join-Path $Ordner 'TableHuellfl.BDExit'
if (-not (Test-Path $datei)) { throw "$datei fehlt - ist der Container entpackt?" }
$b = [System.IO.File]::ReadAllBytes($datei)
$k = BdeKopf $b

$pflicht = 'SANBEZ','SANK_ZAHL','SANKOSTENQM','SANKOSTEN','SANKOSTENQM_EE','SANKOSTEN_EE','SANDICKE','SANLAMBDA','FLAECHE_BR','FLAECHE'
$fehlt = $pflicht | Where-Object { $n = $_; -not ($k.Felder | Where-Object Name -eq $n) }
if ($fehlt) { throw "In TableHuellfl fehlen Felder: $($fehlt -join ', ')" }

$saetze = @(); $o = $k.Daten
while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $saetze += $r; $o = $r.Ende }
if ($saetze.Count -ne $k.Satzzahl) { throw "$($saetze.Count) Saetze gelesen, Kopf sagt $($k.Satzzahl)" }

function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }
function Da($r, $n)   { ($r.Werte | Where-Object Name -eq $n).Da }

function Trifft($r) {
    if ((Wert $r 'PROJ_ID') -ne $Proj) { return $false }
    if ($Kennzeichen -and (Wert $r 'KENNZEICHEN') -ne $Kennzeichen) { return $false }
    if ($Bauteile) {
        $bez = [string](Wert $r 'BAUTEILBEZ')
        $treffer = $false
        foreach ($m in $Bauteile) { if ($bez -like $m) { $treffer = $true; break } }
        if (-not $treffer) { return $false }
    }
    return $true
}

# Gesamtbetrag -> Preis je Einheit. Muss VOR der Schleife passieren, weil die
# Bezugsflaeche die Summe ueber ALLE Treffer ist: eine Kennung trifft oft mehrere
# Bauteile, und der Betrag gilt fuer sie zusammen. Erst danach setzt die Schleife
# denselben Quadratmeterpreis an jedem einzelnen - so trifft die Summe der
# SANKOSTEN wieder den geplanten Betrag.
if ($Kosten -ge 0) {
    $summeBrutto = 0.0
    foreach ($s in $saetze) {
        if (-not (Trifft $s)) { continue }
        $f = [double](Wert $s 'FLAECHE_BR')
        if (-not (Da $s 'FLAECHE_BR') -or $f -le 0) { $f = [double](Wert $s 'FLAECHE') }
        $summeBrutto += $f
    }
    if ($summeBrutto -le 0) {
        throw "Die getroffenen Bauteile haben keine Flaeche - ein Gesamtbetrag laesst sich nicht umrechnen."
    }
    $KostenQm     = [math]::Round($Kosten / $summeBrutto, 6)
    $MehrkostenQm = if ($Mehrkosten -ge 0) { [math]::Round($Mehrkosten / $summeBrutto, 6) } else { $KostenQm }
    "Gesamtbetrag {0:N2} EUR auf {1:N2} m2 Bezugsflaeche  ->  {2:N4} EUR/m2 gesamt, {3:N4} EUR/m2 energiebedingt" -f `
        $Kosten, $summeBrutto, $KostenQm, $MehrkostenQm
}

$strom = New-Object System.Collections.Generic.List[byte]
$zeilen = @(); $nettoErsatz = 0
$sumGes = 0.0; $sumEE = 0.0
foreach ($s in $saetze) {
    $setze = @{}
    if (Trifft $s) {
        $bez = [string](Wert $s 'BAUTEILBEZ')
        if ($Loeschen) {
            foreach ($f in 'SANBEZ','SANK_ZAHL','SANKOSTENQM','SANKOSTEN','SANKOSTENQM_EE','SANKOSTEN_EE','SANDICKE','SANLAMBDA') {
                $setze[$f] = $(if ($f -eq 'SANBEZ') { '' } else { 0.0 })
            }
            $zeilen += [pscustomobject]@{ Id=(Wert $s 'HUELL_ID'); Bez=$bez; Brutto=0.0; Ges=0.0; EE=0.0; Sowieso=0.0; Hinweis='geloescht' }
        }
        else {
            $brutto = [double](Wert $s 'FLAECHE_BR')
            $hinweis = ''
            if (-not (Da $s 'FLAECHE_BR') -or $brutto -le 0) {
                $brutto = [double](Wert $s 'FLAECHE'); $hinweis = 'FLAECHE_BR fehlt -> netto'; $nettoErsatz++
            }
            $setze['SANBEZ']    = $Bezeichnung
            $setze['SANK_ZAHL'] = $ZielU
            if ($KostenQm -ge 0) {
                $ges = [math]::Round($KostenQm * $brutto, 4)
                $ee  = [math]::Round($MehrkostenQm * $brutto, 4)
                $setze['SANKOSTENQM']    = $KostenQm
                $setze['SANKOSTEN']      = $ges
                $setze['SANKOSTENQM_EE'] = $MehrkostenQm
                $setze['SANKOSTEN_EE']   = $ee
                $sumGes += $ges; $sumEE += $ee
            } else { $ges = 0.0; $ee = 0.0 }
            if ($Dicke  -ge 0) { $setze['SANDICKE']  = $Dicke }
            if ($Lambda -ge 0) { $setze['SANLAMBDA'] = $Lambda }
            $zeilen += [pscustomobject]@{
                Id=(Wert $s 'HUELL_ID'); Bez=$bez; Brutto=[math]::Round($brutto,2)
                Ges=[math]::Round($ges,2); EE=[math]::Round($ee,2); Sowieso=[math]::Round($ges-$ee,2); Hinweis=$hinweis
            }
        }
    }
    $strom.AddRange([byte[]] (BdeSchreib $b $k $s $setze))
}

if (-not $zeilen) {
    $filter = @(); if ($Kennzeichen) { $filter += "Kennzeichen $Kennzeichen" }; if ($Bauteile) { $filter += "Muster $($Bauteile -join ', ')" }
    throw "Kein Bauteil in PROJ_ID $Proj trifft auf $($filter -join ' und ')."
}

if ($Loeschen) { "PROJ_ID {0}: Massnahme an {1} Bauteilen entfernt" -f $Proj, $zeilen.Count }
else {
    "PROJ_ID {0}  '{1}'   Ziel-U {2}   {3} EUR/m2 gesamt, {4} EUR/m2 energiebedingt" -f $Proj, $Bezeichnung, $ZielU, $KostenQm, $MehrkostenQm
    "{0,5}  {1,-46} {2,8} {3,11} {4,11} {5,11}" -f 'ID','Bauteil','Brutto m2','Gesamt','Sowieso','Mehrkosten'
    $zeilen | ForEach-Object { "{0,5}  {1,-46} {2,8:N2} {3,11:N2} {4,11:N2} {5,11:N2} {6}" -f $_.Id, $_.Bez.Substring(0,[Math]::Min(45,$_.Bez.Length)), $_.Brutto, $_.Ges, $_.Sowieso, $_.EE, $_.Hinweis }
    "{0,5}  {1,-46} {2,8} {3,11:N2} {4,11:N2} {5,11:N2}" -f '', "SUMME ($($zeilen.Count) Bauteile)", '', $sumGes, ($sumGes-$sumEE), $sumEE
    if ($nettoErsatz) { "  ! bei $nettoErsatz Bauteil(en) fehlte FLAECHE_BR - mit der Nettoflaeche gerechnet" }
}

if ($Vorschau) { 'Vorschau - nichts geschrieben'; return }

$kopf = New-Object byte[] $k.Daten
[Array]::Copy($b, 0, $kopf, 0, $k.Daten)
[System.IO.File]::WriteAllBytes($datei, ($kopf + $strom.ToArray()))

# Gegenprobe am geschriebenen Stand - im Speicher zu setzen beweist nichts.
$b2 = [System.IO.File]::ReadAllBytes($datei)
$k2 = BdeKopf $b2
$n = 0; $geprueft = 0; $o = $k2.Daten
while ($o -lt $b2.Length) {
    $r = BdeLies $b2 $k2 $o -1
    if (Trifft $r) {
        $geprueft++
        if ($Loeschen) {
            if ("$(Wert $r 'SANBEZ')" -ne '') { throw "Gegenprobe: SANBEZ steht noch an HUELL_ID $(Wert $r 'HUELL_ID')" }
        } else {
            if ("$(Wert $r 'SANBEZ')" -ne $Bezeichnung) { throw "Gegenprobe: SANBEZ '$(Wert $r 'SANBEZ')' an HUELL_ID $(Wert $r 'HUELL_ID')" }
            if ([math]::Abs([double](Wert $r 'SANK_ZAHL') - $ZielU) -gt 1e-6) { throw "Gegenprobe: SANK_ZAHL $(Wert $r 'SANK_ZAHL') statt $ZielU" }
            if ($KostenQm -ge 0) {
                $soll = [math]::Round($KostenQm * [double](Wert $r 'FLAECHE_BR'), 2)
                $ist  = [math]::Round([double](Wert $r 'SANKOSTEN'), 2)
                if ([math]::Abs($ist - $soll) -gt 0.02 -and (Da $r 'FLAECHE_BR')) { throw "Gegenprobe: SANKOSTEN $ist statt $soll an HUELL_ID $(Wert $r 'HUELL_ID')" }
            }
        }
    }
    $n++; $o = $r.Ende
}
if ($n -ne $k2.Satzzahl) { throw "Gegenprobe: $n statt $($k2.Satzzahl) Saetze" }
if ($geprueft -ne $zeilen.Count) { throw "Gegenprobe: $geprueft statt $($zeilen.Count) Treffer" }
"Tabelle {0} -> {1} Bytes, Satzzahl unveraendert {2}, {3} Bauteile geprueft - Gegenprobe bestanden" -f $b.Length, $b2.Length, $k2.Satzzahl, $geprueft
