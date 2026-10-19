# Copy-Geschosswaende.ps1 -- Waende eines Geschosses in ein anderes uebernehmen
#
# Der uebliche Fall: der Aussenring wiederholt sich ueber alle Geschosse, die
# Innenwaende nicht. Deshalb -Nur OuterContour als Regelfall.
#
# WAS DABEI UMGERECHNET WERDEN MUSS
#
#   floor="..."        auf das Zielgeschoss
#   z jedes Punktes    um die Differenz der ElevationOfRefHeight VERSCHOBEN,
#                      nicht gesetzt. Ein Wandkoerper hat sein z auf der
#                      Geschosshoehe, ein bottom_planes-Block aber auf einer
#                      anderen -- ein absoluter Wert wuerde die Auflageflaechen
#                      auf die Wandhoehe ziehen.
#   GUID               jede Wand bekommt eine neue CAD-Kennung
#   prev/next          muessen auf die KOPIEN zeigen, nicht auf die Originale.
#                      Deshalb wird erst die ganze Zuordnung alt->neu gebaut und
#                      danach ersetzt. Ohne diesen Schritt haengt der neue Ring
#                      am alten Geschoss, und HottCAD zieht das nicht nach.
#   repositories/val   auf die neue BmElement-UUID
#
# Alles Abgeleitete (Flaechen, Volumen) bleibt wie in der Vorlage stehen; die
# Software rechnet es beim naechsten Oeffnen ohnehin neu.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Von,
    [Parameter(Mandatory = $true)][string]$Nach,
    # Leer = alle Waende. Sonst z. B. OuterContour oder Inner.
    [string]$Nur = 'OuterContour',
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture

if (-not $OhneSoftwarepruefung) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

function Kopiere {
    param($Con, $Tx, [string]$Tabelle, [hashtable]$Schluessel, [hashtable]$Neu)
    $wo = (($Schluessel.Keys | ForEach-Object { "[$_] = @k_$_" }) -join ' AND ')
    $c = $Con.CreateCommand(); if ($Tx) { $c.Transaction = $Tx }
    $c.CommandText = "SELECT * FROM [$Tabelle] WHERE $wo"
    foreach ($k in $Schluessel.Keys) { [void]$c.Parameters.AddWithValue("@k_$k", $Schluessel[$k]) }
    $tab = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)
    if ($tab.Rows.Count -ne 1) { throw "Vorlage in $Tabelle nicht eindeutig ($($tab.Rows.Count) Zeilen)." }
    $q = $tab.Rows[0]
    $spalten = @($tab.Columns | Where-Object { $_.ColumnName -ne 'SyncRowVersion' } | ForEach-Object { $_.ColumnName })
    foreach ($k in $Neu.Keys) { if ($spalten -notcontains $k) { throw "$Tabelle hat keine Spalte '$k'." } }
    if (-not $Tx) { return }
    $i = $Con.CreateCommand(); $i.Transaction = $Tx
    $i.CommandText = "INSERT INTO [$Tabelle] (" + (($spalten | ForEach-Object { "[$_]" }) -join ', ') +
                     ") VALUES (" + (($spalten | ForEach-Object { "@$_" }) -join ', ') + ")"
    foreach ($s in $spalten) {
        $wert = if ($Neu.ContainsKey($s)) { $Neu[$s] } else { $q[$s] }
        if ($null -eq $wert) { $wert = [DBNull]::Value }
        [void]$i.Parameters.AddWithValue("@$s", $wert)
    }
    if ($i.ExecuteNonQuery() -ne 1) { throw "INSERT in $Tabelle schlug fehl." }
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
    $gVon  = @($gs | Where-Object { $_.Name -like "*$Von*" })
    $gNach = @($gs | Where-Object { $_.Name -like "*$Nach*" })
    if ($gVon.Count  -ne 1) { throw "Quellgeschoss nicht eindeutig: $($gVon.Count) Treffer fuer '$Von'." }
    if ($gNach.Count -ne 1) { throw "Zielgeschoss nicht eindeutig: $($gNach.Count) Treffer fuer '$Nach'." }
    $gVon = $gVon[0]; $gNach = $gNach[0]
    if ($gVon.Id -eq $gNach.Id) { throw "Quelle und Ziel sind dasselbe Geschoss." }
    $dz = $gNach.Bezug - $gVon.Bezug

    # Waende des Quellgeschosses holen. Das Geschoss steht im XML, nicht in einer Spalte.
    $c = $con.CreateCommand()
    $c.CommandText = "SELECT e.UUID, e.LongDesc, CAST(d.ClassValue AS nvarchar(max)) " +
                     "FROM BmElement e JOIN BmElementWall w ON w.UUID=e.UUID " +
                     "JOIN BmData d ON d.ReferenceUUID=e.UUID AND d.LongDesc='CADXMLData' " +
                     "WHERE e.ProjectUUID=@p ORDER BY e.LongDesc"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $alle = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $alle += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1); Xml = $l.GetString(2) } }
    $l.Close()

    $quelle = @($alle | Where-Object {
        $_.Xml -match ('floor="' + [regex]::Escape($gVon.Id.ToString()) + '"') -and
        (-not $Nur -or $_.Xml -match ('wall_type="' + [regex]::Escape($Nur) + '"'))
    })
    if ($quelle.Count -eq 0) { throw "Keine passenden Waende in '$($gVon.Name)' gefunden." }

    # Erst die ganze Zuordnung alt->neu, dann ersetzen: prev/next muessen auf
    # die Kopien zeigen.
    $karte = @{}
    foreach ($w in $quelle) {
        $alt = [regex]::Match($w.Xml, '<wall [^>]*?GUID="([^"]+)"').Groups[1].Value
        if (-not $alt) { throw "Wand '$($w.Name)' fuehrt keine GUID." }
        $karte[$alt.ToLower()] = [pscustomobject]@{ Cad = [guid]::NewGuid(); Elem = [guid]::NewGuid() }
    }

    # Wandnamen sind PROJEKTWEIT eindeutig, nicht je Geschoss -- an Werner Grotz
    # geprueft: ueber fuenf Geschosse kein Name doppelt. Die Kopien bekommen
    # deshalb die naechsten freien Nummern ihres Praefixes.
    $maxNr = @{}
    foreach ($a in $alle) {
        $m = [regex]::Match($a.Name, '^([A-Za-z]+)\s*(\d+)$')
        if ($m.Success) {
            $pre = $m.Groups[1].Value.ToUpper(); $nr = [int]$m.Groups[2].Value
            if (-not $maxNr.ContainsKey($pre) -or $maxNr[$pre] -lt $nr) { $maxNr[$pre] = $nr }
        }
    }

    Write-Host "Projekt : $($prj.Name)"
    Write-Host "Von     : $($gVon.Name) ($($gVon.Bezug.ToString('0.00',$inv)) m)"
    Write-Host "Nach    : $($gNach.Name) ($($gNach.Bezug.ToString('0.00',$inv)) m)   Versatz dz = $($dz.ToString('0.00',$inv)) m"
    Write-Host "Filter  : $(if ($Nur) { $Nur } else { '(alle)' })   -> $($quelle.Count) Waende"
    Write-Host ""

    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        foreach ($w in $quelle) {
            $altCad = [regex]::Match($w.Xml, '<wall [^>]*?GUID="([^"]+)"').Groups[1].Value.ToLower()
            $neu = $karte[$altCad]
            $x = $w.Xml

            # Geschoss.
            $x = $x -replace ('floor="' + [regex]::Escape($gVon.Id.ToString()) + '"'), ('floor="' + $gNach.Id + '"')
            # Eigene Kennung sowie prev/next ueber die Zuordnung.
            $x = [regex]::Replace($x, '(GUID|prev|next)="([^"]+)"', {
                param($m)
                $k = $m.Groups[2].Value.ToLower()
                if ($script:karte.ContainsKey($k)) { $m.Groups[1].Value + '="' + $script:karte[$k].Cad + '"' }
                else { $m.Value }
            })
            # Verweis auf das Bauteil.
            $x = $x -replace ('<val>' + [regex]::Escape($w.Id.ToString()) + '</val>'), ('<val>' + $neu.Elem + '</val>')
            # z verschieben, nicht setzen.
            $x = [regex]::Replace($x, '<p>([-\d.eE+]+);([-\d.eE+]+);([-\d.eE+]+)</p>', {
                param($m)
                $z = [double]::Parse($m.Groups[3].Value, [Globalization.CultureInfo]::InvariantCulture) + $script:dz
                '<p>' + $m.Groups[1].Value + ';' + $m.Groups[2].Value + ';' + $z.ToString('R', [Globalization.CultureInfo]::InvariantCulture) + '</p>'
            })

            # Naechste freie Nummer des Praefixes, auch im XML nachziehen.
            $mn = [regex]::Match($w.Name, '^([A-Za-z]+)\s*(\d+)$')
            if ($mn.Success) {
                $pre = $mn.Groups[1].Value.ToUpper()
                $maxNr[$pre] = $maxNr[$pre] + 1
                $neuName = "{0} {1:000}" -f $mn.Groups[1].Value, $maxNr[$pre]
            } else { $neuName = $w.Name }
            $x = $x -replace '(<wall\s+name=")[^"]*(")', ('${1}' + $neuName + '${2}')

            $jetzt = Get-Date
            $gem = @{ UUID = $neu.Elem; GId = $neu.Elem; LongDesc = $neuName; ShortDesc = $neuName
                      StampCreate = $jetzt; StampEdit = $jetzt }
            $elem = $gem.Clone(); $elem['AddInsOutSideUUID'] = [guid]::NewGuid()
            Kopiere $con $tx 'BmElement'                 @{ UUID = $w.Id } $elem
            Kopiere $con $tx 'BmElementWall'             @{ UUID = $w.Id } $gem
            Kopiere $con $tx 'BmElementDimensioning'     @{ UUID = $w.Id } $gem
            Kopiere $con $tx 'BmElementEnergyConsulting' @{ UUID = $w.Id } $gem
            Kopiere $con $tx 'BmData' @{ ReferenceUUID = $w.Id; LongDesc = 'CADXMLData' } @{
                ReferenceUUID = $neu.Elem; ClassValue = $x; StampCreate = $jetzt; StampEdit = $jetzt
            }
            $zNeu = [regex]::Match($x, '<p>[-\d.eE+]+;[-\d.eE+]+;([-\d.eE+]+)</p>').Groups[1].Value
            Write-Host ("  {0,-8} -> {1,-8}  Bauteil {2}   z = {3}" -f $w.Name, $neuName, $neu.Elem, $zNeu)
        }
        if ($Probelauf) { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
        else { $tx.Commit(); Write-Host "`n$($quelle.Count) Waende nach '$($gNach.Name)' kopiert, $($quelle.Count * 5) Zeilen." -ForegroundColor Green }
    } catch { if ($tx) { $tx.Rollback() }; throw }
}
finally { $con.Close() }
