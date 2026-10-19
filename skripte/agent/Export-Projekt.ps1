<#
    Export-Projekt.ps1 - erzeugt den vollstaendigen Satz Ausgaben zu einem
    HSETU-Projekt: IFC, Huellflaechen-IFC und je Geschoss einen Grundriss.

    Die Geschosse werden aus den Daten abgeleitet, nicht vorgegeben: die
    Raumnamen tragen das Geschoss als Praefix (Keller-R1, EG-R3, OG1-R7, RF-R1),
    die Hoehen stehen in BmElementStorey. Geschnitten wird 1,00 m ueber der
    Geschossoberkante - dort, wo ein Grundriss ueblicherweise liegt.

    Am Ende steht eine manifest.json mit allen erzeugten Dateien. Der Agent
    laedt genau diese Liste zum Server hoch.

    Aufruf:
      .\Export-Projekt.ps1 -ProjectGuid <GUID> -Ziel C:\Ausgabe
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $ProjectGuid,
    [string] $Ziel = '.',
    [ValidateSet('Rot','Schwarz','Blau','Gelb')]
    [string] $StempelFarbe = 'Rot',
    [double] $Schriftgroesse = 0.14,
    [switch] $OhneBilder,
    [switch] $OhneIfc,
    [switch] $OhneGrundrisse,
    <#
        Pfad auf eine IFC, die HottCADs eigener Exporter schon geschrieben hat.

        Die entsteht ausserhalb dieses Skripts - der Agent ruft dafuer ueber die
        Bruecke die Hottgenroth-API auf, weil dazu .NET Framework noetig ist.
        Hier wird sie nur einsortiert: umbenannt und ins Manifest aufgenommen,
        damit sie mit hochgeladen wird. Fehlt sie, passiert nichts.
    #>
    [string] $HottCadIfc = '',
    [string] $Server   = '(localdb)\HSETU',
    [string] $Database = 'HsetuPrjData'
)

$ErrorActionPreference = 'Stop'
$INV = [System.Globalization.CultureInfo]::InvariantCulture
$hier = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $Ziel)) { $null = New-Item -ItemType Directory -Path $Ziel }
$Ziel = (Resolve-Path $Ziel).Path

# ---------------------------------------------------------- Projekt und Ebenen

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
$conn.Open()

function Abfrage([string] $sql) {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $null = $cmd.Parameters.AddWithValue('@p', [guid] $ProjectGuid)
    $t = New-Object System.Data.DataTable
    $a = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $null = $a.Fill($t)
    return ,$t
}

$kopf = Abfrage 'SELECT ShortDesc, LongDesc FROM PrProject WHERE UUID=@p'
if ($kopf.Rows.Count -eq 0) { throw "Projekt $ProjectGuid nicht gefunden." }
$projektName = [string] $kopf.Rows[0]['LongDesc']
if ($projektName -eq '') { $projektName = [string] $kopf.Rows[0]['ShortDesc'] }

$raumTab = Abfrage 'SELECT ShortDesc, Height FROM BmRoom WHERE ProjectUUID=@p'
$hoehenTab = Abfrage @'
SELECT DISTINCT ElevationOfRefHeight AS H FROM BmElementStorey
WHERE ProjectUUID=@p AND ElevationOfRefHeight > -1e8 ORDER BY ElevationOfRefHeight
'@
$conn.Close()

function Rang([string] $name) {
    switch -regex ($name) {
        '^(KG|Keller)' { return -1 }
        '^EG'          { return 0 }
        '^OG(\d+)'     { return [int] $matches[1] }
        '^(DG|RF|SB)'  { return 90 }
        default        { return 0 }
    }
}

$ebenen = @{}
foreach ($z in $raumTab.Rows) {
    $k = ([string] $z['ShortDesc'] -split '-')[0]
    if ($k -eq '') { continue }
    if (-not $ebenen.ContainsKey($k)) {
        $ebenen[$k] = [pscustomobject]@{ Name = $k; Rang = (Rang $k); Hoehe = $null; Raumhoehe = 2.6 }
    }
    $h = [double] $z['Height']
    if ($h -gt 0 -and $h -le 1e8) { $ebenen[$k].Raumhoehe = $h }
}

$liste = @($ebenen.Values | Sort-Object Rang)
$echte = @($hoehenTab.Rows | ForEach-Object { [double] $_['H'] } | Sort-Object)

# Gemessene Hoehen von oben nach unten zuordnen, den Rest fortschreiben.
$n = [math]::Min($liste.Count, $echte.Count)
for ($i = 0; $i -lt $n; $i++) { $liste[$liste.Count - 1 - $i].Hoehe = $echte[$echte.Count - 1 - $i] }
for ($i = $liste.Count - $n - 1; $i -ge 0; $i--) {
    $liste[$i].Hoehe = [math]::Round($liste[$i+1].Hoehe - $liste[$i].Raumhoehe - 0.25, 2)
}
foreach ($e in $liste) { if ($null -eq $e.Hoehe) { $e.Hoehe = 0.0 } }

Write-Host ("Projekt: {0}" -f $projektName)
Write-Host ("Ebenen:  {0}" -f (($liste | ForEach-Object { "$($_.Name) @ $($_.Hoehe) m" }) -join ', '))
Write-Host ''

# ------------------------------------------------------------------- Ausgaben

$erzeugt = New-Object System.Collections.ArrayList
function Merke([string] $pfad, [string] $art, [string] $ebene) {
    if (-not (Test-Path $pfad)) { return }
    $i = Get-Item $pfad
    $null = $erzeugt.Add([pscustomobject]@{ datei = $i.Name; art = $art; ebene = $ebene; bytes = $i.Length })
    Write-Host ("   {0,-34} {1,8:N0} KB" -f $i.Name, ($i.Length / 1KB))
}

$rumpf = ($projektName -replace '[^A-Za-z0-9]+', '-').Trim('-')
if ($rumpf.Length -gt 40) { $rumpf = $rumpf.Substring(0, 40) }
if ($rumpf -eq '') { $rumpf = 'Projekt' }

# HottCADs eigener Export, sofern der Agent ihn erzeugt hat. Er kommt aus dem
# CAD-Modell und muss deshalb weder Ecken noch Anschluesse rekonstruieren.
if ($HottCadIfc -ne '' -and (Test-Path $HottCadIfc)) {
    Write-Host 'IFC (HottCAD):'
    # Nicht $ziel nennen: PowerShell unterscheidet keine Gross-/Kleinschreibung,
    # das ueberschriebe den Zielordner $Ziel.
    $hottcadZiel = Join-Path $Ziel "$rumpf-HottCAD.ifc"
    Move-Item -LiteralPath $HottCadIfc -Destination $hottcadZiel -Force
    Merke $hottcadZiel 'ifc-hottcad' ''
    Write-Host ''
}

if (-not $OhneIfc) {
    Write-Host 'IFC:'
    & powershell -ExecutionPolicy Bypass -NoProfile -File (Join-Path $hier 'Export-Ifc.ps1') `
        -ProjectGuid $ProjectGuid -Server $Server -Database $Database `
        -Out (Join-Path $Ziel "$rumpf.ifc") | Out-Null
    Merke (Join-Path $Ziel "$rumpf.ifc") 'ifc' ''

    & powershell -ExecutionPolicy Bypass -NoProfile -File (Join-Path $hier 'Export-Ifc.ps1') `
        -ProjectGuid $ProjectGuid -Server $Server -Database $Database -NurHuelle `
        -Out (Join-Path $Ziel "$rumpf-nur-Huelle.ifc") | Out-Null
    Merke (Join-Path $Ziel "$rumpf-nur-Huelle.ifc") 'ifc-huelle' ''
    Write-Host ''
}

if (-not $OhneGrundrisse) {
    Write-Host 'Grundrisse:'
    foreach ($e in $liste) {
        $schnitt = [math]::Round($e.Hoehe + 1.00, 2)
        $dxf = Join-Path $Ziel ("$rumpf-Grundriss-$($e.Name).dxf")
        $png = if ($OhneBilder) { '' } else { Join-Path $Ziel ("$rumpf-Grundriss-$($e.Name).png") }

        # -Bild nur mitgeben, wenn ein Bild gewollt ist: ein leerer Wert ist
        # fuer PowerShell kein Argument, sondern ein fehlendes Argument, und
        # der Aufruf bricht ab, bevor auch nur die DXF entsteht.
        $bildArg = if ($png -ne '') { @('-Bild', $png) } else { @() }

        & powershell -ExecutionPolicy Bypass -NoProfile -File (Join-Path $hier 'Export-Grundriss.ps1') `
            -ProjectGuid $ProjectGuid -Server $Server -Database $Database `
            -Name $e.Name -Schnitthoehe $schnitt -Ebenenhoehe $e.Hoehe -Schraffur `
            -StempelFarbe $StempelFarbe -Schriftgroesse $Schriftgroesse `
            -Out $dxf @bildArg | Out-Null

        Merke $dxf 'grundriss' $e.Name
        if ($png -ne '') { Merke $png 'vorschau' $e.Name }
    }
    Write-Host ''
}

# ------------------------------------------------------------------- Manifest

$manifest = [pscustomobject]@{
    projekt_guid = $ProjectGuid
    projekt_name = $projektName
    erzeugt_am   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    ebenen       = @($liste | ForEach-Object { [pscustomobject]@{ name = $_.Name; hoehe = $_.Hoehe; schnitt = [math]::Round($_.Hoehe + 1.0, 2) } })
    dateien      = @($erzeugt)
}
$manifestPfad = Join-Path $Ziel 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPfad -Encoding UTF8

Write-Host ("{0} Dateien in {1}" -f $erzeugt.Count, $Ziel)
Write-Host ("Manifest: {0}" -f $manifestPfad)
