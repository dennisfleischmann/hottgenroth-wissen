---
name: schichtloses-bauteil-verliert-u-wert
description: "Ein schichtloses Katalogbauteil verliert seinen U-Wert, weil die Software Rsi und Rse als Zahlen in die Zeile schreibt — und rechnet dann 1/(Rsi+Rse); ohne diese zwei Felder hält keine Reparatur"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 634a2411-a32e-41c2-8ecf-cb250ec3dc7c
  modified: 2026-10-03T15:01:53.112Z
---

Ein **schichtloses** Bauteil im Hottgenroth-Bauteilkatalog („U-Wert direkt")
verliert seinen gespeicherten U-Wert, sobald die Software es anfasst. Sie rechnet
ihn dann aus null Schichten: es bleibt nur Rsi + Rse, und heraus kommt
**U = 1/0,17 = 5,882** bei „gegen außen" oder **1/0,13 = 7,692** bei „gegen
Erdreich". Der genaue Wert verrät also die Lage, mit der das Bauteil getypt ist.

**Die Ursache sind zwei Spalten, nicht der U-Wert:**
`InternalCoefficientOfHeatTransfer` und `ExternalCoefficientOfHeatTransfer` in
`TcBuildingElementDimension`. Heil tragen sie den **Sentinel** −987654321,99;
kaputt stehen dort **0,13 und 0,04**. Solange Zahlen darin stehen, rechnet die
Software bei jeder Berührung neu — und 1/(0,13+0,04) ist das Ergebnis.

**Darum hält eine Reparatur nicht, die nur U, RValue und ElementMeta setzt.**
Genau das ist am 03.10.2026 passiert: um 11:57 zurückgesetzt, um 16:40 beim
nächsten Öffnen wieder 5,882. Erst mit den beiden Übergangskoeffizienten blieb
es stehen. **Sechs Felder gehören dazu:** `UValue`, `RValue`,
`InternalCoefficientOfHeatTransfer`, `ExternalCoefficientOfHeatTransfer`,
`ShortDesc` (dort steht ein Kurzzeichen wie `GEG`, das die Software mit dem
U-Wert als Text überschreibt) und `ElementMeta` (leer; kaputt steht der
`KorrLS/KorrBe/KorrUD`-Rumpf drin). `CatalogStateType` ist **nicht** der
Unterschied — kaputt und heil tragen beide 4.

`KorrUD=Falsch` im ElementMeta ist ebenfalls nicht der Schalter für „U-Wert
direkt": 3.079 heile schichtlose Bauteile tragen ihn mit U-Werten von 0 bis 7,69.

**Die Sollwerte nie abschreiben, sondern lesen.** Dasselbe Bauteil liegt meist
mehrfach als Variantenkopie (`VAR …: <gleicher Name>`) im selben Projekt; die
werden nicht mit angefasst und sind damit der Originalzustand. Ein Skript, das
sie zur Laufzeit ausliest und abbricht, wenn sie nicht einig sind, hat keine
geratene Zahl im Code. Zur Gegenprobe `K_ZAHL` der Hüllfläche im Container.

**Suchabfrage** — der negative `RValue` ist das schnellste Erkennungszeichen,
Rsi/Rse die Ursache; beide Mengen deckten sich (199 Bauteile in 27 Projekten):

```sql
SELECT ... FROM TcBuildingElementDimension d
WHERE d.InternalCoefficientOfHeatTransfer > 0
  AND d.ExternalCoefficientOfHeatTransfer > 0
  AND NOT EXISTS (SELECT 1 FROM TcBuildingElementDimensionLayer l
                   WHERE l.DimensionUId = d.UId)
```

**Why:** Kein neues Verhalten und kein Einzelfall — 199 Bauteile in 27 Projekten,
zurück bis November 2025. Der Container wird dabei **nicht** angefasst: der
falsche U-Wert steht in der Bauteilliste, die Bilanz rechnet weiter mit dem
richtigen. Das macht es leicht zu übersehen und schwer zu glauben.

**How to apply:** Nach jedem Öffnen eines Projekts, in dem schichtlose Bauteile
hängen, einmal danach suchen. Und keine Entwarnung geben, nur weil eine Sitzung
ohne Schaden verlief — am 03.10. war eine Sitzung unauffällig und die nächste
nicht. Verwandt: [[container-ergebnisse-gehoeren-der-software]] (dort der
Container, hier der Katalog), [[varianten-sind-schnappschuesse]],
[[klenke-mp7-kopie-von-mp6]].
