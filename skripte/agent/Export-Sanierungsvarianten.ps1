<#
.SYNOPSIS
    Liest die Sanierungsvarianten eines Projekts aus der LocalDB und schreibt sie als JSON.

.BESCHREIBUNG
    Die Varianten des Energieberaters stehen NICHT in SQL-Tabellen, sondern in einem
    Anhang am Projekt: PrMedia.Media traegt eine 'eberater.zip' mit neun Tabellen im
    Format .BDExit. Dieses Skript holt den Anhang, entpackt ihn im Speicher, liest die
    Tabellen feldweise und gibt zurueck, was eine Auswertung braucht:

      Varianten          Name je Variante (TableProjekt.VarianteBez)
      Bauteile           je Variante die Huellflaechen mit U-Wert, Flaeche und - wo
                         vorhanden - der Sanierungsmassnahme samt Kosten
      Ergebnisse         die Energiebilanz je Variante (TableResult.EBilanz)
      Heizung/Wasser     Verluste, Erzeuger und Aufwandszahlen je Strang
      Anlage             Anlagenmassnahmen mit Investition und energiebedingtem Anteil

    NUR LESEND. Es wird kein Byte in die Datenbank geschrieben, und der Container
    wird nicht veraendert - er wird nur gelesen.

    Das Format ist gemessen, nicht dokumentiert. Die Beschreibung steht in
    hsetu-decompiled/SANIERUNGSVARIANTEN.md, Abschnitt 8; hier ist nur der Leseweg.

.HINWEIS
    Laeuft der Energieberater gerade, ist der Anhang so aktuell wie der letzte
    Speichervorgang. Das Skript sagt mit 'gespeichert_am', wann das war.

.BEISPIEL
    .\Export-Sanierungsvarianten.ps1 -ProjectGuid 46a5a001-... -Ziel C:\Temp\arbeit
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ProjectGuid,
    [Parameter(Mandatory)] [string] $Ziel,
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true',
    [string] $Dateiname = 'varianten.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---------------------------------------------------------------- Format lesen

# Kopf   00 Magic | 08 uint32 Beginn Feldtabelle | 12 uint16 Feldzahl
#        14 uint16 Satzzahl | 24 Feldtabelle
# Feld   byte Laenge | Name | uint16 Typ | uint16 Code | uint16 ? | uint16 Unter
# Satz   Anwesenheitskarte (2 Bit je Feld, aufgerundet + 1 Byte), dann die Werte.
#        Bitwert 1 = Feld FEHLT im Satz.
function Lies-Kopf([byte[]] $b) {
    $p = [BitConverter]::ToUInt32($b, 8)
    $felder = New-Object System.Collections.ArrayList

    while ($p -lt $b.Length - 8) {
        $len = $b[$p]
        if ($len -lt 1 -or $len -gt 40) { break }
        $name = -join ($b[($p + 1)..($p + $len)] | ForEach-Object { [char]$_ })
        # Feldnamen koennen EIN Zeichen lang sein (TableZusatz: A, B, B1) - eine
        # Mindestlaenge von 2 bricht den Leser dort ab.
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { break }
        $q = $p + 1 + $len
        $code = [BitConverter]::ToUInt16($b, $q + 2)

        if ($name -eq 'SUBTYPE' -or $name -eq 'WIDTH') {
            $q += 4
            if ($code -eq 0x49) { $l = [BitConverter]::ToUInt16($b, $q); $q += 2 + $l }
            else { $q += 2 }
        } else {
            $typ = [BitConverter]::ToUInt16($b, $q)
            $q += 8
            [void] $felder.Add([pscustomobject]@{ Name = $name; Typ = $typ; Code = $code })
        }
        $p = $q
    }

    # Hinter der Feldtabelle stehen immer zwei Bytes, danach optional der Autowert.
    $q = $p + 2
    if ($b[$q] -eq 12) {
        $n = -join ($b[($q + 1)..($q + 12)] | ForEach-Object { [char]$_ })
        if ($n -eq 'AUTOINCVALUE') { $q = $q + 1 + 12 + 4 + 4 }
    }

    $fz = [BitConverter]::ToUInt16($b, 12)

    [pscustomobject]@{
        Felder   = $felder
        Satzzahl = [BitConverter]::ToUInt16($b, 14)
        Vorspann = [math]::Ceiling($fz * 2 / 8) + 1
        Daten    = $q
    }
}

function Lies-Satz([byte[]] $b, $k, [int] $satz) {
    $o = $satz + $k.Vorspann
    $werte = @{}

    for ($i = 0; $i -lt $k.Felder.Count; $i++) {
        $f = $k.Felder[$i]
        $fehlt = (($b[$satz + 1 + [math]::Floor($i / 4)] -shr (($i % 4) * 2)) -band 3) -ne 0
        if ($fehlt) { continue }

        # Eine einzige Regel deckt alle Typen ab: Code 73/75 ist Text, die Laenge
        # steht in "Typ" Bytes davor; sonst feste Breite "Typ" Bytes.
        $text = ($f.Code -eq 73 -or $f.Code -eq 75)
        if ($text) {
            $kopf = $f.Typ
            $nutz = switch ($f.Typ) {
                1 { [int] $b[$o] }
                2 { [int] [BitConverter]::ToUInt16($b, $o) }
                default { [int] [BitConverter]::ToUInt32($b, $o) }
            }
        } else {
            $kopf = 0
            $nutz = [int] $f.Typ
        }

        if ($o + $kopf + $nutz -gt $b.Length) { throw "Feld $($f.Name) laeuft ueber das Dateiende." }

        if ($text) {
            # CP1252, wie die Software selbst. Der Kernel-Blob wird nicht gedeutet -
            # er ist ein BinaryFormatter-Graph und hier ohnehin nicht gefragt.
            if ($f.Name -notmatch 'Kernel18599V5|PrMedia|Blob') {
                $werte[$f.Name] = if ($nutz) { [Text.Encoding]::GetEncoding(1252).GetString($b, $o + $kopf, $nutz) } else { '' }
            }
        } else {
            $werte[$f.Name] = switch ("$($f.Typ)/$($f.Code)") {
                '4/1' { [BitConverter]::ToInt32($b, $o) }
                '2/1' { [BitConverter]::ToInt16($b, $o) }
                '8/4' { [BitConverter]::ToDouble($b, $o) }
                '2/3' { [BitConverter]::ToUInt16($b, $o) }
                default { $null }   # Datum und Ungedeutetes bleiben leer
            }
        }

        $o += $kopf + $nutz
    }

    [pscustomobject]@{ Werte = $werte; Ende = $o }
}

function Lies-Tabelle([byte[]] $b) {
    $k = Lies-Kopf $b
    $saetze = New-Object System.Collections.ArrayList
    $o = $k.Daten

    while ($o -lt $b.Length) {
        $r = Lies-Satz $b $k $o
        [void] $saetze.Add($r.Werte)
        $o = $r.Ende
    }

    if ($saetze.Count -ne $k.Satzzahl) {
        throw "Satzzahl stimmt nicht: $($saetze.Count) gelesen, der Kopf nennt $($k.Satzzahl)."
    }

    , $saetze
}

# Schluessel=Wert je Zeile - so liegen EBilanz und LookupData im Container.
function Lies-Paare([string] $text) {
    $h = [ordered]@{}
    foreach ($zeile in ($text -split "`r?`n")) {
        if ($zeile -match '^([^=]+)=(.*)$') {
            $name = $Matches[1].Trim()
            $wert = $Matches[2].Trim()
            $zahl = 0.0
            if ([double]::TryParse(($wert -replace '\.', '' -replace ',', '.'), [Globalization.NumberStyles]::Float,
                    [Globalization.CultureInfo]::InvariantCulture, [ref] $zahl)) {
                $h[$name] = [math]::Round($zahl, 4)
            } elseif ($wert -ne '') {
                $h[$name] = $wert
            }
        }
    }
    $h
}

function Zahl($wert, [int] $stellen = 2) {
    if ($null -eq $wert) { return $null }
    [math]::Round([double] $wert, $stellen)
}

# ------------------------------------------------------------------- Container

$con = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$con.Open()

try {
    $c = $con.CreateCommand()
    $c.CommandText = @'
SELECT TOP 1 m.Media, CONVERT(varchar(19), p.StampEdit, 120), p.LongDesc
  FROM PrMedia m
  JOIN PrProject p ON p.UUID = m.ProjectUUID
 WHERE m.ProjectUUID = @u AND m.MediaName = 'eberater.zip'
'@
    $null = $c.Parameters.AddWithValue('@u', [guid] $ProjectGuid)

    $r = $c.ExecuteReader()
    if (-not $r.Read()) { $r.Close(); throw "Das Projekt $ProjectGuid hat keinen Anhang 'eberater.zip' - es fuehrt keine Sanierungsvarianten." }

    $roh = [byte[]] $r[0]
    $gespeichert = [string] $r[1]
    $projektname = [string] $r[2]
    $r.Close()
} finally {
    $con.Close()
}

$tabellen = @{}
$strom = New-Object System.IO.MemoryStream(, $roh)
$zip = New-Object System.IO.Compression.ZipArchive($strom, [System.IO.Compression.ZipArchiveMode]::Read)

try {
    foreach ($eintrag in $zip.Entries) {
        if ($eintrag.Name -notlike '*.BDExit') { continue }
        $ms = New-Object System.IO.MemoryStream
        $s = $eintrag.Open(); $s.CopyTo($ms); $s.Close()
        $tabellen[[IO.Path]::GetFileNameWithoutExtension($eintrag.Name)] = Lies-Tabelle $ms.ToArray()
        $ms.Dispose()
    }
} finally {
    $zip.Dispose(); $strom.Dispose()
}

foreach ($noetig in 'TableProjekt', 'TableHuellfl', 'TableResult') {
    if (-not $tabellen.ContainsKey($noetig)) { throw "Im Container fehlt $noetig - das ist kein Energieberater-Anhang." }
}

# --------------------------------------------------------------- zusammenbauen

# Die erste Variante ist der Ist-Zustand; sie traegt keine Bezeichnung.
$varianten = New-Object System.Collections.ArrayList
$reihe = 0

foreach ($p in $tabellen['TableProjekt']) {
    $id = [int] $p['PROJEKT_ID']
    $bez = [string] $p['VarianteBez']
    $reihe++

    $ergebnis = @($tabellen['TableResult'] | Where-Object { [int] $_['Result_ID'] -eq $id })
    $heizung = @($tabellen['TableHeizung'] | Where-Object { [int] $_['ProjektID'] -eq $id })
    $wasser = @($tabellen['TableWasser'] | Where-Object { [int] $_['ProjektID'] -eq $id })
    $anlage = @($tabellen['TableAnlage'] | Where-Object { [int] $_['ANLAGE_ID'] -eq $id })

    # Bauteile: alles, was die Variante fuehrt, mit Massnahme wo vorhanden.
    $bauteile = New-Object System.Collections.ArrayList
    foreach ($h in ($tabellen['TableHuellfl'] | Where-Object { [int] $_['PROJ_ID'] -eq $id })) {
        $gesamt = [double] $h['SANKOSTEN']
        $ee = [double] $h['SANKOSTEN_EE']
        $brutto = [double] $h['FLAECHE_BR']
        if ($brutto -le 0) { $brutto = [double] $h['FLAECHE'] }

        [void] $bauteile.Add([ordered]@{
            bauteil      = [string] $h['BAUTEILBEZ']
            kennzeichen  = [string] $h['KENNZEICHEN']
            ausrichtung  = [string] $h['AUSRICHTUNG']
            flaeche_brutto = Zahl $brutto
            flaeche_netto  = Zahl $h['FLAECHE']
            u_ist        = Zahl $h['K_ZAHL'] 3
            massnahme    = [string] $h['SANBEZ']
            u_ziel       = Zahl $h['SANK_ZAHL'] 3
            daemmung_cm  = Zahl $h['SANDICKE'] 1
            lambda       = Zahl $h['SANLAMBDA'] 3
            kosten_gesamt = Zahl $gesamt
            # Die Sowieso-Kosten stehen nirgends gespeichert - sie sind die
            # Differenz, und genau sie entscheidet ueber die Foerderung.
            kosten_sowieso = if ($gesamt) { Zahl ($gesamt - $ee) } else { $null }
            kosten_energiebedingt = if ($gesamt) { Zahl $ee } else { $null }
        })
    }

    $anlagenposten = New-Object System.Collections.ArrayList
    if ($anlage.Count -and $anlage[0]['InvestKostenText']) {
        foreach ($zeile in ([string] $anlage[0]['InvestKostenText'] -split "`r?`n")) {
            if ($zeile.Trim() -eq '') { continue }
            $teile = $zeile -split '\|'
            [void] $anlagenposten.Add([ordered]@{
                posten = $teile[0]
                kosten_gesamt = if ($teile.Count -gt 1) { Zahl $teile[1] } else { $null }
                kosten_energiebedingt = if ($teile.Count -gt 2) { Zahl $teile[2] } else { $null }
            })
        }
    }

    $bilanz = if ($ergebnis.Count -and $ergebnis[0]['EBilanz']) { Lies-Paare ([string] $ergebnis[0]['EBilanz']) } else { [ordered]@{} }
    $lookup = [ordered]@{}
    if ($tabellen.ContainsKey('TableZusatz')) {
        $z = @($tabellen['TableZusatz'] | Where-Object { [int] $_['PROJ_ID'] -eq $id })
        if ($z.Count -and $z[0]['LookupData']) { $lookup = Lies-Paare ([string] $z[0]['LookupData']) }
    }

    [void] $varianten.Add([ordered]@{
        id = $id
        nummer = $reihe - 1                       # 0 = Ist-Zustand, 1..n = Pakete
        name = if ($bez) { $bez } else { 'Ist-Zustand' }
        ist_zustand = ($reihe -eq 1)
        bilanz = $bilanz
        lookup = $lookup
        heizung = if ($heizung.Count) { [ordered]@{
            waermebedarf_kwh = Zahl $heizung[0]['Qh'] 0
            uebergabe_verlust_kwh = Zahl $heizung[0]['UbergabeQ'] 0
            verteilung_verlust_kwh = Zahl $heizung[0]['VerteilQ'] 0
            speicher_verlust_kwh = Zahl $heizung[0]['SpeicherQ'] 0
            hilfsenergie_kwh = Zahl $heizung[0]['QHilf'] 0
            endenergie_kwh = Zahl $heizung[0]['QE'] 0
            uebergabe = [string] $heizung[0]['UbergabeText1']
            verteilung = [string] $heizung[0]['VerteilText2']
            speicher = [string] $heizung[0]['SpeicherText2']
            erzeuger = [string] $heizung[0]['Erz1Text1']
            erzeuger_zusatz = [string] $heizung[0]['Erz1Text2']
            brennstoff = [string] $heizung[0]['Erz1Brennst']
            # Aufwandszahl, nicht Wirkungsgrad: bei einer Waermepumpe ist 1/AZ
            # die Jahresarbeitszahl.
            aufwandszahl = Zahl $heizung[0]['Erz1AZ'] 3
        } } else { $null }
        warmwasser = if ($wasser.Count) { [ordered]@{
            verteilung_verlust_kwh = Zahl $wasser[0]['VerteilQ'] 0
            speicher_verlust_kwh = Zahl $wasser[0]['SpeicherQ'] 0
            endenergie_kwh = Zahl $wasser[0]['QE'] 0
            erzeuger = [string] $wasser[0]['Erz1Text2']
            aufwandszahl = Zahl $wasser[0]['Erz1AZ'] 3
        } } else { $null }
        anlage = if ($anlage.Count) { [ordered]@{
            heizung = ([string] $anlage[0]['Beschr_Heiz']).Trim()
            warmwasser = ([string] $anlage[0]['Beschr_Wass']).Trim()
            lueftung = ([string] $anlage[0]['Beschr_Luft']).Trim()
            invest_gesamt = Zahl $anlage[0]['InvestKosten']
            invest_energiebedingt = Zahl $anlage[0]['InvestKosten_EE']
            posten = $anlagenposten
        } } else { $null }
        bauteile = $bauteile
    })
}

$ergebnis = [ordered]@{
    projekt = [ordered]@{
        guid = $ProjectGuid
        name = $projektname
        gespeichert_am = $gespeichert
    }
    gelesen_am = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    anzahl_varianten = $varianten.Count
    varianten = $varianten
}

New-Item -ItemType Directory -Force -Path $Ziel | Out-Null
$datei = Join-Path $Ziel $Dateiname
# Depth 8: Variante -> bauteile -> Eintrag reicht nicht, die Bilanz haengt tiefer.
$ergebnis | ConvertTo-Json -Depth 8 -Compress | Set-Content -Path $datei -Encoding UTF8

"{0} Varianten, {1} Bauteilzeilen -> {2}" -f $varianten.Count,
    (($varianten | ForEach-Object { $_.bauteile.Count } | Measure-Object -Sum).Sum), $datei
