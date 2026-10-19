# Remove-Bauteile.ps1 -- Bauteile eines Projekts loeschen
#
# Das Gegenstueck zu den New-*-Skripten. Loeschen ist die einzige Aktion hier,
# die sich nicht durch Neuschreiben beheben laesst -- deshalb: Probelauf zuerst,
# Sicherung vorher, und die Software muss zu sein.
#
# WAS ALLES DARANHAENGT
# Ein Bauteil ist nicht eine Zeile, sondern eine ueber mehrere Tabellen. Welche
# Beisatztabellen es gibt, wird nicht aufgezaehlt, sondern aus dem Schema
# gelesen: jede Tabelle, die BmElement... heisst und eine Spalte UUID fuehrt.
# So bleibt das Skript richtig, wenn ein Projekt Bauteilarten enthaelt, die hier
# noch nie vorkamen -- Gauben, Fenster, Schornsteine.
#
# Dazu die Zeichnung in BmData (ueber ReferenceUUID) und die Verweise in
# BmElementReference, die von beiden Seiten zeigen koennen.
#
# WAS ES NICHT ANFASST
# Geschosse, Gebaeude, Zonen, Raeume. Wer das Geschoss mitloeschen will, macht
# das in der Oberflaeche -- dort haengt mehr daran, als hier sichtbar ist.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    # Nur Bauteile dieses Geschosses. Leer = alle. Das Geschoss steht in der
    # Zeichnung, nicht in einer Spalte, deshalb wird ueber die XML gefiltert.
    [string]$Geschoss = '',
    # Nur Bauteile dieser Art, z. B. 'AW' oder 'Dach'. Leer = alle.
    [string]$NamePraefix = '',
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

if (-not $OhneSoftwarepruefung) {
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

    $gfId = $null
    if ($Geschoss) {
        $c = $con.CreateCommand()
    # Das floor-Attribut zeigt auf die GUID der GESCHOSSZEICHNUNG, nicht auf
    # BmFloor.UUID. Beide sind nur gleich, wenn New-Geschoss.ps1 das Geschoss
    # angelegt hat. In jedem importierten oder in HottCAD gebauten Projekt weichen
    # sie ab -- die Bauteile haengen dann an keinem Geschoss und sind in der
    # Software unsichtbar, waehrend in der Datenbank alles zu stimmen scheint.
    # Gemessen am 24.08.2026 an XWSKQ_Holger Hoffmann: EG und DG kamen aus einer
    # importierten Vorlage, 10 Bauteile blieben unsichtbar. Siehe den Kommentar
    # in Get-Wandsilhouette.ps1, der das seit Langem beschreibt.
        $c.CommandText = "SELECT CASE WHEN CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) > 0 THEN LOWER(SUBSTRING(CAST(d.ClassValue AS nvarchar(max)), CHARINDEX('<floor GUID=' + CHAR(34), CAST(d.ClassValue AS nvarchar(max))) + 13, 36)) ELSE NULL END, f.LongDesc, CAST(f.UUID AS varchar(40)) " +
                         "FROM BmFloor f LEFT JOIN BmData d ON d.ReferenceUUID = f.UUID AND d.LongDesc = 'CADXMLData' " +
                         "WHERE f.ProjectUUID=@p AND f.LongDesc LIKE @g"
        [void]$c.Parameters.AddWithValue("@p", $prj.Id)
        [void]$c.Parameters.AddWithValue("@g", "%$Geschoss%")
        $gg = @(); $l = $c.ExecuteReader()
        while ($l.Read()) { $gg += [pscustomobject]@{
            Id = $(if ($l.IsDBNull(0)) { $l.GetString(2).ToLower() } else { $l.GetString(0) })
            Name = $l.GetString(1) } }
        $l.Close()
        if ($gg.Count -ne 1) { throw "Geschoss nicht eindeutig: $($gg.Count) Treffer fuer '$Geschoss'." }
        $gfId = $gg[0].Id; $gfName = $gg[0].Name
    }

    # Betroffene Bauteile bestimmen.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT e.UUID, e.LongDesc, e.ElementType, ISNULL(CAST(d.ClassValue AS nvarchar(max)),'') " +
                     "FROM BmElement e LEFT JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' " +
                     "WHERE e.ProjectUUID=@p ORDER BY e.LongDesc"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $ziel = @(); $l = $c.ExecuteReader()
    while ($l.Read()) {
        $id = $l.GetGuid(0); $nm = $l.GetString(1); $et = [int]$l.GetValue(2); $xml = $l.GetString(3)
        if ($NamePraefix -and -not $nm.StartsWith($NamePraefix)) { continue }
        if ($gfId -and $xml -notmatch ('floor="' + [regex]::Escape($gfId.ToString()) + '"')) { continue }
        $ziel += [pscustomobject]@{ Id = $id; Name = $nm; Typ = $et }
    }
    $l.Close()

    Write-Host "Projekt : $($prj.Name)"
    if ($gfId) { Write-Host "Geschoss: $gfName" }
    if ($NamePraefix) { Write-Host "Filter  : Name beginnt mit '$NamePraefix'" }
    Write-Host "Betroffen: $($ziel.Count) Bauteile"
    if ($ziel.Count -eq 0) { Write-Host "Nichts zu tun."; return }
    Write-Host ("  " + (($ziel.Name) -join ', '))
    Write-Host ""

    # Beisatztabellen aus dem Schema lesen statt aufzuzaehlen.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT t.name FROM sys.tables t JOIN sys.columns k ON k.object_id=t.object_id AND k.name='UUID' " +
                     "WHERE t.name LIKE 'BmElement%' AND t.name <> 'BmElement' ORDER BY t.name"
    $tabellen = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tabellen += $l.GetString(0) }
    $l.Close()

    $liste = "(" + (($ziel.Id | ForEach-Object { "'$_'" }) -join ',') + ")"
    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        $gesamt = 0
        function Fuehre([string]$sql, [string]$was) {
            $u = $con.CreateCommand(); if ($tx) { $u.Transaction = $tx }
            if ($tx) {
                $u.CommandText = $sql
                $n = $u.ExecuteNonQuery()
            } else {
                $u.CommandText = ($sql -replace '^DELETE FROM', 'SELECT COUNT(*) FROM')
                $n = [int]$u.ExecuteScalar()
            }
            if ($n -gt 0) { Write-Host ("  {0,-32} {1,4} Zeilen" -f $was, $n) }
            return $n
        }
        $gesamt += Fuehre "DELETE FROM BmData WHERE ReferenceUUID IN $liste" 'BmData (Zeichnung)'
        $gesamt += Fuehre "DELETE FROM BmElementReference WHERE ReferenceFromUUID IN $liste OR ReferenceToUUID IN $liste" 'BmElementReference'
        foreach ($t in $tabellen) { $gesamt += Fuehre "DELETE FROM [$t] WHERE UUID IN $liste" $t }
        $gesamt += Fuehre "DELETE FROM BmElement WHERE UUID IN $liste" 'BmElement'

        if ($Probelauf) { Write-Host "`n[Probelauf] $gesamt Zeilen waeren betroffen. Nichts geloescht." -ForegroundColor Yellow }
        else { $tx.Commit(); Write-Host "`n$($ziel.Count) Bauteile geloescht, $gesamt Zeilen." -ForegroundColor Green }
    } catch { if ($tx) { $tx.Rollback() }; throw }
}
finally { $con.Close() }
