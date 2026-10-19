# Set-Geschoss.ps1 -- Hoehenlage und Hoehen eines Geschosses aendern
#
# WARUM DAS NICHT EINE SPALTE IST
# Eine Geschosshoehe zu aendern zieht vier Dinge nach sich, und wer eines davon
# vergisst, hinterlaesst ein Modell, das in sich widerspruechlich ist:
#
#   1. BmFloor            Height, CeilingThickness, FloorHeight, Elevation
#   2. die ZEICHNUNG des Geschosses (BmData 'CADXMLData')
#                         <floor elevation= height= ceiling=>
#                         Ohne sie sieht die Oberflaeche die Aenderung nicht --
#                         genau der Fehler, an dem schon zwei angelegte
#                         Geschosse unsichtbar geblieben sind.
#   3. ALLE GESCHOSSE DARUEBER. Sie stapeln sich: Hoehenlage eines Geschosses
#                         = Hoehenlage des darunter + dessen Geschosshoehe.
#                         Wer nur eines aendert, reisst eine Luecke oder
#                         schiebt zwei uebereinander.
#   4. die BAUTEILE der verschobenen Geschosse. Ihr z steckt in jedem einzelnen
#                         Punkt der Zeichnung und muss mitwandern.
#
# Deshalb rechnet dieses Skript die ganze Kette neu, von unten nach oben, und
# zeigt sie im Probelauf vollstaendig an. Der Probelauf ist hier wichtiger als
# sonst irgendwo: die Auswirkung reicht ueber das angefasste Geschoss hinaus.
#
# ZUSAMMENHANG DER HOEHEN, an Werner Grotz und Test0001 nachgerechnet:
#
#   FloorHeight (Geschosshoehe) = Height (lichte Hoehe) + CeilingThickness
#
# WAS ES NICHT KANN
# Ein Geschoss einschieben. Dafuer New-Geschoss.ps1 nehmen und die darueber
# liegenden anschliessend hiermit nachziehen.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Geschoss,
    # Lichte Raumhoehe. Wirkt auch auf die Wandhoehe dieses Geschosses.
    [double]$LichteHoehe = 0,
    # -1 heisst "nicht angegeben". NICHT 0 -- eine Deckenstaerke von 0 ist ein
    # gueltiger Wert: das oberste Geschoss unter einem Satteldach hat keine
    # Decke, und mit 0 als Vorgabe liesse sie sich nie setzen.
    [double]$Deckenstaerke = -1,
    # Hoehenlage NUR dieses Geschosses. Die darueber folgen automatisch.
    # Wird nichts angegeben, bleibt sie und nur die Hoehen wirken nach oben.
    [double]$Hoehenlage = [double]::NaN,
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture
function Z([double]$w) { $w.ToString('R', $inv) }
function K([double]$w) { $w.ToString('0.###', $inv) }

if (-not $OhneSoftwarepruefung -and -not $Probelauf) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
$tx = $null
try {
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
    [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Count) Treffer." }
    $prj = $tp[0]

    # Geschosse von UNTEN nach oben -- so stapelt sich die Rechnung.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT CAST(UUID AS varchar(40)), LongDesc, ElevationOfRefHeight, Height, CeilingThickness, FloorHeight " +
                     "FROM BmFloor WHERE ProjectUUID=@p ORDER BY ElevationOfRefHeight ASC"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $ge = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $ge += [pscustomobject]@{
            Id = $l.GetString(0).ToLower(); Name = $l.GetString(1)
            Bezug = [double]$l.GetValue(2); Hoehe = [double]$l.GetValue(3)
            Decke = [double]$l.GetValue(4); Geschosshoehe = [double]$l.GetValue(5)
            NeuBezug = 0.0; NeuHoehe = 0.0; NeuDecke = 0.0
        }
    }
    $l.Close()
    if ($ge.Count -eq 0) { throw "Das Projekt hat keine Geschosse." }

    $treffer = @($ge | Where-Object { $_.Name -like "*$Geschoss*" })
    if ($treffer.Count -ne 1) { throw "Geschoss nicht eindeutig: $($treffer.Count) Treffer fuer '$Geschoss'. $(($ge.Name) -join ', ')" }
    $ziel = $treffer[0]

    # --- Neue Werte rechnen -------------------------------------------------
    foreach ($g in $ge) { $g.NeuHoehe = $g.Hoehe; $g.NeuDecke = $g.Decke; $g.NeuBezug = $g.Bezug }
    if ($LichteHoehe -gt 0)   { $ziel.NeuHoehe = $LichteHoehe }
    if ($Deckenstaerke -ge 0) { $ziel.NeuDecke = $Deckenstaerke }
    if (-not [double]::IsNaN($Hoehenlage)) { $ziel.NeuBezug = $Hoehenlage }

    # Ab dem geaenderten Geschoss stapeln: jedes folgende sitzt auf dem darunter.
    $abIndex = [array]::IndexOf($ge.Name, $ziel.Name)
    for ($i = $abIndex + 1; $i -lt $ge.Count; $i++) {
        $u = $ge[$i - 1]
        $ge[$i].NeuBezug = $u.NeuBezug + $u.NeuHoehe + $u.NeuDecke
    }

    Write-Host "Projekt : $($prj.Name)"
    Write-Host "Geschoss: $($ziel.Name)"
    Write-Host ""
    Write-Host "  Geschoss     Hoehenlage           lichte Hoehe        Decke        Geschosshoehe"
    foreach ($g in ($ge | Sort-Object NeuBezug -Descending)) {
        $dz = $g.NeuBezug - $g.Bezug
        $mark = if ($g.Name -eq $ziel.Name) { '*' } elseif ([Math]::Abs($dz) -gt 1e-9) { '>' } else { ' ' }
        Write-Host ("  {0}{1,-10} {2,7} -> {3,-7}  {4,5} -> {5,-5}  {6,5} -> {7,-5}  {8,5} -> {9}" -f `
            $mark, $g.Name, (K $g.Bezug), (K $g.NeuBezug), (K $g.Hoehe), (K $g.NeuHoehe),
            (K $g.Decke), (K $g.NeuDecke), (K $g.Geschosshoehe), (K ($g.NeuHoehe + $g.NeuDecke)))
    }
    Write-Host "`n  * geaendert   > mitverschoben"

    $betroffen = @($ge | Where-Object {
        [Math]::Abs($_.NeuBezug - $_.Bezug) -gt 1e-9 -or [Math]::Abs($_.NeuHoehe - $_.Hoehe) -gt 1e-9 -or
        [Math]::Abs($_.NeuDecke - $_.Decke) -gt 1e-9
    })
    if ($betroffen.Count -eq 0) { Write-Host "`nNichts zu tun."; return }

    # --- Bauteile der betroffenen Geschosse ---------------------------------
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT e.UUID, e.LongDesc, e.ElementType, CAST(d.ClassValue AS nvarchar(max)) " +
                     "FROM BmElement e JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' " +
                     "WHERE e.ProjectUUID=@p"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $bt = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $x = $l.GetString(3)
        $bt += [pscustomobject]@{
            Id = $l.GetGuid(0); Name = $l.GetString(1); Art = [int]$l.GetValue(2); Xml = $x
            Geschoss = ([regex]::Match($x, 'floor="([^"]+)"')).Groups[1].Value.ToLower()
        }
    }
    $l.Close()

    Write-Host ""
    foreach ($g in $betroffen) {
        $meins = @($bt | Where-Object { $_.Geschoss -eq $g.Id })
        $dz = $g.NeuBezug - $g.Bezug
        $dh = $g.NeuHoehe - $g.Hoehe
        $was = @()
        if ([Math]::Abs($dz) -gt 1e-9) { $was += "z um $(K $dz) m verschieben" }
        if ([Math]::Abs($dh) -gt 1e-9) { $was += "Wandhoehe auf $(K $g.NeuHoehe) m setzen" }
        Write-Host ("  {0,-10} {1,2} Bauteile: {2}" -f $g.Name, $meins.Count, ($was -join ', '))
    }

    if ($Probelauf) { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow; return }

    # --- Schreiben ----------------------------------------------------------
    $tx = $con.BeginTransaction()
    $jetzt = Get-Date
    $zeilen = 0

    foreach ($g in $betroffen) {
        $u = $con.CreateCommand(); $u.Transaction = $tx
        $u.CommandText = "UPDATE BmFloor SET ElevationOfRefHeight=@b, Height=@h, CeilingThickness=@d, FloorHeight=@f, StampEdit=@s WHERE UUID=@u"
        [void]$u.Parameters.AddWithValue("@b", $g.NeuBezug)
        [void]$u.Parameters.AddWithValue("@h", $g.NeuHoehe)
        [void]$u.Parameters.AddWithValue("@d", $g.NeuDecke)
        [void]$u.Parameters.AddWithValue("@f", $g.NeuHoehe + $g.NeuDecke)
        [void]$u.Parameters.AddWithValue("@s", $jetzt)
        [void]$u.Parameters.AddWithValue("@u", [guid]$g.Id)
        $zeilen += $u.ExecuteNonQuery()

        # Die Zeichnung des Geschosses -- ohne sie sieht die Oberflaeche nichts.
        $s = $con.CreateCommand(); $s.Transaction = $tx
        $s.CommandText = "SELECT CAST(ClassValue AS nvarchar(max)) FROM BmData WHERE ReferenceUUID=@r AND LongDesc='CADXMLData'"
        [void]$s.Parameters.AddWithValue("@r", [guid]$g.Id)
        $alt = $s.ExecuteScalar()
        if ($alt) {
            $neu = [string]$alt
            $neu = $neu -replace 'elevation="[^"]*"', ('elevation="' + (Z $g.NeuBezug) + '"')
            $neu = $neu -replace '(<floor[^>]*?)\sheight="[^"]*"', ('${1} height="' + (Z ($g.NeuHoehe + $g.NeuDecke)) + '"')
            $neu = $neu -replace 'ceiling="[^"]*"', ('ceiling="' + (Z $g.NeuDecke) + '"')
            $w = $con.CreateCommand(); $w.Transaction = $tx
            $w.CommandText = "UPDATE BmData SET ClassValue=@v, StampEdit=@s WHERE ReferenceUUID=@r AND LongDesc='CADXMLData'"
            [void]$w.Parameters.AddWithValue("@v", $neu)
            [void]$w.Parameters.AddWithValue("@s", $jetzt)
            [void]$w.Parameters.AddWithValue("@r", [guid]$g.Id)
            $zeilen += $w.ExecuteNonQuery()
        }

        # Bauteile mitziehen.
        $dz = $g.NeuBezug - $g.Bezug
        $dh = $g.NeuHoehe - $g.Hoehe
        # Der Ersetzungsblock unten ist ein eigener Bereich und sieht $dz nicht;
        # deshalb der ausdrueckliche Umweg ueber den Skriptbereich.
        $script:dzAktuell = $dz
        foreach ($b in @($bt | Where-Object { $_.Geschoss -eq $g.Id })) {
            $x = $b.Xml
            if ([Math]::Abs($dz) -gt 1e-9) {
                # Das Traufrechteck eines Dachs (<plane_definition>) liegt IMMER
                # flach auf z = 0. Es sagt nur, WO die Dachebene beginnt und in
                # welche Richtung sie steigt -- ein absoluter Wert waere dort
                # sinnlos. Wer es mitverschiebt, bekommt ein Dach im Boden.
                # Deshalb wird die Zeichnung an diesem Block geteilt und nur
                # ausserhalb davon gerechnet.
                $teile = [regex]::Split($x, '(?s)(<plane_definition[^>]*>.*?</plane_definition>)')
                for ($i = 0; $i -lt $teile.Count; $i++) {
                    if ($teile[$i] -like '<plane_definition*') { continue }
                        $teile[$i] = [regex]::Replace($teile[$i], '<p>([-\d.eE+]+);([-\d.eE+]+);([-\d.eE+]+)</p>', {
                            param($m)
                            $z = [double]::Parse($m.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture) + $script:dzAktuell
                            '<p>' + $m.Groups[1].Value + ';' + $m.Groups[2].Value + ';' +
                                $z.ToString('R', [Globalization.CultureInfo]::InvariantCulture) + '</p>'
                        })
                }
                $x = -join $teile
            }
            if ([Math]::Abs($dh) -gt 1e-9 -and $b.Art -eq 1) {
                $x = $x -replace '(<wall[^>]*?)\sheight="[^"]*"', ('${1} height="' + (Z $g.NeuHoehe) + '"')
            }
            if ($x -ne $b.Xml) {
                $w = $con.CreateCommand(); $w.Transaction = $tx
                $w.CommandText = "UPDATE BmData SET ClassValue=@v, StampEdit=@s WHERE ReferenceUUID=@r AND LongDesc='CADXMLData'"
                [void]$w.Parameters.AddWithValue("@v", $x)
                [void]$w.Parameters.AddWithValue("@s", $jetzt)
                [void]$w.Parameters.AddWithValue("@r", $b.Id)
                $zeilen += $w.ExecuteNonQuery()
            }
            if ([Math]::Abs($dh) -gt 1e-9 -and $b.Art -eq 1) {
                $w = $con.CreateCommand(); $w.Transaction = $tx
                $w.CommandText = "UPDATE BmElement SET Height=@h, StampEdit=@s WHERE UUID=@u"
                [void]$w.Parameters.AddWithValue("@h", $g.NeuHoehe)
                [void]$w.Parameters.AddWithValue("@s", $jetzt)
                [void]$w.Parameters.AddWithValue("@u", $b.Id)
                $zeilen += $w.ExecuteNonQuery()
            }
        }
    }

    # SortNum neu vergeben -- die Reihenfolge kann sich geaendert haben.
    $u = $con.CreateCommand(); $u.Transaction = $tx
    $u.CommandText = "WITH r AS (SELECT UUID, ROW_NUMBER() OVER (ORDER BY ElevationOfRefHeight DESC) AS n " +
                     "FROM BmFloor WHERE ProjectUUID=@p) UPDATE f SET SortNum=r.n FROM BmFloor f JOIN r ON r.UUID=f.UUID"
    [void]$u.Parameters.AddWithValue("@p", $prj.Id)
    [void]$u.ExecuteNonQuery()

    $tx.Commit(); $tx = $null
    Write-Host "`n$($betroffen.Count) Geschoss(e) geaendert, $zeilen Zeilen." -ForegroundColor Green
}
catch { if ($tx) { $tx.Rollback() }; throw }
finally { $con.Close() }
