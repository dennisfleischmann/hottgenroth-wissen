<#
    Arbeitet einen Teil der Auftragsliste ab. Gestartet von dekompiliere-alles.ps1,
    mehrfach parallel: jeder Arbeiter nimmt die Zeilen, deren Nummer modulo der
    Arbeiterzahl seiner Nummer entspricht. Keine Absprache noetig, weil die
    Zieldateien im Plan schon feststehen.

    Geschrieben wird erst in eine .teil-Datei und dann umbenannt. Ein
    abgebrochener Lauf hinterlaesst so keine halbe Datei, die der naechste Lauf
    faelschlich fuer erledigt haelt.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Auftrag,
    [Parameter(Mandatory)] [string] $Ziel,
    [Parameter(Mandatory)] [int]    $Teil,
    [Parameter(Mandatory)] [int]    $Von,
    [int] $FristSekunden = 900
)

$ErrorActionPreference = 'Continue'

$log = Join-Path $Ziel ("fortschritt-teil{0}.log" -f $Teil)

function Schreibe([string] $text) {
    Add-Content -LiteralPath $log -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $text) -Encoding utf8
}

$alle = @(Import-Csv -LiteralPath $Auftrag)
$meine = @(for ($i = 0; $i -lt $alle.Count; $i++) { if (($i % $Von) -eq $Teil) { $alle[$i] } })

Schreibe "Arbeiter $Teil von ${Von}: $($meine.Count) Assemblies"

$fehler = 0
$nr = 0

foreach ($a in $meine) {
    $nr++

    if ((Test-Path -LiteralPath $a.ZielDatei) -and (Get-Item -LiteralPath $a.ZielDatei).Length -gt 0) { continue }

    $vorlaeufig = $a.ZielDatei + '.teil'
    $fehlerdatei = $a.ZielDatei + '.err'

    try {
        $p = Start-Process -FilePath 'ilspycmd' -PassThru -NoNewWindow `
            -ArgumentList @("`"$($a.Quelle)`"") `
            -RedirectStandardOutput $vorlaeufig -RedirectStandardError $fehlerdatei

        if (-not $p.WaitForExit($FristSekunden * 1000)) {
            try { $p.Kill() } catch { }
            $fehler++
            Schreibe ("[{0}/{1}] {2} -> ABBRUCH nach {3}s" -f $nr, $meine.Count, $a.Name, $FristSekunden)
            continue
        }

        $groesse = if (Test-Path -LiteralPath $vorlaeufig) { (Get-Item -LiteralPath $vorlaeufig).Length } else { 0 }

        if ($groesse -gt 0) {
            Move-Item -LiteralPath $vorlaeufig -Destination $a.ZielDatei -Force
            Remove-Item -LiteralPath $fehlerdatei -ErrorAction SilentlyContinue
            Schreibe ("[{0}/{1}] {2} -> {3:N0} KB" -f $nr, $meine.Count, $a.Name, ($groesse / 1KB))
        } else {
            $fehler++
            $grund = ''
            if (Test-Path -LiteralPath $fehlerdatei) {
                $grund = (Get-Content -LiteralPath $fehlerdatei -TotalCount 3) -join ' / '
            }
            Schreibe ("[{0}/{1}] {2} -> LEER (Code {3}) {4}" -f $nr, $meine.Count, $a.Name, $p.ExitCode, $grund)
            Remove-Item -LiteralPath $vorlaeufig -ErrorAction SilentlyContinue
        }
    } catch {
        $fehler++
        Schreibe ("[{0}/{1}] {2} -> FEHLER: {3}" -f $nr, $meine.Count, $a.Name, $_.Exception.Message)
        Remove-Item -LiteralPath $vorlaeufig -ErrorAction SilentlyContinue
    }
}

Schreibe "Arbeiter $Teil fertig. $($meine.Count) bearbeitet, $fehler ohne Ergebnis."
