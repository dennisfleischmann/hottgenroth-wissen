# Remove-Geschoss.ps1 -- ein Geschoss samt allem, was darin steht, entfernen
#
# Das Gegenstueck zu New-Geschoss.ps1. Ein Geschoss besteht aus vier Zeilen, und
# alle vier muessen weg -- sonst bleibt ein halbes Geschoss stehen, das die
# Oberflaeche entweder ignoriert oder falsch anzeigt:
#
#   BmFloor                        die Kenngroessen
#   BmFloorData                    Rechenergebnisse, gleiche UUID
#   BmData 'CADXMLData'            <floor GUID=... elevation=... type=...>
#   BmData 'is_auto_generated'     der Wert 1
#
# WAS SONST NOCH DARANHAENGT
# Die Bauteile. Sie fuehren ihr Geschoss nicht in einer Spalte, sondern im
# Attribut floor= ihrer Zeichnung. Wer nur die Geschosszeilen loescht,
# hinterlaesst Waende und Daecher, die auf ein Geschoss zeigen, das es nicht
# mehr gibt. Deshalb wird dafuer Remove-Bauteile.ps1 aufgerufen, statt die
# Logik ein zweites Mal zu schreiben.
#
# DANACH WIRD AUFGERAEUMT
# SortNum wird fuer alle verbliebenen Geschosse neu vergeben und FloorCount im
# building_data nachgezogen -- das ist die Zahl der Geschosse UEBER dem EG,
# also FloorType 1 und 2. Beides genau wie beim Anlegen.
#
# SICHERUNG
# Loeschen ist die einzige Aktion hier, die sich nicht durch Neuschreiben
# beheben laesst. Probelauf zuerst.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Geschoss,
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

if (-not $OhneSoftwarepruefung -and -not $Probelauf) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

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

    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, LongDesc, ElevationOfRefHeight FROM BmFloor WHERE ProjectUUID=@p"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $gs = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $gs += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1); Bezug = [double]$l.GetValue(2) } }
    $l.Close()

    $ziel = @($gs | Where-Object { $_.Name -like "*$Geschoss*" })
    if ($ziel.Count -ne 1) { throw "Geschoss nicht eindeutig: $($ziel.Count) Treffer fuer '$Geschoss'. $(($gs.Name) -join ', ')" }
    $ziel = $ziel[0]
    if ($gs.Count -le 1) { throw "'$($ziel.Name)' ist das letzte Geschoss des Projekts -- ein Gebaeude ohne Geschoss waere kaputt." }

    Write-Host "Projekt : $($prj.Name)"
    Write-Host "Geschoss: $($ziel.Name) ($($ziel.Bezug)) -- $(($gs.Name) -join ', ')"
    Write-Host ""

    # 1. Bauteile des Geschosses -- eigenes Werkzeug, eigener Probelauf.
    $bt = Join-Path $PSScriptRoot "Remove-Bauteile.ps1"
    if (-not (Test-Path $bt)) { throw "Remove-Bauteile.ps1 nicht gefunden neben diesem Skript." }
    & $bt -Projekt $Projekt -Geschoss $ziel.Name -Probelauf:$Probelauf -OhneSoftwarepruefung `
          -Instanz $Instanz -Datenbank $Datenbank | ForEach-Object { "  $_" }

    # 2. Die vier Geschosszeilen.
    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        function Weg([string]$sql, [string]$was) {
            $u = $con.CreateCommand(); if ($tx) { $u.Transaction = $tx }
            if ($tx) { $u.CommandText = $sql; $n = $u.ExecuteNonQuery() }
            else { $u.CommandText = ($sql -replace '^DELETE FROM', 'SELECT COUNT(*) FROM'); $n = [int]$u.ExecuteScalar() }
            Write-Host ("  {0,-28} {1,4} Zeilen" -f $was, $n)
        }
        Weg "DELETE FROM BmData WHERE ReferenceUUID = '$($ziel.Id)'" 'BmData (Geschosszeichnung)'
        Weg "DELETE FROM BmFloorData WHERE UUID = '$($ziel.Id)'"     'BmFloorData'
        Weg "DELETE FROM BmFloor WHERE UUID = '$($ziel.Id)'"         'BmFloor'

        if ($tx) {
            $u = $con.CreateCommand(); $u.Transaction = $tx
            $u.CommandText = "WITH r AS (SELECT UUID, ROW_NUMBER() OVER (ORDER BY ElevationOfRefHeight DESC) AS n " +
                             "FROM BmFloor WHERE ProjectUUID=@p) UPDATE f SET SortNum=r.n FROM BmFloor f JOIN r ON r.UUID=f.UUID"
            [void]$u.Parameters.AddWithValue("@p", $prj.Id)
            [void]$u.ExecuteNonQuery()

            # FloorCount = Geschosse ueber dem EG (FloorType 1 und 2).
            $u = $con.CreateCommand(); $u.Transaction = $tx
            $u.CommandText = "SELECT COUNT(*) FROM BmFloor WHERE ProjectUUID=@p AND FloorType IN (1,2)"
            [void]$u.Parameters.AddWithValue("@p", $prj.Id)
            $fc = [int]$u.ExecuteScalar()
            $u = $con.CreateCommand(); $u.Transaction = $tx
            [void]$u.Parameters.AddWithValue("@p", $prj.Id)
            [void]$u.Parameters.AddWithValue("@neu", $fc)
            $u.CommandText = "UPDATE d SET ClassValue = " +
                             "STUFF(CAST(d.ClassValue AS nvarchar(max)), " +
                             "  CHARINDEX('FloorCount=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) + 12, " +
                             "  CHARINDEX(CHAR(34), CAST(d.ClassValue AS nvarchar(max)), CHARINDEX('FloorCount=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) + 12) " +
                             "  - CHARINDEX('FloorCount=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) - 12, " +
                             "  CAST(@neu AS varchar(4))) " +
                             "FROM BmData d JOIN BmBuilding b ON b.UUID=d.ReferenceUUID " +
                             "WHERE d.ProjectUUID=@p AND d.LongDesc='CADXMLData' " +
                             "  AND CHARINDEX('FloorCount=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) > 0"
            [void]$u.ExecuteNonQuery()
            Write-Host "  ~ FloorCount auf $fc gesetzt"
            $tx.Commit()
            Write-Host "`nGeschoss '$($ziel.Name)' entfernt." -ForegroundColor Green
        } else { Write-Host "`n[Probelauf] Nichts geloescht." -ForegroundColor Yellow }
    } catch { if ($tx) { $tx.Rollback() }; throw }

    $c = $con.CreateCommand()
    $c.CommandText = "SELECT SortNum, LongDesc, FloorType, ElevationOfRefHeight FROM BmFloor WHERE ProjectUUID=@p ORDER BY SortNum"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $l = $c.ExecuteReader()
    Write-Host "`n  Nr  Geschoss    Typ   Hoehenlage"
    while ($l.Read()) {
        Write-Host ("  {0,2}  {1,-10}  {2,3}   {3,8:N2}" -f $l.GetValue(0), $l.GetValue(1), $l.GetValue(2), [double]$l.GetValue(3))
    }
    $l.Close()
}
finally { $con.Close() }
