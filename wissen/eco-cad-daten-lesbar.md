---
name: eco-cad-daten-lesbar
description: Die Ökobilanz von ECO-CAD steht als normale SQL-Tabellen in HsetuPrjData — Bauteil, Schicht, Menge, Nutzungsdauer, EPD-Zuordnung
metadata:
  type: reference
---

Kein Blob, keine Oberfläche nötig. Die Kette in `(localdb)\HSETU`, Datenbank `HsetuPrjData`:

```
FmLCA               eine Sammlung je Sicht (ein Projekt hat mehrere, u. a. eine für Anlagen)
 └ FmLCAElementGroup  das BAUTEIL — LongDesc = Bauteilname ("Bodenplatte EH 40")
    └ FmLCAElement     die Schicht — LongDesc, Quantity, EstimatedServiceLife, EPDUUID
       └ TcEPD.UId  →  TcEPD.DataSetUId = die ÖKOBAUDAT-UUID
```

Am 30.09.2026 an einem echten Projekt geprüft: alle 1.250 `FmLCAElement`-Zeilen der
LocalDB lösen über `TcEPD` auf, und `DataSetUId` trifft die Spalte `UUID` in
`EPD-Zuordnungen.csv` (Schaumglas → FOAMGLAS W+F, Beton → Transportbeton C20/25 …).

**Warum wichtig:** damit ist Bauteil → Schicht → EPD von außen lesbar, ohne Energie.exe
und ohne ECO-CAD zu öffnen — die Grundlage für jede Zuordnungshilfe.

**So anwenden:**
- `TcEPD` ist hier nur ein Zeiger: ShortDesc/LongDesc/Category leer, `ReferenceUnit` und
  `GrossDensity` tragen den Fehlwert **−987654321,99**. Namen, Einheit und Rohdichte kommen
  aus der CSV, nicht aus der Tabelle.
- `AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA` in `DataSetUId` heißt **nicht zugeordnet**.
- `FmLCAElement.Quantity` steht in der Bezugseinheit des **zugeordneten** EPD — dieselbe
  Zeile führt vor der Zuordnung m³ und danach kg. Nie ohne die Einheit des EPD lesen.
- `Mass` ist nicht gespeichert (auch Fehlwert), die Software rechnet sie beim Öffnen.
- Die Seite „Baustoffe kombiniert" ist eine **Sicht**: sie fasst die Elementzeilen über
  Name + Dichte + Schichtdicke zusammen. Die Summen treffen die Bildschirmtabelle auf den
  Cent (Zement-Estrich 31.111,44).

Schreiben ist damit **nicht** belegt — siehe [[container-ergebnisse-gehoeren-der-software]].
Verwandt: [[epd-liste-steckt-in-der-dll]], [[bauteilspiegel-ist-die-kostengrundlage]].
