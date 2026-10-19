# Fuellt die Zahlen- und Stammdatenseite eines iSFP und prueft am Ende, was noch
# fehlt. Der zweite Gang nach isfp-texte-fuellen.ps1: dort die Erzaehlung, hier
# das Geld, die Beraterangaben und die Schlusspruefung.
#
# WARUM ES DAS GIBT
# Ein Abgleich des Rohexports (direkt nach "Erfassung zuruecksetzen", 358 Pfade)
# gegen den fertigen Fahrplan Klenke (391 Pfade) hat 93 Feldarten gezeigt, die
# von Hand dazukamen. Die Texte davon deckt isfp-texte-fuellen.ps1 ab. Was blieb,
# war dreierlei:
#
#   Stammdaten   Beraternummer, Anschrift, Logo, Unterschrift - in jedem Projekt
#                dasselbe, und trotzdem jedes Mal neu getippt. In vier Projekten
#                steht die Buroanschrift in drei Schreibweisen und die
#                BAFA-Nummer zweimal verschieden.
#   Geld         einzelPositionen, investition, instandsetzungskosten,
#                foerderbetrag, foerderProgramm. Steht rechnerisch vollstaendig
#                im Container - siehe unten - und wurde trotzdem abgetippt.
#   Ortskenntnis techDoku, Nutzereinfluss, Fotos. Das kann kein Werkzeug wissen.
#                Es kann aber danach fragen, und genau das tut die Pruefliste.
#
# WORAUS DAS GELD GERECHNET WIRD
# TableHuellfl je Variante, nur Zeilen mit SANBEZ. An Klenke nachgemessen:
#
#   Position           = "KENNZEICHEN - SANBEZ"   (BK - Kellerdecke von unten ...)
#   investitionsKosten = Summe SANKOSTEN    ueber alle Zeilen dieser Position
#   sowiesoKosten      = Summe SANKOSTEN - Summe SANKOSTEN_EE
#   foerderung         = min(investitionsKosten, Deckel) * Satz
#
# Vier Aussenwandzeilen ergeben 5425+8175+5425+8175 = 27.200 - genau der Betrag,
# der von Hand in MP3 stand. Fenster 13.701 gegen 13.700, Haustuer 6.050 gegen
# 6.000: der Berater hat gerundet, die Rechnung stimmt.
# Anlagen (Waermepumpe, PV, Lueftung) stehen NICHT in TableHuellfl - die kommen
# aus anlagenkosten.json, derselben Datei, die anlagenkosten-setzen.ps1 fuehrt.
#
# Varianten sind KUMULATIV. Genommen wird je Paket nur, was gegenueber dem
# Vorgaenger neu ist - sonst steht die Kellerdecke fuenfmal im Fahrplan.
#
# WARUM DAS SCHREIBEN HIER ERLAUBT IST
# Die Komponenten (sanierungskomponenten) erzeugt die Maske aus dem Modell; ein
# frueherer Versuch, sie von aussen aufzubauen, ist genau daran gescheitert. Die
# Kostenpositionen sind etwas anderes: im Rohexport steht in allen fuenf Paketen
#   einzelPositionen/item = 0 ,  sanierungskomponenten/item = 1 bzw. 2
# Die Maske erzeugt sie also NICHT. Sie sind reine Dialogdaten, dieselbe Sorte
# wie die Texte - und die ueberleben das Schreiben von aussen nachweislich.
#
#   .\isfp-fertigstellen.ps1 -Projekt 'Klenke'              # Vorschau + Pruefliste
#   .\isfp-fertigstellen.ps1 -Projekt 'Klenke' -Schreiben
#   .\isfp-fertigstellen.ps1 -Projekt 'Klenke' -NurPruefen  # nichts fuellen, nur pruefen
#   .\isfp-fertigstellen.ps1 -Datei 'C:\...\Klenke_isfp.mSFPprojekt'   # fertige Datei pruefen

param(
    [string] $Projekt,
    [string] $Datei,
    [string] $Werkzeug = $PSScriptRoot,
    [string] $Bdexit   = 'C:\Projekte_Dev\hsetu-decompiled\werkzeuge\bdexit',
    [string] $Ablage,
    [switch] $Schreiben,
    [switch] $Vorschau,
    [switch] $NurPruefen,
    [switch] $StammdatenLassen,
    [string] $Uebernehmen,
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true'
)

$ErrorActionPreference = 'Stop'
if (-not $Projekt -and -not $Datei) { throw 'Entweder -Projekt (aus der Datenbank) oder -Datei (eine .mSFPprojekt-Datei) angeben.' }
if ($Datei) { $NurPruefen = $true }
if (-not $Schreiben) { $Vorschau = $true }
if (-not $Ablage) { $Ablage = Join-Path $Werkzeug 'laeufe' }

# ---------------------------------------------------------------- Hilfsmittel

function Entumlaut([string] $s) {
    if ($null -eq $s) { return '' }
    $s = $s.ToLowerInvariant()
    foreach ($p in @(@([char]0xE4, 'ae'), @([char]0xF6, 'oe'), @([char]0xFC, 'ue'), @([char]0xDF, 'ss'))) {
        $s = $s.Replace([string]$p[0], [string]$p[1])
    }
    return ($s -replace '\s+', ' ').Trim()
}

# Ein Knoten, der da sein muss. Fehlt er, wird er angelegt - aber nur unterhalb
# eines Elternteils, den es schon gibt. Ganze Aeste erfindet dieses Werkzeug nicht.
function Knoten([System.Xml.XmlNode] $eltern, [string] $name) {
    if (-not $eltern) { return $null }
    $k = $eltern.SelectSingleNode($name)
    if ($k) { return $k }
    return $eltern.AppendChild($eltern.OwnerDocument.CreateElement($name))
}

# Setzt nur, wo leer oder 'nan'. Was der Berater geschrieben hat, bleibt stehen -
# das ist die Regel, an die sich auch isfp-texte-fuellen.ps1 haelt.
$script:Gesetzt = 0
$script:Belassen = New-Object System.Collections.Generic.List[string]
$script:Abweichungen = New-Object System.Collections.Generic.List[string]
function Setze([System.Xml.XmlNode] $wurzel, [string] $pfad, $wert, [string] $notiz = '') {
    if ($null -eq $wert -or "$wert" -eq '') { return $false }
    $k = $wurzel.SelectSingleNode($pfad)
    if (-not $k) { return $false }
    $alt = $k.InnerText.Trim()
    if ($alt -ne '' -and $alt -ne 'nan') { $script:Belassen.Add("$pfad = $alt"); return $false }
    $k.InnerText = "$wert"
    $script:Gesetzt++
    $zeig = "$wert"
    if ($zeig.Length -gt 44) { $zeig = $zeig.Substring(0, 44) + [char]0x2026 }
    Write-Host ("    {0,-54} {1}{2}" -f $pfad, $zeig, $(if ($notiz) { "   ($notiz)" } else { '' }))
    return $true
}

# Stammdaten sind etwas anderes als Projektinhalt: sie SIND die Wahrheit, und
# was im Projekt davon abweicht, ist ein Tippfehler. Klenke hat das gezeigt -
# dort stand vorNachname = "Firma" und StrasseHnr = "FS Energieberater GmbH",
# also das ganze Feld um eins verrutscht, und die Regel "nichts ueberschreiben"
# haette den Fehler stehen lassen. Deshalb wird hier ueberschrieben - aber jede
# Abweichung wird gezeigt, und -StammdatenLassen schaltet es ab.
$script:Korrigiert = 0
function SetzeFest([System.Xml.XmlNode] $wurzel, [string] $pfad, $wert) {
    $k = $wurzel.SelectSingleNode($pfad)
    if (-not $k) { return }
    $alt = $k.InnerText.Trim()
    if ($alt -eq "$wert") { return }
    if ($alt -ne '' -and $alt -ne 'nan') {
        if ($StammdatenLassen) {
            Write-Host ("    {0,-54} bleibt '{1}'  (Stammdaten sagen '{2}')" -f $pfad, $alt, $wert) -ForegroundColor DarkYellow
            return
        }
        Write-Host ("    {0,-54} '{1}'  ->  '{2}'" -f $pfad, $alt, $wert) -ForegroundColor Yellow
        $script:Korrigiert++
    } else {
        Write-Host ("    {0,-54} {1}" -f $pfad, $wert)
        $script:Gesetzt++
    }
    $k.InnerText = "$wert"
}

function Euro($x) {
    if ($null -eq $x) { return 'nan' }
    return [string][int][Math]::Round([double]$x, 0)
}

function Zahl([System.Xml.XmlNode] $knoten, [string] $pfad) {
    if (-not $knoten) { return 0.0 }
    $k = $knoten.SelectSingleNode($pfad)
    if (-not $k) { return 0.0 }
    $v = 0.0
    if ([double]::TryParse($k.InnerText.Trim(), [ref] $v)) { return $v }
    return 0.0
}

function Kuerze([string] $s, [int] $n) {
    if ($null -eq $s) { return '' }
    if ($s.Length -le $n) { return $s }
    return $s.Substring(0, $n)
}

# ------------------------------------------------------------------ Einlesen

$st = Get-Content (Join-Path $Werkzeug 'stammdaten.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$stempel = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Force -Path $Ablage | Out-Null

$dok = New-Object System.Xml.XmlDocument
$dok.PreserveWhitespace = $false
$zielXmlUUID = $null; $projName = $null; $altBytes = $null; $arbeit = $null; $sicherung = $null

if ($Datei) {
    if (-not (Test-Path -LiteralPath $Datei)) { throw "Datei $Datei gibt es nicht." }
    $altBytes = [System.IO.File]::ReadAllBytes($Datei)
    $dok.Load((New-Object System.IO.MemoryStream(, $altBytes)))
    $projName = Split-Path -Leaf $Datei
    Write-Host "Datei:    $Datei" -ForegroundColor Cyan
} else {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    . (Join-Path $Bdexit 'bde.ps1')
    . (Join-Path $Bdexit 'satz.ps1')

    $cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
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
WHERE p.LongDesc LIKE @s
'@
        $null = $cmd.Parameters.AddWithValue('@s', "%$Projekt%")
        $rd = $cmd.ExecuteReader(); $t = @()
        while ($rd.Read()) {
            $t += [pscustomobject]@{
                Name     = $rd['LongDesc']
                XmlUUID  = $(if ($rd['XmlUUID']  -is [DBNull]) { $null } else { $rd['XmlUUID'] })
                Xml      = $(if ($rd['Xml']      -is [DBNull]) { $null } else { $rd['Xml'] })
                XmlStand = $(if ($rd['XmlStand'] -is [DBNull]) { $null } else { $rd['XmlStand'] })
                Zip      = $(if ($rd['Zip']      -is [DBNull]) { $null } else { $rd['Zip'] })
                ZipStand = $(if ($rd['ZipStand'] -is [DBNull]) { $null } else { $rd['ZipStand'] })
            }
        }
        $rd.Close()
    } finally { $cn.Close() }

    if ($t.Count -eq 0) { throw "Kein Projekt gefunden fuer '$Projekt'." }
    if ($t.Count -gt 1) { throw "Mehrdeutig - $($t.Count) Treffer: $(($t.Name) -join ', ')" }
    $ziel = $t[0]
    if (-not $ziel.Xml) { throw "Projekt '$($ziel.Name)' hat keine iSFP2.xml - die iSFP-Maske muss einmal geoeffnet und gespeichert worden sein." }
    if (-not $ziel.Zip) { throw "Projekt '$($ziel.Name)' hat keinen Container (eberater.zip)." }

    $projName = $ziel.Name; $zielXmlUUID = $ziel.XmlUUID; $altBytes = $ziel.Xml
    Write-Host "Projekt:  $projName" -ForegroundColor Cyan
    Write-Host "Container: $($ziel.ZipStand)   iSFP-XML: $($ziel.XmlStand)"
    if ($ziel.ZipStand -gt $ziel.XmlStand) {
        Write-Warning "Der Container ist juenger als die XML. Was seither an den Varianten geaendert wurde, steht noch nicht in der XML - iSFP-Maske einmal oeffnen und speichern."
    }

    $sicherung = Join-Path $Ablage "iSFP2-VORHER_$stempel.xml"
    [System.IO.File]::WriteAllBytes($sicherung, $altBytes)
    $sha = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($altBytes)).Replace('-', '')
    Write-Host "Sicherung: $sicherung"
    Write-Host "SHA-256:   $sha"
    $dok.Load((New-Object System.IO.MemoryStream(, [byte[]]$altBytes)))

    $arbeit = Join-Path $Ablage "container_$stempel"
    New-Item -ItemType Directory -Force -Path $arbeit | Out-Null
    $zipDatei = Join-Path $arbeit 'eberater.zip'
    [System.IO.File]::WriteAllBytes($zipDatei, $ziel.Zip)
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipDatei, $arbeit)
}

$wurzel = $dok.SelectSingleNode('/iSFP-Projekt')
$pakete = @($dok.SelectNodes('/iSFP-Projekt/massnahmenpakete/item'))
Write-Host "Pakete in der XML: $($pakete.Count)`n"

# ------------------------------------------------------------ Container lesen

$positionen = @{}
if (-not $NurPruefen) {
    function Tabelle([string] $pfad) {
        $roh = [System.IO.File]::ReadAllBytes($pfad); $kopf = BdeKopf $roh; $pos = $kopf.Daten
        $aus = @()
        while ($pos -lt $roh.Length) {
            $s = BdeLies $roh $kopf $pos -1
            $h = @{}; foreach ($v in $s.Werte) { $h[$v.Name] = $v.Wert }
            $aus += $h; $pos = $s.Ende
        }
        return $aus
    }

    $varianten = @{}
    foreach ($s in (Tabelle (Join-Path $arbeit 'TableProjekt.BDExit'))) {
        $varianten[[int]$s['PROJEKT_ID']] = [string]$s['VarianteBez']
    }
    $ids      = @($varianten.Keys | Sort-Object)
    $paketIds = @($ids | Select-Object -Skip 1)
    Write-Host "Varianten im Container: Ist = $($ids[0]), Pakete = $($paketIds -join ', ')"

    # Huellflaechen je Variante zu Positionen zusammenfassen. Mehrere Zeilen mit
    # demselben SANBEZ sind EINE Position - vier Wandzeilen, eine Wandposition.
    $jeVariante = @{}
    foreach ($s in (Tabelle (Join-Path $arbeit 'TableHuellfl.BDExit'))) {
        $sb = [string]$s['SANBEZ']
        if ([string]::IsNullOrWhiteSpace($sb)) { continue }
        $id = [int]$s['PROJ_ID']
        if (-not $jeVariante.ContainsKey($id)) { $jeVariante[$id] = @{} }
        $name = ('{0} - {1}' -f [string]$s['KENNZEICHEN'], $sb).Trim(' ', '-')
        if (-not $jeVariante[$id].ContainsKey($name)) {
            $jeVariante[$id][$name] = [pscustomobject]@{ Name = $name; Invest = 0.0; InvestEE = 0.0; Zeilen = 0 }
        }
        $p = $jeVariante[$id][$name]
        $p.Invest   += [double]$s['SANKOSTEN']
        $p.InvestEE += [double]$s['SANKOSTEN_EE']
        $p.Zeilen++
    }

    # Anlagenkosten aus derselben Datei, die anlagenkosten-setzen.ps1 fuehrt.
    $anlagen = @{}
    $akDatei = Join-Path $Werkzeug 'anlagenkosten.json'
    if (Test-Path -LiteralPath $akDatei) {
        $ak = Get-Content $akDatei -Raw -Encoding UTF8 | ConvertFrom-Json
        $e = $ak.PSObject.Properties | Where-Object { $_.Name -eq $projName } | Select-Object -First 1
        if ($e) {
            foreach ($zeile in $e.Value.zeilen) {
                $p = [int]$zeile.ab
                if (-not $anlagen.ContainsKey($p)) { $anlagen[$p] = @() }
                $anlagen[$p] += [pscustomobject]@{
                    Name = [string]$zeile.bezeichnung; Invest = [double]$zeile.invest
                    InvestEE = [double]$zeile.invest_ee; Zeilen = 0
                }
            }
        } else {
            Write-Warning "In anlagenkosten.json steht kein Eintrag fuer '$projName' - Waermepumpe, PV und Lueftung fehlen dann in den Kostenpositionen."
        }
    }

    # Kumulativ aufloesen: je Paket nur, was gegenueber dem Vorgaenger neu ist.
    for ($i = 0; $i -lt $paketIds.Count; $i++) {
        $paket  = $i + 1
        $jetzt  = $jeVariante[$paketIds[$i]]
        $vorher = if ($i -eq 0) { @{} } else { $jeVariante[$paketIds[$i - 1]] }
        $neu = @()
        if ($jetzt) {
            foreach ($n in ($jetzt.Keys | Sort-Object)) {
                if ($vorher -and $vorher.ContainsKey($n)) { continue }
                $neu += $jetzt[$n]
            }
        }
        if ($anlagen.ContainsKey($paket)) { $neu += $anlagen[$paket] }
        $positionen[$paket] = $neu
    }
}

# --------------------------------------------------------------- Stammdaten

if (-not $NurPruefen) {
    Write-Host "`nStammdaten des Buros" -ForegroundColor Yellow
    foreach ($e in $st.berater.PSObject.Properties) { SetzeFest $wurzel $e.Name $e.Value }

    foreach ($e in $st.vorgaben.PSObject.Properties) {
        # Energietraeger hat mehrere item - alle gleich behandeln.
        $treffer = @($wurzel.SelectNodes($e.Name))
        if ($treffer.Count -le 1) { [void](Setze $wurzel $e.Name $e.Value); continue }
        foreach ($k in $treffer) {
            if ($k.InnerText.Trim() -ne '' -and $k.InnerText.Trim() -ne 'nan') { continue }
            $k.InnerText = "$($e.Value)"; $script:Gesetzt++
            Write-Host ("    {0,-54} {1}" -f $e.Name, $e.Value)
        }
    }

    foreach ($e in $st.bilder.PSObject.Properties) {
        $bild = Join-Path $Werkzeug $e.Value
        if (-not (Test-Path -LiteralPath $bild)) { Write-Warning "Bild fehlt: $bild"; continue }
        $eltern = $wurzel.SelectSingleNode($e.Name)
        if (-not $eltern) { Write-Warning "Knoten $($e.Name) gibt es in dieser XML nicht."; continue }
        $strom = Knoten $eltern 'stream'
        if ($strom.InnerText.Trim() -ne '') { $script:Belassen.Add("$($e.Name)/stream (Bild stand schon drin)"); continue }
        $roh = [System.IO.File]::ReadAllBytes($bild)
        $strom.InnerText = [Convert]::ToBase64String($roh)
        (Knoten $eltern 'format').InnerText = 'IF_JPG'
        $script:Gesetzt++
        Write-Host ("    {0,-54} {1} ({2} KB)" -f "$($e.Name)/stream", (Split-Path -Leaf $bild), [math]::Round($roh.Length / 1KB))
    }

    # Briefanrede aus dem Eigentuemernamen. "Familie" ist die Annahme des Buros;
    # bei einem Einpersonenhaushalt muss der Berater sie ueberschreiben.
    $eig = $wurzel.SelectSingleNode('eigentuemer/vorNachname')
    if ($eig -and $eig.InnerText.Trim()) {
        $nach = (($eig.InnerText.Trim()) -split '\s+')[-1]
        [void](Setze $wurzel 'eigentuemer/briefanrede' "Sehr geehrte Familie $nach" 'aus eigentuemer/vorNachname - bei Einzelperson aendern')
    }
}

# --------------------------------- Rueckuebernahme aus der fertigen Datei
#
# Was in der Druckanwendung entsteht, kommt nie nach Hottgenroth zurueck. Bei
# Klenke standen 10 Bilder in der .mSFPprojekt-Datei und null im Projekt: waere
# dort "Erfassung zuruecksetzen" gedrueckt worden, waeren sie alle weg gewesen.
# Diese Richtung holt sie zurueck - nur dorthin, wo Hottgenroth leer ist.
#
# Bewusst NICHT dabei sind die Prinzipskizzen: die Druckanwendung rechnet beim
# Speichern jedes Bild auf rund 300 px herunter (Fensterskizze 2024 -> 296 px),
# die Fassung in Hottgenroth ist also die bessere.

if ($Uebernehmen) {
    if (-not (Test-Path -LiteralPath $Uebernehmen)) { throw "Uebernahme-Datei $Uebernehmen gibt es nicht." }
    $quelle = New-Object System.Xml.XmlDocument
    $quelle.PreserveWhitespace = $false
    $quelle.Load($Uebernehmen)
    $qWurzel = $quelle.SelectSingleNode('/iSFP-Projekt')
    if (-not $qWurzel) { throw "$Uebernehmen ist keine iSFP-Datei." }

    Write-Host "`nRueckuebernahme aus $(Split-Path -Leaf $Uebernehmen)" -ForegroundColor Yellow
    $script:Uebernommen = 0; $uebBelegt = 0

    # Fuellt $ziel aus $q, Blatt fuer Blatt. Fehlende Blaetter werden angelegt,
    # belegte nicht angefasst. Ein Blatt ist, was keine Elementkinder hat.
    function Uebertrage([System.Xml.XmlNode] $q, [System.Xml.XmlNode] $ziel, [string] $pfad) {
        $kinder = @($q.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
        if ($kinder.Count -eq 0) {
            $wert = $q.InnerText
            if ([string]::IsNullOrWhiteSpace($wert) -or $wert.Trim() -eq 'nan') { return }
            $alt = $ziel.InnerText.Trim()
            if ($alt -ne '' -and $alt -ne 'nan') { $script:UebBelegt++; return }
            $ziel.InnerText = $wert
            $script:Uebernommen++
            $zeig = $wert.Trim()
            if ($zeig.Length -gt 40) { $zeig = (Kuerze $zeig 40) + ' … (' + [math]::Round($wert.Length * 3 / 4 / 1KB) + ' KB)' }
            Write-Host ("    {0,-58} {1}" -f $pfad, $zeig)
            return
        }
        $zaehler = @{}
        foreach ($k in $kinder) {
            $n = $k.Name
            $zaehler[$n] = ($zaehler[$n] + 1)
            $gleiche = @($ziel.SelectNodes($n))
            if ($zaehler[$n] -le $gleiche.Count) { $zk = $gleiche[$zaehler[$n] - 1] }
            else { $zk = $ziel.AppendChild($ziel.OwnerDocument.CreateElement($n)) }
            $mark = if ($n -eq 'item') { "$n[$($zaehler[$n])]" } else { $n }
            Uebertrage $k $zk "$pfad/$mark"
        }
    }

    $script:UebBelegt = 0
    foreach ($pfad in $st.rueckuebernahme) {
        $qKnoten = @($qWurzel.SelectNodes($pfad))
        if ($qKnoten.Count -eq 0) { continue }
        $zKnoten = @($wurzel.SelectNodes($pfad))
        for ($i = 0; $i -lt $qKnoten.Count; $i++) {
            if ($i -lt $zKnoten.Count) { $z = $zKnoten[$i] }
            else {
                # Der Ast fehlt in Hottgenroth. Nur ein weiteres item unter einem
                # vorhandenen Elternteil wird angelegt, sonst wird gemeldet.
                $eltern = Split-Path $pfad -Parent
                $e = if ($eltern) { $wurzel.SelectSingleNode(($eltern -replace '\\', '/')) } else { $wurzel }
                if (-not $e) { Write-Warning "    $pfad gibt es in Hottgenroth nicht - uebersprungen."; break }
                $z = $e.AppendChild($dok.CreateElement((Split-Path $pfad -Leaf)))
            }
            $mark = if ($qKnoten.Count -gt 1) { "$pfad[$($i+1)]" } else { $pfad }
            Uebertrage $qKnoten[$i] $z $mark
        }
    }
    Write-Host ("    uebernommen: {0}   in Hottgenroth schon belegt, gelassen: {1}" -f $script:Uebernommen, $script:UebBelegt) -ForegroundColor Green
}

# ------------------------------------------------- Kostenpositionen und Geld

if (-not $NurPruefen) {
    Write-Host "`nKostenpositionen aus dem Container" -ForegroundColor Yellow
    $nichtFoerder = [string]$st.foerderung.nicht_foerderfaehig

    for ($i = 0; $i -lt $pakete.Count; $i++) {
        $paket = $i + 1
        $mp    = $pakete[$i]
        $liste = @($positionen[$paket])
        if (-not $liste -or $liste.Count -eq 0) {
            Write-Host "  MP$paket  keine neue Position - gegenueber dem Vorgaenger ist nichts dazugekommen." -ForegroundColor DarkYellow
            continue
        }

        # Topf bestimmen: erste Regel, die auf eine der neuen Positionen passt.
        $topfName = 'huelle'
        foreach ($r in $st.foerderung.regeln) {
            $tr = @($liste | Where-Object { (Entumlaut $_.Name) -match (Entumlaut $r.muster) })
            if ($tr.Count -gt 0) { $topfName = [string]$r.topf; break }
        }
        $topf = $st.foerderung.toepfe.$topfName
        Write-Host ("  MP{0}   Topf: {1}   {2}" -f $paket, $topfName, $topf.name) -ForegroundColor Yellow
        if ($topf.hinweis) { $script:Abweichungen.Add("MP$paket $($topf.hinweis)") }

        $ep = $mp.SelectSingleNode('einzelPositionen')
        if (-not $ep) { $ep = Knoten $mp 'einzelPositionen' }
        $vorhanden = @($ep.SelectNodes('item'))

        $sInv = 0.0; $sSow = 0.0; $sFoe = 0.0
        if ($vorhanden.Count -gt 0) {
            # Der Berater war schneller. Seine Positionen bleiben, wie sie sind -
            # aber die Summen darunter werden aus IHNEN gebildet, nicht aus dem
            # Container. Sonst widerspraeche die Paketsumme ihren eigenen Posten.
            # Und die Foerderung, die er je Position eingetragen hat, wird nicht
            # nachgerechnet: dort stecken Deckel und Boni, die hier nicht stehen.
            Write-Host ("       {0} Position(en) stehen schon drin - gelassen, Summen daraus gebildet." -f $vorhanden.Count) -ForegroundColor DarkGray
            $script:Belassen.Add("MP$paket/einzelPositionen ($($vorhanden.Count) Positionen)")
            foreach ($it in $vorhanden) {
                $sInv += (Zahl $it 'investitionsKosten')
                $sSow += (Zahl $it 'sowiesoKosten')
                $sFoe += (Zahl $it 'foerderung')
            }
            # Gegenprobe: was von Hand getippt wurde, gegen das, was im Container
            # steht. Abweichungen ueber der Rundungsschwelle sind fast immer
            # Zahlendreher - in Klenke stand die Sowieso-Zeile der Aussenwand auf
            # 0, obwohl der Container 16.200 EUR hergibt.
            foreach ($it in $vorhanden) {
                $nk = $it.SelectSingleNode('name'); if (-not $nk) { continue }
                $nm = $nk.InnerText.Trim()
                $c = $liste | Where-Object { (Entumlaut $_.Name) -eq (Entumlaut $nm) } | Select-Object -First 1
                if (-not $c) { continue }
                $cSow = [Math]::Max(0.0, $c.Invest - $c.InvestEE)
                foreach ($v in @(@('investitionsKosten', $c.Invest), @('sowiesoKosten', $cSow))) {
                    $ist = Zahl $it $v[0]
                    $soll = [double]$v[1]
                    if ([Math]::Abs($ist - $soll) -le [Math]::Max([double]$st.pruefung.rundung_euro, $soll * 0.02)) { continue }
                    $script:Abweichungen.Add(("MP{0} '{1}': {2} steht auf {3} EUR, der Container rechnet {4} EUR." -f `
                        $paket, (Kuerze $nm 40), $v[0], (Euro $ist), (Euro $soll)))
                }
            }

            # Fehlt an einer Position der Foerderbetrag, wird er hier nachgetragen -
            # 'nan' im Fahrplan ist genau der Zustand, der in Klenke gedruckt wurde.
            foreach ($it in $vorhanden) {
                $fk = $it.SelectSingleNode('foerderung')
                if (-not $fk -or ($fk.InnerText.Trim() -ne '' -and $fk.InnerText.Trim() -ne 'nan')) { continue }
                $nm = ''
                $nk = $it.SelectSingleNode('name'); if ($nk) { $nm = $nk.InnerText.Trim() }
                $inv = Zahl $it 'investitionsKosten'
                $foe = 0.0
                if ([double]$topf.satz -gt 0 -and -not ((Entumlaut $nm) -match (Entumlaut $nichtFoerder))) {
                    $foe = [Math]::Min($inv, [double]$topf.deckel) * [double]$topf.satz
                }
                $fk.InnerText = Euro $foe; $sFoe += $foe; $script:Gesetzt++
                Write-Host ("       {0,-50} Foerderung war 'nan', jetzt {1} EUR" -f (Kuerze $nm 50), (Euro $foe))
            }
        } else {
            foreach ($p in $liste) {
                $sow = [Math]::Max(0.0, $p.Invest - $p.InvestEE)
                $foe = 0.0
                if ([double]$topf.satz -gt 0 -and -not ((Entumlaut $p.Name) -match (Entumlaut $nichtFoerder))) {
                    $basis = [Math]::Min($p.Invest, [double]$topf.deckel)
                    $foe = $basis * [double]$topf.satz
                }
                $it = $ep.AppendChild($dok.CreateElement('item'))
                (Knoten $it 'name').InnerText               = $p.Name
                (Knoten $it 'investitionsKosten').InnerText = Euro $p.Invest
                (Knoten $it 'sowiesoKosten').InnerText      = Euro $sow
                (Knoten $it 'foerderung').InnerText         = Euro $foe
                $sInv += $p.Invest; $sSow += $sow; $sFoe += $foe
                $script:Gesetzt++
                Write-Host ("       {0,-50} {1,8} EUR   Sowieso {2,7} EUR   Foerderung {3,7} EUR{4}" -f `
                    (Kuerze $p.Name 50), (Euro $p.Invest), (Euro $sow), (Euro $foe),
                    $(if ($p.Zeilen -gt 1) { "   [$($p.Zeilen) Bauteilzeilen]" } else { '' }))
            }
        }

        [void](Setze $mp 'wirtschaftlichkeit/investition'           (Euro $sInv))
        [void](Setze $mp 'wirtschaftlichkeit/instandsetzungskosten' (Euro $sSow))
        [void](Setze $mp 'wirtschaftlichkeit/foerderbetrag'         (Euro $sFoe))

        # Ohne dieses Haekchen zeigt die Fahrplan-Grafik keinen Foerderbalken,
        # auch wenn der Betrag danebensteht. Genau das hat in Klenke gefehlt.
        if ($sFoe -gt 0) {
            $fm = Knoten ($mp.SelectSingleNode('wirtschaftlichkeit')) 'foerderungMoeglich'
            if ($fm.InnerText.Trim() -ne 'true') {
                $fm.InnerText = 'true'; $script:Gesetzt++
                Write-Host ("       {0,-50} true   (weil Foerderbetrag {1} EUR)" -f 'wirtschaftlichkeit/foerderungMoeglich', (Euro $sFoe))
            }
        }
        if ($topf.name) {
            [void](Setze $mp 'foerderProgramm/name'         $topf.name)
            [void](Setze $mp 'foerderProgramm/beschreibung' $topf.beschreibung)
        }
        Write-Host ("       {0,-50} {1,8} EUR   Sowieso {2,7} EUR   Foerderung {3,7} EUR" -f `
            'SUMME Paket', (Euro $sInv), (Euro $sSow), (Euro $sFoe)) -ForegroundColor DarkGray
    }

    Write-Host ("`n    gesetzt: {0}   Stammdaten korrigiert: {1}   schon belegt und gelassen: {2}" -f `
        $script:Gesetzt, $script:Korrigiert, $script:Belassen.Count) -ForegroundColor Green
    if ($script:Belassen.Count -gt 0) {
        # Zusammengefasst - sonst steht foerderProgramm/name fuenfmal da.
        $kurz = $script:Belassen | ForEach-Object { ($_ -split ' = ')[0] -replace '^MP\d+/', '' } |
                Group-Object | Sort-Object Count -Descending |
                ForEach-Object { if ($_.Count -gt 1) { "$($_.Name) x$($_.Count)" } else { $_.Name } }
        Write-Host ("    davon: {0}" -f ($kurz -join ', ')) -ForegroundColor DarkGray
    }
    if ($script:Abweichungen.Count -gt 0) {
        Write-Host "`n    Bitte nachsehen:" -ForegroundColor Yellow
        foreach ($a in $script:Abweichungen) { Write-Host "       $a" -ForegroundColor Yellow }
    }
}

# ------------------------------------------------------------- Pruefliste
#
# Was jetzt noch leer ist, ist entweder Ortskenntnis oder ein Knopfdruck in der
# Maske. Beides kann das Werkzeug nicht leisten - aber es kann genau sagen,
# welches von beidem, und wo es herkommt. Die Liste ist aus dem Abgleich
# Rohexport gegen fertigen Klenke-Fahrplan entstanden; sie enthaelt jedes Feld,
# das dort von Hand gefuellt wurde und hier nicht automatisch faellt.

$offen = @(
    @{ pfad = 'bafa_vorgangs_nr';                     quelle = 'BAFA-Antrag';        was = 'Vorgangsnummer aus der Zuwendungsbestaetigung' }
    @{ pfad = 'techDoku/beschr_keller';               quelle = 'Ortstermin';         was = 'Kellerdecke: Aufbau, Dicke, Baujahr' }
    @{ pfad = 'techDoku/beschr_kellerabgang';         quelle = 'Ortstermin';         was = 'Treppe, Tuer, Lage' }
    @{ pfad = 'techDoku/beschr_wand';                 quelle = 'Ortstermin';         was = 'Wandaufbau je Geschoss' }
    @{ pfad = 'techDoku/beschr_fenster';              quelle = 'Ortstermin';         was = 'Verglasung, Rahmen, Baujahr' }
    @{ pfad = 'techDoku/beschr_dach';                 quelle = 'Ortstermin';         was = 'Dachform, Konstruktion, Deckung' }
    @{ pfad = 'techDoku/beschr_heizung';              quelle = 'Typenschild';        was = 'Hersteller, Typ, Leistung, Baujahr' }
    @{ pfad = 'techDoku/beschr_verteilung';           quelle = 'Ortstermin';         was = 'Rohrnetz, Pumpen, Daemmung' }
    @{ pfad = 'techDoku/beschr_tww';                  quelle = 'Ortstermin';         was = 'Speicher, Volumen, Zirkulation' }
    @{ pfad = 'techDoku/beschr_lueftung';             quelle = 'Ortstermin';         was = 'Lueftungsart, Luftdichtheit' }
    @{ pfad = 'nutzereinfluss/anwesenheit';           quelle = 'Nutzergespraech';    was = 'Personenzahl, Stunden zu Hause' }
    @{ pfad = 'nutzereinfluss/raumnutzung';           quelle = 'Nutzergespraech';    was = 'welche Raeume wie beheizt' }
    @{ pfad = 'nutzereinfluss/lueftverhalten';        quelle = 'Nutzergespraech';    was = 'wie oft, wie lange' }
    @{ pfad = 'wirtschaftlichkeit/energiekosten';     quelle = 'Maske: berechnen';   was = 'iSFP > Kosten > Knopf berechnen' }
    @{ pfad = 'kennwerte_sfp/verbrauch';              quelle = 'Maske: berechnen';   was = 'Verbrauch Ist-Zustand' }
)
$offenPaket = @(
    @{ pfad = 'anlassFahrplan';                       quelle = 'Beraterentscheidung'; was = 'Jahreszahl / Nach Faelligkeit / Nach Budget' }
    @{ pfad = 'wirtschaftlichkeit/energiekosten';     quelle = 'Maske: berechnen';    was = 'Energiekosten des Pakets' }
    @{ pfad = 'kennwerte_sfp/verbrauch';              quelle = 'Maske: berechnen';    was = 'Verbrauch nach dem Paket' }
)

Write-Host "`n=== Pruefliste: was noch fehlt ===" -ForegroundColor Cyan
$fehlt = 0
foreach ($o in $offen) {
    $k = $wurzel.SelectSingleNode($o.pfad)
    $wert = if ($k) { $k.InnerText.Trim() } else { '' }
    if ($wert -ne '' -and $wert -ne 'nan') { continue }
    $fehlt++
    Write-Host ("   {0,-18} {1,-42} {2}" -f $o.quelle, $o.pfad, $o.was)
}
$fehltPaket = @()
for ($i = 0; $i -lt $pakete.Count; $i++) {
    foreach ($o in $offenPaket) {
        $k = $pakete[$i].SelectSingleNode($o.pfad)
        $wert = if ($k) { $k.InnerText.Trim() } else { '' }
        if ($wert -ne '' -and $wert -ne 'nan') { continue }
        $fehltPaket += ('MP{0} {1}' -f ($i + 1), $o.pfad)
    }
}
# Die Fotos stehen NICHT hier - sie liegen in PrMedia und kommen erst beim
# Erzeugen der .mSFPprojekt herein. Geprueft werden sie weiter unten an ihrer
# eigenen Stelle; ein leerer Stream ist kein Mangel.
if ($fehltPaket.Count -gt 0) {
    Write-Host ("   {0,-18} {1}" -f 'je Paket', ($fehltPaket -join ', '))
}
Write-Host ("   -> {0} projektweite Felder offen, {1} Paketfelder offen" -f $fehlt, $fehltPaket.Count) -ForegroundColor DarkGray

# --------------------------------------------------- Bilder in Hottgenroth
#
# Zwei Bildsorten, zwei getrennte Wege - das zu verwechseln kostet Arbeit:
#
#   Titelbild, Foto heute, Ansichten
#       liegen in PrMedia (MediaType 14/15), nicht in der iSFP2.xml. Die
#       Software setzt die Bytes erst ein, wenn sie die .mSFPprojekt erzeugt.
#       In allen 59 Projekten dieser Datenbank ist jeder Foto-Stream in der
#       iSFP2.xml leer - das ist der Normalzustand, kein Fehler.
#           XimMediaType  = Funktion (10 Titelbild, 12 Foto heute, 13 Ansicht,
#                           1 Unterlage/Plan, 0 ohne Funktion)
#           Category      = Reihenfolge innerhalb der Funktion
#           ShortDesc     -> titel        InfoDesc -> beschreibung
#           MediaCopyright-> bildquelle
#       An Messinger und Bieche Feld fuer Feld nachgewiesen.
#
#   Prinzipskizzen je Massnahme
#       werden in der iSFP-Maske oder in der Druckanwendung hochgeladen und
#       liegen direkt in der iSFP2.xml. Die fuellt isfp-texte-fuellen.ps1 aus
#       dem Ordner Massnahmenbilder.
#
# Hier wird nur geprueft, nicht geschrieben: was am Bild fehlt, gehoert in die
# Bilderverwaltung von Hottgenroth.

if (-not $Datei) {
    Write-Host "`n=== Bilder in Hottgenroth (PrMedia) ===" -ForegroundColor Cyan
    $bilder = @()
    $cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
    $cn.Open()
    try {
        $cmd = $cn.CreateCommand()
        $cmd.CommandText = @'
SELECT m.XimMediaType, m.Category, m.ShortDesc, m.InfoDesc, m.MediaCopyright, DATALENGTH(m.Media) AS Bytes
FROM PrMedia m JOIN PrProject p ON p.UUID = m.ProjectUUID
WHERE p.LongDesc = @p AND m.MediaType IN (14, 15)
ORDER BY m.XimMediaType, m.Category
'@
        $null = $cmd.Parameters.AddWithValue('@p', $projName)
        $rd = $cmd.ExecuteReader()
        while ($rd.Read()) {
            $bilder += [pscustomobject]@{
                Funktion = [int]$rd['XimMediaType']
                Kategorie = "$($rd['Category'])"
                Titel = "$($rd['ShortDesc'])".Trim()
                Beschreibung = "$($rd['InfoDesc'])".Trim()
                Quelle = "$($rd['MediaCopyright'])".Trim()
                KB = [math]::Round([double]$rd['Bytes'] / 1KB)
            }
        }
        $rd.Close()
    } finally { $cn.Close() }

    if ($bilder.Count -eq 0) {
        Write-Host "   keine Bilder im Projekt." -ForegroundColor Yellow
    } else {
        $ohneFunktion = @(); $ohneName = @(); $ohneText = @()
        foreach ($f in @('10', '12', '13', '1', '0')) {
            $grp = @($bilder | Where-Object { "$($_.Funktion)" -eq $f })
            if ($grp.Count -eq 0) { continue }
            $def = $st.bildfunktionen.$f
            $soll = if ($def) { [int]$def.anzahl } else { 0 }
            $zeile = "   {0,-18} {1} Bild(er)" -f $(if ($def) { $def.name } else { "XimMediaType $f" }), $grp.Count
            if ($def -and $def.ziel) { $zeile += "  ->  $($def.ziel)" }
            if ($soll -gt 0 -and $grp.Count -ne $soll) { $zeile += "   [erwartet: $soll]" }
            Write-Host $zeile -ForegroundColor $(if ($f -eq '0') { 'Yellow' } else { 'Gray' })
            foreach ($b in $grp) {
                $mangel = @()
                if ($b.Titel -eq '' -or $b.Titel -match '^(PICT_|IMG_|\d{8}_\d{6})') { $mangel += 'Name' }
                if ($b.Beschreibung -eq '') { $mangel += 'Beschreibung' }
                Write-Host ("        Kat {0,-3} {1,-26} {2,-44} {3,5} KB  {4}" -f `
                    $b.Kategorie, (Kuerze $b.Titel 26), (Kuerze $b.Beschreibung 44), $b.KB,
                    $(if ($mangel) { "<- es fehlt: $($mangel -join ' und ')" } else { '' })) `
                    -ForegroundColor $(if ($mangel -and $f -in @('10','12','13')) { 'Yellow' } else { 'DarkGray' })
                if ($f -in @('10', '12', '13')) {
                    if ($mangel -contains 'Name')         { $ohneName += "$($def.name) Kat $($b.Kategorie)" }
                    if ($mangel -contains 'Beschreibung') { $ohneText += "$($def.name) Kat $($b.Kategorie)" }
                }
            }
            if ($f -eq '0') { foreach ($b in $grp) { $ohneFunktion += $b.Titel } }
        }
        Write-Host ""
        if ($ohneFunktion) { Write-Host "   $($ohneFunktion.Count) Bild(er) ohne Funktion - erscheinen im Fahrplan nicht: $($ohneFunktion -join ', ')" -ForegroundColor Yellow }
        if ($ohneName)     { Write-Host "   $($ohneName.Count) Bild(er) tragen noch den Dateinamen statt eines Titels: $($ohneName -join ', ')" -ForegroundColor Yellow }
        if ($ohneText)     { Write-Host "   $($ohneText.Count) Bild(er) ohne Beschreibung - die Druckpruefung bemaengelt kurze Bildtexte: $($ohneText -join ', ')" -ForegroundColor Yellow }
        if (-not ($ohneFunktion -or $ohneName -or $ohneText)) { Write-Host "   Funktion, Titel und Beschreibung sind ueberall gesetzt." -ForegroundColor Green }
        Write-Host "   Gepflegt wird das in Hottgenroth an der Bilderverwaltung, nicht hier." -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------- Schlusspruefung
#
# Jede dieser Pruefungen steht fuer einen Fehler, der in Klenke tatsaechlich
# passiert ist. Sie sind der eigentliche Ertrag des Abgleichs.

Write-Host "`n=== Schlusspruefung ===" -ForegroundColor Cyan
$funde = New-Object System.Collections.Generic.List[string]

# 1) Pilcrow. Die Textbausteindateien trennen Absaetze mit U+00B6; im Fahrplan
#    wird das Zeichen woertlich gedruckt. 39 echte Exporte kennen es nicht.
$pilcrow = @($dok.SelectNodes('//*[not(*)]') | Where-Object { $_.InnerText -and $_.InnerText.IndexOf([char]0xB6) -ge 0 })
if ($pilcrow.Count -gt 0) { $funde.Add("$($pilcrow.Count) Feld(er) enthalten noch ein Pilcrow-Zeichen - isfp-texte-fuellen.ps1 raeumt sie beim naechsten Lauf auf.") }

# 2) nan als ganzer Feldwert. Teiltreffer wie "Finanzierung" zaehlen nicht.
$nan = @($dok.SelectNodes('//*[not(*)]') | Where-Object { $_.InnerText.Trim() -eq 'nan' })
if ($nan.Count -gt 0) {
    $wo = ($nan | ForEach-Object { $_.Name } | Group-Object | Sort-Object Count -Descending |
           Select-Object -First 6 | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
    $funde.Add("$($nan.Count) Feld(er) stehen auf 'nan': $wo")
}

# 3) Foerderbetrag ohne Haekchen - dann fehlt der Balken in der Fahrplan-Grafik.
for ($i = 0; $i -lt $pakete.Count; $i++) {
    $b = $pakete[$i].SelectSingleNode('wirtschaftlichkeit/foerderbetrag')
    $m = $pakete[$i].SelectSingleNode('wirtschaftlichkeit/foerderungMoeglich')
    if (-not $b -or -not $m) { continue }
    $betrag = 0.0; [void][double]::TryParse($b.InnerText.Trim(), [ref]$betrag)
    if ($betrag -gt 0 -and $m.InnerText.Trim() -ne 'true') {
        $funde.Add("MP$($i+1): Foerderbetrag $([int]$betrag) EUR, aber foerderungMoeglich steht auf '$($m.InnerText.Trim())' - die Grafik zeigt dann keinen Foerderanteil.")
    }
}

# 4) Summe der Positionen gegen die Paketsumme.
for ($i = 0; $i -lt $pakete.Count; $i++) {
    $items = @($pakete[$i].SelectNodes('einzelPositionen/item'))
    if ($items.Count -eq 0) { continue }
    foreach ($paar in @(@('investitionsKosten', 'investition'), @('sowiesoKosten', 'instandsetzungskosten'), @('foerderung', 'foerderbetrag'))) {
        $summe = 0.0
        foreach ($it in $items) {
            $k = $it.SelectSingleNode($paar[0]); if (-not $k) { continue }
            $v = 0.0; if ([double]::TryParse($k.InnerText.Trim(), [ref]$v)) { $summe += $v }
        }
        $g = $pakete[$i].SelectSingleNode('wirtschaftlichkeit/' + $paar[1])
        if (-not $g) { continue }
        $gv = 0.0
        if (-not [double]::TryParse($g.InnerText.Trim(), [ref]$gv)) { continue }
        if ([Math]::Abs($summe - $gv) -gt [Math]::Max(50.0, $gv * 0.02)) {
            $funde.Add("MP$($i+1): Summe der Positionen ($([int]$summe) EUR, Feld $($paar[0])) passt nicht zu wirtschaftlichkeit/$($paar[1]) = $([int]$gv) EUR.")
        }
    }
}

# 5) Komponente ohne Kostenposition. In Klenke stand die Lueftungsanlage als
#    Komponente in MP5, aber ihre 13.200 EUR standen in keiner Position.
for ($i = 0; $i -lt $pakete.Count; $i++) {
    $komp = @($pakete[$i].SelectNodes('sanierungskomponenten/item')).Count
    $pos  = @($pakete[$i].SelectNodes('einzelPositionen/item')).Count
    if ($komp -gt 0 -and $pos -eq 0) { $funde.Add("MP$($i+1): $komp Komponente(n), aber keine einzige Kostenposition.") }
}

# 6) Zwei techDoku-Felder mit demselben Text - fast immer ein Kopierfehler.
$td = @{}
foreach ($k in @($wurzel.SelectNodes('techDoku/*'))) {
    $t = $k.InnerText.Trim()
    if ($t.Length -lt 30) { continue }
    if ($td.ContainsKey($t)) { $funde.Add("techDoku/$($td[$t]) und techDoku/$($k.Name) stehen wortgleich - vermutlich hineinkopiert.") }
    else { $td[$t] = $k.Name }
}

# 7) Bildunterschriften. Die Druckapplikation meldet "Bildbeschreibung zu kurz".
$minLen = [int]$st.pruefung.bildbeschreibung_min
$kurz = @()
foreach ($pfad in @('fotos/fotoHeute/item', 'fotos/ansichten/item')) {
    $n = 0
    foreach ($it in @($wurzel.SelectNodes($pfad))) {
        $n++
        $s = $it.SelectSingleNode('stream')
        if (-not $s -or $s.InnerText.Trim() -eq '') { continue }
        $b = $it.SelectSingleNode('beschreibung')
        $t = if ($b) { $b.InnerText.Trim() } else { '' }
        if ($t.Length -lt $minLen) { $kurz += "$pfad[$n] (`"$t`")" }
    }
}
if ($kurz.Count -gt 0) { $funde.Add("Bildbeschreibung kuerzer als $minLen Zeichen: $($kurz -join ', ')") }

# 8) PLZ und Ort widersprechen sich. In Klenke steht PLZ 27229 und Ort
#    "27299 Langwedel" - eine der beiden Zahlen ist falsch.
foreach ($wer in @('eigentuemer', 'energieberater')) {
    $plzK = $wurzel.SelectSingleNode("$wer/PLZ"); $ortK = $wurzel.SelectSingleNode("$wer/ort")
    if (-not $plzK -or -not $ortK) { continue }
    $plz = $plzK.InnerText.Trim(); $ort = $ortK.InnerText.Trim()
    if ($plz -eq '' -or $ort -eq '') { continue }
    if ($ort -match '(\d{5})' -and $matches[1] -ne $plz) {
        $funde.Add("$wer : PLZ steht auf '$plz', im Ortsfeld steht aber '$($matches[1])' ($ort).")
    }
}

# 9) Komponente ohne Ausfuehrungstext - dann bleibt die Seite im Druck leer.
$ohneText = 0
for ($i = 0; $i -lt $pakete.Count; $i++) {
    foreach ($k in @($pakete[$i].SelectNodes('sanierungskomponenten/item'))) {
        $mit = @($k.SelectNodes('ausfuehrung/item/beschreibung') | Where-Object { $_.InnerText.Trim() -ne '' }).Count
        if ($mit -eq 0) { $ohneText++ }
    }
}
if ($ohneText -gt 0) { $funde.Add("$ohneText Komponente(n) ohne Ausfuehrungstext - isfp-texte-fuellen.ps1 laufen lassen.") }

if ($funde.Count -eq 0) {
    Write-Host "   nichts zu beanstanden." -ForegroundColor Green
} else {
    foreach ($f in $funde) { Write-Host "   $f" -ForegroundColor Yellow }
}

# ------------------------------------------------------------- Zurueckschreiben

if ($NurPruefen) { Write-Host "`nNur geprueft - nichts geaendert." -ForegroundColor Magenta; return }

$einst = New-Object System.Xml.XmlWriterSettings
$einst.Encoding = New-Object System.Text.UTF8Encoding($false)
$einst.Indent = $false
$strom = New-Object System.IO.MemoryStream
$schreiber = [System.Xml.XmlWriter]::Create($strom, $einst)
$dok.Save($schreiber); $schreiber.Flush(); $schreiber.Close()
$neuBytes = $strom.ToArray()

if ($Vorschau) {
    Write-Host "`nVORSCHAU - nichts geschrieben. Neue Groesse waere $([math]::Round($neuBytes.Length/1KB)) KB (vorher $([math]::Round($altBytes.Length/1KB)) KB)." -ForegroundColor Magenta
    Write-Host "Zum Schreiben denselben Aufruf mit -Schreiben."
    return
}

# Beide Anwendungen halten ihren Stand im Speicher und schreiben ihn beim
# Speichern zurueck. Laeuft eine von beiden, ist jede Aenderung von aussen weg.
foreach ($p in @('Energie', 'MeinSanierungsfahrplan')) {
    $laeuft = Get-Process $p -ErrorAction SilentlyContinue
    if ($laeuft) { throw "$p.exe laeuft (PID $($laeuft.Id -join ', ')) und ueberschreibt den Stand beim naechsten Speichern - erst schliessen." }
}

$ausDatei = Join-Path $Ablage "$($projName -replace '[^\w\-]', '_')_$stempel.mSFPprojekt"
[System.IO.File]::WriteAllBytes($ausDatei, $neuBytes)

$cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$cn.Open()
try {
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = 'UPDATE PrMedia SET Media = @b, StampEdit = GETDATE() WHERE UUID = @u'
    $par = $cmd.Parameters.Add('@b', [System.Data.SqlDbType]::VarBinary, -1); $par.Value = $neuBytes
    $null = $cmd.Parameters.AddWithValue('@u', $zielXmlUUID)
    $zeilenZahl = $cmd.ExecuteNonQuery()
} finally { $cn.Close() }

$cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$cn.Open()
try {
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = 'SELECT Media FROM PrMedia WHERE UUID = @u'
    $null = $cmd.Parameters.AddWithValue('@u', $zielXmlUUID)
    $zurueck = $cmd.ExecuteScalar()
} finally { $cn.Close() }

$shaNeu = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($neuBytes)).Replace('-', '')
$shaDb  = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($zurueck)).Replace('-', '')
if ($shaNeu -ne $shaDb) { throw 'Gegenprobe fehlgeschlagen: was in der Datenbank steht, ist nicht, was geschrieben wurde.' }

Write-Host "`nGeschrieben: PrMedia ($zeilenZahl Zeile), $([math]::Round($neuBytes.Length/1KB)) KB, Gegenprobe ok." -ForegroundColor Green
Write-Host "Datei:       $ausDatei"
Write-Host "Zurueck:     $sicherung"
