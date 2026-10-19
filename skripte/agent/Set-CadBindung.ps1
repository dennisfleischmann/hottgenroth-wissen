<#
.SYNOPSIS
    Loest die CAD-Bindung einer Sanierungsvariante oder stellt sie wieder her.

.BESCHREIBUNG
    Im Energieberater ist die Bauteiluebersicht einer Variante gesperrt, solange die
    Variante am HottCAD-Modell haengt. Die Software blendet dann das Panel
    'PanelCADHinweis' ein ("Diese Ansicht ist rein informativ ... Nachbearbeitung
    erfolgt ueber den Arbeitsbereich HottCAD") und laesst Flaechen, Masse und
    Bauteilzuordnung nicht mehr tabellarisch aendern.

    Woran das haengt, ist EIN Feld: TableZusatz.ProjektPfad3D. Steht dort 'Art=CAD',
    ist die Variante gebunden; ist es leer, ist sie frei bearbeitbar. Gemessen am
    Projekt V4DZX_Nadine Klenke am 04.10.2026: Ist-Zustand und die aus dem Modell
    erzeugte Variante trugen 'Art=CAD', eine von Hand neu angelegte Variante nicht -
    und genau die liess sich bearbeiten. Alles andere war identisch, bis auf die
    laufende Nummer: ProjektGesperrt leer, PROJEKT_ART/ProjAnl_Art/ProjAnl_Erfass
    gleich, VarianteID bei beiden gesetzt, Sperre=1 auf allen Huellflaechen.

    DAS IST EINE ABWAEGUNG, KEINE REPARATUR. Eine geloeste Variante folgt dem
    HottCAD-Modell nicht mehr: aendert sich spaeter die Zeichnung, wandert die
    Aenderung nicht mehr in diese Variante. Deshalb meldet das Skript den Preis mit,
    statt ihn zu verschweigen, und -Probelauf ist der empfohlene erste Aufruf.

    SCHREIBT IN DEN CONTAINER. Die Varianten stehen nicht in SQL-Tabellen, sondern in
    PrMedia.Media als 'eberater.zip' mit neun .BDExit-Tabellen. Das Skript holt den
    Anhang, prueft ihn Satz fuer Satz, baut NUR TableZusatz neu auf, ersetzt im Zip
    nur diesen Eintrag und schreibt zurueck. Alle uebrigen Tabellen bleiben Byte fuer
    Byte unberuehrt, und innerhalb von TableZusatz reisen alle Felder ausser dem
    einen als Rohbytes mit - auch der BinaryFormatter-Graph in Kernel18599V5, den
    eine Umwandlung ueber eine Zeichenkette zerstoeren wuerde.

.HINWEIS
    Die Software muss ZU sein. Sie haelt den Container im Speicher und schreibt ihren
    Stand beim Schliessen zurueck; ein Fenster zu heisst nicht Prozess beendet.

.BEISPIEL
    .\Set-CadBindung.ps1 -ProjectGuid 83f7e8f0-... -Variante 3 -Ziel C:\Temp\a -Probelauf
    .\Set-CadBindung.ps1 -ProjectGuid 83f7e8f0-... -Variante 3 -Ziel C:\Temp\a
    .\Set-CadBindung.ps1 -ProjectGuid 83f7e8f0-... -Variante 3 -Ziel C:\Temp\a -Richtung setzen
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ProjectGuid,
    [Parameter(Mandatory)] [string] $VarianteBez,
    [Parameter(Mandatory)] [string] $Ziel,
    [ValidateSet('loesen', 'setzen')] [string] $Richtung = 'loesen',
    [switch] $Probelauf,
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true',
    [string] $Dateiname = 'cad-bindung.json'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$TABELLE = 'TableZusatz'
$NAMENSTABELLE = 'TableProjekt'      # dort steht VarianteBez je PROJEKT_ID
$FELD    = 'ProjektPfad3D'
$SCHLUESSEL = 'PROJ_ID'

# ---------------------------------------------------------------- Format
#
# Kopf   00 Magic | 08 uint32 Beginn Feldtabelle | 12 uint16 Feldzahl
#        14 uint16 Satzzahl | danach die Feldtabelle
# Satz   Anwesenheitskarte (2 Bit je Feld, aufgerundet + 1 Byte), dann die Werte
#        der vorhandenen Felder in Feldreihenfolge. Bitwert 1 = Feld FEHLT.
# Breite Code 73/75 -> Text, Laenge steht in "Typ" Bytes davor.
#        sonst feste Breite "Typ" Bytes (2/1 int16, 4/1 int32, 8/4 double, 2/3 kurz).
#
# Anders als in Export-Sanierungsvarianten.ps1 behaelt der Leser hier je Feld die
# ROHBYTES. Nur so kann der Schreiber alles unveraendert durchreichen, was er nicht
# selbst setzt - einschliesslich der Felder, deren Typ gar nicht gedeutet wird.

function Lies-Kopf([byte[]] $b) {
    $p = [BitConverter]::ToUInt32($b, 8)
    $felder = New-Object System.Collections.ArrayList

    while ($p -lt $b.Length - 8) {
        $len = $b[$p]
        if ($len -lt 1 -or $len -gt 40) { break }
        $name = -join ($b[($p + 1)..($p + $len)] | ForEach-Object { [char]$_ })
        # Feldnamen koennen EIN Zeichen lang sein (TableZusatz: A, B, B1).
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

function Lies-Satz-Roh([byte[]] $b, $k, [int] $satz) {
    $o = $satz + $k.Vorspann
    $werte = New-Object System.Collections.ArrayList

    for ($i = 0; $i -lt $k.Felder.Count; $i++) {
        $f = $k.Felder[$i]
        $fehlt = (($b[$satz + 1 + [math]::Floor($i / 4)] -shr (($i % 4) * 2)) -band 3) -ne 0
        if ($fehlt) {
            [void] $werte.Add([pscustomobject]@{ Nr = $i; Name = $f.Name; Da = $false; Roh = $null; Wert = $null })
            continue
        }

        $text = ($f.Code -eq 73 -or $f.Code -eq 75)
        if ($text) {
            $kopf = [int] $f.Typ
            $nutz = switch ($f.Typ) {
                1 { [int] $b[$o] }
                2 { [int] [BitConverter]::ToUInt16($b, $o) }
                default { [int] [BitConverter]::ToUInt32($b, $o) }
            }
        } else {
            $kopf = 0
            $nutz = [int] $f.Typ
        }

        $ganz = $kopf + $nutz
        if ($o + $ganz -gt $b.Length) { throw "Feld $($f.Name) laeuft ueber das Dateiende." }

        $roh = New-Object byte[] $ganz
        [Array]::Copy($b, $o, $roh, 0, $ganz)

        $w = if ($text) {
            if ($nutz) { [Text.Encoding]::GetEncoding(1252).GetString($b, $o + $kopf, $nutz) } else { '' }
        } else {
            switch ("$($f.Typ)/$($f.Code)") {
                '4/1' { [BitConverter]::ToInt32($b, $o) }
                '2/1' { [BitConverter]::ToInt16($b, $o) }
                '8/4' { [BitConverter]::ToDouble($b, $o) }
                '2/3' { [BitConverter]::ToUInt16($b, $o) }
                default { $null }
            }
        }

        [void] $werte.Add([pscustomobject]@{ Nr = $i; Name = $f.Name; Da = $true; Roh = $roh; Wert = $w })
        $o += $ganz
    }

    [pscustomobject]@{ Satz = $satz; Ende = $o; Werte = $werte }
}

# Baut einen Satz neu auf. Alles, was nicht in $Setze steht, wandert als Rohbytes
# durch; ein Feld, das bisher fehlte, wird in der Anwesenheitskarte freigeschaltet.
function Schreib-Satz([byte[]] $b, $k, $gelesen, [hashtable] $Setze) {
    $karte = New-Object byte[] $k.Vorspann
    [Array]::Copy($b, $gelesen.Satz, $karte, 0, $k.Vorspann)
    $strom = New-Object System.Collections.Generic.List[byte]

    foreach ($w in $gelesen.Werte) {
        $f = $k.Felder[$w.Nr]
        $neu = $Setze.ContainsKey($f.Name)
        if (-not $w.Da -and -not $neu) { continue }
        if (-not $neu) { $strom.AddRange($w.Roh); continue }

        $i = $w.Nr
        $bi = 1 + [math]::Floor($i / 4)
        $karte[$bi] = $karte[$bi] -band (-bnot (3 -shl (($i % 4) * 2)))   # 0 = steht im Satz

        $wert = $Setze[$f.Name]
        if ($f.Code -eq 73 -or $f.Code -eq 75) {
            # Zuweisung DIREKT in den Zweigen: ein "$t = if (...) { $feld }" faltet
            # ein Bytefeld beim Zuweisen auf und ergaebe ein Object[].
            if ($wert -is [byte[]]) { $t = $wert }
            else { $t = [Text.Encoding]::GetEncoding(1252).GetBytes([string] $wert) }
            switch ($f.Typ) {
                1 { $strom.Add([byte] $t.Length) }
                2 { $strom.AddRange([BitConverter]::GetBytes([uint16] $t.Length)) }
                default { $strom.AddRange([BitConverter]::GetBytes([uint32] $t.Length)) }
            }
            $strom.AddRange($t)
        } else {
            switch ("$($f.Typ)/$($f.Code)") {
                '4/1' { $strom.AddRange([BitConverter]::GetBytes([int]    $wert)) }
                '2/1' { $strom.AddRange([BitConverter]::GetBytes([int16]  $wert)) }
                '8/4' { $strom.AddRange([BitConverter]::GetBytes([double] $wert)) }
                '2/3' { $strom.AddRange([BitConverter]::GetBytes([uint16] $wert)) }
                default { throw "Feld $($f.Name) hat Typ $($f.Typ)/$($f.Code) - dafuer gibt es keinen Schreibweg." }
            }
        }
    }

    # Fuehrendes Komma: sonst faltet PowerShell das Bytefeld beim Zurueckgeben auf.
    , [byte[]] ($karte + $strom.ToArray())
}

# Liest eine Tabelle Satz fuer Satz durch und haelt das Ergebnis gegen die
# Satzzahl im Kopf. Laeuft das nicht sauber durch, stimmt die Deutung nicht -
# und dann wird nichts geschrieben.
function Pruefe-Tabelle([byte[]] $b, [string] $name) {
    $k = Lies-Kopf $b
    $n = 0; $o = $k.Daten
    while ($o -lt $b.Length) { $r = Lies-Satz-Roh $b $k $o; $n++; $o = $r.Ende }
    if ($n -ne $k.Satzzahl) { throw "$name : $n Saetze gelesen, der Kopf nennt $($k.Satzzahl)." }
    return $n
}

# ---------------------------------------------------------------- Vorbedingung

# Die Software haelt den Container im Speicher. Geprueft wird Name UND Pfad,
# damit ein fremdes Programm gleichen Namens nicht grundlos sperrt; laesst sich
# der Pfad nicht lesen, wird gesperrt - im Zweifel nicht schreiben.
$schreiber = 'Energie', 'Simulation', 'RenovationAssistant', 'ETUSimulation',
             'Viewer', 'MeinSanierungsfahrplan', 'hottcad'
$offen = @(Get-Process -ErrorAction SilentlyContinue |
           Where-Object { $schreiber -contains $_.ProcessName } |
           Where-Object {
               $pfad = $null
               try { $pfad = $_.Path } catch { }
               -not $pfad -or $pfad -like '*\HSETU\*'
           })
if ($offen -and -not $Probelauf) {
    throw ("Erst die Software schliessen - es laeuft: " +
           (($offen | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', ') +
           ". Sie haelt den Container im Speicher und schreibt ihren Stand beim Schliessen zurueck.")
}

New-Item -ItemType Directory -Force -Path $Ziel | Out-Null

# ---------------------------------------------------------------- Container holen

$con = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$con.Open()
try {
    $c = $con.CreateCommand()
    $c.CommandText = @'
SELECT TOP 1 m.Media, CONVERT(varchar(19), m.StampEdit, 120), p.LongDesc
  FROM PrMedia m
  JOIN PrProject p ON p.UUID = m.ProjectUUID
 WHERE m.ProjectUUID = @u AND m.MediaName = 'eberater.zip'
'@
    $null = $c.Parameters.AddWithValue('@u', [guid] $ProjectGuid)
    $r = $c.ExecuteReader()
    if (-not $r.Read()) { $r.Close(); throw "Das Projekt $ProjectGuid hat keinen Anhang 'eberater.zip'." }
    $roh = [byte[]] $r[0]
    $gespeichert = [string] $r[1]
    $projektname = [string] $r[2]
    $r.Close()

    # Ohne Rueckweg wird nicht angefasst.
    $sicherung = Join-Path $Ziel 'eberater-ORIGINAL.zip'
    [System.IO.File]::WriteAllBytes($sicherung, $roh)
    $sha = (Get-FileHash $sicherung -Algorithm SHA256).Hash

    # ------------------------------------------------------------ Entpacken
    $tabellen = [ordered] @{}
    $strom = New-Object System.IO.MemoryStream(, $roh)
    $zip = New-Object System.IO.Compression.ZipArchive($strom, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach ($eintrag in $zip.Entries) {
            if ($eintrag.Name -notlike '*.BDExit') { continue }
            $ms = New-Object System.IO.MemoryStream
            $s = $eintrag.Open(); $s.CopyTo($ms); $s.Close()
            $tabellen[[IO.Path]::GetFileNameWithoutExtension($eintrag.Name)] = $ms.ToArray()
            $ms.Dispose()
        }
    } finally { $zip.Dispose(); $strom.Dispose() }

    if (-not $tabellen.Contains($TABELLE)) {
        throw "Im Container fehlt $TABELLE - er traegt: $(($tabellen.Keys) -join ', ')."
    }

    # ------------------------------------------------------------ Pruefstein
    $pruefung = [ordered] @{}
    foreach ($name in $tabellen.Keys) { $pruefung[$name] = Pruefe-Tabelle $tabellen[$name] $name }

    function Feld($satz, $name) { ($satz.Werte | Where-Object Name -eq $name).Wert }

    # --------------------------------------------------- Variante ueber den NAMEN
    #
    # NICHT ueber die Nummer. PROJEKT_ID ist fluechtig: werden Varianten
    # geloescht, vergibt die Software die Nummern neu - am 03.10.2026 trug
    # dasselbe Paket noch die 12, am 04.10. die 3. Ein Auftrag, der eine Nummer
    # mitbringt, trifft dann lautlos die falsche Variante. Der Name aendert sich
    # nur, wenn ihn jemand aendert.
    $bn = $tabellen[$NAMENSTABELLE]
    $kn = Lies-Kopf $bn
    $namen = @(); $o = $kn.Daten
    while ($o -lt $bn.Length) {
        $rn = Lies-Satz-Roh $bn $kn $o
        $namen += [pscustomobject]@{
            Nummer = [int] (Feld $rn 'PROJEKT_ID')
            Bez    = ([string] (Feld $rn 'VarianteBez')).Trim()
        }
        $o = $rn.Ende
    }

    $gesucht = $VarianteBez.Trim()
    if (-not $gesucht) { throw 'Ohne Variantennamen wird nichts angefasst.' }

    $gefunden = @($namen | Where-Object { $_.Bez -eq $gesucht })
    if (-not $gefunden) {
        $liste = @($namen | Where-Object { $_.Bez } | ForEach-Object { "'$($_.Bez)'" })
        throw ("Eine Variante '$gesucht' gibt es nicht. Vorhanden: " +
               $(if ($liste) { $liste -join ', ' } else { '(keine)' }) + '.')
    }
    if ($gefunden.Count -gt 1) {
        throw "Der Name '$gesucht' kommt $($gefunden.Count)-mal vor - so laesst sich nicht eindeutig waehlen."
    }

    $nummer = $gefunden[0].Nummer

    # Der Ist-Zustand IST das Modell. Loest man ihn, haengt das ganze Projekt
    # nicht mehr an der Zeichnung - das ist etwas anderes als eine freie Variante.
    $istZustand = @($namen | Where-Object { -not $_.Bez } | ForEach-Object { $_.Nummer })
    if ($istZustand -contains $nummer) {
        throw 'Das ist der Ist-Zustand, nicht eine Variante. Ihn von der Zeichnung zu loesen, haette das ganze Projekt zur Folge - dieses Skript tut es nicht.'
    }

    # ------------------------------------------------------------ Lesen
    $b = $tabellen[$TABELLE]
    $k = Lies-Kopf $b
    if (-not ($k.Felder | Where-Object Name -eq $FELD)) {
        throw "$TABELLE kennt kein Feld $FELD."
    }

    $saetze = @(); $o = $k.Daten
    while ($o -lt $b.Length) { $r2 = Lies-Satz-Roh $b $k $o; $saetze += $r2; $o = $r2.Ende }

    $stand = @()
    foreach ($s in $saetze) {
        $nr = [int] (Feld $s $SCHLUESSEL)
        $stand += [pscustomobject]@{
            Variante = $nr
            Bez      = [string] (@($namen | Where-Object Nummer -eq $nr | ForEach-Object { $_.Bez }) | Select-Object -First 1)
            Wert     = [string] (Feld $s $FELD)
        }
    }

    # NICHT $ziel nennen: PowerShell unterscheidet keine Gross-/Kleinschreibung,
    # und $Ziel ist der Ausgabeordner. Die Zuweisung wuerde ihn ueberschreiben.
    $treffer = @($stand | Where-Object Variante -eq $nummer)
    if (-not $treffer) {
        throw ("Variante '$gesucht' (Nr. $nummer) steht in $TABELLE nicht. Dort: " +
               (($stand | ForEach-Object { $_.Variante }) -join ', ') + '.')
    }
    if ($treffer.Count -gt 1) { throw "Nr. $nummer kommt in $TABELLE $($treffer.Count)-mal vor - das Skript ruehrt nichts an." }

    $vorher = $treffer[0].Wert

    # Beim Setzen wird der Wert NICHT erfunden, sondern von einer Variante
    # genommen, die noch gebunden ist. So steht nie eine abgeschriebene
    # Zeichenkette im Code.
    if ($Richtung -eq 'setzen') {
        $quelle = @($stand | Where-Object { $_.Variante -ne $nummer -and $_.Wert.Trim() })
        if (-not $quelle) {
            throw "Keine andere Variante traegt eine CAD-Bindung - woher der Wert kommen soll, ist damit offen."
        }
        $verschieden = @($quelle | ForEach-Object { $_.Wert } | Sort-Object -Unique)
        if ($verschieden.Count -ne 1) {
            throw "Die gebundenen Varianten tragen verschiedene Werte ($($verschieden.Count)) - nichts geschrieben."
        }
        $nachher = $verschieden[0]
    } else {
        $nachher = ''
    }

    $ergebnis = [ordered] @{
        projekt         = $projektname
        projekt_guid    = $ProjectGuid
        gespeichert_am  = $gespeichert
        variante        = $gesucht
        variante_nr     = $nummer
        richtung        = $Richtung
        feld            = "$TABELLE.$FELD"
        vorher          = $vorher
        nachher         = $nachher
        gebunden_vorher = [bool] $vorher.Trim()
        gebunden_nachher= [bool] $nachher.Trim()
        probelauf       = [bool] $Probelauf
        sicherung       = $sicherung
        sha256          = $sha
        saetze_geprueft = $pruefung
        alle_varianten  = @($stand | ForEach-Object { [ordered] @{ name = $_.Bez; nummer = $_.Variante; gebunden = [bool] $_.Wert.Trim() } })
        hinweis         = 'Eine geloeste Variante folgt dem HottCAD-Modell nicht mehr: spaetere Aenderungen an der Zeichnung wandern nicht mehr hinein.'
        geschrieben     = $false
    }

    if ($vorher -eq $nachher) {
        $ergebnis['bemerkung'] = 'Schon im gewuenschten Zustand - nichts zu tun.'
        $ergebnis | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $Ziel $Dateiname) -Encoding UTF8
        Write-Output "Variante '$gesucht' : $FELD steht bereits auf '$nachher' - nichts geschrieben."
        return
    }

    if ($Probelauf) {
        $ergebnis | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $Ziel $Dateiname) -Encoding UTF8
        Write-Output "PROBELAUF - Variante '$gesucht' : '$vorher' -> '$nachher', nichts geschrieben."
        return
    }

    # ------------------------------------------------------------ Tabelle neu bauen
    $kopf = New-Object byte[] $k.Daten
    [Array]::Copy($b, 0, $kopf, 0, $k.Daten)
    $neu = New-Object System.Collections.Generic.List[byte]
    $neu.AddRange($kopf)

    foreach ($s in $saetze) {
        $setze = @{}
        if ([int] (Feld $s $SCHLUESSEL) -eq $nummer) { $setze[$FELD] = $nachher }
        $neu.AddRange([byte[]] (Schreib-Satz $b $k $s $setze))
    }
    $neuBytes = $neu.ToArray()

    # Gegenprobe am neu gebauten Stand, bevor er in den Container geht.
    $null = Pruefe-Tabelle $neuBytes $TABELLE
    $k3 = Lies-Kopf $neuBytes
    $o = $k3.Daten; $nachKontrolle = $null
    while ($o -lt $neuBytes.Length) {
        $r3 = Lies-Satz-Roh $neuBytes $k3 $o
        if ([int] (Feld $r3 $SCHLUESSEL) -eq $nummer) { $nachKontrolle = [string] (Feld $r3 $FELD) }
        $o = $r3.Ende
    }
    if ($nachKontrolle -ne $nachher) {
        throw "Die neu gebaute Tabelle traegt '$nachKontrolle' statt '$nachher' - nichts geschrieben."
    }

    # ------------------------------------------------------------ Zip ersetzen
    # Nur dieser eine Eintrag wird getauscht; alles andere bleibt, wie es war.
    $zielZip = Join-Path $Ziel 'eberater-NEU.zip'
    Copy-Item $sicherung $zielZip -Force
    $zip2 = [System.IO.Compression.ZipFile]::Open($zielZip, 'Update')
    try {
        $e = $zip2.Entries | Where-Object { $_.Name -eq "$TABELLE.BDExit" }
        if (-not $e) { throw "Im Zip fehlt der Eintrag $TABELLE.BDExit." }
        $pfadImZip = $e.FullName
        $e.Delete()
        $e2 = $zip2.CreateEntry($pfadImZip)
        $st = $e2.Open(); $st.Write($neuBytes, 0, $neuBytes.Length); $st.Close()
    } finally { $zip2.Dispose() }

    $fertig = [System.IO.File]::ReadAllBytes($zielZip)

    # ------------------------------------------------------------ Zurueckschreiben
    $tx = $con.BeginTransaction()
    try {
        $u = $con.CreateCommand()
        $u.Transaction = $tx
        $u.CommandText = "UPDATE PrMedia SET Media = @m WHERE ProjectUUID = @u AND MediaName = 'eberater.zip'"
        $pm = $u.Parameters.Add('@m', [System.Data.SqlDbType]::VarBinary, -1); $pm.Value = $fertig
        $null = $u.Parameters.AddWithValue('@u', [guid] $ProjectGuid)
        $n = $u.ExecuteNonQuery()
        if ($n -ne 1) { throw "UPDATE hat $n Zeilen getroffen, erwartet genau eine." }

        # Gegenprobe aus der Datenbank, nicht aus dem Speicher.
        $g = $con.CreateCommand(); $g.Transaction = $tx
        $g.CommandText = "SELECT Media FROM PrMedia WHERE ProjectUUID = @u AND MediaName = 'eberater.zip'"
        $null = $g.Parameters.AddWithValue('@u', [guid] $ProjectGuid)
        $zurueck = [byte[]] $g.ExecuteScalar()
        if ($zurueck.Length -ne $fertig.Length) {
            throw "Gegenprobe: $($zurueck.Length) B in der Datenbank statt $($fertig.Length)."
        }

        $ms2 = New-Object System.IO.MemoryStream(, $zurueck)
        $zip3 = New-Object System.IO.Compression.ZipArchive($ms2, [System.IO.Compression.ZipArchiveMode]::Read)
        try {
            $e3 = $zip3.Entries | Where-Object { $_.Name -eq "$TABELLE.BDExit" }
            $ms3 = New-Object System.IO.MemoryStream
            $s3 = $e3.Open(); $s3.CopyTo($ms3); $s3.Close()
            $pruefBytes = $ms3.ToArray(); $ms3.Dispose()
        } finally { $zip3.Dispose(); $ms2.Dispose() }

        $k4 = Lies-Kopf $pruefBytes
        $o = $k4.Daten; $endkontrolle = $null
        while ($o -lt $pruefBytes.Length) {
            $r4 = Lies-Satz-Roh $pruefBytes $k4 $o
            if ([int] (Feld $r4 $SCHLUESSEL) -eq $nummer) { $endkontrolle = [string] (Feld $r4 $FELD) }
            $o = $r4.Ende
        }
        if ($endkontrolle -ne $nachher) {
            throw "In der Datenbank steht '$endkontrolle' statt '$nachher' - zurueckgerollt."
        }

        $tx.Commit(); $tx = $null
    } finally {
        if ($tx) { try { $tx.Rollback() } catch { } }
    }

    $ergebnis['geschrieben'] = $true
    $ergebnis['container_bytes'] = $fertig.Length
    $ergebnis | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $Ziel $Dateiname) -Encoding UTF8

    Write-Output "Variante '$gesucht' : $FELD '$vorher' -> '$nachher'. Geschrieben und gegengeprueft."
    Write-Output "Rueckweg: $sicherung"
    Write-Output "Die Software zeigt es erst nach einem Neustart."
}
finally { $con.Close() }
