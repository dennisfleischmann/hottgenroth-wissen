# Setze-Schichttypen.ps1 -- Baustoffgruppe, Schichtart und Katalogpfad auf
# Schichten setzen, die schon im Bauteilkatalog eines Projekts stehen.
#
# WOZU
# add_hottgenroth_bauteile kann Bauteile nur ANLEGEN; ein zweiter Aufruf legt
# Dubletten an. Fuer einen Aufbau, der ohne Gruppe eingespielt wurde, gab es
# damit keinen Weg zurueck -- und ohne Gruppe wird die Schicht im Schichtaufbau
# nicht grau, sondern violett wie "Sonstiges": der fehlende Wert sieht aus wie
# ein gesetzter. (Hsetu.FW.Calculations.CS GraphHelper.BaustoffFarbe hat keinen
# Zweig fuer mgdNone; die 0 faellt in den Default und bekommt 136/81/136,
# dieselbe Farbe wie Gruppe 8 und 9. Grau ist Gruppe 2.)
#
# Dieses Skript setzt genau die fuenf Felder, die dabei fehlen, und laesst alles
# andere in Ruhe -- lambda, Dicke, Rohdichte, Kapazitaet und die mu-Werte werden
# NICHT angefasst. Der U-Wert aendert sich also nicht; was sich aendert, ist die
# Farbe, die Einordnung im Materialbaum und die Behandlung der Daemmschichten.
#
# ZWEI STELLEN, NICHT EINE
# Die Software liest die Schicht aus TcBuildingElementDimensionLayer UND aus dem
# Legacy-Block TcBuildingElementDimension.ElementMeta (G1Sn=...). Feld 6 der
# G1S-Zeile ist die Materialgruppe, Feld 12 der Katalogpfad. Wer nur die
# Layer-Zeilen setzt, hinterlaesst zwei Quellen, die sich widersprechen.
# Deshalb werden beide geschrieben, in einer Transaktion.
#
# WAS GEPRUEFT WIRD, BEVOR GESCHRIEBEN WIRD
#   1. Das Projekt muss eindeutig sein.
#   2. JEDE Schicht des Projekts muss in der Zuordnung stehen. Eine Luecke
#      bricht ab, statt die Haelfte zu setzen -- halb eingefaerbt ist
#      schlimmer als gar nicht.
#   3. Jede G1S-Zeile im ElementMeta muss sich einer Schicht zuordnen lassen.
#   4. Nach dem Schreiben wird aus der Datenbank zurueckgelesen, nicht aus dem
#      Speicher. Stimmt etwas nicht, wird zurueckgerollt.
#
# OHNE -Schreiben wird nur gezeigt, was geschehen wuerde. Das ist die Vorgabe.
#
# Die Software muss ZU sein -- sie liest den Katalog beim Laden und merkt von
# Aenderungen im laufenden Betrieb nichts; beim Speichern schreibt sie ihren
# Stand zurueck. Ein Prozess ohne Fenster zaehlt auch.
#
#   .\Setze-Schichttypen.ps1 -Projekt 'Klenke' -Zuordnung .\zuordnung-klenke.json
#   .\Setze-Schichttypen.ps1 -Projekt 'Klenke' -Zuordnung .\zuordnung-klenke.json -Schreiben
#
# Die Zuordnung ist eine JSON-Datei; Schluessel ist der Schichtname, wie er in
# der Datenbank steht:
#
#   { "schichten": {
#       "Zementestrich": { "gruppe": "putz_estrich", "katalogpfad": "1.4.1" },
#       "Holzschalung":  { "gruppe": "holz" },
#       "Mineralwolle":  { "gruppe": "daemmung", "schichtart": "daemmschicht" } } }
#
# gruppe, schichtart und katalogpfad heissen genau wie im Werkzeug
# add_hottgenroth_bauteile (HottgenrothBauteilImport). Fehlt die gruppe, wird
# die Schicht uebersprungen -- "keine Angabe" bleibt "keine Angabe".

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Zuordnung,
    [switch]$Schreiben,
    [string]$Sicherung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

# --- Die Vokabeln, identisch zu HottgenrothBauteilImport --------------------
$GRUPPEN = @{
    'putz_estrich'     = 1
    'beton'            = 2
    'platte'           = 3
    'mauerwerk'        = 4
    'daemmung'         = 5
    'holz'             = 6
    'belag_abdichtung' = 7
    'sonstiges'        = 8
    'systemplatte'     = 9
}

$SCHICHTARTEN = @{
    'normal'                 = @{ LayerType = 0; MaterialType = 0 }
    'daemmschicht'           = @{ LayerType = 3; MaterialType = 1 }
    'luftschicht'            = @{ LayerType = 0; MaterialType = 10 }
    'belueftete_luftschicht' = @{ LayerType = 2; MaterialType = 0 }
}

# Holz traegt seinen Materialtyp an der Gruppe: 5.289 von 5.381 Schichten der
# Gruppe 6 in dieser Datenbank tragen MaterialType 12, und kein Satz einer
# anderen Gruppe tut es.
$MATERIALTYPEN = @{ 6 = 12 }

function Loese-Schichtart($eintrag, $gruppe, $name) {
    $wort = [string] $eintrag.schichtart
    if ($wort) { $wort = $wort.Trim().ToLowerInvariant() }

    if ($wort -and -not $SCHICHTARTEN.ContainsKey($wort)) {
        throw "Schicht '$name': unbekannte Schichtart '$wort'. Erlaubt: $(($SCHICHTARTEN.Keys | Sort-Object) -join ', ')."
    }

    # Eine Daemmung IST eine Daemmschicht: 4.932 von 5.042 Schichten der
    # Gruppe 5 tragen LayerType 3, und LayerType 0 mit MaterialType 1 kommt
    # hier gar nicht vor. Wer es anders will, schreibt 'normal' hin.
    if (-not $wort) { $wort = if ($gruppe -eq $GRUPPEN['daemmung']) { 'daemmschicht' } else { 'normal' } }

    $art = @{ LayerType = $SCHICHTARTEN[$wort].LayerType; MaterialType = $SCHICHTARTEN[$wort].MaterialType }

    # Nur ergaenzen, nie ueberschreiben.
    if ($art.MaterialType -eq 0 -and $MATERIALTYPEN.ContainsKey($gruppe)) {
        $art.MaterialType = $MATERIALTYPEN[$gruppe]
    }

    return $art
}

# --- Zuordnung einlesen und in Zahlen uebersetzen ---------------------------
if (-not (Test-Path $Zuordnung)) { throw "Zuordnung '$Zuordnung' gibt es nicht." }

$json = Get-Content $Zuordnung -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $json.schichten) { throw "In '$Zuordnung' fehlt das Objekt 'schichten'." }

$soll = @{}
foreach ($eigenschaft in $json.schichten.PSObject.Properties) {
    $name = $eigenschaft.Name
    $e = $eigenschaft.Value

    $wort = [string] $e.gruppe
    if ($wort) { $wort = $wort.Trim().ToLowerInvariant() }

    if (-not $wort) {
        # Keine Gruppe heisst: diese Schicht bleibt, wie sie ist.
        $soll[$name] = $null
        continue
    }

    if (-not $GRUPPEN.ContainsKey($wort)) {
        throw "Schicht '$name': unbekannte Gruppe '$wort'. Erlaubt: $(($GRUPPEN.Keys | Sort-Object) -join ', ')."
    }

    $gruppe = $GRUPPEN[$wort]
    $art = Loese-Schichtart $e $gruppe $name

    $pfad = [string] $e.katalogpfad
    if ($pfad) { $pfad = $pfad.Trim() } else { $pfad = '' }

    if ($pfad) {
        if ($pfad -notmatch '^\d+(\.\d+)*$') {
            throw "Schicht '$name': katalogpfad '$pfad' ist kein Pfad aus Ziffern und Punkten."
        }
        $erste = [int] ($pfad -split '\.')[0]
        # Der Baum hat neun Wurzeln. Dass die erste Ziffer der Gruppe
        # widersprechen DARF, ist gemessen: 1.912 von 23.353 Schichten dieser
        # Datenbank tun es, allein 1.258-mal Pfad 6.x in Gruppe 3 (OSB steht
        # unter Holz und ist als Bauplatte eingefaerbt).
        if ($erste -lt 1 -or $erste -gt 9) {
            throw "Schicht '$name': katalogpfad '$pfad' beginnt mit $erste; der Materialbaum hat neun Wurzeln."
        }
    }

    $soll[$name] = [pscustomobject]@{
        Gruppe       = $gruppe
        GruppeWort   = $wort
        LayerType    = $art.LayerType
        MaterialType = $art.MaterialType
        Pfad         = $pfad
    }
}

# --- Verbindung -------------------------------------------------------------
$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
$tx = $null

function Abfrage($sql, [hashtable]$p = @{}, $tx = $null) {
    $c = $con.CreateCommand()
    $c.CommandText = $sql
    $c.CommandTimeout = 180
    if ($tx) { $c.Transaction = $tx }
    foreach ($k in $p.Keys) { [void] $c.Parameters.AddWithValue($k, $p[$k]) }
    $t = New-Object System.Data.DataTable
    [void] (New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($t)
    # Das Komma ist Pflicht: ohne es loest PowerShell die DataTable in ihre
    # Zeilen auf, und $t.Rows.Count ist danach 0 statt der Satzzahl - ein
    # leeres Ergebnis, das aussieht wie "nicht gefunden".
    return , $t
}

function Befehl($sql, [hashtable]$p, $tx) {
    $c = $con.CreateCommand()
    $c.CommandText = $sql
    $c.CommandTimeout = 180
    $c.Transaction = $tx
    foreach ($k in $p.Keys) { [void] $c.Parameters.AddWithValue($k, $p[$k]) }
    return $c.ExecuteNonQuery()
}

try {
    # --- 1. Projekt eindeutig finden ---------------------------------------
    $leer = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref] $leer)) {
        $t = Abfrage 'SELECT UUID, LongDesc FROM PrProject WHERE UUID = @p' @{ '@p' = [guid] $Projekt }
    } else {
        $t = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE '%' + @p + '%'" @{ '@p' = $Projekt }
    }
    if ($t.Rows.Count -eq 0) { throw "Kein Projekt zu '$Projekt'." }
    if ($t.Rows.Count -gt 1) {
        throw ("'$Projekt' trifft $($t.Rows.Count) Projekte: " +
               (($t.Rows | ForEach-Object { $_.LongDesc }) -join ' | ') + " - genauer angeben.")
    }
    $projGuid = [guid] $t.Rows[0]['UUID']
    $projName = [string] $t.Rows[0]['LongDesc']
    "Projekt: $projName"
    ""

    # --- 2. Alle Schichten des Projekts holen ------------------------------
    $schichten = Abfrage @"
SELECT l.UId, l.DimensionUId, l.SortNum, l.LongDesc AS Schicht, b.LongDesc AS Bauteil,
       l.MaterialGroupType, l.LayerType, l.MaterialType, l.ShortDesc,
       l.ThermalConductivity, l.Thickness
FROM TcBasis b
JOIN TcBuildingElementDimension d ON d.BasisUId = b.UId
JOIN TcBuildingElementDimensionLayer l ON l.DimensionUId = d.UId
WHERE b.ProjectUId = @p
ORDER BY b.LongDesc, l.SortNum
"@ @{ '@p' = $projGuid }

    if ($schichten.Rows.Count -eq 0) { throw "Das Projekt hat keine Schichten im Katalog." }
    "$($schichten.Rows.Count) Schichten im Katalog, $(@($schichten.Rows | Group-Object Schicht).Count) verschiedene Baustoffe."
    ""

    # --- 3. Luecken in der Zuordnung sind ein Abbruch, kein Hinweis --------
    $fehlend = @($schichten.Rows | ForEach-Object { [string] $_.Schicht } | Sort-Object -Unique |
                 Where-Object { -not $soll.ContainsKey($_) })
    if ($fehlend) {
        throw ("In der Zuordnung fehlen $($fehlend.Count) Baustoffe - nichts geschrieben:`n  " +
               ($fehlend -join "`n  "))
    }

    # --- 4. Zeigen, was geschehen wuerde -----------------------------------
    "{0,-52} {1,-7} {2,-12} {3,-12} {4}" -f 'Baustoff', 'Gruppe', 'LayerType', 'MatType', 'Pfad'
    "{0,-52} {1,-7} {2,-12} {3,-12} {4}" -f ('-' * 52), '-------', '------------', '------------', '--------'
    $zuSetzen = 0
    foreach ($g in ($schichten.Rows | Group-Object Schicht | Sort-Object Name)) {
        $s = $soll[$g.Name]
        $ist = $g.Group[0]
        if ($null -eq $s) {
            "{0,-52} {1,-7} {2,-12} {3,-12} {4}" -f $g.Name.PadRight(52).Substring(0, 52), '(bleibt)', '', '', ''
            continue
        }
        $gAlt = [int] $ist.MaterialGroupType; $lAlt = [int] $ist.LayerType; $mAlt = [int] $ist.MaterialType
        $pAlt = [string] $ist.ShortDesc
        "{0,-52} {1,-7} {2,-12} {3,-12} {4}" -f `
            $g.Name.PadRight(52).Substring(0, 52),
            "$gAlt -> $($s.Gruppe)",
            "$lAlt -> $($s.LayerType)",
            "$mAlt -> $($s.MaterialType)",
            $(if ($s.Pfad) { "'$pAlt' -> '$($s.Pfad)'" } else { '(leer)' })
        $zuSetzen += $g.Count
    }
    ""
    "$zuSetzen von $($schichten.Rows.Count) Schichten werden gesetzt."

    if (-not $Schreiben) {
        ""
        "PROBELAUF - nichts geschrieben. Zum Schreiben denselben Aufruf mit -Schreiben."
        return
    }

    # --- 4a. Die Software muss ZU sein -------------------------------------
    # Oben im Kopf stand diese Regel von Anfang an, erzwungen wurde sie nicht --
    # und genau das ist am 03.10.2026 schiefgegangen: waehrend der Katalog offen
    # war, hat Energie.exe ein schichtloses Bauteil neu durchgerechnet und seinen
    # U-Wert von 0,900 auf 5,882 gesetzt (ohne Schichten bleibt nur Rsi + Rse).
    # Ein Kommentar haelt keinen Prozess auf.
    #
    # Die Liste ist nicht geraten, sondern aus C:\Program Files\HSETU abgelesen:
    # Energie.exe ist der EE-Berater (zweimal, Energieberater2022 und
    # EnergieberaterPlaner), dazu halten Simulation.exe, RenovationAssistant.exe
    # (Optimus), ETUSimulation.exe, Viewer.exe und MeinSanierungsfahrplan.exe
    # Projekte derselben Datenbank. HsetuServices.exe NICHT: das ist der
    # Dienst, der immer laeuft.
    #
    # Ein Fenster zu heisst nicht Prozess beendet -- einmal lief eine verwaiste
    # Instanz 34 Stunden und hat jeden Schreibvorgang rueckgaengig gemacht.
    # Geprueft wird Name UND Pfad: "Viewer" und "Simulation" heissen auch
    # Programme anderer Hersteller, und eine Sperre, die ohne Grund zuschlaegt,
    # wird irgendwann umgangen. Laesst sich der Pfad nicht lesen (fremder
    # Benutzer, fehlendes Recht), wird gesperrt -- im Zweifel nicht schreiben.
    $schreiber = 'Energie', 'Simulation', 'RenovationAssistant', 'ETUSimulation',
                 'Viewer', 'MeinSanierungsfahrplan', 'hottcad'
    $offen = @(Get-Process -ErrorAction SilentlyContinue |
               Where-Object { $schreiber -contains $_.ProcessName } |
               Where-Object {
                   $pfad = try { $_.Path } catch { $null }
                   -not $pfad -or $pfad -like '*\HSETU\*'
               })
    if ($offen) {
        throw ("Erst die Software schliessen - es laeuft: " +
               (($offen | ForEach-Object {
                   "$($_.ProcessName) (PID $($_.Id), seit $($_.StartTime.ToString('dd.MM. HH:mm')))"
                 }) -join ', ') +
               ". Sie haelt den Katalog im Speicher und schreibt ihren Stand beim Schliessen zurueck. " +
               "Ein Fenster zu heisst nicht Prozess beendet - im Zweifel im Task-Manager beenden.")
    }

    # --- 5. Sicherung der betroffenen Zeilen -------------------------------
    # Neben die Datenbanksicherung von Sichere-Projektdatenbank.ps1, nicht neben
    # die Zuordnung: der Rueckweg gehoert zu den Rettungsdaten und nicht in ein
    # Git-Repository, in dem er beim naechsten Blick auf den Status stoert.
    if (-not $Sicherung) {
        $ablage = Join-Path $env:USERPROFILE 'Hottgenroth-Rettung'
        if (-not (Test-Path $ablage)) { [void] (New-Item -ItemType Directory -Path $ablage) }
        $Sicherung = Join-Path $ablage ("schichttypen-vorher-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    }
    $meta = Abfrage @"
SELECT d.UId, d.ElementMeta
FROM TcBasis b JOIN TcBuildingElementDimension d ON d.BasisUId = b.UId
WHERE b.ProjectUId = @p
"@ @{ '@p' = $projGuid }

    @{
        projekt   = $projName
        gestellt  = (Get-Date -Format 'o')
        schichten = @($schichten.Rows | ForEach-Object {
            @{ uid = [string] $_.UId; schicht = [string] $_.Schicht
               gruppe = [int] $_.MaterialGroupType; layerType = [int] $_.LayerType
               materialType = [int] $_.MaterialType; shortDesc = [string] $_.ShortDesc }
        })
        elementMeta = @($meta.Rows | ForEach-Object {
            @{ uid = [string] $_.UId; meta = [string] $_.ElementMeta }
        })
    } | ConvertTo-Json -Depth 6 | Set-Content -Path $Sicherung -Encoding UTF8
    "Sicherung: $Sicherung"
    ""

    # --- 6. Schreiben, in einer Transaktion --------------------------------
    $tx = $con.BeginTransaction()

    $gesetzt = 0
    foreach ($r in $schichten.Rows) {
        $s = $soll[[string] $r.Schicht]
        if ($null -eq $s) { continue }
        $gesetzt += Befehl @"
UPDATE TcBuildingElementDimensionLayer
   SET MaterialGroupType = @g, LayerType = @l, MaterialType = @m,
       ShortDesc = @sd, StampEdit = GETDATE()
 WHERE UId = @u
"@ @{ '@g' = $s.Gruppe; '@l' = $s.LayerType; '@m' = $s.MaterialType
      '@sd' = $s.Pfad; '@u' = [guid] $r.UId } $tx
    }
    "  $gesetzt Schichtzeilen gesetzt."

    # --- 7. Den Legacy-Block mitziehen -------------------------------------
    # Feld 6 der G1S-Zeile ist die Materialgruppe, Feld 12 der Katalogpfad.
    # Alles andere in der Zeile bleibt Zeichen fuer Zeichen stehen - die
    # Software rechnet daraus, und die Zahlenformate sind eigenwillig
    # (Dicke ohne Nachkommanullen, der Rest mit sechs).
    $metaGesetzt = 0
    foreach ($m in $meta.Rows) {
        $alt = [string] $m.ElementMeta
        if (-not $alt) { continue }

        $zeilen = $alt -split "(`r`n|`n|`r)"
        $neu = New-Object System.Collections.Generic.List[string]
        $beruehrt = $false

        foreach ($z in $zeilen) {
            if ($z -notmatch '^G\d+S\d+=') { $neu.Add($z); continue }

            $trenner = $z.IndexOf('=')
            $kopf = $z.Substring(0, $trenner + 1)
            $felder = $z.Substring($trenner + 1) -split '\|'

            if ($felder.Count -lt 12) {
                throw "ElementMeta-Zeile mit nur $($felder.Count) Feldern: '$z' - Deutung stimmt nicht, nichts geschrieben."
            }

            $name = $felder[0]
            if (-not $soll.ContainsKey($name)) {
                throw "ElementMeta nennt den Baustoff '$name', der in der Zuordnung fehlt - nichts geschrieben."
            }
            $s = $soll[$name]
            if ($null -eq $s) { $neu.Add($z); continue }

            $felder[5] = [string] $s.Gruppe      # Feld 6: Materialgruppe
            $felder[11] = $s.Pfad                # Feld 12: Katalogpfad
            $neu.Add($kopf + ($felder -join '|'))
            $beruehrt = $true
        }

        if (-not $beruehrt) { continue }

        $metaNeu = $neu -join ''
        $metaGesetzt += Befehl @"
UPDATE TcBuildingElementDimension SET ElementMeta = @em, StampEdit = GETDATE() WHERE UId = @u
"@ @{ '@em' = $metaNeu; '@u' = [guid] $m.UId } $tx
    }
    "  $metaGesetzt ElementMeta-Bloecke mitgezogen."
    ""

    # --- 8. Gegenprobe aus der Datenbank, nicht aus dem Speicher -----------
    $nach = Abfrage @"
SELECT COUNT(*) AS Gesamt,
       SUM(CASE WHEN l.MaterialGroupType = 0 THEN 1 ELSE 0 END) AS OhneGruppe
FROM TcBasis b
JOIN TcBuildingElementDimension d ON d.BasisUId = b.UId
JOIN TcBuildingElementDimensionLayer l ON l.DimensionUId = d.UId
WHERE b.ProjectUId = @p
"@ @{ '@p' = $projGuid } $tx

    $sollenBleiben = @($soll.Keys | Where-Object { $null -eq $soll[$_] }).Count
    $offen = [int] $nach.Rows[0]['OhneGruppe']
    "Gegenprobe: $([int] $nach.Rows[0]['Gesamt']) Schichten, $offen noch ohne Gruppe."

    if ($offen -gt 0 -and $sollenBleiben -eq 0) {
        throw "Es stehen noch $offen Schichten ohne Gruppe da, obwohl die Zuordnung alle nennt - zurueckgerollt."
    }

    $tx.Commit(); $tx = $null
    ""
    "Geschrieben. Die Software zeigt den neuen Stand erst nach einem Neustart -"
    "sie liest den Katalog beim Laden."
}
finally {
    if ($tx) { try { $tx.Rollback(); "ZURUECKGEROLLT - nichts geaendert." } catch {} }
    $con.Close()
}
