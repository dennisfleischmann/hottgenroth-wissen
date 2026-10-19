# New-Raum.ps1 — einen Raum aus einem Grundrisspolygon anlegen
#
# WOFUER
# HottCAD erzeugt Modellbauteile (RepositoryType 1) nur dort, wo Raeume die
# gezeichneten Waende begrenzen. Ein Gebaeudeteil, der gezeichnet ist, aber keine
# Raeume traegt, fehlt in der 18599-Rechnung vollstaendig. Dieses Skript legt
# die fehlenden Raeume von aussen an; die Polygone liefert z. B. die
# Fluetfuellung ueber die Zeichnungswaende (raeume-finden.ps1).
#
# WIE
# Ein Raum sind fuenf Zeilen (bauteile/docs/hottgenroth-raum-zone-sql.md, Abschn. 4):
#   BmRoom -> BmRoomData -> BmBuildingSpace -> PdProfileReference -> BmData (CAD-XML)
# Alle werden von einem Vorlagenraum DESSELBEN PROJEKTS kopiert (generisch, alle
# Spalten), danach werden Schluessel, Geometrie, Stempel und XML neu gesetzt.
# Abgeleitetes (Bauteilverweise, PmSpace) ergaenzt HottCAD beim naechsten Oeffnen
# selbst — belegt am 17.08.2026 (Memory "raeume-sind-anlegbar").
#
# Das Raumprofil (PdProfileReference) wird nur gesetzt, wenn im Projekt schon ein
# Raum derselben Raumart eines traegt. Grund: HottCAD setzt RoomType beim
# Speichern aus dem Profil zurueck (UpdateRoomsWithSameProfiles) — ein falsches
# Profil ueberschreibt den Stempel, keines laesst ihn stehen.
#
# Beispiel:
#   .\New-Raum.ps1 -Projekt <GUID> -Geschoss EG -Name Wohnraum -Raumart 1 -Status beheizt `
#       -Polygon "-3.459;4.419 2.0;4.419 2.0;12.469 -3.459;12.469" -Zone -Probelauf

param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Geschoss,
    # Eckpunkte "x;y x;y ..." in Metern, Reihenfolge beliebig umlaufend, ohne Wiederholung des ersten Punkts.
    [Parameter(Mandatory = $true)][string]$Polygon,
    [Parameter(Mandatory = $true)][string]$Name,
    [int]$Raumart = 1,
    [ValidateSet('beheizt', 'unbeheizt')][string]$Status = 'beheizt',
    [double]$Temperatur = [double]::NaN,
    # Lichte Hoehe; leer = wie der Vorlagenraum des Geschosses (sonst FloorHeight - 0,2).
    [double]$Hoehe = [double]::NaN,
    # In die (einzige) DIN-18599-Zone des Projekts haengen.
    [switch]$Zone,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData",
    [switch]$Probelauf
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture

$katalog = @{
    1  = @{ Mrt = 'mrtLiving';         Luft = 0.5; Ht = 1; T = 20; Bez = 'Wohnraum' }
    2  = @{ Mrt = 'mrtSleeping';       Luft = 0.5; Ht = 1; T = 20; Bez = 'Schlafen' }
    3  = @{ Mrt = 'mrtChild';          Luft = 0.5; Ht = 1; T = 20; Bez = 'Kind' }
    4  = @{ Mrt = 'mrtKitchen';        Luft = 0.5; Ht = 1; T = 20; Bez = 'Küche' }
    5  = @{ Mrt = 'mrtEating';         Luft = 0.5; Ht = 1; T = 20; Bez = 'Essen' }
    6  = @{ Mrt = 'mrtHall';           Luft = 0.0; Ht = 4; T = 15; Bez = 'Flur' }
    11 = @{ Mrt = 'mrtBath';           Luft = 0.5; Ht = 1; T = 24; Bez = 'Bad/Dusche/Umkleideraum' }
    23 = @{ Mrt = 'mrtBasement';       Luft = 0.0; Ht = 2; T = 10; Bez = 'Kellerraum' }
    24 = @{ Mrt = 'mrtCentralHeating'; Luft = 0.0; Ht = 1; T = 15; Bez = 'Heizungsaufstellraum' }
    25 = @{ Mrt = 'mrtRoof';           Luft = 0.0; Ht = 2; T = 7; Bez = 'Dachraum' }
    34 = @{ Mrt = 'mrtStore';          Luft = 0.0; Ht = 1; T = 15; Bez = 'Abstellraum' }
    42 = @{ Mrt = 'mrtGarage';         Luft = 0.0; Ht = 2; T = 5; Bez = 'Garage' }
}
if (-not $katalog.ContainsKey($Raumart)) { throw "Raumart $Raumart nicht im Katalog (bekannt: $(($katalog.Keys | Sort-Object) -join ', '))." }
$ht = if ($Status -eq 'beheizt') { 1 } else { 2 }
$htXml = @{ 1 = 'Heated'; 2 = 'Unheated' }[$ht]
$t = if ([double]::IsNaN($Temperatur)) { if ($Status -eq 'beheizt') { $katalog[$Raumart].T } else { 10 } } else { $Temperatur }
$sentinel = -987654321.99

# Polygon lesen, Flaeche (Gauss) und Umfang
$pts = @($Polygon.Trim() -split '\s+' | ForEach-Object { $a = $_ -split ';'; ,@([double]::Parse($a[0], $inv), [double]::Parse($a[1], $inv)) })
if ($pts.Count -lt 3) { throw "Polygon braucht mindestens drei Punkte." }
$flaeche = 0.0; $umfang = 0.0
for ($i = 0; $i -lt $pts.Count; $i++) {
    $a = $pts[$i]; $b = $pts[($i + 1) % $pts.Count]
    $flaeche += $a[0] * $b[1] - $b[0] * $a[1]
    $umfang += [math]::Sqrt(($b[0] - $a[0]) * ($b[0] - $a[0]) + ($b[1] - $a[1]) * ($b[1] - $a[1]))
}
if ($flaeche -lt 0) { [array]::Reverse($pts) }   # HottCAD-Raeume laufen wie die Vorlage; Vorzeichen egal, Betrag zaehlt
$flaeche = [math]::Abs($flaeche) / 2

. (Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1")
Assert-SoftwareZu -Erlaubt:$Probelauf

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
function Lade($sql, $param) {
    $c = $con.CreateCommand(); $c.CommandText = $sql
    foreach ($k in $param.Keys) { [void]$c.Parameters.AddWithValue($k, $param[$k]) }
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $c
    $tab = New-Object System.Data.DataTable; [void]$da.Fill($tab)
    return ,@($tab, $da)
}
try {
    # Projekt
    $g = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$g)) { $tp = (Lade "SELECT UUID, LongDesc FROM PrProject WHERE UUID=@p" @{ '@p' = $g })[0] }
    else { $tp = (Lade "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p" @{ '@p' = "%$Projekt%" })[0] }
    if ($tp.Rows.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Rows.Count) Treffer." }
    $projektId = [guid]$tp.Rows[0].UUID
    Write-Host "Projekt: $($tp.Rows[0].LongDesc)" -ForegroundColor Cyan

    # Geschoss
    $tf = (Lade "SELECT UUID, ShortDesc, ElevationOfRefHeight, FloorHeight FROM BmFloor WHERE ProjectUUID=@p AND ShortDesc=@g" @{ '@p' = $projektId; '@g' = $Geschoss })[0]
    if ($tf.Rows.Count -ne 1) { throw "Geschoss '$Geschoss' nicht gefunden." }
    $floorId = [guid]$tf.Rows[0].UUID; $z = [double]$tf.Rows[0].ElevationOfRefHeight; $floorH = [double]$tf.Rows[0].FloorHeight

    # Vorlage: Raum desselben Geschosses, sonst irgendein Raum des Projekts
    $tr = (Lade "SELECT TOP 1 r.UUID, r.ShortDesc, r.Height, f.ShortDesc AS G FROM BmRoom r JOIN BmFloor f ON f.UUID=r.FloorUUID WHERE r.ProjectUUID=@p ORDER BY CASE WHEN r.FloorUUID=@f THEN 0 ELSE 1 END, r.StampCreate" @{ '@p' = $projektId; '@f' = $floorId })[0]
    if ($tr.Rows.Count -ne 1) { throw "Kein Vorlagenraum im Projekt — ohne Vorlage wird nicht angelegt." }
    $vorlageId = [guid]$tr.Rows[0].UUID
    $gleichesGeschoss = ([string]$tr.Rows[0].G -eq $Geschoss)
    $h = if (-not [double]::IsNaN($Hoehe)) { $Hoehe } elseif ($gleichesGeschoss) { [double]$tr.Rows[0].Height } else { $floorH - 0.2 }
    Write-Host "Vorlage: $($tr.Rows[0].ShortDesc) ($($tr.Rows[0].G)); Hoehe $h m" -ForegroundColor Cyan

    # CAD-Geschoss-GUID: aus einem Raum-XML des Geschosses, sonst aus einer Zeichnungswand auf dieser Hoehe
    $cadFloor = $null
    $txr = (Lade "SELECT CAST(b.ClassValue AS nvarchar(max)) X FROM BmData b JOIN BmRoom r ON r.UUID=b.ReferenceUUID WHERE r.ProjectUUID=@p AND r.FloorUUID=@f AND b.LongDesc='CADXMLData'" @{ '@p' = $projektId; '@f' = $floorId })[0]
    foreach ($row in $txr.Rows) { $m = [regex]::Match([string]$row.X, '<room [^>]*floor="([^"]+)"'); if ($m.Success) { $cadFloor = $m.Groups[1].Value; break } }
    if (-not $cadFloor) {
        $tw = (Lade "SELECT CAST(b.ClassValue AS nvarchar(max)) X FROM BmData b JOIN BmElement e ON e.UUID=b.ReferenceUUID AND e.ElementType=1 WHERE b.ProjectUUID=@p AND b.LongDesc='CADXMLData'" @{ '@p' = $projektId })[0]
        foreach ($row in $tw.Rows) {
            $x = [string]$row.X
            $m = [regex]::Match($x, '<wall [^>]*floor="([^"]+)"[^>]*>\s*<points count="\d+">\s*<p>[^;]+;[^;]+;([^<]+)</p>')
            if ($m.Success -and [math]::Abs([double]::Parse($m.Groups[2].Value, $inv) - $z) -lt 0.05) { $cadFloor = $m.Groups[1].Value; break }
        }
    }
    if (-not $cadFloor) { throw "Keine CAD-Geschoss-GUID fuer '$Geschoss' ermittelbar." }

    # Naechste Raumnummer im Geschoss
    $tn = (Lade "SELECT ShortDesc FROM BmRoom WHERE ProjectUUID=@p AND FloorUUID=@f" @{ '@p' = $projektId; '@f' = $floorId })[0]
    $max = 0
    foreach ($row in $tn.Rows) { $m = [regex]::Match([string]$row.ShortDesc, '-R(\d+)$'); if ($m.Success -and [int]$m.Groups[1].Value -gt $max) { $max = [int]$m.Groups[1].Value } }
    $n = $max + 1
    $nr = "$Geschoss-R$n"; $kurz = "R$n-$Geschoss"

    # Zone
    $zoneId = $null
    if ($Zone) {
        $tz = (Lade "SELECT UUID, LongDesc FROM BmZone WHERE ProjectUUID=@p AND ZoneType=5" @{ '@p' = $projektId })[0]
        if ($tz.Rows.Count -ne 1) { throw "Zone nicht eindeutig: $($tz.Rows.Count) DIN-18599-Zonen." }
        $zoneId = [guid]$tz.Rows[0].UUID
    }

    # Raumprofil mit dem Namen der Raumart im Projekt? (nur namensgleich - ein fremdes Profil setzt RoomType beim Speichern zurueck)
    $profilId = $null
    $tpr = (Lade "SELECT TOP 1 pr.UUID FROM PdProfileReference pr JOIN BmRoom r ON r.UUID=pr.ReferenceToUUID WHERE r.ProjectUUID=@p AND pr.LongDesc=@bez" @{ '@p' = $projektId; '@bez' = $katalog[$Raumart].Bez })[0]
    if ($tpr.Rows.Count -eq 1) { $profilId = [guid]$tpr.Rows[0].UUID }

    $raumId = [guid]::NewGuid(); $xmlGuid = [guid]::NewGuid(); $jetzt = Get-Date
    $volumen = $flaeche * $h
    $living = if ($ht -eq 1) { $flaeche } else { $sentinel }

    "  {0}: {1} | Raumart {2} ({3}) | {4} {5} C | {6:F2} m2, {7:F2} m3, {8} Ecken | Zone: {9} | Profil: {10}" -f `
        $nr, $Name, $Raumart, $katalog[$Raumart].Mrt, $Status, $t, $flaeche, $volumen, $pts.Count, $(if ($zoneId) { 'ja' } else { 'nein' }), $(if ($profilId) { $profilId } else { 'keins' })

    # XML
    $zs = $z.ToString($inv); $zo = ($z + $h).ToString($inv)
    $pLines = ($pts | ForEach-Object { "<p>$($_[0].ToString($inv));$($_[1].ToString($inv));$zs</p>" }) -join "`n            "
    $heights = ((1..$pts.Count) | ForEach-Object { "<height_ext>$zs;$zs;$zo;$zo</height_ext>" }) -join "`n        "
    $esc = [System.Security.SecurityElement]::Escape($Name)
    if ($ht -eq 1) {
        $regel = "<LivingAreaCalculationRule count=`"3`"><rule><minZ>0</minZ><maxZ>1</maxZ><percentage>Percent_0</percentage></rule><rule><minZ>1</minZ><maxZ>2</maxZ><percentage>Percent_50</percentage></rule><rule><minZ>2</minZ><percentage>Percent_100</percentage></rule></LivingAreaCalculationRule>"
        $info = "<LivingAreaInformation><LivingAreaEntry><Area>0</Area><AreaKind>Room</AreaKind><Percentage>Percent_0</Percentage><CustomPercentage></CustomPercentage></LivingAreaEntry><LivingAreaEntry><Area>0</Area><AreaKind>Room</AreaKind><Percentage>Percent_50</Percentage><CustomPercentage></CustomPercentage></LivingAreaEntry><LivingAreaEntry><Area>$($flaeche.ToString($inv))</Area><AreaKind>Room</AreaKind><Percentage>Percent_100</Percentage><CustomPercentage></CustomPercentage></LivingAreaEntry><LivingAreaEntry><Area>0</Area><AreaKind>Stair</AreaKind><Percentage>Percent_0</Percentage><CustomPercentage></CustomPercentage></LivingAreaEntry><LivingAreaEntry><Area>0</Area><AreaKind>Stair</AreaKind><Percentage>Percent_50</Percentage><CustomPercentage></CustomPercentage></LivingAreaEntry><LivingAreaEntry><Area>0</Area><AreaKind>Stair</AreaKind><Percentage>Percent_100</Percentage><CustomPercentage></CustomPercentage></LivingAreaEntry></LivingAreaInformation>"
    } else {
        $regel = "<LivingAreaCalculationRule count=`"1`"><rule><minZ>0</minZ><percentage>NONE</percentage></rule></LivingAreaCalculationRule>"
        $info = "<LivingAreaInformation><LivingAreaEntry><Area>$($flaeche.ToString($inv))</Area><AreaKind>Room</AreaKind><Percentage>NONE</Percentage><CustomPercentage></CustomPercentage></LivingAreaEntry><LivingAreaEntry><Area>0</Area><AreaKind>Stair</AreaKind><Percentage>NONE</Percentage><CustomPercentage></CustomPercentage></LivingAreaEntry></LivingAreaInformation>"
    }
    $xml = @"
<?xml version="1.0"?>
<geometry>
  <Room count="1">
    <room name="$esc" GUID="$xmlGuid" floor="$cadFloor" number="$nr" helpLinesOffset="0" room_type="$($katalog[$Raumart].Mrt)" component_type="Room" temperature="$($t.ToString($inv))" air_change="$($katalog[$Raumart].Luft.ToString($inv))" heating_type="$htXml" short_name="$kurz" area="$($flaeche.ToString($inv))" volume="$($volumen.ToString($inv))" height="$($h.ToString($inv))" userDefinedLivingArea="">
      <points count="$($pts.Count + 1)">
            $pLines
            <p>$($pts[0][0].ToString($inv));$($pts[0][1].ToString($inv));$zs</p>
      </points>
      <polygons count="1">
        <plg height="$($h.ToString($inv))" type="MRoomPolygon" with_holes="True">
          <extensions count="0" />
          <points count="$($pts.Count + 1)">
            $pLines
            <p>$($pts[0][0].ToString($inv));$($pts[0][1].ToString($inv));$zs</p>
          </points>
        </plg>
      </polygons>
      <heights count="$($pts.Count)">
        $heights
      </heights>
      <extensions count="0" />
      <transform_origin count="1">
        <p>0;0;0</p>
      </transform_origin>
      <insertation_point count="1">
        <p>0;0;0</p>
      </insertation_point>
      $regel
      $info
    </room>
  </Room>
</geometry>
"@

    if ($Probelauf) { Write-Host "Probelauf - nichts geschrieben." -ForegroundColor Yellow; return }

    $tx = $con.BeginTransaction()
    try {
        function Kopiere($tabelle, $whereSql, $param, [scriptblock]$anpassen) {
            $c = $con.CreateCommand(); $c.Transaction = $tx; $c.CommandText = "SELECT * FROM $tabelle WHERE $whereSql"
            foreach ($k in $param.Keys) { [void]$c.Parameters.AddWithValue($k, $param[$k]) }
            $da = New-Object System.Data.SqlClient.SqlDataAdapter $c
            $tab = New-Object System.Data.DataTable; [void]$da.Fill($tab)
            if ($tab.Rows.Count -lt 1) { throw "Vorlage in $tabelle fehlt ($whereSql)." }
            $neu = $tab.NewRow(); $neu.ItemArray = $tab.Rows[0].ItemArray
            & $anpassen $neu
            $tab.Rows.Add($neu)
            $cb = New-Object System.Data.SqlClient.SqlCommandBuilder $da
            $ins = $cb.GetInsertCommand(); $ins.Transaction = $tx
            $da.InsertCommand = $ins
            $da.Update(@($neu)) | Out-Null
        }
        $stempel = { param($r) $r.StampCreate = $jetzt; $r.StampEdit = $jetzt; $r.SyncStamp = $jetzt; $r.SyncRowVersion = [guid]::NewGuid() }

        Kopiere 'BmRoom' 'UUID=@u' @{ '@u' = $vorlageId } {
            param($r)
            $r.UUID = $raumId; $r.FloorUUID = $floorId; $r.GId = $xmlGuid; $r.VariantRoot = ''
            $r.SortNum = $n; $r.ShortDesc = $nr; $r.LongDesc = $Name; $r.InfoDesc = $Name
            $r.RoomType = $Raumart; $r.HeatingType = $ht; $r.InsideTemperature = $t
            $r.Length = 1; $r.Width = $flaeche; $r.Area = $flaeche; $r.FloorArea = $flaeche; $r.FloorCircuitArea = $flaeche
            $r.CeilingArea = $flaeche; $r.CeilingCircuitArea = $flaeche; $r.UsefulArea = $flaeche; $r.LivingArea = $living
            $r.Height = $h; $r.ClearHeight = $h; $r.FloorHeight = $floorH; $r.Volume = $volumen
            $r.FloorPerimeter = $umfang; $r.WallArea = $umfang * $h; $r.WallCircuitArea = $umfang * $h; $r.EnclosureSurface = 2 * $flaeche + $umfang * $h
            & $stempel $r
        }
        Kopiere 'BmRoomData' 'UUID=@u' @{ '@u' = $vorlageId } {
            param($r)
            $r.UUID = $raumId; $r.GId = $xmlGuid; $r.SortNum = $n; $r.ShortDesc = $nr; $r.LongDesc = $Name; $r.InfoDesc = $Name
            $r.DINEN12831P = $sentinel
            & $stempel $r
        }
        Kopiere 'BmBuildingSpace' 'ParentUUID=@u' @{ '@u' = $vorlageId } {
            param($r)
            $r.UUID = [guid]::NewGuid(); $r.GId = [guid]::NewGuid(); $r.ParentUUID = $raumId; $r.VariantRoot = ''
            $r.NetAreaValue = $flaeche; $r.NetAreaDefaultValue = $flaeche
            & $stempel $r
        }
        Kopiere 'BmData' "ReferenceUUID=@u AND LongDesc='CADXMLData'" @{ '@u' = $vorlageId } {
            param($r)
            # UUID/GId bleiben: fuer CADXMLData ist das die KONSTANTE Datenart-Kennung (99E575C9-...),
            # ueber die HottCAD die Zeichnung sucht. Eine neue GUID macht den Raum unsichtbar (18.10.2026).
            $r.ReferenceUUID = $raumId; $r.InfoDesc = $Name
            $r.ClassValue = $xml
            & $stempel $r
        }
        if ($profilId) {
            Kopiere 'PdProfileReference' 'ReferenceToUUID=@u AND ReferenceClass=''TModelRoom''' @{ '@u' = $vorlageId } {
                param($r)
                $r.UUID = $profilId; $r.GId = $profilId; $r.ReferenceToUUID = $raumId
                $r.StampCreate = $jetzt; $r.StampEdit = $jetzt
            }
        }
        if ($zoneId) {
            $c = $con.CreateCommand(); $c.Transaction = $tx
            $c.CommandText = "INSERT INTO BmZoneReference (UUID, ReferenceToUUID, ReferenceClassType, ReferenceClass, GeneratorType, StampEdit, StampCreate, SyncType, SyncCreate, SyncEdit, SyncVersion, SyncMeta, ProjectUUID, StampSync, MId, SyncStamp, SyncRowVersion) VALUES (@z, @r, 1, 'TModelRoom', 2, @s, @s, 2, @leer, @leer, '1.5.6', '{""meta"":{""sync"":{""mod"":""6.6.0"",""dal"":""17.3""}}}', @p, '1899-12-30', @leer, @s, @v)"
            [void]$c.Parameters.AddWithValue('@z', $zoneId); [void]$c.Parameters.AddWithValue('@r', $raumId)
            [void]$c.Parameters.AddWithValue('@s', $jetzt); [void]$c.Parameters.AddWithValue('@leer', [guid]'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
            [void]$c.Parameters.AddWithValue('@p', $projektId); [void]$c.Parameters.AddWithValue('@v', [guid]::NewGuid())
            [void]$c.ExecuteNonQuery()
        }
        $tx.Commit()
        Write-Host "Raum $nr angelegt ($raumId)." -ForegroundColor Green
    } catch { $tx.Rollback(); throw }
} finally { $con.Close() }
