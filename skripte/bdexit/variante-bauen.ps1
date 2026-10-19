# Legt in eberater.zip eine neue Sanierungsvariante an, abgeleitet aus einer
# vorhandenen (oder aus dem Ist-Zustand).
#
# EINE Regel deckt alle Tabellen ab. Je Tabelle gilt:
#
#   Bezug      das Feld, das auf das Projekt zeigt:
#              heisst es PROJ_ID oder ProjektID -> dieses Feld,
#              sonst ist das ERSTE Feld selbst die Projektnummer.
#   Schluessel ist der Bezug nicht das erste Feld, dann ist das erste Feld ein
#              eigener fortlaufender Schluessel (HUELL_ID, StrangId) und muss
#              beim Klonen neu vergeben werden.
#
#   TableProjekt … TableZusatz   Bezug = erstes Feld (PROJEKT_ID, ANLAGE_ID …)
#   TableHuellfl                 Bezug = PROJ_ID,    Schluessel = HUELL_ID
#   TableHeizung, TableWasser    Bezug = ProjektID,  Schluessel = StrangId
#
# Diese beiden waren im ersten untersuchten Projekt leer und fehlten deshalb in
# der ersten Fassung. In 20260626_HottCAD_82024 tragen sie je einen Satz pro
# Variante - eine Variante ohne sie waere unvollstaendig, so wie eine ohne
# TableHausDat als Nichtwohngebaeude gilt.
#
# Ebenfalls nicht vorausgesetzt: dass die Projektnummern fortlaufen. Im zweiten
# Projekt sind es 2, 4, 5, 6, 7, 8 - ohne 3.

param(
    [Parameter(Mandatory)] [string] $Ordner,          # entpackter Container
    [Parameter(Mandatory)] [int]    $VonProj,         # Vorlage
    [int]    $NeuProj = 0,                            # 0 = naechste freie Nummer
    [Parameter(Mandatory)] [string] $Name,
    [switch] $Vorschau
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bde.ps1')
. (Join-Path $PSScriptRoot 'satz.ps1')

function Tabelle([string] $Datei) {
    $b = [System.IO.File]::ReadAllBytes($Datei)
    $k = BdeKopf $b
    $s = @(); $o = $k.Daten
    while ($o -lt $b.Length) { $r = BdeLies $b $k $o -1; $s += $r; $o = $r.Ende }
    if ($s.Count -ne $k.Satzzahl) { throw "$(Split-Path $Datei -Leaf): $($s.Count) Saetze gelesen, Kopf sagt $($k.Satzzahl)" }

    # Bezug und eigener Schluessel herleiten, nicht raten.
    # Ohne das [string] liefert die Kette ein Feld statt einer Zeichenkette,
    # und der Bezug landet als "System.Object[]" im Hashtabellen-Schluessel.
    $bezug = [string] ($k.Felder | Where-Object { $_.Name -eq 'PROJ_ID' -or $_.Name -eq 'ProjektID' } |
               ForEach-Object { $_.Name } | Select-Object -First 1)
    if (-not $bezug) { $bezug = [string] $k.Felder[0].Name }
    $schluessel = if ($bezug -ne $k.Felder[0].Name) { $k.Felder[0].Name } else { $null }

    [pscustomobject]@{ Bytes=$b; Kopf=$k; Saetze=$s; Datei=$Datei
                       Bezug=$bezug; Schluessel=$schluessel }
}
function Wert($r, $n) { ($r.Werte | Where-Object Name -eq $n).Wert }

$tabellen = @{}
foreach ($f in Get-ChildItem $Ordner -Filter *.BDExit) { $tabellen[$f.BaseName] = Tabelle $f.FullName }

# Freie Projektnummer aus TableProjekt, nicht aus VonProj+1 - die Nummern
# koennen Luecken haben.
$tp = $tabellen['TableProjekt']
$nummern = @($tp.Saetze | ForEach-Object { Wert $_ $tp.Bezug })
if ($NeuProj -le 0) { $NeuProj = ($nummern | Measure-Object -Maximum).Maximum + 1 }
if ($nummern -contains $NeuProj) { throw "Projektnummer $NeuProj ist bereits vergeben ($($nummern -join ', '))" }
if (-not ($nummern -contains $VonProj)) { throw "Vorlage $VonProj gibt es nicht ($($nummern -join ', '))" }

"Vorlage {0} -> neue Variante {1} '{2}'   vorhandene Nummern: {3}" -f $VonProj, $NeuProj, $Name, ($nummern -join ', ')
""
"Tabelle           Bezug         Schluessel    Vorlage  neu"

foreach ($n in ($tabellen.Keys | Sort-Object)) {
    $t = $tabellen[$n]
    $quelle = @($t.Saetze | Where-Object { (Wert $_ $t.Bezug) -eq $VonProj })
    if (-not $quelle) {
        "{0,-16} {1,-13} {2,-13} {3,7}  {4}" -f $n, $t.Bezug, $(if($t.Schluessel){$t.Schluessel}else{'-'}), 0, 'nichts zu klonen'
        continue
    }

    # neuer Schluesselbereich, falls die Tabelle einen eigenen fuehrt
    $maxK = 0
    if ($t.Schluessel) { $maxK = ($t.Saetze | ForEach-Object { Wert $_ $t.Schluessel } | Measure-Object -Maximum).Maximum }

    $strom = New-Object System.Collections.Generic.List[byte]
    foreach ($s in $t.Saetze) { $strom.AddRange([byte[]] (BdeSchreib $t.Bytes $t.Kopf $s @{})) }

    $i = 0
    foreach ($q in $quelle) {
        $setze = @{ $t.Bezug = $NeuProj }
        if ($t.Schluessel) { $setze[$t.Schluessel] = $maxK + 1 + $i }
        if ($n -eq 'TableProjekt') {
            $setze['PROJEKT_NR']  = ($t.Saetze | ForEach-Object { Wert $_ 'PROJEKT_NR' } | Measure-Object -Maximum).Maximum + 1
            # VarianteID ist KEIN Zaehler, sondern der Verweis auf den Ist-Zustand:
            # in 20260626_HottCAD_82024 und CCKZL_Messinger tragen ALLE Varianten die 2,
            # also die PROJEKT_ID des Ist-Zustands. Ein Hochzaehlen laesst die Software
            # 'Ist-Zustand nicht vorhanden!' melden und den Variantenwaehler leer bleiben.
            # Vorlage ist der Ist-Zustand (kein VarianteID) -> VonProj, sonst deren Wert erben.
            $vid = Wert $q 'VarianteID'
            $setze['VarianteID']  = if ($vid) { $vid } else { $VonProj }
            $setze['VarianteBez'] = $Name
        }
        $strom.AddRange([byte[]] (BdeSchreib $t.Bytes $t.Kopf $q $setze))
        $i++
    }

    $kopf = New-Object byte[] $t.Kopf.Daten
    [Array]::Copy($t.Bytes, 0, $kopf, 0, $t.Kopf.Daten)
    [BitConverter]::GetBytes([uint16]($t.Kopf.Satzzahl + $quelle.Count)).CopyTo($kopf, 14)
    if ($t.Kopf.AutoPos -ge 0) {
        $auto = if ($t.Schluessel) { $maxK + $quelle.Count + 1 } else { $NeuProj + 1 }
        [BitConverter]::GetBytes([int] $auto).CopyTo($kopf, $t.Kopf.AutoPos)
    }
    if (-not $Vorschau) { [System.IO.File]::WriteAllBytes($t.Datei, ($kopf + $strom.ToArray())) }

    "{0,-16} {1,-13} {2,-13} {3,7}  {4}" -f $n, $t.Bezug, $(if($t.Schluessel){"$($t.Schluessel) ab $($maxK+1)"}else{'-'}), $quelle.Count, "$($quelle.Count) Saetze"
}

if ($Vorschau) { ""; "Vorschau - nichts geschrieben"; return }

""
"Gegenprobe:"
foreach ($f in Get-ChildItem $Ordner -Filter *.BDExit | Sort-Object Name) {
    $t = Tabelle $f.FullName
    $n = @($t.Saetze | Where-Object { (Wert $_ $t.Bezug) -eq $NeuProj }).Count
    "  {0,-16} {1,8} B  {2,4} Saetze, davon {3} neu  vollstaendig lesbar" -f $f.BaseName, $t.Bytes.Length, $t.Saetze.Count, $n
}
