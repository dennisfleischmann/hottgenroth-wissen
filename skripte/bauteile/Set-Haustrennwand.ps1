# Set-Haustrennwand.ps1 -- Haustrennwand (DHH/Reihenhaus) herstellen: Angrenzung
# "gegen beheizt" im Rechenmodell, optional dazu das Nebengebaeude in der Zeichnung.
#
# WARUM ES DAS GIBT
# Bei einer Doppelhaushaelfte grenzt die Trennwand nicht an Aussenluft, sondern an
# den beheizten Nachbarn. Diese Angrenzung lebt AUSSCHLIESSLICH im Rechenmodell
# (BmElement mit RepositoryType 1) -- die Zeichnung (RepositoryType 3) kennt keine
# Angrenzung, dort bleibt AdjacentType 0. Das sichtbare Nachbarhaus wiederum lebt
# nur in der Zeichnung, als <attachment> im BmMedia-Blob (Set-Nebengebaeude.ps1).
# Bisher war das ein Zweischritt aus Einmalskript plus Werkzeug; dieses Skript
# macht beides in einem Aufruf und ist idempotent: was schon stimmt, wird nicht
# angefasst, sondern als "schon gesetzt" gezaehlt.
#
# WAS "WAND GEGEN BEHEIZT" IN DER DATENBANK HEISST (vier Felder, nicht zwei)
# Gemessen am nativ gezeichneten Referenzmodell "3QHTK_Lennart Krause_260929
# Kopie" und am umgestellten Krause-Projekt (beide 14.10.2026), Spalte fuer
# Spalte verglichen:
#   1. BmElement.AdjacentType            = 1   (btaHeated; Aussenluft = 3)
#   2. BmElementEnergyConsulting.CladdingSurface = 0   (keine Huellflaeche)
#   3. BmElementEnergyConsulting.FxElementType   = 19  (Fx-Zeile 19 der DIN V 18599;
#      Aussenwand = 1. Beleg im dekompilierten Code Hsetu.BuildingModule.ViewModel.cs
#      Z. 48122 ff.: btaOutside -> st18599RF01, btaHeated -> st18599RF19)
#   4. BmElement.MetaDesc: der Eigenschafts-Cache der Oberflaeche. Zwei Eintraege
#      im Format {Property-GUID}|Typ|Wert|Wert|1 tragen Huellflaeche und Fx-Typ.
# Die Software zieht 3 und 4 selbst nach -- aber erst beim Oeffnen/Schliessen des
# Projekts (live gemessen 14.10.2026: fx sprang erst bei der Projektschliessung
# 15:04:35 von 1 auf 19, ohne dass EC.StampEdit sich bewegte). Ein Werkzeug, das
# bei geschlossener Software schreibt, muss deshalb alle vier Felder setzen,
# sonst rechnen Spiegel-Abruf und Rechenlauf ohne Oberflaeche mit fx=1 weiter.
# Die EC-Zeile wird ohne StampEdit geschrieben -- byte-treu zum erprobten
# Einmalskript und zum gemessenen Verhalten der Software selbst.
#
# Die zwei Property-GUIDs in MetaDesc sind KEINE Projektdaten, sondern Kennungen
# des Hottgenroth-Datenmodells (Hsetu.Model.Bim.cs: "Huellflaeche / Systemgrenze"
# und "Angrenztyp fuer Fx-Bestimmung"), byte-identisch in beiden gemessenen
# Projekten -- deshalb stehen sie hier als Konstanten, wie ein Spaltenname.
# MetaDesc ist nur zu ~95 % entschluesselt: ersetzt werden gezielt die zwei
# bekannten Eintraege. Sieht der Inhalt anders aus, bleibt MetaDesc unangetastet
# (die Eigenschaftsmaske zeigt dann bis zum naechsten Software-Speichern den
# alten Wert; Rechenkern und Spiegel lesen die harten Spalten).
#
# WOHER DIE ZIELWAENDE KOMMEN
# -Wand sucht den Zeichnungsnamen an den Repo-3-Waenden -- in BEIDEN Namensspalten,
# denn skriptgebaute Projekte tragen ihn in ShortDesc UND LongDesc, von HottCAD
# selbst gezeichnete nur in LongDesc. Von der Zeichnungswand zum Rechenmodell
# geht es ueber BmElement.RepositoryElementUUID (verifiziert an AW 004 im
# Krause-Projekt und am 1:n-Fall EW 001 der Kopie: EINE Zeichnungswand traegt
# dort drei Repo-1-Teilflaechen).
# -Richtung nimmt stattdessen BmElement.Orientation am Repo-1-Element
# (Kompassgrad: 0=N, 90=O, 180=S, 270=W; an beiden Projekten exakt). Das
# Punkte-Parsing der Zeichnung waere hier die schlechtere Quelle: es braucht
# erst eine Gebaeude-BoundingBox, denn software-gezeichnete Projekte liegen
# verschoben im Koordinatensystem. Innenwaende tragen den Sentinel
# -987654321.99 und fallen aus jedem Fenster; Nord braucht ein Wrap-around-
# Fenster (>=315 oder <45), nie einen Gleichheitstest -- andernorts wurde
# 359.999999999997 fuer Nord gemessen. Grenze: bei frei gedrehten Gebaeuden
# (Nordabweichung) ist der Namensweg der eindeutige.
#
# SCHUTZSCHRANKEN: NUR PLAUSIBLE AUSGANGSLAGEN (nachgeruestet 14.10.2026)
# Ein 90-Grad-Fenster faengt nicht nur Trennwaende. In der echten Datenbank
# stehen in West-Fenstern auch Waende gegen Erdreich (AdjacentType 5, z. B.
# 7CJM4_Sahin: 9 Stueck) und gegen unbeheizt (2) -- und native Innenwaende
# tragen im Rechenmodell EXAKT den Trennwand-Zielzustand 1/0/19, sind also vom
# umgestellten Zustand nicht unterscheidbar. Deshalb zwei Schranken, in beiden
# Richtungen:
#   - Angefasst wird nur die plausible Ausgangslage: vorwaerts AdjacentType 3
#     (oder 1 als halb gesetzter Vorlauf -- das Einmalskript schrieb ohne Fx),
#     rueckwaerts AUSSCHLIESSLICH AdjacentType 1. Alles andere (2/5/0/...)
#     wird angezeigt und uebersprungen, nie still mitgenommen.
#   - Die Zeichnungswand muss auf dem Aussenring liegen. wall_type kennt drei
#     Werte (ausgezaehlt ueber alle Projekte: Inner, OuterContour, OuterSingle);
#     "Inner" ist bei -Wand ein Abbruch (vertippte IW-Wand) und bei -Richtung
#     ein Ueberspringen. Traegt die Zeichnungswand keine CADXMLData (in
#     Bestandsprojekten haeufig), ist dieser Schutz nicht pruefbar und es gilt
#     nur die Angrenzungs-Schranke -- das Werkzeug sagt das dann.
#
# NEBENGEBAEUDE: WARUM DER ANKER DIE UNTERSTE WAND IST
# Die Oberflaeche haengt EIN Attachment an die Wand des untersten Geschosses und
# zieht den Umriss ueber alle Geschosse (gemessen 14.10.2026 am handgezeichneten
# NG 001 im Krause-Projekt: wall_ref = EG-Wand, z von 0 bis 10,226 m) -- nicht
# drei Attachments je Geschoss. Dieses Skript macht es genauso: Anker ist die
# Zielwand mit der niedrigsten Geschoss-Hoehenlage, den Umriss leitet
# Set-Nebengebaeude.ps1 selbst ab (Get-Wandsilhouette.ps1, ab Kellersohle).
# Idempotenz: haengt an einer der Zielwaende schon ein Heated-Attachment, wird
# nichts aufgerufen ("vorhanden"). Haengen FREMDE Anbauten im Blob -- an
# fremden Waenden ODER mit anderem Typ als Heated (Carport, Garage) --, bricht
# das Skript ab, vorwaerts wie rueckwaerts: Set-Nebengebaeude.ps1 ersetzt beim
# Schreiben den ganzen attachments-Block und wuerde sie still verwerfen.
# Dazu eine Blob-Plausibilitaet: jedes <attachment> muss dem bekannten Muster
# (name -> wall_ref -> type) folgen und ein vorhandener <attachments>-Block
# mindestens einen lesbaren Eintrag tragen, sonst Abbruch -- eine andere
# HottCAD-Schreibweise ginge sonst beim Blockersatz unsichtbar verloren.
# Reihenfolge: der gesamte Nebengebaeude-Bestand wird VOR dem Schreiben der
# Angrenzung geprueft (reine Leseoperationen) -- ein Abbruch im Nebengebaeude-
# Teil hinterlaesst so keinen halben Zustand.
#
# WAS ES NICHT KANN
# - Nur Waende (ElementType 1). FxElementType 19 ist nur fuer Waende gegen
#   beheizt belegt; andere Bauteilarten haben andere Fx-Zeilen.
# - Repo-3-Elemente bekommen nie eine Angrenzung (sie kennen keine).
# - Den IBP-Blob (TableZusatz.Kernel18599V5) fasst es nicht an. Nach dem ersten
#   Echtlauf gehoert eine Wirkungsprobe an HT'/Endenergie dazu -- die Angrenzung
#   wandert ueber das Referenzgebaeude auch in den HT'-Grenzwert.
# - Kein zweites Attachment anhaengen: ein Blob mit fremden Anbauten ist ein
#   Abbruch, kein Ersetzen.
#
# ERPROBUNGSSTAND: 14.10.2026 gebaut, nur Probelaeufe, Echtlauf steht aus.
# Geprueft an zwei Projekten: "3QHTK_Lennart Krause" per GUID (Idempotenz-Fall:
# alle drei W-Flaechen standen schon auf dem Ziel, das handgezeichnete NG 001
# wurde als vorhanden erkannt; -Richtung W fand exakt dieselben drei Flaechen;
# -Zuruecknehmen kuendigte alle vier Felder samt MetaDesc-Ersetzung an) und
# "_260929 Kopie" (nativer Bestand: -Wand "EW 001" traf die drei Teilflaechen
# des 1:n-Mappings, Namensmatch nur ueber LongDesc). Die Silhouetten-Ableitung
# lief per GUID gegen die Krause-Westwand (5 Punkte mit Giebel). Nach dem
# ersten Echtlauf: Wirkungsprobe an HT'/Endenergie, nicht nur zuruecklesen --
# und ausdruecklich pruefen, ob die Umstellung einen Oeffnen/Schliessen-Zyklus
# der Software uebersteht (die des Einmalskripts tat es).
# Flaechen-Kontext fuer HT'-Wirkungsproben: die Westflaechen der 260929 Kopie
# summieren in EG und OG1 exakt die Krause-Werte (31,29 m2), im DG weichen sie
# ab (19,53 gegen 27,15 m2) -- Modellunterschied der nativ gezeichneten Kopie
# (anderer Dach-/Drempelschnitt), kein Werkzeugfehler.
#
# Siehe auch: Set-Nebengebaeude.ps1, Get-Wandsilhouette.ps1,
# bauteile/docs/hottgenroth-bauteil-sql.md.
#
# Beispiele:
#   .\Set-Haustrennwand.ps1 -Projekt "Krause" -Wand "AW 004" -MitNebengebaeude -Probelauf
#   .\Set-Haustrennwand.ps1 -Projekt ea94920b-8917-49d9-bcc4-fadc8d510712 -Richtung W -Probelauf
#   .\Set-Haustrennwand.ps1 -Projekt "Krause" -Wand "AW 004" -MitNebengebaeude
#   .\Set-Haustrennwand.ps1 -Projekt "Krause" -Wand "AW 004" -Zuruecknehmen

[CmdletBinding()]
param(
    # GUID (PrProject.UUID) oder eindeutiger Namensteil (LongDesc). GUID nehmen,
    # wenn der Name Praefix eines anderen Projekts ist (Krause gegen seine Kopie).
    [Parameter(Mandatory = $true)][string]$Projekt,
    # Zeichnungsname der Trennwand, z. B. 'AW 004'. Findet alle Geschosse,
    # die eine Repo-3-Wand dieses Namens fuehren.
    [string]$Wand = '',
    # Alternativ: alle Aussenring-Waende dieser Himmelsrichtung, alle Geschosse.
    [ValidateSet('', 'N', 'O', 'S', 'W')][string]$Richtung = '',
    # Zusaetzlich das Nachbarhaus als beheiztes Nebengebaeude in die Zeichnung
    # haengen (bzw. mit -Zuruecknehmen entfernen).
    [switch]$MitNebengebaeude,
    # Angrenzung zurueck auf Aussenluft (AdjacentType 3, CladdingSurface 1, Fx 1).
    [switch]$Zuruecknehmen,
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture
function K([double]$w) { $w.ToString('0.##', $inv) }
$script:schrittNr = 0
function Schritt([string]$Text) { $script:schrittNr++; Write-Host "`n== $($script:schrittNr). $Text" -ForegroundColor Cyan }

if (($Wand -eq '') -and ($Richtung -eq '')) { throw "Entweder -Wand (Zeichnungsname, z. B. 'AW 004') oder -Richtung (N/O/S/W) angeben." }
if (($Wand -ne '') -and ($Richtung -ne '')) { throw "-Wand und -Richtung schliessen sich aus -- genau eines angeben." }

# Softwarepruefung nach dem Setup-Wohngebaeude-Muster: immer pruefen, im
# Probelauf nur warnen (es wird nichts geschrieben). Die Software verwirft
# Fremd-Schreibzugriffe beim Beenden still -- siehe Test-SoftwareLaeuft.ps1.
if (-not $OhneSoftwarepruefung) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu -Erlaubt:$Probelauf }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

# Zielwerte. Rueckweg = Aussenwand (AdjacentType 3 btaOutside, Huellflaeche 1,
# Fx-Zeile 1) -- das native Aussenwand-Muster beider gemessener Projekte.
$zielAdj    = 1;  $zielHuelle = 0; $zielFx = 19
$zielWort   = "gegen beheizt (Haustrennwand)"
if ($Zuruecknehmen) {
    $zielAdj = 3; $zielHuelle = 1; $zielFx = 1
    $zielWort = "gegen Aussenluft (zurueckgenommen)"
}

# Property-GUIDs des MetaDesc-Caches: Datenmodell-Konstanten, keine Projektdaten
# (siehe Kopf). Ersetzt wird genau der Eintrag {GUID}|Typ|Wert|Wert|1.
$propHuelle = 'f61322be-6008-4958-809c-a7c3124982cb'   # "Huellflaeche / Systemgrenze"
$propFx     = 'c35bfdee-2dcd-47e1-8a38-f2adb3f8d862'   # "Angrenztyp fuer Fx-Bestimmung"
$patHuelle  = '\{' + $propHuelle + '\}\|3\|-?\d+\|-?\d+\|1'
$patFx      = '\{' + $propFx     + '\}\|14\|-?\d+\|-?\d+\|1'
$ersHuelle  = '{' + $propHuelle + '}|3|'  + $zielHuelle + '|' + $zielHuelle + '|1'
$ersFx      = '{' + $propFx     + '}|14|' + $zielFx     + '|' + $zielFx     + '|1'

$adjWort = @{ 0 = 'Vorrat'; 1 = 'beheizt'; 2 = 'unbeheizt'; 3 = 'Aussenluft'; 4 = 'innen'
              5 = 'Erdreich'; 6 = 'oberste Decke'; 7 = 'Kellerdecke'; 8 = 'Gebaeude' }
function AdjText([int]$a) {
    $w = $adjWort[$a]
    if ($w) { return "$a $w" }
    return "$a"
}

# Orientierungsfenster: +/-45 Grad je Richtung, N mit Wrap-around. Der Sentinel
# -987654321.99 (Innenwand ohne Orientierung) faellt aus jedem Fenster.
$fenster = @{
    'N' = "(r1.Orientation >= 315 OR (r1.Orientation > -1 AND r1.Orientation < 45))"
    'O' = "(r1.Orientation >= 45 AND r1.Orientation < 135)"
    'S' = "(r1.Orientation >= 135 AND r1.Orientation < 225)"
    'W' = "(r1.Orientation >= 225 AND r1.Orientation < 315)"
}

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
function Abfrage([string]$Sql, [hashtable]$P = @{}, $Tx = $null) {
    $c = $con.CreateCommand(); $c.CommandText = $Sql; $c.CommandTimeout = 300
    if ($Tx) { $c.Transaction = $Tx }
    foreach ($k in $P.Keys) { [void]$c.Parameters.AddWithValue($k, $P[$k]) }
    $t = New-Object System.Data.DataTable; $t.Load($c.ExecuteReader()); return , $t
}
function Befehl([string]$Sql, [hashtable]$P = @{}, $Tx = $null) {
    $c = $con.CreateCommand(); $c.CommandText = $Sql; $c.CommandTimeout = 300
    if ($Tx) { $c.Transaction = $Tx }
    foreach ($k in $P.Keys) { [void]$c.Parameters.AddWithValue($k, $P[$k]) }
    return $c.ExecuteNonQuery()
}

$tx = $null
try {
    # --------------------------------------------------------------- Zielwaende
    Schritt "Zielwaende"

    $g = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$g)) { $tp = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE UUID=@p" @{ '@p' = $g } }
    else {
        # LIKE-Wildcards aus der Eingabe escapen: '[' matcht sonst nie, '_'
        # jedes Zeichen -- ein Namensteil soll woertlich gemeint sein.
        $like = $Projekt -replace '([%_\[])', '[$1]'
        $tp = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p" @{ '@p' = "%$like%" }
    }
    if ($tp.Rows.Count -ne 1) {
        $namen = ($tp.Rows | ForEach-Object { "  " + $_.LongDesc }) -join "`n"
        throw "Projekt nicht eindeutig: $($tp.Rows.Count) Treffer.`n$namen"
    }
    $projektId = [guid]$tp.Rows[0].UUID
    $projektName = [string]$tp.Rows[0].LongDesc
    $modus = if ($Wand) { "Zeichnungswand '$Wand'" } else { "Richtung $Richtung" }
    Write-Host "   Projekt : $projektName"
    Write-Host "   Modus   : $modus"
    Write-Host "   Ziel    : $zielWort -- AdjacentType $zielAdj, CladdingSurface $zielHuelle, FxElementType $zielFx"

    # Geschosse: Zeichnungs-GUID (<floor GUID="..."> in der CADXMLData) UND
    # Zeilen-UUID als Schluessel. Die Wand-XML verweist auf die Zeichnungs-GUID;
    # nur in skriptgebauten Projekten sind beide gleich (Krause), in von HottCAD
    # angelegten verschieden (260929 Kopie: 11d49f8f... gegen 1e434e1e...).
    $sqlGeschosse = "SELECT f.LongDesc, f.ElevationOfRefHeight, LOWER(CAST(f.UUID AS varchar(40))) AS ZeilenUuid, " +
        "CASE WHEN CHARINDEX('<floor GUID=""', CAST(d.ClassValue AS nvarchar(max))) > 0 " +
        "THEN LOWER(SUBSTRING(CAST(d.ClassValue AS nvarchar(max)), CHARINDEX('<floor GUID=""', CAST(d.ClassValue AS nvarchar(max))) + 13, 36)) " +
        "ELSE NULL END AS ZeichnungsGuid " +
        "FROM BmFloor f LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.ProjectUUID = f.ProjectUUID AND d.LongDesc = 'CADXMLData' " +
        "WHERE f.ProjectUUID = @p ORDER BY f.ElevationOfRefHeight"
    $geschossMap = @{}
    foreach ($r in (Abfrage $sqlGeschosse @{ '@p' = $projektId }).Rows) {
        $info = [pscustomobject]@{ Name = [string]$r.LongDesc; Elev = [double]$r.ElevationOfRefHeight }
        $geschossMap[[string]$r.ZeilenUuid] = $info
        if ($r.ZeichnungsGuid -isnot [DBNull] -and $r.ZeichnungsGuid) { $geschossMap[([string]$r.ZeichnungsGuid).ToLower()] = $info }
    }

    # Zielwaende: Zeichnungswand (Repo 3) und ihre Rechenmodell-Flaechen (Repo 1)
    # ueber RepositoryElementUUID. 1:n ist der Normalfall -- immer ALLE Treffer.
    # ISNULL ueberall, wo das Schema NULL erlaubt (AdjacentType, CladdingSurface,
    # FxElementType): eine NULL soll als Befund erscheinen, nicht als Cast-Crash.
    # HatEC markiert Flaechen ohne EC-Zeile (deshalb LEFT JOIN, nicht INNER):
    # die EC-Zeile legt erst die Software an -- gerade frisch importierte oder
    # skriptgebaute Projekte koennen ohne dastehen, und die Flaechen duerfen
    # nicht still aus der Zielmenge fallen.
    $spalten = "r1.UUID AS ModellUUID, r1.LongDesc AS ModellName, ISNULL(r1.AdjacentType, 0) AS AdjacentType, " +
        "CAST(ISNULL(ec.CladdingSurface, 0) AS int) AS Huelle, ISNULL(ec.FxElementType, 0) AS FxElementType, " +
        "CASE WHEN ec.UUID IS NULL THEN 0 ELSE 1 END AS HatEC, " +
        "ISNULL(CAST(r1.MetaDesc AS nvarchar(max)), '') AS MetaDesc, ISNULL(r1.GrossArea, 0) AS Flaeche, " +
        "z.UUID AS ZeichnungUUID, COALESCE(NULLIF(z.ShortDesc,''), z.LongDesc) AS ZeichnungName"
    if ($Wand) {
        # Namensmatch MUSS beide Spalten decken (siehe Kopf).
        $tzw = Abfrage ("SELECT UUID FROM BmElement WHERE ProjectUUID=@p AND RepositoryType=3 AND ElementType=1 " +
                "AND (NULLIF(ShortDesc,'') = @n OR LongDesc = @n)") @{ '@p' = $projektId; '@n' = $Wand }
        if ($tzw.Rows.Count -eq 0) {
            $tn = Abfrage ("SELECT DISTINCT COALESCE(NULLIF(ShortDesc,''), LongDesc) AS Name FROM BmElement " +
                    "WHERE ProjectUUID=@p AND RepositoryType=3 AND ElementType=1 ORDER BY Name") @{ '@p' = $projektId }
            $da = ($tn.Rows | ForEach-Object { [string]$_.Name }) -join ', '
            throw "Zeichnungswand '$Wand' nicht gefunden. Vorhandene Zeichnungswaende: $(if ($da) { $da } else { '(keine)' })."
        }
        $sqlZiele = "SELECT $spalten FROM BmElement z " +
            "JOIN BmElement r1 ON r1.RepositoryElementUUID = z.UUID AND r1.ProjectUUID = z.ProjectUUID AND r1.RepositoryType = 1 AND r1.ElementType = 1 " +
            "LEFT JOIN BmElementEnergyConsulting ec ON ec.UUID = r1.UUID " +
            "WHERE z.ProjectUUID = @p AND z.RepositoryType = 3 AND z.ElementType = 1 " +
            "AND (NULLIF(z.ShortDesc,'') = @n OR z.LongDesc = @n) ORDER BY r1.LongDesc"
        $sqlParams = @{ '@p' = $projektId; '@n' = $Wand }
        $tz = Abfrage $sqlZiele $sqlParams
        if ($tz.Rows.Count -eq 0) {
            throw ("Zeichnungswand '$Wand' gefunden ($($tzw.Rows.Count) Geschoss(e)), aber kein Repo-1-Element verweist darauf -- " +
                   "das Rechenmodell ist noch nicht aufgebaut. Das Projekt einmal in der Software oeffnen und schliessen.")
        }
    }
    else {
        $sqlZiele = "SELECT $spalten FROM BmElement r1 " +
            "LEFT JOIN BmElementEnergyConsulting ec ON ec.UUID = r1.UUID " +
            "LEFT JOIN BmElement z ON z.UUID = r1.RepositoryElementUUID AND z.ProjectUUID = r1.ProjectUUID AND z.RepositoryType = 3 AND z.ElementType = 1 " +
            "WHERE r1.ProjectUUID = @p AND r1.RepositoryType = 1 AND r1.ElementType = 1 " +
            "AND " + $fenster[$Richtung] + " ORDER BY r1.LongDesc"
        $sqlParams = @{ '@p' = $projektId }
        $tz = Abfrage $sqlZiele $sqlParams
        if ($tz.Rows.Count -eq 0) {
            $ta = Abfrage ("SELECT ISNULL(Orientation, -987654321.99) AS Orientation FROM BmElement WHERE ProjectUUID=@p AND RepositoryType=1 AND ElementType=1") @{ '@p' = $projektId }
            if ($ta.Rows.Count -eq 0) {
                throw "Das Projekt hat keine Modellwaende (RepositoryType 1) -- das Rechenmodell ist noch nicht aufgebaut. Das Projekt einmal in der Software oeffnen und schliessen."
            }
            $statistik = @{ 'N' = 0; 'O' = 0; 'S' = 0; 'W' = 0; 'ohne' = 0 }
            foreach ($r in $ta.Rows) {
                $o = [double]$r.Orientation
                if ($o -le -1) { $statistik['ohne']++ }
                elseif ($o -ge 315 -or $o -lt 45) { $statistik['N']++ }
                elseif ($o -lt 135) { $statistik['O']++ }
                elseif ($o -lt 225) { $statistik['S']++ }
                else { $statistik['W']++ }
            }
            throw ("Keine Modellwand mit Orientierung $Richtung. Verteilung der $($ta.Rows.Count) Modellwaende: " +
                   "N=$($statistik['N']), O=$($statistik['O']), S=$($statistik['S']), W=$($statistik['W']), ohne Orientierung=$($statistik['ohne']).")
        }
    }

    # Zeichnungswaende anreichern: CAD-GUID (Attribut GUID am <wall>, NICHT
    # BmElement.UUID) und Geschoss aus dem floor-Attribut. Case-sensitiv matchen:
    # prev=/next=-Nachbarverweise und u_valueDimGuid sind klein geschrieben.
    function NeueZeile($r) {
        $zu = $null
        if ($r.ZeichnungUUID -isnot [DBNull]) { $zu = ([guid]$r.ZeichnungUUID).ToString().ToLower() }
        $zn = ''
        if ($r.ZeichnungName -isnot [DBNull]) { $zn = [string]$r.ZeichnungName }
        return [pscustomobject]@{
            ModellUUID = [guid]$r.ModellUUID
            Kurz       = ([guid]$r.ModellUUID).ToString().Substring(0, 8)
            Name       = [string]$r.ModellName
            Adj        = [int]$r.AdjacentType
            Huelle     = [int]$r.Huelle
            Fx         = [int]$r.FxElementType
            HatEC      = ([int]$r.HatEC -eq 1)
            Meta       = [string]$r.MetaDesc
            Flaeche    = [double]$r.Flaeche
            ZKey       = $zu
            ZName      = $zn
        }
    }
    $ziele = @($tz.Rows | ForEach-Object { NeueZeile $_ })

    # Flaechen ohne EC-Zeile nicht still verlieren (frueher fielen sie durch
    # den INNER JOIN kommentarlos aus der Zielmenge): benennen und abbrechen --
    # ohne EC-Zeile laesst sich weder Huellflaeche noch Fx setzen.
    $ohneEC = @($ziele | Where-Object { -not $_.HatEC })
    if ($ohneEC.Count) {
        throw ("$($ohneEC.Count) von $($ziele.Count) Modellflaeche(n) ohne BmElementEnergyConsulting-Zeile: " +
               (($ohneEC | ForEach-Object { "$($_.Name) ($($_.Kurz))" }) -join ', ') +
               ". Die legt erst die Software an -- das Projekt einmal in der Software oeffnen und schliessen, dann erneut ausfuehren.")
    }

    $zeichnungen = @{}
    foreach ($zi in $ziele) {
        if (-not $zi.ZKey -or $zeichnungen.ContainsKey($zi.ZKey)) { continue }
        $txml = Abfrage ("SELECT TOP 1 CAST(d.ClassValue AS nvarchar(max)) AS Xml FROM BmData d " +
                "WHERE d.ReferenceUUID=@z AND d.ProjectUUID=@p AND d.LongDesc='CADXMLData'") @{ '@z' = [guid]$zi.ZKey; '@p' = $projektId }
        $cad = $null; $geschoss = '?'; $elev = [double]::MaxValue; $wandTyp = $null
        if ($txml.Rows.Count -eq 1) {
            $xml = [string]$txml.Rows[0].Xml
            $mg = [regex]::Match($xml, '<wall\b[^>]*? GUID="([^"]+)"')
            if ($mg.Success) { $cad = $mg.Groups[1].Value.ToLower() }
            $mf = [regex]::Match($xml, '<wall\b[^>]*? floor="([^"]+)"')
            if ($mf.Success) {
                $fl = $geschossMap[$mf.Groups[1].Value.ToLower()]
                if ($fl) { $geschoss = $fl.Name; $elev = $fl.Elev }
            }
            # wall_type: Inner / OuterContour / OuterSingle (ausgezaehlt ueber
            # alle Projekte). Eine Haustrennwand liegt auf dem Aussenring.
            $mw = [regex]::Match($xml, '<wall\b[^>]*? wall_type="([^"]+)"')
            if ($mw.Success) { $wandTyp = $mw.Groups[1].Value }
        }
        if (-not $cad) { Write-Warning "Zeichnungswand '$($zi.ZName)' ohne CAD-GUID in der CADXMLData -- als Nebengebaeude-Anker unbrauchbar." }
        $zeichnungen[$zi.ZKey] = [pscustomobject]@{ Name = $zi.ZName; CadGuid = $cad; Geschoss = $geschoss; Elev = $elev; WandTyp = $wandTyp }
    }

    # Vertippte Innenwand bei -Wand ist ein Abbruch, kein Ueberspringen: native
    # Innenwaende stehen im Rechenmodell auf exakt dem Trennwand-Zielzustand
    # (1/0/19) und duerfen weder gestellt noch zurueckgenommen werden.
    if ($Wand) {
        $innen = @($zeichnungen.Values | Where-Object { $_.WandTyp -eq 'Inner' })
        if ($innen.Count) {
            throw ("Zeichnungswand '$Wand' ist eine Innenwand (wall_type=""Inner"" in der CADXMLData) -- eine Haustrennwand " +
                   "liegt auf dem Aussenring. Native Innenwaende tragen im Rechenmodell dieselben Werte wie eine umgestellte " +
                   "Haustrennwand und werden grundsaetzlich nicht angefasst.")
        }
    }

    $ohneZeichnung = @($ziele | Where-Object { -not $_.ZKey })
    if ($ohneZeichnung.Count) {
        Write-Warning ("$($ohneZeichnung.Count) Modellflaeche(n) ohne Zeichnungsverweis (RepositoryElementUUID leer): " +
            "$(($ohneZeichnung | ForEach-Object { $_.Name }) -join ', '). Die Angrenzung wird trotzdem gestellt; " +
            "als Anker fuer ein Nebengebaeude taugen sie nicht.")
    }

    # Schutzschranken (siehe Kopf): 'ziel' = schon gesetzt, 'umstellen' = wird
    # geschrieben, 'uebersprungen' = unplausible Ausgangslage oder Innenwand --
    # bleibt stehen und wird mit Grund gezeigt. Die Innenwand-Pruefung kommt
    # ZUERST: eine Inner-Wand auf 1/0/19 ist keine gesetzte Trennwand, sondern
    # nativ so, und darf auch nicht als "schon gesetzt" durchgehen.
    function SetzeStatus($liste) {
        foreach ($zi in $liste) {
            $wt = $null
            if ($zi.ZKey -and $zeichnungen.ContainsKey($zi.ZKey)) { $wt = $zeichnungen[$zi.ZKey].WandTyp }
            $plausibel = ($zi.Adj -eq 3 -or $zi.Adj -eq 1)
            if ($Zuruecknehmen) { $plausibel = ($zi.Adj -eq 1) }
            $status = 'umstellen'; $grund = ''
            if ($wt -eq 'Inner') {
                $status = 'uebersprungen'
                $grund = 'Zeichnungswand ist eine Innenwand (wall_type Inner), keine Aussenring-Wand'
            }
            elseif ($zi.Adj -eq $zielAdj -and $zi.Huelle -eq $zielHuelle -and $zi.Fx -eq $zielFx) { $status = 'ziel' }
            elseif (-not $plausibel) {
                $status = 'uebersprungen'
                if ($Zuruecknehmen) { $grund = "Angrenzung $(AdjText $zi.Adj) stammt nicht von diesem Werkzeug (zurueckgenommen wird nur 1 beheizt)" }
                else { $grund = "Angrenzung $(AdjText $zi.Adj) ist keine plausible Ausgangslage einer Haustrennwand (erwartet: 3 Aussenluft, oder 1 beheizt als halb gesetzter Vorlauf)" }
            }
            if ($zi.PSObject.Properties['Status']) { $zi.Status = $status; $zi.Grund = $grund }
            else { $zi | Add-Member Status $status; $zi | Add-Member Grund $grund }
        }
    }
    function ZeigeZiele($liste) {
        Write-Host ""
        Write-Host ("   {0}{1,-9} {2,-12} {3,-9} {4,-28} {5,-8} {6,-9} {7,8}" -f ' ', 'Modell', 'Name', 'Geschoss', 'Angrenzung', 'Huelle', 'Fx', 'm2')
        foreach ($zi in $liste) {
            $geschoss = '?'
            if ($zi.ZKey -and $zeichnungen.ContainsKey($zi.ZKey)) { $geschoss = $zeichnungen[$zi.ZKey].Geschoss }
            $mark = ' '
            if ($zi.Status -eq 'umstellen') { $mark = '*' }
            if ($zi.Status -eq 'uebersprungen') { $mark = '-' }
            $sAdj = AdjText $zi.Adj
            $sHuelle = "$($zi.Huelle)"
            $sFx = "$($zi.Fx)"
            if ($zi.Status -eq 'umstellen') {
                if ($zi.Adj -ne $zielAdj) { $sAdj = (AdjText $zi.Adj) + ' -> ' + (AdjText $zielAdj) }
                if ($zi.Huelle -ne $zielHuelle) { $sHuelle = "$($zi.Huelle) -> $zielHuelle" }
                if ($zi.Fx -ne $zielFx) { $sFx = "$($zi.Fx) -> $zielFx" }
            }
            Write-Host ("   {0}{1,-9} {2,-12} {3,-9} {4,-28} {5,-8} {6,-9} {7,8}" -f $mark, $zi.Kurz, $zi.Name, $geschoss, $sAdj, $sHuelle, $sFx, (K $zi.Flaeche))
        }
        foreach ($zi in @($liste | Where-Object { $_.Status -eq 'uebersprungen' })) {
            Write-Host "   - $($zi.Name): $($zi.Grund)" -ForegroundColor Yellow
        }
        return @($liste | Where-Object { $_.Status -eq 'umstellen' }).Count
    }
    SetzeStatus $ziele
    [void](ZeigeZiele $ziele)
    $zuAendern     = @($ziele | Where-Object { $_.Status -eq 'umstellen' })
    $uebersprungen = @($ziele | Where-Object { $_.Status -eq 'uebersprungen' })
    $schonGesetzt  = @($ziele | Where-Object { $_.Status -eq 'ziel' })
    if ($zuAendern.Count -or $uebersprungen.Count) { Write-Host "`n   * wird geschrieben   - uebersprungen   (ohne Marker: schon gesetzt)" }
    Write-Host "`n   $($zuAendern.Count) umzustellen, $($schonGesetzt.Count) schon gesetzt, $($uebersprungen.Count) uebersprungen."
    $wtUnbekannt = @($zuAendern | Where-Object { -not ($_.ZKey -and $zeichnungen.ContainsKey($_.ZKey) -and $zeichnungen[$_.ZKey].WandTyp) })
    if ($wtUnbekannt.Count) {
        Write-Host ("   Hinweis: wall_type an $($wtUnbekannt.Count) umzustellenden Flaeche(n) nicht pruefbar (keine CADXMLData) -- " +
            "der Innenwand-Schutz greift dort nicht, es gilt nur die Angrenzungs-Schranke.") -ForegroundColor Yellow
    }

    # --------------------------- Nebengebaeude: Bestand pruefen (reine Lesung)
    # VOR dem Schreiben der Angrenzung: Blob-Analyse, Anker-Wahl und alle
    # Abbruchgruende des Nebengebaeude-Teils sind lesend feststellbar. Ein
    # Abbruch hier hinterlaesst keinen halben Zustand.
    $ngPlan = ''; $ngAnker = $null
    if ($MitNebengebaeude) {
        Schritt "Nebengebaeude: Bestand pruefen"
        # Anker-Kandidaten nur aus plausiblen Zielwaenden -- eine uebersprungene
        # Erdreich- oder Innenwand ist kein Trennwand-Anker.
        $ankerWaende = @{}
        foreach ($zi in $ziele) {
            if ($zi.Status -ne 'uebersprungen' -and $zi.ZKey -and $zeichnungen.ContainsKey($zi.ZKey)) { $ankerWaende[$zi.ZKey] = $zeichnungen[$zi.ZKey] }
        }
        $kandidaten = @($ankerWaende.Values | Where-Object { $_.CadGuid } | Sort-Object Elev)
        $cadGuids = @{}
        foreach ($zw in $kandidaten) { $cadGuids[$zw.CadGuid] = $zw }

        # Bestand im Umgebungs-Blob selbst lesen: Set-Nebengebaeude.ps1 ersetzt
        # beim Schreiben den ganzen attachments-Block -- Idempotenz und der
        # Schutz fremder Anbauten muessen deshalb hier passieren.
        $L1 = [System.Text.Encoding]::GetEncoding(28591)   # Latin1: verlustfreier Byte-Rundlauf
        $tm = Abfrage "SELECT UUID, Media FROM BmMedia WHERE ProjectUUID=@p AND Media IS NOT NULL" @{ '@p' = $projektId }
        $blobs = @()
        foreach ($r in $tm.Rows) {
            $b = [byte[]]$r.Media
            if ($b.Length -gt 64 -and ($L1.GetString($b, 0, [Math]::Min(400, $b.Length)) -match 'application="building3d"')) { $blobs += , $b }
        }
        if ($blobs.Count -ne 1) {
            throw ("Erwartet genau eine building3d-Zeichnung in BmMedia, gefunden: $($blobs.Count) " +
                   "(von $($tm.Rows.Count) Medienzeilen). Ohne Zeichnung gibt es keine Wand, an der ein Nebengebaeude haengen koennte.")
        }
        $xml = $L1.GetString($blobs[0])
        $anbauten = @()
        foreach ($m in [regex]::Matches($xml, '<attachment\s+name="([^"]*)"[^>]*?wall_ref="([^"]*)"[^>]*?type="([^"]*)"')) {
            $anbauten += [pscustomobject]@{ Name = $m.Groups[1].Value; WallRef = $m.Groups[2].Value.ToLower(); Typ = $m.Groups[3].Value }
        }
        # Blob-Plausibilitaet: das Muster oben verlangt die Attributreihenfolge
        # name -> wall_ref -> type (beide bekannte Erzeuger schreiben so). Ein
        # <attachment> ausserhalb des Musters oder ein leerer/selbstschliessender
        # <attachments>-Block waere sonst unsichtbar -- und jedes Schreiben
        # ersetzt den GANZEN Block. Dann lieber abbrechen.
        $roh = [regex]::Matches($xml, '<attachment\b').Count
        if ($roh -ne $anbauten.Count) {
            throw ("Im Blob stehen $roh <attachment>-Eintraege, lesbar im bekannten Muster (name, wall_ref, type in dieser " +
                   "Reihenfolge) sind $($anbauten.Count) -- vermutlich eine andere HottCAD-Schreibweise. Abbruch: jedes Schreiben " +
                   "ersetzt den ganzen attachments-Block und wuerde die unlesbaren Eintraege still verwerfen. Erst in der Oberflaeche pruefen.")
        }
        if ($anbauten.Count -eq 0 -and $xml.IndexOf('<attachments') -ge 0) {
            throw ("Der Blob traegt einen <attachments>-Block ohne lesbaren <attachment>-Eintrag (leer oder selbstschliessend) -- " +
                   "Set-Nebengebaeude.ps1 kaeme damit beim Ersetzen nicht zurecht. Erst in der Oberflaeche pruefen.")
        }
        function AnbauText($a) {
            $wo = 'ohne Wandverweis'
            if ($a.WallRef) { $wo = 'fremde Wand ' + $a.WallRef.Substring(0, [Math]::Min(8, $a.WallRef.Length)) }
            if ($cadGuids.ContainsKey($a.WallRef)) { $wo = "$($cadGuids[$a.WallRef].Name) ($($cadGuids[$a.WallRef].Geschoss))" }
            return "$($a.Name) [$($a.Typ)] an $wo"
        }
        $bestand = '(keiner)'
        if ($anbauten.Count) { $bestand = ($anbauten | ForEach-Object { AnbauText $_ }) -join ', ' }
        Write-Host "   Bestand : $bestand"

        if ($Zuruecknehmen) {
            # Blockieren muss alles, was NICHT der eigene Heated-Anbau an einer
            # Zielwand ist: fremde Waende UND fremde Typen (Carport/Garage als
            # Unheated an der Zielwand) -- das Entfernen loescht den ganzen Block.
            $nichtMeins = @($anbauten | Where-Object { -not ($cadGuids.ContainsKey($_.WallRef) -and $_.Typ -eq 'Heated') })
            if ($anbauten.Count -eq 0) {
                $ngPlan = 'nichts'
                Write-Host "   Kein Anbau im Blob -- nichts zu entfernen." -ForegroundColor Yellow
            }
            elseif ($nichtMeins.Count) {
                throw ("Im Umgebungs-Blob haengen Anbauten an fremden Waenden oder mit anderem Typ als Heated: " +
                       (($nichtMeins | ForEach-Object { AnbauText $_ }) -join ', ') +
                       ". -Entfernen loescht den GANZEN attachments-Block und wuerde sie mitnehmen. Erst in der Oberflaeche klaeren.")
            }
            else {
                $ngPlan = 'entfernen'
                Write-Host "   wird entfernt (nach der Angrenzung): $bestand"
            }
        }
        else {
            $meins = @($anbauten | Where-Object { $cadGuids.ContainsKey($_.WallRef) -and $_.Typ -eq 'Heated' })
            if ($meins.Count) {
                $ngPlan = 'vorhanden'
                Write-Host "   vorhanden: $(($meins | ForEach-Object { AnbauText $_ }) -join ', ') -- nichts zu tun." -ForegroundColor Yellow
            }
            elseif ($anbauten.Count) {
                throw ("Im Umgebungs-Blob haengen schon Anbauten ($bestand), aber keiner als Heated an einer Zielwand. " +
                       "Set-Nebengebaeude.ps1 ersetzt beim Schreiben den ganzen attachments-Block und wuerde sie verwerfen. " +
                       "Erst in der Oberflaeche klaeren (oder dort zeichnen).")
            }
            else {
                if ($kandidaten.Count -eq 0) { throw "Keine plausible Zielwand traegt eine CAD-GUID in der Zeichnung -- kein Anker fuer das Nebengebaeude." }
                $ngAnker = $kandidaten[0]
                if ($ngAnker.Geschoss -eq '?') { Write-Warning "Geschoss des Ankers nicht aufloesbar -- nehme '$($ngAnker.Name)'." }
                $ngPlan = 'anlegen'
                Write-Host "   Anker   : $($ngAnker.Name) ($($ngAnker.Geschoss)), CAD-GUID $($ngAnker.CadGuid)"
                Write-Host "   wird angelegt (nach der Angrenzung)."
            }
        }
    }

    # ----------------------------------------------- Angrenzung im Rechenmodell
    Schritt "Angrenzung im Rechenmodell"
    $nrAngrenzung = $script:schrittNr
    $metaLeer = 0
    foreach ($zi in $zuAendern) {
        $zi | Add-Member MetaNeu $null
        if (-not $zi.Meta) { $metaLeer++; continue }
        if ([regex]::IsMatch($zi.Meta, $patHuelle, 'IgnoreCase') -and [regex]::IsMatch($zi.Meta, $patFx, 'IgnoreCase')) {
            $m = [regex]::Replace($zi.Meta, $patHuelle, $ersHuelle, 'IgnoreCase')
            $zi.MetaNeu = [regex]::Replace($m, $patFx, $ersFx, 'IgnoreCase')
        }
        else {
            # MetaDesc ist nur teilentschluesselt: Unerwartetes nicht ueberschreiben.
            Write-Warning ("MetaDesc von $($zi.Name) traegt nicht die zwei bekannten Eintraege -- bleibt unangetastet. " +
                "Die Eigenschaftsmaske zeigt bis zum naechsten Software-Speichern den alten Wert; Rechenkern und Spiegel lesen die Spalten.")
        }
    }
    if ($metaLeer) { Write-Host "   MetaDesc leer an $metaLeer Flaeche(n) -- die Software baut den Cache beim naechsten Oeffnen selbst." -ForegroundColor Yellow }

    if ($zuAendern.Count -eq 0) {
        if ($uebersprungen.Count) {
            Write-Host ("   Nichts umgestellt -- $($schonGesetzt.Count) von $($ziele.Count) Flaeche(n) stehen auf '$zielWort', " +
                "$($uebersprungen.Count) uebersprungen (Gruende oben).") -ForegroundColor Yellow
        }
        else {
            Write-Host "   Nichts zu tun -- alle $($ziele.Count) Flaeche(n) stehen schon auf '$zielWort'." -ForegroundColor Yellow
        }
    }
    elseif ($Probelauf) {
        $mitMeta = @($zuAendern | Where-Object { $_.MetaNeu }).Count
        Write-Host ("   wuerde geschrieben: AdjacentType=$zielAdj, CladdingSurface=$zielHuelle, FxElementType=$zielFx " +
            "an $($zuAendern.Count) Flaeche(n), MetaDesc an $mitMeta davon.") -ForegroundColor Yellow
    }
    else {
        # Eine Transaktion, je Flaeche zwei Updates, Zeilenzahl geprueft --
        # stimmt eine nicht, rollt alles zurueck. Guard ElementType/RepositoryType
        # haelt die Zeichnung (Repo 3, kennt keine Angrenzung) sicher draussen.
        $tx = $con.BeginTransaction()
        $zeilen = 0
        foreach ($zi in $zuAendern) {
            # ProjectUUID zusaetzlich zur (eindeutigen) UUID: Defense-in-depth,
            # die Projekt-Schranke steht damit IM Statement.
            if ($zi.MetaNeu) {
                $n1 = Befehl ("UPDATE BmElement SET AdjacentType=@a, MetaDesc=@m, StampEdit=GETDATE() " +
                        "WHERE UUID=@u AND ProjectUUID=@p AND ElementType=1 AND RepositoryType=1") @{ '@a' = $zielAdj; '@m' = $zi.MetaNeu; '@u' = $zi.ModellUUID; '@p' = $projektId } $tx
            }
            else {
                $n1 = Befehl ("UPDATE BmElement SET AdjacentType=@a, StampEdit=GETDATE() " +
                        "WHERE UUID=@u AND ProjectUUID=@p AND ElementType=1 AND RepositoryType=1") @{ '@a' = $zielAdj; '@u' = $zi.ModellUUID; '@p' = $projektId } $tx
            }
            # EC ohne StampEdit: byte-treu zum erprobten Einmalskript -- auch
            # die Software bewegte EC.StampEdit beim Fx-Nachziehen nicht (Kopf).
            $n2 = Befehl ("UPDATE BmElementEnergyConsulting SET CladdingSurface=@c, FxElementType=@f " +
                    "WHERE UUID=@u AND ProjectUUID=@p") @{ '@c' = $zielHuelle; '@f' = $zielFx; '@u' = $zi.ModellUUID; '@p' = $projektId } $tx
            if ($n1 -ne 1 -or $n2 -ne 1) {
                throw "Erwartet je 1 Update an $($zi.Name) ($($zi.Kurz)), waren $n1/$n2 -- Rollback."
            }
            $zeilen += $n1 + $n2
        }
        $tx.Commit(); $tx = $null
        Write-Host "   $($zuAendern.Count) Flaeche(n) umgestellt, $zeilen Zeilen." -ForegroundColor Green
    }

    # ------------------------------------------- Nebengebaeude in der Zeichnung
    # Nur noch ausfuehren -- alle Entscheidungen und Abbruchgruende sind oben
    # in der Bestandspruefung gefallen, bevor die Angrenzung geschrieben wurde.
    if ($MitNebengebaeude -and (($ngPlan -eq 'anlegen') -or ($ngPlan -eq 'entfernen'))) {
        Schritt "Nebengebaeude in der Zeichnung"
        $durchreich = @{}
        if ($Probelauf) { $durchreich['Probelauf'] = $true }
        if ($OhneSoftwarepruefung) { $durchreich['OhneSoftwarepruefung'] = $true }
        try {
            if ($ngPlan -eq 'entfernen') {
                & (Join-Path $PSScriptRoot 'Set-Nebengebaeude.ps1') -Projekt "$projektId" -Entfernen -Instanz $Instanz -Datenbank $Datenbank @durchreich
            }
            else {
                & (Join-Path $PSScriptRoot 'Set-Nebengebaeude.ps1') -Projekt "$projektId" -Wand $ngAnker.CadGuid -Art beheizt -Instanz $Instanz -Datenbank $Datenbank @durchreich
            }
        }
        catch {
            # Alle bekannten Abbruchgruende sind vorab geprueft; schlaegt der
            # Kindaufruf dennoch fehl (z. B. Silhouetten-Ableitung), muss die
            # Meldung sagen, was schon geschrieben ist.
            $hinweis = "An der Angrenzung ist nichts geschrieben worden."
            if ((-not $Probelauf) -and $zuAendern.Count) {
                $hinweis = ("Die Angrenzung (Schritt $nrAngrenzung) ist bereits geschrieben und bleibt bestehen -- " +
                            "ein Wiederanlauf dieses Werkzeugs ist idempotent und holt nur den Nebengebaeude-Teil nach.")
            }
            throw "Set-Nebengebaeude.ps1 schlug fehl: $($_.Exception.Message)`n$hinweis"
        }
    }

    # --------------------------------------------------------------- Kontrolle
    Schritt "Kontrolle"
    if ($Probelauf) {
        Write-Host "   [Probelauf] Nichts geschrieben." -ForegroundColor Yellow
    }
    elseif ($zuAendern.Count -eq 0) {
        Write-Host "   Unveraendert -- es gab nichts zu schreiben." -ForegroundColor Yellow
    }
    else {
        $ziele = @((Abfrage $sqlZiele $sqlParams).Rows | ForEach-Object { NeueZeile $_ })
        SetzeStatus $ziele
        $offen = ZeigeZiele $ziele
        if ($offen) { Write-Warning "$offen Flaeche(n) weichen nach dem Schreiben noch vom Ziel ab -- bitte pruefen." }
        else {
            $ueb = @($ziele | Where-Object { $_.Status -eq 'uebersprungen' }).Count
            if ($ueb) { Write-Host "`n   $($ziele.Count - $ueb) Flaeche(n) stehen auf '$zielWort', $ueb uebersprungen (unveraendert)." -ForegroundColor Green }
            else { Write-Host "`n   Alle $($ziele.Count) Flaeche(n) stehen auf '$zielWort'." -ForegroundColor Green }
        }
    }
}
finally {
    if ($tx) { $tx.Rollback() }
    $con.Close()
}
