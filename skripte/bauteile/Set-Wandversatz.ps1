# Set-Wandversatz.ps1 -- eine gezeichnete Wand in der Ebene verschieben
#
# ZWECK
# Das ist zunaechst ein MESSWERKZEUG, kein Produktionswerkzeug. Es beantwortet
# eine einzige offene Frage: liest HottCAD die Geometrie aus BmData/CADXMLData
# beim Oeffnen zurueck, oder zeichnet es das Modell aus den parametrischen
# BmElement-Zeilen (RepositoryType 3) neu?
#
#   Wand verschoben und HottCAD zeigt sie versetzt  -> CADXMLData traegt.
#   Wand verschoben und HottCAD zeigt das Original  -> CADXMLData ist abgeleitet.
#
# Beides ist ein Ergebnis. Erst wenn die erste Antwort stimmt, lohnt der Versuch,
# eine ganze Wand von aussen anzulegen.
#
# WARUM AUSGERECHNET EINE PARALLELVERSCHIEBUNG
# Weil dabei nichts anderes nachgezogen werden muss. Laenge, Flaeche, Dicke und
# Hoehe der Wand bleiben gleich, also bleiben BmElement.Width und
# BmElementDimensioning stimmig. Jede andere Aenderung (drehen, verlaengern)
# wuerde die abgeleiteten Zeilen widerspruechlich machen und das Messergebnis
# vermischen: man wuesste hinterher nicht, ob HottCAD die Geometrie oder den
# Widerspruch repariert hat.
#
# WAS ES NICHT ANFASST
# Nur der erste <points>-Block INNERHALB von <wall ...> wird geaendert. Die
# <bottom_planes> bleiben stehen -- sie beschreiben die Auflage auf der
# Bodenplatte, und ob HottCAD den entstehenden Widerspruch bemerkt, ist selbst
# Teil der Messung. Unveraenderte Koordinaten werden zeichengleich uebernommen,
# nicht neu formatiert: so zeigt der Snapshot-Vergleich hinterher genau die
# Stellen, die ich angefasst habe, und keine Formatierungsunterschiede.
#
# ZURUECK
# -Rueckgaengig dreht das Vorzeichen um. Wer mit -dy -2 verschoben hat, kommt
# mit denselben Werten plus -Rueckgaengig wieder heraus. Das ersetzt keine
# Sicherung, aber es macht den haeufigen Fall billig.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Projekt,
    [Parameter(Mandatory = $true)][string]$Wand,
    [double]$dx = 0,
    [double]$dy = 0,
    [switch]$Rueckgaengig,
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

if ($dx -eq 0 -and $dy -eq 0) { throw "dx und dy sind beide 0 -- nichts zu tun." }
if ($Rueckgaengig) { $dx = -$dx; $dy = -$dy }

# Vorbedingung: keine Hottgenroth-Anwendung offen. Sie schreibt ihr Modell beim
# Beenden zurueck und verwirft jede Aenderung von aussen, ohne Meldung.
if (-not $OhneSoftwarepruefung) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

$inv = [Globalization.CultureInfo]::InvariantCulture
$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    $p = $con.CreateCommand()
    $p.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @n"
    [void]$p.Parameters.AddWithValue("@n", "%$Projekt%")
    $treffer = @(); $l = $p.ExecuteReader()
    while ($l.Read()) { $treffer += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($treffer.Count -ne 1) { throw "Projekt nicht eindeutig: $($treffer.Count) Treffer fuer '$Projekt'. $($treffer.Name -join ' | ')" }
    $prj = $treffer[0]

    $g = $con.CreateCommand()
    $g.CommandText = @"
SELECT d.ReferenceUUID, d.UUID, CAST(d.ClassValue AS nvarchar(max))
FROM BmData d JOIN BmElement e ON e.UUID = d.ReferenceUUID
WHERE d.ProjectUUID = @p AND d.LongDesc = 'CADXMLData' AND e.LongDesc = @w
"@
    [void]$g.Parameters.AddWithValue("@p", $prj.Id)
    [void]$g.Parameters.AddWithValue("@w", $Wand)
    $zeilen = @(); $l = $g.ExecuteReader()
    while ($l.Read()) { $zeilen += [pscustomobject]@{ Ref = $l.GetGuid(0); Dat = $l.GetGuid(1); Xml = $l.GetString(2) } }
    $l.Close()
    if ($zeilen.Count -ne 1) { throw "Wand '$Wand' nicht eindeutig: $($zeilen.Count) CADXMLData-Zeilen in '$($prj.Name)'." }
    $z = $zeilen[0]

    $start = $z.Xml.IndexOf('<wall ')
    if ($start -lt 0) { throw "Kein <wall>-Element in der CADXMLData von '$Wand' -- ist das ueberhaupt eine Wand?" }
    $m = [regex]::Match($z.Xml.Substring($start), '<points count="\d+">.*?</points>', 'Singleline')
    if (-not $m.Success) { throw "Kein <points>-Block innerhalb von <wall> gefunden." }

    # Nur die tatsaechlich verschobene Komponente wird neu geschrieben. Die
    # anderen bleiben als Originalzeichenkette stehen -- kein Rauschen im Diff.
    $alt = @(); $neu = @()
    $neuBlock = [regex]::Replace($m.Value, '<p>([-\d.eE+]+);([-\d.eE+]+);([-\d.eE+]+)</p>', {
        param($t)
        $sx = $t.Groups[1].Value; $sy = $t.Groups[2].Value; $sz = $t.Groups[3].Value
        $script:alt += "$sx;$sy;$sz"
        if ($dx -ne 0) { $sx = ([double]::Parse($sx, $inv) + $dx).ToString('R', $inv) }
        if ($dy -ne 0) { $sy = ([double]::Parse($sy, $inv) + $dy).ToString('R', $inv) }
        $script:neu += "$sx;$sy;$sz"
        "<p>$sx;$sy;$sz</p>"
    })
    if ($alt.Count -eq 0) { throw "Der <points>-Block enthielt keine lesbaren Punkte." }

    Write-Host "Projekt : $($prj.Name)"
    Write-Host "Wand    : $Wand   Versatz dx=$dx dy=$dy"
    Write-Host ""
    for ($i = 0; $i -lt $alt.Count; $i++) {
        Write-Host ("  p{0}  {1,-46} -> {2}" -f ($i + 1), $alt[$i], $neu[$i])
    }

    $neuXml = $z.Xml.Remove($start + $m.Index, $m.Length).Insert($start + $m.Index, $neuBlock)
    Write-Host ""
    Write-Host ("  XML {0} -> {1} Zeichen" -f $z.Xml.Length, $neuXml.Length)

    if ($Probelauf) { Write-Host "`n[Probelauf] Nichts geschrieben." -ForegroundColor Yellow; return }

    $tx = $con.BeginTransaction()
    try {
        $u = $con.CreateCommand(); $u.Transaction = $tx
        $u.CommandText = "UPDATE BmData SET ClassValue = @v, StampEdit = @s WHERE ReferenceUUID = @r AND UUID = @u"
        [void]$u.Parameters.AddWithValue("@v", $neuXml)
        [void]$u.Parameters.AddWithValue("@s", (Get-Date))
        [void]$u.Parameters.AddWithValue("@r", $z.Ref)
        [void]$u.Parameters.AddWithValue("@u", $z.Dat)
        $n = $u.ExecuteNonQuery()
        if ($n -ne 1) { throw "UPDATE traf $n Zeilen statt 1 -- zurueckgerollt." }
        $tx.Commit()
        Write-Host "`n1 Zeile geschrieben." -ForegroundColor Green
    } catch { $tx.Rollback(); throw }
}
finally { $con.Close() }
