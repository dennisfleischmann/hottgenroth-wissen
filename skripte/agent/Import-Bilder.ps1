# Legt Bilder in der Bilderverwaltung eines Hottgenroth-Projekts an.
#
# WOZU
# Ein Bild in Hottgenroth ist eine Zeile in PrMedia. Daran haengen vier
# Angaben, und jede landet an einer festen Stelle im iSFP:
#
#   XimMediaType    Funktion   10 Titelbild, 12 Foto heute, 13 Ansicht,
#                              1 Unterlage/Plan, 17 Zonierung, 18 Systemgrenze,
#                              11 Unterschrift, 0 ohne Funktion
#   Category        Reihenfolge innerhalb der Funktion, aufsteigend
#   ShortDesc       Name         -> fotos/.../titel
#   InfoDesc        Beschreibung -> fotos/.../beschreibung
#   MediaCopyright  Bildquelle   -> fotos/.../bildquelle
#
# An zwei fremden Projekten Feld fuer Feld nachgewiesen: die Anzahl der Zeilen
# je Funktion stimmt exakt mit den item-Knoten unter fotos/ ueberein, und die
# Reihenfolge folgt Category.
#
# Ein Bild mit XimMediaType 0 erscheint im Fahrplan ueberhaupt nicht - die
# Funktion ist deshalb Pflicht, nicht Beiwerk.
#
# WICHTIG: Die Bilddaten gehen NICHT in die iSFP2.xml. Die Software setzt sie
# erst ein, wenn sie die .mSFPprojekt fuer die Druckanwendung erzeugt. In allen
# 59 geprueften Projekten ist jeder Foto-Stream in der iSFP2.xml leer - das ist
# der Normalzustand und kein Mangel.
#
# AUFRUF
#   .\Import-Bilder.ps1 -ProjectGuid '<GUID>' -Manifest '<pfad.json>'
#   .\Import-Bilder.ps1 -ProjectGuid '<GUID>' -Manifest '<pfad.json>' -Schreiben
#
#   -Ersetzen    belegt einen Platz (Funktion + Reihenfolge) neu, statt ihn
#                zu ueberspringen
#   -Ziel        wohin bilder-import.json geschrieben wird; ausserdem die Basis
#                fuer relative Dateinamen im Manifest
#
# MANIFEST
#   { "bilder": [
#       { "datei": "fassade.jpg", "funktion": 12, "reihenfolge": 1,
#         "name": "Fassade", "beschreibung": "Verputzte Aussenwand ohne Daemmung",
#         "bildquelle": "FS Energieberater" } ] }
#
#   "reihenfolge" darf fehlen - dann wird der naechste freie Platz der Funktion
#   genommen. Alles ausser "bildquelle" und "reihenfolge" ist Pflicht.
#
# Energieberater.exe muss GESCHLOSSEN sein. Eine laufende Instanz haelt den
# Projektstand im Speicher und schreibt ihn beim naechsten Speichern zurueck -
# die neuen Zeilen waeren dann wieder weg.

param(
    [Parameter(Mandatory)] [string] $ProjectGuid,
    [Parameter(Mandatory)] [string] $Manifest,
    [string] $Ziel,
    [switch] $Schreiben,
    [switch] $Ersetzen,
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Die Funktionen, die es gibt. Eine POSITIVLISTE: was hier nicht steht, wird
# nicht geschrieben. Eine erfundene Nummer waere ein Bild, das in keiner
# Ansicht der Software mehr auftaucht und das niemand wiederfindet.
$Funktionen = @{
    10 = 'Titelbild'
    12 = 'Foto heute'
    13 = 'Ansicht'
    1  = 'Unterlage (Plan)'
    17 = 'Zonierung'
    18 = 'Systemgrenze'
    11 = 'Unterschrift'
}

# Wie viele Bilder eine Funktion im iSFP traegt. 0 heisst beliebig viele.
$Erwartet = @{ 10 = 1; 12 = 4; 13 = 0; 1 = 0; 17 = 0; 18 = 0; 11 = 1 }

$GUID = '^\{?[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}?$'
if ($ProjectGuid -notmatch $GUID) { throw "'$ProjectGuid' ist keine Projekt-GUID." }
$projGuid = $ProjectGuid.Trim('{', '}')

if (-not (Test-Path -LiteralPath $Manifest)) { throw "Manifest $Manifest gibt es nicht." }
$plan = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $plan.bilder) { throw 'Das Manifest nennt keine Bilder.' }
if (-not $Ziel) { $Ziel = Split-Path -Parent (Resolve-Path -LiteralPath $Manifest) }

# --------------------------------------------------------------- Datenbank

function Abfrage([string] $sql, [hashtable] $par = @{}) {
    $cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
    $cn.Open()
    try {
        $cmd = $cn.CreateCommand(); $cmd.CommandText = $sql
        foreach ($k in $par.Keys) { $null = $cmd.Parameters.AddWithValue("@$k", $par[$k]) }
        $rd = $cmd.ExecuteReader(); $aus = @()
        while ($rd.Read()) {
            $z = @{}
            for ($i = 0; $i -lt $rd.FieldCount; $i++) {
                $z[$rd.GetName($i)] = $(if ($rd[$i] -is [DBNull]) { $null } else { $rd[$i] })
            }
            $aus += [pscustomobject]$z
        }
        $rd.Close(); return $aus
    } finally { $cn.Close() }
}

$kopf = @(Abfrage 'SELECT UUID, LongDesc FROM PrProject WHERE UUID = @u' @{ u = [guid]$projGuid })
if ($kopf.Count -eq 0) { throw "Kein Projekt mit der GUID $projGuid in dieser Datenbank." }
Write-Host "Projekt: $($kopf[0].LongDesc)"

# Was schon da ist - fuer die Platzvergabe und damit nichts doppelt landet.
$vorhanden = @(Abfrage @'
SELECT UUID, GId, VariantRoot, Id, MediaType, XimMediaType, Category, SortNum, ShortDesc, SyncVersion
FROM PrMedia WHERE ProjectUUID = @u AND MediaType IN (14, 15) ORDER BY SortNum
'@ @{ u = [guid]$projGuid })

$naechsteSortNum = 1
if ($vorhanden.Count -gt 0) {
    $naechsteSortNum = (($vorhanden | ForEach-Object { [int]$_.SortNum } | Measure-Object -Maximum).Maximum) + 1
}

# ---- Das Muster des Projekts uebernehmen, nicht eines erfinden
#
# Ueber 932 Bildsaetze der Datenbank gemessen, gibt es zwei Schreibweisen, und
# beide kommen in Projekten vor, die einwandfrei drucken:
#
#   volles Muster (868 Saetze)  GId ist eine EIGENE Kennung, VariantRoot traegt
#                               eine dritte in geschweiften Klammern
#   einfaches Muster (64)       GId = UUID, VariantRoot leer
#
# VariantRoot zeigt dabei auf nichts: weder auf UUID noch auf das Projekt, und
# nur in 25 von 868 Faellen auf GId. Es ist eine Kennung je Satz, keine
# Beziehung - deshalb wird sie erzeugt und nicht abgeleitet.
#
# Welches der beiden richtig ist, entscheidet nicht dieses Skript, sondern das
# Projekt: ein neuer Satz soll neben seinen Geschwistern nicht auffallen. Steht
# das Projekt noch leer, gilt das volle Muster - es ist das ueberwiegende.
$vorlage = $vorhanden | Select-Object -Last 1
$vollesMuster = $true
$mediaType = 14
$naechsteId = -1

if ($vorlage) {
    $vollesMuster = ("$($vorlage.GId)" -ne "$($vorlage.UUID)") -or ("$($vorlage.VariantRoot)".Trim() -ne '')
    $mediaType = [int]$vorlage.MediaType
    # Fuehrt das Projekt echte Nummern, wird weitergezaehlt; sonst bleibt -1,
    # was 356 Saetze ebenso tun.
    $echte = @($vorhanden | Where-Object { [int]$_.Id -ne -1 } | ForEach-Object { [int]$_.Id })
    if ($echte.Count -gt 0) { $naechsteId = ($echte | Measure-Object -Maximum).Maximum + 1 }
}

# Die Fassung, die dieser Bestand schreibt. Nicht geraten: hat das Projekt
# schon Bilder, wird ihre uebernommen.
$syncVersion = ($vorhanden | Where-Object { $_.SyncVersion } | Select-Object -First 1).SyncVersion
if (-not $syncVersion) { $syncVersion = '1.7.2' }

Write-Host ("Bilder im Projekt: {0}   naechste SortNum: {1}   Muster: {2}   MediaType: {3}" -f `
    $vorhanden.Count, $naechsteSortNum, $(if ($vollesMuster) { 'voll' } else { 'einfach' }), $mediaType)

# ------------------------------------------------------------ Plan bauen

$auftrag = @(); $fehler = @(); $nr = 0
$belegt = @{}
foreach ($v in $vorhanden) { $belegt["$($v.XimMediaType)/$($v.Category)"] = $v }

foreach ($b in $plan.bilder) {
    $nr++
    $fkt = [int]$b.funktion
    if (-not $Funktionen.ContainsKey($fkt)) {
        $fehler += "Bild $nr : Funktion $fkt gibt es nicht. Moeglich sind $(($Funktionen.Keys | Sort-Object) -join ', ')."
        continue
    }
    $name = "$($b.name)".Trim()
    if ($name -eq '') { $fehler += "Bild $nr : ohne Namen - der wird im Fahrplan als Bildtitel gedruckt."; continue }

    $pfad = "$($b.datei)"
    if (-not [System.IO.Path]::IsPathRooted($pfad)) { $pfad = Join-Path $Ziel $pfad }
    if (-not (Test-Path -LiteralPath $pfad)) { $fehler += "Bild $nr '$name': Datei $pfad fehlt."; continue }

    $roh = [System.IO.File]::ReadAllBytes($pfad)
    $breite = 0; $hoehe = 0
    try {
        $im = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(, $roh)))
        $breite = $im.Width; $hoehe = $im.Height; $im.Dispose()
    } catch {
        $fehler += "Bild $nr '$name': $([System.IO.Path]::GetFileName($pfad)) ist kein lesbares Bild."
        continue
    }

    # Platz bestimmen: vorgegeben oder der naechste freie dieser Funktion.
    if ($null -ne $b.reihenfolge -and "$($b.reihenfolge)" -ne '') {
        $kat = [int]$b.reihenfolge
    } else {
        $kat = 1
        while ($belegt.ContainsKey("$fkt/$kat")) { $kat++ }
    }

    $alt = $belegt["$fkt/$kat"]
    if ($alt -and -not $Ersetzen) {
        $fehler += "Bild $nr '$name': $($Funktionen[$fkt]) Platz $kat ist mit '$($alt.ShortDesc)' belegt. " +
                   'Anderen Platz waehlen oder -Ersetzen angeben.'
        continue
    }

    $auftrag += [pscustomobject]@{
        Nr = $nr; Funktion = $fkt; FunktionName = $Funktionen[$fkt]; Kategorie = $kat
        Name = $name; Beschreibung = "$($b.beschreibung)".Trim(); Quelle = "$($b.bildquelle)".Trim()
        Pfad = $pfad; Bytes = $roh.Length; Breite = $breite; Hoehe = $hoehe
        Ersetzt = $(if ($alt) { $alt.UUID } else { $null })
        SortNum = $naechsteSortNum
        Id = $naechsteId
    }
    $naechsteSortNum++
    if ($naechsteId -ne -1) { $naechsteId++ }
    $belegt["$fkt/$kat"] = [pscustomobject]@{ UUID = $null; ShortDesc = $name }
}

$warnungen = @()
Write-Host ''
foreach ($a in $auftrag) {
    Write-Host ("  {0,-16} Platz {1,-3} {2,-24} {3,5} KB  {4}x{5}{6}" -f `
        $a.FunktionName, $a.Kategorie, $a.Name, [math]::Round($a.Bytes / 1KB), $a.Breite, $a.Hoehe,
        $(if ($a.Ersetzt) { '   ersetzt den vorhandenen Platz' } else { '' }))
    if ($a.Beschreibung -eq '') {
        $warnungen += "'$($a.Name)' hat keine Beschreibung - die Druckpruefung bemaengelt kurze Bildtexte."
    }
}

# Bekommt eine Funktion mehr Bilder, als der Fahrplan vorsieht, ist das meist
# ein Zahlendreher in der Reihenfolge - gemeldet, nicht verhindert.
foreach ($fkt in ($Funktionen.Keys | Sort-Object)) {
    if ($Erwartet[$fkt] -le 0) { continue }
    $danach = @($vorhanden | Where-Object { [int]$_.XimMediaType -eq $fkt }).Count +
              @($auftrag | Where-Object { $_.Funktion -eq $fkt -and -not $_.Ersetzt }).Count
    if ($danach -gt $Erwartet[$fkt]) {
        $warnungen += "$($Funktionen[$fkt]): danach $danach Bilder, der Fahrplan sieht $($Erwartet[$fkt]) vor."
    }
}

foreach ($w in $warnungen) { Write-Warning $w }
foreach ($f in $fehler) { Write-Warning $f }

# Das Ergebnis als JSON - der Server liest es mit file.read und meldet daraus,
# was angekommen ist. Wird in JEDEM Fall geschrieben, auch beim Abbruch weiter
# unten: ein Auftrag ohne Ergebnisdatei laesst sich nicht auseinanderhalten von
# einem, der den Rechner nie erreicht hat.
function SchreibeErgebnis([string] $zustand, [int] $geschrieben, [array] $stand) {
    $daten = [ordered]@{
        zustand = $zustand
        projekt = $kopf[0].LongDesc
        geschrieben = $geschrieben
        geplant = @($auftrag | ForEach-Object {
            [ordered]@{ funktion = $_.Funktion; funktion_name = $_.FunktionName; reihenfolge = $_.Kategorie
                        name = $_.Name; beschreibung = $_.Beschreibung; bytes = $_.Bytes
                        breite = $_.Breite; hoehe = $_.Hoehe; ersetzt = [bool]$_.Ersetzt } })
        abgelehnt = @($fehler)
        warnungen = @($warnungen)
        stand = @($stand)
    }
    $pfad = Join-Path $Ziel 'bilder-import.json'
    $json = $daten | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($pfad, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Ergebnis: $pfad"
}

if ($auftrag.Count -eq 0) {
    SchreibeErgebnis 'nichts_zu_tun' 0 @()
    throw 'Kein Bild uebrig, das angelegt werden koennte - Gruende in bilder-import.json.'
}

if (-not $Schreiben) {
    SchreibeErgebnis 'vorschau' 0 @()
    Write-Host "`nVORSCHAU - nichts geschrieben. $($auftrag.Count) Bild(er) waeren angelegt worden."
    return
}

# Eine laufende Instanz haelt den Projektstand im Speicher und schreibt ihn
# beim naechsten Speichern zurueck - die neuen Zeilen waeren dann wieder weg.
$laeuft = Get-Process Energie -ErrorAction SilentlyContinue
if ($laeuft) {
    SchreibeErgebnis 'energie_laeuft' 0 @()
    throw "Energie.exe laeuft (PID $($laeuft.Id -join ', ')) und macht den Import beim naechsten Speichern rueckgaengig - erst schliessen."
}

# ------------------------------------------------------------- Schreiben
#
# Alle Spalten ausdruecklich, keine Vorgabewerte der Tabelle. Die Werte sind an
# Saetzen abgelesen, die die Software selbst geschrieben hat, nicht geraten:
#   XIMUUID             die Projekt-GUID, nicht eine eigene
#   SeqNum = -1         in allen 932 gemessenen Saetzen
#   SyncType 2, SyncCreate/SyncEdit/MId auf der Nullkennung aaaa...,
#   SyncMeta fest, SyncRowVersion je Satz neu
#   MediaLink           der Herkunftspfad, rein informativ
#   GId/VariantRoot/Id/MediaType  kommen aus dem Muster des Projekts (siehe oben)

$sqlNeu = @'
INSERT INTO PrMedia (
    UUID, ProjectUUID, XIMUUID, Id, SeqNum, SortNum,
    ShortDesc, LongDesc, InfoDesc, BodyText, BodyTextType,
    MediaName, MediaData, MediaLink, Media, MediaSize,
    MediaType, MediaURLType, XimMediaType, MediaContainerType,
    MediaBlobType, MediaVariantType, MediaCopyright, MediaVersion,
    EditModeType, StateType, VariantType, GeneratorType, VariantRoot,
    Category, StampEdit, StampCreate, StampSync, SyncStamp,
    SyncType, SyncCreate, SyncEdit, SyncVersion, SyncMeta, SyncRowVersion, GId, MId
) VALUES (
    @uuid, @proj, @proj, @id, -1, @sortnum,
    @name, @name, @info, '', 0,
    @name, '', @link, @bytes, @groesse,
    @mediatype, 0, @fkt, 0,
    0, 0, @quelle, '',
    0, 0, 0, 0, @variantroot,
    @kat, @jetzt, @jetzt, @jetzt, @jetzt,
    2, @null, @null, @version, @meta, @rowver, @gid, @null
)
'@
$sqlErsetzen = @'
UPDATE PrMedia SET
    ShortDesc = @name, LongDesc = @name, MediaName = @name, InfoDesc = @info,
    MediaCopyright = @quelle, MediaLink = @link, Media = @bytes, MediaSize = @groesse,
    XimMediaType = @fkt, Category = @kat, StampEdit = @jetzt, SyncRowVersion = @rowver
WHERE UUID = @uuid
'@

$nullKennung = [guid]'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$meta = '{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}'
$geschrieben = 0

$cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$cn.Open()
$tx = $cn.BeginTransaction()
try {
    foreach ($a in $auftrag) {
        $roh = [System.IO.File]::ReadAllBytes($a.Pfad)
        $cmd = $cn.CreateCommand(); $cmd.Transaction = $tx
        $cmd.CommandText = $(if ($a.Ersetzt) { $sqlErsetzen } else { $sqlNeu })

        $uuid = $(if ($a.Ersetzt) { [guid]$a.Ersetzt } else { [guid]::NewGuid() })
        $null = $cmd.Parameters.AddWithValue('@uuid', $uuid)
        $null = $cmd.Parameters.AddWithValue('@proj', [guid]$projGuid)
        $null = $cmd.Parameters.AddWithValue('@sortnum', [int]$a.SortNum)
        $null = $cmd.Parameters.AddWithValue('@id', [int]$a.Id)
        $null = $cmd.Parameters.AddWithValue('@mediatype', [int]$mediaType)
        $null = $cmd.Parameters.AddWithValue('@gid', $(if ($vollesMuster) { [guid]::NewGuid() } else { $uuid }))
        $null = $cmd.Parameters.AddWithValue('@variantroot', $(if ($vollesMuster) { '{' + [guid]::NewGuid().ToString() + '}' } else { '' }))
        $null = $cmd.Parameters.AddWithValue('@name', $a.Name)
        $null = $cmd.Parameters.AddWithValue('@info', $a.Beschreibung)
        $null = $cmd.Parameters.AddWithValue('@quelle', $a.Quelle)
        $null = $cmd.Parameters.AddWithValue('@link', $a.Pfad)
        $null = $cmd.Parameters.AddWithValue('@fkt', [int]$a.Funktion)
        $null = $cmd.Parameters.AddWithValue('@kat', [string]$a.Kategorie)
        $null = $cmd.Parameters.AddWithValue('@groesse', [int]$roh.Length)
        $null = $cmd.Parameters.AddWithValue('@jetzt', (Get-Date))
        $null = $cmd.Parameters.AddWithValue('@version', $syncVersion)
        $null = $cmd.Parameters.AddWithValue('@meta', $meta)
        $null = $cmd.Parameters.AddWithValue('@rowver', [guid]::NewGuid())
        $null = $cmd.Parameters.AddWithValue('@null', $nullKennung)
        $par = $cmd.Parameters.Add('@bytes', [System.Data.SqlDbType]::VarBinary, -1)
        $par.Value = $roh

        $null = $cmd.ExecuteNonQuery()
        $geschrieben++
        Write-Host ("  geschrieben: {0,-16} Platz {1,-3} {2}" -f $a.FunktionName, $a.Kategorie, $a.Name)
    }
    $tx.Commit()
} catch {
    $tx.Rollback()
    SchreibeErgebnis 'fehlgeschlagen' 0 @()
    throw
} finally { $cn.Close() }

# Gegenprobe aus der Datenbank, nicht aus dem Speicher - und ueber die
# Bildgroesse, nicht ueber die blosse Anwesenheit einer Zeile.
$probe = @(Abfrage @'
SELECT XimMediaType, Category, ShortDesc, InfoDesc, DATALENGTH(Media) AS Bytes
FROM PrMedia WHERE ProjectUUID = @u AND MediaType IN (14, 15) AND XimMediaType IN (1, 10, 11, 12, 13, 17, 18)
ORDER BY XimMediaType, Category
'@ @{ u = [guid]$projGuid })

$stand = @($probe | ForEach-Object {
    [ordered]@{
        funktion = [int]$_.XimMediaType
        funktion_name = $(if ($Funktionen.ContainsKey([int]$_.XimMediaType)) { $Funktionen[[int]$_.XimMediaType] } else { "Funktion $($_.XimMediaType)" })
        reihenfolge = "$($_.Category)"
        name = "$($_.ShortDesc)"
        beschreibung = "$($_.InfoDesc)"
        bytes = [int]$_.Bytes
    } })

SchreibeErgebnis 'geschrieben' $geschrieben $stand

Write-Host "`nGeschrieben: $geschrieben Bild(er)."
Write-Host 'Die Bilder stehen jetzt in der Bilderverwaltung. Damit sie im Fahrplan'
Write-Host 'erscheinen, muss der Berater das Projekt und die iSFP-Maske einmal oeffnen'
Write-Host 'und speichern - erst dann uebernimmt die Maske sie in ihre Bildliste.'
