# Export-Katalog.ps1 -- der vollstaendige Datenstand fuer die FS-App.
#
# Schreibt database/data/hottgenroth/ nach dem Muster, das der Altbauatlas
# vormacht: NDJSON je Bestand, bilder.json mit den Metadaten, images/ mit den
# Dateien. Was hier herauskommt, wird versioniert und von
# `php artisan hottgenroth:import` eingelesen.
#
#   aufbauten.ndjson         Bestand + Ziel; Waende/Daecher/Decken mit Schichten,
#                            Fenster und Tueren mit Uw, g und Rahmenanteil
#   typologie-uwerte.ndjson  4.324 Vergleichswerte
#   waermebruecken.ndjson    467 Details aus DIN 4108 Bbl 2 und dem Katalog
#   bilder.json              Metadaten, Schluessel ist der sha256 der Quelldatei
#   images/<zwei>/<sha256>.<ext>
#
# Der Schnitt ist die Entscheidung vom 11.09.2026: deutscher Bestand, ohne
# Oesterreich, ohne Ausland, ohne Produktkataloge. Begruendung in
# hottgenroth-agent/docs/bauteile-in-die-fs-liste.md.
#
# Nur lesend: jede Abfrage laeuft in einer Transaktion, die zurueckgerollt wird.

[CmdletBinding()]
param(
    [string]$Instanz = "(localdb)\HSETU",
    [Parameter(Mandatory = $true)][string]$Ziel
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
Add-Type -AssemblyName System.Drawing
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

$bilderVerzeichnis = Join-Path $Ziel 'images'
foreach ($v in @($Ziel, $bilderVerzeichnis)) {
    if (-not (Test-Path $v)) { New-Item -ItemType Directory -Path $v | Out-Null }
}

# ---------------------------------------------------------------- Datenbank

function Abfragen([string]$Sql) {
    $con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=HsetuAppTimData;Integrated Security=true;TrustServerCertificate=true"
    $con.Open()
    $tx = $con.BeginTransaction()
    try {
        $c = $con.CreateCommand(); $c.Transaction = $tx; $c.CommandTimeout = 900; $c.CommandText = $Sql
        $tab = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)
        return , $tab
    } finally { try { $tx.Rollback() } catch {}; $con.Close() }
}

# Die Software traegt -987654321.99 ein, wo nichts angegeben ist. Und bei
# Typologiebauteilen steht zusaetzlich 0 in Dicke und U-Wert. Beides ist kein
# Messwert, sondern eine Luecke.
function Wert($w) {
    if ($null -eq $w -or $w -is [System.DBNull]) { return $null }
    $d = [double]$w
    if ($d -le -1000000 -or $d -le 0) { return $null }
    return [math]::Round($d, 4)
}

function Text($w) {
    if ($null -eq $w -or $w -is [System.DBNull]) { return '' }
    return ([string]$w -replace '\s+', ' ').Trim()
}

# Wie Text(), aber eine leere Zeichenkette kommt als null heraus. Fuer Felder,
# die im Ziel nullable sind: '' hiesse dort "es gibt einen Pfad, und er ist
# leer", und genau das ist nicht gemeint.
function TextOderNull($w) {
    $t = Text $w
    if ($t -eq '') { return $null }
    return $t
}

<#
  Eine Aufzaehlung, kein Messwert.

  Wert() darf hier nicht greifen: es rundet auf vier Stellen und macht damit aus
  einer Kennzahl eine Fliesskommazahl. Die 0 faellt trotzdem heraus, aber aus
  einem anderen Grund als bei Wert() -- TMaterialGroupEnum 0 heisst "ohne
  Gruppe" und traegt in der Software auch keinen Klartext.

  Gemessen am 19.09.2026 ueber die 3.365 Schichten, die dieser Export
  ausliefert: MaterialGroupType ist in 3.365 von 3.365 gesetzt und nirgends 0.
#>
function Gruppe($w) {
    if ($null -eq $w -or $w -is [System.DBNull]) { return $null }
    $i = [int]$w
    if ($i -le 0) { return $null }
    return $i
}

# ------------------------------------------------------------------ Bilder

$bildIndex = @{}     # sha256 -> Metadaten
$bildJeDim = @{}     # DimensionUId -> Liste aus @{sha; typ; pos}

# CatalogMediaType -> Rolle. 0 fuehren die Typologien (ein Foto des
# Typologie-Gebaeudes, nicht des Bauteils), 2/9/36 die Waermebruecken.
$rollen = @{ 0 = 'gebaeudefoto'; 2 = 'vorschau'; 9 = 'zeichnung'; 36 = 'temperaturfeld' }

function Endung([byte[]]$b) {
    $kopf = ($b[0..1] | ForEach-Object { $_.ToString('X2') }) -join ''
    switch ($kopf) {
        'FFD8'  { 'jpg' }
        '4749'  { 'gif' }
        '424D'  { 'bmp' }
        '8950'  { 'png' }
        default { 'bin' }
    }
}

<#
  Ein Bild ablegen und seinen sha256 zurueckgeben.

  Entdoppelt wird ueber den sha256 der QUELLE, nicht der abgelegten Datei --
  sonst wandelte man dasselbe BMP hundertmal um. Bei den Typologien stehen
  hinter 4.772 Verweisen nur 230 verschiedene Bilder; dasselbe Gebaeudefoto
  bedient jedes Bauteil seines Typs.

  BMP wird nach PNG gewandelt: unkomprimiert sind es 30 kB je 163x177, als PNG
  ein Bruchteil. Verlustfrei, nur kleiner.
#>
function BildAblegen([byte[]]$roh, [string]$typ) {
    $sha = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash($roh)).Replace('-', '').ToLower()

    if ($bildIndex.ContainsKey($sha)) { return $sha }

    $endung = Endung $roh
    $inhalt = $roh
    if ($endung -eq 'bmp') {
        $ein = New-Object System.IO.MemoryStream(, $roh)
        $bild = [System.Drawing.Image]::FromStream($ein)
        $aus = New-Object System.IO.MemoryStream
        $bild.Save($aus, [System.Drawing.Imaging.ImageFormat]::Png)
        $inhalt = $aus.ToArray()
        $breite = $bild.Width; $hoehe = $bild.Height
        $aus.Dispose(); $bild.Dispose(); $ein.Dispose()
        $endung = 'png'
    } else {
        $ein = New-Object System.IO.MemoryStream(, $roh)
        $bild = [System.Drawing.Image]::FromStream($ein)
        $breite = $bild.Width; $hoehe = $bild.Height
        $bild.Dispose(); $ein.Dispose()
    }

    $unter = Join-Path $bilderVerzeichnis $sha.Substring(0, 2)
    if (-not (Test-Path $unter)) { New-Item -ItemType Directory -Path $unter | Out-Null }
    $relativ = "images/$($sha.Substring(0,2))/$sha.$endung"
    [System.IO.File]::WriteAllBytes((Join-Path $Ziel $relativ), $inhalt)

    $bildIndex[$sha] = [ordered]@{
        sha256    = $sha
        typ       = $typ
        datei     = $relativ
        dateiname = "$sha.$endung"
        mime      = switch ($endung) { 'jpg' { 'image/jpeg' } 'gif' { 'image/gif' } 'png' { 'image/png' } default { 'application/octet-stream' } }
        bytes     = $inhalt.Length
        breite    = $breite
        hoehe     = $hoehe
    }
    return $sha
}

<#
  Alle Medien der uebergebenen Dimensionen einsammeln.

  $Cte ist der WITH-Block, falls die Auswahl einen braucht -- er muss vor dem
  SELECT stehen, nicht im IN(), sonst kennt SQL Server die Tabelle dort nicht.
  Wer eine fertige Liste von GUIDs uebergibt, laesst ihn leer.
#>
function BilderLaden([string]$WoDimension, [string]$Cte = '') {
    $sql = @"
$Cte
SELECT CONVERT(nvarchar(36), r.UId) AS DimUId, m.CatalogMediaType AS Rolle, m.Media
FROM TcMediaReference r
JOIN TcMedia m ON m.UId = r.MediaUId AND m.Media IS NOT NULL
WHERE r.UId IN ($WoDimension)
ORDER BY r.UId, m.CatalogMediaType
"@
    $tab = Abfragen $sql
    $pos = @{}
    foreach ($r in $tab.Rows) {
        $dim = [string]$r['DimUId']
        # Aufbauten und Vergleichsband ueberschneiden sich in 143 Bauteilen, und
        # beide rufen diese Funktion. Ohne den Riegel stuenden deren Bilder
        # zweimal in der Liste.
        if ($bildJeDim.ContainsKey($dim) -and -not $pos.ContainsKey($dim)) { continue }
        $typ = $rollen[[int]$r['Rolle']]
        if (-not $typ) { $typ = 'sonstiges' }
        $sha = BildAblegen ([byte[]]$r['Media']) $typ
        if (-not $pos.ContainsKey($dim)) { $pos[$dim] = 0 }
        $pos[$dim]++
        if (-not $bildJeDim.ContainsKey($dim)) { $bildJeDim[$dim] = @() }
        $bildJeDim[$dim] += , [ordered]@{ sha256 = $sha; typ = $typ; pos = $pos[$dim] }
    }
    return $tab.Rows.Count
}

# ------------------------------------------------------- Gemeinsame Bausteine

# Der Katalogbaum: Elternordner und eigener Ordner je Bauteil.
$platz = @"
WITH pfad AS (
    SELECT cc.UId, cc.CatalogUId, COALESCE(p.LongDesc, N'') AS Eltern, cc.LongDesc AS Kind
    FROM TcCatalogContent cc LEFT JOIN TcCatalogContent p ON p.UId = cc.ReferenceUId
),
platz AS (
    SELECT cs.BasisUId, MIN(pf.Eltern) AS Eltern, MIN(pf.Kind) AS Kind,
           MIN(COALESCE(k.LongDesc, N'')) AS Katalog
    FROM TcCatalogContents cs
    JOIN pfad pf ON pf.UId = cs.CatalogContentUId
    LEFT JOIN TcCatalog k ON k.UId = pf.CatalogUId
    GROUP BY cs.BasisUId
)
"@

# Oesterreich faellt heraus -- entschieden am 11.09.2026. Es kostet keinen
# einzigen Aufbau: alle 715 abbildbaren oesterreichischen Bauteile sind reine
# U-Wert-Zeilen.
$ohneOesterreich = @"
  AND pl.Kind NOT LIKE N'%sterreich%' AND pl.Kind NOT LIKE N'%Burgenland%'
  AND pl.Kind NOT LIKE N'%rnten%'      AND pl.Kind NOT LIKE N'%Salzburg%'
  AND pl.Kind NOT LIKE N'%Steiermark%' AND pl.Kind NOT LIKE N'%Tirol%'
  AND pl.Kind NOT LIKE N'%Vorarlberg%' AND pl.Kind NOT LIKE N'%Wien%'
"@

# Die Lagen, fuer die die FS-Liste eine Bauteilart kennt.
#
# Fenster (3/2) und Tueren (2/2) sind am 13.09.2026 dazugekommen. Sie tragen
# KEINE Schichten -- ein Fenster rechnet aus Uw, g und Rahmenanteil, nicht aus
# Lambda und Dicke. Deshalb faellt unten auch die EXISTS-Bedingung auf die
# Schichttabelle: sie hat bisher jeden schichtlosen Eintrag ausgeschlossen und
# damit 264 der 265 Katalogeintraege, die in echten Projekten wirklich benutzt
# werden -- darunter 70 Aussenwaende in einer laengst erlaubten Lage.
$fsLagen = "((b.GroupType=1 AND b.UsageType=2) OR (b.GroupType=5 AND b.UsageType=2)
            OR (b.GroupType=4 AND b.UsageType IN (4,7,8))
            OR (b.GroupType=3 AND b.UsageType=2 AND b.SubType=0)
            OR (b.GroupType=2 AND b.UsageType=2))"

# Zwei PowerShell-Fallen auf einmal, beide schon zugeschnappt:
#
#  1. @($null) ist ein Array MIT einem Null-Element, nicht ein leeres. Ohne den
#     Filter stuende in der Ausgabe [null] statt [].
#  2. ConvertTo-Json klappt eine EINELEMENTIGE Liste zu einem Objekt zusammen:
#     aus [{...}] wird {...}. Beim ersten Lauf sind so 387 Bildverweise und die
#     Schichten von 9 Bauteilen verschwunden — lautlos, weil die Feldwerte des
#     Objekts auf der Leseseite wie Listenelemente aussehen.
#
# Das `, ` vor dem Rueckgabewert ist die Abhilfe fuer die zweite: Der
# Komma-Operator verpackt das Array in ein weiteres, das die Pipeline dann
# wieder auspackt — uebrig bleibt das Array, auch mit nur einem Element.
function Liste($x) {
    if ($null -eq $x) { return , @() }
    return , @([object[]]@($x | Where-Object { $null -ne $_ }))
}

function NdJson($Zeilen, $Datei) {
    $sw = New-Object System.IO.StreamWriter((Join-Path $Ziel $Datei), $false, (New-Object System.Text.UTF8Encoding $false))
    try { foreach ($z in $Zeilen) { $sw.WriteLine(($z | ConvertTo-Json -Depth 6 -Compress)) } } finally { $sw.Close() }
    Write-Output ("{0,-26} {1,6} Zeilen" -f $Datei, @($Zeilen).Count)
}

Write-Output "Lese aus $Instanz ..."
Write-Output ''
# ===========================================================================
# 1. Aufbauten -- Bestand und Ziel
# ===========================================================================
#
# Bewusst ROH: Bauteilart, Baualtersband und ergaenzte Titel entstehen erst im
# Importkommando. Die abgeleiteten Werte sind die einzigen, die falsch sein
# koennen -- sie gehoeren an eine Stelle, die sich mit PHP-Tests pruefen laesst,
# nicht in ein Exportskript, das nur auf diesem Arbeitsplatz laeuft.

$sqlAufbauten = @"
$platz
SELECT CONVERT(nvarchar(36), d.UId) AS ref,
       CASE WHEN pl.Katalog = N'Typologien' THEN 'bestand' ELSE 'ziel' END AS rolle,
       b.GroupType AS gruppe_nr, b.UsageType AS lage_nr, b.SubType AS unterart,
       b.LongDesc AS bezeichnung, d.InfoDesc AS beschreibung,
       d.UValue AS u_wert, d.RValue AS r_wert, d.Thickness AS dicke,
       d.GValue AS g_wert, d.FractionOfFrame AS rahmenanteil,
       pl.Katalog AS katalog, pl.Eltern AS ordner_eltern, pl.Kind AS ordner,
       (SELECT COUNT(DISTINCT s.UId) FROM TcBuildingElementDimensionLayerSection s
        WHERE s.DimensionUId = d.UId) AS gefache
FROM TcBuildingElementDimension d
JOIN TcBasis b ON b.UId = d.BasisUId
JOIN platz pl ON pl.BasisUId = d.BasisUId
WHERE $fsLagen
  AND (
        (pl.Katalog = N'Typologien' AND pl.Kind LIKE N'%Schichtaufbauten%' $ohneOesterreich)
     OR  pl.Katalog IN (N'BauteileNeubau', N'BauteileHersteller', N'BauteilePassivhaus')
      )
ORDER BY rolle, b.GroupType, b.UsageType, d.UValue
"@

$aufbauten = Abfragen $sqlAufbauten
$refs = @($aufbauten.Rows | ForEach-Object { "'" + $_['ref'] + "'" })
Write-Output ("Aufbauten: {0} ({1} Bestand, {2} Ziel)" -f $aufbauten.Rows.Count,
    @($aufbauten.Rows | Where-Object { $_['rolle'] -eq 'bestand' }).Count,
    @($aufbauten.Rows | Where-Object { $_['rolle'] -eq 'ziel' }).Count)

# Die fuenf Felder hinter rohdichte kamen am 19.09.2026 dazu.
#
# Ohne sie setzt der Arbeitsplatz beim Zurueckschreiben eines Bauteils die
# Vorgaben 1000 kg/m3, cp = 1,0, mu 10/35 und Materialgruppe 8 ("Sonstige") --
# und die stehen nicht nur da, sie rechnen mit: Waermespeicherfaehigkeit,
# Tauwasser und sommerlicher Waermeschutz haengen an cp und mu.
#
# MaterialGroupType ist die Farbe der Schicht in der Zeichnung und steht zu
# 100 % an jeder Zeile (3.365 von 3.365, keine davon 0).
#
# ShortDesc ist der Katalogpfad ("1.1.2", "4.1.2.6"), belegt in 3.194 von 3.365
# Zeilen. Er ist der Grund, warum die Gruppe mitreisen muss statt geraten zu
# werden: "Dachziegelsteine aus Ton nach DIN 12524" steht 50-mal mit Pfad 4.6.1
# in Gruppe 4 und 58-mal mit Pfad 8.12.1 in Gruppe 8. Ueber den Namen ist das
# nicht entscheidbar, ueber den Pfad schon. Regel BK-12.
#
# Bei den Diffusionswiderstaenden sind es Lower/Upper, nicht das nackte
# DiffusionResistanceCoefficient: dieses Feld ist im ganzen Katalog in 0 von
# 9.296 Zeilen gefuellt.
$sqlSchichten = @"
SELECT CONVERT(nvarchar(36), l.DimensionUId) AS ref,
       COALESCE(sek.SectionNum, 1) AS gefach, sek.SectionShareValve AS anteil,
       l.SortNum AS nr, l.LongDesc AS material,
       l.Thickness AS dicke, l.ThermalConductivity AS lambda, l.Density AS rohdichte,
       l.HeatCapacity AS kapazitaet,
       l.LowerDiffusionResistanceCoefficient AS mu_unten,
       l.UpperDiffusionResistanceCoefficient AS mu_oben,
       l.MaterialGroupType AS material_gruppe,
       l.ShortDesc AS katalogpfad
FROM TcBuildingElementDimensionLayer l
LEFT JOIN TcBuildingElementDimensionLayerSection sek ON sek.UId = l.LayerSectionUId
WHERE l.DimensionUId IN ($($refs -join ','))
ORDER BY l.DimensionUId, COALESCE(sek.SectionNum, 1), l.SortNum
"@
$schichten = Abfragen $sqlSchichten
$schichtJeRef = @{}
foreach ($s in $schichten.Rows) {
    $r = [string]$s['ref']
    if (-not $schichtJeRef.ContainsKey($r)) { $schichtJeRef[$r] = @() }
    $schichtJeRef[$r] += , [ordered]@{
        gefach   = [int]$s['gefach']
        anteil   = Wert $s['anteil']
        nr       = [int]$s['nr']
        material = Text $s['material']
        dicke    = Wert $s['dicke']
        lambda   = Wert $s['lambda']
        rohdichte = Wert $s['rohdichte']
        # cp in kJ/(kgK), gemessen 0,01 bis 2,2. mu ist dimensionslos und reicht
        # von 0,01 bis 1.000.000 (Dampfsperren) -- die Zielspalte muss sieben
        # Vorkommastellen vertragen.
        kapazitaet = Wert $s['kapazitaet']
        mu_unten   = Wert $s['mu_unten']
        mu_oben    = Wert $s['mu_oben']
        material_gruppe = Gruppe $s['material_gruppe']
        katalogpfad     = TextOderNull $s['katalogpfad']
    }
}
# Die Deckung der fuenf neuen Felder gehoert ins Protokoll: faellt sie beim
# naechsten Softwarestand ein, sieht man es hier und nicht erst daran, dass ein
# zurueckgeschriebenes Bauteil wieder mit den Vorgaben rechnet.
$mitGruppe = @($schichten.Rows | Where-Object { $_['material_gruppe'] -isnot [System.DBNull] -and [int]$_['material_gruppe'] -gt 0 }).Count
$mitPfad = @($schichten.Rows | Where-Object { (Text $_['katalogpfad']) -ne '' }).Count
Write-Output ("  Schichten: {0} ({1} mit Materialgruppe, {2} mit Katalogpfad)" -f `
    $schichten.Rows.Count, $mitGruppe, $mitPfad)

$anzahlMedien = BilderLaden ($refs -join ',')
Write-Output ("  Bildverweise: {0}" -f $anzahlMedien)

$zeilenAufbauten = foreach ($r in $aufbauten.Rows) {
    $ref = [string]$r['ref']
    [ordered]@{
        ref          = $ref
        rolle        = [string]$r['rolle']
        gruppe_nr    = [int]$r['gruppe_nr']
        lage_nr      = [int]$r['lage_nr']
        unterart     = [int]$r['unterart']
        bezeichnung  = Text $r['bezeichnung']
        beschreibung = Text $r['beschreibung']
        u_wert       = Wert $r['u_wert']
        r_wert       = Wert $r['r_wert']
        dicke        = Wert $r['dicke']
        g_wert       = Wert $r['g_wert']
        rahmenanteil = Wert $r['rahmenanteil']
        katalog      = Text $r['katalog']
        ordner       = (Text $r['ordner_eltern']) + '|' + (Text $r['ordner'])
        gefache      = [int]$r['gefache']
        schichten    = Liste $schichtJeRef[$ref]
        bilder       = Liste $bildJeDim[$ref]
    }
}
NdJson $zeilenAufbauten 'aufbauten.ndjson'
Write-Output ''
# ===========================================================================
# 2. Vergleichsband -- typische U-Werte der deutschen Bestandstypologie
# ===========================================================================
#
# Bewusst OHNE Einschraenkung auf die fuenf FS-Bauteilarten: Das Band soll
# gerade die Lagen beantworten, die die Bauteilliste nicht halten kann --
# Fenster, Innenwand, Kellerwand, Wand gegen unbeheizt.

$wahlBand = @"
    FROM TcBuildingElementDimension d
    JOIN TcBasis b ON b.UId = d.BasisUId
    JOIN platz pl ON pl.BasisUId = d.BasisUId
    -- Nur N'Typologien': Der Teilkatalog BauteileTypologie traegt Namen, die
    -- wie Dubletten der grossen Sammlungen aussehen ('EnEV 2015 - Typologie'
    -- neben 'Deutschland -EnEV 2015-'), ist aber ein anderer Schnitt: ALLE 516
    -- Zeilen fuehren keinen Gebaeudetyp und passen damit nicht in das Raster des
    -- Vergleichsbands (Lage x Baualter x Gebaeudetyp x Region). 112 tragen auch
    -- keine Jahresangabe, und wo sich vergleichen liess, deckten sich rund 52
    -- Prozent der Werte mit der grossen Sammlung. Entschieden am 12.09.2026.
    WHERE pl.Katalog = N'Typologien' $ohneOesterreich
"@

$band = Abfragen @"
$platz
SELECT CONVERT(nvarchar(36), d.UId) AS ref,
       b.GroupType AS gruppe_nr, b.UsageType AS lage_nr, b.SubType AS unterart,
       b.LongDesc AS bezeichnung, d.UValue AS u_wert,
       -- g-Wert und Rahmenanteil gehoeren AUCH ins Vergleichsband, nicht nur
       -- zu den Aufbauten. Am 20.09.2026 hing genau daran ein Projekt: die
       -- Fenster liessen sich nicht zuweisen, weil add_components ohne g-Wert
       -- abweist (fenster_ohne_g_wert) -- und alle 698 Fenster-Typologien kamen
       -- ohne an, obwohl HsetuAppTimData fuer jede einzelne einen fuehrt.
       -- Ein erfundener g-Wert laesst die solaren Gewinne still auf null fallen;
       -- deshalb ist die Abweisung richtig und die Luecke lag hier.
       d.GValue AS g_wert, d.FractionOfFrame AS rahmenanteil,
       pl.Katalog AS katalog, pl.Eltern AS ordner_eltern, pl.Kind AS ordner,
       CASE WHEN EXISTS (SELECT 1 FROM TcBuildingElementDimensionLayer l
                         WHERE l.DimensionUId = d.UId) THEN 1 ELSE 0 END AS hat_aufbau
$wahlBand
ORDER BY b.GroupType, b.UsageType, pl.Eltern, pl.Kind
"@
Write-Output ("Vergleichsband: {0}" -f $band.Rows.Count)

$anzahlMedien = BilderLaden "SELECT d.UId $wahlBand" $platz
Write-Output ("  Bildverweise: {0}" -f $anzahlMedien)

$zeilenBand = foreach ($r in $band.Rows) {
    $ref = [string]$r['ref']
    # Hoechstens ein Bild je Zeile -- das Foto des Typologie-Gebaeudes.
    # Hier NICHT ueber Liste(): die gibt komma-verpackt zurueck, damit
    # ConvertTo-Json eine einelementige Liste nicht zu einem Objekt zusammen-
    # klappt. Ein zusaetzliches @() drumherum ergaebe ein Array IM Array, und
    # $bild[0] waere dann das innere Array statt des ersten Bildes.
    $bildSha = $null
    $eintraege = $bildJeDim[$ref]
    if ($null -ne $eintraege) {
        foreach ($e in $eintraege) { if ($null -ne $e) { $bildSha = $e.sha256; break } }
    }
    [ordered]@{
        ref         = $ref
        gruppe_nr   = [int]$r['gruppe_nr']
        lage_nr     = [int]$r['lage_nr']
        bezeichnung = Text $r['bezeichnung']
        u_wert      = Wert $r['u_wert']
        g_wert       = Wert $r['g_wert']
        rahmenanteil = Wert $r['rahmenanteil']
        katalog     = Text $r['katalog']
        ordner      = (Text $r['ordner_eltern']) + '|' + (Text $r['ordner'])
        hat_aufbau  = [int]$r['hat_aufbau']
        bild        = $bildSha
    }
}
NdJson $zeilenBand 'typologie-uwerte.ndjson'
Write-Output ''

# ===========================================================================
# 3. Waermebruecken -- DIN 4108 Beiblatt 2 und der Hottgenroth-Katalog
# ===========================================================================
#
# Eigener Bestand, eigene Tabelle: Psi steht in W/(mK) und ist keine Groesse,
# die neben einem U-Wert in derselben Spalte stehen darf.

$wahlWb = @"
    FROM TcBuildingElementDimension d
    JOIN TcBasis b ON b.UId = d.BasisUId
    JOIN platz pl ON pl.BasisUId = d.BasisUId
    -- Der zweite Katalog heisst "Waermebrueckenkatalog" mit Umlauten. Hier
    -- steht er als LIKE-Muster mit _ statt ae/ue: PowerShell 5.1 liest eine
    -- .ps1 ohne BOM als ANSI, ein Umlaut im Quelltext kaeme falsch an der
    -- Datenbank an und die Abfrage faende still nichts.
    WHERE (pl.Katalog = N'DIN 4108 Bbl 2: 2019-06' OR pl.Katalog LIKE N'W_rmebr_ckenkatalog')
"@

$wb = Abfragen @"
$platz
SELECT CONVERT(nvarchar(36), d.UId) AS ref,
       b.ShortDesc AS detailnummer, b.LongDesc AS gruppe,
       b.ConstructionInfo AS konstruktion,
       d.PsiValue AS psi_wert,
       pl.Katalog AS quelle, pl.Eltern AS ordner_eltern, pl.Kind AS ordner
$wahlWb
ORDER BY pl.Katalog, b.LongDesc, b.ShortDesc
"@
# Psi darf negativ sein -- Wert() liest das als Luecke, hier also von Hand.
$mitPsi = @($wb.Rows | Where-Object {
    $_['psi_wert'] -isnot [System.DBNull] -and [double]$_['psi_wert'] -gt -1000000
}).Count
Write-Output ("Waermebruecken: {0} ({1} mit Psi-Wert)" -f $wb.Rows.Count, $mitPsi)

$anzahlMedien = BilderLaden "SELECT d.UId $wahlWb" $platz
Write-Output ("  Bildverweise: {0}" -f $anzahlMedien)

$zeilenWb = foreach ($r in $wb.Rows) {
    $ref = [string]$r['ref']
    # Psi darf negativ sein -- Wert() wuerde das als Luecke lesen.
    $psi = $null
    if ($r['psi_wert'] -isnot [System.DBNull]) {
        $d = [double]$r['psi_wert']
        if ($d -gt -1000000) { $psi = [math]::Round($d, 3) }
    }
    [ordered]@{
        ref          = $ref
        detailnummer = Text $r['detailnummer']
        gruppe       = Text $r['gruppe']
        konstruktion = Text $r['konstruktion']
        psi_wert     = $psi
        quelle       = Text $r['quelle']
        ordner       = (Text $r['ordner_eltern']) + '|' + (Text $r['ordner'])
        bilder       = Liste $bildJeDim[$ref]
    }
}
NdJson $zeilenWb 'waermebruecken.ndjson'
Write-Output ''

# ===========================================================================
# 4. Bilderverzeichnis
# ===========================================================================

$bilderListe = @($bildIndex.Values | Sort-Object { $_.sha256 })
$sw = New-Object System.IO.StreamWriter((Join-Path $Ziel 'bilder.json'), $false, (New-Object System.Text.UTF8Encoding $false))
try { $sw.Write(($bilderListe | ConvertTo-Json -Depth 4)) } finally { $sw.Close() }

# Measure-Object liest keine Schluessel geordneter Hashtables, deshalb von Hand.
$summe = 0
foreach ($b in $bilderListe) { $summe += [long]$b.bytes }
$mb = $summe / 1MB
Write-Output ("bilder.json               {0,6} Bilder, {1:N1} MB" -f $bilderListe.Count, $mb)
Write-Output ''
Write-Output "Fertig. Datenstand in: $Ziel"
