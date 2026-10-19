# Sichere-Projektdatenbank.ps1 -- Rettungssicherung der Hottgenroth-Projektdatenbank
#
# WOZU
# Wenn in der Software etwas verloren gegangen ist -- eine geloeschte Etage, ein
# geloeschtes Bauteil -- dann steht der alte Stand meist noch in der Datenbank:
# Hottgenroth haelt die Aenderung im Speicher und schreibt sie erst beim Speichern
# bzw. beim Schliessen zurueck. Dieses Skript friert den Stand ein, der JETZT auf
# der Platte liegt, und sagt dazu, was darin steckt -- vor allem die Zahl der
# Geschosse je Projekt. Daran siehst du, ob die Etage noch drin ist.
#
# ES LAEUFT ABSICHTLICH BEI OFFENER SOFTWARE
# Die Sicherung ist COPY_ONLY und nur lesend: kein Byte geht in die Datenbank,
# keine Sicherungskette wird gestoert, die laufende Anwendung merkt nichts. Darum
# fehlt hier die Sperre aus bauteile\tools\Testzustand.ps1, die eine geschlossene
# Software verlangt -- die waere hier genau falsch.
#
# REIHENFOLGE IM NOTFALL
#   1. Erst sichern (dieses Skript). Das friert den guten Stand ein.
#   2. Dann im Task-Manager 'Energie.exe' beenden -- NICHT das Fenster zumachen.
#      Zumachen ist der Moment, in dem zurueckgeschrieben wird.
#   3. Pruefen, dass kein 'Energie.exe' uebrig ist. Eine verwaiste Instanz
#      schreibt still weiter.
#   4. Mit -Einspielen die Sicherung als Seitendatenbank daneben legen und das
#      eine Projekt mit bauteile\tools\Restore-Projekt.ps1 zurueckkopieren.
#
#   .\Sichere-Projektdatenbank.ps1
#   .\Sichere-Projektdatenbank.ps1 -Projekt Mueller
#   .\Sichere-Projektdatenbank.ps1 -Pruefen
#   .\Sichere-Projektdatenbank.ps1 -Einspielen "C:\...\HsetuPrjData-2026....bak"

[CmdletBinding()]
param(
    [switch]$Pruefen,
    [string]$Einspielen = '',
    [string]$Projekt = '',
    [string]$Ablage = "$env:USERPROFILE\Hottgenroth-Rettung",
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData",
    [string]$DatenOrdner = "C:\ProgramData\HSETU\ApplicationService\Data"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

function Sql([string]$db, [string]$befehl, [int]$zeitlimit = 1800) {
    $con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$db;Integrated Security=true;TrustServerCertificate=true"
    $con.Open()
    try {
        $c = $con.CreateCommand(); $c.CommandText = $befehl; $c.CommandTimeout = $zeitlimit
        $t = New-Object System.Data.DataTable
        [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($t)
        return , $t
    } finally { $con.Close() }
}

function Zeile($text) { Write-Host "  $text" }
function Tabelle($t) { $t | Format-Table -AutoSize | Out-String | Write-Host }

# Einfache Anfuehrungszeichen verdoppeln -- die Suchworte kommen vom Nutzer.
function Lit([string]$s) { return $s.Replace("'", "''") }

Write-Host ""
Write-Host "  Hottgenroth-Projektdatenbank sichern" -ForegroundColor Cyan
Write-Host "  ------------------------------------"
Write-Host ""

# ----------------------------------------------------------- Instanz erreichbar

try {
    $v = Sql 'master' "SELECT SERVERPROPERTY('ProductVersion') AS v"
    Zeile ("Instanz {0} erreichbar, SQL Server {1}" -f $Instanz, $v.Rows[0]['v'])
} catch {
    Write-Host "  Die Instanz $Instanz antwortet nicht." -ForegroundColor Red
    Zeile "Vorhandene LocalDB-Instanzen auf diesem Rechner:"
    try { sqllocaldb info | ForEach-Object { Zeile "  $_" } } catch { Zeile "  (sqllocaldb nicht gefunden)" }
    Zeile "Mit -Instanz den richtigen Namen uebergeben."
    exit 1
}

$da = Sql 'master' "SELECT name FROM sys.databases WHERE name = '$(Lit $Datenbank)'"
if ($da.Rows.Count -eq 0) {
    Write-Host "  Datenbank '$Datenbank' gibt es auf dieser Instanz nicht." -ForegroundColor Red
    Zeile "Vorhanden sind:"
    foreach ($r in (Sql 'master' "SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name").Rows) { Zeile "  $($r['name'])" }
    exit 1
}

# ----------------------------------------------- Laeuft die Software gerade noch

$offen = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(Energie|Hott)' })
Write-Host ""
if ($offen.Count -gt 0) {
    Zeile "Hottgenroth laeuft noch:"
    foreach ($p in $offen) {
        $start = ''
        try { $start = $p.StartTime.ToString('dd.MM.yyyy HH:mm') } catch { $start = 'unbekannt' }
        Zeile ("  {0} (PID {1}), gestartet {2}" -f $p.ProcessName, $p.Id, $start)
    }
    Zeile "Die Sicherung nimmt den Stand von der PLATTE -- nicht den aus dem Programm."
    Zeile "Genau das ist hier gewollt: der Stand vor dem Loeschen."
} else {
    Zeile "Kein Hottgenroth-Prozess laeuft. Die Platte traegt damit den letzten"
    Zeile "gespeicherten Stand. War das Loeschen schon gespeichert, ist es auch hier drin."
}

# ------------------------------------------- Wann wurde zuletzt geschrieben

try {
    foreach ($r in (Sql $Datenbank "SELECT name FROM sys.columns WHERE object_id = OBJECT_ID('PrProject') AND name LIKE 'Stamp%' ORDER BY name").Rows) {
        $sn = $r['name']
        $mx = Sql $Datenbank "SELECT MAX([$sn]) AS m FROM PrProject"
        if ($mx.Rows[0]['m'] -isnot [DBNull]) { Zeile ("Letzter Schreibzugriff laut PrProject.$sn : {0}" -f $mx.Rows[0]['m']) }
    }
} catch { }

try {
    foreach ($r in (Sql 'master' "SELECT physical_name AS p FROM sys.master_files WHERE database_id = DB_ID('$(Lit $Datenbank)') AND type = 0").Rows) {
        $f = Get-Item -LiteralPath $r['p'] -ErrorAction SilentlyContinue
        if ($f) { Zeile ("Datenbankdatei zuletzt geaendert: {0:dd.MM.yyyy HH:mm:ss}" -f $f.LastWriteTime) }
    }
} catch { }

# -------------------------------------------------------------- Was steckt drin

# Geschosse aus BmFloor, Bauteile aus BmElement -- dieselbe Abfrage, mit der
# Testzustand.ps1 seine Zustaende belegt.
$rumpf = "SELECT p.LongDesc AS Projekt, " +
         "(SELECT COUNT(*) FROM BmFloor f WHERE f.ProjectUUID = p.UUID) AS Geschosse, " +
         "(SELECT COUNT(*) FROM BmElement e WHERE e.ProjectUUID = p.UUID) AS Bauteile " +
         "FROM PrProject p"
$wo = ''
if ($Projekt -ne '') { $wo = " WHERE p.LongDesc LIKE N'%$(Lit $Projekt)%'" }

$t = Sql $Datenbank ($rumpf + $wo + " ORDER BY p.LongDesc")
Write-Host ""
Zeile "Inhalt auf der Platte:"
Tabelle $t
if ($t.Rows.Count -eq 0) { Zeile "Kein Projekt gefunden -- Suchwort in -Projekt pruefen." }

if ($Pruefen) {
    Write-Host ""
    Zeile "Nur geprueft, nichts gesichert. Ohne -Pruefen nochmal aufrufen, um zu sichern."
    Write-Host ""
    exit 0
}

# ------------------------------------------------------------------ Einspielen

if ($Einspielen -ne '') {
    if (-not (Test-Path -LiteralPath $Einspielen)) { throw "Sicherungsdatei nicht gefunden: $Einspielen" }

    # Der Zielname wird erzeugt, nicht uebergeben: so kann dieser Zweig die
    # laufende Datenbank nicht ueberschreiben, auch nicht bei Tippfehlern.
    $zdb = 'HsetuRettung_' + (Get-Date -Format 'yyyyMMdd_HHmm')
    Write-Host ""
    Zeile "Spiele die Sicherung als SEITENDATENBANK '$zdb' ein."
    Zeile "Die laufende Datenbank '$Datenbank' wird dabei NICHT angefasst."

    # Logische Dateinamen aus der Sicherung lesen statt sie zu raten -- sie
    # heissen nur solange 'HsetuPrjData.data', wie niemand die DB umbenannt hat.
    $moves = @()
    foreach ($r in (Sql 'master' "RESTORE FILELISTONLY FROM DISK = N'$(Lit $Einspielen)'").Rows) {
        if ($r['Type'] -eq 'L') { $ziel = Join-Path $DatenOrdner ($zdb + '_log.ldf') }
        else                    { $ziel = Join-Path $DatenOrdner ($zdb + '.mdf') }
        $moves += "MOVE N'$(Lit $r['LogicalName'])' TO N'$ziel'"
    }
    Sql 'master' ("RESTORE DATABASE [$zdb] FROM DISK = N'$(Lit $Einspielen)' WITH " + ($moves -join ', ') + ", RECOVERY") | Out-Null

    Write-Host ""
    Zeile "Eingespielt als '$zdb'. Inhalt:"
    Tabelle (Sql $zdb ($rumpf + " ORDER BY p.LongDesc"))
    Zeile "Das eine Projekt aus der Seitendatenbank zurueckkopieren macht"
    Zeile "bauteile\tools\Restore-Projekt.ps1 -- es laesst die anderen Projekte in Ruhe:"
    Zeile "  .\Restore-Projekt.ps1 -Projekt <Name> -Quelle $zdb -Ziel $Datenbank"
    Write-Host ""
    exit 0
}

# --------------------------------------------------------------------- Sichern

if (-not (Test-Path -LiteralPath $Ablage)) { New-Item -ItemType Directory -Path $Ablage -Force | Out-Null }
$stempel = Get-Date -Format 'yyyyMMdd_HHmmss'
$bak = Join-Path $Ablage "$Datenbank-$stempel.bak"

Write-Host ""
Zeile "Sichere '$Datenbank' nach:"
Zeile "  $bak"
Zeile "Das dauert einige Minuten -- die Datenbank ist meist mehrere Gigabyte gross."

Sql 'master' "BACKUP DATABASE [$Datenbank] TO DISK = N'$(Lit $bak)' WITH INIT, COPY_ONLY, CHECKSUM" | Out-Null

Zeile "Pruefe die Sicherung ..."
Sql 'master' "RESTORE VERIFYONLY FROM DISK = N'$(Lit $bak)' WITH CHECKSUM" | Out-Null

$gb = [math]::Round((Get-Item -LiteralPath $bak).Length / 1GB, 2)
Write-Host ""
Write-Host ("  Fertig. Sicherung geprueft, {0} GB." -f $gb) -ForegroundColor Green
Zeile $bak

# Die ganze Geschosstabelle als CSV daneben: so muss niemand Spaltennamen raten,
# um nachzusehen, welches Geschoss fehlt.
try {
    $g = Sql $Datenbank "SELECT p.LongDesc AS Projekt, f.* FROM BmFloor f JOIN PrProject p ON p.UUID = f.ProjectUUID$wo"
    $csv = Join-Path $Ablage "geschosse-$stempel.csv"
    $g | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8 -Delimiter ';'
    Zeile "Geschossliste zum Nachsehen: $csv"
} catch { }

Write-Host ""
Zeile "Naechster Schritt: im Task-Manager 'Energie.exe' BEENDEN (Task beenden),"
Zeile "nicht das Fenster zumachen. Danach pruefen, dass kein Energie.exe uebrig ist."
Write-Host ""
