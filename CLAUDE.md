# CLAUDE.md — Hottgenroth-Wissen

Dieses Repo ist das gemeinsame Gedächtnis für die Arbeit mit der Hottgenroth-
Energieberatersoftware (Energieberater 18599, HottCAD, iSFP-Druckanwendung,
Hottgenroth-Agent). Es gehört keinem Rechner. Jede Claude-Code-Sitzung auf
jedem Arbeitsplatz liest hier, schreibt hier und committet hier.

## Wo was liegt

| Ordner | Inhalt | Rolle |
|---|---|---|
| `wissen/` | Ein Fakt je Datei, Frontmatter mit `name`, `description`, `type` | **Das Gedächtnis.** `wissen/MEMORY.md` ist der Index |
| `wissen/aus-ifcweb-agent/` | Einträge des iSFP-Assistenten, die lokal noch fehlten | Gleicher Aufbau, noch nicht in den Hauptindex gemischt |
| `doku/` | Datenmodell, Regeln, Werkzeughandbuch (`ki-hottgenroth.md`), Agent-README, Korpus-Übersichten | Quelle für *warum* und *wie die Software gebaut ist* |
| `skripte/bauteile/` | PowerShell/SQL direkt gegen die Projektdatenbank `(localdb)\HSETU` | Geometrie, Räume, Zonen, Dächer, Treppen, Snapshots |
| `skripte/agent/` | Werkzeuge, die der Hottgenroth-Agent auf dem Arbeitsplatz ausführt | Export, Druck, Sicherung, Wohngebäude-Setup |
| `skripte/bdexit/` | Leser/Schreiber für das `.BDExit`-Format, Varianten, Maßnahmen, `container.ps1` | Sanierungsvarianten des Energieberaters |
| `skripte/ibp/` | `ibp-*.exe` + C#-Quellen für den DIN-18599-Blob (`TableZusatz.Kernel18599V5`) | Anlagentechnik, U-Werte, Lüftung, PV |
| `skripte/isfp/` | `isfp-texte-fuellen.ps1`, `isfp-fertigstellen.ps1`, Textbausteine, Stammdaten | iSFP-XML füllen und drucken |
| `skripte/hsetu/` | Hilfsskripte rund um den dekompilierten Korpus | Suche in API-Indizes |
| `.claude/skills/` | Skills: `hottcad-modell`, `hottcad-projekt`, `hottgenroth-bauteile`, `hottgenroth-heizung`, … | Claude Code lädt sie automatisch |
| `vorlagen/` | `Vorlage-Leeres-Projekt.sqproj` | Ausgangspunkt für neue Projekte |

## Arbeitsweise mit dem Gedächtnis

1. **Zu Beginn** `wissen/MEMORY.md` lesen. Einträge nur bei Bedarf öffnen.
2. **Vor jeder Änderung an einem Hottgenroth-Projekt** die passenden Einträge
   und `doku/regeln-hottgenroth-arbeitsplatz.md` nachschlagen. Vieles, was
   naheliegend aussieht, ist dort als Falle dokumentiert.
3. **Neue Erkenntnis** → neue Datei in `wissen/` im selben Format wie die
   vorhandenen, dann eine Zeile in `wissen/MEMORY.md`. Bestehende Datei
   aktualisieren statt Duplikat anlegen. Widerlegtes löschen oder als
   widerlegt markieren.
4. **Jeder Eintrag trägt seinen Stand**: gemessen, gerechnet oder geschlossen.
   Geschlossenes nie als Tatsache zitieren (siehe `raeume-sind-anlegbar.md`).
5. **Am Ende der Sitzung committen und pushen.** Vorher `git pull`, der
   andere Rechner war vielleicht schneller.

`sync-wissen.ps1` gleicht `wissen/` mit dem lokalen Claude-Code-Gedächtnis
(`~/.claude/projects/<projekt>/memory/`) ab, in beide Richtungen.

## Pfade, die auf jedem Rechner anders sind

Die Skripte wurden unter `C:\Projekte_Dev\energieberatung\bauteile\tools`,
`…\hottgenroth-agent\tools` und `C:\Projekte_Dev\hsetu-decompiled\werkzeuge`
entwickelt. Sie laden Nachbarskripte über `$PSScriptRoot`; absolute Pfade
in Kopfkommentaren und Beispielen müssen auf dem neuen Rechner angepasst
werden. Der dekompilierte Korpus (`hsetu-decompiled/`) ist **nicht** Teil
dieses Repos und darf es nicht werden; `doku/hsetu/` enthält nur die
eigenen Übersichten dazu.

## Was nicht hinein darf

- Kundendaten: Projekt-Snapshots, `Vorlage-Partnermodell.sqproj`, iSFP-Läufe,
  `.mSFPprojekt`-Dateien echter Kunden.
- Zugangsdaten: `HOTTGENROTH_AGENT_TOKEN`, `appsettings.local.json`, `.env`.
- Dekompilierter Quelltext von HSETU-Modulen.

## Regeln aus der Hauptarbeit, die hier weitergelten

- **Wirkungsprobe statt Selbstprüfung**: nach jeder Änderung die Wirkung in der
  Software messen (UA, Endenergie, Fläche). Rückschreibbarkeit beweist nichts.
- **Energie.exe muss zu sein**, bevor in `PrMedia` geschrieben wird; Fenster zu
  heißt nicht Prozess beendet.
- **Varianten über den Namen adressieren**, nie über `PROJEKT_ID` oder `HUELL_ID`.
- **Byte-treue Dateien** (`.BDExit`, `.bin`, `.sqproj`) sind in `.gitattributes`
  als binär markiert. Die Markierung nicht entfernen.
