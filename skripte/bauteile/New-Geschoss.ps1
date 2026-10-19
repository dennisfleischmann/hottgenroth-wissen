# New-Geschoss.ps1 -- ein Geschoss an ein bestehendes Gebaeude haengen
#
# BmFloor ALLEIN GENUEGT NICHT
# Das war der Fehlschlag beim ersten Versuch: die Geschosse standen in BmFloor,
# aber der Dialog "Geschosse anlegen und loeschen" zeigte weiter nur das EG.
# HottCAD liest die Geschossliste aus der ZEICHNUNG, nicht aus der Tabelle.
# Ein vollstaendiges Geschoss besteht aus vier Zeilen:
#
#   BmFloor                        die Kenngroessen
#   BmFloorData                    Rechenergebnisse, gleiche UUID
#   BmData 'CADXMLData'            <floor GUID=... elevation=... type=...>
#   BmData 'is_auto_generated'     der Wert 1
#
# Deshalb ist dieses Skript IDEMPOTENT: es legt an, was fehlt, und ergaenzt bei
# einem vorhandenen Geschoss die fehlenden Zeilen. Zweimal aufrufen schadet
# nicht.
#
# GEMESSEN AN 19 MEHRGESCHOSSERN
#
#   FloorType  1 = DG,  2 = OG,  3 = EG,  6 = Keller
#   type im XML   1 -> Roof,  2/3 -> Standard,  6 -> Cellar
#   SortNum    zaehlt von OBEN nach unten (DG = 1)
#   FloorCount in building_data = Anzahl der Geschosse UEBER dem EG,
#              also OG + DG. Keller und EG zaehlen NICHT mit. Die Regel geht
#              bei allen 19 Projekten mit mehr als einem Geschoss glatt auf.
#
# ElevationOfRefHeight ist zugleich das z der Wandpunkte dieses Geschosses --
# darauf baut Copy-Geschosswaende.ps1 auf.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Name,
    [ValidateSet('Keller', 'EG', 'OG', 'DG')][string]$Typ = 'OG',
    # Bezugsgeschoss, an dem sich die Hoehenlage bemisst. Entfaellt, wenn das
    # Geschoss schon existiert und nur ergaenzt wird.
    [string]$Bezug = '',
    [ValidateSet('darueber', 'darunter')][string]$Lage = 'darueber',
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$inv = [Globalization.CultureInfo]::InvariantCulture
$NZ  = [char]13 + [char]10
$FloorType = @{ 'DG' = 1; 'OG' = 2; 'EG' = 3; 'Keller' = 6 }
$XmlTyp    = @{ 1 = 'Roof'; 2 = 'Standard'; 3 = 'Standard'; 6 = 'Cellar' }
function Z([double]$w) { $w.ToString('R', $inv) }

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

    # Der Transaktionsparameter ist Pflicht, nicht Kosmetik: solange eine
    # Transaktion offen ist, weist ADO.NET jeden Befehl ohne sie zurueck.
    function LiesGeschosse($Tx) {
        $q = $con.CreateCommand()
        if ($Tx) { $q.Transaction = $Tx }
        $q.CommandText = "SELECT f.UUID, f.LongDesc, f.ElevationOfRefHeight, f.FloorHeight, f.CeilingThickness, f.FloorType, " +
                         "(SELECT COUNT(*) FROM BmData d WHERE d.ReferenceUUID=f.UUID AND d.LongDesc='CADXMLData') AS hatXml, " +
                         "(SELECT COUNT(*) FROM BmData d WHERE d.ReferenceUUID=f.UUID AND d.LongDesc='is_auto_generated') AS hatFlag " +
                         "FROM BmFloor f WHERE f.ProjectUUID=@p ORDER BY f.ElevationOfRefHeight DESC"
        [void]$q.Parameters.AddWithValue("@p", $prj.Id)
        $r = @(); $x = $q.ExecuteReader()
        while ($x.Read()) {
            $r += [pscustomobject]@{ Id = $x.GetGuid(0); Name = $x.GetString(1); Bezug = [double]$x.GetValue(2)
                                     Hoehe = [double]$x.GetValue(3); Decke = [double]$x.GetValue(4)
                                     Typ = [int]$x.GetValue(5); HatXml = [int]$x.GetValue(6) -gt 0; HatFlag = [int]$x.GetValue(7) -gt 0 }
        }
        $x.Close(); return , $r
    }
    $gs = LiesGeschosse $null

    # Vorlagengeschoss fuer die Zeilenkopien: eines, das alle vier Zeilen hat.
    $vl = @($gs | Where-Object { $_.HatXml -and $_.HatFlag }) | Select-Object -First 1
    if (-not $vl) { throw "Kein vollstaendiges Geschoss als Vorlage vorhanden." }

    $vorhanden = @($gs | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    $jetzt = Get-Date
    Write-Host "Projekt : $($prj.Name)"

    $tx = if ($Probelauf) { $null } else { $con.BeginTransaction() }
    try {
        if ($vorhanden) {
            Write-Host "Geschoss '$Name' ist vorhanden -- es werden nur fehlende Zeilen ergaenzt."
        } else {
            if (-not $Bezug) { throw "Geschoss '$Name' gibt es noch nicht -- dann wird -Bezug gebraucht." }
            $ref = @($gs | Where-Object { $_.Name -like "*$Bezug*" })
            if ($ref.Count -ne 1) { throw "Bezugsgeschoss nicht eindeutig: $($ref.Count) Treffer fuer '$Bezug'." }
            $ref = $ref[0]
            $neuBezug = if ($Lage -eq 'darueber') { $ref.Bezug + $ref.Hoehe } else { $ref.Bezug - $ref.Hoehe }
            $neuId = [guid]::NewGuid()
            Write-Host "Neu     : $Name (FloorType $($FloorType[$Typ])), $Lage von '$($ref.Name)', Hoehenlage $(Z $neuBezug) m"
            $gem = @{ UUID = $neuId; GId = $neuId; ShortDesc = $Name; LongDesc = $Name; StampCreate = $jetzt; StampEdit = $jetzt }
            $fl = $gem.Clone()
            $fl['FloorType'] = $FloorType[$Typ]
            $fl['ElevationOfRefHeight'] = $neuBezug
            Kopiere $con $tx 'BmFloor'     @{ UUID = $ref.Id } $fl
            Kopiere $con $tx 'BmFloorData' @{ UUID = $ref.Id } $gem
            if ($tx) { $gs = LiesGeschosse $tx }
        }

        # Fehlende Zeichendaten fuer ALLE Geschosse ergaenzen -- selbstheilend.
        foreach ($g in $gs) {
            if ($g.HatXml -and $g.HatFlag) { continue }
            $xml = @(
                '<?xml version="1.0"?>', '<geometry>', '  <Floor count="1">'
                ('    <floor GUID="' + $g.Id.ToString().ToLower() + '" name="' + $g.Name + '" username=""' +
                 ' elevation="' + (Z $g.Bezug) + '" type="' + $XmlTyp[$g.Typ] + '"' +
                 ' height="' + (Z $g.Hoehe) + '" ceiling="' + (Z $g.Decke) + '">')
                '      <templates count="1" />', '    </floor>', '  </Floor>', '</geometry>'
            ) -join $NZ
            if (-not $g.HatXml) {
                Write-Host ("  + Zeichendaten fuer '{0}' (type={1}, elevation={2})" -f $g.Name, $XmlTyp[$g.Typ], (Z $g.Bezug))
                Kopiere $con $tx 'BmData' @{ ReferenceUUID = $vl.Id; LongDesc = 'CADXMLData' } @{
                    ReferenceUUID = $g.Id; ClassValue = $xml; StampCreate = $jetzt; StampEdit = $jetzt }
            }
            if (-not $g.HatFlag) {
                Write-Host ("  + Kennzeichen is_auto_generated fuer '{0}'" -f $g.Name)
                Kopiere $con $tx 'BmData' @{ ReferenceUUID = $vl.Id; LongDesc = 'is_auto_generated' } @{
                    ReferenceUUID = $g.Id; StampCreate = $jetzt; StampEdit = $jetzt }
            }
        }

        if ($tx) {
            # SortNum neu vergeben: 1 ist das oberste Geschoss.
            $u = $con.CreateCommand(); $u.Transaction = $tx
            $u.CommandText = "WITH r AS (SELECT UUID, ROW_NUMBER() OVER (ORDER BY ElevationOfRefHeight DESC) AS n " +
                             "FROM BmFloor WHERE ProjectUUID=@p) UPDATE f SET SortNum=r.n FROM BmFloor f JOIN r ON r.UUID=f.UUID"
            [void]$u.Parameters.AddWithValue("@p", $prj.Id)
            [void]$u.ExecuteNonQuery()

            # FloorCount = Geschosse ueber dem EG (OG + DG).
            $u = $con.CreateCommand(); $u.Transaction = $tx
            $u.CommandText = "SELECT COUNT(*) FROM BmFloor WHERE ProjectUUID=@p AND FloorType IN (1,2)"
            [void]$u.Parameters.AddWithValue("@p", $prj.Id)
            $fc = [int]$u.ExecuteScalar()
            # Der bisherige Wert ist unbekannt, deshalb wird die Stelle zwischen
            # den Anfuehrungszeichen ausgeschnitten und ersetzt.
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
            Write-Host "  ~ FloorCount im Gebaeude auf $fc gesetzt (Geschosse ueber dem EG)"
            $tx.Commit()
            Write-Host "`nFertig." -ForegroundColor Green
        } else { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow }
    } catch { if ($tx) { $tx.Rollback() }; throw }

    $c = $con.CreateCommand()
    $c.CommandText = "SELECT f.SortNum, f.LongDesc, f.FloorType, f.ElevationOfRefHeight, " +
                     "(SELECT COUNT(*) FROM BmData d WHERE d.ReferenceUUID=f.UUID) AS n " +
                     "FROM BmFloor f WHERE f.ProjectUUID=@p ORDER BY f.SortNum"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $l = $c.ExecuteReader()
    Write-Host "`n  Nr  Geschoss    Typ   Hoehenlage  Zeichendaten"
    while ($l.Read()) {
        Write-Host ("  {0,2}  {1,-10}  {2,3}   {3,9}  {4}" -f $l.GetValue(0), $l.GetValue(1), $l.GetValue(2),
                    (Z ([double]$l.GetValue(3))), $(if ([int]$l.GetValue(4) -ge 2) { 'vollstaendig' } else { 'FEHLT' }))
    }
    $l.Close()
}
finally { $con.Close() }
