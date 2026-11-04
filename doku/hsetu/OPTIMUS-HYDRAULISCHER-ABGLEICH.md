# Optimus — hydraulischer Abgleich: Rechenweg, Module, Datenmodell

**Stand 04.11.2026.** Gelesen am Dekompilat des *Optimus 2026 Planer* (Hsetu.FW.Calculations
6.7.8.301 = `eigen/Hsetu.FW.Calculations~5e976678.cs`, Hsetu.Optimus.BL 8.7.0.13 =
`eigen/Hsetu.Optimus.BL~90a21848.cs`, Hsetu.Hed 6.7.2.302) und **gegen die zwei Berichte vom
01.11.2026 zum Projekt „Jonathan Hilgert_Heizlastberechnung" nachgerechnet** — die
Nachrechnung (`skripte/optimus/optimus-nachrechnen.py`) trifft kv-Werte und Voreinstellungen von
15 der 19 Fußbodenheizkreise exakt, die Durchflüsse auf 3–5 % und die Förderhöhen beider
Berichte auf 5–12 % (35 °C: 1 818/611 gegen 1 730/571 mbar; 45 °C: 1 202/149 gegen 1 070/152). Zeilenangaben beziehen sich auf
den Optimus-Build; im Energieberater-Build (`Hsetu.FW.Calculations.cs`, 6.7.6.301) liegen
dieselben Klassen ein paar hundert Zeilen versetzt.

Stand je Aussage: **gemessen** = am Projekt/Bericht nachgerechnet, **gelesen** = im Quelltext
belegt, **geschlossen** = aus Indizien.

---

## 1. Was Optimus ist

Optimus ist Hottgenroths Modul für den **hydraulischen Abgleich nach Verfahren B** (raumweise
Heizlast → Heizflächenleistung → Volumenstrom → Ventil-Voreinstellung → Pumpenförderhöhe) auf
Basis der DBU-geförderten „OPTIMUS-Studie". Es läuft

- eingebettet im **GebäudeProfi/ETU-Planer** (`Hsetu.BuildingModule`, Kachel „optimus"), oder
- als eigenes Programm **Optimus / Optimus Planer** (`C:\Program Files\HSETU\Optimus`,
  `…\OptimusPlaner`; der Bericht trägt „Optimus 2026 Planer 8.7.1.7").

Lizenzen: Optimus 2026 (`7eb1218c…`, Nr. 61), Optimus 3D (`60189fd3…`, 61), Optimus Standard
(`4d92f5b1…`, 697); eine ETU-Planer-Lizenz ab *Basic* schaltet Optimus pauschal frei
(`LicenseHelper.IsOptimusLicensed`). Alle drei stehen seit 04.11.2026 im Lizenzkatalog der
fs-app.

Die Doku-Zeile in `MODULE.md`, Optimus sei „Sanierungsoptimierung", war falsch — die
`Calculations.BuildingElements`-Klassen dort sind nur Hilfsschritte, die Bauteilwerte aus dem
Gebäudemodul in den Optimus-Raum spiegeln.

---

## 2. Beteiligte Baugruppen

| Baugruppe | Rolle |
|---|---|
| `Hsetu.Optimus.BL` | Oberflächen-Logik, Projekt laden/speichern, **Einstiegsbefehl** `CalculateHeatloadAndHydraulicBalancingCommand` (Z. 5784 ff.) |
| `Hsetu.FW.Calculations` | **Der Rechenkern**: `TCalcOptimusCalculation` + Strategien S5/S2 + ~60 `TCalcOptimus*`-Schritte/Objekte (Z. 21698–52700) |
| `Hsetu.FW.Calculations` (`TCalcHeatLoadCalculation`) | Raumheizlast DIN EN 12831, wenn „TGA-Heizlast" gewählt |
| `Hsetu.Model.Pim.Calculation` | **DIN EN 1264** für Fußbodenheizkreise (`TCalcEN1264Data`): Normleistung 50/40, Wärmestromdichte, Oberflächentemperatur, Rohrlänge (`HcL`) |
| `Hsetu.Hed` | Heizungsauslegung/Oberfläche, Berichtsdaten (`TBOHedState.HydraulicBalancing`) |
| `Hsetu.Model.Xim` | Enums (`TTechDataHeatingLoadType`, `TTechDataBuildingAdjacentType`, …) |
| `HsetuAppTimData` (LocalDB) | App-TIM: Ventil-/Pumpenkataloge („Neutraler Hersteller – Abgang Verteiler"). **Nicht mit dem Windows-Login lesbar** (Login failed); die Software öffnet sie mit eigenen Zugangsdaten |

Die Optimus-Rechenergebnisse heißen `TCalcOptimus*CalculationResults` (Kürzel `CR`), hängen zur
Laufzeit an den Modellobjekten (`circuit.CR.Locate(...)`) und sind **flüchtig** — siehe § 6.

---

## 3. Ablauf einer Berechnung (gelesen)

`CalculateHeatloadAndHydraulicBalancingCommand.Execute` (Optimus.BL Z. 5935 ff.):

1. **Heizlast.** Projekteinstellung `OptimusSettingGroup.TGAOptimusHeatload == 2` und
   `HeatLoadSettingGroup.HeatLoadCalculationType ∈ {8, 9, 13, 14, 15}` (DIN/ÖNORM EN 12831,
   Enum `TTechDataHeatingLoadType`: 13 = `hltDINEN12831NA12017`) → `TCalcHeatLoadCalculation`
   läuft (TGA-Heizlast). Sonst Strategie **S5 „Berechnung von Heizlast"**
   (`TCalcOptimusHeatloadStrategy`: `RoomCalculationResultsStep`, `RoomHeatloadCalcStep` =
   die vereinfachte Optimus-Heizlast nach Baualtersklasse).
2. **Anlage.** Strategie **S2 „Berechnung von der Anlage"** (`TCalcOptimusPlantStrategy`,
   Z. 52363 ff.), Anlagentyp = `PmPlant.HydraulicIntegrationType` (1…3). Schrittfolge:
   `*CalculationResultsStep` für Distribution/Pump/PlantSpace/Radiator/SingleCircuit/Valve/Plant
   → `CheckFlowMedium` → `CheckDistributionBranchType` → `CheckPlantSpaces` → (`Insulation` bei
   Gebäudesanierung) → `FillTemplates` → `ValidatorsAccept` → `CalculateCircuits` →
   **OptimizationSteps** (`RadiatorCalc`, `SingleCircuitCalc`, `RequiredOutput`, `HeatedArea`,
   `ValveCalc`; je Verteilung: `SetCalcDistribution`, `DistributionFlowTemperature`,
   `DistributionOptimization` (TF/FF), `SetPlantTemperature`, bei Anlagentyp 3
   `PlantCalcForPump`; zuletzt `CheckKvValues` + `ValveSetting`) → `CalcSumsRadiator` →
   `ThermalWorstMessage`.
3. **Grenzwerte** aus der Benutzer-DB: `Optimus.OPT_APPL_SETTING_FH_WARNING_VALUE` (Standard 150)
   und `…_FH_ERROR_VALUE` (250) → Förderhöhen-Warnung/-Fehler in mbar.
4. **Vorlaufoptimierung** findet nur statt, wenn `PmDistribution.RatedFlowTemperature ≤ 0`
   (`TCalcOptimusDistributionOptimizationFHPumpCalcObject.CheckDistribution`, Z. 28367 ff.).
   Steht dort ein Wert (Hilgert: 45 bzw. 35), bleibt der eingetragene Vorlauf fest.
5. Obergrenze der Vorlauftemperatur: **52 °C**, oder das `MaximalFlowTemperature` des ersten
   Kessels, wenn kleiner (`CalcFlowTemperature`, Z. 33284 ff.). Hilgert: Weishaupt WTC 25-A mit
   45 °C → alles, was mehr bräuchte, wird auf 45 gekappt.
6. `OptimusSettingGroup.StandardTemperature = True` + `FlowTemperature/ReturnTemperature`
   (Standard 55/45) rechnet zusätzlich die Heizkörperleistung bei dieser Systemtemperatur aus
   (`CalculateOutputForSystemTemperatures`) — nur Anzeige.

---

## 4. Die Formeln je Fußbodenheizkreis (gelesen, gemessen)

Klasse `TCalcOptimusSingleCircuitCalcObject` (Z. 33115–33592) und
`TCalcOptimusRequiredOutputCalcObject` (Z. 32031 ff.). Einheiten: W, K, kg/h, m³/h, mbar.

| Schritt | Formel | Fundstelle |
|---|---|---|
| Normleistung des Kreises | `Q_out` = Leistung bei **50/40 °C** aus DIN EN 1264 (`PmCircuit.HeatOutput`); `q = Q_out/A` steht in `ResidentialZoneHeatFlowDensity` (VA 10 cm, R_B = 0, 45 mm Überdeckung: 144,8 W/m²; VA 12,5: 135,3) | Pim.Calculation |
| Soll-Leistung je Kreis | `Q_req = Q_Raum · Q_out / Σ Q_out(Kreise des Raums)` — die Raumheizlast wird **nach Normleistung** auf die Kreise verteilt | Z. 32065 |
| erforderliche Übertemperatur | `Δθ_erf = (Q_req/Q_out)^(1/1,1) · 25 K` | `CalcFlowTemperature` |
| erforderlicher Vorlauf | `t_V,erf = trunc(Δθ_erf + t_i + 2,6)`, geklemmt auf `[26 °C, min(52, Kessel-Max)]` | ebd. |
| Spreizung beim gegebenen Vorlauf | `n = 1 + 4·(t_V − Δθ_erf − t_i)/(3·Δθ_erf)`; `ΔT = 3·Δθ_erf·(√n − 1)`; **geklemmt auf 5…15 K** | `CalcReturnTemperature` |
| Massenstrom | `ṁ = Q_req / (4,2 · ΔT) · 3,6` | `CalcMassFlow` |
| Volumenstrom | `V̇ = ṁ / 993 · **1,15**` — 15 % Aufschlag ist fest einprogrammiert | `CalcVolumeFlow` |
| Rohrlänge | `L = A_Heiz / VA` (`ResidentialZoneHcL`) | `CalcDpPipe` |
| Rohrreibung | `w = V̇/(3600·π·d_i²/4)`, `Re = w·d_i/4,8e-7`, λ Colebrook mit Rauheit **0,0015 mm**, Start Nikuradse, 4 Iterationen; `Δp_Rohr = L · λ·ρ·w²/(2 d_i) / 100` [mbar] | `CalcDpPipe` |
| Ventil offen | `Δp_V = 1000 · (V̇/kvs)²`; kvs des Kreisventils, **ohne Ventil kvs = 0,7**; Dynacon/Dynacon Eclipse fest 150–250 mbar | `CalcValveDp`, Z. 26930 |
| Verteilerzuleitung (echtes Rohr) | `Δp_Verteiler` = Colebrook über `L = PmDevice.DistanceToPump` (einfache Länge) mit `d_i = PmConnection.InnerDiameter` des **Vorlaufanschlusses** des Verteilers (`PmDistributor.SupplyConnectorUUID`), **Standard 20 mm**, wenn leer; Durchfluss = Summe der Kreise | `TCalcOptimusDistributorCalcObject.CalcDpPipe` |
| Verteilerniveau | `P = max_Kreise(Δp_Verteiler + Δp_Rohr + Δp_V,offen)`; dieser Kreis ist der **„hydraulisch ungünstigste"**; für die Ventilwahl zählt `P − Δp_Verteiler` (`CalcDpValveForCircuit`: `Δp_V,soll = DpOfV − Δp_Rohr − Δp_Verteiler`) | `CalcMaxPressureLoss`, Z. 26560; Z. 28060 ff. |
| Ventilvoreinstellung | `Δp_V,soll = P − Δp_Rohr`, `kv = V̇/√(Δp_V,soll/1000)`, Voreinstellung aus der Kennlinie des Katalogventils (`PressureLossCurveTypeA`, bevorzugt xp = 1 K, dann 2 K) | `TCalcOptimusValveSettingCalcStep`, Z. 50599 ff.; `GetValvePresetValueNotBasis`, Z. 36125 |
| Netz-Heuristik | `R = max(0,2; (V̇_ges[l/h] / (4,3 · A_beheizt[m²]))²)` mbar/m, `Δp_Netz = R · L_Zuleitung`; `A_beheizt` = Summe der **Raumflächen** der versorgten Räume (`CalcHeatedArea`, Z. 29118), `L_Zuleitung` = `PmDistribution.TechData.PipelineLength` (= Verteilerzuleitung) | `CalcDpPump`, Z. 26500 ff. |
| Förderhöhe (Verteilung) | `DPthkv = Δp_sonstigeGeräte + Δp_Zähler + max(Δp_Netz, P)`; mindestens `OptimusSettingGroup.MinDeltaP`. Aufgerufen nur, wenn `Domain.ApplicationDomain.TIM` geladen ist (`CalcDistributionDpPump`) | ebd. |

**„Thermisch ungünstigster" Kreis** = der mit dem höchsten `t_V,erf`
(`TCalcOptimusDistributionThermalWorstCalcObject`); er bestimmt bei freier Optimierung den
Vorlauf der Verteilung (Suche 26…52 °C in 1-K-Schritten über `DictPosTemp`).

**Heizkörper-Pfad** (nur zur Einordnung): `Q_req = Q_75/65 · (Δθ_log/Δθ_log,75/65)^n`,
`Δθ_log = ΔT/ln((t_V−t_i)/(t_R−t_i))`, Volumenstrom `Q·0,043/1000` bzw. `Q·3,6/(4200·ΔT)`;
Zuleitung dort `×1,5`, Gesamt `×2,0` (bzw. ×1,43 bei Ventilautorität/einheitlicher
Dimensionierung) — `TCalcOptimusRadiatorDistributionDpPumpCalcObject`, Z. 30582 ff.

### Warnungen und ihre Schwellen (gelesen)

| Nr. | Text | Bedingung |
|---|---|---|
| 1008 | „…größere Leistung als die maximale Leistung (100 W/m²) nach DIN EN 1264-4…" | `Q_req/A_Heiz > 100` (`CheckSingleCircuitsCalcResults`, Z. 49095) |
| 1025/1026/1027 | thermisch / hydraulisch / beides ungünstigste Heizfläche | Flags `IsThermalWorst`, `IsHydraulicWorst` |
| 6050 | „Heizfläche … ist relativ klein dimensioniert …" | `PartOfLoad ≤ 80 %` — der Kreis deckt beim gegebenen Vorlauf höchstens 80 % seiner Soll-Leistung (`CalcCircuitKvValues`, Z. 37860) |
| 1021 | „Keinen passenden Ventiltyp gefunden." | kein Katalogventil liefert den kv mit xp ≤ 2 K |
| 1022 / 1023 | Ventiltyp manuell wählen / kv nicht ermittelbar | — |
| 1020 | „Das Ventil kann die Regeldifferenz von 1 K nicht einhalten." | nur xp = 2 K gefunden |
| 1012–1014 | Vorlauf nicht im Bereich / Raumtemperatur fehlt / Soll-Leistung fehlt | — |
| 1028 | „Bitte Unterdeckung von %d Watt decken." | Raumheizlast > Summe der Heizflächen-Soll-Leistungen |
| 1016/1018/1023 (Verteilung) | Pumpe reicht nicht / geregelte Pumpe zu klein / Überströmventil zu niedrig | `FHPumpCalcObject.CheckDistribution` |

Konstanten: Oberflächentemperatur max **29 °C**, min 20 °C (`cMaxSurfaceTemperature`, Z. 21740).

---

## 5. Was im Hilgert-Projekt passiert ist (gemessen)

Projekt „Jonathan Hilgert_Heizlastberechnung (1)", UUID `63A5A101-16F2-377E-9D40-D15541CB1289`,
Gruppe `63A5A101-069F-C97A-ADCE-102564A4483D`. Fußbodenheizung, zwei Verteiler (EG 11 Kreise,
OG 8), Rohr d_i 14 mm, VA 10/12,5 cm, Belag R_B = 0 (`PmCircuitData.CoveringType 1`,
Überdeckung 45 mm), Kessel Weishaupt WTC 25-A mit `MaximalFlowTemperature 45`,
Verteilerzuleitungen 19 m (EG) / 26 m (OG), keine Pumpe („Pumpe nicht vorhanden").

**Die Berichtszahlen sind reproduzierbar** — Beispiele EG, 35 °C (Bericht → Nachrechnung):
Bad EG kv 0,281/Voreinst. 2 → 0,283/2; Bad 2 0,209/1 → 0,209/1; Wohnraum 0,655/3 → 0,662/3;
Küche 2,007 „kein Ventiltyp" → 1,824 „kein Ventiltyp"; Kind 2 „voll offen, hydraulisch
ungünstigste" → dito. Verteilerniveau EG ≈ 270–285 mbar, OG ≈ 80–95 mbar. Die Rechnung des
Kerns ist also **nicht fehlerhaft** — sie rechnet die Eingaben korrekt zu Ende. Die Eingaben
sind das Problem:

1. **Der „35 °C End Zustand"-Bericht stammt aus dem unsanierten Projekt.** Alle drei
   Hilgert-Projekte liegen in der LocalDB. Das Original (`2268A101…`, 23.10.) und die Kopie
   „(1)" tragen Bestands-U-Werte (AW 1,14, Fenster 1,6, Rollladenkasten 4,0), die Variante
   „Jonathan Hilgert_hydraulischer Abgleich 35 °C" (`63A5A101-34F2…`) trägt **sanierte**
   U-Werte (AW 0,20, Dach 0,14, Fenster 0,95). Die Raumheizlasten im 35-°C-Bericht (Küche
   1 840 W, Wohnraum 4 732 W) sind die des **Bestands**; die Variante hätte 1 296 / 4 250 W
   und rechnet mit 1 464 l/h / 658 mbar (EG) statt 2 275 l/h / 1 730 mbar. Der Bericht
   „End Zustand" ist also mit dem falschen Projekt erzeugt worden — oder falsch beschriftet.
   **Die Variante ist aber selbst nicht aktuell:** Räume zuletzt 22.07.2026 bearbeitet,
   Optimus-Lauf vom 20.09.2026, drei Kreise ohne Normleistung, Zuleitungen 15/20 m × 16 mm
   statt 19/26 m × 15 mm. Die Nachrechnung trifft ihre DB-Werte deshalb nicht (983/774 gegen
   658/179 mbar) — ihre Zahlen taugen nicht als „Ergebnis saniert", sie muss neu gerechnet
   werden.
2. **Heizlast 98 W/m² Gesamtgebäude, Küche 222 W/m²** (1 841 W auf 8,3 m²). Eine
   Fußbodenheizung liefert bei 35/30 °C und R_B = 0 höchstens ~50 W/m²; der Kern reagiert
   folgerichtig mit ΔT = 5 K (Minimum), 6 l/min durch 60 m 14-mm-Rohr, „kein passender
   Ventiltyp", „>100 W/m²" und „zu klein dimensioniert" in fast jedem Raum.
3. **Angrenzungsfehler in der Heizlast.** 11 Innenwände (`IW …`, U 2,0, 32 m²) und 3 Innentüren
   (`IT …`, U 2,04) sind mit `BmElementReference.AdjacentType = 3` (= `btaOutside`,
   Außenluft, Fx = 1, ΔT 31 K) angesetzt — zusammen **2 388 W**. Für die Küche sind das 490 W
   (27 % ihrer Heizlast); grenzen die Wände in Wahrheit an den unbeheizten Treppenraum
   (10 °C), wäre es ein Drittel. Außerdem liegt im Wohnraum EG eine 8,15 m² große
   Betondecke `Boden OG1 002-29` (U 2,97) als **Dach gegen Außenluft** (865 W); über dem
   Wohnraum liegen aber die 13-°C-„Dachräume" des OG1, nicht der Himmel. In der sanierten
   Variante bleiben genau diese Fehler stehen (IW weiterhin U 2,0) und dominieren dann die
   Restheizlast — deshalb kommt auch die Variante nicht unter 1 300 W in der Küche.
4. **Förderhöhe 1 730 mbar — aufgeklärt, kein Rechenfehler.** Das Verteilerniveau
   (ungünstigster Kreis Kind 2: 256 mbar Rohr + 15 mbar Ventil offen) ist plausibel. Der
   Rest ist die **Verteilerzuleitung als Rohr**: beide Verteiler tragen am Vorlaufanschluss
   `InnerDiameter = 0,015` (`PmConnection`, 15 mm; Kern-Standard wären 20 mm), Länge
   `DistanceToPump` 19 m (EG) / 26 m (OG). 2 275 l/h durch 15 mm = **3,7 m/s** →
   ≈ 1 500 mbar; dazu das Niveau → Nachrechnung 1 818 mbar (Bericht 1 730; Abweichung =
   quadrierter Durchfluss-Überhang von 3–5 %). OG: 611 gegen 571. Bei 45 °C: 1 202/149 gegen
   1 070/152. Die Netz-Heuristik (583 mbar) liegt darunter und zählt nicht. Was-wäre-wenn bei
   35 °C: Zuleitung 20 mm → EG 666 mbar, 25 mm → 583 mbar (dann bestimmt die Heuristik).
   **Zwei Eingaben treiben die Zahl:** der Durchfluss (4-fach, weil ΔT auf 5 K geklemmt) und
   der Zuleitungsdurchmesser (15 mm für einen Verteiler mit 11 Kreisen / 98 m² ist unüblich;
   26×3 PE-X hat 20 mm, 28×1,5 Cu 25 mm). Ob die 15 mm eingegeben oder aus einer Vorlage
   übernommen wurden, steht nicht in der Datenbank — am Objekt prüfen.
5. **Kennwert-Zeile „Kennw. HK-Dim. 25 % 1,2 / 50 % 1,6" und „nicht-einheitliche
   HK-Dimensionierung"** stammt aus dem Dimensionierungs-Durchlauf (`Dimensioning = true`,
   `DimDPthkv`, Z. 40668 ff.); Bedeutung der beiden Zahlen nicht nachgelesen.

**Empfehlung für den Kundenfall:** (a) Angrenzungen der IW/IT und der Decke `Boden OG1 002-29`
korrigieren (an unbeheizte Räume, nicht Außenluft) — in Original *und* Variante; (b) den
End-Zustand ausschließlich aus der sanierten Variante berichten; (c) Vorlauf nicht fest
vorgeben (`RatedFlowTemperature` leer lassen), damit Optimus die niedrigste tragfähige
Vorlauftemperatur sucht, statt bei 35 °C in die 5-K-Klemme zu laufen; (d) prüfen, ob die
Kreise wirklich so lang sind (Küche 60 m bei 6 m² Heizfläche — die Heizfläche ist kleiner
als die Raumfläche 8,3 m², das ist richtig, aber `HeatingArea` je Kreis sollte gegen den
Verlegeplan gehalten werden); (e) eine Pumpe eintragen, sonst rechnet der Kern mit der
Anlagenpumpe und schlägt den Anlagenpfad auf jede Verteilung.

---

## 6. Datenmodell in `HsetuPrjData` (gemessen am Projekt)

Alle Tabellen tragen `ProjectUUID`; Zahl „nicht gesetzt" ist der **Sentinel
`-987654321.99`** (als NULL behandeln). Spalten `GeoDesc, EditModeType, StateType, VariantType,
GeneratorType, Stamp*, Sync*, GId, MId, VariantRoot` sind Verwaltungsrauschen.

### Container
- `PrProject` (ShortDesc = Projektnummer, LongDesc = Name, `GroupUUID`; `VariantType 1` =
  Variante). `PrXim` = Modellcontainer je Projekt, `ContainerType 7 = mxtPIM` (Anlage),
  2 = BIM (Gebäude), 4 = SIM, 17 = GIM. `PmPlant.PIMUUID`, `PmCircuit.PIMUUID` → `PrXim.UUID`.

### Anlage (PIM) — die Optimus-Seite
| Tabelle | Inhalt | Verknüpfung |
|---|---|---|
| `PmPlant` | eine Anlage je Projekt; `HydraulicIntegrationType` (Anlagentyp 1–3), `HGenMaximalFlowTemperatureHeating` | `PIMUUID → PrXim` |
| `PmDistribution` | **Verteilung = „Heizkreis" im Bericht**; `FlowTemperature/ReturnTemperature` (Rechenzustand), `RatedFlowTemperature` (fest vorgegeben, >0 = keine Optimierung), `DistributionBranchType` (1 Geräte/Heizkörper, 2 Kreise/FBH, 3 gemischt); **Ergebnisse `VolumetricFlow` [m³/h], `DeltaP` [mbar] = Förderhöhe im Bericht** | `ParentUUID/PlantUUID → PmPlant` |
| `PmDistributionReference` | Mitglieder einer Verteilung: `UUID` = Verteilung, `ReferenceToUUID` = `PmCircuit` oder Verteiler-`PmDevice` (`ReferenceClass TModelSingleCircuit / TModelHeatingDistributor`) | |
| `PmCircuit` | **Fußbodenheizkreis** (`CircuitType 1`). Geometrie/EN 1264: `HeatingArea`, `ResidentialZoneDistance` (VA), `ResidentialZoneHcL` (Rohrlänge = A/VA), `InnerDiameter`, `HeatOutput` (**Normleistung 50/40**), `ResidentialZoneHeatFlowDensity`, `ResidentialZoneSurfaceTemperature`, `RatedAmbientTemperature`; `FlowTemperature/ReturnTemperature/MassFlow/VolumetricFlow/DeltaP` sind der **Normzustand 50/40, nicht das Abgleichergebnis**; `RequiredHeatOutput` nur sporadisch gefüllt | `ParentUUID → PmPlant` (nicht die Verteilung!), `DistributorUUID → PmDevice = PmDistributor` |
| `PmCircuitData` | Aufbau: `CoveringType`, `EmbeddedSystemType`, `DistributionLayerCoverThickness` (0,045 m) | `UUID = PmCircuit.UUID` |
| `PmDevice` | Geräte: Verteiler (`GroupType 1, BasisType 2`, **`DistanceToPump` = Verteilerzuleitung [m]**), Kessel (`GroupType 11`, `FlowTemperature`, `MaximalFlowTemperature`, `ManufactureName`, `CatalogBasisUUID → TcBasis`) | |
| `PmDistributor` | Verteiler-Erweiterung zum Device (`UUID = PmDevice.UUID`): `BranchCount`, `NumberOfCircuits`, `ManifoldDistributorUUID/ManifoldCollectorUUID` (virtuelle IDs, keine Zeilen) | |
| `PmBranch` | **Abgänge des Verteilers**, Ventil denormalisiert: `ValveLongDesc` („Abgang Verteiler"), `ValveKvsValue` (2,4), `ValveKvValue`, `ValveKvSettingAlphanumeric` (Voreinstellung), `ValveDeltaP`; `ParentUUID` = Manifold-ID, `ElementUUID` = Verteiler-Device, `ConElement01RefClass TModelSingleCircuit`. Steht nach dem Speichern — spiegelt den **letzten gespeicherten** Lauf, nicht zwingend den gedruckten Bericht (Hilgert: Werte ≠ beide Berichte) | |
| `PmConnection` | Anschlüsse (`HK VL`, `HV`, …) der Geräte | `ElementUUID → PmDevice` |
| `PmSpace` | Raum im Anlagenmodell (eigene UUID ≠ `BmRoom.UUID`). Die Heizlastspalten (`HeatingLoad`, `FloorHeatingRatedHeatingLoad`, …) waren in beiden Hilgert-Projekten **leer** — der Kern holt die Last zur Laufzeit aus `BmRoom` (`PlantSpace.Heating.RatedHeatingLoad`) | `PmBuildingReference` Typ 22 → `BmRoom` |
| `PmSpaceReference` | `ReferenceToUUID → PmCircuit` (Raum → Kreis) | |
| `PmBuildingReference` | **Brücke PIM ↔ BIM**: `ObjReferenceType 22` = `PmSpace → BmRoom` (ReferenceSpaceUUID = `BmFloor`), **13 = `PmCircuit → BmRoom`**, 32 = `PmDistribution → BmZone`, 7 = Anlage → Gebäude | |
| `PmValve`, `PmRadiator`, `PmPipeline`, `PmPump` | nur bei Heizkörpernetzen/Rohrnetz; bei reiner FBH **leer** | |
| `NmNet*`, `NmRadiator`, `NmValve` | Rohrnetz-Modul (Heizungsnetz-Planer), nicht Optimus | |

### Gebäude (BIM) — die Heizlast-Seite
| Tabelle | Inhalt |
|---|---|
| `BmRoom` | `HeatingType` 1 beheizt / 2 unbeheizt, `InsideTemperature`, `Area`, `Volume`, **`HeatingLoad`, `HeatingRatedHeatingLoad`**, `FloorHeatingRatedHeatingLoad`, `RadiatorRatedHeatingLoad`; `FloorUUID → BmFloor` |
| `BmRoomData` | `HeatingLoadType` (13 = DIN EN 12831 NA 2017), `DINEN12831Load/TransmissionLoad/VentilationLoad/RatedLoad`, `SpecificAreaHeatingLoad` |
| `BmElementReference` | Raum ↔ Bauteil: `ReferenceFromUUID → BmRoom`, `ReferenceToUUID → BmElement`, **`AdjacentType`** (`TTechDataBuildingAdjacentType`: 0 none, 1 beheizt, 2 unbeheizt, **3 Außenluft**, 4 intern, 5 Erdreich, 6 oberste Geschossdecke, 7 Kellerdecke, 8 Nachbargebäude), `AdjacentTemperature`, `Fx`, `UValue`, `TransmissionHeatLossCoefficient`, **`TransmissionHeatLoss`** [W] |
| `BmElement` | `ElementType` (`TTechDataBuildingElementType`: 1 Wand, 2 Tür, 3 Fenster, 4 Geschossdecke, 5 Dach, 11 Bodenplatte, 15 Rollladenkasten), `UValue`, `RepositoryType` (1 = gerechnetes Gebäude, siehe `bmelement-zwei-repositories.md`) |

### Einstellungen und Optionen
- `PrProjectSetting` (`SettingKey`, `SettingValue`) in Gruppen `PrProjectSettingGroup.SettingGroupKey`:
  `OptimusSettingGroup.{TGAOptimusHeatload, FlowTemperature, ReturnTemperature,
  StandardTemperature, MinDeltaP, NoStopCalculation, PlantBoilerType}`,
  `HeatLoadSettingGroup.{HeatLoadCalculationType, OptimusHeatLoadCalculationType,
  ThermalBridgeValue, …}`.
- `PrProjectOption`: `NewCalcType` (= 2 → „neue" Rechnung mit `MinVolumetricFlow`,
  `MinValveAuthority`; Kreis-Δp dann aus `FlowData.Heating.DeltaP` statt `DpPipe`). Hilgert: leer.
- Ventil-/Heizkörperprofile: `PdProfileValve` („Prf. 1", `Presettable`, Katalogbezug),
  `PdProfileRadiator` (Optimus Flach-/Stahl-/Guss-/Rohrradiatoren, `DeltaTheta`,
  `FlowTemperature`).

### Was **nicht** in der Datenbank steht
Durchflüsse, Spreizungen, kv-Werte, Voreinstellungen, Warnungen und die Flags „thermisch/
hydraulisch ungünstigste" sind `TCalcOptimus*CalculationResults` — **Laufzeitobjekte**. In die
DB gelangen nur `PmDistribution.VolumetricFlow/DeltaP/ReturnTemperature` und die
denormalisierten Ventile in `PmBranch` (beim Speichern). **Der gedruckte Bericht ist die
einzige vollständige Aufzeichnung eines Laufs.** `ProjectElementHelper.SaveProjectElements
(petHeatingLoad)` schreibt Heizlast-Projektelemente; für dieses Projekt fanden sich keine Zeilen
in `XmProjectElement/XmProjectContent` (vermutlich Dateien unter `XmProject.ProjectPath`) —
offen.

---

## 7. Selber rechnen und prüfen

- **`skripte/optimus/hsetu_sql.py "<SQL>" [--rows]`** — liest `HsetuPrjData` per pyodbc,
  ersetzt den Sentinel, lässt leere Spalten weg. (`sqlcmd`-Fallen: `-W` und `-y 0` schließen
  sich aus; nvarchar(max) wird ohne `-y 0` bei 256 Zeichen gekappt.)
- **`skripte/optimus/optimus-nachrechnen.py "<Projekt>" [--tv 35] [--kvs 2.4]`** — baut
  § 4 nach (Lastaufteilung, Spreizung, Volumenstrom, Colebrook, Verteilerniveau, kv,
  Voreinstellung, Zuleitungs-Heuristik) und stellt den DB-Werten gegenüber. Voreinstellungs-
  leiter des Neutralventils ist aus dem Bericht abgelesen (1: ≤0,25; 2: ≤0,40; 3: ≤0,70;
  4: ≤1,15; darüber „kein passender Ventiltyp"; 2,4 = voll offen), weil der Ventilkatalog in
  `HsetuAppTimData` liegt.
- **Prüfliste vor jedem Abgleich-Bericht:**
  1. Heizlast je Raum in W/m² — über 120 W/m² beim Bestand und über 60 W/m² nach Sanierung
     nachsehen, woher es kommt (`BmElementReference` nach `TransmissionHeatLoss` sortieren).
  2. `AdjacentType 3` nur bei echten Außenbauteilen; `IW`/`IT`/`Boden` mit 3 sind fast immer
     Zuordnungsfehler.
  3. `PmDistribution.RatedFlowTemperature`: leer = Optimus optimiert; Wert = fest.
  4. `PmDevice.MaximalFlowTemperature` des Kessels kappt den erforderlichen Vorlauf.
  5. `HeatingArea`, `ResidentialZoneDistance`, `InnerDiameter` je Kreis gegen den Verlegeplan.
  6. Ergebnisplausibilität: ΔT = 5,0 K bei allen Kreisen heißt „Vorlauf zu niedrig
     erzwungen"; Förderhöhe > 400 mbar bei FBH → zuerst `PmConnection.InnerDiameter` des
     Verteiler-Vorlaufanschlusses und `PmDevice.DistanceToPump` prüfen (Zuleitung als Rohr),
     dann die Netz-Heuristik; `optimus-nachrechnen.py --di 20` zeigt den Unterschied.
- **Rechenlauf ohne Oberfläche:** `CalculateHeatloadAndHydraulicBalancingCommand` braucht
  `TFWProjectEnvironmentState.ActiveProjectEnvironment`; der Weg über die Brücke aus
  `hsetu-projekt-headless-laden.md` ist dafür der Ansatz, **nicht erprobt**. Mit
  `calculation.WriteLog = true` schreibt der Kern jeden Zwischenwert (DpPipe, kv, Heuristik)
  ins Log — der Weg, um die offene Förderhöhen-Zerlegung zu klären.

---

## 8. Offen

- Bedeutung der Berichtszeile „Kennw. HK-Dim. 25 % 1,2".
- Ablageort der Heizlast-Projektelemente (`petHeatingLoad`).
- Lesezugriff auf `HsetuAppTimData` (Ventil-/Pumpenkennlinien) — Login der Software ermitteln
  oder Katalog per Oberfläche exportieren.
