---
name: prproject-varianttype-ist-keine-variantenliste
description: "PrProject.VariantType ist bei allen 102 Projekten konstant 2 und sagt nichts über Sanierungsvarianten; Schlüsselspalte heißt dort UUID, nicht ProjectUUID"
metadata:
  type: project
  stand: gemessen
---

Zwei Fallen beim Beantworten der Frage "welche Sanierungsvarianten hat Projekt X":

1. **PrProject.VariantType ist kein Variantenzähler.** Der Wert ist über den gesamten Bestand konstant 2 (102 von 102 Projekten) und trägt damit null Information. Wer ihn als "zwei Varianten" liest, meldet Varianten, die es nicht gibt. Auch VariantRoot und OriginUUID in PrProject sind keine Variantenliste — bei Test0001 sind sie leer bzw. eine Platzhalter-GUID aus lauter 'a', obwohl das Projekt keine Variante besitzt.

2. **Die Schlüsselspalte heißt je Tabelle anders.** PrProject: `UUID`. PrMedia: `ProjectUUID` (Fremdschlüssel auf PrProject.UUID). Ein Join `PrProject p JOIN PrMedia m ON p.ProjectUUID = m.ProjectUUID` bricht mit "Invalid column name" ab.

Die belastbare Auskunft kommt allein aus PrMedia (siehe energieberater-sanierungsvarianten): keine Zeile mit eberater.zip → keine Variante, Ende. Varianten leben in den BDE-Tabellen dieses Containers, nicht in SQL-Spalten.

**Beleg:** 21.08.2026, HsetuPrjData: `SELECT VariantType, COUNT(*) FROM PrProject GROUP BY VariantType` liefert genau eine Zeile — VariantType=2, 102 Projekte. Bei Test0001 (UUID 2c5ac804-0dcc-4560-88a7-7b8827ff69f8) steht VariantType=2, VariantRoot leer, OriginUUID aaaaaaaa-…-aaaaaaaaaaaa, und zugleich 0 Zeilen in PrMedia — also nachweislich keine einzige Variante. Ebenfalls gemessen: `WHERE p.ProjectUUID` gegen PrProject wirft "Invalid column name 'ProjectUUID'"; laut INFORMATION_SCHEMA heißt die Spalte dort UUID, während PrMedia sehr wohl ProjectUUID führt.

**Nicht gemessen:** Ausgezählt am Bestand sind nur die VariantType-Verteilung über alle 102 Projekte und die Spaltennamen aus INFORMATION_SCHEMA (21.08.2026). Der Satz "Varianten leben in den BDE-Tabellen des Containers" ist aus `energieberater-sanierungsvarianten` übernommen und hier nicht nachgezählt. Die Regel "keine eberater.zip → keine Variante" hängt an genau einem Projekt (Test0001, 0 PrMedia-Zeilen) und ist im Übrigen aus jenem Eintrag geschlossen. Der LEFT-JOIN-Hinweis unter "How to apply" folgt aus der Join-Semantik, er ist nicht eigens am Bestand gegengeprüft.

**Why:** Ohne das erste liest man aus einer konstanten Spalte eine Variantenzahl heraus und liefert eine erfundene Antwort, die plausibel klingt. Ohne das zweite kostet jede Variantenabfrage erst einen Fehlschlag. Und ohne den LEFT JOIN meldet man "keine Varianten vorhanden", wo in Wahrheit nur der Projektname falsch geschrieben war.

**How to apply:** Variantenfrage immer über PrMedia beantworten, und zwar mit PrProject als führender Tabelle und LEFT JOIN:

```sql
SELECT p.LongDesc, m.MediaName, DATALENGTH(m.Media) AS Bytes, m.StampEdit
FROM PrProject p
LEFT JOIN PrMedia m ON m.ProjectUUID = p.UUID
WHERE p.LongDesc LIKE '%<Projekt>%'
ORDER BY m.StampEdit DESC
```

Der LEFT JOIN trennt zwei Fälle, die ein INNER JOIN ununterscheidbar macht — beide liefern dort ein leeres Ergebnis:

- **gar keine Zeile** → kein Projekt trifft das Muster; der Projektname ist falsch geschrieben oder das Projekt liegt nicht in dieser Datenbank. Nicht "keine Varianten" melden, sondern den Namen prüfen.
- **eine Zeile, MediaName NULL** → das Projekt existiert und hat keinen Medien-Eintrag: "keine Varianten vorhanden".
- **Zeilen mit eberater.zip** → das sind die Varianten, weiter im Container.

VariantType/VariantRoot aus PrProject gar nicht erst heranziehen.
