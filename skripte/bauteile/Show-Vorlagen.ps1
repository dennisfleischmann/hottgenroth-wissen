# Show-Vorlagen.ps1 -- welche Seitendatenbanken sich als Muster eignen
#
# WOZU
# Die New-*-Werkzeuge bauen ein neues Bauteil als Spalte-fuer-Spalte-Kopie eines
# vorhandenen desselben Projekts -- so stimmen auch die Spalten, die niemand
# namentlich kennt. Steht im Projekt kein passendes Bauteil, braucht es
# -VorlageDatenbank.
#
# Nur: welche Datenbank das ist, stand bisher nirgends. Wer den Namen raet,
# zieht Katalogverweise aus einem fremden Projekt mit. Dieses Skript zaehlt auf,
# was tatsaechlich da ist, und sagt je Datenbank, welche Bauteilarten sie fuehrt.
#
# Massgeblich ist die Zeile "brauchbar als Vorlage fuer": nur wo ein Projekt
# GLEICHEN NAMENS mit dem gesuchten Bauteiltyp existiert, passen auch die
# Katalog- und Gebaeudeverweise.
#
# Nur lesend.

[CmdletBinding()]
param(
    # Nur Datenbanken zeigen, die ein Projekt dieses Namens fuehren.
    [string]$Projekt = '',
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Laufend = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

function Frage([string]$db, [string]$sql) {
    $con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$db;Integrated Security=true;TrustServerCertificate=true"
    $con.Open()
    try {
        $c = $con.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = 120
        $t = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($t)
        return , $t
    } finally { $con.Close() }
}

$system = @('master', 'model', 'msdb', 'tempdb')
$dbs = Frage 'master' "SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name"

$artName = @{ 1 = 'Wand'; 4 = 'Decke'; 5 = 'Dach'; 11 = 'Bodenplatte' }
Write-Output "Datenbanken auf $Instanz, die als Vorlage taugen:"
Write-Output ""
$gefunden = 0

foreach ($r in $dbs.Rows) {
    $db = [string]$r['name']
    if ($system -contains $db) { continue }
    if ($db -eq $Laufend) { continue }

    try {
        $t = Frage $db @"
SELECT p.LongDesc AS prj, e.ElementType AS art, COUNT(*) AS n
FROM BmElement e JOIN PrProject p ON p.UUID = e.ProjectUUID
WHERE e.RepositoryType = 3
GROUP BY p.LongDesc, e.ElementType
ORDER BY p.LongDesc, e.ElementType
"@
    } catch {
        # Keine Projektdatenbank oder nicht lesbar -- still uebergehen, das ist
        # kein Fehler, sondern der Normalfall bei fremden Datenbanken.
        continue
    }
    if ($t.Rows.Count -eq 0) { continue }

    $projekte = @{}
    foreach ($z in $t.Rows) {
        $p = [string]$z['prj']
        if ($Projekt -and $p -notlike "*$Projekt*") { continue }
        if (-not $projekte.ContainsKey($p)) { $projekte[$p] = @{} }
        $projekte[$p][[int]$z['art']] = [int]$z['n']
    }
    if ($projekte.Count -eq 0) { continue }

    $gefunden++
    Write-Output "  $db"
    foreach ($p in ($projekte.Keys | Sort-Object)) {
        $teile = @()
        foreach ($a in ($projekte[$p].Keys | Sort-Object)) {
            $bez = if ($artName.ContainsKey([int]$a)) { $artName[[int]$a] } else { "Art $a" }
            $teile += "$bez $($projekte[$p][$a])"
        }
        Write-Output ("     {0,-34} {1}" -f $p, ($teile -join ', '))
    }
}

if ($gefunden -eq 0) {
    Write-Output "  keine"
    Write-Output ""
    Write-Output "Ohne Vorlage laesst sich kein Bauteil anlegen. Zwei Wege:"
    Write-Output "  - eine Sicherung als Seitendatenbank einspielen, die das gesuchte Bauteil fuehrt"
    Write-Output "  - oder ein Exemplar einmal in der Oberflaeche zeichnen lassen"
} else {
    Write-Output ""
    Write-Output "Verwendung: -VorlageDatenbank <Name>. Nimm eine Datenbank, die ein Projekt"
    Write-Output "GLEICHEN NAMENS mit der gesuchten Bauteilart fuehrt -- sonst passen die"
    Write-Output "Katalog- und Gebaeudeverweise nicht."
}
