# Räume, Zonen und Raumstempel in der Hottgenroth-Datenbank

Schwesterdokument zu [`hottgenroth-bauteil-sql.md`](hottgenroth-bauteil-sql.md).
Dort geht es um den Bauteilkatalog, hier um das gerechnete Gebäude: Räume,
DIN-18599-Zonen, Nutzungsprofile und den Raumstempel.

Alles hier steht auf Messung, nicht auf Vermutung. Wie gemessen wurde, steht in
[Abschnitt 10](#10-woher-das-wissen-stammt). Was **nicht** verstanden ist, steht in
[Abschnitt 11](#11-offene-punkte) — bitte dort zuerst nachsehen, bevor darauf
aufgebaut wird.

---

## 1. Drei Welten, dünn verkoppelt

| Welt | Tabellen | führt |
|---|---|---|
| **Gebäudemodell** | `Bm*` | Geometrie: Räume, Bauteile, Zonen, Geschosse. HottCAD zeichnet hier. |
| **Anlagenseite** | `Pm*` | Heizung/Technik. `PmSpace` ist ein Abbild jedes Raums — führt aber nur den Namen. |
| **EE-Berater** | `eberater.zip` als Blob in `PrMedia` | die 18599-Rechnung: `TableHuellfl`, `TableHausDat`, `TableProjekt` … |

Die Nähte:

- **Gebäudemodell ↔ Anlage** über `PmBuildingReference`:
  `ReferenceFromUUID` → `PmSpace.UUID`, `ReferenceToUUID` → `BmRoom.UUID`,
  `ReferenceSpaceUUID` → `BmFloor.UUID`, dazu `ReferenceType = 1`,
  `ObjReferenceType = 22`.
- **Gebäudemodell ↔ EE-Berater** über **`BmZone.InfoDesc`**. Wo sie gefüllt ist,
  steht dort wörtlich die Zonenkennung des EE-Beraters im Format
  `P0Zone_<n>[HASH8]` — genau der Wert aus `TableHuellfl.ZoneID`. Bei
  Brandschutzzonen (`ZoneType = 10`) steht stattdessen deutscher Klartext.

  **Sie ist aber nicht immer gefüllt.** Geprüft an drei Projekten: in den beiden
  Nichtwohngebäuden (RVRW6, Ossendorf) trägt jede `ZoneType-5`-Zone ihre
  Kennung; im Wohngebäude *Werner Grotz* ist `InfoDesc` der Zone
  „Wohnung Einfamilienhaus" **leer**. Eine Zone kann im Gebäudemodell also ohne
  Verbindung zum EE-Berater bestehen. Woran das hängt — Herkunft der Zone,
  Rechenverfahren, Reihenfolge der Anlage — ist ungeklärt und gehört zu den
  offenen Punkten.

**Diese Naht läuft nicht von allein.** Eine `BmZone` mit passender `InfoDesc`
anzulegen ändert die `eberater.zip` um kein Byte — gemessen, beide Blob-Hashes
blieben gleich. Ausgewertet wird sie erst beim Übertrag, und was den auslöst, ist
offen (Abschnitt 11).

---

## 2. Das Grundmuster: Verweistabellen ohne Eigenidentität

Der häufigste Irrtum beim Lesen dieses Schemas. Eine Verweistabelle hat **keine
eigene Identität** — die Spalte `UUID` ist der *Besitzer*, nicht die Zeile:

| Tabelle | `UUID` ist | `ReferenceToUUID` ist | `ReferenceClass` |
|---|---|---|---|
| `BmZoneReference` | die **Zone** | der Raum | `TModelRoom` |
| `PdProfileReference` | das **Profil** | Raum oder Zone | `TModelRoom` / `TModelZone` |

Primärschlüssel ist in beiden Fällen das **Paar** (`ReferenceToUUID`, `UUID`).
Daneben gibt es die zweite Bauart — eigene Identität plus zwei Enden:
`PmBuildingReference` und `BmElementReference` mit `ReferenceFromUUID` **und**
`ReferenceToUUID`.

Dieselbe Falle ein Stockwerk tiefer:

> **`BmData.UUID` ist die Kennung der Datenart, nicht der Zeile.**
> Alle 138 `CADXMLData`-Sätze eines Projekts teilen dieselbe UUID
> (`99e575c9-…`); daneben stehen `Color`, `is_auto_generated`, `plot_head`,
> `plot_properties`, `save_type` mit je eigener. Der Schlüssel ist das Paar mit
> `ReferenceUUID`. Wer `UUID` für den Zeilenschlüssel hält, überschreibt beim
> ersten `UPDATE` das ganze Projekt.

---

## 3. Dieselbe Aussage steht mehrfach da

Die gefährlichste Eigenschaft des Modells. Wer nur eine Stelle setzt,
hinterlässt ein Gebäude, das sich selbst widerspricht — die Oberfläche zeigt die
eine Zahl, gerechnet wird die andere.

| Aussage | Stelle 1 | Stelle 2 |
|---|---|---|
| Heizstatus | `BmRoom.HeatingType` | `heating_type` im CAD-XML |
| Raumtemperatur | `BmRoom.InsideTemperature` | `temperature` im CAD-XML |
| Raumart | `BmRoom.RoomType` | `room_type` im CAD-XML |
| Raumname | `BmRoom.LongDesc`, `BmRoomData.LongDesc` | `name` im CAD-XML |
| Zone | `BmZone` | `TableHuellfl.ZoneID` in der `eberater.zip` |
| Raum | `BmRoom` | `PmSpace` |

Dazu: **HottCAD führt eigene GUIDs.** Die Raum-GUID im XML ist *nicht*
`BmRoom.UUID`, die `floor`-GUID im XML ist *nicht* `BmFloor.UUID`. Wer sie
gleichsetzt, verknüpft ins Leere.

Das reiht sich in das ein, was von der Anlagentechnik bekannt ist, wo die
Vorlauftemperatur getrennt an Heizkreis und Wärmepumpe hängt.

---

## 4. Ein Raum: fünf Zeilen in fester Reihenfolge

Mitgeschnitten beim Anlegen eines Raums über HottCAD — **fünf `INSERT`, kein
einziges `UPDATE`**, zusammen 212 ms:

```
BmRoom  →  BmRoomData  →  BmBuildingSpace  →  PdProfileReference  →  BmData
```

| Tabelle | Schlüssel | Inhalt |
|---|---|---|
| `BmRoom` | `UUID` | Kennzahlen: `FloorUUID`, `ShortDesc` (`DG2-R1`), `RoomType`, `HeatingType`, `Area`, `Height`, `Volume`, `InsideTemperature`, `RatedMinAirExchangeRate` |
| `BmRoomData` | **dieselbe UUID** | fast leer, nur die drei Bezeichnungen. 1:1 zum Raum, kein eigener Schlüssel |
| `BmBuildingSpace` | eigene UUID | `ParentUUID` = Raum, `ParentElementType 1`, `SpaceType 2`, `SpaceCaseType 2` |
| `PdProfileReference` | (`ReferenceToUUID`, `UUID`) | `UUID` = **Raumprofil**, `ReferenceClass` = `TModelRoom`, `GeneratorType 26` |
| `BmData` | (`ReferenceUUID`, `UUID`) | `ClassValue` = das CAD-XML |

Zum Vergleich: ein *Bauteil* anzulegen kostet 7 `INSERT` und **81 `UPDATE`**.
Räume sind ungleich einfacher.

**`PmSpace` entsteht dabei nicht.** Es blieb beim Anlegen unverändert und kam
erst später dazu — wodurch, ist offen (Abschnitt 11).

### Das CAD-XML

```xml
<room name="Wohnraum" GUID="b651d925-…" floor="17eedd34-…" number="DG2-R1"
      room_type="mrtLiving" temperature="20" air_change="0.5"
      heating_type="Heated" area="97.54…" height="2.6" short_name="R1-DG">
  <points count="9"> … </points>
  <polygons count="1"><plg height="2.6" type="MRoomPolygon" with_holes="True"> … </plg></polygons>
  <heights count="4"><height_ext>3;3;5.6;5.6</height_ext> … </heights>
  <LivingAreaCalculationRule count="3">   <!-- 0–1 m → 0 %, 1–2 m → 50 %, darüber 100 % -->
```

### Der Rückweg

Ein Raum hängt an **35 Zeilen in 7 Tabellen** — die fünf oben plus:

- `BmElementReference` (`ReferenceFromUUID`) — **29 Zeilen**, die umschließenden Bauteile
- `PmBuildingReference` (`ReferenceToUUID`) — die Brücke zur Anlagenseite

Wer einen Raum löscht und diese beiden vergisst, hinterlässt Waisen.

---

## 5. Eine Zone: zwei Zeilen

`BmZone` + `BmZoneData` unter **derselben UUID**. `BmZoneData` unterscheidet sich
zwischen einer echten DIN-18599-Zone und einer Brandschutzzone in **nichts außer
den Kennungen** — reine Kopie.

In `BmZone` sind nur diese Felder verschieden:

| Feld | DIN 18599 | Brandschutz |
|---|---|---|
| `ZoneType` | **5** | 10 |
| `HeatingType` | 1 | 0 |
| `InfoDesc` | `P0Zone_1[216377D5]` | deutscher Klartext |
| `Area`, `Volume`, `ClearHeight`, `HeatableLivingArea` | gerechnet | Sentinel |

Gleich sind `ParentUUID` (= `BmBuilding`), `ParentClassType 4`, `SpaceType 2`,
`ZoneSubType 0`, `ProfileGroupUUID` (Null-GUID), `BWZId -1`, `SyncVersion 1.5.4`,
`GeoType` (`NULL`), `GeneratorType 2`.

**Eine handgeschriebene Zone trägt.** Erprobt: zwei Zeilen per `INSERT` angelegt,
danach hat die Software sie nicht nur angezeigt, sondern **selbst
weiterbearbeitet** — ein Nutzungsprofil angehängt und die Zone dabei nach dem
Profil umbenannt. Das ist die strengere Wirkungsprobe: nicht „sichtbar", sondern
„die Software arbeitet damit wie mit einer eigenen".

Die drei Brandschutzzonen legt die Software beim Anlegen des Projekts selbst an,
auf Englisch, alle in derselben Sekunde, mit Sentinel als Fläche. Sie sind
Beiwerk, nicht Arbeit.

---

## 6. Ein Nutzungsprofil: drei Zeilen unter einer UUID

| Tabelle | Inhalt |
|---|---|
| `PdProfile` | `PDMUUID`, `ShortDesc`, `LongDesc` (`42 - Wohnung Einfamilienhaus`), `ProfileType 2`, `StandardType 2`, `Active False` |
| `PdProfileUsage` | `HeatingType 1`, **`ProfileUsageType 34`** |
| `PdProfileReference` | `ReferenceToUUID` = Zone, `ReferenceClass TModelZone`, `ReferenceClassType 2`, `ReferenceContainerType 2` |

Alle drei tragen **dieselbe `UUID`** und `GId`. Profile werden **je Projekt neu
angelegt**, nicht aus einem Katalog verwiesen — deshalb hat
„42 - Wohnung Einfamilienhaus" in jedem Projekt eine andere UUID (in dieser
Datenbank 40-mal, 40 verschiedene UUIDs).

`StandardType = 2` bei allen 502 Nutzungsprofilen: das Profil ist ein Verweis in
die DIN-Tabellen, kein Wertespeicher. Deshalb sind 33 der 56 Spalten in
`PdProfileUsage` leer — **es gibt nichts zu speichern.** Die Auswahl *ist* die
Konfiguration; `StampEdit` bleibt gleich `StampCreate`.

### Die Falle: `ProfileUsageType` ist nicht die Nummer im Namen

Bis 33 stimmen beide überein, danach nicht mehr:

| Anzeige | `ProfileUsageType` |
|---|---|
| **42 - Wohnung Einfamilienhaus** | **34** |
| 43 - Wohnung Mehrfamilienhaus | 35 |
| 34 - Saunabereich | 40 |
| 35 - Fitnessraum | 41 |
| 36 - Labor | 42 |
| 37 - Untersuchungsraum, Behandlungsraum | 43 |
| 38 - Spezialpflegebereich, Intensivmedizin | 44 |
| 39 - Flure (Krankenhaus) | 45 |
| 40 - Arztpraxis, Therapeutische Praxis | 46 |
| 41 - Lagerhalle, Logistikhalle | 47 |
| 22.1 / 22.2 / 22.3 Gewerbehalle | 38 / 71 / 70 |

Die Aufzählung folgt der Reihenfolge, in der die Profile in die Norm gekommen
sind. **Wer für „42 Einfamilienhaus" die 42 schreibt, bekommt „36 Labor".**
Als Tabelle mitführen, nicht rechnen.

---

## 7. Raum in Zone: eine Zeile

```
BmZoneReference:  UUID = Zone,  ReferenceToUUID = Raum,
                  ReferenceClass = 'TModelRoom',  ReferenceClassType = 1
```

`Id`, `SortNum`, `ShortDesc`, `LongDesc` und `GId` sind `NULL`.

Aus dem dekompilierten `TBORoom.MoveToDIN18599Zone`:

```csharp
if (DIN18599Zone != null) BolModelMapper.DeleteRef(DIN18599Zone, this);
result = BolModelMapper.CreateRef(AZone, this);
```

**Ein Raum hängt in genau einer DIN-18599-Zone.** Alte Zuordnung lösen, dann neu
setzen. Die Oberfläche arbeitet über die Auswahl
(`Selection.ForEach(x => x.MoveToDIN18599Zone(…))`), mehrere Räume in einem Zug
sind also vorgesehen.

Ein Raum kann gleichzeitig an **sechs verschiedenen Zonenachsen** hängen —
Wohneinheit, DIN 18599, DIN 1946, VDI 2078, Verteilerzone, Brandschutzzone. Die
sind unabhängig; `RemoveFromDIN18599Zone` rührt die anderen nicht an.
Das DIN-18599-Feld ist grau, wenn das Projekt auf **DIN 4108-6** steht
(`DIN18599Zone_Enabled => !ConfigState.DIN_4108_6`).

---

## 8. Der Raumstempel

Der Raumstempel ist **kein eigenes Objekt**. Was im Grundriss steht —

```
Keller-R1; Kellerraum
99,34 m²/218,54 m³
WoFl: ---
unbeheizt
10 °C
```

— ist die Anzeige von `ShortDesc`; `LongDesc`, `Area`/`Volume`, `LivingArea`
(`---` = Sentinel), `HeatingType` und `InsideTemperature`. Einen Stempel setzen
heißt: diese Felder setzen, in `BmRoom` **und** im CAD-XML.

### Raumartkatalog

Aus 1704 Räumen dieser Datenbank abgeleitet. `HT`/`T` sind die Vorgaben, die die
Raumart mitbringt.

| RT | Raumname | HT | T | Profil-Id | `room_type` |
|---|---|---|---|---|---|
| 0 | Raum | 1 | 20 | — | — |
| 1 | Wohnraum | 1 | 20 | (oft ohne) | `mrtLiving` |
| 2 | Schlafen | 1 | 20 | 1003 | `mrtSleeping` |
| 3 | Kind | 1 | 20 | 1004 | `mrtChild` |
| 4 | Küche | 1 | 20 | 1005 | `mrtKitchen` |
| 5 | Essen | 1 | 20 | 1006 | `mrtEating` |
| 6 | Flur | **4** | 15 | (ohne) | `mrtHall` |
| 8 | Hobby | 1 | 20 | — | — |
| 9 | Nebenraum | **2** | 10 | 1041 | — |
| 11 | Bad/Dusche/Umkleideraum | 1 | **24** | 1012 | `mrtBath` |
| 12 | WC-Raum | 1 | 20 | 1013 | — |
| 13 | Heizraum | **2** | 20 | (ohne) | — |
| 14 | Büroraum | 1 | 20 | 1015 | — |
| 23 | Kellerraum | **2** | 10 | (ohne) | `mrtBasement` |
| 24 | Heizungsaufstellraum | 1 | 15 | 1025 | `mrtCentralHeating` |
| 25 | Dachraum | **2** | **7** | 1026 | `mrtRoof` |
| 26 | Treppenhaus | **4** | 15 | (ohne) | — |
| 30 | Sauna | 1 | 15 | — | — |
| 34 | Abstellraum | 1 | 15 | 1035 | `mrtStore` |
| 35 | Vorratsraum | **2** | 10 | 1046 | — |
| 36 | Hausanschlussraum | **2** | 10 | 1044 | — |
| 42 | Garage | **2** | **5** | 1054 | `mrtGarage` |
| 52 | Wohnungsflur | 1 | 20 | — | — |
| 53 | Fahrstuhlschacht | **2** | 15 | 1057 | — |

`air_change` folgt der Raumart: **0,5 bei Aufenthaltsräumen** (Wohnen, Schlafen,
Kind, Küche, Essen, Bad), **0 bei allen anderen**.

Die `mrt*`-Bezeichnung fehlt bei 12 der 24 Arten, weil im ganzen Bestand nur
**42 Räume** ein CAD-XML haben. Nicht erfinden — siehe Abschnitt 11.

### Der Konflikt mit „nur beheizt oder unbeheizt"

`HeatingType` ist dreiwertig: **1** Heated, **2** Unheated, **4**
SeparatelyHeated. Die 3 ist nie aufgetreten.

Die Raumart bringt ihren eigenen Wert mit, und der ist bei Flur und Treppenhaus
`4`, bei Keller/Dach/Garage/Vorrat/Nebenraum/Schacht `2`. Wer nur zwei Zustände
führen will, **entkoppelt den Heizstatus vom Stempel** und setzt ihn je
Geschoss. Beides ist vertretbar, aber nicht gleichzeitig — die Entscheidung
gehört ins Projekt, nicht ins Werkzeug.

Für ein Wohngebäude mit **einer** Zone ist die Entkopplung unkritisch: die
Nutzung trägt das Nutzungsprofil der Zone, die Raumart einzelner Räume geht in
die 18599-Rechnung nicht ein. Für eine Heizlast nach DIN EN 12831 sehr wohl —
dort zählt jede Raumtemperatur.

---

## 9. Konventionen und Sentinels

Beim **Neuanlegen** (gemessen am frisch gezeichneten Raum):

- `GId = UUID`. In gewachsenen Projekten ist `GId` etwas anderes — beim Kopieren
  also mappen, nicht gleichsetzen.
- `VariantRoot` **leer**. Bestehende Objekte tragen dort eine Variantenwurzel.
- `Id = SeqNum = -1`, `GeneratorType = 2` (Modellobjekte), `26` bei
  `PdProfileReference`.
- `SyncCreate`/`SyncEdit` = Null-GUID, `SyncType = 2` (bei `Pd*`: `1`).

**`SyncVersion` ist je Tabelle verschieden** — `BmRoom` `1.5.6`, `BmZone` `1.5.4`,
`PdProfile`/`PdProfileUsage` `1.1.2.3`. Nicht vereinheitlichen.

| Wert | Bedeutung |
|---|---|
| `-987654321,99` | nicht gesetzt |
| `AAAAAAAA-AAAA-…` | kein Verweis |
| `1899-12-30` | kein Zeitpunkt |
| `-1`, `-999` | nicht gesetzt (ganzzahlig) |

`Zone2ID`/`Zone2Bez` in `TableHuellfl` ist **keine zweite Zone**, sondern der
angrenzende unbeheizte Bereich; `Zone2Bez` trägt `Fx 0,45` … und `REDFAKTOR`
daneben dieselbe Zahl.

---

## 10. Woher das Wissen stammt

Derselbe Zyklus wie beim Bauteil, mit zwei neuen Werkzeugen:

1. **Momentaufnahme** — [`Snapshot-Projekt.ps1`](../tools/Snapshot-Projekt.ps1)
   zieht jede Tabelle mit Projektbezug, legt die `PrMedia`-Blobs als Dateien ab
   **und packt den ZIP-Blob aus**, um die `.BDExit`-Tabellen des EE-Beraters
   feldweise zu lesen (über `werkzeuge/bdexit/bde.ps1` + `satz.ps1` im
   dekompilierten Korpus). Ohne diesen Schritt meldet der Vergleich nur
   „Blob geändert".
2. **In der Software einen Schritt tun, speichern.**
3. **Zweite Momentaufnahme, vergleichen** —
   [`Diff-Snapshot.ps1`](../tools/Diff-Snapshot.ps1) zeigt bei geänderten Zeilen
   nur die Spalten, die sich wirklich unterscheiden, und meldet
   „nur Zeitstempel" getrennt.
4. **SQL-Trace** über `create-bauteil-trace-v3.sql` für die *Reihenfolge* der
   Schreibvorgänge — der Snapshot zeigt den Endzustand, nicht den Weg.
5. **Dekompilierter Bestand** unter `C:\Projekte_Dev\hsetu-decompiled` für die
   Regeln hinter den Zeilen (`MoveToDIN18599Zone`, `RoomZonesViewModel`).

### Stolpersteine des Messens

- **Die Software muss zu sein — und sie heißt nicht immer `Energie`.** Bei
  laufender Anwendung wird das Modell beim Beenden zurückgeschrieben und alles
  verworfen, was von außen kam, ohne Meldung. **Der EE-Berater läuft als
  `EEBerater`** (Fenstertitel „EE-Berater Wohnen"). Eine Prüfung nur auf
  `Energie` lässt ihn durch und meldet fälschlich „gefahrlos" — genau so sind am
  17.08.2026 drei Schreibvorgänge gegen eine offene Anwendung gelaufen. Die
  Liste steht jetzt in [`Test-SoftwareLaeuft.ps1`](../tools/Test-SoftwareLaeuft.ps1)
  und deckt `Energie`, `EEBerater`, `HottCAD`, `Hsetu.Shell`, `Hsetu.Desktop`,
  `HottTherm`, `Hsetu.Assistant` ab. `HsetuServices` und `Hsetu.Update.Check`
  gehören **nicht** dazu — Hintergrunddienste ohne Projektmodell, die dauerhaft
  laufen.
- **Die Extended-Events-Session überlebt keinen Instanz-Neustart.** LocalDB
  fährt herunter, wenn eine Weile niemand verbunden ist; die Session bleibt
  angelegt, läuft aber nicht mehr. `ALTER EVENT SESSION … WITH (STARTUP_STATE = ON)`
  behebt das — im Bauteil-Skript fehlt der Schalter.
- **PowerShell 5.1 liest `.ps1` ohne BOM als ANSI.** Umlaute und Gedankenstriche
  zerlegen den Parser. Mit UTF-8-BOM speichern.
- **PowerShell entrollt eine `DataTable` beim `return`** in ihre Zeilen;
  `.Rows.Count` ist danach still `0`. `return , $tab` verhindert es.
- **`$pid` ist schreibgeschützt** (die Prozess-ID). Eine Auswertung, die `$pid`
  als Variable benutzt, liefert überall dieselbe Zahl.
- **Häufigsten Wert ≠ typischen Wert.** Eine Auswertung über alle 1704 Räume
  wird von Altprojekten ohne CAD-XML beherrscht; für `room_type` bleiben 42.

---

## 11. Offene Punkte

| # | offen | Folge |
|---|---|---|
| 1 | **Der `[HASH8]`** in `P0Zone_1[216377D5]` — Bildungsregel unbekannt. | Bei einem Wohngebäude unkritisch: der EE-Berater legt seine Zone selbst an, die Kennung steht immer schon in `TableHuellfl.ZoneID` und wird von dort gelesen. Für eine **zweite** Zone in einem Projekt fehlt sie. |
| 2 | **Raumgeometrie** — das Polygon kommt aus HottCAD. | Räume können geändert, aber nicht neu erfunden werden. |
| 3 | **Was `PmSpace` entstehen lässt.** Beim Raumanlegen kam es nicht mit, später war es da. | Ein von außen angelegter Raum hat kein Gegenstück auf der Anlagenseite. |
| 4 | **`mrt*` für 12 der 24 Raumarten** (WC-Raum, Treppenhaus, Vorratsraum, Nebenraum, Büroraum, Hobby, Sauna, Hausanschlussraum, Wohnungsflur, Fahrstuhlschacht, Heizraum, Raum). | Diese Raumarten dürfen nicht gesetzt werden — ein erfundener Name macht das XML unbrauchbar. `Set-Raumstempel.ps1` weist sie ab. |
| 5 | **Was den Übertrag ins `eberater.zip` auslöst.** | Zone, Profil und Zuordnung im Gebäudemodell erreichen die 18599-Rechnung nicht von allein. |
| 6 | **`Profil-Id` ↔ `RoomType`** nicht durchgängig 1:1 — Abstellraum trat mit 1035 und 1045 auf, Kellerraum mit 1047 ohne festen Bezug. | Beim Setzen eines Raumprofils die Id aus dem Projekt lesen, nicht aus dieser Tabelle raten. |

---

## 12. Werkzeuge

| Datei | Zweck |
|---|---|
| [`Snapshot-Projekt.ps1`](../tools/Snapshot-Projekt.ps1) | Momentaufnahme eines Projekts inkl. Blobs und `.BDExit` |
| [`Diff-Snapshot.ps1`](../tools/Diff-Snapshot.ps1) | zwei Aufnahmen spaltengenau vergleichen |
| [`Set-Raum-Heizstatus.ps1`](../tools/Set-Raum-Heizstatus.ps1) | Heizstatus je Geschoss setzen — `BmRoom` **und** XML |
| [`Set-Raum-Zone.ps1`](../tools/Set-Raum-Zone.ps1) | Räume einer DIN-18599-Zone zuordnen, mit der Ein-Zone-Regel |
| [`Set-Raumstempel.ps1`](../tools/Set-Raumstempel.ps1) | Raumart, Name, Heizstatus und Temperatur setzen, beidseitig |
| [`Test-SoftwareLaeuft.ps1`](../tools/Test-SoftwareLaeuft.ps1) | `Assert-SoftwareZu` — sieben Prozessnamen, nicht nur `Energie` |
| [`Restore-Projekt.ps1`](../tools/Restore-Projekt.ps1) | **ein** Projekt aus einer Sicherung zurückholen, ohne die anderen 40 anzufassen |

`Restore-Projekt.ps1` ist der Weg, wenn im Gebäudemodell etwas verlorengeht: die
Sicherung als Seitendatenbank einspielen, dann je Tabelle mit Projektbezug die
Zeilen dieses Projekts löschen und aus der Quelle neu einfügen. Erprobt am
17.08.2026 nach dem Löschen von `RepositoryType 1` — **1265 Zeilen in 20 Tabellen
zurück, byte-genau bis auf das absichtlich ausgenommene Journal.** Ein
Voll-Restore von `HsetuPrjData` wäre falsch: er setzt alle Projekte zurück.

Alle drei schreibenden Werkzeuge haben `-Probelauf` und brechen ab, wenn
Energie.exe läuft. Vor dem Einsatz sichern:

```sql
BACKUP DATABASE HsetuPrjData TO DISK = N'…\vorher.bak' WITH INIT;
```

`WITH COMPRESSION` geht nicht — die LocalDB ist Express Edition.
