---
name: raum-zone-raumstempel
description: "Räume, DIN-18599-Zonen, Nutzungsprofile und Raumstempel — Doku und erprobte Schreibwerkzeuge im bauteile/-Repo"
metadata: 
  node_type: memory
  type: project
  originSessionId: a79f8008-5d86-4c71-9f3c-51871403afa1
  modified: 2026-08-17T20:27:25.957Z
---

Vollständige Beschreibung in `bauteile/docs/hottgenroth-raum-zone-sql.md`,
Werkzeuge in `bauteile/tools/`: `Snapshot-Projekt.ps1`, `Diff-Snapshot.ps1`,
`Set-Raum-Heizstatus.ps1`, `Set-Raum-Zone.ps1`, `Set-Raumstempel.ps1`.
Alle schreibenden haben `-Probelauf`. Beides im separaten `bauteile/`-Repo.

Die vier Sätze, die man vorher wissen muss:

- **Eine handgeschriebene `BmZone` trägt.** Zwei Zeilen (`BmZone` + `BmZoneData`,
  gleiche UUID, `ZoneType 5`, Parent = `BmBuilding`, `ParentClassType 4`) genügen;
  die Software hat sie danach selbst weiterbearbeitet. Erprobt, nicht vermutet.
- **`BmZone.InfoDesc` ist die Naht zum EE-Berater** — dort steht wörtlich dessen
  `P0Zone_<n>[HASH8]` aus `TableHuellfl.ZoneID`. Bei einem Wohngebäude immer schon
  vorhanden, also lesen statt erzeugen. Die Naht wirkt **nicht** von allein:
  eine passende `InfoDesc` ändert die `eberater.zip` um kein Byte.
- **Der Raumstempel ist kein eigenes Objekt**, sondern die Anzeige von
  `ShortDesc`/`LongDesc`, `Area`/`Volume`, `LivingArea`, `HeatingType`,
  `InsideTemperature`. Jedes davon steht doppelt — in `BmRoom` **und** im CAD-XML
  in `BmData.ClassValue`. Siehe [[vorlauftemperatur-zwei-stellen]] für dasselbe
  Muster in der Anlagentechnik.
- **`UUID` ist in Verweistabellen der Besitzer, nicht die Zeile.**
  `BmZoneReference.UUID` = die Zone, `PdProfileReference.UUID` = das Profil,
  `BmData.UUID` = die *Datenart* (alle `CADXMLData` teilen eine). Schlüssel ist
  jeweils das Paar. Wer das verwechselt, überschreibt beim ersten `UPDATE` das
  ganze Projekt.

**Raum anlegen (18.10.2026, Hudlberger):** `New-Raum.ps1` kopiert die fünf Zeilen eines Vorlagenraums und schreibt das CAD-XML neu. Falle: `BmData.UUID` UND `GId` der `CADXMLData`-Zeile sind die **konstante Datenart-Kennung `99E575C9-E4EA-4F13-A622-84A1D3B742F8`** (projektübergreifend gleich). Eine frische GUID dort → HottCAD findet die Zeichnung nicht, der Raum bleibt unsichtbar. `GId` des Raums = XML-`GUID` (nicht die UUID); `VariantRoot` leer ist in Ordnung (Pohlstraße-Beleg). Raumprofil nur namensgleich setzen – HottCAD setzt `RoomType` beim Speichern aus dem Profil zurück.

**Why:** Räume und Zonen von außen zu setzen ist erprobt und ungleich einfacher
als Bauteile (5 `INSERT` ohne `UPDATE` je Raum, gegen 7 `INSERT` + 81 `UPDATE`
je Bauteil) — aber jede Aussage steht mehrfach in der Datenbank, und wer nur eine
Stelle setzt, erzeugt ein Gebäude, das sich selbst widerspricht.

**How to apply:** Vor jedem Schreiben Energie.exe schließen
([[energie-exe-verwaiste-instanz]]) und sichern; danach die Wirkung in der
Oberfläche prüfen, nicht die Rückschreibbarkeit
([[wirkungsprobe-statt-selbstpruefung]]). Geometrie kann nicht erzeugt werden —
Räume ändern ja, neu erfinden nein.
