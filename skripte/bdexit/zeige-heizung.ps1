# Zeigt das Ergebnis der Anlagentechnik je Variante - die WIRKUNGSPROBE fuer die
# Heizung. Gegenstueck zu zeige-massnahmen.ps1, das die Bauteilseite zeigt.
#
# WARUM ES DIESE PRUEFUNG BRAUCHT
#
# pruefe-variante.ps1 misst die Wirkung an UA, also an der Huelle. Fuer die
# Anlagentechnik sagt UA nichts: eine Waermepumpe aendert keinen U-Wert. Wer
# eine Heizung von aussen setzt und nur zurueckliest, hat eine Selbstpruefung -
# und die war am 13.08.2026 gruen, waehrend die Software
# "Keine Heizung vorhanden" schrieb.
#
# Die Wirkung der Anlagentechnik steht in TableHeizung. Das ist ERGEBNIS, keine
# Eingabe: die Software schreibt den Satz beim Rechnen. Daraus folgen die zwei
# Aussagen, die dieses Werkzeug liefert:
#
#   1  KEIN SATZ heisst NICHT GERECHNET. Das ist unabhaengig davon, ob die
#      Variante einen Blob fuehrt: der wird beim Anlegen mitkopiert, jede
#      Variante hat also meist ein Modell. Erst der Satz in TableHeizung sagt,
#      dass die Software darauf gerechnet hat. Fehlt er, ist nichts angekommen -
#      egal was im Blob steht (hole-kernel.ps1 zeigt die Blobs).
#   2  Bewegt sich die Endenergie zwischen den Stufen nicht, ist die Massnahme
#      nicht angekommen.
#
# Die Waermebilanz der Tabelle geht auf (am Referenzfall geprueft):
#
#   Qw = Qh + UbergabeQ + VerteilQ + SpeicherQ
#   24408 + 4397 + 12020 + 0 = 40825
#
# Qw ist also NICHT das Warmwasser, sondern die Waerme, die der Erzeuger
# liefern muss. Die Endenergie ist die Summe der Erz*QE.
#
#   .\zeige-heizung.ps1 -Ordner .\arbeit
#   .\zeige-heizung.ps1 -Ordner .\arbeit -Proj 17          # nur eine Variante
#   .\zeige-heizung.ps1 -Ordner .\arbeit -Fahrplan 2,3,4   # Wirkungsprobe
#   .\zeige-heizung.ps1 -Ordner .\arbeit -Csv .\heizung.csv

param(
    [Parameter(Mandatory)] [string] $Ordner,
    [int[]]  $Proj,
    [int[]]  $Fahrplan,
    [string] $Csv
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

function Zahl($v) { if ($null -eq $v -or "$v" -eq '') { 0.0 } else { [double] $v } }

# Leere Textfelder der BDExit-Tabellen sind nicht leer, sondern ein NULLBYTE -
# .Trim() entfernt es nicht, und ein solches Feld ist in PowerShell wahr. Wer
# nur trimmt, sammelt Leereintraege ein (Erz2Brennst, Erz3Brennst).
function Text($v) {
    if ($null -eq $v) { return '' }
    (([string] $v) -replace "`0", '').Trim([char[]] @(' ', '|', "`t", "`r", "`n"))
}

function Saetze([string] $datei) {
    $b = [System.IO.File]::ReadAllBytes($datei); $k = BdeKopf $b
    $liste = New-Object System.Collections.ArrayList
    $o = $k.Daten
    while ($o -lt $b.Length) {
        $r = BdeLies $b $k $o -1
        $g = @{}; foreach ($v in $r.Werte) { $g[$v.Name] = $v.Wert }
        [void] $liste.Add($g); $o = $r.Ende
    }
    if ($liste.Count -ne $k.Satzzahl) {
        throw "$datei : $($liste.Count) Saetze gelesen, Kopf sagt $($k.Satzzahl)"
    }
    , $liste
}

$th = Join-Path $Ordner 'TableHeizung.BDExit'
$tp = Join-Path $Ordner 'TableProjekt.BDExit'
$ta = Join-Path $Ordner 'TableAnlage.BDExit'
if (-not (Test-Path $th)) { throw "$th fehlt - ist der Container entpackt?" }

# Variantennamen, damit die Pakete beim Namen genannt werden.
$namen = @{}
if (Test-Path $tp) {
    foreach ($g in (Saetze $tp)) {
        $bez = Text $g['VarianteBez']
        $namen[[int] $g['PROJEKT_ID']] = $(if ($bez) { $bez } else { 'Ist-Zustand' })
    }
}

# Die Klartextbeschreibung der Anlage steht in TableAnlage, nicht in
# TableHeizung: Erz1Text1 ist dort im Referenzfall leer. Der Schluessel heisst
# dort ANLAGE_ID, nicht PROJ_ID - er traegt dieselbe Variantennummer.
$beschr = @{}
if (Test-Path $ta) {
    foreach ($g in (Saetze $ta)) {
        $beschr[[int] $g['ANLAGE_ID']] = Text $g['Beschr_Heiz']
    }
}

$heiz = @{}
foreach ($g in (Saetze $th)) {
    $id = [int] $g['ProjektID']
    if (-not $heiz.ContainsKey($id)) { $heiz[$id] = New-Object System.Collections.ArrayList }
    [void] $heiz[$id].Add($g)
}

# Welche Varianten zeigen? Vorgabe: alle, die der Container kennt.
$ids = @($namen.Keys) | Sort-Object
if (-not $ids) { $ids = @($heiz.Keys) | Sort-Object }
if ($Proj) { $ids = $ids | Where-Object { $Proj -contains $_ } }

$zeilen = New-Object System.Collections.ArrayList
foreach ($id in $ids) {
    $x = New-Object psobject
    $x | Add-Member NoteProperty Proj  ([int] $id)
    $x | Add-Member NoteProperty Paket ($(if ($namen[$id]) { $namen[$id] } else { "($id)" }))

    if (-not $heiz.ContainsKey($id)) {
        $x | Add-Member NoteProperty Stand 'NICHT GERECHNET'
        foreach ($n in 'Qh', 'Verluste', 'Qw', 'Endenergie', 'Hilfsenergie', 'AZ') {
            $x | Add-Member NoteProperty $n $null
        }
        $x | Add-Member NoteProperty Anlage (Text $beschr[$id])
        [void] $zeilen.Add($x); continue
    }

    $qh = 0.0; $ue = 0.0; $ve = 0.0; $sp = 0.0; $qw = 0.0
    $qe = 0.0; $hilf = 0.0; $brennst = @()
    foreach ($g in $heiz[$id]) {
        $qh += Zahl $g['Qh']; $ue += Zahl $g['UbergabeQ']
        $ve += Zahl $g['VerteilQ']; $sp += Zahl $g['SpeicherQ']
        $qw += Zahl $g['Qw']
        $hilf += Zahl $g['QHilf']
        foreach ($i in 1, 2, 3) {
            $qe += Zahl $g["Erz${i}QE"]
            $b = Text $g["Erz${i}Brennst"]
            if ($b -and $brennst -notcontains $b) { $brennst += $b }
        }
    }
    # Die Bilanz gegenprobieren - geht sie nicht auf, ist die Deutung falsch.
    $summe = $qh + $ue + $ve + $sp
    if ($qw -gt 0 -and [math]::Abs($summe - $qw) -gt [math]::Max(1.0, $qw * 0.001)) {
        Write-Warning ("Proj {0}: Qh+Verluste = {1:N0}, Qw = {2:N0} - Bilanz geht nicht auf" -f $id, $summe, $qw)
    }

    $x | Add-Member NoteProperty Stand        'gerechnet'
    $x | Add-Member NoteProperty Qh           ([math]::Round($qh, 0))
    $x | Add-Member NoteProperty Verluste     ([math]::Round($ue + $ve + $sp, 0))
    $x | Add-Member NoteProperty Qw           ([math]::Round($qw, 0))
    $x | Add-Member NoteProperty Endenergie   ([math]::Round($qe, 0))
    $x | Add-Member NoteProperty Hilfsenergie ([math]::Round($hilf, 0))
    $x | Add-Member NoteProperty AZ           $(if ($qw -gt 0) { [math]::Round($qe / $qw, 4) } else { $null })
    $x | Add-Member NoteProperty Anlage       $(if ($beschr[$id]) { Text $beschr[$id] } else { $brennst -join ', ' })
    [void] $zeilen.Add($x)
}

$zeilen | Format-Table Proj, Paket, Stand, Qh, Verluste, Qw, Endenergie, Hilfsenergie, AZ, Anlage -AutoSize
'Alle Energien in kWh/a. AZ = Endenergie / Qw, aus der Tabelle gerechnet.'

if ($Csv) {
    $zeilen | Export-Csv -Path $Csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    "geschrieben: $Csv"
}

# ---- Wirkungsprobe ---------------------------------------------------------
# Nicht "laesst sich zurueckschreiben", sondern "bewegt sich die Endenergie".
if ($Fahrplan) {
    ''
    'Wirkungsprobe Anlagentechnik'
    $vor = $null; $mangel = 0
    foreach ($id in $Fahrplan) {
        $z = $zeilen | Where-Object Proj -eq $id | Select-Object -First 1
        if (-not $z) {
            Write-Warning "Proj $id ist im Container nicht vorhanden"; $mangel++; continue
        }
        if ($z.Stand -ne 'gerechnet') {
            '  {0,-28} NICHT GERECHNET - kein Satz in TableHeizung, Heizung nicht angekommen' -f $z.Paket
            $mangel++; continue
        }
        if ($null -eq $vor) {
            '  {0,-28} {1,10:N0} kWh/a   (Ausgangspunkt)' -f $z.Paket, $z.Endenergie
        } else {
            $d = $z.Endenergie - $vor
            $p = $(if ($vor -ne 0) { $d / $vor * 100 } else { 0 })
            $hinweis = ''
            if ([math]::Abs($d) -lt 1) {
                $hinweis = '  <- keine Wirkung, Massnahme nicht angekommen'; $mangel++
            } elseif ($d -gt 0) {
                $hinweis = '  <- steigt'
            }
            '  {0,-28} {1,10:N0} kWh/a   {2,9:N0} ({3,6:N1} %){4}' -f $z.Paket, $z.Endenergie, $d, $p, $hinweis
        }
        $vor = $z.Endenergie
    }
    ''
    if ($mangel -gt 0) { Write-Warning "$mangel Beanstandung(en) - siehe oben" }
    else { 'Wirkungsprobe bestanden: jede Stufe bewegt die Endenergie.' }
}
