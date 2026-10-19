# Set-Nebengebaeude.ps1 -- ein Nebengebaeude an eine Wand haengen
#
# WARUM DAS ANDERS IST ALS ALLES ANDERE HIER
# Ein Nebengebaeude ist KEIN Bauteil. Es entsteht keine Zeile in BmElement, es
# bekommt keine Angrenzung und keine Huellflaeche. Es lebt als <attachment> im
# BmMedia-Blob -- einer eigenen building3d-XML neben der Bauteilzeichnung.
# Gemessen an Test0001 (23.08.2026): das Anlegen aenderte zwar 23 BmElement-
# Zeilen, aber ausschliesslich AddInsOutSideUUID und Rundungen um 1e-14.
#
#   <attachments count="1">
#     <attachment name="NG 001" GUID="..." drawn_in_wallview="True"
#                 wall_ref="<CAD-GUID der Wand>" wall_side_index="2"
#                 type="Heated" parent_wall="<dieselbe GUID>">
#       <points count="7"> ... </points>
#
# `type` ist der Knopf aus der Oberflaeche: Heated / Unheated.
# `wall_ref` und `parent_wall` zeigen auf die CAD-GUID aus der ZEICHNUNG --
# nicht auf BmElement.UUID. Beide tragen denselben Wert.
#
# DER BLOCK SITZT ZWISCHEN </contour_inner> UND <surrounding>
# `<surrounding>` ist das Gelaende und hat mit dem Nebengebaeude nichts zu tun;
# dort steht es NICHT drin. Genau da habe ich zuerst gesucht -- vergeblich.
#
# GESCHRIEBEN WIRD AUF BYTE-EBENE
# Der Blob ist UTF-8 ohne BOM mit CRLF und enthaelt Umlaute. Wer ihn dekodiert
# und neu kodiert, riskiert stille Aenderungen an Stellen, die niemand angefasst
# hat. Deshalb Latin1-Rundlauf: jedes Byte 0..255 bleibt, was es war.
#
# WAS ICH NICHT RECHNE
# Den Umriss. HottCAD leitet ihn selbst aus der Gebaeudesilhouette ab -- bei
# Test0001 sieben Punkte, mit Geschossversatz und First. Hier muss er angegeben
# werden; die Ableitung aus Geschossen und Dach ist nicht gebaut.
#
# ERPROBUNGSSTAND: an EINEM Projekt geschrieben. Die Wirkungsprobe geht nur
# ueber die Oberflaeche -- im IFC taucht ein Nebengebaeude nicht auf.

[CmdletBinding()]
param(
    # Namensteil (LongDesc) oder PrProject-UUID. Die UUID braucht, wessen
    # Projektname woertlich in einem anderen steckt ("3QHTK_Lennart Krause"
    # in "..._260929 Kopie") -- dann gibt es keinen eindeutigen Namensteil.
    [Parameter(Mandatory = $true)][string]$Projekt,
    # CAD-GUID der Wand aus der Zeichnung (Attribut GUID am <wall>), nicht BmElement.UUID.
    [string]$Wand = '',
    [ValidateSet('beheizt', 'unbeheizt')][string]$Art = 'beheizt',
    # Umriss auf der Wandebene, "x,y,z;x,y,z;...". Leer = aus dem Gebaeude
    # ableiten (Get-Wandsilhouette.ps1) -- das ist der Regelfall.
    [string]$Umriss = '',
    # Silhouette erst ab diesem Geschoss. Leer = ab Kellersohle.
    [string]$AbGeschoss = '',
    [string]$Name = '',
    [int]$Seite = 2,
    [switch]$Zeigen,
    [switch]$Entfernen,
    [switch]$Probelauf,
    [switch]$OhneSoftwarepruefung,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$NZ = [char]13 + [char]10
$L1 = [System.Text.Encoding]::GetEncoding(28591)   # Latin1: verlustfreier Byte-Rundlauf

if (-not $Zeigen -and -not $Probelauf -and -not $OhneSoftwarepruefung) {
    $pruef = Join-Path $PSScriptRoot "Test-SoftwareLaeuft.ps1"
    if (Test-Path $pruef) { . $pruef; Assert-SoftwareZu }
    else { Write-Warning "Test-SoftwareLaeuft.ps1 nicht gefunden -- Softwarepruefung uebersprungen." }
}

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
try {
    $c = $con.CreateCommand()
    # GUID zuerst, dann Namensteil -- Muster wie Setup-Wohngebaeude.ps1.
    $pg = [guid]::Empty
    if ([guid]::TryParse($Projekt, [ref]$pg)) {
        $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE UUID = @p"
        [void]$c.Parameters.AddWithValue("@p", $pg)
    }
    else {
        $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE @p"
        [void]$c.Parameters.AddWithValue("@p", "%$Projekt%")
    }
    $tp = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $tp += [pscustomobject]@{ Id = $l.GetGuid(0); Name = $l.GetString(1) } }
    $l.Close()
    if ($tp.Count -ne 1) { throw "Projekt nicht eindeutig ($($tp.Count) Treffer): $(($tp.Name) -join ' | ')" }
    $prj = $tp[0]

    $c = $con.CreateCommand()
    $c.CommandText = "SELECT UUID, Media FROM BmMedia WHERE ProjectUUID=@p AND Media IS NOT NULL"
    [void]$c.Parameters.AddWithValue("@p", $prj.Id)
    $rows = @(); $l = $c.ExecuteReader()
    while ($l.Read()) { $rows += [pscustomobject]@{ Id = $l.GetGuid(0); Bytes = [byte[]]$l["Media"] } }
    $l.Close()
    # Ein Projekt kann mehrere Medien fuehren. Gauting etwa haelt neben der
    # Zeichnung ein 3-MB-PNG des eingescannten Kellerplans. Gesucht ist die
    # building3d-XML -- und die erkennt man am Inhalt, nicht an einer Nummer:
    # BuildingMediaType war in den zwei gemessenen Faellen 3 gegen 4, aber das
    # sind zwei Faelle, kein Beleg.
    $zeichnung = @($rows | Where-Object {
        $_.Bytes.Length -gt 64 -and
        ($L1.GetString($_.Bytes, 0, [Math]::Min(400, $_.Bytes.Length)) -match 'application="building3d"')
    })
    if ($zeichnung.Count -ne 1) {
        throw ("Erwartet genau eine building3d-Zeichnung in BmMedia, gefunden: $($zeichnung.Count) " +
               "(von $($rows.Count) Medienzeilen). Ohne Zeichnung gibt es keine Wand, an der ein " +
               "Nebengebaeude haengen koennte.")
    }
    $blob = $zeichnung[0]
    $xml = $L1.GetString($blob.Bytes)

    Write-Host "Projekt : $($prj.Name)"
    Write-Host "Blob    : $($blob.Bytes.Length) Bytes"

    # --- was schon drinsteht ------------------------------------------------
    $vorhanden = @()
    foreach ($m in [regex]::Matches($xml, '<attachment name="([^"]*)"[^>]*type="([^"]*)"')) {
        $vorhanden += [pscustomobject]@{ Name = $m.Groups[1].Value; Typ = $m.Groups[2].Value }
    }
    $liste = if ($vorhanden.Count) { ($vorhanden | ForEach-Object { $_.Name + " [" + $_.Typ + "]" }) -join ', ' } else { 'keines' }
    Write-Host "Vorhanden: $liste"

    if ($Zeigen) { return }

    $a = $xml.IndexOf('<attachments')
    $e = $xml.IndexOf('</attachments>')
    if ($e -ge 0) { $e += '</attachments>'.Length }

    if ($Entfernen) {
        if ($a -lt 0) { Write-Host "Nichts zu entfernen." -ForegroundColor Yellow; return }
        $schwanz = if ($xml.Substring($e, 6) -eq ($NZ + '    ')) { 6 } else { 0 }
        $neu = $xml.Substring(0, $a) + $xml.Substring($e + $schwanz)
        Write-Host "Entfernen: $($e + $schwanz - $a) Zeichen"
    }
    else {
        if (-not $Wand) { throw "-Wand fehlt (CAD-GUID der Wand aus der Zeichnung)." }
        if (-not $Umriss) {
            # Der Regelfall: die Silhouette des eigenen Hauses auf der Wandebene.
            # Von Hand gerechnet war sie der Grund, warum dieses Skript allein
            # noch kein Werkzeug war.
            $sil = Join-Path $PSScriptRoot "Get-Wandsilhouette.ps1"
            if (-not (Test-Path $sil)) { throw "-Umriss fehlt und Get-Wandsilhouette.ps1 ist nicht da." }
            $Umriss = & $sil -Projekt $Projekt -Wand $Wand -AbGeschoss $AbGeschoss -Instanz $Instanz -Datenbank $Datenbank
            Write-Host "Umriss  : abgeleitet$(if ($AbGeschoss) { " ab $AbGeschoss" })"
        }
        $punkte = @($Umriss -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($punkte.Count -lt 3) { throw "Umriss braucht mindestens 3 Punkte, hat $($punkte.Count)." }
        foreach ($p in $punkte) {
            if (($p -split ',').Count -ne 3) { throw "Punkt '$p' hat nicht drei Werte." }
        }
        if (-not $Name) {
            $hoechste = 0
            foreach ($v in $vorhanden) {
                $t = [regex]::Match($v.Name, '^NG\s+(\d+)$')
                if ($t.Success -and [int]$t.Groups[1].Value -gt $hoechste) { $hoechste = [int]$t.Groups[1].Value }
            }
            $Name = "NG {0:000}" -f ($hoechste + 1)
        }
        $typ = if ($Art -eq 'beheizt') { 'Heated' } else { 'Unheated' }
        $cad = [guid]::NewGuid().ToString()
        $pz = ($punkte | ForEach-Object {
                '          <p>' + (($_ -split ',' | ForEach-Object { $_.Trim() }) -join ';') + '</p>'
            }) -join $NZ

        $kopf = '      <attachment name="' + $Name + '" GUID="' + $cad + '" drawn_in_wallview="True" wall_ref="' +
                $Wand + '" wall_side_index="' + $Seite + '" type="' + $typ + '" parent_wall="' + $Wand + '">'
        $block = '<attachments count="1">' + $NZ + $kopf + $NZ +
                 '        <points count="' + $punkte.Count + '">' + $NZ +
                 $pz + $NZ +
                 '        </points>' + $NZ +
                 '      </attachment>' + $NZ +
                 '    </attachments>'

        if ($a -ge 0) {
            $neu = $xml.Substring(0, $a) + $block + $xml.Substring($e)
            Write-Host "Ersetzen: der vorhandene Block wird ueberschrieben."
        }
        else {
            $ziel = $xml.IndexOf('<surrounding')
            if ($ziel -lt 0) { $ziel = $xml.IndexOf('</topitem>') }
            if ($ziel -lt 0) { throw "Kein Einfuegepunkt gefunden (weder <surrounding noch </topitem>)." }
            $neu = $xml.Substring(0, $ziel) + $block + $NZ + '    ' + $xml.Substring($ziel)
            Write-Host "Einfuegen vor: $($xml.Substring($ziel, 14))"
        }
        Write-Host ""
        Write-Host "  Name  : $Name"
        Write-Host "  Art   : $Art  (type=$typ)"
        Write-Host "  Wand  : $Wand   Seite $Seite"
        Write-Host "  Umriss: $($punkte.Count) Punkte"
        foreach ($p in $punkte) { Write-Host "      $p" }
    }

    $neuBytes = $L1.GetBytes($neu)
    Write-Host ""
    Write-Host "Blob neu: $($neuBytes.Length) Bytes (vorher $($blob.Bytes.Length))"

    if ($Probelauf) { Write-Host "" ; Write-Host "[Probelauf] Nichts geschrieben." -ForegroundColor Yellow; return }

    $u = $con.CreateCommand()
    $u.CommandText = "UPDATE BmMedia SET Media=@v, StampEdit=@s WHERE UUID=@u"
    $pv = $u.Parameters.Add("@v", [System.Data.SqlDbType]::VarBinary, -1); $pv.Value = $neuBytes
    [void]$u.Parameters.AddWithValue("@s", (Get-Date))
    [void]$u.Parameters.AddWithValue("@u", $blob.Id)
    $n = $u.ExecuteNonQuery()
    Write-Host "$n Zeile geschrieben." -ForegroundColor Green
}
finally { $con.Close() }
