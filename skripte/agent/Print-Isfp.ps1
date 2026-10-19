# Erzeugt iSFP und Umsetzungshilfe als PDF - auf dem Rechner des Beraters.
#
# WAS HIER PASSIERT
#   1. Den Speicherstand der iSFP-Maske aus PrMedia holen (MediaType 11,
#      MediaName 'iSFP2.xml'). Das IST die .mSFPprojekt-Datei, byte-gleich.
#   2. MeinSanierungsfahrplan.exe im Stapelbetrieb darauf ansetzen.
#   3. Die beiden PDFs und das Protokoll liegen lassen; der Auftrag laedt sie hoch.
#
# DIE KOMMANDOZEILE DER DRUCKAPPLIKATION
#   --infile <datei>        Eingabe (.mSFPprojekt)
#   --create-pdf            normale Fassung erzeugen
#   --preview               Vorschaudruck statt normaler Fassung
#   --outfile-sfp <pdf>     Ausgabe iSFP
#   --outfile-uh <pdf>      Ausgabe Umsetzungshilfe
#   --logfile <datei>       Protokoll; ohne diesen Parameter schreibt sie keines
#   --disable-gpu           ohne Hardwarezugriff - auf einem Dienstkonto noetig
#
# NACHGEMESSEN am 27.09.2026 mit dem fertigen Fahrplan Klenke: 28,8 Sekunden,
# Exitcode 0, iSFP 17 Seiten / 2,2 MB, Umsetzungshilfe 43 Seiten / 2,4 MB, und
# die Protokolldatei blieb LEER - kein Mangel.
#
# DER DRUCK VERAENDERT DAS PROJEKT NICHT. Die Eingabedatei war nach dem Lauf
# byte-gleich. Das ist der Unterschied zum Druck von Hand: dort HAELT die
# Anwendung die Datei offen und schreibt sie beim Schliessen zurueck - dabei
# rechnet sie jedes Bild auf rund 300 px herunter. Im Stapelbetrieb nicht.
#
# AUFRUF
#   .\Print-Isfp.ps1 -ProjectGuid '<GUID>' -Ziel '<ordner>'
#   .\Print-Isfp.ps1 -ProjectGuid '<GUID>' -Ziel '<ordner>' -Vorschau

param(
    [Parameter(Mandatory)] [string] $ProjectGuid,
    [Parameter(Mandatory)] [string] $Ziel,
    [switch] $Vorschau,
    [int] $Frist = 600,
    [string] $Anwendung,
    [string] $Verbindung = 'Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true'
)

$ErrorActionPreference = 'Stop'

$GUID = '^\{?[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}?$'
if ($ProjectGuid -notmatch $GUID) { throw "'$ProjectGuid' ist keine Projekt-GUID." }
$projGuid = $ProjectGuid.Trim('{', '}')
New-Item -ItemType Directory -Force -Path $Ziel | Out-Null

# Die Anwendung suchen, wenn sie nicht vorgegeben ist. Eine kurze Liste
# bekannter Orte - kein Durchsuchen der ganzen Platte, das dauert Minuten.
if (-not $Anwendung) {
    foreach ($k in @(
        'C:\Program Files (x86)\HSETU\iSFP2\MeinSanierungsfahrplan.exe',
        'C:\Program Files\HSETU\iSFP2\MeinSanierungsfahrplan.exe',
        'C:\HSETU\iSFP2\MeinSanierungsfahrplan.exe'
    )) { if (Test-Path -LiteralPath $k) { $Anwendung = $k; break } }
}
if (-not $Anwendung -or -not (Test-Path -LiteralPath $Anwendung)) {
    throw 'MeinSanierungsfahrplan.exe wurde auf diesem Rechner nicht gefunden. Pfad mit -Anwendung angeben.'
}

# Ergebnis wird in JEDEM Fall geschrieben - auch beim Abbruch. Ein Auftrag ohne
# Ergebnisdatei laesst sich sonst nicht von einem unterscheiden, der den
# Rechner nie erreicht hat.
$ergebnisDatei = Join-Path $Ziel 'druck.json'
function SchreibeErgebnis([hashtable] $daten) {
    $json = ([ordered]@{
        zustand = $daten.zustand
        projekt = $daten.projekt
        anwendung = $Anwendung
        vorschau = [bool]$Vorschau
        exitcode = $daten.exitcode
        dauer_s = $daten.dauer
        dateien = @($daten.dateien)
        protokoll = $daten.protokoll
        meldung = $daten.meldung
    }) | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($ergebnisDatei, $json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Ergebnis: $ergebnisDatei"
}

# --- Den Speicherstand der Maske holen

$cn = New-Object System.Data.SqlClient.SqlConnection $Verbindung
$cn.Open()
try {
    $cmd = $cn.CreateCommand()
    $cmd.CommandText = @'
SELECT TOP 1 p.LongDesc AS Projekt, m.Media, m.StampEdit
FROM PrMedia m JOIN PrProject p ON p.UUID = m.ProjectUUID
WHERE m.ProjectUUID = @u AND m.MediaName = 'iSFP2.xml' AND m.MediaType = 11
ORDER BY m.StampEdit DESC
'@
    $null = $cmd.Parameters.AddWithValue('@u', [guid]$projGuid)
    $rd = $cmd.ExecuteReader()
    if (-not $rd.Read()) {
        $rd.Close()
        throw 'Das Projekt hat keinen iSFP-Stand (PrMedia iSFP2.xml). Die iSFP-Maske muss einmal geoeffnet und gespeichert worden sein.'
    }
    $projektName = [string]$rd['Projekt']
    $roh = $rd['Media']
    $stand = $rd['StampEdit']
    $rd.Close()
} finally { $cn.Close() }

$eingabe = Join-Path $Ziel 'projekt.mSFPprojekt'
[System.IO.File]::WriteAllBytes($eingabe, $roh)
Write-Host "Projekt: $projektName"
Write-Host ("Stand:   {0}   {1} KB" -f $stand, [math]::Round($roh.Length / 1KB))
Write-Host "Anwendung: $Anwendung"

# --- Drucken

$sfp = Join-Path $Ziel 'isfp.pdf'
$uh = Join-Path $Ziel 'umsetzungshilfe.pdf'
$log = Join-Path $Ziel 'druck.log'
Remove-Item $sfp, $uh, $log -Force -ErrorAction SilentlyContinue

$argumente = @(
    '--infile', $eingabe,
    $(if ($Vorschau) { '--preview' } else { '--create-pdf' }),
    '--outfile-sfp', $sfp,
    '--outfile-uh', $uh,
    '--logfile', $log,
    # Auf einem Dienstkonto ohne Sitzung gibt es keinen Grafikkontext; ohne
    # diesen Schalter bleibt die Anwendung dort haengen.
    '--disable-gpu'
)
Write-Host ("Starte: {0} {1}" -f (Split-Path -Leaf $Anwendung), ($argumente -join ' '))

$t0 = Get-Date
$p = Start-Process -FilePath $Anwendung -ArgumentList $argumente -PassThru -WindowStyle Hidden
$p | Wait-Process -Timeout $Frist -ErrorAction SilentlyContinue

if (-not $p.HasExited) {
    try { $p.Kill() } catch { }
    SchreibeErgebnis @{ zustand = 'frist_abgelaufen'; projekt = $projektName; exitcode = $null
        dauer = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1); dateien = @()
        protokoll = $(if (Test-Path $log) { Get-Content $log -Raw } else { '' })
        meldung = "Die Druckanwendung lief laenger als $Frist Sekunden und wurde beendet." }
    throw "Die Druckanwendung lief laenger als $Frist Sekunden."
}

$dauer = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
$protokoll = $(if (Test-Path -LiteralPath $log) { (Get-Content -LiteralPath $log -Raw) } else { '' })
Write-Host ("Beendet nach {0} s, Exitcode {1}" -f $dauer, $p.ExitCode)

$dateien = @()
foreach ($paar in @(@($sfp, 'isfp-pdf'), @($uh, 'umsetzungshilfe-pdf'))) {
    if (-not (Test-Path -LiteralPath $paar[0])) { continue }
    $f = Get-Item -LiteralPath $paar[0]
    # Ein PDF, das kein PDF ist, waere eine abgebrochene Ausgabe - die soll
    # nicht als Erfolg hochgeladen werden.
    $kopf = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($f.FullName)[0..4])
    $dateien += [ordered]@{
        art = $paar[1]; pfad = $f.FullName; name = $f.Name
        bytes = $f.Length; gueltig = ($kopf -eq '%PDF-')
    }
    Write-Host ("  {0,-20} {1,8:N0} KB  {2}" -f $f.Name, ($f.Length / 1KB), $(if ($kopf -eq '%PDF-') { 'PDF' } else { 'KEIN PDF' }))
}

$gueltige = @($dateien | Where-Object { $_.gueltig })
$zustand = if ($p.ExitCode -ne 0) { 'fehlgeschlagen' }
           elseif ($gueltige.Count -eq 0) { 'ohne_ausgabe' }
           elseif ($gueltige.Count -lt 2) { 'unvollstaendig' }
           else { 'gedruckt' }

SchreibeErgebnis @{
    zustand = $zustand; projekt = $projektName; exitcode = $p.ExitCode; dauer = $dauer
    dateien = $dateien; protokoll = $protokoll
    meldung = $(switch ($zustand) {
        'gedruckt' { 'iSFP und Umsetzungshilfe sind erzeugt.' }
        'unvollstaendig' { 'Nur eine der beiden Ausgaben ist entstanden.' }
        'ohne_ausgabe' { 'Die Anwendung endete ohne Fehler, hat aber keine PDF erzeugt.' }
        default { 'Die Druckanwendung endete mit Exitcode ' + $p.ExitCode + '.' }
    })
}

if ($protokoll.Trim()) {
    Write-Host "`nProtokoll der Druckanwendung:"
    Write-Host $protokoll
} else {
    Write-Host "`nDie Druckanwendung hat nichts zu beanstanden (Protokoll leer)."
}

if ($zustand -ne 'gedruckt') { throw "Druck nicht vollstaendig: $zustand" }
