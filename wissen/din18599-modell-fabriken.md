---
name: din18599-modell-fabriken
description: "Anlagentechnik im IBP-Modell nie von Hand zusammenstecken — es gibt Fabrikmethoden (NewGeneratorBoiler, NewUnitHeating, NewZone …), die Kennungen und Querverweise selbst setzen"
metadata: 
  node_type: memory
  type: project
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-12T18:29:31.939Z
---

Das IBP-Datenmodell hat für alles Fabrikmethoden. Wer Geräte selbst instanziiert und
in die Sammlungen schiebt, muss Kennungen und Querverweise erraten — unnötig.

**Am Gebäude** (`DIN18599Building`): `NewZone`, `NewUnheatedZone`,
`NewConstruction(pID, pName, pU)`, `NewWindow(…)`, `NewUnitHeating`, `NewUnitDHW`,
`NewCircuitHeatWater`, `NewCircuitDHW`, dazu `Get…`/`Delete…`.

**An der Erzeugereinheit** (`P58GenerationUnit`) — deckt sich Kachel für Kachel mit
dem Konfigurator: `NewGeneratorBoiler`, `NewGeneratorHeatPump`, `NewGeneratorDistrict`,
`NewCombinedHeatPowerGeneration` (KWK), `NewGeneratorSorptionHeatPump` (Gas-WP),
`NewGeneratorHeatPumpRV` (Abluft-WP), `NewGeneratorSolar`, `NewStorage`,
`GetGenerator(pID)`, `DeleteGenerator(…)`.

**Zweischichtig wie der Bauteilkatalog:** Typenpool am Gebäude (`P58Generators` =
„Erzeugertyp 1", `P58Storages`, `P58Emissions`, `P58CircuitPipes`) und Komponenten in
der Einheit. Die Komponente zeigt über `Generator` (Objekt) und `strGeneratorID` auf
den Typ; **das Setzen von `Generator` trägt die ID selbst nach**. Bauart und Baujahr
sitzen am Typ, die Normparameter (`fq_B70`, `feta_k_Pn`, `fP_aux_Pn`) an der
Komponente — jeweils mit `b…_Standard`-Schalter („verbesserte Standardwerte").

**Why:** Am 09.08.2026 durchgespielt — ein zweiter Kessel über `NewGeneratorBoiler`,
an den Pooltyp gehängt, serialisiert, neu gelesen: Verweis **objektidentisch** mit dem
Pooleintrag. BinaryFormatter schreibt Referenzen, keine Kopien; die Zweischichtigkeit
hält über den Datenträger.

**Am 12.08.2026 vollständig durchgeführt:** Heizung **und** Warmwasser von außen
angelegt, die Software zeigt und rechnet sie wie eigene Eingaben (Dialogwerte
deckungsgleich, Restabweichung 0,07 %). Verknüpft wird über Zeichenketten:
`strGeneratorID`, `strEmissionID`, `strEnergySource`, `strIDLink` (versorgte Zone),
`strParentID`.

**Zwei Dinge, ohne die es still falsch rechnet:**
- **`UnitCircuitInterrelation.AddRelation(einheitID, kreisID, 1f)`** — die
  Beziehungsmatrix ist der Träger der Verknüpfung Einheit ↔ Kreis. Ohne sie kommt am
  Erzeuger kein Bedarf an: `fQdot_N` 0,01 kW, „Keine Heizung vorhanden".
- **`enumPipeType`** an der Leitungskomponente (2 Anbindeleitung, 1 Steigstrang,
  0 Verteilleitung). Sonst sind alle Verteilleitung und das Modell leitet 584 m statt
  27+5+195 m ab — Endenergie 78.854 statt 50.836 kWh.

**Warmwasser** meist `NewGeneratorLinkedToHeating` + `LinkedGenerator` auf die
Erzeuger**komponente** der Heizung. `LinkedUnit` ist schreibgeschützt und wird vom
Modell selbst nachgetragen — wie `strGeneratorID` beim Setzen von `Generator`.

Austauschformat und Werkzeuge: `ibp-anlage-lesen.exe` / `ibp-anlage-setzen.exe`,
JSON mit nur den Eingabewerten.

**How to apply:** Fünf Fallstricke, die schon Zeit gekostet haben:

1. **`pID` darf nicht leer sein.** Mit leerem `pID` legt die Fabrik das Objekt an und
   gibt es zurück — trägt es aber **nicht in die Sammlung ein**, ohne Fehlermeldung.
   Die Sammlungen sind nach Kennung geschlüsselt. Muster: `Typname_N[HEX8]`.
2. **Die `b*_Standard`-Flags nicht ausschalten.** Sie stehen auf True, das Modell
   leitet die Kennwerte selbst ab. Wer sie abschaltet und Werte von Hand setzt, muss
   *alle* abhängigen Felder kennen — der Versuch hat die **Oberfläche unbrauchbar
   gemacht** (kein Fenster mehr, Prozess musste beendet werden).
3. `IBPHashtable` ist **keine** `IDictionary` (eigene Klasse mit `Count`, `this[int]`,
   `this[string]`, `Add(string, object)`).
4. Die Werte sind **Eigenschaften, keine Felder**, und sitzen teils auf Basisklassen.
5. `.NET Framework 4.8` ist Pflicht (BinaryFormatter).

Namen nicht raten: `werkzeuge/ibp/ibp-api.exe` listet alle `New*`-Methoden und
Aufzählungen, `ibp-heating.exe --sammlungen` die echten Sammlungsnamen (der Heizkreis
heißt `CircuitHeatWater`, nicht `Circuits`). Vor jedem Schreiben gegen
`referenz-heizung-konfiguriert.txt` vergleichen.

**Offen:** Nach dem Einlesen rechnet die Software `fQdot_N` auf 0,01 kW und
`fTemperatureRise` auf −20 statt 42,5 — die Auslegungstemperaturen kommen in ihrer
Rechnung als 0 an, ein Eingang fehlt noch. Sie schreibt dann „Keine Heizung
vorhanden".

Werkzeuge und Belege: `hsetu-decompiled/werkzeuge/ibp/` und
`hsetu-decompiled/DIN18599-ANLAGENTECHNIK.md`.
Verwandt: [[din18599-anlagentechnik-ibp-blob]], [[hsetu-bauteilkatalog-api]]
