---
name: isfp-export-pruefen
description: "Der iSFP-Export liegt als iSFP2.xml in PrMedia.Media — damit lässt sich jede Meldung der iSFP-App am Datensatz nachweisen statt raten"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-12T05:00:15.089Z
---

Der Energieberater übergibt dem iSFP-Programm eine **XML-Datei**, und die liegt als
Medienanhang am Projekt:

```sql
SELECT Media FROM PrMedia
WHERE ProjectUUID = '…' AND MediaName = 'iSFP2.xml'   -- Spalte Media, nicht MediaData
```

`MediaSize` steht auf 0 und ist wertlos; die Bytes stehen in **`Media`**
(`DATALENGTH` nehmen). Die Datei ist mehrere MB groß, weil die Fotos mit drinstecken —
`[System.Xml.XmlDocument]` lädt sie trotzdem ohne Umstände.

**Aufbau:** `iSFP-Projekt/bilanz/allgemein` ist der **Ist-Zustand**,
`iSFP-Projekt/massnahmenpakete/item[n]/bilanz/allgemein` die **Maßnahmenpakete** in
der Reihenfolge der Varianten aus `TableProjekt` ([[bdexit-format]]). Daneben
`…/anlagen/heizungen/item` mit `technik` (`HT_KESSEL_BW`, `HT_WP`, `HT_DIREKT`),
`energietraegerName`, `JAZ`, `deckung`.

**Die Prüfprogramm-Seite:** `C:\Program Files (x86)\HSETU\iSFP2\` — die App heißt
`MeinSanierungsfahrplan.exe` (Qt, nativ). Sie ist inzwischen zerlegt:
[[isfp2-dekompiliert]]. Das maßgebliche Austauschschema steckt **in der EXE**, nicht
als `TiSFPProjekt.xsd` daneben — die auf der Platte ist von 2022 und unvollständig.
Beide tragen Dokumentation je Feld (Bedeutung, Vorkommen `S4`/`S9`,
„Veränderbar: ja/nein"). **Alle Prüfmeldungen stehen als Klartext in der EXE** und
lassen sich mit `grep -a` samt Nachbarschaft herausholen — so ist belegbar, welches
Feld eine Warnung meint, statt es aus dem Meldungstext zu deuten.

**Why:** Ohne den Export bleibt jede Erklärung Vermutung. Mit ihm ist in fünf
Minuten entschieden, ob ein Wert falsch gerechnet, falsch eingegeben oder falsch
zugeordnet ist — so gefunden bei [[isfp-regenerativ-haekchen]].

**How to apply:** Nicht nur das eine Projekt lesen. Alle `iSFP2.xml` der LocalDB
nebeneinander legen (47 Stück, ein `JOIN` auf `PrProject.LongDesc` und
`m.StampEdit`), das fragliche Feld je Projekt ausgeben und nach Datum sortieren.
Dann zeigt sich sofort, ob es ein Einzelfall ist oder ein Muster mit Stichtag —
und die `software_version` im Export sagt, ob ein Update dahintersteckt.

Achtung: Läuft `Energie.exe`, ist der Anhang nur so aktuell wie der letzte
Speichervorgang ([[energie-exe-verwaiste-instanz]]).
