<#
    Erhebt je Modul einen Steckbrief - die Grundlage fuer den Modulkatalog.

    Bewusst zweigleisig, damit der Lauf Minuten und nicht Stunden dauert:

      * Aus der .cs-Datei nur der KOPF (Attribute und using-Zeilen). Was ein
        Modul ueber sich selbst sagt und worauf es aufbaut, steht dort - der
        Rest der Datei, oft zweistellige Megabyte, wird nicht angefasst.

      * Alles Gezaehlte aus api-typen.csv / api-mitglieder.csv. Die liegen schon
        vor (werkzeuge\lies-api.ps1); sie noch einmal aus dem Quelltext zu
        gewinnen waere dieselbe Arbeit zum zweiten Mal.

    Die Abhaengigkeiten sind der eigentliche Ertrag: welches Modul auf welchem
    aufbaut, laesst sich sonst nur erraten. Aus ihnen ergibt sich die
    Schichtung - Modell unten, Rahmenwerk darueber, Oberflaeche oben.

    Ergebnis:
      steckbriefe.csv    eine Zeile je Modul, fuer Auswertung und Sortierung
      steckbriefe.txt    dasselbe lesbar, als Nachschlagewerk beim Schreiben
#>
[CmdletBinding()]
param(
    [string] $Quelle = 'C:\Projekte_Dev\hsetu-decompiled\eigen',
    [string] $Ziel   = 'C:\Projekte_Dev\hsetu-decompiled',
    [string] $Marke  = ''
)

$ErrorActionPreference = 'Stop'

$anhang = if ($Marke -ne '') { "-$Marke" } else { '' }

Write-Host 'Lade Schnittstellenindex ...'

$typen = Import-Csv (Join-Path $Ziel "api-typen$anhang.csv")
$mitglieder = Import-Csv (Join-Path $Ziel "api-mitglieder$anhang.csv")

# Von Hand gruppiert statt mit Group-Object.
#
# Group-Object mit Skriptblock ueber 350.000 Zeilen laeuft in dieser
# PowerShell-Fassung minutenlang, ohne fertig zu werden - es vergleicht je
# Eintrag gegen alle bisherigen Gruppen. Eine Hashtabelle tut dasselbe in
# Sekunden. Von den Mitgliedern je Typ wird ohnehin nur die Anzahl gebraucht,
# also gar nicht erst die Objekte sammeln.
Write-Host "  $($typen.Count) Typen, $($mitglieder.Count) Mitglieder - gruppiere ..."

$typenJeModul = @{}
foreach ($t in $typen) {
    if (-not $typenJeModul.ContainsKey($t.Modul)) {
        $typenJeModul[$t.Modul] = New-Object System.Collections.ArrayList
    }
    [void] $typenJeModul[$t.Modul].Add($t)
}

$mitgliederJeModul = @{}
$mitgliederJeTyp = @{}
foreach ($m in $mitglieder) {
    # Kein ?? - Windows PowerShell 5.1 kennt den Operator nicht. Und das else
    # bleibt in derselben Zeile: nach einem einzeiligen if-Block ist die
    # Anweisung fuer den Parser sonst beendet, und das else steht allein da.
    if ($mitgliederJeModul.ContainsKey($m.Modul)) { $mitgliederJeModul[$m.Modul]++ } else { $mitgliederJeModul[$m.Modul] = 1 }

    $schluessel = $m.Modul + '|' + $m.Typ
    if ($mitgliederJeTyp.ContainsKey($schluessel)) { $mitgliederJeTyp[$schluessel]++ } else { $mitgliederJeTyp[$schluessel] = 1 }
}

$dateien = @(Get-ChildItem -LiteralPath $Quelle -Filter *.cs -File | Where-Object { $_.Name -notmatch '~' } | Sort-Object Name)

Write-Host "$($dateien.Count) Module"

# Bekannte Fremdrahmen, aus denen sich die Schicht ablesen laesst.
$rahmen = [ordered]@{
    'WPF/Oberflaeche' = @('System.Windows', 'System.Windows.Controls', 'System.Windows.Media')
    'Prism'           = @('Prism.', 'Microsoft.Practices')
    'DevExpress'      = @('DevExpress.')
    'Datenbank'       = @('System.Data', 'System.Data.SqlClient', 'Microsoft.Data.SqlClient')
    'Serialisierung'  = @('System.Xml', 'Newtonsoft.Json', 'System.Runtime.Serialization')
    'Web'             = @('System.Net.Http', 'System.ServiceModel', 'RestSharp')
}

$steckbriefe = New-Object System.Collections.ArrayList
$n = 0

foreach ($d in $dateien) {
    $n++
    if ($n % 100 -eq 0) { Write-Host "  $n/$($dateien.Count) ..." }

    $modul = $d.BaseName

    # Kopf lesen: alles bis zum ersten namespace. Danach beginnt der Rumpf,
    # und der ist hier ohne Belang.
    $kopf = New-Object System.Collections.ArrayList
    foreach ($z in [System.IO.File]::ReadLines($d.FullName)) {
        if ($z.StartsWith('namespace ')) { break }
        [void] $kopf.Add($z)
        if ($kopf.Count -gt 400) { break }
    }

    $text = $kopf -join "`n"

    $wert = {
        param($muster)
        $t = [regex]::Match($text, $muster)
        if ($t.Success) { $t.Groups[1].Value.Trim() } else { '' }
    }

    $beschreibung = & $wert 'AssemblyDescription\("([^"]*)"\)'
    $produkt      = & $wert 'AssemblyProduct\("([^"]*)"\)'
    $version      = & $wert 'AssemblyFileVersion\("([^"]*)"\)'
    if ($version -eq '') { $version = & $wert 'AssemblyVersion\("([^"]*)"\)' }
    $framework    = & $wert 'TargetFramework\("([^"]*)"\)'

    # using-Zeilen: eigene Abhaengigkeiten und Fremdrahmen getrennt.
    $usings = @($kopf | Where-Object { $_.StartsWith('using ') -and -not $_.Contains('=') } |
        ForEach-Object { $_.Substring(6).TrimEnd(';').Trim() })

    $eigene = @($usings | Where-Object { $_ -match '^(Hsetu|Hstac|Hott|HSETU)' } | Sort-Object -Unique)

    # Namensraum auf Modul abbilden: der laengste Modulname, der Praefix des
    # Namensraums ist. 'Hsetu.Model.Dal.Bim.Ado' gehoert damit zu genau einem
    # Modul und nicht zu jedem, dessen Name zufaellig passt.
    $modulnamen = $dateien.BaseName

    $abhaengig = New-Object System.Collections.ArrayList
    foreach ($ns in $eigene) {
        $treffer = $modulnamen | Where-Object { $ns -eq $_ -or $ns.StartsWith($_ + '.') } |
            Sort-Object Length -Descending | Select-Object -First 1
        if ($treffer -and $treffer -ne $modul -and -not $abhaengig.Contains($treffer)) {
            [void] $abhaengig.Add($treffer)
        }
    }

    $gefunden = New-Object System.Collections.ArrayList
    foreach ($name in $rahmen.Keys) {
        foreach ($praefix in $rahmen[$name]) {
            if ($usings | Where-Object { $_.StartsWith($praefix) }) {
                if (-not $gefunden.Contains($name)) { [void] $gefunden.Add($name) }
                break
            }
        }
    }

    $meineTypen = $typenJeModul[$modul]
    $anzahlMitglieder = if ($mitgliederJeModul.ContainsKey($modul)) { $mitgliederJeModul[$modul] } else { 0 }

    $namensraeume = @($meineTypen | Select-Object -ExpandProperty Namensraum -Unique | Sort-Object)

    # Die groessten Typen - sie tragen den Zweck des Moduls am deutlichsten.
    $gross = @($meineTypen | ForEach-Object {
        $s = $modul + '|' + $_.Typ
        [pscustomobject]@{
            Typ = $_.Typ
            Art = $_.Art
            Anzahl = if ($mitgliederJeTyp.ContainsKey($s)) { $mitgliederJeTyp[$s] } else { 0 }
        }
    } | Sort-Object Anzahl -Descending | Select-Object -First 8)

    [void] $steckbriefe.Add([pscustomobject]@{
        Modul         = $modul
        Familie       = ($modul -split '\.')[0..1] -join '.'
        Version       = $version
        Framework     = $framework
        Beschreibung  = $beschreibung
        Produkt       = $produkt
        Groesse_KB    = [math]::Round($d.Length / 1KB)
        Namensraeume  = $namensraeume.Count
        NsListe       = ($namensraeume -join ';')
        Typen         = if ($meineTypen) { $meineTypen.Count } else { 0 }
        Mitglieder    = $anzahlMitglieder
        Klassen       = @($meineTypen | Where-Object Art -eq 'class').Count
        Schnittstellen= @($meineTypen | Where-Object Art -eq 'interface').Count
        Enums         = @($meineTypen | Where-Object Art -eq 'enum').Count
        Baut_auf      = ($abhaengig -join ';')
        Baut_auf_n    = $abhaengig.Count
        Rahmen        = ($gefunden -join ';')
        Grosse_Typen  = (($gross | ForEach-Object { "$($_.Typ) ($($_.Anzahl))" }) -join '; ')
    })
}

$steckbriefe | Export-Csv (Join-Path $Ziel "steckbriefe$anhang.csv") -NoTypeInformation -Encoding utf8

# Lesbare Fassung - beim Schreiben des Katalogs schlaegt man hierin nach.
$zeilen = New-Object System.Collections.ArrayList

foreach ($s in ($steckbriefe | Sort-Object Familie, Modul)) {
    [void] $zeilen.Add("=== $($s.Modul)  [$($s.Version)]  $($s.Groesse_KB) KB")
    if ($s.Beschreibung) { [void] $zeilen.Add("    Selbstauskunft: $($s.Beschreibung)") }
    [void] $zeilen.Add("    $($s.Typen) Typen ($($s.Klassen) Klassen, $($s.Schnittstellen) Schnittstellen, $($s.Enums) Enums), $($s.Mitglieder) Mitglieder")
    [void] $zeilen.Add("    Namensraeume: $($s.NsListe)")
    if ($s.Baut_auf) { [void] $zeilen.Add("    Baut auf: $($s.Baut_auf)") }
    if ($s.Rahmen)   { [void] $zeilen.Add("    Rahmen: $($s.Rahmen)") }
    [void] $zeilen.Add("    Grosse Typen: $($s.Grosse_Typen)")
    [void] $zeilen.Add('')
}

Set-Content -LiteralPath (Join-Path $Ziel "steckbriefe$anhang.txt") -Value $zeilen -Encoding utf8

Write-Host ''
Write-Host ("$($steckbriefe.Count) Steckbriefe, davon {0} mit eigener Beschreibung" -f @($steckbriefe | Where-Object Beschreibung).Count)
Write-Host 'Meistgenutzte Module (worauf am haeufigsten aufgebaut wird):'
$steckbriefe | ForEach-Object { $_.Baut_auf -split ';' } | Where-Object { $_ } |
    Group-Object | Sort-Object Count -Descending | Select-Object -First 15 |
    ForEach-Object { "  {0,4}x  {1}" -f $_.Count, $_.Name }
