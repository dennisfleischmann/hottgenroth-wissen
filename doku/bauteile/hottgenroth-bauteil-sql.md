# Bauteile in Hottgenroth per SQL anlegen

Wie man einen Bauteilaufbau (Wandschichten mit U-Wert) direkt per `INSERT` in die
Hottgenroth-/ETU-Datenbank schreibt, statt ihn in der GUI zu klicken.

> **Status: verifiziert.** Am 06.08.2026 wurde `BEISPIEL-Aussenwand-WDVS-16cm` per
> `insert-bauteil-strackerjan.sql` in das Projekt „Jan Malte Strackerjan_iSFP (1)"
> geschrieben und erschien nach einem Neustart korrekt im Bauteilkatalog der Software.

Das Schema ist von Hottgenroth nicht dokumentiert. Alles hier stammt aus einem
SQL-Trace der laufenden Software plus Datenbank-Snapshots — siehe [Abschnitt 10](#10-woher-das-wissen-stammt).

---

## 1. Schnellstart

Referenzskript: [`../tools/insert-bauteil-strackerjan.sql`](../tools/insert-bauteil-strackerjan.sql).
Für ein neues Bauteil reicht es, drei Dinge darin zu ändern.

**a) Projekt-GUID** ermitteln und oben eintragen:

```sql
SELECT UUID, LongDesc FROM PrProject WHERE LongDesc LIKE '%Suchbegriff%';
```

**b) Name** in `@BauteilName` setzen.

**c) Schichten** in der Tabellenvariable `@L` definieren — von **innen nach außen**:

```sql
INSERT INTO @L VALUES
--SortNum, UId,     Name,                    λ,     d(m),  ρ,    c,   µu, µo,  Grp, LayerT, MatT, KatPfad
 (0, NEWID(), N'Gipsputz ohne Zuschlag',     0.51,  0.015, 1200, 1.0, 10,  35, 1,   0,      0,    N'1.1.2'),
 (1, NEWID(), N'Kalksandstein …',            0.99,  0.240, 1800, 1.0,  5,  15, 4,   0,      0,    N'4.1.2'),
 (2, NEWID(), N'Polystyrol PS …',            0.035, 0.160,   30, 1.5, 80, 250, 5,   3,      1,    N'5.5.1.1.1.2'),
 (3, NEWID(), N'Putzmoertel …',              0.70,  0.005, 1400, 1.0, 15,  35, 1,   0,      0,    N'1.1.1');
```

Alles Weitere — `ElementMeta`, die Layer-Zeilen, die R-Werte je Schicht — erzeugt das
Skript daraus selbst. Nur die drei Gesamtkennwerte oben musst du noch ausrechnen und
eintragen (`@Thickness`, `@RValue`, `@UValue`, siehe [Abschnitt 8](#8-kennwerte-berechnen)).

**Materialdaten** (λ, ρ, c, µ) kommen aus `hottgenroth-baustoffkatalog.csv` auf dem
Desktop. Praktisch: die dortige Spalte `GruppeNr` ist direkt der Wert für `MatGruppe`.

**d) Ausführen** — die Software vorher schließen:

```
sqlcmd -S "(localdb)\HSETU" -i mein-bauteil.sql
```

**e) Prüfen** — Software starten, Projekt öffnen, Bauteilkatalog → Ordner
„=== Benutzerdefinierte Bauteile ===". Ein Neustart ist zwingend: die Software liest
den Katalog beim Laden und merkt nichts von Änderungen an der DB im laufenden Betrieb.

---

## 2. Umgebung

| | |
|---|---|
| SQL-Instanz | `(localdb)\HSETU` |
| Projekt-DB | `HsetuPrjData` — Bauteile **innerhalb eines Projekts** |
| Benutzer-DB | `HsetuUsrData` — „Meine Bauteile", projektübergreifend |
| Projekttabelle | `PrProject`, Primärschlüssel heißt **`UUID`** (nicht `UId`) |
| App-Version | Modul `6.6.0`, DAL `17.3` (steht in jeder Zeile in `SyncMeta`) |

Die Projektzuordnung läuft über `ProjectUId`. Für „Meine Bauteile" in `HsetuUsrData`
wird dort stattdessen die Null-GUID gesetzt (siehe `insert-bauteil-meine.sql`).

---

## 3. Wie es funktioniert: das Datenmodell

Ein Bauteil verteilt sich auf sechs Tabellen:

```
TcCatalog                                  1 Bauteilkatalog pro Projekt
   │  UId ─────────────────────────────┐
   │                                   │
   └─< TcCatalogContent                │   Ordner im Baum
         │  (CatalogUId ───────────────┘   "=== Benutzerdefinierte Bauteile ==="
         │   CatalogContainerType = 6, ContentLevel = 7, ContentType = 1)
         │
         └─< TcCatalogContents             Baum-Eintrag = macht das Bauteil SICHTBAR
               │  CatalogContentUId → TcCatalogContent.UId
               │  CatalogUId        → TcCatalog.UId
               │  BasisUId          → TcBasis.UId
               │  DimensionUId      = NullGuid (!)
               ▼
TcBasis                                    Stammsatz: Identität, Typ, Name
   │  UId
   ▼
TcBuildingElementDimension                 Kennwerte: U, R, Dicke, ElementMeta
   │  BasisUId → TcBasis.UId
   │  UId
   ▼
TcBuildingElementDimensionLayer            n Schichten, Reihenfolge über SortNum
      DimensionUId → TcBuildingElementDimension.UId
```

Zwei Dinge daran sind nicht offensichtlich:

**`TcCatalogContents.DimensionUId` bleibt die Null-GUID.** Der Katalogeintrag zeigt
ausschließlich über `BasisUId` auf das Bauteil; die Dimension hängt ihrerseits über
ihre eigene `BasisUId` an `TcBasis`. Das ist kein Versehen — die Software schreibt es
selbst genau so.

**`TcCatalogContents` ist der Sichtbarkeits-Schalter.** `TcBasis` + `Dimension` +
`Layer` allein ergeben ein vollständiges, korrekt berechnetes Bauteil, das in der UI
aber nirgends auftaucht. Fehlt der Baum-Eintrag, sucht man vergeblich.

`TcBuildingElementDimensionLayerSection` existiert für inhomogene Schichten (Gefache
nach EN ISO 6946). Für einfache Aufbauten ungenutzt — `LayerSectionUId` = Null-GUID.

---

## 4. Der Schreibvorgang

### Reihenfolge

1. **`TcCatalog`** — nur falls für das Projekt noch keiner existiert. Liefert
   `CatalogUId` **und `TIMUId`**; beide werden später gebraucht.
2. **`TcCatalogContent`** — der Ordner.
3. **`TcBasis`** — Stammsatz. `LongDesc` = Bauteilname, `TIMUId` aus Schritt 1.
4. **`TcBuildingElementDimension`** — Kennwerte + `ElementMeta`.
5. **`TcCatalogContents`** — Baum-Eintrag.
6. **`TcBuildingElementDimensionLayer`** × n — `SortNum` 0..n-1, 0 = innen.

Bei bestehendem Projekt existieren Katalog und Ordner meist schon. Dann diese auslesen
statt neu anzulegen — das Referenzskript bricht sauber ab, wenn es sie nicht findet:

```sql
SELECT @CatalogUId = UId, @TimUId = TIMUId FROM TcCatalog WHERE ProjectUId = @ProjUId;
SELECT @CatContentUId = UId FROM TcCatalogContent
 WHERE CatalogUId = @CatalogUId AND CatalogContainerType = 6;
```

### Wie die Software selbst schreibt

Aus dem Trace: die Software arbeitet **zweiphasig**. Erst ein `INSERT`, der die Zeile
mit komplett leeren Werten anlegt (alle Floats `-987654321.99`, `LongDesc = N''`,
`SyncType = 1`), dann ein `UPDATE`, das die fachlichen Werte setzt und `SyncType` auf
`2` zieht.

Die Skripte hier machen beides in einem `INSERT`. Das ist in Ordnung — entscheidend
ist der Endzustand, nicht der Weg dorthin. Das erklärt aber, warum man im Trace
`SyncType = 1` sieht und trotzdem `2` schreiben muss.

---

## 5. Pflichtfelder und Magic Values

Die Software benutzt Sentinel-Werte statt `NULL`. Echte `NULL` führen zu Bauteilen,
die nicht geladen oder falsch gerechnet werden.

| Konstante | Wert | Verwendung |
|---|---|---|
| Null-GUID | `AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA` | leere GUID-Referenz |
| Null-Float | `-987654321.99` | leerer `float` |
| Null-Int | `-999` | leerer `int` (`VDI3805*`, `*NumberOfBars`) |
| Leeres Datum | `1899-12-30T00:00:00` | Delphi/OLE-Epoch |
| Nicht gesetzt | `-1` | `OId`, `SeqNum`, `SortNum`, `FIdx01` |
| `SyncMeta` | `{"meta":{"sync":{"mod":"6.6.0","dal":"17.3"}}}` | in **jeder** Zeile |
| `SyncStamp` | `GETDATE() - 2 Stunden` | bewusst in der Vergangenheit |
| `SyncRowVersion` | `NEWID()` | frische GUID je Zeile |
| `StampCreate` / `StampEdit` | `GETDATE()` | |

`SyncVersion` ist **pro Tabelle verschieden** und muss exakt stimmen:

| Tabelle | `SyncVersion` | `SyncType` |
|---|---|---|
| `TcCatalog` | `1.3.8` | 1 |
| `TcCatalogContent` | `1.3.4` | 1 |
| `TcBasis` | `1.3.1.3` | 2 |
| `TcCatalogContents` | `1.3.3` | 2 |
| `TcBuildingElementDimension` | `1.3.1.5` | 2 |
| `TcBuildingElementDimensionLayer` | `1.3.1.8` | 2 |
| `TcBuildingElementDimensionLayerSection` | `1.3.2.2` | 2 |

Durchgängig außerdem: `GId = UId` (jede Zeile ist ihre eigene Gruppenwurzel),
`MId` = Null-GUID, `VariantRoot` = `N''`, und alle `*Type`-Spalten (`StateType`,
`EditModeType`, `VariantType`, `GeneratorType`, `CatalogStateType`) = `0`.

---

## 6. Typ-Kennzeichnung

In **`TcBasis`** und **`TcCatalogContents`** identisch setzen:

| Spalte | Wert |
|---|---|
| `ElementType` | `2` — bei **allen** Bauteilen, egal welcher Art |
| `GroupType` | grobe Kategorie, siehe unten |
| `CategoryType`, `BasisType`, `SubType` | `0` |
| `UsageType` (nur `TcBasis`) | konkreter Bauteiltyp, siehe unten |

### `GroupType` — grobe Kategorie

| GT | Kategorie |
|---|---|
| 1 | Wand |
| 2 | Tür |
| 3 | Fenster |
| 4 | Boden / Decke |
| 5 | Dach |
| 15 | Rollladenkasten |
| 17 | Fensterbrüstung |

### `UsageType` — der Typ in der Auswahlliste

`GroupType` allein genügt nicht. Was die Software rechts oben als Typ anzeigt, ist die
Kombination aus `GroupType` (Kategorie) und **`TcBasis.UsageType`** (Lage/Angrenzung).

Die Bezeichnungen stammen aus
`C:\Program Files\HSETU\Energieberater2022\Hsetu.ConstructionCatalog.Resources.dll`,
die Zuordnung zu den Zahlen aus der Korrelation mit 5.700 Bauteilen im Bestand.
Vollständig als `hottgenroth-bauteiltypen.csv` auf dem Desktop.

| GT | Usg | Typ in der Software | Bauteile im Bestand |
|---|---|---|---|
| 1 | 1 | Wand gegen beheizt | 201 |
| 1 | 2 | Wand gegen außen | 1.159 |
| 1 | 4 | Wand gegen Erdreich | 352 |
| 1 | 6 | Wand gegen unbeheizt | 224 |
| 2 | 1 | Tür gegen beheizt | 214 |
| 2 | 2 | Tür gegen außen | 561 |
| 3 | 1 | Fenster gegen beheizt | *0 — nicht belegt* |
| 3 | 2 | Fenster gegen außen | 1.326 |
| 4 | 1 | Decke / Boden gegen beheizt | 122 |
| 4 | 2 | Boden gegen außen | 107 |
| 4 | 4 | Boden gegen Erdreich | 524 |
| **4** | **7** | **Decke gegen unbeheizt** — oberste Geschossdecke | 414 |
| 4 | 8 | Boden gegen Keller / unbeh. — Kellerdecke | 395 |
| 5 | 2 | Dach gegen außen | 571 |
| 15 | 2 | Rollladenkasten | 27 |
| 17 | 0 | Fensterbrüstung | 1 |

`UsageType` ist über die Kategorien hinweg konsistent: **1 = gegen beheizt, 2 = gegen
außen, 4 = gegen Erdreich, 6 = gegen unbeheizt (Wand), 7 = Decke gegen unbeheizt
(nach oben), 8 = Boden gegen Keller (nach unten)**. Die Werte 3 und 5 kommen im
Bestand nicht vor.

Die einzige Lücke ist „Fenster gegen beheizt": der Typ existiert in der Auswahlliste,
kommt im Bestand aber nicht vor. `GroupType 3` + `UsageType 1` ist analog zur Tür
naheliegend, aber unbelegt.

Wer `UsageType` aus einem Wandbauteil übernimmt (`2`) und nur `GroupType` auf 4 setzt,
bekommt „Boden gegen außen" statt einer Decke — und dazu die falschen
Übergangswiderstände (0,17/0,04 statt 0,10/0,10).

Alle vier Werte stammen aus dem `UPDATE`, das die Software selbst absetzt. Vor allem
`GroupType = 1` und `LongDesc` ≠ leer sind kritisch: mit `GroupType = 0` oder leerem
Namen in `TcBasis` erscheint das Bauteil nicht im Katalog.

---

## 7. `ElementMeta` — der Legacy-Textblock

`TcBuildingElementDimension.ElementMeta` ist ein CRLF-getrennter Key-Value-Block im
Altformat mit **deutschen Dezimalkommas**. Die Software rechnet daraus — er muss
zwingend zu den Layer-Zeilen passen.

```
RAI=0,13                 ← Rsi
RAA=0,04                 ← Rse
CP10CM=4800
CP3CM=16000
CPEnIso13786=5020
G1S1=<Schicht 1>
G1S2=<Schicht 2>
…
KorrLS=Falsch|0|-1
KorrBe=version2008|Falsch|6|0|0|0|-1|0
KorrUD=Falsch|0|0|0|-1
```

Der Schlüssel `G<n>S<m>` heißt **Section n, Schicht m** — `G` ist der Gefach-Abschnitt,
nicht „Gruppe". Homogene Bauteile haben nur `G1S…`, weil sie aus einem einzigen Schnitt
bestehen. Bei inhomogenen kommen `BEZ<n>` / `ANT<n>` / `ANTWERT<n>` und ein zweiter
Block `G2S…` dazu — siehe [Abschnitt 9a](#9a-inhomogene-bauteile-gefache).

### `G1S<n>` — pipe-getrennte Schichtdefinition

```
G1S1=Gipsputz ohne Zuschlag|0,510000|1,5|10,000000|35,000000|1|1200,000000|Falsch|Falsch|Falsch|0|1.1.2|1,000000|0,000000|0,000000|0,000000|NEIN
```

| # | Beispiel | Bedeutung | entspricht Layer-Spalte |
|---|---|---|---|
| 1 | `Gipsputz ohne Zuschlag` | Materialname | `LongDesc` |
| 2 | `0,510000` | λ [W/mK] | `ThermalConductivity` |
| 3 | `1,5` | Dicke in **cm** | `Thickness` (dort in **m**) |
| 4 | `10,000000` | µ unten | `LowerDiffusionResistanceCoefficient` |
| 5 | `35,000000` | µ oben | `UpperDiffusionResistanceCoefficient` |
| 6 | `1` | Materialgruppe | `MaterialGroupType` |
| 7 | `1200,000000` | Rohdichte [kg/m³] | `Density` |
| 8–10 | `Falsch|Falsch|Falsch` | Flags | `IsVentilated` / `IsCapillary` / `IsVapourDiffusionTight` |
| 11 | `0` | — | |
| 12 | `1.1.6` | Pfad in der Materialdatenbank ([so ermittelt](#katalogpfad-aus-der-datenbank-ableiten)) | (`MaterialClassDesc` bleibt leer) |
| 13 | `1,000000` | c [kJ/kgK] | `HeatCapacity` |
| 14–16 | `0,000000` ×3 | — | |
| 17 | `NEIN` | — | |

**Formatfallen:** Feld 3 ist cm, die Layer-Spalte m. Die Dicke wird ohne
Nachkommanullen geschrieben (`24`, nicht `24,000000`; `1,5`, nicht `1,50`), alle
anderen Zahlen mit sechs Nachkommastellen. Das Referenzskript erzeugt das korrekt aus
der Schichttabelle; ein Trockenlauf lohnt sich trotzdem:

```
sqlcmd -S "(localdb)\HSETU" -d HsetuPrjData -i test-elementmeta.sql
```

**Bekannter Fehler in den Beispielskripten:** Die Katalogpfade in Feld 12 stammen aus dem
ursprünglich abgeschriebenen Bauteil und sind für drei der vier Schichten falsch
(`1.1.2` statt `1.1.6` für Gipsputz, `4.1.2` statt `4.2.5` für Kalksandstein,
`5.5.1.1.1.2` statt `5.5.1.3` für EPS). Das Bauteil rechnet trotzdem korrekt — die
U-Wert-Berechnung nutzt λ und d aus den Layer-Zeilen, nicht den Pfad. Für neue Bauteile
den Pfad aus `hottgenroth-materialbaum.csv` nehmen.

Nicht entschlüsselt: `CP10CM`, `CP3CM`, `CPEnIso13786`. Die Werte lassen sich aus den
Schichtdaten nicht nachrechnen und wurden unverändert aus einem Software-Bauteil
übernommen. Sie scheinen für die U-Wert-Berechnung nicht relevant zu sein.

---

## 8. Kennwerte berechnen

```
Thickness        = Σ Schichtdicken
Layer.RValue     = d / λ                        (je Schicht)
Dimension.RValue = Σ Layer.RValue               ← OHNE Rsi/Rse
UValue           = 1 / (RValue + Rsi + Rse)
```

Am verifizierten Beispiel (Gipsputz 1,5 / KS1800 24 / EPS-035 16 / Putz 0,5 cm):

```
R = 0,0294 + 0,2424 + 4,5714 + 0,0071 = 4,850408
U = 1 / (4,850408 + 0,13 + 0,04)      = 0,199189 W/(m²K)
d = 0,42 m
```

`InternalCoefficientOfHeatTransfer` = `0,13` und `ExternalCoefficientOfHeatTransfer`
= `0,04`: trotz des Namens sind das die **Widerstände** Rsi/Rse, nicht die
Übergangskoeffizienten.

---

## 9. Schicht-Enums

| Spalte | Wert | Bedeutung |
|---|---|---|
| `LayerType` | `0` | normale Schicht |
| | `2` | belüftete Luftschicht (λ = 0, R = 0) |
| | `3` | Dämmschicht |
| `MaterialType` | `0` | Standard |
| | `1` | Dämmstoff |
| `SortNum` | `0..n-1` | **0 = innen**, aufsteigend nach außen |

### `MaterialGroupType` — die acht Baustoffgruppen

| Nr | Gruppe | Materialien im Katalog |
|---|---|---|
| 1 | Putze | 475 |
| 2 | Beton | 82 |
| 3 | Bauplatten | 1076 |
| 4 | Mauerwerk | 220 |
| 5 | Dämmstoffe | 412 |
| 6 | Holz | 21 |
| 7 | Beläge | 494 |
| 8 | Sonstiges | 754 |

Identisch mit der Spalte `GruppeNr` in `hottgenroth-baustoffkatalog.csv` — und zugleich
die **erste Ziffer des Katalogpfads** (siehe unten).

### Katalogpfad aus der Datenbank ableiten

Der Pfad (`1.1.6`, `5.5.1.3` — Feld 12 in `ElementMeta`) steht nirgends als Text in der
Datenbank, sondern ist in `TcMaterial.SortNum` in **Ziffernpaaren** kodiert. Datenbank:
`HsetuAppTimData`.

```
SortNum 1010600  →  01 | 01 | 06 | 00  →  1.1.6   (Gipsputz ohne Zuschlag)
SortNum 4020500  →  04 | 02 | 05 | 00  →  4.2.5   (Kalksandstein NM/DM 1800)
SortNum 5050103  →  05 | 05 | 01 | 03  →  5.5.1.3 (Polystyrol PS, WLG 035, >30 kg/m³)
```

Auf acht Stellen linksbündig mit Nullen auffüllen, in Paare zerlegen, Nullpaare am Ende
weglassen. Verifiziert gegen die UI-Screenshots des Materialbaums.

Grenzen: `SortNum = -1` haben Herstellerprodukte (kein Platz im Standardbaum),
neunstellige Werte ab `9…` sind LCA-Sondermaterialien mit abweichender Kodierung. Die
571 Standardbaustoffe der Gruppen 1–8 liegen fertig aufgelöst in
`hottgenroth-materialbaum.csv` auf dem Desktop (`Pfad;Gruppe;Material`).

`MaterialUId` bleibt Null-GUID: Materialien werden als Freitext plus Kennwerte in die
Schicht geschrieben, nicht aus dem Materialkatalog referenziert. Das ist auch der Weg,
den die Software geht.

---

## 9a. Inhomogene Bauteile (Gefache)

Sparrendächer, Holzbalkendecken, Fachwerk und Ständerwände bestehen aus nebeneinander
liegenden Abschnitten mit unterschiedlichem Aufbau. Hottgenroth bildet das über
`TcBuildingElementDimensionLayerSection` ab. Analysiert am Bauteil
„Sparrendach 10 cm Dämmung" (07.08.2026).

### Das Modell: vertikale Schnitte

Jede Section ist ein **vollständiger vertikaler Schnitt** durch das Bauteil. Es gibt
also nicht „eine Schicht mit zwei Materialien", sondern **jede Schicht existiert n-mal,
einmal pro Section**:

```
                Section A (88,24 %)          Section B (11,76 %)
SortNum 0   Gipskarton 12,5 mm           Gipskarton 12,5 mm      ← identisch
SortNum 1   PTFE-Folie 0,6 mm            PTFE-Folie 0,6 mm       ← identisch
SortNum 2   Mineralfaser λ 0,05  R 2,0   Konstruktionsholz λ 0,13  R 0,77   ← GEFACH
SortNum 3   Unterspannbahn 0,8 mm        Unterspannbahn 0,8 mm   ← identisch
SortNum 4   belüftete Luftschicht 5 cm   belüftete Luftschicht   ← identisch
SortNum 5   Dachziegel 3 cm              Dachziegel 3 cm         ← identisch
```

Durchgehende Schichten werden in **allen** Sections wiederholt, mit identischen Werten.
Nur wo das Gefach sitzt, unterscheiden sich die Zeilen. Ein sechsschichtiges Bauteil mit
zwei Sections hat also 12 Layer-Zeilen. Das erklärt, warum 62 % aller Layer-Zeilen im
Bestand zu Sections gehören, aber nur 9 % der Bauteile inhomogen sind.

### `TcBuildingElementDimensionLayerSection`

| Spalte | Wert | Bedeutung |
|---|---|---|
| `UId` / `GId` | GUID, `GId = UId` | |
| `DimensionUId` | → `TcBuildingElementDimension.UId` | |
| `LongDesc` | z. B. `Konstruktionsholz` | Name des Abschnitts (meist das Gefachmaterial) |
| **`SectionShareValve`** | **`11.7647…` / `88.2352…`** | **Flächenanteil in Prozent, Summe = 100** |
| `SortNum` | `0`, `1`, … | Reihenfolge der Sections |
| `SeqNum` | `0` | (nicht `-1` wie sonst) |
| `OId` | `-1` | |
| `SectionType`, `SectionNum` | `0` | |
| `SectionLayerNum` | `-999` | Null-Int |
| `GeoType` | `NULL` | echtes NULL, ausnahmsweise |
| `CatalogGroupUId` | `NULL` | |
| `SyncType` / `SyncVersion` | `2` / `1.3.2.2` | |
| `ShortDesc`, `InfoDesc`, `VariantRoot` | `N''` | |
| `MId` | Null-GUID | |

Die Layer-Zeilen verweisen über `LayerSectionUId` auf ihre Section — dieselbe Spalte, die
bei homogenen Bauteilen die Null-GUID trägt.

Der Anteil ist der **Flächenanteil im Bauteil**, nicht der Anteil an der Schicht:
11,76 % = 10 cm Sparrenbreite bei 85 cm Achsabstand.

### `ElementMeta` bei inhomogenen Bauteilen

Der Legacy-Block bekommt einen Kopfzusatz und je Section einen eigenen Schichtblock:

```
RAI=0,1
RAA=0,1
CP10CM=…  CP3CM=…  CPEnIso13786=…
InhomogenAlsGefach=Falsch
InhomogenDaten=||||||||Wahr|10|75|0|||||||||||||
BEZ1=Konstruktionsholz                 ← Name Section 1
ANT1=0,117647058823528                 ← Anteil als Faktor
ANTWERT1=11,7647058823528              ← Anteil in Prozent
G1S1=…  G1S2=…  G1S3=…                 ← Schichten von Section 1
BEZ2=Mineral. und pflanzl. Faserdämmstoff
ANT2=0,882352941176472
ANTWERT2=88,2352941176472
G2S1=…  G2S2=…  G2S3=…                 ← Schichten von Section 2
KorrLS=…  KorrBe=…  KorrUD=…
```

`InhomogenDaten` trägt die Geometrie: Feld 9 `Wahr`, Feld 10 = **Balkenbreite in cm**,
Feld 11 = **lichter Abstand in cm**. Daraus folgt der Anteil: 10/(10+75) = 11,76 %.

In der Gefachschicht steht in Feld 8 des `G<n>S<m>`-Blocks `Wahr` statt `Falsch` — dort,
wo bei homogenen Schichten das `IsVentilated`-Flag sitzt.

Luftschichten haben Katalogpfade mit `L.`-Präfix (`L.5.3.3.1`) und in Feld 11 eine `-3`
statt `0`.

### Beim Anlegen zu beachten

1. Sections **vor** den Layer-Zeilen anlegen (die brauchen die `LayerSectionUId`).
2. `SectionShareValve` in Prozent, Summe exakt 100.
3. Jede Schicht für **jede** Section anlegen — auch die durchgehenden.
4. `SortNum` der Layer läuft je Section wieder bei 0 los; die Zuordnung erfolgt über
   `LayerSectionUId`, nicht über eine fortlaufende Nummer.
5. U- und R-Wert der Dimension rechnet Hottgenroth **nicht** selbst nach — sie müssen
   nach EN ISO 6946 (Mittel aus oberer und unterer Grenze) vorberechnet eingetragen
   werden, wie bei homogenen Bauteilen auch.

---

## 10. Woher das Wissen stammt

### Der Reverse-Engineering-Zyklus

Für jeden weiteren Bauteiltyp (Fenster, Dach, Boden) dieselbe Schleife:

1. **Trace starten** — `create-bauteil-trace-v2.sql` legt die Extended-Events-Session
   `HottgenrothTrace` an: `sql_statement_completed` + `rpc_completed`, Ring-Buffer,
   gefiltert auf `INSERT|UPDATE|DELETE|MERGE` und `client_app_name <> 'SQLCMD'`.
2. **In der Software das Bauteil anlegen** (GUI).
3. **Trace auslesen** — `read-bauteil-trace.sql` / `monitor-bauteile.sql` (T-SQL über
   das Ring-Buffer-XML) oder `read-sql-trace.ps1` (mit `-Loop` und `-Export`).
4. **Snapshot ziehen** — `dump-bauteile-snapshot.sql` (`SELECT *` über alle beteiligten
   Tabellen), um die exakten Spaltenwerte inklusive Sentinels abzulesen.
5. **Nachbauen, ausführen, in der Software prüfen.**

### Vorhandene Dumps

Liegen auf dem **Desktop** (`C:\Users\fs-energieberater\Desktop\`), nicht im Repo:

| Datei | Inhalt |
|---|---|
| `bauteil_trace_output.txt` | **Der SQL-Mitschnitt der Software** beim Anlegen eines Bauteils — 451 Batches, 7 `INSERT`, 81 `UPDATE`. Die maßgebliche Referenz. |
| `hottgenroth_dump_BEFORE.txt` / `_AFTER.txt` | Snapshots vor/nach einem Test-Insert |
| `hottgenroth-baustoffkatalog.csv` | Materialkatalog: Baustoff, Gruppe, GruppeNr, λ, ρ, c, µ min/max |
| `hottgenroth-schichtaufbauten.csv` | alle Schichtaufbauten mit Header, Tab-getrennt |
| `hottgenroth-schichtaufbauten-export.csv` | dieselben Daten `;`-getrennt, plus Dimension-GUID |
| `hottgenroth_nutzungsprofile.csv`, `_profiltypen`, `_raumarten` | Raumprofile |

Dazu ein DB-Backup: `Dokumente\HSETU\Backups\HSETUPRJDATA_20260320.BAK`.

---

## 11. Skripte in `../tools/`

| Datei | Zweck |
|---|---|
| **`insert-bauteil-strackerjan.sql`** | **Referenzfassung.** Verifiziert. Schichten aus Tabellenvariable, `ElementMeta` generiert. Vorlage für neue Bauteile. |
| `delete-bauteil-strackerjan.sql` | Gegenstück zum Zurückrollen |
| `insert-bauteil-v4.sql` | Vorläufer. Legt Katalog + Ordner selbst an, falls nicht vorhanden — dieser Teil ist weiter nützlich. Enthält aber `UsageType = 0` und `TcBasis.SyncType = 1`, beides falsch. |
| `insert-bauteil-v3.sql`, `v2`, `-beispiel` | frühere Stufen, nur noch historisch |
| `insert-bauteil-meine.sql` | Variante für `HsetuUsrData` („Meine Bauteile") |
| `create-bauteil-trace-v2.sql` | Trace-Session anlegen und starten |
| `read-bauteil-trace.sql`, `monitor-bauteile.sql`, `read-sql-trace.ps1` | Trace auslesen |
| `dump-bauteile-snapshot.sql` | Volldump der beteiligten Tabellen |
| `test-elementmeta.sql` | Trockenlauf: erzeugt `ElementMeta` + Kennwerte read-only zur Kontrolle |
| `query-raumprofile*.sql`, `query-alle-raumarten.sql` | Raumprofile (anderes Thema) |

---

## 12. Stolpersteine

- **Software schließen** vor dem Schreiben, und danach **neu starten**. Der Katalog
  wird beim Laden gelesen; ohne Neustart erscheint das Bauteil nicht.
- **Die laufende Software überschreibt Änderungen.** Nicht nur „sieht sie nicht" — sie
  hat geöffnete Bauteile im Speicher und schreibt ihren Stand zurück. Beobachtet am
  07.08.2026: ein `UPDATE` auf `TcBasis.UsageType` war in der Datenbank verifizierbar
  gesetzt und stand kurz darauf wieder auf dem alten Wert, dazu hatte die Software
  `Rsi`/`Rse` passend zu *ihrem* Bauteiltyp umgeschrieben. Neue Zeilen (`INSERT`)
  überlebten dagegen. Für `UPDATE`s ist das Schließen der Software also Pflicht.
- **Rsi/Rse leitet die Software aus dem Bauteiltyp ab** und überschreibt die
  eingetragenen Werte. Falscher `UsageType` → falsche Übergangswiderstände → falscher
  U-Wert. Bei „Boden gegen Außen" 0,17/0,04, bei oberster Geschossdecke 0,10/0,10.
  Manche Katalogbauteile lassen die Felder auf dem Null-Float stehen und überlassen der
  Software die Ableitung ganz.
- **`PRINT` verträgt keine Subquery.** `PRINT … CAST((SELECT COUNT(*) …))` ist ein
  Compile-Fehler (Msg 1046) — und weil SQL Server den ganzen Batch vor der Ausführung
  kompiliert, läuft dann *nichts*, auch die INSERTs nicht. Erst in eine Variable
  selektieren. (Immerhin ein sicheres Scheitern.)
- **`PrProject`-Schlüssel heißt `UUID`**, nicht `UId` wie überall sonst.
- **cm vs. m** zwischen `ElementMeta` und den Layer-Zeilen.
- **Alles in eine Transaktion** mit `SET XACT_ABORT ON` — ein halb geschriebenes
  Bauteil ist schwerer zu finden als gar keines.
- **Vorab auf Namensdubletten prüfen**, sonst sammeln sich stille Duplikate im Katalog.

---

## 13. Was noch offen ist

- **Zuweisung an das Gebäude.** Ein Bauteil im Katalog ist noch keine verbaute Wand.
  Dafür sind `TcElementReference` und die `BmElement*`-Tabellen zuständig — in
  `dump-bauteile-snapshot.sql` bereits mit abgefragt, aber noch nicht analysiert.
- **Andere Bauteiltypen.** Fenster (`Glazing*`, `Frame*`, `Mullion*`/`Transom*`), Dach,
  Bodenplatte: die Spalten existieren in `TcBuildingElementDimension`, die passenden
  `ElementType`/`GroupType`-Werte sind unbekannt. Der Zyklus aus Abschnitt 10 liefert sie.
- **`CP10CM` / `CP3CM` / `CPEnIso13786`** in `ElementMeta` (Abschnitt 7).
- **Die `EN6946*`-Spalten** in der Layer-Tabelle sind weiterhin ungenutzt — das Gefach
  läuft über Sections (Abschnitt 9a), wofür diese Spalten offenbar nicht gebraucht werden.
- **Inhomogene Bauteile sind analysiert** (Abschnitt 9a), aber noch nicht per SQL
  erzeugt. Der erste Schreibversuch steht aus.
- **`HsetuUsrData`-Weg** („Meine Bauteile", projektübergreifend) ist seit den
  Korrekturen nicht erneut getestet.
