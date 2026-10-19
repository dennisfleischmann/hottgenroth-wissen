# Show-Projekt.ps1 -- ein Projekt lesbar zusammenfassen
#
# Snapshot-Projekt.ps1 schreibt Dateien; die kann ein Agent nicht lesen. Dieses
# Skript gibt dasselbe Wissen als Text aus, kurz genug fuer einen Werkzeug-
# aufruf und vollstaendig genug, um darauf aufzubauen.
#
# DIE AUSSENKONTUR IST DER EIGENTLICHE ZWECK
# Wer ein Dach auf ein Geschoss setzen will, braucht dessen Grundriss. Der steht
# nirgends als Liste -- er ergibt sich aus den Aussenwaenden, und zwar aus deren
# ERSTEM Punkt, in der Reihenfolge der prev/next-Kette. Genau das rechnet dieses
# Skript aus und gibt es in der Form aus, die New-Satteldach.ps1 erwartet.
#
# Nur lesend. Laeuft auch bei geoeffneter Software -- dann allerdings auf dem
# zuletzt gespeicherten Stand, nicht auf dem, was im Fenster zu sehen ist.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [switch]$MitKoordinaten,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture
function Z([double]$w) { $w.ToString('0.####', $inv) }
function Wert([object]$w) { $d = [double]$w; if ($d -lt -999999) { '--' } else { Z $d } }

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
    [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -eq 0) { throw "Kein Projekt passt auf '$Projekt'." }
    if ($tp.Count -gt 1) { throw "Projekt nicht eindeutig ($($tp.Count)): $(($tp.Name) -join ' | ')" }
    $prj = $tp[0]
    Write-Output "Projekt: $($prj.Name)"

    # Geschosse
    $c = $con.CreateCommand()
    # `wall floor="..."` zeigt auf die GUID der GESCHOSSZEICHNUNG, nicht auf
    # BmFloor.UUID. Bei Projekten, die unsere Skripte gebaut haben, sind beide
    # gleich; bei jedem von HottCAD selbst angelegten nicht. Ohne diese Aufloesung
    # stand hier bei echten Projekten jedes Bauteil unter "ohne Geschossbezug".
    $c.CommandText = @"
SELECT f.SortNum, f.LongDesc, f.FloorType, f.ElevationOfRefHeight, f.Height, f.FloorHeight,
       CAST(f.UUID AS varchar(40)),
       CASE WHEN CHARINDEX('<floor GUID="', CAST(d.ClassValue AS nvarchar(max))) > 0
            THEN LOWER(SUBSTRING(CAST(d.ClassValue AS nvarchar(max)),
                       CHARINDEX('<floor GUID="', CAST(d.ClassValue AS nvarchar(max))) + 13, 36))
            ELSE NULL END
FROM BmFloor f
LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.LongDesc = 'CADXMLData'
WHERE f.ProjectUUID=@p ORDER BY f.SortNum
"@
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $ge = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $zg = if ($l.IsDBNull(7)) { $null } else { $l.GetString(7) }
        $ge += [pscustomobject]@{ Nr = $l.GetValue(0); Name = $l.GetString(1); Typ = [int]$l.GetValue(2)
                                  Bezug = [double]$l.GetValue(3); Hoehe = [double]$l.GetValue(4)
                                  Geschosshoehe = [double]$l.GetValue(5)
                                  Id = $(if ($zg) { $zg } else { $l.GetString(6).ToLower() }) }
    }
    $l.Close()
    $typName = @{ 1 = 'DG'; 2 = 'OG'; 3 = 'EG'; 6 = 'Keller' }
    Write-Output ""
    Write-Output "Geschosse (Typ 1=DG 2=OG 3=EG 6=Keller):"
    if ($ge.Count -eq 0) { Write-Output "  keine" }
    foreach ($g in $ge) {
        Write-Output ("  {0}  {1,-10} Typ {2} ({3,-6})  Hoehenlage {4,7} m  lichte Hoehe {5} m  Geschosshoehe {6} m" -f `
            $g.Nr, $g.Name, $g.Typ, $typName[$g.Typ], (Z $g.Bezug), (Z $g.Hoehe), (Z $g.Geschosshoehe))
    }

    # Bauteile samt Zeichnung
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT e.LongDesc, e.ElementType, e.Width, e.Height, e.Thickness, e.Slope, " +
                     "ISNULL(CAST(d.ClassValue AS nvarchar(max)),'') " +
                     "FROM BmElement e LEFT JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' " +
                     "WHERE e.ProjectUUID=@p ORDER BY e.ElementType, e.LongDesc"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $bt = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $x = $l.GetString(6)
        $bt += [pscustomobject]@{
            Name = $l.GetString(0); Art = [int]$l.GetValue(1)
            Width = [double]$l.GetValue(2); Hoehe = [double]$l.GetValue(3)
            Dicke = [double]$l.GetValue(4); Slope = [double]$l.GetValue(5)
            Xml = $x
            Geschoss = ([regex]::Match($x, 'floor="([^"]+)"')).Groups[1].Value.ToLower()
            WandTyp  = ([regex]::Match($x, 'wall_type="([^"]+)"')).Groups[1].Value
        }
    }
    $l.Close()

    $artName = @{ 1 = 'Wand'; 4 = 'Decke'; 5 = 'Dach'; 11 = 'Bodenplatte' }
    Write-Output ""
    Write-Output "Bauteile: $($bt.Count)"
    foreach ($g in $ge) {
        $meins = @($bt | Where-Object { $_.Geschoss -eq $g.Id })
        Write-Output "  -- $($g.Name) --"
        if ($meins.Count -eq 0) { Write-Output "     (leer)"; continue }
        foreach ($b in $meins) {
            $zusatz = if ($b.Art -eq 5) { "Neigung $(Wert $b.Slope) Grad" } else { "Laenge $(Wert $b.Width) m" }
            Write-Output ("     {0,-10} {1,-11} {2,-13} {3,-18} Dicke {4} m" -f `
                $b.Name, $artName[$b.Art], $b.WandTyp, $zusatz, (Wert $b.Dicke))
        }
    }
    $ohne = @($bt | Where-Object { -not $_.Geschoss })
    if ($ohne.Count) { Write-Output "  -- ohne Geschossbezug --"; foreach ($b in $ohne) { Write-Output "     $($b.Name)" } }

    # Aussenkontur je Geschoss: erster Punkt jeder OuterContour-Wand, in der
    # Reihenfolge der prev/next-Kette.
    Write-Output ""
    Write-Output "Aussenkontur je Geschoss (Form fuer -Polygon / -Grundriss):"
    foreach ($g in $ge) {
        $ring = @($bt | Where-Object { $_.Geschoss -eq $g.Id -and $_.WandTyp -eq 'OuterContour' })
        if ($ring.Count -lt 3) { Write-Output "  $($g.Name): kein geschlossener Ring ($($ring.Count) Aussenwaende)"; continue }

        $nachGuid = @{}
        foreach ($w in $ring) {
            $gu = ([regex]::Match($w.Xml, '<wall [^>]*?GUID="([^"]+)"')).Groups[1].Value.ToLower()
            $p1 = [regex]::Match($w.Xml, '<p>([-\d.eE+]+);([-\d.eE+]+);')
            $nachGuid[$gu] = [pscustomobject]@{
                Naechste = ([regex]::Match($w.Xml, ' next="([^"]+)"')).Groups[1].Value.ToLower()
                X = [double]::Parse($p1.Groups[1].Value, $inv)
                Y = [double]::Parse($p1.Groups[2].Value, $inv)
            }
        }
        # Der Kette folgen. Bricht sie, wird das gemeldet statt geraten.
        $start = @($nachGuid.Keys)[0]
        $punkte = @(); $k = $start
        for ($i = 0; $i -lt $ring.Count; $i++) {
            if (-not $nachGuid.ContainsKey($k)) { break }
            $punkte += ((Z $nachGuid[$k].X) + ',' + (Z $nachGuid[$k].Y))
            $k = $nachGuid[$k].Naechste
        }
        if ($punkte.Count -ne $ring.Count -or $k -ne $start) {
            Write-Output "  $($g.Name): Kette unvollstaendig -- $($punkte.Count) von $($ring.Count) Waenden erreicht"
        } else {
            Write-Output "  $($g.Name): $($punkte -join ';')"
        }
    }

    if ($MitKoordinaten) {
        Write-Output ""
        Write-Output "Zeichnungen (Punkte je Bauteil):"
        foreach ($b in $bt) {
            if (-not $b.Xml) { continue }
            $p = @([regex]::Matches($b.Xml, '<p>([-\d.eE+]+);([-\d.eE+]+);([-\d.eE+]+)</p>') |
                   ForEach-Object { $_.Groups[1].Value + ';' + $_.Groups[2].Value + ';' + $_.Groups[3].Value })
            Write-Output "  $($b.Name): $($p -join '  |  ')"
        }
    }
}
finally { $con.Close() }
