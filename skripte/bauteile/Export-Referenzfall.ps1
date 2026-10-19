# Export-Referenzfall.ps1 -- einen bestaetigten Fall als Datenbestand ablegen
#
# WOZU
# Doku beschreibt Regeln, Werkzeuge setzen sie um -- beides kann falsch sein,
# ohne dass es auffaellt. Was fehlt, ist der Belegfall: die exakten Bytes eines
# Modells, das in der Software nachweislich richtig aussah.
#
# Ein Referenzfall dient drei Zwecken:
#
#   1. BEWEIS.       Nicht "die Regel lautet so", sondern "so sah es aus, als
#                    es funktioniert hat".
#   2. RUECKFALL.    Eine spaetere Sitzung kann ihre eigene Ausgabe dagegen
#                    halten, statt die Regel neu herzuleiten.
#   3. REGRESSION.   Wer ein Werkzeug aendert, laesst es gegen den Fall laufen
#                    und vergleicht. Genau so wurde New-Satteldach.ps1 geprueft.
#
# WAS EXPORTIERT WIRD
# Die Zeichnung (CADXMLData) je Bauteil als eigene Datei -- das ist die
# eigentliche Wahrheit, alles andere rechnet HottCAD daraus. Dazu eine
# Uebersicht der Bauteilzeilen und der Geschosse, damit der Zusammenhang
# lesbar bleibt, und ein Kopf mit Herkunft und Bestaetigung.
#
# WICHTIG: EIN FALL WIRD ERST DURCH DIE BESTAETIGUNG ZUM REFERENZFALL.
# Deshalb ist -Bestaetigt Pflicht. Ein Fall, den nur die Datenbank gesehen hat,
# beweist nichts -- das Pultdach stand auch sauber in den Zeilen und ergab
# trotzdem keine Flaeche.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    # Kurzname des Falls, wird zum Verzeichnisnamen.
    [Parameter(Mandatory = $true)][string]$Fall,
    # Wie und wann bestaetigt. Ohne das kein Referenzfall.
    [Parameter(Mandatory = $true)][string]$Bestaetigt,
    [string]$Beschreibung = '',
    # Nur Bauteile mit diesem Namensanfang, z. B. 'Dach' oder 'AW'. Leer = alle.
    [string]$NamePraefix = '',
    [string]$Ziel = '',
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture

if (-not $Ziel) {
    $Ziel = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "sanierungsfahrplan-agent\beispiele"
}
$ordner = Join-Path $Ziel $Fall
$null = New-Item -ItemType Directory -Force -Path (Join-Path $ordner "zeichnung")

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
    [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -ne 1) { throw "Projekt nicht eindeutig: $($tp.Count) Treffer." }
    $prj = $tp[0]

    # Geschosse.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT SortNum, LongDesc, FloorType, ElevationOfRefHeight, Height, FloorHeight, CeilingThickness, CAST(UUID AS varchar(40)) " +
                     "FROM BmFloor WHERE ProjectUUID=@p ORDER BY SortNum"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $ge = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $ge += [pscustomobject]@{
            SortNum = $l.GetValue(0); Geschoss = $l.GetString(1); FloorType = $l.GetValue(2)
            Bezug = [double]$l.GetValue(3); Hoehe = [double]$l.GetValue(4)
            Geschosshoehe = [double]$l.GetValue(5); Deckendicke = [double]$l.GetValue(6)
            UUID = $l.GetString(7)
        }
    }
    $l.Close()

    # Bauteile samt Zeichnung.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT e.LongDesc, e.ElementType, e.RepositoryType, e.Width, e.Height, e.Thickness, e.Slope, " +
                     "CAST(e.UUID AS varchar(40)), CAST(d.ClassValue AS nvarchar(max)) " +
                     "FROM BmElement e LEFT JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' " +
                     "WHERE e.ProjectUUID=@p ORDER BY e.ElementType, e.LongDesc"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $bt = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $bt += [pscustomobject]@{
            Bauteil = $l.GetString(0); ElementType = [int]$l.GetValue(1); Repo = [int]$l.GetValue(2)
            Width = [double]$l.GetValue(3); Hoehe = [double]$l.GetValue(4)
            Dicke = [double]$l.GetValue(5); Slope = [double]$l.GetValue(6)
            UUID = $l.GetString(7); Xml = $(if ($l.IsDBNull(8)) { '' } else { $l.GetString(8) })
        }
    }
    $l.Close()
    if ($NamePraefix) { $bt = @($bt | Where-Object { $_.Bauteil.StartsWith($NamePraefix) }) }
    if ($bt.Count -eq 0) { throw "Keine Bauteile gefunden -- Filter '$NamePraefix' pruefen." }

    # Zeichnungen einzeln ablegen. Der Dateiname ist der Bauteilname, damit ein
    # Vergleich ohne Umweg ueber UUIDs moeglich ist -- UUIDs sind bei jedem Lauf
    # andere und taugen nicht zum Vergleichen.
    $n = 0
    foreach ($b in $bt) {
        if (-not $b.Xml) { continue }
        $datei = Join-Path $ordner ("zeichnung\" + ($b.Bauteil -replace '[^A-Za-z0-9._-]', '_') + ".xml")
        [IO.File]::WriteAllText($datei, $b.Xml, (New-Object Text.UTF8Encoding $false))
        $n++
    }

    $art = @{ 1 = 'Wand'; 4 = 'Decke/Platte'; 5 = 'Dach'; 11 = 'Bodenplatte' }
    $zeilen = @()
    $zeilen += "# Referenzfall: $Fall"
    $zeilen += ""
    if ($Beschreibung) { $zeilen += $Beschreibung; $zeilen += "" }
    $zeilen += "**Bestätigt:** $Bestaetigt"
    $zeilen += ""
    $zeilen += "**Herkunft:** Projekt *$($prj.Name)*, Datenbank ``$Datenbank``, exportiert am $(Get-Date -Format 'dd.MM.yyyy')."
    $zeilen += ""
    $zeilen += "> Die Zeichnungen unter ``zeichnung/`` sind die Wahrheit. Alles andere in"
    $zeilen += "> dieser Datei ist daraus abgeleitet und wird von HottCAD beim Öffnen neu"
    $zeilen += "> gerechnet — als Vergleichsgröße taugt nur das XML."
    $zeilen += ""
    $zeilen += "## Geschosse"
    $zeilen += ""
    $zeilen += "| Nr | Geschoss | FloorType | Höhenlage | lichte Höhe | Geschosshöhe |"
    $zeilen += "|---|---|---|---|---|---|"
    foreach ($g in $ge) {
        $zeilen += "| $($g.SortNum) | $($g.Geschoss) | $($g.FloorType) | $($g.Bezug.ToString('0.00',$inv)) | $($g.Hoehe.ToString('0.00',$inv)) | $($g.Geschosshoehe.ToString('0.00',$inv)) |"
    }
    $zeilen += ""
    $zeilen += "## Bauteile"
    $zeilen += ""
    $zeilen += "| Bauteil | Art | ElementType | Länge/Breite | Höhe | Dicke | Neigung |"
    $zeilen += "|---|---|---|---|---|---|---|"
    foreach ($b in $bt) {
        function Wert([double]$w) { if ($w -lt -999999) { '—' } else { $w.ToString('0.###', $inv) } }
        $zeilen += "| $($b.Bauteil) | $($art[$b.ElementType]) | $($b.ElementType) | $(Wert $b.Width) | $(Wert $b.Hoehe) | $(Wert $b.Dicke) | $(Wert $b.Slope) |"
    }
    [IO.File]::WriteAllLines((Join-Path $ordner "fall.md"), $zeilen, (New-Object Text.UTF8Encoding $false))

    Write-Host "Referenzfall '$Fall' abgelegt unter:"
    Write-Host "  $ordner"
    Write-Host "  fall.md  +  $n Zeichnungen  ($($bt.Count) Bauteile, $($ge.Count) Geschosse)" -ForegroundColor Green
}
finally { $con.Close() }
