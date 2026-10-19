# Fuellt die Texte, Kurzbeschreibungen und Prinzipskizzen eines iSFP aus den
# eigenen Textbausteinen - anhand der Sanierungsvarianten aus der Hottgenroth-
# Datenbank.
#
# Warum es das gibt: Die Erzaehlung eines iSFP ist zu rund 90 % Wiederholung.
# 46 Bausteine decken 98 % dessen ab, was in 19 Projekten tatsaechlich stand.
# Bisher wandert dieser Vorrat von Hand von Projekt zu Projekt.
#
# WORAUS GELESEN WIRD - zwei Quellen, weil eine nicht reicht:
#   Huellflaechen  eberater.zip -> TableHuellfl.SANBEZ je Variante.
#   Anlagentechnik iSFP2.xml -> massnahmenpakete/item/anlagen. Im Container
#                  steht sie NICHT: TableAnlage.Beschr_Heiz ist die alte
#                  DIN-4701-10-Beschreibung und bleibt auf dem Ist-Zustand
#                  stehen, auch wenn nach DIN 18599 laengst eine Waermepumpe
#                  gerechnet wird.
# Varianten sind KUMULATIV - ein Paket enthaelt die Massnahmen der vorigen.
# Genommen wird deshalb je Paket nur, was gegenueber dem Vorgaenger neu ist.
#
# WOHIN GESCHRIEBEN WIRD: PrMedia.iSFP2.xml (MediaType 11) - das ist der
# Speicherstand der iSFP-Maske, nicht bloss ein Export. Zusaetzlich wird eine
# .mSFPprojekt-Datei abgelegt, damit der Weg ueber "Datendatei einlesen ..."
# offensteht, falls die Maske ihren Stand nicht von allein zurueckliest.
#
#   .\isfp-texte-fuellen.ps1 -Projekt 'Klenke'
#   .\isfp-texte-fuellen.ps1 -Projekt 'Klenke' -Schreiben
#
#   -Vorschau    zeigt, was gesetzt wuerde, ohne zu schreiben (Standard)
#   -Schreiben   schreibt in PrMedia und legt die .mSFPprojekt-Datei ab
#   -Ablage      Ordner fuer Sicherung und .mSFPprojekt

param(
    [Parameter(Mandatory)] [string] $Projekt,
    [string] $Werkzeug = $PSScriptRoot,
    [string] $Bdexit   = 'C:\Projekte_Dev\hsetu-decompiled\werkzeuge\bdexit',
    [string] $Ablage,
    [string] $Uebernehmen,
    [switch] $Schreiben,
    [switch] $Vorschau,
    [int]    $MaxBildKante = 1200,
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true'
)

$ErrorActionPreference = 'Stop'
if (-not $Schreiben) { $Vorschau = $true }
if (-not $Ablage) { $Ablage = Join-Path $Werkzeug 'laeufe' }

. (Join-Path $Bdexit 'bde.ps1')
. (Join-Path $Bdexit 'satz.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---------------------------------------------------------------- Hilfsmittel

# Der Container schreibt ae/oe/ue ("Haustuer"), Bausteine und Regeln schreiben
# Umlaute. Ohne Vereinheitlichung trifft "Haustuer Ud 1,3" nicht auf "Haustür".
function Entumlaut([string] $s) {
    if ($null -eq $s) { return '' }
    $s = $s.ToLowerInvariant()
    foreach ($p in @(@('ä','ae'), @('ö','oe'), @('ü','ue'), @('ß','ss'))) { $s = $s.Replace($p[0], $p[1]) }
    return ($s -replace '\s+', ' ').Trim()
}

function Lies-Zeilen([string] $pfad) {
    $roh = [System.IO.File]::ReadAllText($pfad, [System.Text.Encoding]::UTF8)
    return ($roh -replace "^\uFEFF", '') -split "`r`n|`r|`n"
}

# Kompo_Beschreibung / Kompo_ZuBeachten: "-  -  -" trennt die GRUPPEN,
# die erste Zeile danach ist die Ueberschrift, dann je Zeile ein Baustein.
function Lies-Bausteine([string] $pfad) {
    $aus = @{}
    $erwarteUeberschrift = $true
    foreach ($z in (Lies-Zeilen $pfad)) {
        $z = $z.TrimEnd()
        if ($z -eq '' -or $z -eq 'Eigene Texte zum iSFP') { continue }
        if ($z -match '^-(\s+-)+\s*$') { $erwarteUeberschrift = $true; continue }
        if ($erwarteUeberschrift) { $erwarteUeberschrift = $false; continue }
        if ($z -match '^(.{2,60}?)\s[-\u2013]\s') {
            $s = Entumlaut $matches[1]
            if (-not $aus.ContainsKey($s)) { $aus[$s] = $z }
        }
    }
    return $aus
}

# Das_bringt_es: Leerzeile trennt die Gruppen, darunter EINE Zeile mit Punkten.
function Lies-Gruppen([string] $pfad) {
    $aus = @{}; $gruppe = $null
    foreach ($z in (Lies-Zeilen $pfad)) {
        $z = $z.TrimEnd()
        if ($z -eq 'Eigene Texte zum iSFP') { continue }
        if ($z -eq '') { $gruppe = $null; continue }
        if ($z -match '^-(\s+-)+\s*$') { continue }
        if ($null -eq $gruppe) { $gruppe = $z; continue }
        if (-not $aus.ContainsKey($gruppe)) { $aus[$gruppe] = $z }
        $gruppe = $null
    }
    return $aus
}

# Grosse Vorlagen werden beim Einbetten verkleinert - NUR im Speicher, die
# Dateien im Bilderordner bleiben, wie sie sind. Ohne das wird die XML groesser
# als jeder bisherige Export: zwei Fenstervorlagen allein wiegen 12 MB, und
# base64 legt ein Drittel drauf. Gedruckt werden die Skizzen ohnehin klein.
function Bild-Base64([string] $ordner, [string] $name, [int] $maxKante) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $p = $null
    foreach ($e in @('.png', '.jpg', '.jpeg')) {
        $k = Join-Path $ordner ($name + $e)
        if (Test-Path -LiteralPath $k) { $p = $k; break }
    }
    if (-not $p) { return $null }
    $roh = [System.IO.File]::ReadAllBytes($p)
    if ($maxKante -le 0) { return [Convert]::ToBase64String($roh) }

    Add-Type -AssemblyName System.Drawing
    $quelle = $null; $ziel = $null; $gr = $null; $ms = $null
    try {
        $quelle = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(,$roh)))
        if ($quelle.Width -le $maxKante -and $quelle.Height -le $maxKante) { return [Convert]::ToBase64String($roh) }
        $faktor = [Math]::Min($maxKante / $quelle.Width, $maxKante / $quelle.Height)
        $b = [int][Math]::Round($quelle.Width * $faktor)
        $h = [int][Math]::Round($quelle.Height * $faktor)
        $ziel = New-Object System.Drawing.Bitmap($b, $h)
        $gr = [System.Drawing.Graphics]::FromImage($ziel)
        $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gr.DrawImage($quelle, 0, 0, $b, $h)
        $ms = New-Object System.IO.MemoryStream
        $ziel.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        return [Convert]::ToBase64String($ms.ToArray())
    } catch {
        Write-Warning "Bild '$name' liess sich nicht verkleinern ($($_.Exception.Message)) - es wird unveraendert eingebettet."
        return [Convert]::ToBase64String($roh)
    } finally {
        foreach ($o in @($gr, $ziel, $quelle, $ms)) { if ($o) { $o.Dispose() } }
    }
}

# Projektweite Bausteindatei lesen und einordnen. Drei Sorten liegen im selben
# Ordner, und sie sehen gleich aus:
#   ein langer Text            -> setzbar
#   mehrere kurze Zeilen       -> eine AUSWAHL (Bauweise, Dachform, Foerderprogramm).
#                                 Die trifft der Berater, nicht das Werkzeug.
#   mehrere lange Zeilen       -> Absaetze EINES Textes (bisher nur das Anschreiben),
#                                 nur mit "verbinden" in der Zuordnung.
function Lies-Projektweit([string] $pfad, [bool] $verbinden) {
    if (-not (Test-Path -LiteralPath $pfad)) { return @{ Art = 'fehlt' } }
    $zeilen = @()
    foreach ($z in (Lies-Zeilen $pfad)) {
        $z = $z.TrimEnd()
        if ($z -eq '' -or $z -eq 'Eigene Texte zum iSFP') { continue }
        if ($z -match '^[-–—]+$' -or $z -match '^Text:?$') { continue }   # Kopfreste
        $zeilen += $z
    }
    if ($zeilen.Count -eq 0) { return @{ Art = 'leer' } }
    if ($zeilen.Count -eq 1) { return @{ Art = 'text'; Wert = $zeilen[0] } }
    if ($verbinden)          { return @{ Art = 'text'; Wert = ($zeilen -join '¶¶') } }
    $langste = ($zeilen | Measure-Object -Property Length -Maximum).Maximum
    if ($langste -lt 90)     { return @{ Art = 'auswahl'; Auswahl = $zeilen } }
    return @{ Art = 'mehrdeutig'; Auswahl = $zeilen }
}

# Das ¶ der Bausteindateien ist eine reine Dateikonvention - dort muss ein
# Baustein auf EINER Zeile stehen. In der XML hat es nichts verloren: es wird
# woertlich gedruckt. In 39 echten Exporten kommt es kein einziges Mal vor.
# Stattdessen <br> in den beiden RichText-Feldern der Ausfuehrung, sonst LF.
function Umbruch([string] $text, [switch] $Html) {
    if ([string]::IsNullOrEmpty($text)) { return $text }
    if ($Html) { return $text.Replace('¶', '<br>') }
    return $text.Replace('¶', "`n")
}

function Neu([System.Xml.XmlDocument] $dok, [string] $name, $wert) {
    $e = $dok.CreateElement($name)
    if ($null -ne $wert) { $e.InnerText = [string]$wert }
    return $e
}

function Text-Von($knoten, [string] $pfad) {
    if (-not $knoten) { return '' }
    $e = $knoten.SelectSingleNode($pfad)
    if ($e) { return $e.InnerText.Trim() } else { return '' }
}

# ------------------------------------------------------------------ Einlesen

$bausteinOrdner = Get-ChildItem -Path $Werkzeug -Recurse -Directory -Filter 'Textbausteine' | Select-Object -First 1
$bildOrdner     = Get-ChildItem -Path $Werkzeug -Recurse -Directory -Filter 'Maßnahmenbilder' | Select-Object -First 1
if (-not $bausteinOrdner) { throw "Ordner 'Textbausteine' unter $Werkzeug nicht gefunden." }
if (-not $bildOrdner)     { throw "Ordner 'Maßnahmenbilder' unter $Werkzeug nicht gefunden." }

$beschreibung = Lies-Bausteine (Join-Path $bausteinOrdner.FullName 'Texte_iSFP_Kompo_Beschreibung.txt')
$zuBeachten   = Lies-Bausteine (Join-Path $bausteinOrdner.FullName 'Texte_iSFP_Kompo_ZuBeachten.txt')
$bringtEs     = Lies-Gruppen   (Join-Path $bausteinOrdner.FullName 'Texte_iSFP_Das_bringt_es.txt')
$z            = Get-Content (Join-Path $Werkzeug 'zuordnung.json') -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "Bausteine: $($beschreibung.Count) Beschreibungen, $($zuBeachten.Count) Hinweise, $($bringtEs.Count) Gruppen" -ForegroundColor DarkGray

# --- Projekt, Container und XML aus der Datenbank

function Hole-Projekt([string] $suche, [string] $verb) {
    $cn = New-Object System.Data.SqlClient.SqlConnection $verb
    $cn.Open()
    try {
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = @'
SELECT p.UUID AS ProjUUID, p.LongDesc,
       x.UUID AS XmlUUID, x.Media AS Xml, x.StampEdit AS XmlStand,
       c.Media AS Zip, c.StampEdit AS ZipStand
FROM PrProject p
OUTER APPLY (SELECT TOP 1 * FROM PrMedia m WHERE m.ProjectUUID=p.UUID AND m.MediaName='iSFP2.xml'   AND m.MediaType=11 ORDER BY m.StampEdit DESC) x
OUTER APPLY (SELECT TOP 1 * FROM PrMedia m WHERE m.ProjectUUID=p.UUID AND m.MediaName='eberater.zip' ORDER BY m.StampEdit DESC) c
WHERE p.LongDesc LIKE @s OR CAST(p.UUID AS varchar(40)) = @u
'@
        $null = $cmd.Parameters.AddWithValue('@s', "%$suche%")
        $null = $cmd.Parameters.AddWithValue('@u', $suche)
        $rd = $cmd.ExecuteReader()
        $t = @()
        while ($rd.Read()) {
            $t += [pscustomobject]@{
                ProjUUID = $rd['ProjUUID']; Name = $rd['LongDesc']
                XmlUUID  = $(if ($rd['XmlUUID'] -is [DBNull]) { $null } else { $rd['XmlUUID'] })
                Xml      = $(if ($rd['Xml']     -is [DBNull]) { $null } else { $rd['Xml'] })
                XmlStand = $(if ($rd['XmlStand']-is [DBNull]) { $null } else { $rd['XmlStand'] })
                Zip      = $(if ($rd['Zip']     -is [DBNull]) { $null } else { $rd['Zip'] })
                ZipStand = $(if ($rd['ZipStand']-is [DBNull]) { $null } else { $rd['ZipStand'] })
            }
        }
        $rd.Close()
        return $t
    } finally { $cn.Close() }
}

$treffer = @(Hole-Projekt $Projekt $Verbindung)
if ($treffer.Count -eq 0) { throw "Kein Projekt gefunden fuer '$Projekt'." }
if ($treffer.Count -gt 1) { throw "Mehrdeutig - $($treffer.Count) Treffer: $(($treffer.Name) -join ', ')" }
$ziel = $treffer[0]
if (-not $ziel.Xml) { throw "Projekt '$($ziel.Name)' hat keine iSFP2.xml. Die iSFP-Maske muss einmal geoeffnet und gespeichert worden sein." }
if (-not $ziel.Zip) { throw "Projekt '$($ziel.Name)' hat keinen Container (eberater.zip)." }

Write-Host "Projekt:  $($ziel.Name)" -ForegroundColor Cyan
Write-Host "Container: $($ziel.ZipStand)   iSFP-XML: $($ziel.XmlStand)"
if ($ziel.ZipStand -gt $ziel.XmlStand) {
    Write-Warning "Der Container ist juenger als die XML. Was seither an den Varianten geaendert wurde, steht noch nicht in der XML - iSFP-Maske einmal oeffnen und speichern."
}

# --- Container entpacken und Varianten lesen

New-Item -ItemType Directory -Force -Path $Ablage | Out-Null
$stempel = Get-Date -Format 'yyyyMMdd-HHmmss'
$arbeit  = Join-Path $Ablage "container_$stempel"
New-Item -ItemType Directory -Force -Path $arbeit | Out-Null
$zipDatei = Join-Path $arbeit 'eberater.zip'
[System.IO.File]::WriteAllBytes($zipDatei, $ziel.Zip)
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipDatei, $arbeit)

function Lies-Tabelle([string] $pfad) {
    $roh = [System.IO.File]::ReadAllBytes($pfad); $kopf = BdeKopf $roh; $pos = $kopf.Daten
    $saetze = @()
    while ($pos -lt $roh.Length) {
        $s = BdeLies $roh $kopf $pos -1
        $h = @{}; foreach ($v in $s.Werte) { $h[$v.Name] = $v.Wert }
        $saetze += $h
        $pos = $s.Ende
    }
    return $saetze
}

$varianten = @{}
foreach ($s in (Lies-Tabelle (Join-Path $arbeit 'TableProjekt.BDExit'))) {
    $varianten[[int]$s['PROJEKT_ID']] = [string]$s['VarianteBez']
}
$huelle = @{}
foreach ($s in (Lies-Tabelle (Join-Path $arbeit 'TableHuellfl.BDExit'))) {
    if (-not $s['SANBEZ']) { continue }
    $id = [int]$s['PROJ_ID']
    if (-not $huelle.ContainsKey($id)) { $huelle[$id] = @() }
    $huelle[$id] += [pscustomobject]@{ Kz = [string]$s['KENNZEICHEN']; SanBez = [string]$s['SANBEZ'] }
}

$ids = @($varianten.Keys | Sort-Object)
$istId = $ids[0]
$paketIds = @($ids | Where-Object { $_ -ne $istId })
Write-Host "Varianten: Ist = $istId, Pakete = $($paketIds -join ', ')`n"

# --- XML laden

$sicherung = Join-Path $Ablage "iSFP2-VORHER_$stempel.xml"
[System.IO.File]::WriteAllBytes($sicherung, $ziel.Xml)
$sha = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($ziel.Xml)).Replace('-','')
Write-Host "Sicherung: $sicherung"
Write-Host "SHA-256:   $sha`n"

$dok = New-Object System.Xml.XmlDocument
$dok.PreserveWhitespace = $false
$dok.Load((New-Object System.IO.MemoryStream(,[byte[]]$ziel.Xml)))
$pakete = @($dok.SelectNodes('/iSFP-Projekt/massnahmenpakete/item'))
if ($pakete.Count -ne $paketIds.Count) {
    Write-Warning "XML hat $($pakete.Count) Pakete, der Container $($paketIds.Count) Varianten - es wird paarweise in Reihenfolge zugeordnet."
}

# ------------------------------- Komponenten FUELLEN, nicht neu bauen
#
# Die Maske legt die Komponenten selbst an: aus den SANBEZ der Huellflaechen
# und aus der Anlagentechnik. Hier werden nur Texte, Kurzbeschreibungen und
# Skizzen hineingeschrieben. Ein frueherer Entwurf hat die Liste neu aufgebaut -
# das haelt nicht: beim naechsten Oeffnen erzeugt die Maske sie wieder aus dem
# Modell, und was nicht von dort stammt, faellt heraus.

function Baustein-Fuer([string] $kz, [string] $sanbez) {
    foreach ($r in $z.huelle) {
        if ($r.kennzeichen -and ($r.kennzeichen -notcontains $kz)) { continue }
        if ((Entumlaut $sanbez) -match (Entumlaut $r.muster)) { return $r.baustein }
    }
    return $null
}

# SANBEZ -> KENNZEICHEN aus dem Container. Die XML fuehrt das Kennzeichen nicht
# mit, die Regeln brauchen es aber, um Haustuer von Innentuer zu trennen.
$kzVon = @{}
foreach ($id in $huelle.Keys) {
    foreach ($e in $huelle[$id]) { $kzVon[(Entumlaut $e.SanBez)] = $e.Kz }
}

$istWurzel  = $dok.SelectSingleNode('/iSFP-Projekt')
$istTechnik = Text-Von $istWurzel 'anlagen/heizungen/item/technik'
$istTraeger = Text-Von $istWurzel 'anlagen/heizungen/item/energietraegerName'

# Anlagenkomponenten tragen keinen SANBEZ, sondern einen von der Software
# erzeugten Satz ("Waermepumpe Luft-Wasser, Strom-Mix"). Der Baustein ergibt
# sich aus der Komponentenart und dem Uebergang vom Ist-Zustand.
function Baustein-Anlage([string] $art, [string] $kurz) {
    $k = Entumlaut $kurz
    if ($art -eq 'SK_HEIZUNG') {
        if ($k -match 'photovolt|pv-anlage|module')        { return $z.anlagen.pv }
        if ($k -match 'speicher')                          { return 'Stromspeicher' }
        if ($k -match 'optimierung|abgleich|heizkoerper')   { return 'Heizungsoptimierung' }
        $alt = $z.anlagen.alt_aus_technik.$istTechnik
        $altName = if ($alt) { $alt.$istTraeger } else { $null }
        $neuName = $null
        if     ($k -match 'sole')                   { $neuName = 'Sole-Waermepumpe' }
        elseif ($k -match 'waermepumpe|luft-wasser') { $neuName = 'Luft-Waermepumpe' }
        elseif ($k -match 'fernwaerme')             { return $z.anlagen.fernwaerme_baustein }
        elseif ($k -match 'pellet')                 { $neuName = 'Holzpelletheizung' }
        if ($altName -and $neuName) {
            # Der Bausteinname traegt Umlaute, die Vergleiche hier nicht.
            $treffer = $beschreibung.Keys | Where-Object { $_ -eq (Entumlaut "$altName -> $neuName") }
            if ($treffer) {
                foreach ($n in $z.bausteine.PSObject.Properties.Name) {
                    if ((Entumlaut $n) -eq (Entumlaut "$altName -> $neuName")) { return $n }
                }
            }
        }
        return $null
    }
    if ($art -eq 'SK_WARMWASSER') {
        if ($k -match 'solarthermie') { return 'Heizung alt -> Solarthermie' }
        if ($k -match 'pellet')       { return 'Heizung alt -> Holzpelletheizung neu' }
        return 'Heizung alt -> Wärmepumpe'
    }
    if ($art -eq 'SK_LUEFTUNG') {
        if ($k -match 'blower|luftdicht') { return 'Luftdichtheitstest (Blower-Door)' }
        return 'Dezentrale Lüftungsanlage'
    }
    return $null
}

$offen = @(); $gesetzt = 0; $bilder = 0; $fehlendeBilder = @(); $ohneBaustein = @()

$nr = 0
foreach ($mp in $pakete) {
    $nr++
    $paketName = if ($nr -le $paketIds.Count) { $varianten[$paketIds[$nr - 1]] } else { "Massnahmenpaket $nr" }
    Write-Host "MP$nr  $paketName" -ForegroundColor Yellow

    $nk = $mp.SelectSingleNode('name')
    if (-not $nk) { $nk = $mp.AppendChild((Neu $dok 'name' $null)) }
    $nk.InnerText = "$paketName"

    $gruppen = @()
    $komponenten = @($mp.SelectNodes('sanierungskomponenten/item'))
    if (-not $komponenten) { Write-Host "    (keine Komponente in der XML - nichts zu fuellen)" -ForegroundColor DarkYellow }

    foreach ($k in $komponenten) {
        $art = Text-Von $k 'art'
        $kurzListe = @($k.SelectNodes('ausFuehrungKurzbeschreibung/item') |
                       ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ -ne '' })
        if (-not $kurzListe) { continue }

        $ausWurzel = $k.SelectSingleNode('ausfuehrung')
        if (-not $ausWurzel) { $ausWurzel = $k.AppendChild((Neu $dok 'ausfuehrung' $null)) }
        $ausListe = @($ausWurzel.SelectNodes('item'))

        $kompName = $null; $teil = 0
        foreach ($kurz in ($kurzListe | Select-Object -First 3)) {
            $teil++
            $kz = $kzVon[(Entumlaut $kurz)]
            $bname = $null
            if ($kz) { $bname = Baustein-Fuer $kz $kurz }
            if (-not $bname) { $bname = Baustein-Anlage $art $kurz }
            if (-not $bname) { $ohneBaustein += "MP$nr [$art] $kurz"; continue }

            $b = $z.bausteine.$bname
            if (-not $b) { $ohneBaustein += "MP$nr [$art] $kurz  (Baustein fehlt in zuordnung.json: $bname)"; continue }
            if (-not $kompName) { $kompName = $b.komponente }
            if ($gruppen -notcontains $b.bringt_es) { $gruppen += $b.bringt_es }

            if ($teil -le $ausListe.Count) { $ai = $ausListe[$teil - 1] }
            else { $ai = $ausWurzel.AppendChild((Neu $dok 'item' $null)) }

            foreach ($f in @('beschreibung', 'zu_beachten')) {
                if (-not $ai.SelectSingleNode($f)) { [void]$ai.AppendChild((Neu $dok $f $null)) }
            }
            $ai.SelectSingleNode('beschreibung').InnerText = Umbruch "$($beschreibung[(Entumlaut $bname)])" -Html
            $hw = ''
            if ($b.zu_beachten) { $hw = "$($zuBeachten[(Entumlaut $b.zu_beachten)])" }
            $ai.SelectSingleNode('zu_beachten').InnerText = Umbruch $hw -Html

            $ps = $ai.SelectSingleNode('prinzipskizzen')
            if (-not $ps) { $ps = $ai.AppendChild((Neu $dok 'prinzipskizzen' $null)) }
            while ($ps.HasChildNodes) { [void]$ps.RemoveChild($ps.FirstChild) }
            foreach ($bild in @($b.skizzen)) {
                if ([string]::IsNullOrWhiteSpace($bild)) { continue }
                $b64 = Bild-Base64 $bildOrdner.FullName $bild $MaxBildKante
                if (-not $b64) { if ($fehlendeBilder -notcontains $bild) { $fehlendeBilder += $bild }; continue }
                $si = $ps.AppendChild((Neu $dok 'item' $null))
                [void]$si.AppendChild((Neu $dok 'stream' $b64))
                [void]$si.AppendChild((Neu $dok 'beschreibung' $bild))
                $bilder++
            }
            if ($ai.SelectSingleNode('beschreibung').InnerText) { $gesetzt++ }
            $anzeige = $kurz
            if ($anzeige.Length -gt 44) { $anzeige = $anzeige.Substring(0, 44) }
            Write-Host ("    [{0,-13}] {1,-44} -> {2}" -f $art, $anzeige, $bname)
        }

        # Die Software vergibt nur "Dach", "Heizung", "Aussenwand" - hier kommt
        # die Ueberschrift aus der Zuordnung hinein.
        if ($kompName) {
            $knk = $k.SelectSingleNode('name')
            if (-not $knk) { $knk = $k.AppendChild((Neu $dok 'name' $null)) }
            $knk.InnerText = $kompName
        }
    }

    # das_bringt_es: Gruppen in Paketreihenfolge, doppelte Punkte weg, Deckel 400
    $punkte = New-Object System.Collections.Generic.List[string]
    foreach ($g in $gruppen) {
        if (-not $bringtEs.ContainsKey($g)) { continue }
        $kand = New-Object System.Collections.Generic.List[string]
        $kand.AddRange($punkte)
        foreach ($pt in ($bringtEs[$g] -split '¶')) { if ($pt -and -not $kand.Contains($pt)) { $kand.Add($pt) } }
        if ((($kand -join '¶').Length) -le 400) { $punkte = $kand }
    }
    if ($punkte.Count) {
        $bk = $mp.SelectSingleNode('das_bringt_es')
        if (-not $bk) { $bk = $mp.AppendChild((Neu $dok 'das_bringt_es' $null)) }
        $bk.InnerText = Umbruch ($punkte -join '¶')
        Write-Host ("    das_bringt_es  {0} Punkte, {1} Zeichen" -f $punkte.Count, $bk.InnerText.Length)
    }
}


# ------------------------------------- handgeschriebene Felder uebernehmen
#
# "Erfassung zuruecksetzen" in der Maske baut den Fahrplan neu aus den
# Energieberater-Daten auf - und loescht dabei alles, was nur im Dialog stand:
# die Begruendungen fuer Architekt, Statiker, Schornsteinfeger, die Anmerkungen
# zum Verbrauch, die Beraterangaben. Aus dem Modell kommen die nicht zurueck.
# Deshalb werden sie aus einer vorherigen Fassung uebernommen, aber nur dort,
# wo das Ziel leer ist.
if ($Uebernehmen) {
    if (-not (Test-Path -LiteralPath $Uebernehmen)) { throw "Uebernahme-Datei $Uebernehmen gibt es nicht." }
    $alt = New-Object System.Xml.XmlDocument
    $alt.Load($Uebernehmen)
    $uebernommen = 0; $uebersprungen = 0
    Write-Host "`nUebernahme aus $(Split-Path -Leaf $Uebernehmen)" -ForegroundColor Yellow
    foreach ($pfad in $z.handgeschrieben) {
        $q = $alt.SelectSingleNode('/iSFP-Projekt/' + $pfad)
        if (-not $q -or $q.InnerText.Trim() -eq '') { continue }
        $t = $dok.SelectSingleNode('/iSFP-Projekt/' + $pfad)
        if (-not $t) { continue }
        if ($t.InnerText.Trim() -ne '') { $uebersprungen++; continue }
        $t.InnerText = Umbruch $q.InnerText
        $uebernommen++
        Write-Host ("    {0,-36} {1}" -f $pfad, $(if ($q.InnerText.Length -gt 50) { $q.InnerText.Substring(0,50) + '…' } else { $q.InnerText }))
    }
    Write-Host ("    uebernommen: {0}   schon belegt, gelassen: {1}" -f $uebernommen, $uebersprungen)
}

# ------------------------------------- Auswahlfelder aus dem Modell herleiten
#
# Fuer Heizung, Warmwasser, Lueftung, Keller und Bauweise steht die Antwort im
# Modell - die muss niemand aussuchen. Bauart von Wand und Fenster dagegen steht
# dort NICHT; die bleiben dem Berater. Was hier gesetzt wird, muss wortgleich
# eine der Moeglichkeiten aus der Bausteindatei sein, sonst kennt die Maske es nicht.
Write-Host "`nAus dem Modell hergeleitet" -ForegroundColor Yellow
$hlGesetzt = 0; $hlOffen = @()
$hzIst = $null
if ($huelle) { }   # Container ist schon gelesen
$hzRoh = Join-Path $arbeit 'TableHeizung.BDExit'
if (Test-Path -LiteralPath $hzRoh) {
    $b = [System.IO.File]::ReadAllBytes($hzRoh); $kf = BdeKopf $b
    $sz = BdeLies $b $kf $kf.Daten -1
    $hzIst = @{}; foreach ($v in $sz.Werte) { $hzIst[$v.Name] = $v.Wert }
}
foreach ($e in $z.herleitung.PSObject.Properties) {
    $pfad = $e.Name
    $knoten = $dok.SelectSingleNode('/iSFP-Projekt/' + $pfad)
    if (-not $knoten) { continue }
    if ($knoten.InnerText.Trim() -ne '') { continue }   # nichts ueberschreiben
    $wert = $null; $quelleTxt = $null
    foreach ($r in $e.Value) {
        $q = "$($r.quelle)"
        if ($q -like 'heizung:*') {
            if (-not $hzIst) { continue }
            $ist = "$($hzIst[$q.Substring(8)])"
        } else {
            $n = $dok.SelectSingleNode('/iSFP-Projekt/' + $q)
            $ist = if ($n) { $n.InnerText.Trim() } else { '' }
        }
        if ($ist -eq '') { continue }
        $passt = $false
        if ($r.PSObject.Properties.Name -contains 'ist')      { $passt = (Entumlaut $ist) -eq (Entumlaut $r.ist) }
        if (-not $passt -and ($r.PSObject.Properties.Name -contains 'enthaelt')) {
            $passt = (Entumlaut $ist).Contains((Entumlaut $r.enthaelt))
        }
        if ($passt) { $wert = "$($r.wert)"; $quelleTxt = "$q = $ist"; break }
    }
    if (-not $wert) { $hlOffen += $pfad; continue }
    $knoten.InnerText = $wert
    $hlGesetzt++
    Write-Host ("    {0,-32} {1,-44} aus {2}" -f $pfad, $wert, $quelleTxt)
}
Write-Host ("    hergeleitet: {0}   keine Regel getroffen: {1}" -f $hlGesetzt, $hlOffen.Count)
if ($hlOffen) { Write-Host "    ohne Treffer: $($hlOffen -join ', ')" -ForegroundColor DarkGray }

# ------------------------------------------------- projektweite Texte

Write-Host "`nProjektweite Texte" -ForegroundColor Yellow
$pwGesetzt = 0; $pwAuswahl = @(); $pwBesetzt = @(); $pwOhneKnoten = @()
foreach ($e in $z.projektweit.PSObject.Properties) {
    $pfad  = $e.Name
    $datei = Join-Path $bausteinOrdner.FullName ($e.Value.datei + '.txt')
    $r = Lies-Projektweit $datei ([bool]$e.Value.verbinden)

    $knoten = $dok.SelectSingleNode('/iSFP-Projekt/' + $pfad)
    if (-not $knoten) { $pwOhneKnoten += $pfad; continue }

    switch ($r.Art) {
        'text' {
            # Was der Berater schon geschrieben hat, bleibt stehen.
            if ($knoten.InnerText.Trim() -ne '') { $pwBesetzt += $pfad; break }
            $knoten.InnerText = Umbruch $r.Wert
            $pwGesetzt++
            Write-Host ("    {0,-36} {1,5} Zeichen  {2}" -f $pfad, $r.Wert.Length,
                $(if ($r.Wert.Length -gt 46) { $r.Wert.Substring(0,46) + '…' } else { $r.Wert }))
        }
        'auswahl'    {
            # Nicht melden, was die Herleitung vorher schon gesetzt hat.
            if ($knoten.InnerText.Trim() -ne '') { $pwBesetzt += $pfad; break }
            $pwAuswahl += "$pfad  ($($r.Auswahl.Count) Möglichkeiten: $(($r.Auswahl | Select-Object -First 3) -join ' / ')…)"
        }
        'mehrdeutig' {
            if ($knoten.InnerText.Trim() -ne '') { $pwBesetzt += $pfad; break }
            $pwAuswahl += "$pfad  ($($r.Auswahl.Count) lange Zeilen - 'verbinden' in zuordnung.json setzen, falls es ein Text ist)"
        }
        default      { }
    }
}
Write-Host ("    gesetzt: {0}   Auswahl noetig: {1}   schon belegt: {2}" -f $pwGesetzt, $pwAuswahl.Count, $pwBesetzt.Count)
if ($pwAuswahl)     { Write-Warning "Auswahl noetig, bleibt leer:`n   $($pwAuswahl -join "`n   ")" }
if ($pwBesetzt)     { Write-Host   "    unveraendert gelassen (stand schon Text drin): $($pwBesetzt -join ', ')" -ForegroundColor DarkGray }
if ($pwOhneKnoten)  { Write-Warning "Knoten gibt es in dieser XML nicht: $($pwOhneKnoten -join ', ')" }

Write-Host ""
Write-Host "Ausfuehrungen mit Text: $gesetzt   Skizzen eingebettet: $bilder" -ForegroundColor Green
if ($fehlendeBilder) { Write-Warning "Bilddateien fehlen: $($fehlendeBilder -join ', ')" }
if ($ohneBaustein)   { Write-Warning "Ohne Baustein geblieben:`n   $($ohneBaustein -join "`n   ")" }

# ------------------------------------------------- ¶ aufraeumen, ueberall
#
# Zum Schluss ueber ALLE Textknoten, auch ueber die, die oben unangetastet
# blieben. Ein ¶ dort stammt aus einem frueheren Lauf oder aus einem von Hand
# eingefuegten Baustein - in beiden Faellen wird es sonst woertlich gedruckt.
# Ersetzen kann nichts kaputt machen, nur reparieren.
$aufgeraeumt = 0
foreach ($kn in @($dok.SelectNodes('//*[not(*)]'))) {
    $t = $kn.InnerText
    if ([string]::IsNullOrEmpty($t) -or $t.IndexOf('¶') -lt 0) { continue }
    $html = ($kn.Name -eq 'beschreibung' -or $kn.Name -eq 'zu_beachten')
    if ($html) { $kn.InnerText = Umbruch $t -Html } else { $kn.InnerText = Umbruch $t }
    $aufgeraeumt++
}
if ($aufgeraeumt) { Write-Host "`n¶ ersetzt in $aufgeraeumt Feldern" -ForegroundColor Green }

# ------------------------------------------------------------- Zurueckschreiben

$einst = New-Object System.Xml.XmlWriterSettings
$einst.Encoding = New-Object System.Text.UTF8Encoding($false)
$einst.Indent = $false
$strom = New-Object System.IO.MemoryStream
$schreiber = [System.Xml.XmlWriter]::Create($strom, $einst)
$dok.Save($schreiber); $schreiber.Flush(); $schreiber.Close()
$neuBytes = $strom.ToArray()

if ($Vorschau) {
    Write-Host "`nVORSCHAU - nichts geschrieben. Neue Groesse waere $([math]::Round($neuBytes.Length/1KB)) KB (vorher $([math]::Round($ziel.Xml.Length/1KB)) KB)." -ForegroundColor Magenta
    Write-Host "Zum Schreiben denselben Aufruf mit -Schreiben."
    return
}

$laeuft = Get-Process Energie -ErrorAction SilentlyContinue
if ($laeuft) { throw "Energie.exe laeuft (PID $($laeuft.Id -join ', ')). Sie haelt den Stand im Speicher und ueberschreibt ihn beim naechsten Speichern - erst schliessen." }

$datei = Join-Path $Ablage "$($ziel.Name -replace '[^\w\-]','_')_$stempel.mSFPprojekt"
[System.IO.File]::WriteAllBytes($datei, $neuBytes)

$cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$cn.Open()
try {
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = 'UPDATE PrMedia SET Media = @b, StampEdit = GETDATE() WHERE UUID = @u'
    $par = $cmd.Parameters.Add('@b', [System.Data.SqlDbType]::VarBinary, -1); $par.Value = $neuBytes
    $null = $cmd.Parameters.AddWithValue('@u', $ziel.XmlUUID)
    $zeilenZahl = $cmd.ExecuteNonQuery()
} finally { $cn.Close() }

# Gegenprobe aus der Datenbank, nicht aus dem Speicher
$cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$cn.Open()
try {
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = 'SELECT Media FROM PrMedia WHERE UUID = @u'
    $null = $cmd.Parameters.AddWithValue('@u', $ziel.XmlUUID)
    $zurueck = $cmd.ExecuteScalar()
} finally { $cn.Close() }

$shaNeu = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($neuBytes)).Replace('-','')
$shaDb  = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($zurueck)).Replace('-','')
if ($shaNeu -ne $shaDb) { throw "Gegenprobe fehlgeschlagen: was in der Datenbank steht, ist nicht, was geschrieben wurde." }

Write-Host "`nGeschrieben: PrMedia ($zeilenZahl Zeile), $([math]::Round($neuBytes.Length/1KB)) KB, Gegenprobe ok." -ForegroundColor Green
Write-Host "Datei:       $datei"
Write-Host "Zurueck:     $sicherung"
