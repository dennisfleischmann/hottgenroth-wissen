# Set-Raumstempel.ps1 — Raumart, Name und Heizstatus eines Raums setzen
#
# Der "Raumstempel" ist kein eigenes Objekt. Was im Grundriss steht —
#     Keller-R1; Kellerraum
#     99,34 m²/218,54 m³
#     WoFl: ---
#     unbeheizt
#     10 °C
# — ist die Anzeige von BmRoom.ShortDesc/LongDesc, Area/Volume, LivingArea,
# HeatingType und InsideTemperature. Es gibt nichts Zusätzliches zu schreiben.
#
# Jedes Feld steht aber an ZWEI Stellen: in BmRoom und im CAD-XML in
# BmData.ClassValue (Attribute name, room_type, heating_type, temperature,
# air_change). Beide müssen zusammenpassen.
#
# Der Katalog unten ist aus 1704 Räumen dieser Datenbank abgeleitet, nicht
# geraten. Wo die mrt*-Bezeichnung fehlt, hatten die Projekte kein CAD-XML —
# im ganzen Bestand haben nur 42 Räume eines. Solche Raumarten weist das
# Skript ab, statt einen Namen zu erfinden.
#
# Beispiele:
#   .\Set-Raumstempel.ps1 -Projekt "Pohlstra" -Geschoss EG,DG1,DG2 -Raumart 1 -Name Wohnraum -Probelauf
#   .\Set-Raumstempel.ps1 -Projekt "Pohlstra" -Geschoss Keller     -Status unbeheizt

param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string[]]$Geschoss,
    # Einzelne Raeume ueber ShortDesc (z. B. EG-R9). Mit "-Geschoss *" kombinieren,
    # um geschossunabhaengig genau diese Raeume zu treffen - fuer Ausnahmen,
    # die nicht dem Geschoss folgen.
    [string[]]$Raum = @(),
    # Raumart setzen (RoomType). Ohne Angabe bleibt die vorhandene stehen.
    [int]$Raumart = 0,
    # Umbenennen: Basisname, erster Raum ohne Nummer, danach " 2", " 3" …
    # Das ist das Muster, das die Software selbst verwendet (Wohnraum,
    # Wohnraum 2 / Kind, Kind 2, Kind 3).
    [string]$Name,
    [ValidateSet('', 'beheizt', 'unbeheizt')][string]$Status = '',
    [double]$Temperatur = [double]::NaN,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData",
    [switch]$Probelauf
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Data

# RoomType -> mrt*-Bezeichnung, air_change, Vorgabe-Heizstatus, Vorgabe-Temperatur.
# Abgeleitet aus dem Bestand. air_change ist 0,5 bei Aufenthaltsraeumen, sonst 0.
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
    25 = @{ Mrt = 'mrtRoof';           Luft = 0.0; Ht = 2; T = 7;  Bez = 'Dachraum' }
    34 = @{ Mrt = 'mrtStore';          Luft = 0.0; Ht = 1; T = 15; Bez = 'Abstellraum' }
    42 = @{ Mrt = 'mrtGarage';         Luft = 0.0; Ht = 2; T = 5;  Bez = 'Garage' }
}
$statusZuHt = @{ 'beheizt' = @{ Ht = 1; Xml = 'Heated'; T = 20 }; 'unbeheizt' = @{ Ht = 2; Xml = 'Unheated'; T = 10 } }
$htZuXml = @{ 1 = 'Heated'; 2 = 'Unheated'; 4 = 'SeparatelyHeated' }

if ($Raumart -ne 0 -and -not $katalog.ContainsKey($Raumart)) {
    throw "Raumart $Raumart ist im abgeleiteten Katalog nicht enthalten. Die mrt*-Bezeichnung dafuer ist unbekannt; sie zu erfinden wuerde das XML unbrauchbar machen. Bekannt: $(($katalog.Keys | Sort-Object) -join ', ')."
}

. (Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1")
Assert-SoftwareZu -Erlaubt:$Probelauf

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    $cmd = $con.CreateCommand()
    $g = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$g)) { $cmd.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE UUID=@p" }
    else { $cmd.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"; $Projekt = "%$Projekt%" }
    [void]$cmd.Parameters.AddWithValue("@p", $Projekt)
    $tp = New-Object System.Data.DataTable; $tp.Load($cmd.ExecuteReader())
    if ($tp.Rows.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Rows.Count) Treffer." }
    $projektId = [guid]$tp.Rows[0].UUID
    Write-Host "Projekt: $($tp.Rows[0].LongDesc)" -ForegroundColor Cyan

    $filter = ""
    if ($Geschoss -notcontains '*') {
        $liste = ($Geschoss | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ","
        $filter = " AND f.ShortDesc IN ($liste)"
    }
    if ($Raum.Count) {
        $rliste = ($Raum | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ","
        $filter += " AND r.ShortDesc IN ($rliste)"
    }
    $cmd = $con.CreateCommand()
    # Reihenfolge nach Anlagezeit - so nummeriert die Software selbst.
    $cmd.CommandText = @"
SELECT r.UUID, r.ShortDesc AS Nr, r.LongDesc AS Raum, r.RoomType, r.HeatingType,
       r.InsideTemperature, f.ShortDesc AS Gesch
FROM BmRoom r LEFT JOIN BmFloor f ON f.UUID = r.FloorUUID
WHERE r.ProjectUUID = @p$filter
ORDER BY r.StampCreate, r.ShortDesc
"@
    [void]$cmd.Parameters.AddWithValue("@p", $projektId)
    $tr = New-Object System.Data.DataTable; $tr.Load($cmd.ExecuteReader())
    if ($tr.Rows.Count -eq 0) { throw "Keine Raeume in Geschoss $($Geschoss -join ', ')." }

    $tx = $null
    if (-not $Probelauf) { $tx = $con.BeginTransaction() }
    $jetzt = Get-Date
    $lfd = 0; $geaendert = 0; $ohneXml = 0

    foreach ($r in $tr.Rows) {
        $uuid = [guid]$r.UUID
        $altRt = [int]$r.RoomType
        $neuRt = if ($Raumart -ne 0) { $Raumart } else { $altRt }

        # Heizstatus: ausdruecklicher Status schlaegt die Katalogvorgabe der Raumart.
        if ($Status) { $ht = $statusZuHt[$Status].Ht; $tVor = $statusZuHt[$Status].T }
        elseif ($katalog.ContainsKey($neuRt)) { $ht = $katalog[$neuRt].Ht; $tVor = $katalog[$neuRt].T }
        else { $ht = [int]$r.HeatingType; $tVor = [double]$r.InsideTemperature }
        $t = if ([double]::IsNaN($Temperatur)) { $tVor } else { $Temperatur }

        # Name
        $neuName = [string]$r.Raum
        if ($Name) {
            $lfd++
            $neuName = if ($lfd -eq 1) { $Name } else { "$Name $lfd" }
        }

        $mrt = $null; $luft = $null
        if ($katalog.ContainsKey($neuRt)) { $mrt = $katalog[$neuRt].Mrt; $luft = $katalog[$neuRt].Luft }

        if (-not $Probelauf) {
            $u = $con.CreateCommand(); $u.Transaction = $tx
            $u.CommandText = "UPDATE BmRoom SET RoomType=@rt, LongDesc=@n, InfoDesc=@n, HeatingType=@h, InsideTemperature=@t, StampEdit=@s WHERE UUID=@u"
            [void]$u.Parameters.AddWithValue("@rt", $neuRt)
            [void]$u.Parameters.AddWithValue("@n", $neuName)
            [void]$u.Parameters.AddWithValue("@h", $ht)
            [void]$u.Parameters.AddWithValue("@t", $t)
            [void]$u.Parameters.AddWithValue("@s", $jetzt)
            [void]$u.Parameters.AddWithValue("@u", $uuid)
            [void]$u.ExecuteNonQuery()

            $u2 = $con.CreateCommand(); $u2.Transaction = $tx
            $u2.CommandText = "UPDATE BmRoomData SET LongDesc=@n, InfoDesc=@n, StampEdit=@s WHERE UUID=@u"
            [void]$u2.Parameters.AddWithValue("@n", $neuName)
            [void]$u2.Parameters.AddWithValue("@s", $jetzt)
            [void]$u2.Parameters.AddWithValue("@u", $uuid)
            [void]$u2.ExecuteNonQuery()
        }

        # Das CAD-XML nachziehen
        $q = $con.CreateCommand(); $q.Transaction = $tx
        $q.CommandText = "SELECT CAST(ClassValue AS nvarchar(max)) FROM BmData WHERE ReferenceUUID=@u AND LongDesc='CADXMLData'"
        [void]$q.Parameters.AddWithValue("@u", $uuid)
        $xml = $q.ExecuteScalar()
        if ([string]::IsNullOrEmpty([string]$xml)) {
            $ohneXml++
        } else {
            $inv = [Globalization.CultureInfo]::InvariantCulture
            $neu = [regex]::Replace($xml, '(?<=<room )name="[^"]*"', "name=""$([System.Security.SecurityElement]::Escape($neuName))""")
            $neu = [regex]::Replace($neu, 'heating_type="[^"]*"', "heating_type=""$($htZuXml[$ht])""")
            $neu = [regex]::Replace($neu, '(?<![\w_])temperature="[^"]*"', "temperature=""$($t.ToString($inv))""")
            if ($mrt) { $neu = [regex]::Replace($neu, 'room_type="[^"]*"', "room_type=""$mrt""") }
            if ($null -ne $luft) { $neu = [regex]::Replace($neu, 'air_change="[^"]*"', "air_change=""$($luft.ToString($inv))""") }
            if (-not $Probelauf -and $neu -ne $xml) {
                $u3 = $con.CreateCommand(); $u3.Transaction = $tx
                $u3.CommandText = "UPDATE BmData SET ClassValue=@v, StampEdit=@s WHERE ReferenceUUID=@u AND LongDesc='CADXMLData'"
                [void]$u3.Parameters.AddWithValue("@v", $neu)
                [void]$u3.Parameters.AddWithValue("@s", $jetzt)
                [void]$u3.Parameters.AddWithValue("@u", $uuid)
                [void]$u3.ExecuteNonQuery()
            }
        }

        "  {0,-11} {1,-24} -> {2,-14} RT {3,2}->{4,-2} HT {5}->{6}  T {7}->{8}  {9}" -f `
            $r.Nr, $r.Raum, $neuName, $altRt, $neuRt, $r.HeatingType, $ht, $r.InsideTemperature, $t, $(if ($mrt) { $mrt } else { '(kein mrt)' })
        $geaendert++
    }

    Write-Host ""
    if ($Probelauf) { Write-Host "Probelauf - nichts geschrieben. $geaendert Raeume betroffen." -ForegroundColor Yellow }
    else { $tx.Commit(); Write-Host "$geaendert Raeume gesetzt." -ForegroundColor Green }
    if ($ohneXml -gt 0) { Write-Warning "$ohneXml Raeume ohne CADXMLData - dort steht der Stempel nur in BmRoom." }
} finally { $con.Close() }
