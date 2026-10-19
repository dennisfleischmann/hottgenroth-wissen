# Get-Raeume.ps1 -- Geschosse, DIN-18599-Zonen und Raeume eines Projekts lesen
#
# Das lesende Gegenstueck zu Set-Raumstempel.ps1 und Set-Raum-Zone.ps1. Es gibt
# aus, was der Raumstempel im Grundriss zeigt (Nummer, Name, Raumart, Heizstatus,
# Temperatur, Flaeche) und dazu die Zonenzugehoerigkeit -- je Raum beide Stellen,
# BmRoom und das CAD-XML, damit ein Widerspruch zwischen ihnen sichtbar wird.
#
# Nur lesend. Laeuft auch bei geoeffneter Software -- dann auf dem zuletzt
# gespeicherten Stand.
#
# -AlsJson gibt ein einziges JSON-Objekt aus. Das ist die Form fuer den Agenten:
# der Server liest sie aus dem Protokoll des Auftrags.
#
# Beispiele:
#   .\Get-Raeume.ps1 -Projekt "Hudlberger"
#   .\Get-Raeume.ps1 -Projekt "ea4aa101-d7b6-2b7e-b9ee-32c6f3600057" -AlsJson

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [switch]$AlsJson,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

# Raumart -> Klartext. Dieselbe Tabelle wie in Set-Raumstempel.ps1 und in
# bauteile/docs/hottgenroth-raum-zone-sql.md, Abschnitt 8.
$raumarten = @{
    0 = 'Raum'; 1 = 'Wohnraum'; 2 = 'Schlafen'; 3 = 'Kind'; 4 = 'Küche'; 5 = 'Essen'
    6 = 'Flur'; 8 = 'Hobby'; 9 = 'Nebenraum'; 11 = 'Bad/Dusche/Umkleideraum'; 12 = 'WC-Raum'
    13 = 'Heizraum'; 14 = 'Büroraum'; 23 = 'Kellerraum'; 24 = 'Heizungsaufstellraum'
    25 = 'Dachraum'; 26 = 'Treppenhaus'; 30 = 'Sauna'; 34 = 'Abstellraum'; 35 = 'Vorratsraum'
    36 = 'Hausanschlussraum'; 42 = 'Garage'; 52 = 'Wohnungsflur'; 53 = 'Fahrstuhlschacht'
}
$heizstatus = @{ 1 = 'beheizt'; 2 = 'unbeheizt'; 4 = 'separat' }
$xmlZuHt = @{ 'Heated' = 1; 'Unheated' = 2; 'SeparatelyHeated' = 4 }
$sentinel = -987654321.99

function Wert([object]$w) {
    if ($null -eq $w -or $w -is [DBNull]) { return $null }
    $d = [double]$w
    if ($d -lt -999999) { return $null }   # Sentinel = nicht gerechnet
    return [math]::Round($d, 2)
}

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    function Abfrage([string]$Sql, [hashtable]$P = @{}) {
        $c = $con.CreateCommand(); $c.CommandText = $Sql; $c.CommandTimeout = 120
        foreach ($k in $P.Keys) { [void]$c.Parameters.AddWithValue($k, $P[$k]) }
        $t = New-Object System.Data.DataTable; $t.Load($c.ExecuteReader()); return , $t
    }

    # --- Projekt ---
    $g = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$g)) { $tp = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE UUID=@p" @{ '@p' = $g } }
    else { $tp = Abfrage "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p" @{ '@p' = "%$Projekt%" } }
    if ($tp.Rows.Count -eq 0) { throw "Kein Projekt passt auf '$Projekt'." }
    if ($tp.Rows.Count -gt 1) { throw "Projekt nicht eindeutig ($($tp.Rows.Count)): $(($tp.Rows | ForEach-Object { $_.LongDesc }) -join ' | ')" }
    $projektId = [guid]$tp.Rows[0].UUID
    $projektName = [string]$tp.Rows[0].LongDesc

    # --- Geschosse ---
    $tf = Abfrage @"
SELECT f.UUID, f.SortNum, f.ShortDesc, f.LongDesc, f.FloorType,
       (SELECT COUNT(*) FROM BmRoom r WHERE r.FloorUUID = f.UUID) AS Raeume
FROM BmFloor f WHERE f.ProjectUUID=@p ORDER BY f.SortNum
"@ @{ '@p' = $projektId }
    $typName = @{ 1 = 'DG'; 2 = 'OG'; 3 = 'EG'; 6 = 'Keller' }
    $geschosse = @(foreach ($f in $tf.Rows) {
        [ordered]@{
            kuerzel = [string]$f.ShortDesc
            name    = [string]$f.LongDesc
            typ     = $typName[[int]$f.FloorType]
            raeume  = [int]$f.Raeume
        }
    })

    # --- Zonen (nur DIN 18599, ZoneType 5) samt Nutzungsprofil ---
    $tz = Abfrage @"
SELECT z.UUID, z.LongDesc, ISNULL(z.InfoDesc,'') AS InfoDesc, z.HeatingType, z.Area, z.HeatableLivingArea,
       (SELECT COUNT(*) FROM BmZoneReference x WHERE x.UUID = z.UUID) AS Raeume,
       (SELECT TOP 1 r.LongDesc FROM PdProfileReference r
         WHERE r.ReferenceClass='TModelZone' AND r.ReferenceToUUID = z.UUID) AS Profil,
       (SELECT TOP 1 u.ProfileUsageType FROM PdProfileReference r JOIN PdProfileUsage u ON u.UUID = r.UUID
         WHERE r.ReferenceClass='TModelZone' AND r.ReferenceToUUID = z.UUID) AS ProfileUsageType
FROM BmZone z WHERE z.ProjectUUID=@p AND z.ZoneType=5 ORDER BY z.SortNum
"@ @{ '@p' = $projektId }
    $zonen = @(foreach ($z in $tz.Rows) {
        [ordered]@{
            uuid          = ([guid]$z.UUID).ToString()
            name          = [string]$z.LongDesc
            eberater_kennung = [string]$z.InfoDesc
            heizstatus    = $heizstatus[[int]$z.HeatingType]
            raeume        = [int]$z.Raeume
            flaeche_m2    = Wert $z.Area
            wohnflaeche_m2 = Wert $z.HeatableLivingArea
            flaeche_gerechnet = ($null -ne (Wert $z.Area))
            profil        = $(if ($z.Profil -is [DBNull]) { $null } else { [string]$z.Profil })
            profil_typ    = $(if ($z.ProfileUsageType -is [DBNull]) { $null } else { [int]$z.ProfileUsageType })
        }
    })
    # Brandschutz- und sonstige Zonen zaehlen nur: sie dienen als Vorlage, wenn
    # noch keine DIN-18599-Zone existiert (Setup-Wohngebaeude.ps1, Schritt 2).
    $ta = Abfrage "SELECT COUNT(*) AS n FROM BmZone WHERE ProjectUUID=@p" @{ '@p' = $projektId }

    # --- Raeume ---
    $tr = Abfrage @"
SELECT r.UUID, r.ShortDesc AS Nr, r.LongDesc AS Raum, r.RoomType, r.HeatingType, r.InsideTemperature,
       r.Area, r.Volume, r.LivingArea, f.ShortDesc AS Gesch, f.SortNum,
       CAST(d.ClassValue AS nvarchar(max)) AS Xml,
       (SELECT TOP 1 CAST(x.UUID AS varchar(40)) FROM BmZoneReference x
          JOIN BmZone z2 ON z2.UUID = x.UUID AND z2.ZoneType = 5
         WHERE x.ReferenceToUUID = r.UUID) AS Zone,
       (SELECT COUNT(*) FROM BmZoneReference x JOIN BmZone z3 ON z3.UUID = x.UUID AND z3.ZoneType = 5
         WHERE x.ReferenceToUUID = r.UUID) AS Zonen
FROM BmRoom r
LEFT JOIN BmFloor f ON f.UUID = r.FloorUUID
LEFT JOIN BmData d ON d.ReferenceUUID = r.UUID AND d.LongDesc = 'CADXMLData'
WHERE r.ProjectUUID=@p
ORDER BY f.SortNum, r.StampCreate, r.ShortDesc
"@ @{ '@p' = $projektId }

    $zonenName = @{}
    foreach ($z in $zonen) { $zonenName[$z.uuid.ToLower()] = $z.name }

    $raeume = @(foreach ($r in $tr.Rows) {
        $rt = [int]$r.RoomType; $ht = [int]$r.HeatingType
        $xml = if ($r.Xml -is [DBNull]) { '' } else { [string]$r.Xml }
        $xmlHt = $null; $xmlRt = $null; $xmlName = $null
        if ($xml) {
            if ($xml -match 'heating_type="([^"]*)"') { $xmlHt = $Matches[1] }
            if ($xml -match 'room_type="([^"]*)"')    { $xmlRt = $Matches[1] }
            if ($xml -match '<room [^>]*?name="([^"]*)"') { $xmlName = [System.Net.WebUtility]::HtmlDecode($Matches[1]) }
        }
        $widerspruch = @()
        if ($xmlHt -and $xmlZuHt.ContainsKey($xmlHt) -and $xmlZuHt[$xmlHt] -ne $ht) { $widerspruch += "heizstatus: BmRoom $($heizstatus[$ht]), XML $xmlHt" }
        if ($null -ne $xmlName -and $xmlName -ne [string]$r.Raum) { $widerspruch += "name: BmRoom '$($r.Raum)', XML '$xmlName'" }
        $zoneUuid = if ($r.Zone -is [DBNull]) { $null } else { ([string]$r.Zone).ToLower() }
        [ordered]@{
            nr            = [string]$r.Nr
            name          = [string]$r.Raum
            geschoss      = $(if ($r.Gesch -is [DBNull]) { $null } else { [string]$r.Gesch })
            raumart       = $rt
            raumart_name  = $(if ($raumarten.ContainsKey($rt)) { $raumarten[$rt] } else { "unbekannt ($rt)" })
            heizstatus    = $(if ($heizstatus.ContainsKey($ht)) { $heizstatus[$ht] } else { "unbekannt ($ht)" })
            temperatur_c  = Wert $r.InsideTemperature
            flaeche_m2    = Wert $r.Area
            volumen_m3    = Wert $r.Volume
            wohnflaeche_m2 = Wert $r.LivingArea
            zone          = $(if ($zoneUuid -and $zonenName.ContainsKey($zoneUuid)) { $zonenName[$zoneUuid] } else { $null })
            in_zone       = ($null -ne $zoneUuid)
            zonen_anzahl  = [int]$r.Zonen
            cad_xml       = [bool]$xml
            xml_room_type = $xmlRt
            widersprueche = @($widerspruch)
        }
    })

    $ergebnis = [ordered]@{
        projekt   = [ordered]@{ name = $projektName; guid = $projektId.ToString() }
        geschosse = $geschosse
        zonen     = $zonen
        zonen_gesamt = [int]$ta.Rows[0].n
        raeume    = $raeume
        zusammenfassung = [ordered]@{
            raeume            = $raeume.Count
            beheizt           = @($raeume | Where-Object { $_.heizstatus -eq 'beheizt' }).Count
            unbeheizt         = @($raeume | Where-Object { $_.heizstatus -eq 'unbeheizt' }).Count
            separat           = @($raeume | Where-Object { $_.heizstatus -eq 'separat' }).Count
            in_zone           = @($raeume | Where-Object { $_.in_zone }).Count
            ohne_cad_xml      = @($raeume | Where-Object { -not $_.cad_xml }).Count
            mit_widerspruch   = @($raeume | Where-Object { $_.widersprueche.Count -gt 0 }).Count
            din18599_zonen    = $zonen.Count
        }
    }

    if ($AlsJson) {
        # Eine Zeile, damit der Server sie im Protokoll als Ganzes findet.
        Write-Output (ConvertTo-Json -InputObject $ergebnis -Depth 6 -Compress)
        return
    }

    Write-Output "Projekt: $projektName"
    Write-Output ""
    Write-Output "Geschosse:"
    foreach ($f in $geschosse) { Write-Output ("  {0,-8} {1,-20} {2,-7} {3,3} Raeume" -f $f.kuerzel, $f.name, $f.typ, $f.raeume) }
    Write-Output ""
    Write-Output "DIN-18599-Zonen: $($zonen.Count)  (Zonen gesamt inkl. Brandschutz: $($ta.Rows[0].n))"
    foreach ($z in $zonen) {
        $fl = if ($z.flaeche_gerechnet) { "$($z.flaeche_m2) m2" } else { 'Flaeche nicht gerechnet (Sentinel)' }
        Write-Output ("  {0,-30} {1,-10} {2,3} Raeume  {3}  Profil: {4}  EE-Berater: {5}" -f $z.name, $z.heizstatus, $z.raeume, $fl, $(if ($z.profil) { "$($z.profil) [$($z.profil_typ)]" } else { '(keins)' }), $(if ($z.eberater_kennung) { $z.eberater_kennung } else { '(leer)' }))
    }
    Write-Output ""
    Write-Output "Raeume:"
    foreach ($r in $raeume) {
        $zoneTxt = if ($r.in_zone) { $r.zone } else { '-' }
        $w = if ($r.widersprueche.Count) { '  !! ' + ($r.widersprueche -join '; ') } else { '' }
        $x = if ($r.cad_xml) { '' } else { '  (kein CAD-XML)' }
        Write-Output ("  {0,-7} {1,-10} {2,-26} RT {3,2} {4,-24} {5,-10} {6,5} C  {7,7} m2  Zone: {8}{9}{10}" -f `
            $r.geschoss, $r.nr, $r.name, $r.raumart, $r.raumart_name, $r.heizstatus, $r.temperatur_c, $r.flaeche_m2, $zoneTxt, $x, $w)
    }
    $s = $ergebnis.zusammenfassung
    Write-Output ""
    Write-Output "Zusammenfassung: $($s.raeume) Raeume, $($s.beheizt) beheizt, $($s.unbeheizt) unbeheizt, $($s.separat) separat, $($s.in_zone) in einer Zone, $($s.ohne_cad_xml) ohne CAD-XML, $($s.mit_widerspruch) mit Widerspruch BmRoom/XML."
}
finally { $con.Close() }
