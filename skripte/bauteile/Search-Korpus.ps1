# Search-Korpus.ps1 -- den dekompilierten HSETU-Quelltext durchsuchen
#
# WOZU
# Der Bestand beantwortet Fragen zur Rechen- und Datenseite, die sonst niemand
# beantwortet: wie der Bauteilkatalog angesprochen wird, wie das IBP-Modell der
# DIN-18599-Anlagentechnik aufgebaut ist, was in der eberater.zip steht.
#
# WO ER LIEGT
# NICHT im Repository. Seine eigene README verbietet das ausdruecklich -- es ist
# dekompilierte Fremdsoftware, zulaessig allein zur Herstellung von
# Interoperabilitaet (Paragraf 69e UrhG). Der Ort ist deshalb einstellbar:
# Parameter -Wurzel, sonst die Umgebungsvariable HSETU_KORPUS, sonst der lokale
# Pfad. So kann er auch von einem eingebundenen Netzlaufwerk kommen.
#
# WAS ER NICHT ENTHAELT -- die wichtigere Auskunft
# HottCAD ist eine native Anwendung und nicht dekompilierbar. Der gesamte
# Zeichnungsteil fehlt: CADXMLData, wall_type, Gehrungen, alles Geometrische.
# Eine Suche nach wall_type ueber den Gesamtbestand liefert NULL Treffer. Wer
# dort nach CAD-Verhalten sucht, verliert Zeit -- deshalb warnt dieses Skript,
# bevor es sucht.
#
# REGISTER VOR VOLLTEXT
# Der Bestand ist 1,8 GB in ueber 5000 Dateien. Volltext dauert Minuten, die
# Register beantworten die meisten Fragen in Sekunden. Deshalb wird ohne
# -Volltext nur in den Registern gesucht.
#
# Nur lesend.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Begriff,
    # Volltext ueber eigen/ statt nur ueber die Register. Dauert deutlich laenger.
    [switch]$Volltext,
    [int]$Treffer = 30,
    [string]$Wurzel = ''
)

$ErrorActionPreference = 'Stop'

if (-not $Wurzel) { $Wurzel = $env:HSETU_KORPUS }
if (-not $Wurzel) { $Wurzel = 'C:\Projekte_Dev\hsetu-decompiled' }

# Einen Laufwerksbuchstaben ohne Backslash geradeziehen. "K:" ist unter Windows
# NICHT die Wurzel von K, sondern "das aktuelle Verzeichnis auf K" -- Join-Path
# baut daraus ein relatives K:api-typen.csv, und die Suche liefe ins Leere,
# ohne einen Fehler zu werfen. Beim Einbinden eines Netzlaufwerks ist genau
# diese Schreibweise die naheliegende.
$Wurzel = $Wurzel.Trim().TrimEnd('"')
if ($Wurzel -match '^[A-Za-z]:$') { $Wurzel = $Wurzel + '\' }

if (-not (Test-Path $Wurzel)) {
    Write-Output "Der dekompilierte Bestand ist unter '$Wurzel' nicht erreichbar."
    Write-Output "Er gehoert nicht ins Repository. Pfad ueber -Wurzel angeben oder"
    Write-Output "die Umgebungsvariable HSETU_KORPUS setzen (auch ein Netzlaufwerk)."
    return
}

# Warnung vor der haeufigsten Fehlsuche.
$cad = @('wall_type','CADXMLData','plane_definition','gable_mode','OuterContour',
         'roof_type','floor=','BmData','Gehrung','Traufe','First')
foreach ($c in $cad) {
    if ($Begriff -like "*$c*") {
        Write-Output "HINWEIS: '$Begriff' klingt nach HottCAD/Zeichnung."
        Write-Output "HottCAD ist nativ und NICHT in diesem Bestand -- eine Suche danach bleibt leer."
        Write-Output "Solche Fragen werden am Datenbestand ausgezaehlt, nicht hier gesucht."
        Write-Output ""
        break
    }
}

$muster = [regex]::Escape($Begriff)
$gefunden = 0

if (-not $Volltext) {
    Write-Output "Suche in den Registern (schnell). Fuer den Quelltext selbst: -Volltext"
    Write-Output ""
    # Die *-fremd-Register gehoeren dazu, und zwar nicht als Nachtrag.
    #
    # Sie fehlten in der ersten Fassung, weil fremd/ als "556 MB DevExpress"
    # abgetan war. Dort liegt aber DIN18599DataModel -- das IBP-Modell, also
    # das wichtigste Fremdmodul dieser Arbeit. Die Folge war ein stiller
    # blinder Fleck: eine Suche nach NewGeneratorBoiler lieferte null Treffer,
    # obwohl die Methode existiert, und brachte mich dazu, einen gut belegten
    # Gedaechtniseintrag anzuzweifeln.
    #
    # Ein Werkzeug, das an der falschen Stelle sucht, meldet nicht "weiss ich
    # nicht", sondern "gibt es nicht". Das ist die gefaehrlichere Antwort.
    foreach ($reg in @('api-typen.csv', 'api-mitglieder.csv',
                       'api-typen-fremd.csv', 'api-mitglieder-fremd.csv',
                       'steckbriefe.csv', 'index.csv')) {
        $pfad = Join-Path $Wurzel $reg
        if (-not (Test-Path $pfad)) { continue }
        $rest = $Treffer - $gefunden
        if ($rest -le 0) { break }
        $t = @(Select-String -Path $pfad -Pattern $muster -SimpleMatch -List:$false |
               Select-Object -First $rest)
        if ($t.Count) {
            Write-Output "--- $reg ---"
            foreach ($z in $t) {
                $text = $z.Line
                if ($text.Length -gt 200) { $text = $text.Substring(0, 199) + '…' }
                Write-Output "  $text"
            }
            Write-Output ""
            $gefunden += $t.Count
        }
    }
    if ($gefunden -eq 0) {
        Write-Output "Nichts in den Registern. Moegliche Gruende:"
        Write-Output "  - der Begriff kommt nur im Quelltext vor -> mit -Volltext erneut"
        Write-Output "  - er gehoert zu HottCAD -> nicht in diesem Bestand"
        Write-Output "  - er heisst anders -> in API-UEBERSICHT.md oder MODULE.md nachsehen"
    } else {
        Write-Output "$gefunden Treffer. Zum Weiterlesen: doku_lesen geht hier nicht --"
        Write-Output "der Bestand liegt ausserhalb des Repos. Gezielt mit -Volltext nachfassen."
    }
    return
}

# Erst eigen/, dann die Fremdmodule -- aber die kleinen zuerst. DevExpress ist
# gross und fuer diese Arbeit belanglos; DIN18599DataModel ist klein und
# entscheidend. Nach Groesse aufsteigend zu gehen bringt die nuetzlichen
# Treffer zuerst und laesst die Zeitgrenze an der richtigen Stelle greifen.
Write-Output "Volltextsuche: erst eigen/, dann fremd/ (kleine Module zuerst). Das dauert."
Write-Output ""
$eigen = Join-Path $Wurzel 'eigen'
if (-not (Test-Path $eigen)) { Write-Output "Ordner 'eigen' fehlt unter $Wurzel."; return }
$dateien = @(Get-ChildItem $eigen -Filter *.cs -File | Sort-Object Length)
$fremd = Join-Path $Wurzel 'fremd'
if (Test-Path $fremd) { $dateien += @(Get-ChildItem $fremd -Filter *.cs -File | Sort-Object Length) }

$uhr = [Diagnostics.Stopwatch]::StartNew()
foreach ($datei in $dateien) {
    if ($gefunden -ge $Treffer) { break }
    if ($uhr.Elapsed.TotalSeconds -gt 240) {
        Write-Output "(Zeitgrenze erreicht -- Suche eingegrenzt fortsetzen)"
        break
    }
    $nr = 0
    foreach ($zeile in [IO.File]::ReadLines($datei.FullName)) {
        $nr++
        if ($zeile -match $muster) {
            $text = $zeile.Trim()
            if ($text.Length -gt 200) { $text = $text.Substring(0, 199) + '…' }
            Write-Output ("  {0}:{1}  {2}" -f $datei.Name, $nr, $text)
            $gefunden++
            if ($gefunden -ge $Treffer) { break }
        }
    }
}
Write-Output ""
Write-Output "$gefunden Treffer in $([int]$uhr.Elapsed.TotalSeconds) s."
