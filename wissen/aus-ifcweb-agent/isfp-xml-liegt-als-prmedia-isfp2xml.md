---
name: isfp-xml-liegt-als-prmedia-isfp2xml
description: "Das iSFP-Dokument liegt als PrMedia.Media (varbinary) mit MediaName='iSFP2.xml'; Vorbedingungsabfrage vor jedem iSFP-Auftrag"
metadata:
  type: project
  stand: geschlossen
---

Das iSFP-Dokument haengt als Binaerblob an PrMedia: `MediaName = 'iSFP2.xml'`, Inhalt in der Spalte `Media` (varbinary), nicht in `MediaData`. Verknuepfung ueber `PrMedia.ProjectUUID = PrProject.UUID`.

Vorbedingungsabfrage (Sekunden, vor jeder Feldueberlegung):

```sql
SELECT m.MediaName, DATALENGTH(m.Media) AS Bytes
FROM PrMedia m WHERE m.ProjectUUID = '<Projekt-UUID>'
```

Keine Zeile mit `iSFP2.xml` -> im Zielprojekt liegt kein gespeicherter Fahrplan; abbrechen und melden.

Es gibt nichts auszuwaehlen: je Projekt fuehrt PrMedia hoechstens eine Zeile. Was wie Dubletten aussieht, sind verschiedene Projekte mit gleichem Namen; ihr `StampEdit` ist identisch und entscheidet damit gar nichts. Getrennt werden sie ueber die Projekt-UUID -- nie ueber den Projektnamen, nie ueber `StampEdit`.

Eine fehlende PrMedia-Zeile sagt nichts ueber den Ausbaustand des Projekts. Sie bedeutet nicht "reines CAD- oder Testprojekt": Senningsweg 15 (117 Bauteile) und Senningsweg 17 (82 Bauteile) sind voll ausmodellierte Projekte ohne PrMedia-Zeile. Sie bedeutet nur: fuer dieses Projekt wurde noch kein Fahrplan gespeichert. Der Container entsteht erst, wenn ein Mensch in der Software einmal einen Fahrplan erzeugt und speichert.

Achtung Spaltennamen: PrMedia und PrProject heissen `UUID`/`ProjectUUID`, nicht `UId`/`ProjectUId`. `ClassValue` existiert hier ueberhaupt nicht -- diese Spalte gehoert zu BmData. Woher `UId`/`ProjectUId` stammen, ist ungeklaert; BmData-Spalten sind es jedenfalls nicht.

Offen bleibt (unveraendert, siehe Skill isfp-dokument): ob das XML Quelle oder Ausgabe ist. Solange das nicht vermessen ist, wird dort nicht geschrieben.

**Beleg:** 21.08.2026, HsetuPrjData. (1) Spaltennamen ausgezaehlt: PrMedia heisst UUID/ProjectUUID/Media/MediaData/MediaName -- eine Abfrage mit `UId`/`ProjectUId`/`ClassValue` scheitert mit 'Invalid column name'. (2) `SELECT COUNT(DISTINCT ProjectUUID) FROM PrMedia WHERE MediaName='iSFP2.xml'` -> 35 Projekte, 35 Zeilen, 47.033 bis 7.519.129 Bytes; das XML steht in der Binaerspalte Media, MediaData ist 0. 35 Projekte zu 35 Zeilen heisst: hoechstens eine Zeile je Projekt. (3) Nachpruefung 21.08.2026: Senningsweg 15 (117 Bauteile) und Senningsweg 17 (82 Bauteile) haben keine PrMedia-Zeile; bei gleichnamigen Projekten ist `PrMedia.StampEdit` identisch.

**Nicht gemessen:** Nichts an den Zahlen -- Zeilen-, Projekt- und Bauteilzahlen sind am Bestand ausgezaehlt (21.08.2026). Gestrichen wurden zwei ungemessene Saetze der ersten Fassung: die aus `anlagentechnik-vorbedingung-blob-pruefen` uebernommene Regel "keine PrMedia-Zeile = Testprojekt" (durch Senningsweg 15/17 widerlegt) und die Sortierung nach juengstem `StampEdit` (bei hoechstens einer Zeile je Projekt gegenstandslos, bei Namensdubletten identisch). Ungemessen bleibt allein die Richtungsfrage: ob das XML Quelle oder Ausgabe der Software ist.

**Why:** Ohne diese Abfrage baut man Massnahmen-, U-Wert- und Kostenfelder fuer ein Dokument, das im Zielprojekt gar nicht existiert, und merkt es erst beim Schreiben. Wer die Spaltennamen aus dem BmData-Muster uebernimmt, laeuft in 'Invalid column name'. Und wer aus einer fehlenden PrMedia-Zeile auf ein Testprojekt schliesst, verwirft ausmodellierte Kundenprojekte wie Senningsweg 15 oder 17.

**How to apply:** Bei jedem iSFP-Auftrag (Massnahme, Ziel-U-Wert, Kosten, Foerderung, BAFA-Nummer) zuerst PrMedia des Projekts auf `MediaName='iSFP2.xml'` pruefen, immer ueber die Projekt-UUID. Genau eine oder keine Zeile erwarten; kommt mehr als eine, stimmt die UUID nicht -- nicht nach `StampEdit` aussuchen, sondern die Projektzuordnung klaeren. Fehlt die Zeile, den Nutzer bitten, den Fahrplan einmal in der Software anzulegen; von aussen ist der Container nicht sinnvoll zu erzeugen. Aus dem Fehlen keine Aussage ueber den Modellierungsstand ableiten.
