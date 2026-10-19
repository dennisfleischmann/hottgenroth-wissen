# Test-SoftwareLaeuft.ps1 — prueft, ob eine Hottgenroth-Anwendung das Projekt haelt
#
# WARUM ES DAS GIBT
# Eine laufende Anwendung haelt das Projekt als Objektmodell im Speicher und
# serialisiert es beim Beenden zurueck. Alles, was von aussen in die Datenbank
# geschrieben wurde, ist danach fort — ohne Fehlermeldung, ohne Hinweis.
#
# Der Prozessname ist NICHT verlaesslich "Energie". Gemessen am 17.08.2026:
# der EE-Berater laeuft als "EEBerater" (Fenstertitel "EE-Berater Wohnen").
# Eine Pruefung, die nur nach "Energie" sucht, laesst ihn durch — und meldet
# faelschlich, das Schreiben sei gefahrlos. Genau das ist passiert: drei
# Schreibvorgaenge liefen gegen eine offene Anwendung, weil die Pruefung
# zu eng war.
#
# Deshalb hier eine Liste, die auf Verdacht breit ist. Falsch-positiv kostet
# eine Rueckfrage; falsch-negativ kostet die Arbeit.

# Anwendungen, die ein Projekt halten. HsetuServices und Hsetu.Update.Check
# gehoeren NICHT dazu — das sind Hintergrunddienste ohne Projektmodell.
$script:HottgenrothAnwendungen = @(
    'Energie'        # Energie.exe (Energieberater-Hauptprozess)
    'Energieberater' # "Energieberater Wohnen & Gewerbe" -- lief bisher nur
                     # zufaellig unter das Praefix 'Energie'; explizit gelistet,
                     # damit eine spaetere Verschaerfung des Musters auf exakte
                     # Namen ihn nicht verliert (gesehen 14.10.2026, PID 21468)
    'EEBerater'      # EE-Berater
    'HottCAD'        # HottCAD einzeln
    'Hsetu.Shell'
    'Hsetu.Desktop'
    'HottTherm'      # Waermebrueckenrechner
    'Hsetu.Assistant'
)

function Get-HottgenrothAnwendungen {
    $muster = '^(' + (($script:HottgenrothAnwendungen | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')'
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match $muster })
}

function Assert-SoftwareZu {
    param(
        # Bei einem Probelauf darf die Software laufen — es wird nichts geschrieben.
        [switch]$Erlaubt
    )
    $offen = Get-HottgenrothAnwendungen
    if ($offen.Count -eq 0) { return }

    $liste = ($offen | ForEach-Object {
            $titel = if ($_.MainWindowTitle) { " — `"$($_.MainWindowTitle)`"" } else { "" }
            "$($_.ProcessName) (PID $($_.Id), seit $($_.StartTime.ToString('HH:mm:ss')))$titel"
        }) -join "`n  "

    if ($Erlaubt) {
        Write-Warning "Anwendung laeuft, der Probelauf schreibt aber nichts:`n  $liste"
        return
    }
    throw "Eine Hottgenroth-Anwendung ist offen und haelt das Projekt:`n  $liste`n`nSie schreibt ihr Modell beim Beenden zurueck und wuerde jede Aenderung von aussen still verwerfen. Erst schliessen, dann erneut ausfuehren."
}
