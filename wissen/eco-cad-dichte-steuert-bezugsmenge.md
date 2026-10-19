---
name: eco-cad-dichte-steuert-bezugsmenge
description: ECO-CAD rechnet Bezugsmenge = Bauteilvolumen × Schichtdichte ÷ EPD-Rohdichte; Platzhalter 1000/0 in den Schichten machen die Ökobilanz um Faktor 30 falsch
metadata:
  node_type: memory
  type: project
  originSessionId: 7531c62a-dc8c-4e84-b220-0ac59c3132b1
  modified: 2026-10-18T23:40:13.013Z
---

**Die Ökobilanz (ECO-CAD, Ökobilanz → Baustoffe kombiniert) übernimmt die Masse aus
der Schichtdichte des Bauteils**, nicht aus dem EPD. Masse = Volumen × Dichte der
Schicht (`TcBuildingElementDimensionLayer.Density`), Bezugsmenge = Masse ÷ Rohdichte
des zugeordneten Datensatzes (`EPD-Zuordnungen.csv`, Spalte Rohdichte).

Bauteile aus dem FS-Katalog kommen mit **Dichte 1000 oder 0** an. Folgen, gemessen
an Krause 3QHTK am 18./19.10.2026: XPS 16 m³ → 509 m³, EPS 3 m³ → 144 m³, CLT 26 →
53 m³, Kreuzlagenholz mit Dichte 0 → **0 m³ (fehlt ganz)**. Ergebnis 58,8 statt
23 kg CO₂/m²a.

**Regel: Schichtdichte = Rohdichte des EPD-Datensatzes**, nicht die physikalische.
Bei m²-Systemdatensätzen (WDVS-Beschichtung 11,4 kg/m²) ist die Dichte
kg/m² ÷ Schichtdicke (11,4/0,02 = 570), damit die Bezugsmenge die Fläche trifft.
Werte, die getragen haben: XPS 32 · EPS B/P 035 25,9 · EPS 040 18,5 · CLT 489 ·
OSB 600 · Holzfaserplatte 173 · Holzfaser Trockenverfahren 150 · Zellulose 45 ·
Mineralwolle Fassade 46 · Gipsfaser 1000 (QNG-Datensatz!) · Parkett 665 ·
Zementestrich 2000 · Bitumenbahn 1100 · Beton 2400.

**Setzen:** in der Oberfläche über Bauteilkatalog → Schicht → Rohdichte, oder per
SQL auf `TcBuildingElementDimensionLayer` mit `ProjectUId`-Filter (Skript
`Set-Schichtdichte-Krause.ps1`, Muster: Transaktion, Probelauf mit Rollback,
`-Echt` nur bei geschlossener Software — EcoCad und EEBerater zählen auch).
Danach in ECO-CAD „Baustoffe nach KG" neu übernehmen; die Zeilen zeigen dann
„Unterschiedliche Einträge" und müssen einmal neu angeklickt werden.

**Weitere Fallen aus derselben Sitzung:**
- Beim Einfügen aus dem Baustoffkatalog kommt die Katalogdichte mit (Holzfaser 290)
  und überschreibt die gesetzte. Kopie unter „eigene Baustoffe" mit LCA-Dichte anlegen.
- Endenergie in ECO-CAD ist der **Bruttowert** (Heizung + WW + Hilfsenergie); PV-
  Eigenverbrauch getrennt im PV-Block = GEG-§23-Anrechnung aus dem Energieberater
  (brutto − netto). Sonst doppelt gezählt.
- Holzfaser statt Zellulose zwischen den Sparren kostet ~2,5 Punkte (Masse ×4,
  Rückgabe in C3/C4 > Gutschrift in A1-A3). Dämmung ist in QNG nie gratis.
- Haustrennwand mit Außenwandaufbau zählt 90 m² WDVS + Putz zu viel (~1 Punkt).
- Wärmepumpe: Vorlauf steht auch am Erzeuger ([[vorlauftemperatur-zwei-stellen]]),
  70/55 dort kostete ~1,6 Punkte in B6.

Verwandt: [[eco-cad-daten-lesbar]], [[epd-liste-steckt-in-der-dll]].
