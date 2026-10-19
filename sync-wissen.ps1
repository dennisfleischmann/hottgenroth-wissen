<#
.SYNOPSIS
  Gleicht wissen/ mit dem lokalen Claude-Code-Gedächtnis ab.

.DESCRIPTION
  Claude Code hält sein Projektgedächtnis unter
  ~/.claude/projects/<projektkennung>/memory/. Die Kennung ist der Pfad des
  Arbeitsverzeichnisses mit '-' statt ':' und '\' (z. B. c--Projekte-Dev-energieberatung).

  -Richtung Import   wissen/*.md  →  lokales Memory   (neuer Rechner, Sitzung beginnt)
  -Richtung Export   lokales Memory  →  wissen/       (Sitzung endet, vor dem Commit)

  Es werden nur Dateien überschrieben, die jünger sind als das Ziel. MEMORY.md
  wird beim Export nicht blind überschrieben, sondern um fehlende Zeilen ergänzt,
  damit Einträge anderer Projekte im lokalen Index erhalten bleiben.

.PARAMETER Projektpfad
  Arbeitsverzeichnis, dessen Memory gemeint ist. Standard: dieses Repo.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Import','Export')][string]$Richtung,
    [string]$Projektpfad = $PSScriptRoot
)

$kennung = ($Projektpfad -replace '[:\\/]', '-')
$memory  = Join-Path $env:USERPROFILE ".claude\projects\$kennung\memory"
$wissen  = Join-Path $PSScriptRoot 'wissen'

if ($Richtung -eq 'Import') { $von = $wissen; $nach = $memory } else { $von = $memory; $nach = $wissen }
New-Item -ItemType Directory -Force $nach | Out-Null
Write-Host "$Richtung`: $von  →  $nach"

$n = 0
Get-ChildItem (Join-Path $von '*.md') | Where-Object Name -ne 'MEMORY.md' | ForEach-Object {
    $ziel = Join-Path $nach $_.Name
    if (-not (Test-Path $ziel) -or $_.LastWriteTime -gt (Get-Item $ziel).LastWriteTime) {
        Copy-Item $_.FullName $ziel -Force; $n++
    }
}
Write-Host "$n Einträge übertragen."

# Index zusammenführen: fehlende Zeilen anhängen, nichts löschen
$quellIndex = Join-Path $von 'MEMORY.md'
$zielIndex  = Join-Path $nach 'MEMORY.md'
if (Test-Path $quellIndex) {
    $vorhanden = if (Test-Path $zielIndex) { Get-Content $zielIndex -Encoding UTF8 } else { @('# Index','') }
    $neu = Get-Content $quellIndex -Encoding UTF8 | Where-Object { $_ -match '^\- \[' -and $vorhanden -notcontains $_ }
    if ($neu) {
        ($vorhanden + $neu) | Set-Content $zielIndex -Encoding UTF8
        Write-Host "$($neu.Count) Indexzeilen ergänzt."
    }
}
