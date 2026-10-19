# New-Fenster.ps1 -- ein Fenster oder eine Tuer in eine gezeichnete Wand setzen
#
# GRUNDLAGE
# HottCAD liest die Zeichnung aus BmData/CADXMLData zurueck und rechnet alles
# Abgeleitete selbst nach. Fuer Oeffnungen ist das besonders weitgehend: in
# BmElement und BmElementWindow steht bei JEDEM der 300 gezeichneten Fenster
# der Datenbank ueberall der Sentinel -987654321.99 -- Breite, Hoehe, Flaeche,
# Volumen, AF, Sturz, Bruestung. Die Software holt sich das aus der Zeichnung.
#
# FENSTER UND TUER SIND DASSELBE ELEMENT
# Beide sind ein <opening> unter <RoomElements>, unterschieden nur durch
# type="Window" / type="Door" (und type="Hole" fuer die blosse Oeffnung).
# ElementType: 3 Fenster, 2 Tuer, 13 Oeffnung.
#
# AUSGEZAEHLT AN 459 GEZEICHNETEN OEFFNUNGEN (23.08.2026), nicht geraten:
#
#   wall_side_index="2"             459 von 459
#   top_view="True"                 459 von 459
#   from_scan="False"               459 von 459
#   absolute_contour_points="False" 459 von 459
#   support_height="0"              459 von 459
#   groundplan_points               IMMER zeichengleich mit points
#   z aller Punkte                  IMMER 0 -- auch wenn die Wand auf z=0,25 liegt
#   BmElement                       Id=-1, SeqNum=-1, GeneratorType=2
#   CladdingSurface = 0             300 von 300 Fenstern. Ein Fenster ist NIE
#                                   Huellflaeche -- das traegt die Wand.
#
# DIE ZWEI VERWEISE AUF DIE WAND -- NICHT VERWECHSELN
#   XML  wall_ref / parentGuid  -> die CAD-GUID der Wand
#   SQL  BmElement.ParentUUID   -> die BmElement-UUID der Wand
# Das sind zwei verschiedene Kennungen desselben Bauteils. Dazu
# ParentElementType=1 und ParentElementRepositoryType=3.
#
# DIE WAND WEISS NICHTS VON IHREM FENSTER. Der Verweis ist einseitig; in keinem
# geprueften Projekt taucht die Fenster-GUID in der Wand-Zeichnung auf. Ein
# Fenster einzusetzen heisst also NICHT, die Wand anzufassen.
#
# DIE PUNKTREGEL (an 290 Fenstern und 150 Tueren geprueft)
# In Wandkoordinaten, b = Breite, t = Wandstaerke, u laengs, n quer:
#
#   Fenster, 8 Punkte:  p1=0/0  p2=b/0  p3=b/t  p4=0/t
#                       p5=0/0,065  p6=b/0,065  p7=0/T  p8=b/T   mit T=min(0,135;t)
#   Tuer,    6 Punkte:  p1..p4 wie oben, dann p5=0/-b  p6=0/0
#                       (der Aufschlagbogen, Laenge = Fluegelbreite)
#
# 278 von 290 Fenstern treffen das exakt. Die 9 Abweichler haben ALLE
# Wandstaerke 0,12 m -- dort rutscht die zweite Rahmenlinie auf die Innenseite.
# Daher min(0,135;t) und nicht 0,135. Bei 0,14 m gilt schon wieder 0,135.
#
# DER MARKER IST NICHT ABLEITBAR
# AF_Rechteck_125_0_200_0 sieht nach Hoehe und Breite in Zentimetern aus, und
# bei 260 von 459 stimmt das auch -- bei 199 nicht. Er gehoert zum
# KATALOGEINTRAG, nicht zum Einbaumass. Beim Neuanlegen erzeugen wir ihn aus
# den Massen; das ist der Fall, den die Software selbst auch so schreibt.
#
# GRENZE
# Nur form="formRechteck" in einer geraden Wand. Bogen, Dreieck, Dachfenster
# (Elternteil ist dann ein Dach, ElementType 5 -- 10 Faelle in der Datenbank),
# Rollladenkasten und Lichtschacht sind nicht untersucht.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    # Name der Wand, z. B. "AW 001".
    [Parameter(Mandatory = $true)][string]$Wand,
    # Geschoss, z. B. "EG" -- noetig, weil jedes Geschoss eigene AW 001..004 hat.
    [string]$Geschoss = '',
    # Abstand vom ERSTEN Wandpunkt entlang der Aussenkante, in Metern.
    [Parameter(Mandatory = $true)][double]$Abstand,
    [double]$Breite = 1.0,
    [double]$Hoehe = 1.25,
    # Bruestungshoehe ueber Fussboden. Bei einer Tuer immer 0.
    [double]$Bruestung = 0.85,
    [ValidateSet('Fenster', 'Tuer')][string]$Art = 'Fenster',
    # Konstruktion aus dem Projektkatalog, Teiltext genuegt.
    [string]$Konstruktion = '',
    [string]$Name = '',
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture
$NZ = [char]13 + [char]10
$SENTINEL = -987654321.99
$LEER = [guid]'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'

function Z([double]$w) { $w.ToString('R', $inv) }

# Zentimeter mit einer Nachkommastelle, Trenner als Unterstrich:
# 1,25 m -> "125_0"   0,735 m -> "73_5". Wie beim Wandmarker AW_36_5.
function Mass([double]$m) {
    "{0}_{1}" -f [Math]::Truncate($m * 100), [int]([Math]::Round($m * 1000) % 10)
}

# Eine Zeile Spalte fuer Spalte kopieren und dabei gezielt ueberschreiben.
# Dieselbe Technik wie in New-Innenwand.ps1: so stimmen auch die Spalten,
# die ich nicht kenne, und die Sentinels von selbst.
function Kopiere-Zeile {
    param($Con, $Tx, [string]$Tabelle, [hashtable]$Schluessel, [hashtable]$Neu, [switch]$NurZeigen)
    $wo = (($Schluessel.Keys | ForEach-Object { "[$_] = @k_$_" }) -join ' AND ')
    $c = $Con.CreateCommand(); if ($Tx) { $c.Transaction = $Tx }
    $c.CommandText = "SELECT * FROM [$Tabelle] WHERE $wo"
    foreach ($k in $Schluessel.Keys) { [void]$c.Parameters.AddWithValue("@k_$k", $Schluessel[$k]) }
    $tab = New-Object System.Data.DataTable
    $da = New-Object System.Data.SqlClient.SqlDataAdapter; $da.SelectCommand = $c
    [void]$da.Fill($tab)
    if ($tab.Rows.Count -ne 1) { throw "Vorlage in $Tabelle nicht eindeutig ($($tab.Rows.Count) Zeilen)." }
    $q = $tab.Rows[0]

    # SyncRowVersion fuehrt die Datenbank selbst.
    $spalten = @($tab.Columns | Where-Object { $_.ColumnName -ne 'SyncRowVersion' } | ForEach-Object { $_.ColumnName })
    foreach ($k in $Neu.Keys) { if ($spalten -notcontains $k) { throw "$Tabelle hat keine Spalte '$k'." } }

    if ($NurZeigen) {
        $zeig = @($Neu.Keys | Sort-Object | ForEach-Object { "$_=$($Neu[$_])" }) -join '  '
        Write-Host ("  + {0,-28} {1}" -f $Tabelle, $zeig)
        return
    }
    $i = $Con.CreateCommand(); $i.Transaction = $Tx
    $i.CommandText = "INSERT INTO [$Tabelle] (" + (($spalten | ForEach-Object { "[$_]" }) -join ', ') +
                     ") VALUES (" + (($spalten | ForEach-Object { "@$_" }) -join ', ') + ")"
    foreach ($s in $spalten) {
        $w = if ($Neu.ContainsKey($s)) { $Neu[$s] } else { $q[$s] }
        if ($null -eq $w) { $w = [DBNull]::Value }
        [void]$i.Parameters.AddWithValue("@$s", $w)
    }
    if ($i.ExecuteNonQuery() -ne 1) { throw "INSERT in $Tabelle schlug fehl." }
    Write-Host ("  + {0}" -f $Tabelle)
}

if (-not $OhneSoftwarepruefung) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

$istFenster = ($Art -eq 'Fenster')
if (-not $istFenster) { $Bruestung = 0 }

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    # --- Projekt ------------------------------------------------------------
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
    [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Count) Treffer. $($tp.Name -join ' | ')" }
    $prj = $tp[0]

    # --- Wand samt Zeichnung ------------------------------------------------
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT e.UUID, e.LongDesc, CAST(d.ClassValue AS nvarchar(max)) AS Xml " +
                     "FROM BmElement e JOIN BmElementWall w ON w.UUID = e.UUID " +
                     "JOIN BmData d ON d.ReferenceUUID = e.UUID AND d.LongDesc = 'CADXMLData' " +
                     "WHERE e.ProjectUUID = @p AND e.RepositoryType = 3 AND e.LongDesc = @w"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    [void]$c.Parameters.AddWithValue("@w", $Wand)
    $kandidaten = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $kandidaten += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1); Xml = $l.GetString(2) } }
    $l.Close()
    if ($kandidaten.Count -eq 0) { throw "Wand '$Wand' in '$($prj.Name)' nicht gefunden." }

    # Geschoss aufloesen: die floor-UUID der Zeichnung gegen BmFloor.LongDesc.
    if ($Geschoss) {
        $c = $con.CreateCommand()
        # Das floor-Attribut zeigt auf die GUID der GESCHOSSZEICHNUNG, nicht auf
        # BmFloor.UUID. Bei importierten Geschossen weichen beide ab -- der
        # Vergleich fand dann keine einzige Wand. Siehe Get-Wandsilhouette.ps1.
        $c.CommandText = "SELECT ISNULL(CASE WHEN CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) > 0 THEN LOWER(SUBSTRING(CAST(d.ClassValue AS nvarchar(max)), CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) + 13, 36)) ELSE NULL END, LOWER(CAST(f.UUID AS varchar(40)))) FROM BmFloor f LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.LongDesc = 'CADXMLData' WHERE f.ProjectUUID = @p AND f.LongDesc = @g"
        [void]$c.Parameters.AddWithValue("@p", $prj.Id)
        [void]$c.Parameters.AddWithValue("@g", $Geschoss)
        $fl = $c.ExecuteScalar()
        if (-not $fl) { throw "Geschoss '$Geschoss' gibt es in '$($prj.Name)' nicht." }
        $flText = ([string]$fl).ToLower()
        $kandidaten = @($kandidaten | Where-Object {
            [regex]::Match($_.Xml, 'floor="([^"]+)"').Groups[1].Value.ToLower() -eq $flText
        })
    }
    if ($kandidaten.Count -ne 1) {
        throw "Wand '$Wand' ist nicht eindeutig ($($kandidaten.Count) Treffer) -- gib -Geschoss an."
    }
    $wd = $kandidaten[0]

    # --- Wandgeometrie ------------------------------------------------------
    $wandCad = [regex]::Match($wd.Xml, 'GUID="([^"]+)"').Groups[1].Value
    $floor = [regex]::Match($wd.Xml, 'floor="([^"]+)"').Groups[1].Value
    $aussen = ([regex]::Match($wd.Xml, 'outer_wall="([^"]+)"').Groups[1].Value -eq 'True')
    $block = [regex]::Match($wd.Xml, '<points count="4">(.*?)</points>', 'Singleline').Groups[1].Value
    $pw = @([regex]::Matches($block, '<p>([^<]+)</p>') | ForEach-Object {
        $s = $_.Groups[1].Value -split ';'
        , @([double]::Parse($s[0], $inv), [double]::Parse($s[1], $inv))
    })
    if ($pw.Count -ne 4) { throw "Wand '$($wd.Name)' fuehrt $($pw.Count) Punkte statt 4." }

    # u laengs der Kante p1->p2, n quer zu p4 hin. NICHT p4-p1 als Normale
    # nehmen -- bei einer gehrten Aussenwand steht die schraeg.
    $vx = $pw[1][0] - $pw[0][0]; $vy = $pw[1][1] - $pw[0][1]
    $len = [Math]::Sqrt($vx * $vx + $vy * $vy)
    if ($len -lt 0.01) { throw "Wandkante ist entartet." }
    $ux = $vx / $len; $uy = $vy / $len
    $nx = -$uy; $ny = $ux
    $qx = $pw[3][0] - $pw[0][0]; $qy = $pw[3][1] - $pw[0][1]
    $t = $qx * $nx + $qy * $ny
    if ($t -lt 0) { $nx = -$nx; $ny = -$ny; $t = -$t }
    if ($t -lt 0.02) { throw "Wandstaerke aus der Zeichnung ist $t m -- das kann nicht stimmen." }

    if ($Abstand -lt 0) { throw "-Abstand darf nicht negativ sein." }
    if ($Abstand + $Breite -gt $len) {
        throw "Oeffnung reicht ueber die Wand hinaus: $Abstand + $Breite > $([Math]::Round($len,3)) m."
    }
    if ($Abstand -lt $t -or $Abstand + $Breite -gt $len - $t) {
        Write-Warning ("Die Oeffnung liegt naeher als die Wandstaerke ({0} m) an einer Ecke -- bei einer Gehrung kann sie dort aus der Wand ragen." -f (Z ([Math]::Round($t, 3))))
    }

    # --- Punkte -------------------------------------------------------------
    $ursprungX = $pw[0][0]; $ursprungY = $pw[0][1]
    function Pkt([double]$laengs, [double]$quer) {
        $x = $ursprungX + $ux * $laengs + $nx * $quer
        $y = $ursprungY + $uy * $laengs + $ny * $quer
        (Z $x) + ';' + (Z $y) + ';0'
    }
    $a1 = $Abstand; $a2 = $Abstand + $Breite
    if ($istFenster) {
        # NICHT $T nennen: PowerShell unterscheidet nicht zwischen $t und $T,
        # die Wandstaerke waere damit ueberschrieben. Genau das ist mir passiert.
        $rahmen2 = [Math]::Min(0.135, $t)
        $punkte = @(
            (Pkt $a1 0), (Pkt $a2 0), (Pkt $a2 $t), (Pkt $a1 $t),
            (Pkt $a1 0.065), (Pkt $a2 0.065), (Pkt $a1 $rahmen2), (Pkt $a2 $rahmen2)
        )
    }
    else {
        $punkte = @(
            (Pkt $a1 0), (Pkt $a2 0), (Pkt $a2 $t), (Pkt $a1 $t),
            (Pkt $a1 (-$Breite)), (Pkt $a1 0)
        )
    }

    # --- Konstruktion aus dem Projektkatalog --------------------------------
    #
    # Der U-Wert steht redundant an DREI Stellen, und alle drei muessen stimmen:
    #   1. u_value / u_valueDimGuid in der Zeichnung
    #   2. BmElement.UValue und ElementUValue
    #   3. TcBuildingElementDimension.UValue -- die Quelle, aus der 1 und 2 kommen
    # Wer nur eine Seite setzt, hinterlaesst ein Gebaeude, das sich selbst
    # widerspricht. Kopiert man die Zeile einer WAND, erbt das Fenster deren
    # Aufbau -- U=0,9 und AW_36_5 an einem Holzfenster. Genau das ist mir beim
    # ersten Lauf passiert.
    #
    # Die Kette: TcBasis.UId  <-  TcBuildingElementDimension.BasisUId
    #            BmElement.CatalogBasisUUID -> TcBasis.UId
    #            BmElement.CatalogDimUUID   -> TcBuildingElementDimension.UId
    $katId = ''; $katName = ''; $uWert = 0.0; $dimId = ''
    if ($Konstruktion) {
        $c = $con.CreateCommand()
        $c.CommandText = "SELECT b.UId, b.LongDesc, d.UId, d.UValue FROM TcBasis b " +
                         "LEFT JOIN TcBuildingElementDimension d ON d.BasisUId = b.UId " +
                         "WHERE b.ProjectUId = @p AND b.LongDesc LIKE @k"
        [void]$c.Parameters.AddWithValue("@p", $prj.Id)
        [void]$c.Parameters.AddWithValue("@k", "%$Konstruktion%")
        $tk = @(); $l = $c.ExecuteReader()
        while ($l.Read()) {
            $tk += [pscustomobject]@{
                Id = $l.GetGuid(0); Name = $l.GetString(1)
                Dim = $(if ($l.IsDBNull(2)) { '' } else { $l.GetGuid(2) })
                U = $(if ($l.IsDBNull(3)) { 0.0 } else { $l.GetDouble(3) })
            }
        }
        $l.Close()
        if ($tk.Count -ne 1) {
            throw ("Konstruktion '$Konstruktion' nicht eindeutig ($($tk.Count) Treffer):" + $NZ +
                   (($tk.Name | ForEach-Object { "  $_" }) -join $NZ))
        }
        if (-not $tk[0].Dim) { throw "Konstruktion '$($tk[0].Name)' hat keine Bemassungszeile -- ohne die gibt es keinen U-Wert." }
        $katId = $tk[0].Id; $katName = $tk[0].Name; $dimId = $tk[0].Dim; $uWert = $tk[0].U
    }

    # --- Namen und Marker ---------------------------------------------------
    if ($istFenster) { $praefix = $(if ($aussen) { 'AF' } else { 'IF' }) }
    else { $praefix = $(if ($aussen) { 'AT' } else { 'IT' }) }
    $marker = "{0}_Rechteck_{1}_{2}" -f $praefix, (Mass $Hoehe), (Mass $Breite)

    if (-not $Name) {
        $stamm = $(if ($istFenster) { 'F' } else { $praefix })
        $c = $con.CreateCommand()
        $c.CommandText = "SELECT LongDesc FROM BmElement WHERE ProjectUUID=@p AND LongDesc LIKE @m"
        [void]$c.Parameters.AddWithValue("@p", $prj.Id)
        [void]$c.Parameters.AddWithValue("@m", "$stamm %")
        $max = 0; $l = $c.ExecuteReader()
        while ($l.Read()) {
            $n = 0
            if ([int]::TryParse(($l.GetString(0) -replace "^$stamm\s*", ''), [ref]$n) -and $n -gt $max) { $max = $n }
        }
        $l.Close()
        $Name = "{0} {1:000}" -f $stamm, ($max + 1)
    }

    $c = $con.CreateCommand()
    $c.CommandText = "SELECT ISNULL(MAX(SortNum),0)+1 FROM BmElement WHERE ProjectUUID=@p"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $sortNum = [int]$c.ExecuteScalar()

    # --- Zeichnung ----------------------------------------------------------
    $neuId = [guid]::NewGuid()
    $cadId = [guid]::NewGuid()   # CAD-interne Kennung, NICHT die BmElement-UUID
    $jetzt = Get-Date

    $attr = @()
    $attr += 'name="' + $Name + '"'
    $attr += 'GUID="' + $cadId + '"'
    $attr += 'floor="' + $floor + '"'
    if ($katId) {
        $attr += 'u_value="' + (Z $uWert) + '"'
        $attr += 'u_valueDimGuid="' + $katId + '"'
        $attr += 'u_valueDimName="' + $katName + '"'
    }
    $attr += 'u_value_marker="' + $marker + '"'
    $attr += 'u_value_default_typo="True"'
    $attr += 'wall_ref="' + $wandCad + '"'
    $attr += 'wall_side_index="2"'
    $attr += 'parentGuid="' + $wandCad + '"'
    $attr += 'type="' + $(if ($istFenster) { 'Window' } else { 'Door' }) + '"'
    $attr += 'striking_left="True"'
    $attr += 'from_scan="False"'
    $attr += 'top_view="True"'
    $attr += 'form="formRechteck"'
    $attr += 'height="' + (Z $Hoehe) + '"'
    $attr += 'width="' + (Z $Breite) + '"'
    $attr += 'support_height="0"'
    $attr += 'sill="' + (Z $Bruestung) + '"'
    if ($istFenster) { $attr += 'depth="0.065"' }
    $attr += 'heating="' + $(if ($istFenster) { 'True' } else { 'False' }) + '"'
    $attr += 'shutterboxheight="0"'
    $attr += 'shutterboxguid="00000000-0000-0000-0000-000000000000"'
    $attr += 'absolute_contour_points="False"'
    $attr += 'light_well="True"'

    $pZeilen = ($punkte | ForEach-Object { '        <p>' + $_ + '</p>' }) -join $NZ
    $zeichnung = @(
        '<?xml version="1.0"?>',
        '<geometry>',
        '  <RoomElements count="1">',
        ('    <opening ' + ($attr -join ' ') + '>'),
        '      <shutterboxuvalue count="1">',
        '        <uv>0;</uv>',
        '      </shutterboxuvalue>',
        ('      <points count="' + $punkte.Count + '">'),
        $pZeilen,
        '      </points>',
        '      <repositories count="1">',
        ('        <val>' + $neuId + '</val>'),
        '      </repositories>',
        ('      <groundplan_points count="' + $punkte.Count + '">'),
        $pZeilen,
        '      </groundplan_points>',
        '    </opening>',
        '  </RoomElements>',
        '</geometry>'
    ) -join $NZ

    Write-Host "Projekt : $($prj.Name)"
    Write-Host ("Wand    : {0}   Geschoss {1}   Laenge {2} m   Staerke {3} m   {4}" -f $wd.Name, $Geschoss, (Z ([Math]::Round($len, 3))), (Z ([Math]::Round($t, 3))), $(if ($aussen) { 'Aussenwand' } else { 'Innenwand' }))
    Write-Host ("Neu     : {0}   {1}   {2} x {3} m   Bruestung {4} m   Abstand {5} m" -f $Name, $Art, (Z $Breite), (Z $Hoehe), (Z $Bruestung), (Z $Abstand))
    Write-Host ("Marker  : {0}{1}" -f $marker, $(if ($katId) { "   $katName  U=$(Z $uWert)" } else { '   (ohne Katalogeintrag)' }))
    Write-Host ""
    $punkte | ForEach-Object { Write-Host "  $_" }
    Write-Host ""

    $tx = $(if ($Probelauf) { $null } else { $con.BeginTransaction() })
    try {
        # BmElement, Dimensioning, EnergyConsulting: Kopie der Wand desselben
        # Projekts. An Test123 nachgemessen -- zwischen Wand und Fenster
        # unterscheiden sich nur die Kennungen und die Eltern-Angaben.
        $gem = @{
            UUID = $neuId; GId = $neuId; LongDesc = $Name; ShortDesc = $Name
            SortNum = $sortNum; StampCreate = $jetzt; StampEdit = $jetzt
        }
        $elem = $gem.Clone()
        $elem['ElementType'] = $(if ($istFenster) { 3 } else { 2 })
        $elem['ParentUUID'] = $wd.Id
        $elem['ParentElementType'] = 1
        $elem['ParentElementRepositoryType'] = 3
        $elem['AddInsOutSideUUID'] = $LEER
        foreach ($s in 'Width', 'Height', 'Thickness', 'GrossArea', 'NetArea', 'Volume', 'Slope') {
            $elem[$s] = $SENTINEL
        }
        # Katalogbezug: nicht den der Wand stehen lassen. GroupType ist die
        # Bauteilart -- 1 Wand, 2 Tuer, 3 Fenster (an 432 Elementen mit
        # Katalogbezug ausgezaehlt). Ohne -Konstruktion bleibt alles auf dem
        # Sentinel; das ist die zweite, ebenfalls gueltige Betriebsart.
        if ($katId) {
            $elem['UValue'] = $uWert; $elem['ElementUValue'] = $uWert
            $elem['UValueMarker'] = $marker
            $elem['CatalogBasisUUID'] = $katId
            $elem['CatalogDimUUID'] = $dimId
            $elem['CatalogBasisElementType'] = 2
            $elem['CatalogBasisGroupType'] = $(if ($istFenster) { 3 } else { 2 })
        }
        else {
            $elem['UValue'] = $SENTINEL; $elem['ElementUValue'] = $SENTINEL
            $elem['UValueMarker'] = ''
            $elem['CatalogBasisUUID'] = $LEER
            $elem['CatalogDimUUID'] = $LEER
            $elem['CatalogBasisElementType'] = 0
            $elem['CatalogBasisGroupType'] = 0
        }
        Kopiere-Zeile $con $tx 'BmElement' @{ UUID = $wd.Id } $elem -NurZeigen:$Probelauf

        Kopiere-Zeile $con $tx 'BmElementDimensioning' @{ UUID = $wd.Id } $gem -NurZeigen:$Probelauf

        $ec = $gem.Clone(); $ec['CladdingSurface'] = 0
        Kopiere-Zeile $con $tx 'BmElementEnergyConsulting' @{ UUID = $wd.Id } $ec -NurZeigen:$Probelauf

        # Die Bauart-Tabelle gibt es in diesem Projekt noch nicht als Vorlage --
        # sie wird Spalte fuer Spalte aus den ausgezaehlten Werten aufgebaut.
        $bauart = [ordered]@{
            UUID = $neuId; Id = -1; SortNum = $sortNum; ShortDesc = $Name; LongDesc = $Name
            GeneratorType = 2; SyncType = 2; StampCreate = $jetzt; StampEdit = $jetzt
            ProjectUUID = $prj.Id; GId = $neuId; MId = $LEER
            SelfShadingD1 = $SENTINEL; SelfShadingC1 = $SENTINEL; SelfShadingD2 = $SENTINEL
            SelfShadingC2 = $SENTINEL; SelfShadingB1 = $SENTINEL; SelfShadingB2 = $SENTINEL
            SelfShadingF1 = $SENTINEL; SelfShadingF2 = $SENTINEL
            ObjectShadingD1 = $SENTINEL; ObjectShadingH1 = $SENTINEL
            InstallationDepth = $SENTINEL
        }
        if ($istFenster) {
            $bauart['WindowType'] = 0; $bauart['WindowIsoType'] = 0
            $bauart['FractionOfFrame'] = 30
            $bauart['AF'] = $SENTINEL; $bauart['HeadHeight'] = $SENTINEL; $bauart['SillHeight'] = $SENTINEL
            $bauart['GValue'] = $SENTINEL; $bauart['ShadingCoefficient'] = $SENTINEL
            $bauart['OpeningFace'] = $SENTINEL; $bauart['ApertureDimension'] = $SENTINEL
            $bauart['WindowIsOpen'] = $false
            $bauart['WindowPanelPositionType'] = 0; $bauart['WindowPanelOperationType'] = 0
            $tabelle = 'BmElementWindow'
        }
        else {
            $bauart['DoorType'] = 0; $bauart['DoorSealType'] = 0; $bauart['DoorIsOpen'] = $false
            $bauart['LeafWidth'] = $SENTINEL; $bauart['Rise'] = $SENTINEL
            $bauart['DoorPanelOperationType'] = 0; $bauart['DoorPanelPositionType'] = 0
            $tabelle = 'BmElementDoor'
        }

        if ($Probelauf) {
            Write-Host ("  + {0,-28} {1}" -f $tabelle, (($bauart.Keys | ForEach-Object { "$_=$($bauart[$_])" }) -join '  '))
        }
        else {
            $i = $con.CreateCommand(); $i.Transaction = $tx
            $i.CommandText = "INSERT INTO [$tabelle] (" + (($bauart.Keys | ForEach-Object { "[$_]" }) -join ', ') +
                             ") VALUES (" + (($bauart.Keys | ForEach-Object { "@$_" }) -join ', ') + ")"
            foreach ($k in $bauart.Keys) { [void]$i.Parameters.AddWithValue("@$k", $bauart[$k]) }
            if ($i.ExecuteNonQuery() -ne 1) { throw "INSERT in $tabelle schlug fehl." }
            Write-Host ("  + {0}" -f $tabelle)
        }

        # BmData.UUID ist die Kennung der Datenart und bleibt stehen.
        Kopiere-Zeile $con $tx 'BmData' @{ ReferenceUUID = $wd.Id; LongDesc = 'CADXMLData' } @{
            ReferenceUUID = $neuId; ClassValue = $zeichnung; StampCreate = $jetzt; StampEdit = $jetzt
        } -NurZeigen:$Probelauf

        if ($Probelauf) { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
        else { $tx.Commit(); Write-Host "`n$Art '$Name' angelegt (BmElement $neuId)." -ForegroundColor Green }
    }
    catch { if ($tx) { $tx.Rollback() }; throw }
}
finally { $con.Close() }
