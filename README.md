# hottgenroth-wissen

Gesammeltes Wissen und Werkzeuge für die Fernsteuerung der Hottgenroth-
Energieberatersoftware (Energieberater 18599, HottCAD, iSFP) durch Claude Code.
Stand: 19.10.2026, zusammengetragen aus dem Hauptrepo `energieberatung`, dem
iSFP-Assistenten und den eigenen Werkzeugen am dekompilierten HSETU-Korpus.

**Einstieg für Menschen:** `doku/regeln-hottgenroth-arbeitsplatz.md` (die
Geschäftsregeln) und `doku/ki-hottgenroth.md` (das Werkzeughandbuch).
**Einstieg für Claude Code:** `CLAUDE.md`, dann `wissen/MEMORY.md`.

## Auf einem neuen Rechner

```powershell
git clone https://github.com/dennisfleischmann/hottgenroth-agent.git hottgenroth-wissen
cd hottgenroth-wissen
.\sync-wissen.ps1 -Richtung Import     # Gedächtnis in das lokale Claude-Code-Memory spiegeln
claude                                 # Claude Code im Repo starten
```

Voraussetzungen auf dem Arbeitsplatz: Hottgenroth-Software installiert und
mindestens einmal angemeldet (Offline-Cache verfällt nach 14 Tagen),
SQL Server LocalDB mit Instanz `HSETU`, PowerShell 5.1 oder 7, .NET-Laufzeit
für die `ibp-*.exe`.

## Zurückspielen

```powershell
.\sync-wissen.ps1 -Richtung Export     # lokales Memory → wissen/
git add -A; git commit -m "wissen: …"; git pull --rebase; git push
```
