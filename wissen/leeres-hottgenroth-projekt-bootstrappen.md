---
name: leeres-hottgenroth-projekt-bootstrappen
description: Ein frisch angelegtes Projekt ohne Geschosse braucht ein Bootstrap — New-Geschoss/New-Aussenring/New-Dach verlangen eine Vorlage IM Projekt; Fremdprojekt-Kopie mit vier Überschreibungen genügt
metadata:
  node_type: memory
  type: project
  originSessionId: 2ed9860f-2e20-443e-a4ce-98dc560bde95
  modified: 2026-10-13T21:14:53.750Z
---

Die Zeichenwerkzeuge (`New-Geschoss.ps1`, `New-Aussenring.ps1`, `New-Dach.ps1`)
suchen ihre Vorlagezeilen **im Zielprojekt** — auch `-VorlageDatenbank` sucht
dort nur unter derselben Projekt-UUID. Ein vom Agenten frisch angelegtes Projekt
(1 Gebäude, 0 Geschosse, 0 Bauteile) läuft deshalb bei jedem Werkzeug auf
„keine Vorlage". Erprobt am 13.10.2026 an *Simic*:

**Bootstrap = Fremdprojekt-Kopie mit Überschreibung der projektgebundenen Spalten.**

- **EG-Geschoss** (alle vier Zeilen selbst anlegen, sonst scheitert auch die
  Selbstheilung von New-Geschoss am fehlenden Vorlagegeschoss): `BmFloor` +
  `BmFloorData` + `BmData 'CADXMLData'` + `BmData 'is_auto_generated'`.
  Überschreiben: `UUID`/`GId` neu, `ProjectUUID`, `BuildingUUID`, Namen,
  Höhen, Elevation; Floor-XML mit `GUID = BmFloor.UUID` frisch schreiben.
- **Vorlagenwand/-dachfläche** (je 5 Zeilen): zusätzlich
  `ReferenceUUID = BIMUUID = BmBuilding.BIMUUID des Zielgebäudes` setzen —
  Wände und Dächer verweisen in BEIDEN Spalten auf das Gebäude-BIM.
  Nach dem Bau der Ringe/Dächer die Vorlagen löschen (`LongDesc='VORLAGE%'`).
- **Katalogverweise sind NICHT projektgebunden**: `CatalogBasisUUID`,
  `CatalogDimUUID`, `u_valueDimGuid` existieren in keiner Tabelle von
  `HsetuPrjData` — sie zeigen in die globale Katalogdatenbank der Maschine
  und dürfen mitkopiert werden. Das GUID-Präfix-Argument („ba34a101 = projektgebunden")
  ist falsch: Hottgenroth vergibt Präfixe chargenweise, nicht je Projekt.
- `BmFloor.ProfileGroupUUID` ist in echten Projekten NULL; `BmFloor` existiert
  je Gebäude (ein Projekt mit 3 Gebäuden führt jedes Geschoss dreimal).

Danach greifen die normalen Werkzeuge: New-Geschoss (OG/DG/Keller per
`-Bezug EG`), New-Aussenring (`-VorlageWand VORLAGE`), New-Fenster (braucht
keine eigene Vorlage — kopiert von der Zielwand), New-Satteldach.
Einmalskript dieser Sitzung: Scratchpad `bootstrap-simic.ps1`; ein
parametrisiertes Werkzeug `New-Projektstart.ps1` fehlt noch.

**Why:** Ohne das Bootstrap ist jedes agent-angelegte Projekt eine Sackgasse,
und der Fehler („Kein vollstaendiges Geschoss als Vorlage") sieht wie ein
Werkzeugdefekt aus. Die vier Überschreibungen sind die vollständige Liste —
alles andere (Sentinels, Katalog) trägt die Kopie von selbst.

**How to apply:** Vorher sichern ([[messzyklus-snapshot-diff]]), Software-Lage
prüfen ([[energie-exe-verwaiste-instanz]]). Wände tragen danach die U-Werte der
Spenderwand als Platzhalter — Bauteilzuweisung ist ein eigener Schritt.

**Alles Nachgelagerte wartet auf das erste Öffnen.** Ein reiner Zeichnungsimport
(nur RepositoryType 3) ist für drei Abnehmer unsichtbar, gemessen am 13.10.2026
an Simic: der IFC-Export überspringt jedes Element („no geometry",
[[hottcad-eigener-ifc-export]]), der **Bauteilspiegel** der App liest nur
RepositoryType 1 (`HottgenrothBauteilSync::REPO_MODELL`) und zeigt 0 Bauteile —
damit gibt es für `add_components` keine Flächen —, und die **Anlagentechnik**
scheitert noch früher: ohne eberater-Container bricht `container.ps1` mit „kein
Anhang eberater.zip" ab. Erst HottCAD/Energieberater öffnen (materialisiert
Repo 1, Platten und Container), dann Flächenzuweisung und Heizung.
