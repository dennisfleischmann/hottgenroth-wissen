---
name: energie-exe-verwaiste-instanz
description: "Das Schließen des Energieberater-Fensters beendet Energie.exe nicht zuverlässig — die verwaiste Instanz überschreibt jeden Schreibvorgang stillschweigend"
metadata:
  node_type: memory
  type: project
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-17T20:34:45.849Z
---

`Energie.exe` läuft nach dem Schließen des Fensters häufig weiter: **kein Fenstertitel,
`MainWindowHandle 0`**, mehrere hundert MB im Speicher, `Responding = True`. Der Nutzer
sieht nichts und meldet in gutem Glauben „ist geschlossen".

**Why:** Die Instanz hält den Container aus `PrMedia` im Speicher und schreibt ihn beim
nächsten Speichern zurück — **jede Änderung von außen ist dann still weg**, ohne
Fehlermeldung. In dieser Sitzung zweimal aufgetreten, einmal lief die Instanz
**34 Stunden**. Beide Male habe ich zuerst den eigenen Code verdächtigt und Zeit
verloren.

**Der Prozess heißt nicht immer `Energie`** — Nachtrag 17.08.2026: der EE-Berater
läuft als **`EEBerater`** (Fenstertitel „EE-Berater Wohnen"). Eine Prüfung nur auf
`Energie` lässt ihn durch und meldet fälschlich „gefahrlos"; genau so sind drei
Schreibvorgänge gegen eine seit 90 Minuten offene Anwendung gelaufen. Nicht
dazugehören `HsetuServices` und `Hsetu.Update.Check` — Hintergrunddienste ohne
Projektmodell, die dauerhaft laufen.

**How to apply:** Vor **jedem** Schreiben prüfen und abbrechen statt schreiben.
Fertig dafür ist `bauteile/tools/Test-SoftwareLaeuft.ps1` (`Assert-SoftwareZu`);
es deckt `Energie`, `EEBerater`, `HottCAD`, `Hsetu.Shell`, `Hsetu.Desktop`,
`HottTherm`, `Hsetu.Assistant` ab. Von Hand:

```powershell
$p = Get-Process | Where-Object { $_.ProcessName -match '^(Energie|EEBerater|HottCAD|Hsetu\.Shell|Hsetu\.Desktop|HottTherm|Hsetu\.Assistant)' }
if ($p) { throw "Anwendung offen: $($p.ProcessName -join ', ')" }
```

Läuft sie, `MainWindowHandle` und `StartTime` ansehen — ist das Handle 0, ist es eine
verwaiste Instanz und kann nach Rückfrage beendet werden (der Nutzer hat dem zweimal
zugestimmt).

**Zweite Absicherung, unabhängig davon:** vor dem `UPDATE` prüfen, ob `DATALENGTH(Media)`
noch dem Stand entspricht, aus dem gebaut wurde — sonst hat die Software zwischendurch
gespeichert und der eigene Stand würde ihre Arbeit überschreiben. Beides zusammen
verhindert den Datenverlust, den der Prozesscheck allein nicht abdeckt.

Gehört zu [[energieberater-sanierungsvarianten]].
