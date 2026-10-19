# Testzustand.ps1 -- reproduzierbare Ausgangszustaende fuer den Pruefstand
#
# WOZU
# Ein Test ist nur dann aussagekraeftig, wenn er immer beim selben Zustand
# anfaengt. Sonst misst der zweite Lauf etwas anderes als der erste, und ein
# Fehlschlag laesst sich nicht zuordnen.
#
# WIE
# Ein Zustand ist eine SEITENDATENBANK mit dem eingefrorenen Stand. Zuruecksetzen
# heisst dann: die Zeilen dieses einen Projekts aus der Seitendatenbank
# zurueckkopieren -- das macht Restore-Projekt.ps1, und es laesst die anderen
# vierzig Projekte in Ruhe.
#
# WARUM NICHT AUS EINER TSV-AUFNAHME
# Naheliegend waere, die Aufnahmen aus Snapshot-Projekt.ps1 zurueckzuspielen --
# sie sind klein und versionierbar. Dafuer braeuchte es aber eine typgetreue
# Ruecksetzung ueber 152 Spalten in 39 Tabellen, und ein stiller Konvertierungs-
# fehler waere genau die Art Fehler, die dieser Pruefstand finden soll. Der Weg
# ueber die Seitendatenbank benutzt erprobte Technik.
#
# PREIS
# Je Zustand rund 2,5 GB auf der Platte. Deshalb wenige Zustaende halten und
# ungebrauchte mit -Entfernen loeschen.
#
#   .\Testzustand.ps1 -Sichern  -Zustand rechteck -Projekt Test0001
#   .\Testzustand.ps1 -Zuruecksetzen -Zustand rechteck -Projekt Test0001
#   .\Testzustand.ps1 -Liste
#   .\Testzustand.ps1 -Entfernen -Zustand rechteck

[CmdletBinding()]
param(
    [switch]$Sichern,
    [switch]$Zuruecksetzen,
    [switch]$Liste,
    [switch]$Entfernen,
    [string]$Zustand = '',
    [string]$Projekt = '',
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData",
    [string]$Ablage = "C:\ProgramData\HSETU\ApplicationService\Data"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

function Sql([string]$db, [string]$befehl, [int]$zeitlimit = 600) {
    $con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$db;Integrated Security=true;TrustServerCertificate=true"
    $con.Open()
    try {
        $c = $con.CreateCommand(); $c.CommandText = $befehl; $c.CommandTimeout = $zeitlimit
        $t = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($t)
        return , $t
    } finally { $con.Close() }
}

$praefix = 'HsetuTest_'

if ($Liste -or (-not $Sichern -and -not $Zuruecksetzen -and -not $Entfernen)) {
    $t = Sql 'master' "SELECT name, (SELECT SUM(size)*8/1024 FROM sys.master_files WHERE database_id=d.database_id) AS mb FROM sys.databases d WHERE name LIKE '$praefix%' ORDER BY name"
    if ($t.Rows.Count -eq 0) { Write-Host "Keine gesicherten Testzustaende." }
    else {
        Write-Host "Gesicherte Testzustaende:"
        foreach ($r in $t.Rows) { Write-Host ("  {0,-24} {1,6} MB" -f ($r['name'] -replace "^$praefix", ''), $r['mb']) }
    }
    if (-not $Liste) { Write-Host "`nOhne Schalter wird nur aufgelistet. Siehe Kopf der Datei." }
    return
}

if (-not $Zustand) { throw "-Zustand wird gebraucht." }
if ($Zustand -notmatch '^[A-Za-z0-9_-]+$') { throw "Zustandsname darf nur Buchstaben, Ziffern, - und _ enthalten." }
$zdb = $praefix + $Zustand

if ($Entfernen) {
    Sql 'master' "IF DB_ID('$zdb') IS NOT NULL BEGIN ALTER DATABASE [$zdb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$zdb]; END" | Out-Null
    Write-Host "Testzustand '$Zustand' entfernt." -ForegroundColor Green
    return
}

# Ab hier wird geschrieben -- keine Hottgenroth-Anwendung darf offen sein.
$pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }

if ($Sichern) {
    if (-not $Projekt) { throw "-Projekt wird gebraucht, damit der Zustand nachvollziehbar ist." }
    $bak = Join-Path $env:TEMP "testzustand-$Zustand.bak"
    Write-Host "Sichere '$Datenbank' ..."
    Sql 'master' "BACKUP DATABASE [$Datenbank] TO DISK = N'$bak' WITH INIT, COPY_ONLY" | Out-Null
    Write-Host "Spiele als '$zdb' ein ..."
    Sql 'master' ("RESTORE DATABASE [$zdb] FROM DISK = N'$bak' WITH " +
        "MOVE N'HsetuPrjData.data' TO N'$Ablage\$zdb.mdf', " +
        "MOVE N'HsetuPrjData.log'  TO N'$Ablage\${zdb}_log.ldf', REPLACE, RECOVERY") | Out-Null
    Remove-Item $bak -Force -ErrorAction SilentlyContinue

    $t = Sql $zdb "SELECT p.LongDesc AS n, (SELECT COUNT(*) FROM BmElement e WHERE e.ProjectUUID=p.UUID) AS bt, (SELECT COUNT(*) FROM BmFloor f WHERE f.ProjectUUID=p.UUID) AS ge FROM PrProject p WHERE p.LongDesc LIKE '%$Projekt%'"
    foreach ($r in $t.Rows) {
        Write-Host ("Zustand '$Zustand' gesichert: {0} -- {1} Geschosse, {2} Bauteile" -f $r['n'], $r['ge'], $r['bt']) -ForegroundColor Green
    }
    return
}

if ($Zuruecksetzen) {
    if (-not $Projekt) { throw "-Projekt wird gebraucht." }
    $t = Sql 'master' "SELECT name FROM sys.databases WHERE name = '$zdb'"
    if ($t.Rows.Count -eq 0) { throw "Testzustand '$Zustand' gibt es nicht. Erst mit -Sichern anlegen." }
    $rp = Join-Path $PSScriptRoot "Restore-Projekt.ps1"
    if (-not (Test-Path $rp)) { throw "Restore-Projekt.ps1 nicht gefunden." }
    & $rp -Projekt $Projekt -Quelle $zdb -Instanz $Instanz -Ziel $Datenbank | Out-Null
    $t = Sql $Datenbank "SELECT (SELECT COUNT(*) FROM BmElement e JOIN PrProject p ON p.UUID=e.ProjectUUID WHERE p.LongDesc LIKE '%$Projekt%') AS bt, (SELECT COUNT(*) FROM BmFloor f JOIN PrProject p ON p.UUID=f.ProjectUUID WHERE p.LongDesc LIKE '%$Projekt%') AS ge"
    Write-Host ("Auf '$Zustand' zurueckgesetzt: {0} Geschosse, {1} Bauteile" -f $t.Rows[0]['ge'], $t.Rows[0]['bt']) -ForegroundColor Green
}
