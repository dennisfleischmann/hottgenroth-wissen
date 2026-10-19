# Restore-Projekt.ps1 — ein einzelnes Projekt aus einer Sicherung zurückholen
#
# Ein Voll-Restore von HsetuPrjData setzt ALLE Projekte zurück — in dieser
# Datenbank über 40. Wer nur eines zurückbraucht, spielt die Sicherung als
# Seitendatenbank ein und kopiert daraus die Zeilen dieses Projekts.
#
# Vorgehen je Tabelle mit Projektbezug: die Zeilen des Projekts löschen und aus
# der Quelle neu einfügen. Damit sind gelöschte UND veränderte Zeilen in einem
# Zug erledigt. Die Datenbank führt keine Fremdschlüssel (geprüft: 0), die
# Reihenfolge ist deshalb frei.
#
# Das Journal (PrJournal, PrJournalEntry) bleibt ausgenommen — ein Protokoll
# soll seine Geschichte behalten, auch die des Löschvorgangs.
#
# Beispiel:
#   .\Restore-Projekt.ps1 -Projekt "Pohlstra" -Quelle HsetuPrjProbe -Probelauf
#   .\Restore-Projekt.ps1 -Projekt "Pohlstra" -Quelle HsetuPrjProbe

param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Quelle,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Ziel = "HsetuPrjData",
    [string[]]$Ausnehmen = @('PrJournal', 'PrJournalEntry'),
    [switch]$Probelauf
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Data
. (Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1")
Assert-SoftwareZu -Erlaubt:$Probelauf

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Ziel;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    # --- Projekt in der QUELLE auflösen (im Ziel kann es unvollständig sein) ---
    $cmd = $con.CreateCommand()
    $g = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$g)) {
        $cmd.CommandText = "SELECT UUID, LongDesc FROM [$Quelle].dbo.PrProject WHERE UUID=@p"
    } else {
        $cmd.CommandText = "SELECT UUID, LongDesc FROM [$Quelle].dbo.PrProject WHERE LongDesc LIKE @p"
        $Projekt = "%$Projekt%"
    }
    [void]$cmd.Parameters.AddWithValue("@p", $Projekt)
    $tp = New-Object System.Data.DataTable; $tp.Load($cmd.ExecuteReader())
    if ($tp.Rows.Count -ne 1) { throw "Projekt in $Quelle nicht eindeutig: $($tp.Rows.Count) Treffer." }
    $projektId = [guid]$tp.Rows[0].UUID
    Write-Host "Projekt : $($tp.Rows[0].LongDesc)" -ForegroundColor Cyan
    Write-Host "Quelle  : $Quelle   ->   Ziel: $Ziel" -ForegroundColor Cyan
    Write-Host ""

    # --- Tabellen mit Projektbezug, die es in BEIDEN Datenbanken gibt ---
    $cmd = $con.CreateCommand()
    $cmd.CommandText = @"
SELECT t.name AS tabelle, c.name AS spalte
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id AND c.name IN ('ProjectUUID','ProjectUId')
WHERE EXISTS (SELECT 1 FROM [$Quelle].sys.tables qt WHERE qt.name = t.name)
ORDER BY t.name
"@
    $tt = New-Object System.Data.DataTable; $tt.Load($cmd.ExecuteReader())

    $tx = $null
    if (-not $Probelauf) { $tx = $con.BeginTransaction() }
    $gesamtWeg = 0; $gesamtNeu = 0; $betroffen = 0

    foreach ($zeile in $tt.Rows) {
        $name = [string]$zeile.tabelle
        $spalte = [string]$zeile.spalte
        if ($Ausnehmen -contains $name) { continue }

        # Spaltenliste ausdruecklich aufbauen - SELECT * verlaesst sich auf
        # gleiche Spaltenreihenfolge in beiden Datenbanken.
        $c = $con.CreateCommand(); $c.Transaction = $tx
        $c.CommandText = "SELECT name FROM sys.columns WHERE object_id = OBJECT_ID(@t) ORDER BY column_id"
        [void]$c.Parameters.AddWithValue("@t", $name)
        $sp = New-Object System.Data.DataTable; $sp.Load($c.ExecuteReader())
        $liste = (($sp.Rows | ForEach-Object { "[$($_.name)]" }) -join ", ")

        $z1 = $con.CreateCommand(); $z1.Transaction = $tx
        $z1.CommandText = "SELECT (SELECT COUNT(*) FROM [$name] WHERE [$spalte]=@p) AS ziel, (SELECT COUNT(*) FROM [$Quelle].dbo.[$name] WHERE [$spalte]=@p) AS quelle"
        [void]$z1.Parameters.AddWithValue("@p", $projektId)
        $r = New-Object System.Data.DataTable; $r.Load($z1.ExecuteReader())
        $imZiel = [int]$r.Rows[0].ziel; $inQuelle = [int]$r.Rows[0].quelle
        if ($imZiel -eq 0 -and $inQuelle -eq 0) { continue }

        if (-not $Probelauf) {
            $d = $con.CreateCommand(); $d.Transaction = $tx
            $d.CommandText = "DELETE FROM [$name] WHERE [$spalte]=@p"
            [void]$d.Parameters.AddWithValue("@p", $projektId)
            [void]$d.ExecuteNonQuery()

            $i = $con.CreateCommand(); $i.Transaction = $tx
            $i.CommandText = "INSERT INTO [$name] ($liste) SELECT $liste FROM [$Quelle].dbo.[$name] WHERE [$spalte]=@p"
            [void]$i.Parameters.AddWithValue("@p", $projektId)
            [void]$i.ExecuteNonQuery()
        }

        if ($imZiel -ne $inQuelle) {
            "  {0,-42} {1,5} -> {2,5}" -f $name, $imZiel, $inQuelle
            $betroffen++
        }
        $gesamtWeg += $imZiel; $gesamtNeu += $inQuelle
    }

    Write-Host ""
    Write-Host "$betroffen Tabellen mit abweichender Zeilenzahl. Insgesamt $gesamtWeg Zeilen ersetzt durch $gesamtNeu."
    if ($Probelauf) { Write-Host "Probelauf - nichts geschrieben." -ForegroundColor Yellow }
    else { $tx.Commit(); Write-Host "Zurueckgeholt." -ForegroundColor Green }
} finally { $con.Close() }
