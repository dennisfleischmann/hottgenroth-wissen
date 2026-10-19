# Prueft die Varianten eines Containers auf Vollstaendigkeit, Uebereinstimmung
# der Modelle und Wirksamkeit der Massnahmen.
#
# WARUM ES DIESE PRUEFUNG BRAUCHT
#
# Alle bisherigen Pruefungen waren SELBSTPRUEFUNGEN: Rueckschreibprobe
# byte-identisch, Satzzahl stimmt, Rundlauf lesen->schreiben unveraendert. Sie
# beantworten "steht da, was ich geschrieben habe" - und liefen fehlerfrei
# durch, waehrend eine Variante saniere U-Werte ANZEIGTE und mit den alten
# RECHNETE.
#
# Der Grund: derselbe Sachverhalt steht an zwei Stellen.
#
#   TableHuellfl.SANK_ZAHL             was die Oberflaeche anzeigt
#   Kernel18599V5 -> Construction.fU   was gerechnet wird
#
# Eine Selbstpruefung kann das nie finden. Deshalb hier drei Pruefungen anderer
# Art:
#
#   1 Vollstaendigkeit  traegt die Variante in allen neun Tabellen einen Satz,
#                       und ebenso viele Bauteile wie der Ist-Zustand?
#   2 Querprobe         stimmt das Rechenmodell mit der Bauteilliste ueberein?
#                       (ibp-uwert-setzen.exe im Pruefmodus)
#   3 Wirkungsprobe     sinkt UA entlang des Fahrplans monoton, und bewegt
#                       sich ueberhaupt etwas, wo eine Massnahme steht?
#
# Die Wirkungsprobe ist die einzige, die auch dann anschlaegt, wenn der
# Sachverhalt an einer DRITTEN Stelle steht, die noch niemand kennt: bewegt
# sich die Physik nicht, ist die Massnahme nicht angekommen - unabhaengig
# davon, welche Darstellung ich uebersehen habe.
#
#   .\pruefe-variante.ps1 -Ordner .\entpackt
#   .\pruefe-variante.ps1 -Ordner .\entpackt -Fahrplan 2,3,4,5,6,7

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [int[]] $Fahrplan,
    [int[]] $Ueberspringen = @()
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

$ibp = Join-Path (Split-Path $PSScriptRoot -Parent) 'ibp'
$setzen = Join-Path $ibp 'ibp-uwert-setzen.exe'
$lesen = Join-Path $ibp 'ibp-bauteile.exe'
foreach ($p in @($setzen, $lesen)) { if (-not (Test-Path $p)) { throw "$p fehlt - erst bauen" } }

function Lies([string] $Datei) {
    $b = [System.IO.File]::ReadAllBytes($Datei)
    $k = BdeKopf $b
    $s = @(); $o = $k.Daten
    while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $s += $r; $o = $r.Ende }
    if ($s.Count -ne $k.Satzzahl) { throw "$(Split-Path $Datei -Leaf): $($s.Count) Saetze, Kopf sagt $($k.Satzzahl)" }
    @{ Bytes = $b; Kopf = $k; Saetze = $s }
}
function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }
function Da($r, $n) { ($r.Werte | Where-Object Name -eq $n).Da }

$tabellen = @{}
foreach ($f in Get-ChildItem $Ordner -Filter *.BDExit) { $tabellen[$f.BaseName] = Lies $f.FullName }
$th = $tabellen['TableHuellfl']
$tz = $tabellen['TableZusatz']
$tp = $tabellen['TableProjekt']

$varianten = @($tp.Saetze | ForEach-Object { [int] (Wert $_ 'PROJEKT_ID') } | Sort-Object)
$ist = $varianten[0]
$bauteileIst = @($th.Saetze | Where-Object { (Wert $_ 'PROJ_ID') -eq $ist }).Count

$arbeit = Join-Path $env:TEMP ('pruefe-variante-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $arbeit | Out-Null

$ergebnis = New-Object System.Collections.ArrayList

foreach ($v in $varianten) {
    if ($Ueberspringen -contains $v) { continue }
    $name = [string] (Wert (@($tp.Saetze | Where-Object { (Wert $_ 'PROJEKT_ID') -eq $v })[0]) 'VarianteBez')
    if (-not $name) { $name = '(Ist-Zustand)' }
    $mangel = New-Object System.Collections.ArrayList

    # ---- 1 Vollstaendigkeit
    foreach ($n in ($tabellen.Keys | Sort-Object)) {
        $t = $tabellen[$n]
        $bezug = [string] ($t.Kopf.Felder | Where-Object { $_.Name -eq 'PROJ_ID' -or $_.Name -eq 'ProjektID' } |
                   ForEach-Object { $_.Name } | Select-Object -First 1)
        if (-not $bezug) { $bezug = [string] $t.Kopf.Felder[0].Name }
        if (-not @($t.Saetze | Where-Object { (Wert $_ $bezug) -eq $v })) {
            [void] $mangel.Add("$n fuehrt keinen Satz")
        }
    }
    $anz = @($th.Saetze | Where-Object { (Wert $_ 'PROJ_ID') -eq $v }).Count
    if ($anz -ne $bauteileIst) { [void] $mangel.Add("$anz Bauteile statt $bauteileIst wie im Ist-Zustand") }

    # ---- Blob herausloesen
    $blob = Join-Path $arbeit "v$v.bin"
    $satz = @($tz.Saetze | Where-Object { (Wert $_ 'PROJ_ID') -eq $v })
    $ua = $null
    if ($satz.Count -eq 1 -and (Da $satz[0] 'Kernel18599V5')) {
        $feld = $satz[0].Werte | Where-Object Name -eq 'Kernel18599V5'
        $roh = New-Object byte[] ($feld.Roh.Length - 4)
        [Array]::Copy($feld.Roh, 4, $roh, 0, $roh.Length)
        [System.IO.File]::WriteAllBytes($blob, $roh)

        # ---- 2 Querprobe Bauteilliste <-> Rechenmodell
        $eintraege = foreach ($s in @($th.Saetze | Where-Object { (Wert $_ 'PROJ_ID') -eq $v })) {
            $u = if (Da $s 'SANK_ZAHL') { Wert $s 'SANK_ZAHL' } else { Wert $s 'K_ZAHL' }
            $sl = if ((Wert $s 'KENNZEICHEN') -eq 'FA') { 'fenster' } else { 'u' }
            '{ "name": ' + (([string] (Wert $s 'BAUTEILBEZ')) | ConvertTo-Json) + ', "' + $sl + '": ' +
                ([double] $u).ToString([System.Globalization.CultureInfo]::InvariantCulture) + ' }'
        }
        $jd = Join-Path $arbeit "v$v.json"
        [System.IO.File]::WriteAllText($jd, '{ "bauteile": [' + ($eintraege -join ',') + '] }', [System.Text.Encoding]::UTF8)

        # Ein befundener Unterschied ist hier das ERWARTETE Ergebnis, kein
        # Programmabbruch. Mit ErrorActionPreference='Stop' macht PowerShell
        # aus jeder Fehlerausgabe eines Programms eine Ausnahme - dann wuerde
        # die Pruefung genau an der Stelle abbrechen, an der sie etwas findet.
        $vorher = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $q = & $setzen $blob '-' $jd 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $vorher
        if ($code -ne 0) {
            $zeilen = @($q | Where-Object { $_ -match 'Modell rechnet mit' })
            if ($zeilen.Count) {
                [void] $mangel.Add("Rechenmodell weicht bei $($zeilen.Count) Bauteilen ab: " +
                    (($zeilen | Select-Object -First 2 | ForEach-Object { ($_ -replace '\s{2,}', ' ').Trim() }) -join ' / '))
            } else {
                # Abbruch aus einem anderen Grund - Anzahl, Reihenfolge, Zone.
                # Die Meldung des Werkzeugs unveraendert weiterreichen, statt
                # sie unter "0 Bauteile" verschwinden zu lassen.
                [void] $mangel.Add((($q | Where-Object { $_ -match '\S' } |
                    Select-Object -First 2 | ForEach-Object { ($_ -replace '\s{2,}', ' ').Trim() }) -join ' / '))
            }
        }

        # ---- 3 UA fuer die Wirkungsprobe
        # Das @() ist nicht kosmetisch: ohne es ist $z bei genau einem Treffer
        # eine Zeichenkette, und $z[0] liefert dann deren erstes ZEICHEN.
        $vorher = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $b = & $lesen $blob 2>&1
        $ErrorActionPreference = $vorher
        $z = @($b | Where-Object { $_ -match '^UA gesamt:' })
        if ($z.Count -and $z[0] -match '^UA gesamt:\s*([\d.,]+)') {
            $ua = [double] ($Matches[1] -replace '\.', '' -replace ',', '.')
        }
    } else {
        [void] $mangel.Add("kein Kernel18599V5 - die Variante hat kein Rechenmodell")
    }

    [void] $ergebnis.Add([pscustomobject]@{
        Proj = $v; Name = $name; Bauteile = $anz; UA = $ua
        Urteil = $(if ($mangel.Count) { 'FEHLER' } else { 'ok' })
        Mangel = ($mangel -join '; ')
    })
}

""
"Varianten im Container: $($varianten -join ', ')   Ist-Zustand: $ist"
""
$ergebnis | Format-Table -AutoSize -Wrap @{n='Proj';e={$_.Proj}}, @{n='Variante';e={$_.Name}},
    @{n='Bauteile';e={$_.Bauteile}}, @{n='UA W/K';e={ if ($null -eq $_.UA) { '-' } else { '{0:0.0}' -f $_.UA } }},
    Urteil, Mangel

# ---- Wirkungsprobe entlang des Fahrplans
$fehler = @($ergebnis | Where-Object Urteil -eq 'FEHLER').Count
if ($Fahrplan) {
    ""
    "Wirkungsprobe entlang des Fahrplans:"
    $vorher = $null; $vorherName = $null
    foreach ($v in $Fahrplan) {
        $e = $ergebnis | Where-Object Proj -eq $v
        if (-not $e) { "  $v : nicht im Container"; $fehler++; continue }
        if ($null -eq $e.UA) { "  $v : kein UA ermittelbar"; $fehler++; continue }
        if ($null -eq $vorher) {
            "  {0,-22} UA {1,7:0.0} W/K   (Ausgangswert)" -f $e.Name, $e.UA
        } else {
            $d = $e.UA - $vorher
            $hinweis = ''
            if ($d -gt 0.05) { $hinweis = '   FEHLER: UA STEIGT gegenueber der Vorstufe'; $fehler++ }
            elseif ([math]::Abs($d) -le 0.05) { $hinweis = '   keine Huellenwirkung - richtig bei einer reinen Anlagenmassnahme, sonst nicht angekommen' }
            "  {0,-22} UA {1,7:0.0} W/K   {2,7:+0.0;-0.0;0.0}   {3,6:0.0} % gegen Ausgang{4}" -f
                $e.Name, $e.UA, $d, (100 * ($e.UA / ($ergebnis | Where-Object Proj -eq $Fahrplan[0]).UA - 1)), $hinweis
        }
        $vorher = $e.UA; $vorherName = $e.Name
    }
}

""
if ($fehler) { "FEHLGESCHLAGEN: $fehler Beanstandungen"; exit 1 }
"alle Varianten vollstaendig, Bauteilliste und Rechenmodell einig"
