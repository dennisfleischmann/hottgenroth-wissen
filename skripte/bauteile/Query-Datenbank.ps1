# Query-Datenbank.ps1 -- eine LESENDE Abfrage an die Projektdatenbank
#
# WOZU
# Fast jeder belastbare Befund dieser Arbeit ist so entstanden: auszaehlen statt
# annehmen. wall_type hat drei Werte. u_valueDimGuid fehlt bei 43 von 84
# Innenwaenden. FloorCount zaehlt nur OG und DG. Die Raum-Behauptung fiel durch
# einen Vergleich von drei Zeitstempeln.
#
# Wer das nicht kann, kann nicht entdecken -- nur ausfuehren, was ihm jemand
# vorgekaut hat. Genau diese Ungleichheit erzeugt die Abweichung zwischen dem,
# was ein Mensch herausfindet, und dem, was ein Agent weiss.
#
# DREI SICHERUNGEN, UND DIE DRITTE IST DIE ENTSCHEIDENDE
#
#   1. Die Abfrage muss mit SELECT oder WITH beginnen.
#   2. Schreibende Schluesselwoerter werden als ganze Woerter abgewiesen.
#   3. ALLES LAEUFT IN EINER TRANSAKTION, DIE IMMER ZURUECKGEROLLT WIRD.
#
# Die ersten beiden sind Textpruefungen und damit grundsaetzlich umgehbar. Die
# dritte ist es nicht: was auch immer die Abfrage anrichtet, es wird verworfen.
# Auf eine Textpruefung allein wuerde ich eine Datenbank mit vierzig echten
# Kundenprojekten nicht setzen.
#
# Zeilen und Breite sind begrenzt -- eine Abfrage ohne WHERE soll das Gespraech
# nicht mit einer halben Datenbank fluten.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Abfrage,
    [int]$Zeilen = 100,
    [int]$Spaltenbreite = 60,
    [string]$Instanz = "(localdb)\HSETU",
    [string]$Datenbank = "HsetuPrjData"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data

# --- 1. Muss lesend beginnen ------------------------------------------------
$sauber = ($Abfrage -replace '(?s)/\*.*?\*/', ' ') -replace '(?m)--.*$', ' '
$sauber = $sauber.Trim()
if ($sauber -notmatch '^\s*(SELECT|WITH)\b') {
    throw "Nur lesende Abfragen. Sie muss mit SELECT oder WITH beginnen."
}

# --- 2. Keine schreibenden Schluesselwoerter --------------------------------
$verboten = @('INSERT','UPDATE','DELETE','DROP','ALTER','CREATE','TRUNCATE','MERGE',
              'EXEC','EXECUTE','GRANT','REVOKE','BACKUP','RESTORE','SHUTDOWN','RECONFIGURE')
foreach ($v in $verboten) {
    if ($sauber -match "(?i)\b$v\b") { throw "Das Schluesselwort '$v' ist in einer lesenden Abfrage nicht erlaubt." }
}

$con = New-Object System.Data.SqlClient.SqlConnection "Server=$Instanz;Database=$Datenbank;Integrated Security=true;TrustServerCertificate=true"
$con.Open()
$tx = $null
try {
    # --- 3. Die harte Sicherung: alles wird zurueckgerollt -------------------
    $tx = $con.BeginTransaction()

    $c = $con.CreateCommand()
    $c.Transaction = $tx
    $c.CommandTimeout = 120
    $c.CommandText = $Abfrage

    $tab = New-Object System.Data.DataTable
    [void](New-Object System.Data.SqlClient.SqlDataAdapter $c).Fill($tab)

    if ($tab.Rows.Count -eq 0) { Write-Output "(keine Zeilen)"; return }

    $spalten = @($tab.Columns | ForEach-Object { $_.ColumnName })
    function Kuerze($w) {
        if ($null -eq $w -or $w -is [DBNull]) { return '' }
        $s = [string]$w
        # Zeilenumbrueche wuerden die Tabelle zerreissen.
        $s = $s -replace '\r?\n', ' '
        if ($s.Length -gt $Spaltenbreite) { $s.Substring(0, $Spaltenbreite - 1) + '…' } else { $s }
    }

    $breiten = @{}
    foreach ($sp in $spalten) { $breiten[$sp] = $sp.Length }
    $zeigen = [Math]::Min($tab.Rows.Count, $Zeilen)
    for ($i = 0; $i -lt $zeigen; $i++) {
        foreach ($sp in $spalten) {
            $l = (Kuerze $tab.Rows[$i][$sp]).Length
            if ($l -gt $breiten[$sp]) { $breiten[$sp] = $l }
        }
    }

    Write-Output (($spalten | ForEach-Object { $_.PadRight($breiten[$_]) }) -join ' | ')
    Write-Output (($spalten | ForEach-Object { '-' * $breiten[$_] }) -join '-+-')
    for ($i = 0; $i -lt $zeigen; $i++) {
        Write-Output (($spalten | ForEach-Object { (Kuerze $tab.Rows[$i][$_]).PadRight($breiten[$_]) }) -join ' | ')
    }
    if ($tab.Rows.Count -gt $zeigen) {
        Write-Output ""
        Write-Output "... $($tab.Rows.Count) Zeilen insgesamt, $zeigen gezeigt. Grenze das Ergebnis ein oder erhoehe -Zeilen."
    } else {
        Write-Output ""
        Write-Output "$($tab.Rows.Count) Zeile(n)."
    }
}
finally {
    # Auch im Fehlerfall: nichts bleibt stehen.
    if ($tx) { try { $tx.Rollback() } catch {} }
    $con.Close()
}
