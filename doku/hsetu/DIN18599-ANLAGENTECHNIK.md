# DIN 18599: wo die Anlagentechnik steckt und wie man sie setzt

Stand 09.08.2026. Untersucht an `energieberatung/isfp/Jan Malte Strackerjan_iSFP (1).sqproj`
(15,4 MB) und der LocalDB `(localdb)\HSETU`.

**Die Kurzfassung:** Die Anlagentechnik der DIN-18599-Berechnung liegt **nicht in
der Datenbank**, sondern als serialisierter Objektgraph in einem Medienobjekt. Sie
lässt sich lesen und schreiben — über die vorhandene Brücke, mit Fabrikmethoden des
Datenmodells. Der Weg über SQL führt ins Leere.

---

## 1. Der Irrweg zuerst: die `Pm*`-Tabellen

Naheliegend wäre, es wie bei den Bauteilen zu machen: Zeilen schreiben. Dafür gibt es
sogar den passenden Baukasten — `PmHeatingBoiler`, `PmHeatPump`, `PmDistrictHeating`,
`PmBlockTypeThermalPowerStation`, `PmStorage`, `PmSolarCollector`, `PmTubeHeater`, rund
hundert `Pm*`-Tabellen mit vollständigem Schema (`FuelType`, `RatedThermalCapacity`,
`StandbyLoss70`, `InstallationType` …).

**Sie werden nicht benutzt.** Gemessen:

| Prüfung | Ergebnis |
|---|---|
| `PmPlant` im Projekt | 1 Zeile, **jeder** Wert auf Sentinel `-987654321,99` |
| `PmHeatingBoiler` im Projekt | 0 Zeilen |
| `PmHeatingBoiler` in der ganzen LocalDB | 8 Zeilen — **keine mit einem echten Wert** |
| Belegt sind nur | `PmSpace` (Räume aus der Geometrie), `PmSpaceArea`, `PmBuildingReference` |

`PmBuildingReference` verankert die Anlage am Gebäude (`ReferenceFromUUID` → `PmPlant`,
`ReferenceToUUID` → Gebäudeobjekt). Für die Energieberatung spielt das keine Rolle; die
`Pm*`-Familie gehört zu den TGA-Programmen der Suite, nicht zum Energieberater.

---

## 2. Wo sie wirklich liegt

> **Nachtrag 12.08.2026 — der Anhang ist nur die Kopie.**
> Das Modell steht **zweimal** in der Datenbank, und die Quelle ist nicht der Anhang:
>
> | Ort | Anzahl | Rolle |
> |---|---|---|
> | `eberater.zip` → `TableZusatz`, Feld **`Kernel18599V5`** | **eine je Variante** | **Quelle.** Jede Variante führt ihr eigenes vollständiges DIN-18599-Modell. |
> | `PrMedia` → `Kernel18599V5.bin` | eine je Projekt | Ableitung des gerade aktiven Modells, wird beim Speichern neu erzeugt |
>
> Belegt am Projekt „Werner Grotz": das Feld im Ist-Satz war **byte-identisch** mit dem
> Anhang (116.350 B). Und wer nur den Anhang schreibt, sieht in der Software **nichts** —
> beim nächsten Öffnen überschreibt sie ihn aus dem Satz. Genau so geschehen: nach dem
> Schreiben des Anhangs (115.543 B) stand dort wieder die alte Fassung (99.502 B).
>
> Das Feld ist ein `4/75`-Memo (uint32-Länge, siehe
> [`SANIERUNGSVARIANTEN.md`](SANIERUNGSVARIANTEN.md) Abschnitt 8). **Rohbytes schreiben,
> nicht über eine Zeichenkette** — CP1252 bildet fünf Bytewerte nicht ab und würde den
> BinaryFormatter-Graphen zerstören.
>
> Praktische Folge: **Varianten können eigene Anlagentechnik haben.** Der Weg führt über
> `TableZusatz` der jeweiligen Variante, nicht über `PrMedia`.

In `PrMedia`, als Anhang am Projekt:

| Spalte | Wert |
|---|---|
| `MediaName` | `Kernel18599V5.bin` |
| `MediaVersion` | `4.99.797.0` |
| `LongDesc` | `IBP-Kernel 4.99.797.0` |
| `Media` (BLOB) | 116.126 Bytes im untersuchten Projekt |
| `ProjectMediaType` | `IsEb` (Energieberatung) |

Der Inhalt ist ein **.NET-BinaryFormatter-Strom**:

```
00 01 00 00 00 FF FF FF FF 01 00 …    SerializationHeaderRecord
0C 02 00 00 00 57                     BinaryLibrary, Länge 0x57
"DIN18599DataModel, Version=4.99.797.0, Culture=neutral,
 PublicKeyToken=2e97b4b9aa1493d9"
```

Wurzeltyp: `DIN18599DataModel.P0GeneralModel.DIN18599Building`. Das Assembly stammt vom
**Fraunhofer-Institut für Bauphysik**; Hottgenroth rechnet DIN 18599 nicht selbst
(`Hsetu.EbCalc.IbpKernel` sagt das in seiner eigenen Selbstauskunft). Der ganze
IBP-Kern liegt dekompiliert unter `fremd/` — `DIN18599DataModel.cs`,
`DIN18599P58CalculatorV3.cs`, `IBP18599kernelGEG20.cs`, `IBP18599kernelNavigator2024.cs`.

### Die Rechenkette liest nur

Aus `Hsetu.EbCalc.IbpKernel`:

```
GetBinaryDataFromModelStep      sucht in pProject.Media das Objekt mit
                                ProjectMediaType.IsEb && SrcName == "Kernel18599V5.bin",
                                nimmt GetDALData() als Stream
LoadProjectToKernelStep         deserialisiert -> base.Building
StartDin15899_Geg24_Kernel…Step rechnet (Strategien Geg20 / Geg23 / Geg24 / Lca)
FillCalcResult…Step             schreibt Ergebnisse ins Modell
```

**Nichts baut den Graphen aus der Geometrie neu auf.** Was im Blob steht, wird
gerechnet — und nur das.

---

## 3. Der Aufbau des Graphen

Zweischichtig, wie der Bauteilkatalog: ein **Typenpool** am Gebäude und
**Komponenten**, die darauf zeigen. Deshalb heißen die Einträge in der Oberfläche
„Erzeugertyp 1", „Speichertyp 1", „Übergabetyp 1", „Leitungstyp 1".

```
DIN18599Building
├── Zones                IBPHashtable  →  P0Zone ("Wohnen", fA_N_c, BoundaryCondition, …)
├── Constructions        IBPHashtable  →  P2Construction (U-Wert)
├── Windows              IBPHashtable  →  P0Window
│
├── P58Generators        Typenpool     →  P58HeatGeneratorBoiler, …HeatPump, …
├── P58Storages          Typenpool     →  P58Storage (fV_s, sAgeStorage)
├── P58Emissions         Typenpool     →  P5HeatEmissionWaterRadiator, P8DHWEmission
├── P58CircuitPipes      Typenpool     →  P58CircuitPipe (enumPipeInsulation)
├── P58CircuitPumps      Typenpool     →  P58CircuitPump
│
├── UnitHeating          →  P5HeatGenerationUnit ─┬─ Generators [Komponenten]
├── UnitDHW              →  P8DHWGenerationUnit   ├─ Storage
├── CircuitHeatWater     →  P5HeatWaterCircuit    └─ StorageDistribution
└── CircuitDHW           →  P8DHWCircuit
```

Eine **Komponente** (`P58HeatGeneratorBoilerComponent`) hängt in der Einheit und zeigt
über `Generator` (Objektverweis) und `strGeneratorID` auf den **Typ** im Pool
(`P58HeatGeneratorBoiler`). Die Normparameter des Kesseldialogs sitzen auf der
Komponente, die Bauart auf dem Typ:

| Dialogfeld | Ort | Name |
|---|---|---|
| Typ (Brennwert-Kessel) | Typ | `enumBoilerType` (4 = Brennwert) |
| Baujahr | Typ | `sGeneratorAge` |
| Nennleistung Q_N | Typ | `fQdot_N` |
| Betriebsbereitschaftsverlust q_B,70 | Komponente | `fq_B70` (+ `bq_B70_Standard`) |
| Wirkungsgrad Teillast η_k,pl | Komponente | `feta_k_Pint` (+ `beta_k_Pint_Standard`) |
| Wirkungsgrad Nennleistung η_k,100 | Komponente | `feta_k_Pn` (+ `beta_k_Pn_Standard`) |
| P_aux Nennleistung / Teillast / Schlummer | Komponente | `fP_aux_Pn` / `fP_aux_Pint` / `fP_aux_P0` |
| Pumpenmanagement | Komponente | `enumPumpmanagement` |
| „verbesserte Standardwerte" | Komponente | die `b…_Standard`-Schalter |
| Warmwasser „über Heizungs-Heizkessel" | Komponente | `strLinkedDHWUnitID` |

Die `b…_Standard`-Schalter sind der Grund, warum q_B,70 = 1,31 % und η = 104,22 % im
Dialog stehen, aber nicht im Blob: sie werden aus Bauart und Baujahr abgeleitet.

### `IBPHashtable` ist keine `IDictionary`

Eigene Klasse. `Count`, Indexer `this[int]` und `this[string]`,
`Add(string pKey, object pObject)`, `Remove`, `GetKeyAt`, `ContainsKey`,
`GetEnumerator`. Wer sie als `IDictionary` behandelt, bekommt `null`.

Und: die Werte des Modells sind **Eigenschaften, keine Felder**, teils auf
Basisklassen. Reflexion muss die Vererbungskette absuchen und beides prüfen.

---

## 4. Nicht selbst zusammenstecken — es gibt Fabriken

Das war der wichtigste Fund. Querverweise, Kennungen und Registrierungen macht das
Modell selbst.

**Am Gebäude** (`DIN18599Building`):

```csharp
P0Zone              NewZone(string pID, string pName)
P0Zone              NewUnheatedZone(string pID, string pName)
P2Construction      NewConstruction(string pID, string pName, float pU)
P0Window            NewWindow(string pID, string pName, …, float pU)
P5HeatGenerationUnit NewUnitHeating(string pID, string pName)
P8DHWGenerationUnit  NewUnitDHW(string pID, string pName)
P5HeatWaterCircuit   NewCircuitHeatWater(string pID, string pName)
P8DHWCircuit         NewCircuitDHW(string pID, string pName)
…  dazu GetZone / GetConstruction / DeleteZone / DeleteAllUnusedConstructions
```

**An der Erzeugereinheit** (`P58GenerationUnit`) — deckt sich Kachel für Kachel mit
dem Konfigurator „Heizwärme-Erzeugung konfigurieren":

| Kachel | Methode |
|---|---|
| Kessel | `NewGeneratorBoiler(pID, pName)` |
| Wärmepumpe | `NewGeneratorHeatPump(pID, pName)` |
| Fernwärme | `NewGeneratorDistrict(pID, pName)` |
| KWK-Anlage | `NewCombinedHeatPowerGeneration(pID, pName)` |
| Gas-WP | `NewGeneratorSorptionHeatPump(pID, pName)` |
| Abluft-WP | `NewGeneratorHeatPumpRV(pID, pName)` |
| + Solar | `NewGeneratorSolar(pID, pName)` |
| Speicher | `NewStorage(pID, pName)` |
| Elektrisch / Einzelöfen / Hallenheizung | `NewGeneratorElectric` / `NewGeneratorFuelDecentral` / `NewGeneratorHallDecentral` |

Dazu `GetGenerator(pID)`, `GetStorage(pID)`, `DeleteGenerator(…)`,
`NewStorageDistribution(…)`.

---

## 5. Was erprobt ist

Alles mit den Werkzeugen unter [`werkzeuge/ibp/`](werkzeuge/ibp/).

**Deserialisieren über die vorhandene Brücke** — ohne eine Zeile neuen Code. Ihr
`AssemblyResolve`-Handler lädt `DIN18599DataModel.dll` selbstständig aus dem
Installationsordner:

```json
{"steps":[
 {"use":"new","type":"System.Runtime.Serialization.Formatters.Binary.BinaryFormatter","register":"bf"},
 {"use":"call","type":"System.IO.File","method":"OpenRead","args":["…/Kernel18599V5.bin"],"register":"strom"},
 {"use":"call","target":{"$ref":"bf"},"method":"Deserialize","args":[{"$ref":"strom"}],"register":"gebaeude"}
]}
```
→ `"$type":"DIN18599DataModel.P0GeneralModel.DIN18599Building"`

**Rundlauf** (`ibp-roundtrip.exe`): lesen → `sGeneratorAge` 2010 auf 2015 → schreiben →
neu lesen. Wert kommt an, Restgraph unversehrt.

**Gerät anlegen** (`ibp-add-boiler.exe`): `NewGeneratorBoiler("", "Zweiter Kessel")` auf
der Heizeinheit, dann `Generator` auf den vorhandenen Pooltyp gesetzt. Ergebnis:

- `Generators`-Liste der Einheit 1 → 2
- `strGeneratorID` wurde beim Setzen von `Generator` **selbst nachgetragen**
- nach Serialisieren und Neulesen ist der Verweis **objektidentisch** mit dem
  Pooleintrag (`ReferenceEquals == true`) — BinaryFormatter schreibt eine Referenz,
  keine Kopie. Die Zweischichtigkeit hält über den Datenträger.
- Restbestand: 1 Speicher, 1 Zone, 28 Bauteile — unverändert

---

## 6. Was nicht erprobt ist

- ~~Ob die Software einen von außen geänderten Blob annimmt.~~ **Beantwortet am
  12.08.2026: ja.** Eine vollständig von außen erzeugte Heizung — Einheit, Kreis,
  Verteilung, drei Leitungen, Pumpe, Erzeuger, Übergabe — wurde eingelesen und
  **behalten**. Siehe Abschnitt 8.
- **Ein Projekt, das nur HottCAD hat.** Dessen Blob ist die Grundlinie von ~46,4 KB und
  enthält **eine leere Standardzone „Wohnen", sonst nichts** — keine Bauteile, keine
  Zonengeometrie. Gemessen an einem Projekt mit 2.234 Geometrieelementen: die
  Geometrie fließt **nicht** von selbst in den Blob. Wer sie überträgt, ist der
  **native** Teil: von 511 verwalteten Modulen bindet nur `Hsetu.EbCalc.IbpKernel` das
  IBP-Modell ein, und das liest bloß; `Energie.exe` dagegen enthält sowohl
  `Kernel18599V5.bin` als auch `DIN18599DataModel` als Zeichenkette. Eine
  Geometrieübernahme müsste man über `NewZone`/`NewConstruction`/`NewWindow` selbst
  nachbauen.
- **BinaryFormatter braucht .NET Framework 4.8.** In .NET 10 gibt es ihn nicht mehr —
  der Weg führt zwingend über die Brücke, nicht über den Agent.

---

## 7. Die beiden Wege der Anlagenerfassung — getrennt

Lange offen, am 12.08.2026 durch Vorher-Nachher-Vergleich entschieden. Im Projekt
wurde über **Erfassung DIN 18599** eine Heizung angelegt; danach der Container
Feld für Feld verglichen.

| Weg | wo | wann |
|---|---|---|
| **DIN 18599** | `Kernel18599V5` (Blob) | „Start Erfassung" im Anlagentechnik-Bild |
| **vereinfacht (DIN 4701-10)** | `TableAnlage`, 36 × `…_ALT` / 18 × `…_NEU` | der alte Erfassungsweg |

**`TableAnlage` bekam durch die DIN-18599-Erfassung nur Beschreibungstexte** — kein
einziges `_ALT`- oder `_NEU`-Feld wurde angefasst:

```
Beschr_Heiz = 'NT-Gebläse-Kessel, Erdgas E'
Beschr_Wass = '|  Keine Warmwasserbereitung vorhanden'
Beschr_Luft = '|  Keine Lüftung vorhanden'
```

Die `_ALT`/`_NEU`-Felder gehören also **ausschließlich** zum vereinfachten Weg. Wer
eine DIN-18599-Anlage setzen will, fasst sie nicht an.

Mitgeschrieben wurde außerdem:

| Tabelle | Änderung | Charakter |
|---|---|---|
| `TableHeizung` | 0 → **1 Satz** | **Ergebnis**, nicht Eingabe |
| `TableResult` | +485 B | Ergebnis |
| `TableZusatz` | +19.825 B | der Blob selbst |
| `TableHausDat` | `Enev09_Parag5` = 0 | Beiwerk |

`TableHeizung` ist die Wärmeflussdarstellung: `Qh 24.408`, `UbergabeQ 4.397`,
`VerteilQ 12.020`, `Erz1QE 49.967`, `Erz1AZ 1,2239` — genau die Zahlen des
Ergebnisbilds. `SANIERUNG = 0` kennzeichnet den Ist-Zustand.

**Geändert wurde nur der Satz des Ist-Zustands.** Die drei Varianten blieben
byte-identisch — jede Variante hat ihre eigene Anlagentechnik.

---

## 8. Eine Heizung von außen anlegen

Am 12.08.2026 durchgeführt. Nachgebaut wurde die Konfiguration aus Abschnitt 7,
ausschließlich über Fabrikmethoden.

### Der Aufbau

```
DIN18599Building
├─ NewHeatGeneratorBoiler(id, "Erzeugertyp 1")     → Typ im Pool
│      enumBoilerType 3            HgBoilerType.LowTemperatureBoiler
│      enumBoilerTypeAdditional 1  HgStandardLowTemperatureBoilerType.BellowBoiler
│      sGeneratorAge 2006          zusammen: "NT-Gebläse-Kessel"
├─ NewUnitHeating(id, "Heizwärme-Erzeugung 1")
│   └─ NewGeneratorBoiler(id, "Erzeuger 1")        → Komponente
│          Generator = Typ         strEnergySource = "Brennstoff_ErdgasH"
│          fQdot_N 14,8            ftheta_VA/RA 70/55
└─ NewCircuitHeatWater(id, "Verteilung 1")
    ├─ NewDistribution(id, …)      enumNetworkType 1, fGamma 0,35
    │     └─ NewPipe() ×3, NewPump() ×1  → auf die Pooltypen zeigen lassen
    └─ NewEmissionHeatWater(id, "Übergabe 1")
           Emission = Radiatortyp  strIDLink = Zonen-ID   fContribution 1
```

Dazu die wechselseitigen Einträge in `alReferenceList`: die Einheit trägt die
Kennung des Kreises, der Kreis die der Einheit.

### Verknüpft wird über Zeichenketten

Nicht über Objektverweise — die trägt der Graph zwar auch, maßgeblich sind aber:

```
strGeneratorID  → P58HeatGeneratorBoiler_1[3035CA0D]   Komponente → Typ im Pool
strEmissionID   → P5HeatEmissionWaterRadiator_1[…]     dito für die Übergabe
strEnergySource → Brennstoff_ErdgasH                   der Brennstoff
strIDLink       → P0Zone_1[4DDF1C4B]                   Übergabe → versorgte Zone
strParentID     → P5HeatWaterCircuit_1[59C04622]       Kind → Elternobjekt
```

Die Brennstoffe liegen fertig im Modell (26 Stück, `Brennstoff_ErdgasH`,
`Brennstoff_Heizoel`, `Brennstoff_Holzpellets`, …) — man legt keine an, man
verweist.

### Die Falle: `pID` darf nicht leer sein

**Das ist der wichtigste Fund.** Mit leerem `pID` legt die Fabrik das Objekt an und
gibt es zurück — trägt es aber **nicht in die Sammlung ein**:

```
NewUnitHeating("", "…")    → Objekt kommt zurück, UnitHeating.Count bleibt 0
NewUnitHeating(id, "…")    → Objekt ist eingetragen
```

Die Sammlungen sind `IBPHashtable`, also nach Kennung geschlüsselt. Ohne Kennung
kein Eintrag, ohne Fehlermeldung. Kennungen folgen dem Muster `Typname_N[HEX8]`
und müssen eindeutig sein.

### Ergebnis: die Software nimmt den Graphen an

Nach dem Schreiben in `TableZusatz.Kernel18599V5` und dem Öffnen der Software:
`UnitHeating 1`, `CircuitHeatWater 1`, `P58Generators 1` — **gelesen und behalten**,
der Blob wuchs sogar (die Software rechnete darauf weiter).

### Aber: die `b*_Standard`-Flags rechnen die Werte neu

Angezeigt wurde die Heizung trotzdem nicht. Die Software schrieb
`Beschr_Heiz = 'Keine Heizung vorhanden'`, und der Vergleich zeigte warum:

```
fQdot_N           14,79574  →  0,01      Kesselleistung praktisch null
fTemperatureRise  42,5      →  -20       Übertemperatur der Heizkörper negativ
feta_k_Pn         0,902552  →  0,855     Wirkungsgrade daraus abgeleitet
```

Alles andere war deckungsgleich mit der Referenz. Die Kennwerte tragen
`b*_Standard = True` („Normwert verwenden"), das Modell leitet sie also selbst ab
und überschreibt jede Vorgabe. Seine Rechnung kam auf null Leistung.

`fTemperatureRise` ist der Fingerzeig: 42,5 = (70 + 55)/2 − 20, also mittlere
Heizkörpertemperatur über Raumtemperatur. **−20 heißt, die Auslegungstemperaturen
kommen in der Rechnung als 0 an** — es fehlt ein Eingang, der noch nicht gefunden ist.

### Was man daraus NICHT machen sollte

Der Versuch, die Flags auszuschalten und alle elf Kennwerte von Hand zu setzen, hat
**die Oberfläche unbrauchbar gemacht** — kein Fenster mehr, nichts anklickbar, der
Prozess musste beendet werden. Das Modell war in einem Zustand, den die Software
nicht darstellen kann.

**Die `b*_Standard`-Flags stehen lassen.** Wer sie ausschaltet, muss *alle*
abhängigen Felder kennen — und die Liste ist nicht bekannt. Der richtige Weg ist,
den fehlenden Eingang für die Auslegungstemperaturen zu finden, damit das Modell
wieder selbst rechnet.

### Das Austauschformat: Anlage lesen und setzen

Am 12.08.2026 gebaut und an drei Projekten geprüft. Zwei Werkzeuge, ein Format:

```
ibp-anlage-lesen.exe  <blob>                → JSON, rund 1,3 KB
ibp-anlage-setzen.exe <blob> <neu> <json>   → baut sie über die Fabrikmethoden
```

Damit wird „Anlage aus Projekt A nach Projekt B übernehmen" zum Zweizeiler. Woher
das JSON stammt — aus einem Projekt oder aus einer externen Quelle — ist für die
Werkzeuge unerheblich.

```json
{
  "heizung": {
    "auslegung": { "vorlauf": 70, "ruecklauf": 55 },
    "erzeuger": [ { "bauart": "Boiler", "typ": 4, "zusatz": 3, "baujahr": 2022,
                    "brennstoff": "Brennstoff_ErdgasH", "leistung_kw": 22,
                    "vorlauf": 70, "ruecklauf": 55 } ],
    "speicher": [ { "baujahr": 2006, "zirkulation": true, "gleicher_raum": true } ],
    "uebergabe": [ { "bauart": "WaterRadiator", "regelung": 3,
                     "raumhoehe": 3, "anteil": 1 } ],
    "verteilung": { "netz": 1, "netz_heizung": 0, "gruppe": 0,
                    "gamma": 0.35, "heizkoerper": 1, "pumpen": 1,
                    "abgleich": 0, "abgleich_pumpe": false,
                    "pumpe_regelung": 1, "pumpe_auslegung": 1,
                    "leitungen": [ { "art": 2, "lage": 1, "daemmung": 2 },
                                   { "art": 1, "lage": 1, "daemmung": 2 },
                                   { "art": 0, "lage": 1, "daemmung": 2 } ] }
  },
  "warmwasser": {
    "erzeuger": [ { "bauart": "LinkedToHeating", "brennstoff": "Brennstoff_ErdgasH" } ],
    "speicher": [ { "baujahr": 2006, "zirkulation": true } ],
    "verteilung": { "netz": 0, "zirkulation": 1, "gruppe": 0, "zentral": 0 }
  }
}
```

`uebergabe` ist eine **Liste** — ein Heizkreis kann Heizkörper und eine
Flächenheizung im Bad nebeneinander führen. Ein einzelnes Objekt wird weiter
angenommen. `bauart` darf kurz (`"HeatPump"`) oder als voller Klassenname
(`"P58HeatGeneratorHeatPump"`) stehen; der Leser schreibt den vollen Namen,
weil die Kurzform nicht immer eindeutig umkehrbar ist.

**Das Format ist bewusst schmal.** Es enthält nur, was zum Anlegen nötig ist.
Wirkungsgrade, Hilfsenergie, Leitungslängen und Speichervolumen stehen **nicht**
drin — die rechnet das Modell aus den `b*_Standard`-Flags selbst, und sie
vorzugeben hat die Oberfläche unbrauchbar gemacht.

### Die Auslegungstemperatur hängt am Heizkreis

**`P5HeatWaterCircuit.ftheta_VA` / `.ftheta_RA`.** Das ist der Wert, den die
Oberfläche unter „Verteilung" anzeigt, und der einzige, aus dem gerechnet wird.

Das hat vier Anläufe gekostet. Gesetzt wurden nacheinander:

| gesetzt an | Wirkung |
|---|---|
| `P58HeatGenerator…Component.ftheta_VA` | eigenes Feld des Erzeugers, ändert die Anzeige nicht |
| `…HeatPumpComponent.ftheta_si_out/in` | Senke der Kennlinie, ändert die Anzeige nicht |
| `P5HeatGenerationUnit.ftheta_VA` | **schreibgeschützt**, der Schreibversuch lief ins Leere |
| **`P5HeatWaterCircuit.ftheta_VA`** | **das ist es** |

Dreimal stand danach unverändert 70/55 in der Oberfläche. Gefunden wurde es erst,
als der genaue angezeigte Wert bekannt war: 70/55 ist der **Vorgabewert** des
Modells, also war das Feld nie beschrieben worden — keine Fehlrechnung, sondern
eine nie berührte Stelle. Eine Zahl im Klartext war dabei mehr wert als drei
Vermutungen.

Erhoben an 84 Projekten der LocalDB:

- **Der Kreis ist unabhängig vom Erzeuger.** Ein Projekt führt Kreis 80/60 neben
  Kessel 70/55, ein weiteres Kreis 66/51 neben Kessel 70/55. Wer die
  Auslegung in der Oberfläche ändert, ändert den **Kreis**; der Erzeuger bleibt
  auf seinem Wert.
- **`0/0` heißt „nie gesetzt"** und ist nicht dasselbe wie 70/55. Das Modell
  rechnet dann mit 70/55. Der Schreiber fasst den Kreis deshalb nur an, wenn die
  Austauschdatei einen `auslegung`-Block trägt.
- **Die Übertemperatur der Übergabe folgt dem Kreis:**
  `fTemperatureRise = (Vorlauf + Rücklauf) / 2 − 20`. Bestätigt an 12 von 12
  Projekten mit gesetztem Kreis, auch an den schiefen: 80/60 → 50, 66/51 → 38,5,
  55/45 → 30. **Nur bei Heizkörpern** — bei Flächenheizung steht das Feld in
  allen 15 erhobenen Projekten auf 0, obwohl der Kreis dort 35/28 führt.
- **Die Senke der Wärmepumpe (`ftheta_si_out/in`) nicht mitziehen.** In allen 24
  Wärmepumpenprojekten steht sie auf 60/50, auch bei Kreis 35/28 — die Software
  fasst sie nie an. Sie beschreibt den Prüfpunkt der Kennlinie, nicht die
  Betriebstemperatur. Wer sie mitzieht, verbessert die Arbeitszahl gegenüber dem,
  was die Software selbst rechnen würde. Nur auf ausdrückliche Angabe
  (`senke_vorlauf`) setzen.

### Nichts stillschweigend ersetzen

Der Rundlauf **lesen → löschen → setzen** über alle 84 Projekte hat drei stille
Ersetzungen aufgedeckt, die keine einzige Meldung erzeugt hatten:

| was verschwand | wodurch |
|---|---|
| Solaranlage, Einzelofen, Sorptionswärmepumpe (13 Projekte) | `wp = art == "HeatPump"`, sonst Kessel |
| eine zweite Übergabe im Kreis (1 Projekt) | der Leser kannte nur `Emissions[0]` |
| die ganze Warmwasser-Verteilung (Grotz) | Leser **und** Schreiber kannten sie nicht |

Der letzte Fall ist der lehrreichste: **beide Seiten waren blind an derselben
Stelle**, deshalb war der Rundlauf in sich stimmig und meldete nichts. Ein
Rundlaufvergleich findet nur, was mindestens eine Seite kennt — gegen beidseitige
Blindheit hilft nur der Abgleich mit einem realen Projekt.

Daraus die Regel im Schreiber: **eine Bauart, die sich keiner Fabrik zuordnen
lässt, bricht ab.** `Fabrikname()` erfragt die Fabriken zur Laufzeit am Modell
(`New<Vorsatz><Bauart>`) und nennt im Abbruch alle möglichen Werte. Nichts wird
durch einen Vorgabewert ersetzt.

### Vorgabesatz Wärmepumpe

`ibp/vorgaben/waermepumpe-sanierung.json` — anzuwenden, wenn zum Projekt keine
weiteren Angaben vorliegen. Fachliche Vorgabe, gedeckt durch die Erhebung:

| | Wert | Feld | Beleg |
|---|---|---|---|
| Auslegung | 55/45 °C | `P5HeatWaterCircuit.ftheta_VA/RA` | fachlich gesetzt |
| hydraulischer Abgleich | ja | `enumHydraulicBalance = 2` (`Option3`) | **24 von 24** WP-Projekten |
| … an der Pumpe | ja | `bHydraulicBalance = true` | **18 von 18** mit Pumpe |
| Netzform Heizung | Etagenring | `enumNetworkTypeHeating = 0` (`StoreyRing`) | 22 von 24 |
| Gebäudegruppe | Gruppe 1 | `enumBuildingGroup = 0` | 24 von 24 |
| Pumpenregelung | delta-p variabel | `enumPumpControl = 2` | fachlich gesetzt |
| Pumpenauslegung | optimiert | `enumDimensioningPump = 1` | 24 von 24 |
| Übergabe | Heizkörper, PI-Regler mit Optimierung | `HceControlTypeRadiator = 5` | fachlich gesetzt |
| WW-Netz | zentral, Steigestrang | `enumNetTypeDHW = 0`, `enumDistributionType = 0` | 60 von 66 |
| WW-Zirkulation | ohne | `enumCirculation = 1` (`WithoutCirculation`) | 24 von 24 WP |
| WW-Gruppe | Gruppe 1 | `enumBuildingGroup = 0` | 66 von 66 |

Die Pumpenauslegung ist der einzige Punkt, an dem der Vorgabesatz von dem
abweicht, was ein frisch angelegter Kreis mitbringt: die Fabrik setzt
`Oversized`, alle 24 Referenzprojekte führen `Optimized`. Eine neu eingebaute
Pumpe ist ausgelegt, nicht überdimensioniert.

Zum Warmwassererzeuger: der Vorgabesatz führt eine eigene `HeatPump`. Macht
**eine** Wärmepumpe beides, ist `LinkedToHeating` der sauberere Weg — dann hängt
das Warmwasser an derselben Erzeugerkomponente.

### Warmwasser: meist `LinkedToHeating`

Der häufigste Fall im Bestand — das Warmwasser hängt am Heizkessel und hat keinen
eigenen Erzeuger:

```csharp
var k = einheit.NewGeneratorLinkedToHeating(id, name);
k.LinkedGenerator = heizErzeuger;   // die KOMPONENTE, nicht nur die Einheit
```

`LinkedUnit` ist schreibgeschützt — **das Modell trägt sie selbst nach**, sobald
`LinkedGenerator` gesetzt ist. Dasselbe Muster wie bei `strGeneratorID`, das sich
beim Setzen von `Generator` füllt. Ein Schreibversuch darauf ist blinder Alarm.

Das Speichervolumen `fV_s` ebenso: `bV_s_Standard` steht auf `True`, das Modell
leitet es aus der Nutzfläche ab (gemessen: 107,69 l).

### Die Leitungsart entscheidet über die Länge

`HdPipeType` am Leitungs**bauteil**, nicht am Typ:

| | | im untersuchten Projekt |
|---|---|---|
| `2` | `ConnectionPipe` — Anbindeleitung | 27,03 m |
| `1` | `RiserPipe` — Steigstrang | 4,80 m |
| `0` | `DistributionPipe` — Verteilleitung | 194,80 m |

Mit `bL_Standard = True` leitet das Modell die Länge **je Art** aus der Geometrie
ab. Bleiben alle drei auf 0, sind sie alle Verteilleitung — gemessen kamen dann
**584 m** statt 227 m heraus, mit Verteilverlusten von 32.906 statt 12.020 kWh und
einer Endenergie von 78.854 statt 50.836 kWh.

### Was der Nachbau erreicht hat

Nach der Korrektur zeigt der Dialog der Software dieselben Werte wie bei der eigenen
Erfassung — Leitungen 27/5/195 m, `max. 56 m`, `69 W`, 51 °C, Nutzenergie 24.500,
Verteilung 12.000, Endenergie 50.000. Die Restabweichung in den ungerundeten Summen
beträgt **0,07 %** und stammt aus den abgeleiteten Werten.

### Wiederherstellung, wenn die Oberfläche hängt

```powershell
Get-Process -Name Energie | Stop-Process -Force     # Handle=0, kein Fenster
# dann eberater.zip UND Kernel18599V5.bin aus dem letzten guten Stand zurueckschreiben
```

Der letzte gute Stand ist der, den die **Software selbst** geschrieben hat —
`werkzeuge/ibp/referenz-heizung-konfiguriert.bin` ist ein solcher.

---

## 9. Werkzeuge

| Datei | Zweck |
|---|---|
| `werkzeuge/ibp/ibp-anlage-lesen.exe` | **Anlage als JSON auslesen** — Heizung, Speicher, Warmwasser |
| `werkzeuge/ibp/ibp-anlage-setzen.exe` | **Anlage aus JSON anlegen** — Gegenstück dazu |
| `werkzeuge/ibp/ibp-bauteile.exe` | Bauteilbestand klassifiziert: Art, Ausrichtung, Fläche, U-Wert |
| `werkzeuge/ibp/ibp-matrix.exe` | die Beziehungsmatrix Einheit ↔ Kreis untersuchen |
| `werkzeuge/ibp/ibp-api.exe` | **alle Fabrikmethoden und Aufzählungen auflisten** (`<blob> [filter] [praefix]`) |
| `werkzeuge/ibp/ibp-heating.exe` | die Anlagentechnik vollständig auslesen; `--sammlungen` zeigt erst die Sammlungen des Gebäudes |
| `werkzeuge/ibp/ibp-build-heating.exe` | **eine komplette Heizung über die Fabriken anlegen** |
| `werkzeuge/ibp/ibp-dump.exe` | einen Blob lesbar ausgeben (`<datei> [tiefe] [aeste]`) |
| `werkzeuge/ibp/ibp-roundtrip.exe` | ändern und zurückschreiben, mit Gegenprobe |
| `werkzeuge/ibp/ibp-add-boiler.exe` | ein Gerät in eine vorhandene Einheit setzen |
| `werkzeuge/ibp/referenz-heizung-konfiguriert.bin` / `.txt` | Blob **mit** funktionierender Heizung + vollständiger Auszug — der Maßstab für jeden Vergleich |
| `werkzeuge/ibp/beispiel-kernel18599.bin` | der zuerst untersuchte Blob |
| `werkzeuge/bdexit/hole-kernel.ps1` | **den Blob einer Variante herauslösen**; ohne `-Proj` listet es, welche Variante überhaupt ein Modell führt |
| `werkzeuge/bdexit/setze-kernel.ps1` | den Blob in `TableZusatz.Kernel18599V5` einer Variante schreiben (Rohbytes) |
| `werkzeuge/bdexit/zeige-heizung.ps1` | **Wirkungsprobe Anlagentechnik** — Endenergie je Variante aus `TableHeizung`, mit `-Fahrplan` als Verlauf |
| `werkzeuge/sqproj-lesen.php` | eine `.sqproj` untersuchen (Tabellen, Spalten, Suche) |

**Die Wirkungsprobe der Anlagentechnik ist `TableHeizung`, nicht `UA`.** Eine
Wärmepumpe ändert keinen U-Wert, `pruefe-variante.ps1` sieht sie also nicht. Und
**kein Satz heißt nicht gerechnet**: der Blob wird beim Anlegen einer Variante
mitkopiert, jede Variante führt daher meist ein Modell — erst der Satz in
`TableHeizung` belegt, dass die Software darauf gerechnet hat.

**Namen nicht raten.** `ibp-api.exe` listet 746 Typen mit ihren `New*`-Methoden und
allen Aufzählungen; `ibp-heating.exe --sammlungen` zeigt, wie die Sammlungen des
Gebäudes wirklich heißen (der Heizkreis heißt `CircuitHeatWater`, nicht `Circuits`).

**Vor jedem Schreiben vergleichen.** `ibp-heating.exe` auf den eigenen Blob und auf
`referenz-heizung-konfiguriert.txt`, dann `Compare-Object`. Beim Nachbau blieben so
nur elf abgeleitete Kennwerte übrig — alles Strukturelle war deckungsgleich, und das
war vor dem ersten Schreibversuch bekannt.

Bauen: `csc.exe` aus `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319`, `/platform:x64`.

Blob aus der LocalDB holen:

```powershell
$c = New-Object System.Data.SqlClient.SqlConnection "Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true"
$c.Open(); $k = $c.CreateCommand()
$k.CommandText = "SELECT Media FROM PrMedia WHERE ProjectUUID='…' AND MediaName='Kernel18599V5.bin'"
[System.IO.File]::WriteAllBytes("blob.bin", $k.ExecuteScalar()); $c.Close()
```
