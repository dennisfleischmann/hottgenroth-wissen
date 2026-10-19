# Prueft alle Werkzeuge gegen mindestens zwei Projekte.
#
# Hintergrund: mehrfach sah ein Werkzeug fertig aus und enthielt doch eine
# Annahme, die nur am Ursprungsprojekt stimmte - leere Tabellen, fortlaufende
# Projektnummern, drei Leitungstypen im Pool. An einem Projekt allein faellt so
# etwas nie auf.
#
#   .\pruefe-werkzeuge.ps1 -Projekte @('f2b99e66-...','efdb6c6e-...')
#
# Schreibt nichts in die Datenbank. Alle Aenderungen laufen in einem
# Arbeitsordner unter $env:TEMP.

param(
    [string[]] $Projekte = @(
        'f2b99e66-bfeb-494f-adde-81ab3eb1ff44',   # 20260626_HottCAD_82024 - 6 Varianten, Warmwasser
        'efdb6c6e-da4f-4fa2-af7e-06bd4003b295'    # Werner Grotz - 4 Varianten
    ),
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true'
)

$ErrorActionPreference = 'Stop'
$hier = $PSScriptRoot
$ibp  = Join-Path $hier 'ibp'
$bx   = Join-Path $hier 'bdexit'
. (Join-Path $bx 'bde.ps1')
. (Join-Path $bx 'satz.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Muss vor der ersten Pruefung geladen sein, nicht erst am Ende: die JSON-
# Pruefungen brauchen den Serialisierer waehrend der Schleife.
Add-Type -AssemblyName System.Web.Extensions

$arbeit = Join-Path $env:TEMP ('hsetu-pruefung-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $arbeit | Out-Null

$ergebnisse = New-Object System.Collections.ArrayList

# Eine Pruefung kann auf einer vorigen aufbauen. Faellt die Voraussetzung aus,
# wird die Folgepruefung uebersprungen statt mit einer Folgemeldung zu scheitern
# ("Datei nicht gefunden" statt der eigentlichen Ursache).
function Pruefe([string] $Projekt, [string] $Was, [scriptblock] $Block, [string] $Braucht) {
    if ($Braucht) {
        $v = $ergebnisse | Where-Object { $_.Projekt -eq $Projekt -and $_.Was -eq $Braucht }
        if (-not $v -or $v.Urteil -ne 'ok') {
            [void] $ergebnisse.Add([pscustomobject]@{ Projekt = $Projekt; Was = $Was; Urteil = '-'; Info = "uebersprungen, '$Braucht' fehlgeschlagen" })
            return
        }
    }
    try {
        $t = & $Block
        [void] $ergebnisse.Add([pscustomobject]@{ Projekt = $Projekt; Was = $Was; Urteil = 'ok'; Info = "$t" })
    } catch {
        [void] $ergebnisse.Add([pscustomobject]@{ Projekt = $Projekt; Was = $Was; Urteil = 'FEHLER'; Info = $_.Exception.Message })
    }
}

# Vergleichbare Fassung einer Anlagen-JSON: alles ausser den Bezeichnungen und
# Kennungen, die sich beim Neuanlegen zwangslaeufig aendern. Damit laesst sich
# pruefen, ob ein Rundlauf lesen -> loeschen -> setzen dasselbe Anlagenbild
# ergibt. Genau daran sind mehrere stille Fehler aufgefallen: eine Solaranlage,
# die als Kessel wieder auftauchte; eine zweite Uebergabe, die verschwand; eine
# Auslegungstemperatur, die durch die Vorgabe 70/55 ersetzt wurde.
function Kern($wert) {
    if ($wert -is [System.Collections.IDictionary]) {
        $teile = foreach ($s in ($wert.Keys | Sort-Object)) {
            # 'bestand' zaehlt die Pooltypen im Modell. Ein gewachsenes Projekt
            # schleppt dort ungenutzte Typen mit (9 Leitungstypen fuer 3
            # Leitungen), die beim Neuaufbau wegfallen. Das ist Bearbeitungs-
            # geschichte, nicht Anlagenkonfiguration.
            if ($s -in @('name', 'zone', 'bestand')) { continue }
            "$s=" + (Kern $wert[$s])
        }
        return '{' + ($teile -join ';') + '}'
    }
    if ($wert -is [object[]]) {
        return '[' + (($wert | ForEach-Object { Kern $_ }) -join ',') + ']'
    }
    return "$wert"
}

function Hole([string] $Projekt, [string] $Name, [string] $Ziel) {
    $c = New-Object System.Data.SqlClient.SqlConnection $Verbindung
    $c.Open()
    try {
        $k = $c.CreateCommand()
        $k.CommandText = "SELECT Media FROM PrMedia WHERE ProjectUUID=@p AND MediaName=@n"
        [void] $k.Parameters.AddWithValue('@p', [Guid] $Projekt)
        [void] $k.Parameters.AddWithValue('@n', $Name)
        $roh = $k.ExecuteScalar()
        if ($null -eq $roh) { return $false }
        [IO.File]::WriteAllBytes($Ziel, $roh)
        return $true
    } finally { $c.Close() }
}

foreach ($p in $Projekte) {
    $kurz = $p.Substring(0, 8)
    $ordner = Join-Path $arbeit $kurz
    New-Item -ItemType Directory -Force -Path $ordner | Out-Null
    $blob = Join-Path $ordner 'kernel.bin'
    $zip  = Join-Path $ordner 'eberater.zip'
    $aus  = Join-Path $ordner 'entpackt'
    New-Item -ItemType Directory -Force -Path $aus | Out-Null

    if (-not (Hole $p 'Kernel18599V5.bin' $blob)) { Write-Host "$kurz : kein IBP-Blob, uebersprungen"; continue }
    [void] (Hole $p 'eberater.zip' $zip)
    $z = [System.IO.Compression.ZipFile]::OpenRead($zip)
    foreach ($e in $z.Entries) { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $aus $e.Name), $true) }
    $z.Dispose()

    # ---- .BDExit: jede Tabelle lesen UND unveraendert zurueckschreiben
    Pruefe $kurz 'bde/satz: alle Tabellen' {
        $n = 0; $gleich = 0
        foreach ($f in Get-ChildItem $aus -Filter *.BDExit) {
            $b = [System.IO.File]::ReadAllBytes($f.FullName); $k = BdeKopf $b
            $o = $k.Daten; $c = 0
            while ($o -lt $b.Length) {
                $r = BdeLies $b $k $o -1
                $neu = BdeSchreib $b $k $r @{}
                $alt = New-Object byte[] ($r.Ende - $o); [Array]::Copy($b, $o, $alt, 0, $alt.Length)
                if ($neu.Length -eq $alt.Length -and -not (Compare-Object $neu $alt -SyncWindow 0)) { $gleich++ }
                $o = $r.Ende; $c++
            }
            if ($o -ne $b.Length) { throw "$($f.BaseName): Ende $o statt $($b.Length)" }
            if ($c -ne $k.Satzzahl) { throw "$($f.BaseName): $c Saetze statt $($k.Satzzahl)" }
            $n += $c
        }
        if ($gleich -ne $n) { throw "$gleich von $n Saetzen identisch" }
        "$n Saetze, alle identisch zurueckgeschrieben"
    }

    # ---- Variante anlegen, nur Vorschau
    Pruefe $kurz 'variante-bauen (Vorschau)' {
        $b = [System.IO.File]::ReadAllBytes((Join-Path $aus 'TableProjekt.BDExit')); $k = BdeKopf $b
        $o = $k.Daten; $erste = (BdeLies $b $k $o -1)
        $von = ($erste.Werte | Where-Object Name -eq 'PROJEKT_ID').Wert
        $t = & (Join-Path $bx 'variante-bauen.ps1') -Ordner $aus -VonProj $von -Name 'Pruefung' -Vorschau
        ($t | Where-Object { $_ -match 'Vorlage' }) -join ''
    }

    # ---- IBP-Werkzeuge
    Pruefe $kurz 'ibp-bauteile' {
        $t = & (Join-Path $ibp 'ibp-bauteile.exe') $blob 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($t -join '; ') }
        ($t | Where-Object { $_ -match 'Huellflaeche gesamt' }) -join ''
    }
    Pruefe $kurz 'ibp-matrix' {
        $t = & (Join-Path $ibp 'ibp-matrix.exe') $blob 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($t -join '; ') }
        ($t | Where-Object { $_ -match 'Count =' }) -join ' '
    }
    Pruefe $kurz 'ibp-anlage-lesen' {
        $j = Join-Path $ordner 'anlage.json'
        & (Join-Path $ibp 'ibp-anlage-lesen.exe') $blob > $j 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Exitcode' }
        $roh = Get-Content $j -Raw
        [void] ([System.Web.Script.Serialization.JavaScriptSerializer]::new().DeserializeObject($roh))
        "$([math]::Round((Get-Item $j).Length/1KB,1)) KB, gueltiges JSON"
    }

    # ---- Loeschen und wieder anlegen: der Rundlauf
    Pruefe $kurz 'anlage loeschen + setzen' {
        $ohne = Join-Path $ordner 'ohne.bin'
        $neu  = Join-Path $ordner 'neu.bin'
        & (Join-Path $ibp 'ibp-delete-heating.exe') $blob $ohne 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Loeschen fehlgeschlagen' }
        $t = & (Join-Path $ibp 'ibp-anlage-setzen.exe') $ohne $neu (Join-Path $ordner 'anlage.json') 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($t -join '; ') }
        ($t | Where-Object { $_ -match 'geprueft' }) -join ''
    } 'ibp-anlage-lesen'

    # ---- Der Rundlauf muss dasselbe Anlagenbild ergeben
    Pruefe $kurz 'Rundlauf originaltreu' {
        $neu = Join-Path $ordner 'neu.bin'
        $j2  = Join-Path $ordner 'anlage-neu.json'
        & (Join-Path $ibp 'ibp-anlage-lesen.exe') $neu > $j2 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'Neulesen fehlgeschlagen' }
        $s = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $vor  = Kern ($s.DeserializeObject((Get-Content (Join-Path $ordner 'anlage.json') -Raw)))
        $nach = Kern ($s.DeserializeObject((Get-Content $j2 -Raw)))
        if ($vor -ne $nach) {
            for ($i = 0; $i -lt [Math]::Min($vor.Length, $nach.Length); $i++) {
                if ($vor[$i] -ne $nach[$i]) { break }
            }
            $von = [Math]::Max(0, $i - 60)
            throw "Anlagenbild weicht ab ab Zeichen ${i}:`n   vorher : ..." +
                  $vor.Substring($von, [Math]::Min(160, $vor.Length - $von)) +
                  "`n   nachher: ..." + $nach.Substring($von, [Math]::Min(160, $nach.Length - $von))
        }
        "Anlagenbild identisch ($($vor.Length) Zeichen)"
    } 'anlage loeschen + setzen'

    # ---- Querprobe zwischen den Modellen: zeigt jede Variante das, was sie rechnet?
    #
    # Die einzige Pruefung hier, die KEINE Selbstpruefung ist. Alle anderen
    # fragen "steht da, was ich geschrieben habe" - diese fragt, ob zwei
    # unabhaengige Darstellungen desselben Sachverhalts uebereinstimmen.
    # Genau daran war eine Sanierungsvariante gescheitert, die saniere U-Werte
    # anzeigte und mit den alten rechnete, waehrend alle Selbstpruefungen
    # fehlerfrei durchliefen.
    Pruefe $kurz 'Varianten: Modelle einig' {
        $v = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $t = & (Join-Path $bx 'pruefe-variante.ps1') -Ordner $aus 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $v
        if ($code -ne 0) {
            $z = @($t | Where-Object { $_ -match 'FEHLER|weicht' })
            throw (($z | Select-Object -First 3 | ForEach-Object { ($_ -replace '\s{2,}', ' ').Trim() }) -join ' | ')
        }
        (($t | Where-Object { $_ -match 'vollstaendig, Bauteilliste' }) -join '')
    }

    # ---- Blob in eine Variante schreiben
    Pruefe $kurz 'setze-kernel' {
        $b = [System.IO.File]::ReadAllBytes((Join-Path $aus 'TableZusatz.BDExit')); $k = BdeKopf $b
        $erste = BdeLies $b $k $k.Daten -1
        $proj = ($erste.Werte | Where-Object Name -eq 'PROJ_ID').Wert
        $t = & (Join-Path $bx 'setze-kernel.ps1') -Ordner $aus -Proj $proj -Blob (Join-Path $ordner 'neu.bin')
        ($t | Where-Object { $_ -match 'Gegenprobe' }) -join ''
    } 'anlage loeschen + setzen'
}

""
"Arbeitsordner: $arbeit"
""
$ergebnisse | Format-Table -AutoSize -Wrap
$fehler = @($ergebnisse | Where-Object Urteil -eq 'FEHLER')
""
$uebersprungen = @($ergebnisse | Where-Object Urteil -eq '-')
if ($fehler) { "FEHLGESCHLAGEN: $($fehler.Count) von $($ergebnisse.Count)$(if($uebersprungen){", $($uebersprungen.Count) uebersprungen"})"; exit 1 }
"alle $($ergebnisse.Count) Pruefungen bestanden"
