# Holt den Energieberater-Container aus der Datenbank und schreibt ihn zurueck -
# mit den vier Regeln, an denen man sonst jedes Mal einzeln denken muss.
#
#   1  Energie.exe muss beim ZURUECKSCHREIBEN zu sein. Eine laufende Instanz
#      haelt den Container im Speicher und ueberschreibt beim naechsten Speichern
#      kommentarlos. Ein Prozess ohne Fenster zaehlt auch - einmal lief eine
#      verwaiste Instanz 34 Stunden und hat jeden Schreibvorgang rueckgaengig
#      gemacht.
#   2  Beim HOLEN wird immer gesichert: eberater-ORIGINAL.zip samt SHA-256.
#      Ohne Rueckweg wird nicht angefasst.
#   3  Vor dem Zurueckschreiben der PRUEFSTEIN: jede Tabelle wird Satz fuer Satz
#      durchgelesen und gegen die Satzzahl im Kopf gehalten. Laeuft das nicht
#      durch, stimmt die Deutung nicht - dann wird nicht geschrieben.
#   4  Nach dem Schreiben die Gegenprobe aus der Datenbank, nicht aus dem Speicher.
#
# Nur veraenderte Tabellen werden ersetzt; der Rest des Zip bleibt unberuehrt.
#
#   .\container.ps1 -Projekt 'Messinger' -Ordner .\arbeit
#   ... arbeiten: variante-bauen.ps1, setze-massnahme.ps1, uwerte-uebernehmen.ps1 ...
#   .\container.ps1 -Projekt 'Messinger' -Ordner .\arbeit -Zurueck
#
#   -Projekt   Teil des Projektnamens (LongDesc) oder die UUID
#   -Zurueck   packen und in PrMedia schreiben statt holen
#   -Vorschau  zeigt, was sich geaendert hat, schreibt aber nicht

param(
    [Parameter(Mandatory)] [string] $Projekt,
    [Parameter(Mandatory)] [string] $Ordner,
    [switch] $Zurueck,
    [switch] $Vorschau,
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Projekt-Finden($con, $suche) {
    $c = $con.CreateCommand()
    $leer = [guid]::Empty
    if ([guid]::TryParse($suche, [ref] $leer)) {
        $c.CommandText = 'SELECT UUID, LongDesc FROM PrProject WHERE UUID = @p'
    } else {
        $c.CommandText = "SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE '%' + @p + '%' ORDER BY StampEdit DESC"
    }
    $null = $c.Parameters.AddWithValue('@p', $suche)
    $r = $c.ExecuteReader(); $treffer = @()
    while ($r.Read()) { $treffer += [pscustomobject]@{ UUID = $r[0]; Name = [string] $r[1] } }
    $r.Close()
    if (-not $treffer)          { throw "Kein Projekt zu '$suche'." }
    if ($treffer.Count -gt 1)   {
        throw ("'$suche' trifft $($treffer.Count) Projekte: " +
               (($treffer | ForEach-Object { "$($_.Name) [$($_.UUID)]" }) -join ' | ') +
               "  - genauer angeben oder die UUID nehmen.")
    }
    return $treffer[0]
}

function Pruefstein($ordner) {
    $fehler = @()
    foreach ($f in (Get-ChildItem $ordner -Filter *.BDExit | Sort-Object Name)) {
        try {
            $b = [System.IO.File]::ReadAllBytes($f.FullName)
            $k = BdeKopf $b
            $n = 0; $o = $k.Daten
            while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $n++; $o = $r.Ende }
            if ($n -ne $k.Satzzahl) { $fehler += "$($f.Name): $n Saetze gelesen, Kopf sagt $($k.Satzzahl)" }
            else { "  {0,-24} {1,9} B  {2,4} Saetze  lesbar" -f $f.Name, $b.Length, $n }
        } catch { $fehler += "$($f.Name): $($_.Exception.Message)" }
    }
    if ($fehler) { throw ("PRUEFSTEIN FEHLGESCHLAGEN - nicht geschrieben:`n  " + ($fehler -join "`n  ")) }
}

$con = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$con.Open()
try {
    $p = Projekt-Finden $con $Projekt
    "Projekt: {0}  [{1}]" -f $p.Name, $p.UUID

    if (-not $Zurueck) {
        # ---------------- HOLEN ----------------
        New-Item -ItemType Directory -Force -Path $Ordner | Out-Null
        $c = $con.CreateCommand()
        $c.CommandText = "SELECT TOP 1 Media, CONVERT(varchar(19), StampEdit, 120) FROM PrMedia WHERE ProjectUUID = @u AND MediaName = 'eberater.zip'"
        $null = $c.Parameters.AddWithValue('@u', [guid] $p.UUID)
        $r = $c.ExecuteReader()
        if (-not $r.Read()) { $r.Close(); throw "Das Projekt hat keinen Anhang 'eberater.zip'." }
        $bytes = $r[0]; $stand = $r[1]; $r.Close()

        $sicher = Join-Path $Ordner 'eberater-ORIGINAL.zip'
        [System.IO.File]::WriteAllBytes($sicher, $bytes)
        $sha = (Get-FileHash $sicher -Algorithm SHA256).Hash
        "Stand in der Datenbank: {0}   {1} B" -f $stand, $bytes.Length
        "Sicherung: {0}" -f $sicher
        "SHA-256:   {0}" -f $sha
        Expand-Archive -Path $sicher -DestinationPath $Ordner -Force
        "Entpackt nach {0}:" -f $Ordner
        Pruefstein $Ordner
        "`nBereit. Zum Zurueckschreiben denselben Aufruf mit -Zurueck."
    }
    else {
        # ---------------- ZURUECKSCHREIBEN ----------------
        $lauf = Get-Process -Name Energie -ErrorAction SilentlyContinue
        if ($lauf) {
            throw ("Energie.exe laeuft (PID " + (($lauf | ForEach-Object Id) -join ', ') +
                   "). Sie ueberschreibt jeden Schreibvorgang beim naechsten Speichern. " +
                   "Erst in der Software speichern, dann beenden - und im Task-Manager nachsehen, " +
                   "ob der Prozess wirklich weg ist.")
        }
        $sicher = Join-Path $Ordner 'eberater-ORIGINAL.zip'
        if (-not (Test-Path $sicher)) { throw "$sicher fehlt - ohne Sicherung wird nicht geschrieben. Erst holen." }

        "Pruefstein:"
        Pruefstein $Ordner

        # Nur geaenderte Eintraege ersetzen - alles andere bleibt, wie es war.
        $ziel = Join-Path $Ordner 'eberater-NEU.zip'
        Copy-Item $sicher $ziel -Force
        $zip = [System.IO.Compression.ZipFile]::Open($ziel, 'Update')
        $geaendert = @()
        try {
            foreach ($f in (Get-ChildItem $Ordner -Filter *.BDExit | Sort-Object Name)) {
                $neu = [System.IO.File]::ReadAllBytes($f.FullName)
                $alt = $null
                $e = $zip.Entries | Where-Object FullName -eq $f.Name
                if ($e) {
                    $s = $e.Open(); $ms = New-Object System.IO.MemoryStream; $s.CopyTo($ms); $s.Close()
                    $alt = $ms.ToArray(); $ms.Dispose()
                }
                $gleich = $alt -and $alt.Length -eq $neu.Length
                if ($gleich) { for ($i = 0; $i -lt $neu.Length; $i++) { if ($alt[$i] -ne $neu[$i]) { $gleich = $false; break } } }
                if ($gleich) { continue }
                if ($e) { $e.Delete() }
                $e2 = $zip.CreateEntry($f.Name)
                $st = $e2.Open(); $st.Write($neu, 0, $neu.Length); $st.Close()
                $geaendert += [pscustomobject]@{ Name = $f.Name; Vorher = $(if ($alt) { $alt.Length } else { 0 }); Nachher = $neu.Length }
            }
        } finally { $zip.Dispose() }

        if (-not $geaendert) { Remove-Item $ziel -Force; "Nichts geaendert - nichts geschrieben."; return }
        "`nGeaenderte Tabellen:"
        $geaendert | ForEach-Object { "  {0,-24} {1,9} -> {2,9} B" -f $_.Name, $_.Vorher, $_.Nachher }
        $fertig = [System.IO.File]::ReadAllBytes($ziel)
        "Container: {0} -> {1} B" -f (Get-Item $sicher).Length, $fertig.Length

        if ($Vorschau) { "Vorschau - nichts geschrieben"; return }

        $u = $con.CreateCommand()
        $u.CommandText = "UPDATE PrMedia SET Media = @m WHERE ProjectUUID = @u AND MediaName = 'eberater.zip'"
        $pm = $u.Parameters.Add('@m', [System.Data.SqlDbType]::VarBinary, -1); $pm.Value = $fertig
        $null = $u.Parameters.AddWithValue('@u', [guid] $p.UUID)
        $n = $u.ExecuteNonQuery()
        if ($n -ne 1) { throw "UPDATE hat $n Zeilen getroffen, erwartet 1." }

        # Gegenprobe aus der Datenbank, nicht aus dem Speicher.
        $g = $con.CreateCommand()
        $g.CommandText = "SELECT DATALENGTH(Media) FROM PrMedia WHERE ProjectUUID = @u AND MediaName = 'eberater.zip'"
        $null = $g.Parameters.AddWithValue('@u', [guid] $p.UUID)
        $inDb = [int] $g.ExecuteScalar()
        if ($inDb -ne $fertig.Length) { throw "Gegenprobe: $inDb B in der Datenbank statt $($fertig.Length)." }
        "Geschrieben. {0} B in der Datenbank, Gegenprobe bestanden." -f $inDb
        "Rueckweg: {0}" -f $sicher
    }
}
finally { $con.Close() }
