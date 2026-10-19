---
name: hottgenroth-update-download-cli
description: "Hsetu.Update.Download.exe hat eine stille CLI (/qn) - alle neuesten Versionen laden und ohne Benutzerinteraktion installieren; Mutex-Code 14, UAC im InstallWorker"
metadata:
  node_type: memory
  type: reference
  originSessionId: 9cb8c979-3728-4199-b87b-cf3460d0e250
  modified: 2026-10-13T00:03:38.515Z
---

Der Hottgenroth-Updater `C:\Program Files\HSETU\Updater\Hsetu.Update.Download.exe`
(Logik in der gleichnamigen **DLL**, nicht der exe - Stringsuche in der exe findet nichts)
kann headless betrieben werden:

- `/qn` oder `/quietInstall` — Updateliste von Hottgenroth holen, alle neuesten
  Versionen auswählen, nacheinander herunterladen und still installieren
  (`QuietInstallManager.RunQuiet` im [[hsetu-dekompilierter-korpus]]).
- `/includeEditions:<guid> ...` / `/excludeEditions:<guid> ...` — Filter auf Edition-GUIDs.
- `/exportEditionsTo:"pfad.json"` — nur die Liste der verfügbaren Editionen schreiben
  (gute gefahrlose Wirkungsprobe).
- `/downloadSetupsTo:"pfad"` — nur herunterladen, `/clearTempDownloadFolder` davor möglich.

**Fallen:**
- Läuft die App schon (offenes Fenster), hält sie den Mutex
  `HSETU_UPDATE_DOWNLOAD_RUNNING`; jeder weitere Start endet sofort mit
  Exit-Code 536870926 (= strukturiert, App-Fehler 14 „läuft bereits"). Nie den
  laufenden Prozess abschießen — der InstallWorker kann mitten in einer
  Installation stecken.
- Installiert wird durch `Hsetu.Update.Download.InstallWorker.exe`, der sich
  selbst per UAC erhöht (requireAdministrator-Neustart). Ohne Adminrechte und
  sichtbaren Desktop bricht er mit Fehlercode ab.
- Protokolle: `%LOCALAPPDATA%\HSETU\UpdateDownload`.

**Why:** Der fs-app-Auftrag `hottgenroth.update-install` (Knopf „Alle neuesten
Versionen installieren" auf /admin/hottgenroth/updates) fährt genau diesen Weg;
ein Spiegel-basierter msiexec-Ansatz wurde verworfen, weil der Spiegel nie neuer
sein kann als der Arbeitsplatz, der ihn füllt.

**How to apply:** Für stille Updates immer den Updater mit `/qn` starten statt
MSIs selbst zu installieren; vorher auf laufende Instanz prüfen.
