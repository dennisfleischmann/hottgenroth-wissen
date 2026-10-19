# Sanierungsvarianten: anlegen und Bauteile „sanieren"

Stand 11.08.2026. Untersucht am Projekt „Werner Grotz" in `(localdb)\HSETU`, an dem
in der Software eine Variante `Neue_Variante_Test` aus dem Ist-Zustand erzeugt und
darin die sieben Außenwände auf U = 0,20 gesetzt wurden — also der Vorher-Nachher-Fall.

**Die Kurzfassung:** Die Variantenlogik liegt in einem **ZIP im Medienanhang des
Projekts**, nicht in SQL. Dort ist „saniert" keine Kopie des Bauteils, sondern eine
**zweite Spalte neben dem Ist-Wert**. Aufrufbare Funktionen gibt es nicht — der Code
ist nativ. Das Format ist aber selbstbeschreibend und inzwischen **vollständig
entschlüsselt**: alle neun Tabellen lassen sich feldweise lesen und Byte für Byte
identisch zurückschreiben.

**Beides ist erprobt und bestätigt:**

| | |
|---|---|
| Ein Bauteil sanieren (`SANK_ZAHL` setzen) | ✔ 11.08.2026 — Software rechnet neu, Bewertung EH 85 |
| Eine **komplette Variante anlegen** | ✔ 11.08.2026 — Abschnitt 11 |

Die SQL-Modellkopie aus Abschnitt 1 wird zum Anlegen **nicht** gebraucht. Die
angelegte Variante erscheint in der Liste, trägt eigene Bauteile mit eigenen U-Werten
und lässt sich normal weiterbearbeiten.

> **Wer nur etwas erledigen will, springt direkt zu:**
> [**Abschnitt 12 — Anleitung: eine Variante sicher anlegen**](#12-anleitung-eine-variante-sicher-anlegen)
> und [**Abschnitt 13 — Fehlerquellen**](#13-fehlerquellen).
> Die Abschnitte 1–11 erklären, *warum* es so geht; für die Arbeit braucht man sie nicht.

---

## 1. Was beim Anlegen passiert

### In SQL: eine vollständige Kopie

Gemessen an den Zeilen, die beim Anlegen der Variante entstanden sind:

| Tabelle | neu | Tabelle | neu |
|---|---:|---|---:|
| `BmElementReference` | 194 | `BmElementStorey` | 17 |
| `BmElement` | 144 | `BmBuildingSpace` | 16 |
| `BmElementDimensioning` | 144 | `BmRoom` | 16 |
| `BmElementEnergyConsulting` | 144 | `PmSpace` | 16 |
| `BmElementWall` | 69 | `PmBuildingReference` | 16 |
| `BmElementWindow` | 25 | `BmZoneReference` | 14 |
| `BmElementDoor` | 19 | `BmElementRoof` | 11 |

`BmElement` ging damit von 152 auf 296. **Kein Delta, keine Verweisstruktur — eine
echte Kopie im selben Projekt.** Das entspricht dem Muster, das schon vom
`.sqproj`-Import bekannt ist: `CopyModelProject` → `Insert()` → neue Identitäten.

> **Nachtrag 11.08.2026:** Diese Kopie ist zum Anlegen einer Variante **nicht nötig**.
> Eine von außen erzeugte Variante ohne jede SQL-Änderung erscheint in der Liste,
> trägt eigene Bauteile und rechnet (Abschnitt 11). Was die Software hier mitschreibt,
> ist offenbar Beiwerk — der tragende Teil steht im Container.

Was dabei **nicht** hilft: `VariantType` steht auf allen kopierten Zeilen auf `0`, und
`VariantRoot` trägt Werte, die von HottCAD stammen und älter sind. Die
`Bm*Variant`-Tabellen (`BmBuildingVariant`, `BmElementVariant`, …) existieren, sind
aber **leer**. Wer die Variante in SQL sucht, findet sie nicht.

### Im Medienanhang: `eberater.zip`

`PrMedia` enthält neben dem IBP-Blob (siehe
[`DIN18599-ANLAGENTECHNIK.md`](DIN18599-ANLAGENTECHNIK.md)) einen zweiten Anhang:

| | |
|---|---|
| `MediaName` | `eberater.zip` |
| Größe | 75.771 Bytes im untersuchten Projekt |
| Inhalt | neun Tabellen im Format `.BDExit` (BDE — Borland Database Engine, Delphi-Erbe) |

```
TableProjekt    TableHuellfl    TableAnlage
TableHeizung    TableWasser     TableHausDat
TableAnbauDat   TableResult     TableZusatz
```

Das ist das **eigene Datenmodell des Energieberaters** — unabhängig von den
`Hsetu.Model`-Tabellen und unabhängig vom IBP-Blob.

---

## 2. Die Variante selbst: `TableProjekt`

Jede Variante ist eine **Zeile in `TableProjekt`**. Der Ist-Zustand ist die erste;
jede weitere hängt an der vorigen — die Annahme „Varianten sind verkettet" stimmt.

Die tragenden Felder:

```
PROJEKT_ID (Autoinc)   PROJEKT_NR   BEZEICHNUNG
VarianteID             VarianteBez          ← der Name aus dem Eingabedialog
Variante_Inaktiv       Variante_IstPaket
HUELLFLBACK            RECHENVERFAHREN      PROJEKT_ART
```

Daneben trägt die Zeile INI-artige Textblöcke (`[CIM]`, `[BmMediaGuids]`) mit den
GUIDs, über die der Energieberater seine Sätze an die SQL-Welt bindet — Kontakte,
Anschriften, Medien.

Eine Zusammenfassungszeile `sEBT=` hält den Hüllflächenbestand im Klartext und eignet
sich gut zur Gegenprobe:

```
sEBT= Ground Basement-2 + … |BE|0,3|0,8|0|43,447495|0|1@
      EW 028-2 + EW 028     |WE|0,24|0,75|0|15,69392|0|1@
      EW 027                |WE|0,24|0,75|0|8,46407|0|1@
       │                     │   │            │
       Bauteilbezeichnung    │   U-Wert       Fläche
                             Kennzeichen
```

43,45 m² bei U = 0,30 und zusammen 24,16 m² bei 0,24 — genau die Kacheln „BE" und
„2 × WE" der Bauteilübersicht.

---

## 3. Das durchgehende Muster: Ist neben Saniert

Der Energieberater legt für eine Sanierung **keine zweite Zeile** an. Er hat je
Größe zwei Spalten — eine für den Bestand, eine für den sanierten Zustand. Das zieht
sich durch alle Tabellen, nur mit unterschiedlicher Schreibweise:

| Tabelle | Ist | Saniert |
|---|---|---|
| `TableHuellfl` | `K_ZAHL` | **`SANK_ZAHL`** |
| `TableAnlage` | 36 Felder auf `…_ALT` | 18 Felder auf `…_NEU` |
| `TableHeizung`, `TableWasser` | — | eigene Spalte **`SANIERUNG`** |

---

## 4. Der U-Wert: `TableHuellfl`

Die Tabelle der Hüllflächen, je Zeile ein Flächenelement, über `PROJ_ID` an die
Variante gebunden. Vollständige Feldliste des Bestands- und Sanierungsteils:

```
HUELL_ID  PROJ_ID  LFD_NR  KENNZEICHEN  AUSRICHTUNG  KURZBEZ  BAUTEILBEZ
ANZAHL  LAENGE  BREITE  FLAECHE  FLAECHE_BER  FLAECHE_BR  ABZUGSFL  DAEMMFL
WINKEL  RAHMEN  VERSCHATT  DURCHLASSGR  REDFAKTOR  ALPHA  EPSILON  TWD  SONNE
K_ZAHL  K_ZAHL_BER                                   ← Ist
SANBEZ  SANK_ZAHL  SANK_ZAHL_BER  SANDURCHLASSGR     ← Sanierung
SANLAMBDA  SANDICKE
SANKOSTEN  SANKOSTENQM  SANKOSTEN_EE  SANKOSTENQM_EE
BAUTEILINFO  SANINFO  DICKE  UWERTTYP  UUID  REGIONALFAKTOR  ANBAU  UNBEHGVB
```

Feld für Feld die Eingaben des Sanierungs-Dialogs:

| Dialog | Feld |
|---|---|
| Maßnahme | `SANBEZ` |
| Dämmung — cm / W/mK | `SANDICKE` / `SANLAMBDA` |
| **U-Wert (grün)** | **`SANK_ZAHL`** |
| Kosten €/m² und Summe | `SANKOSTENQM`, `SANKOSTEN` |
| „darin enthaltene Kosten nur für Energieeinsparung" | `SANKOSTENQM_EE`, `SANKOSTEN_EE` |
| U-Wert im Ist (Reiter U-Werte) | `K_ZAHL` |

**Ein Bauteil gilt also als saniert, sobald `SANK_ZAHL` gesetzt ist.** Mehr braucht es
nicht; `SANBEZ` und die Kostenfelder sind Beiwerk für Bericht und Wirtschaftlichkeit.

---

## 5. Die Anlagentechnik in der Variante

`TableAnlage` — 120 Felder, davon 36 auf `_ALT` und 18 auf `_NEU`:

```
ALLG_KESSELTYP_ALT   ALLG_BRENNSTOFF_ALT   ALLG_NENNLEIST_ALT   ALLG_BAUJAHR_ALT
ABG_ABGASVERL_ALT    SOL_VORH_ALT          WW_UEBERANL_ALT      …
KESSELTYP_NEU        BRENNSTOFF_NEU        ANZPUMPEN_NEU        WWERNEUERN_NEU
ANLAGEWANDGER_NEU    VERBRAUCH_NEU         ANLINWOHN_NEU        …
```

`TableHeizung` und `TableWasser` bilden den Wärmefluss ab — dieselbe Kette wie im
Ergebnisbild der Software:

```
StrangId  ProjektID  SANIERUNG  Bezeich  Anzahl  Flaeche  GesAnteil
UbergabeText1/2  UbergabeQ  UbergabeQHilf        ← Übergabe
VerteilText1/2   VerteilQ   VerteilQHilf         ← Verteilung
SpeicherText1/2  SpeicherQ  SpeicherQHilf        ← Speicher
Erz1Anteil  Erz1Text1/2  Erz1Brennst  Erz1AZ  Erz1NG  Erz1Fpe  Erz1QE  Erz1QP
```

Achtung: das ist **nicht** dieselbe Anlagentechnik wie im IBP-Blob. Der Energieberater
führt hier seine eigene, vereinfachte Darstellung; die DIN-18599-Rechnung läuft über
`Kernel18599V5.bin`. Welche der beiden bei welchem Rechenverfahren führt
(`RECHENVERFAHREN` in `TableProjekt`), ist noch nicht geklärt.

---

## 6. Aufrufbare Funktionen gibt es nicht

Geprüft, ob die Variantenlogik im verwalteten Code liegt:

| Zeichenkette | `Energie.exe` | 511 verwaltete Module |
|---|:-:|:-:|
| `TableHuellfl` | **ja** | nein |
| `SANK_ZAHL` | **ja** | nein |
| `Variante_IstPaket` | **ja** | nein |
| `VarianteBez` | **ja** | nein |

Alles liegt im **nativen** `Energie.exe`, wie schon die DIN-18599-Erfassung. Kein
DLL-Aufruf, keine Brücke, keine Fabrikmethoden wie im IBP-Modell.

**Aber:** anders als beim IBP-Blob braucht man dafür keine fremde Assembly. Das Format
ist **selbstbeschreibend** — der Dateikopf trägt jeden Feldnamen längenpräfigiert mit
Typ und Breite. Es ist ein Dateiformat-Problem, kein Schnittstellenproblem.

---

## 7. Der Weg zum Ziel

```
PrMedia → eberater.zip herausholen
  └─ TableProjekt lesen, Zeile über VarianteBez finden → deren PROJEKT_ID
     └─ TableHuellfl: Zeilen mit PROJ_ID = dieser Variante
        └─ SANK_ZAHL setzen (optional SANBEZ, SANDICKE, SANLAMBDA, Kosten)
  └─ neu zippen, zurück in PrMedia.Media
```

Wer eine Variante **anlegen** will, braucht mehr — aber nicht die SQL-Modellkopie aus
Abschnitt 1, sondern je einen Satz in sieben Tabellen. Das steht in Abschnitt 11.

Leser und Schreiber für `.BDExit` liegen in
[`werkzeuge/bdexit/`](werkzeuge/bdexit/) (`bde.ps1`, `satz.ps1`).

---

## 8. Das Format `.BDExit` — vollständig entschlüsselt

```
96 19 E0 BD                        Magic
01 00 00 00  18 00 00 00           Version / Kopflänge
4D 00 4C 00  00 00 03 00 00 00     Feldzahl (0x4D = 77) und Weiteres
73 08
08 "HUELL_ID"   04 00 01 00 02 00 01 00
07 "SUBTYPE"    02 00 49 00 08 00  07 "Autoinc"
07 "PROJ_ID"    04 00 01 00 00 00 00 00
06 "LFD_NR"     04 00 01 00 00 00 00 00
0B "KENNZEICHEN" …
```

Es gibt **zwei** Bauarten, und sie zu verwechseln kostet Zeit:

```
FELD (oberste Ebene)   Länge | Name | Typ(2) | Code(2) | ?(2) | Untereinträge(2)
UNTEREINTRAG           Länge | Name | Typ(2) | Code(2) | Nutzlast
                       Code 02 -> 2-Byte-Wert (WIDTH)
                       Code 49 -> Länge(2) + Text (SUBTYPE=Autoinc / Text)
```

### Die Feldtypen folgen einer einzigen Regel

Lange sah das nach einer Liste von Sonderfällen aus. Es ist aber eine Regel, und
`Typ` bedeutet in beiden Zweigen dasselbe — **eine Bytezahl**:

```
Code 73 / 75 (0x49 / 0x4B)   Text. Die LAENGE steht in "Typ" Bytes davor.
sonst                        feste Breite von "Typ" Bytes.
```

| Typ / Code | Bedeutung | im Satz |
|---|---|---|
| `2 / 01` | Ganzzahl klein | int16, 2 Bytes |
| `4 / 01` | Ganzzahl | int32, 4 Bytes |
| `8 / 04` | Gleitkomma | **double, 8 Bytes** |
| `2 / 03` | Kurzfeld (`ABZUGSFL`, `DAEMMFL`) | 2 Bytes |
| `4 / 06` | Datum (`DATUM_ERSTELL`) | 4 Bytes |
| `1 / 49` | Text | **1 Byte** Länge + Zeichen |
| `2 / 49` | Text (`INHOMEMV`) | **2 Bytes** Länge + Zeichen |
| `4 / 4B` | Memo (`Herkunft`, `ZoneID`, die `_BER`-Felder) | **4 Bytes** Länge + Zeichen |

Die `WIDTH` aus dem Kopf ist bei den Memofeldern **kein** Bytemaß, sondern ein Subtyp:
`Herkunft` hat `WIDTH = 2` und trägt trotzdem einen INI-Block von 1418 Bytes. Wer
`WIDTH` als Breite liest, läuft aus dem Satz.

### Jeder Satz beginnt mit einer Anwesenheitskarte

Das war der eigentliche Knoten. Vor den Werten steht eine Bitkarte:

```
Länge     ceil(Feldzahl * 2 / 8) + 1 Byte
          TableHuellfl  77 Felder → 154 Bit → 20 Bytes, +1 = 21
          TableProjekt 116 Felder → 232 Bit → 29 Bytes, +1 = 30
Lage      Das ERSTE Byte gehört nicht zu den Feldern.
          Feld i liegt in Byte 1 + floor(i/4), Schiebung (i % 4) * 2.
Bedeutung 1 = Feld FEHLT im Satz.   0 = Feld steht im Satz.
```

**Fehlende Felder belegen kein einziges Byte.** Deshalb sind die Sätze variabel lang,
und deshalb hat jede Bauteilart ihr eigenes Satzbild — feste Abstände, die bei einer
Wand tragen, gehen bei einem Fenster ins Leere.

Zwei Fehldeutungen, die Zeit gekostet haben: der Satzanfang ist **nicht** das erste
Feld, sondern liegt eine Kartenlänge davor; und das Vorspannbyte zu übersehen
verschiebt jede Feldzuordnung um genau vier Felder.

### Der Satzaufbau, an echten Werten belegt

Ein Fenstersatz aus `TableHuellfl`, feldweise gelesen:

```
HUELL_ID 81 | PROJ_ID 3 | LFD_NR 5 | KENNZEICHEN "FA" | AUSRICHTUNG "N"
[KURZBEZ fehlt] | BAUTEILBEZ "F 011-1 + F 026-1 + F 025-1 + F 024-1"
ANZAHL 4 | LAENGE 1,20 | BREITE 1,00 | [FLAECHE_BER fehlt]
FLAECHE_BR 4,80 | FLAECHE 4,80 | [K_ZAHL_BER fehlt] | K_ZAHL 1,30
ABZUGSFL 0 | DAEMMFL 0 | WINKEL 90 | RAHMEN 30 | DURCHLASSGR 0,50
```

Die Probe: **4 × 1,20 m × 1,00 m = 4,80 m²**, und der Bauteilname nennt genau vier
Fenster. Anzahl, Maße und Fläche gehen auf — die Deutung stimmt bis auf die
Nachkommastelle.

### Die Gegenprobe, die alles trägt

Jeden Satz feldweise auslesen, unverändert neu aufbauen und mit dem Original
vergleichen:

| Tabelle | Sätze | gelesen | identisch zurückgeschrieben |
|---|---:|---|---|
| `TableProjekt` | 2 | exakt bis Dateiende | 2 / 2 |
| `TableHuellfl` | 76 | exakt bis Dateiende | 76 / 76 |
| `TableHausDat` | 2 | exakt bis Dateiende | 2 / 2 |
| `TableAnlage` | 2 | exakt bis Dateiende | 2 / 2 |
| `TableAnbauDat` | 2 | exakt bis Dateiende | 2 / 2 |
| `TableResult` | 2 | exakt bis Dateiende | 2 / 2 |
| `TableZusatz` | 2 | exakt bis Dateiende | 2 / 2 |
| `TableHeizung`, `TableWasser` | 0 | — | — |

**Satzgrenzen müssen damit nicht mehr gesucht werden** — sie ergeben sich beim Lesen.
Jede Heuristik dafür ist überflüssig, und das ist keine Bequemlichkeit: das Raten war
die Ursache jedes gescheiterten Versuchs (Abschnitt 11).

### Der erste Fund: `SANK_ZAHL` unmittelbar hinter `REDFAKTOR`

Der Satz der sanierten Außenwände, Byte für Byte:

```
32700  "…EW 014 + EW 045-3 + EW 045-2 + EW 045"   BAUTEILBEZ
32740  57 4f 9b 86 0d 69 4b 40   = 54,82          FLAECHE     ← Liste Zeile 4
32748  b8 1e 85 eb 51 b8 ce 3f   = 0,24           K_ZAHL      ← Ist
32774  00 00 00 00 00 00 f0 3f   = 1,0            REDFAKTOR
32782  9a 99 99 99 99 99 c9 3f   = 0,20           SANK_ZAHL   ← saniert
```

**`SANK_ZAHL` folgt unmittelbar auf `REDFAKTOR`.** Die Suche nach dem Bitmuster von
0,20 liefert im ganzen Bestand **genau sieben** Treffer — die sieben Außenwände, die
in der Software saniert wurden — und alle liegen im zweiten Block ab Offset 29006,
also bei der Variante. Der erste Block ab 2184 ist der Ist-Zustand.

### Jeder Satz trägt seine Werte zusätzlich im Klartext

Neben den Binärfeldern steht in jedem Satz ein INI-Block mit denselben Angaben:

```
[Herkunft]
Kennzeichen=DA      Winkel=37,9999999999999
Anzahl=1            Ausrichtung=W
Laenge=1            Flaeche_Ber=
Breite=5,47611…     BauteilBez=Roof 001-1
Flaeche=5,47611…    K_Zahl=0,24
Abzugsfl=0          K_Zahl_Ber=
Daemmfl=0           RedFaktor=1
                    DatenmodellGUIDs={E98EE127-…}
```

Das ist die Herkunft aus dem 3D-Modell. Praktisch: Werte lassen sich damit
gegenprüfen, ohne den Binärteil zu entschlüsseln.

### Schreiben funktioniert — am 11.08.2026 durchgeführt

Der vollständige Weg wurde am Testprojekt „Werner Grotz" gegangen:

1. `eberater.zip` aus `PrMedia` gelesen, entpackt
2. in `TableHuellfl.BDExit` die sieben `SANK_ZAHL` der Außenwände von 0,20 auf **0,15**
   gesetzt (je 8 Bytes, Dateigröße unverändert)
3. neu gepackt (75.769 statt 75.770 Bytes) und per `UPDATE PrMedia SET Media = …`
   zurückgeschrieben
4. Software geschlossen, neu geöffnet

**Ergebnis:** Die sieben Zeilen zeigen in der Spalte „Sanierungsmaßnahme" **0,15**.
Und entscheidend — die Software hat **neu gerechnet**: der Verlustbalken springt von
„Wand -7%" auf **„Wand -15%"**, und oben rechts erscheint die Bewertung **EH 85**.
Keine Fehlermeldung, keine Prüfsummenklage.

**Damit ist bewiesen: die Software nimmt einen von außen geänderten Container an und
rechnet mit den Werten.** Es gibt weder eine Signatur noch eine Konsistenzprüfung, die
das verhindert.

Für diesen einen Eingriff genügte der Anker `REDFAKTOR` unmittelbar vor `SANK_ZAHL`.
**Für alles Weitere trägt er nicht** — er gilt nur für Bauteile, die das Feld bereits
haben, und nur für deren Satzbild.

Die „Blöcke von rund 21 Bytes mit `aa`-Muster zwischen den Sätzen", die hier zunächst
als Rätsel notiert waren, sind kein Zwischenraum: es ist die **Anwesenheitskarte am
Satzanfang**. Sie gehört zum folgenden Satz. Damit ist auch geklärt, warum leere
Felder übersprungen wirken — sie stehen gar nicht erst im Satz.

**Sicherung:** `werkzeuge/bdexit/SICHERUNG-eberater-original.zip` hält den Stand vor
dem Eingriff.

---

## 9. Wie die drei Modelle zusammenspielen

Nebeneinander liegen **drei** Darstellungen desselben Gebäudes:

| Ort | Inhalt | Varianten? |
|---|---|---|
| SQL `Bm*` | Geometrie | vollständig kopiert (152 → 296 Elemente) |
| `eberater.zip` | Erfassung des Energieberaters | **zwei Zeilen** in `TableProjekt` — Ist und Variante |
| `Kernel18599V5.bin` | DIN-18599-Objektgraph | **genau einer je Projekt** |

Gemessen am Projekt „Werner Grotz" nach dem Anlegen der Variante:

- `TableProjekt` hat **2 Zeilen** (zwei `[CIM]`-Abschnitte, zwei `sEBT=`-Zeilen). Beide
  `sEBT` sind identisch und tragen die **Ist**-Werte — die Sanierung steckt
  ausschließlich in `SANK_ZAHL` der jeweiligen `TableHuellfl`-Zeilen.
- Der IBP-Blob enthält **38 Bauteile und 17 Fenster** — exakt die 38 Zeilen der
  U-Werte-Liste — und darin für die Außenwände **`fU = 0,24`**, nicht die sanierten
  0,20. Er bildet also den **Ist-Zustand** ab, nicht die Variante.
- `eberater.zip` und `Kernel18599V5.bin` tragen **denselben Zeitstempel** (23:34:43).
  Sie werden zusammen geschrieben; der Blob entsteht offenbar beim Speichern aus dem
  Energieberater-Modell.

**Lesart:** Der Energieberater führt seine Erfassung in `eberater.zip`, wo „saniert"
eine Spalte neben dem Ist ist. Für die DIN-18599-Rechnung wird daraus ein
`DIN18599Building` erzeugt und abgelegt — aber **nur einer**. Das Ergebnis der
Variante wird nicht als zweiter Blob gespeichert; es entsteht beim Rechnen aus Ist +
`SAN*`-Werten.

**Geprüft am 10.08.2026:** In der Software auf die Variante umgeschaltet und
gespeichert. Beide Anhänge wurden neu geschrieben (`StampEdit` 23:16:49), aber:

| | Ergebnis |
|---|---|
| `Kernel18599V5.bin` | **byte-identisch** (gleicher SHA-256), Wände weiterhin `fU = 0,24` |
| `eberater.zip` | geändert — aber nur **`TableZusatz.BDExit`**; `TableHuellfl`, `TableProjekt`, `TableAnlage`, `TableHeizung`, `TableWasser` byte-identisch |

**Der IBP-Blob zeigt also immer den Ist-Zustand**, unabhängig von der aktiven
Ansicht. Und die Variantendaten stehen bereits vollständig im Container.

Was sich in `TableZusatz` geändert hat, ist **nicht** ein Merker für die aktive
Variante. Der Byte-Vergleich (beide Fassungen 212.777 Bytes) zeigt **69 abweichende
Bytes** in 67 Blöcken, durchweg Zahlenwerte in regelmäßigen Abständen von 22 Bytes —
`09 → 0f` an 57 Stellen, `2e → 34` an fünf, dazu `03ba → 0452` (954 → 1106) und
`03b6 → 044e` (950 → 1102). Das sind **neu gerechnete Werte**, keine Schalter.
`TableZusatz` trägt außerdem selbst BinaryFormatter-Abschnitte des IBP-Modells
(`Supplement2Input`, `P0SimplifiedGeometryAssigningFromBuildingSettings`).

### Die aktive Variante wird nicht gespeichert

Gegenprobe am 10.08.2026: in der Software auf **Ist-Zustand** zurückgeschaltet und
gespeichert. Ergebnis über alle drei Zustände hinweg (Ursprung → Variante aktiv →
Ist aktiv):

| | Ergebnis |
|---|---|
| `Kernel18599V5.bin` | **dreimal byte-identisch** (SHA-256 `8A86E0CF…`) |
| `TableProjekt` und alle übrigen Tabellen | **byte-identisch** |
| `TableZusatz` | ändert sich bei jedem Speichern |
| SQL (`PrProjectSetting` u. a.) | **unberührt** — letzte Änderung stammt vom Vortag |

Und die Änderungen in `TableZusatz` kehren beim Zurückschalten **nicht** zurück,
sondern laufen weiter: an denselben Stellen 9 → 15 → 27 und 46 → 52 → 64. Das sind
fortlaufende Zähler beziehungsweise neu gerechnete Werte, kein Merker für die Ansicht.

**Der aktive Zustand wird also weder im Container noch in SQL gehalten** — er ist
Sitzungszustand der Oberfläche. Für Zugriffe von außen ist das eine gute Nachricht:
„aktivieren" muss man nichts. Ist-Zustand und Variante sind zwei gleichrangige Zeilen
in `TableProjekt`; welche Zeile man bearbeitet, entscheidet die `PROJ_ID` an den
`TableHuellfl`-Sätzen, nicht ein Schalter.

Nicht geprüft: `HsetuUsrData` und die Registry — dort läge die zuletzt geöffnete
Ansicht, wenn sie überhaupt irgendwo liegt.

Für die Praxis heißt das: **Der Hebel für Sanierungswerte ist `eberater.zip`, nicht
der Blob.** Wer im Blob U-Werte ändert, ändert den Ist-Zustand. Das Rechenergebnis der
Variante wird nirgends abgelegt; es entsteht beim Rechnen aus Ist + `SAN*`.

### Zwei Wege für die Anlagentechnik

Beim Projekt „Werner Grotz" sind `P58Generators` und `P58Storages` im Blob **leer** —
beim Projekt „Strackerjan" war dort ein Brennwertkessel. Beide sind Wohngebäude nach
GEG 2024. Der Unterschied: bei Strackerjan wurde die „Erfassung DIN 18599" benutzt,
bei Grotz nicht.

Die Anlagentechnik lässt sich also offenbar **auf zwei Wegen** erfassen — vereinfacht
über `TableAnlage` (`…_ALT` / `…_NEU`) und `TableHeizung`/`TableWasser` (`SANIERUNG`),
oder vollständig über den IBP-Graphen. Welcher Weg gilt, dürfte an
`RECHENVERFAHREN` in `TableProjekt` hängen; belegt ist das noch nicht.

## 10. Rezept: einen U-Wert von außen sanieren

Erprobt und bestätigt. Werkzeuge in [`werkzeuge/bdexit/`](werkzeuge/bdexit/).

```powershell
# 1. Container holen
$c = New-Object System.Data.SqlClient.SqlConnection `
     "Server=(localdb)\HSETU;Database=HsetuPrjData;Integrated Security=true"
$c.Open(); $k = $c.CreateCommand()
$k.CommandText = "SELECT Media FROM PrMedia WHERE ProjectUUID='…' AND MediaName='eberater.zip'"
[IO.File]::WriteAllBytes('eberater.zip', $k.ExecuteScalar()); $c.Close()

# 2. entpacken, TableHuellfl.BDExit oeffnen
#    SANK_ZAHL finden: 8-Byte-double, unmittelbar hinter REDFAKTOR (= meist 1,0).
#    Zur Kontrolle: K_ZAHL (der Ist-Wert) steht wenige Felder davor,
#    der Bauteilname als laengenpraefigierter Text davor.
#    Die Bitfolge eines bekannten Werts zu suchen ist der schnellste Einstieg:
#    [BitConverter]::GetBytes([double] 0.20)

# 3. neuen Wert schreiben - gleiche Laenge, Datei bleibt gleich gross
[BitConverter]::GetBytes([double] 0.15).CopyTo($b, $offset)

# 4. neu zippen (dieselben neun Eintragsnamen, keine Ordner)

# 5. zurueckschreiben
$k.CommandText = "UPDATE PrMedia SET Media=@m, MediaSize=@s WHERE ProjectUUID=@p AND MediaName='eberater.zip'"
```

**Die Software muss dabei geschlossen sein** — sonst überschreibt sie beim nächsten
Speichern.

## 11. Eine Variante von außen anlegen

Der Ausgangspunkt: **die Variantenliste kommt aus `TableProjekt`.**

Ebenfalls am 11.08.2026 bewiesen, mit einem risikolosen Eingriff: `VarianteBez` von
`Neue_Variante_Test` auf `Klon_Test_Variante` geändert — **gleiche Länge, 18 Zeichen**,
also keine Strukturänderung. Nach dem Zurückschreiben zeigt die Variantenliste der
Software den neuen Namen.

**Damit steuert `TableProjekt` die Liste.** Eine neue Variante ist also im Kern eine
zusätzliche Zeile dort — und nicht zwingend die 500+ Zeilen SQL, die die Software
beim Anlegen mitschreibt.

### Die Karte des Bestands

`TableHuellfl` (71.686 Bytes) zerfällt sauber in zwei Blöcke:

| Block | Sätze | Offsets | `LFD_NR` | |
|---|---:|---|---|---|
| `PROJ_ID 2` | 38 | 2.184 … 28.378 | 1–38 | Ist-Zustand |
| `PROJ_ID 3` | 38 | 28.988 … 70.745 | 1–38 | die Variante |

`HUELL_ID` läuft durchgehend 39…114. Im Dateikopf steht **`AUTOINCVALUE = 115`** — der
nächste freie Schlüssel. In `TableProjekt` entsprechend **`AUTOINCVALUE = 4`** bei
vorhandenen `PROJEKT_ID` 2 und 3. Beide müssen beim Anlegen mitwandern, sonst vergibt
die Software doppelte Schlüssel.

`VarianteID` und `VarianteBez` liegen in `TableProjekt` beieinander:
`02 00 00 00` gefolgt von `12 "Neue_Variante_Test"` (längenpräfigiert).

### Der Kopf zählt die Sätze mit

Bei Offset 12 stehen **zwei uint16**, nicht eine uint32 — das hatte mein erster
Kopfleser falsch gelesen und „4980813 Einträge" gemeldet:

```
TableHuellfl   4d 00 4c 00   ->   77 Felder,  76 Sätze
TableProjekt   74 00 02 00   ->  116 Felder,   2 Sätze
```

Die Zahl stimmt exakt mit den unabhängig gefundenen Satzanfängen überein. **Wer Sätze
anhängt, muss diesen Zähler mitziehen** — sonst liest die Software nur die alten und
ignoriert den Anhang wortlos.

### Eine Variante besteht aus SIEBEN Sätzen, nicht aus zweien

Das ist die entscheidende Einsicht — und der Grund, warum drei Anläufe scheiterten.
Wer nur `TableProjekt` und `TableHuellfl` klont, bekommt zwar eine sichtbare Variante,
aber eine **kaputte**: ihr fehlen die Gebäudedaten, und die Software hält das Haus
dann für ein **Nichtgebäude — nachträglich nicht mehr umstellbar**.

Je **einen** Satz braucht jede Variante in:

| Tabelle | Schlüssel | Inhalt |
|---|---|---|
| `TableProjekt` | `PROJEKT_ID` | Variantenkopf: Name, `VarianteID` |
| `TableHausDat` | `HAUPTHAUS_ID` | **`BAUJAHR`, `HAUSFORM`, `DACHFORM`** |
| `TableAnlage` | `ANLAGE_ID` | Anlagentechnik |
| `TableAnbauDat` | `ANBAU_ID` | Anbauten |
| `TableResult` | `Result_ID` | Ergebnisse |
| `TableZusatz` | `PROJ_ID` | Zusatzdaten, u. a. der 3D-Pfad |

Dazu `TableHuellfl` mit **je einem Satz pro Bauteil** (hier 38) und eigenem
fortlaufenden `HUELL_ID`. `TableHeizung` und `TableWasser` waren in diesem Projekt
leer und blieben es.

Die Falle: **außer `TableHuellfl` und `TableZusatz` heißt der Projektbezug nirgends
`PROJ_ID`.** Er ist überall schlicht das **erste Feld** der Tabelle und trägt die
Projektnummer — `HAUPTHAUS_ID`, `ANLAGE_ID`, `Result_ID`. Wer nach einer Spalte
namens `PROJ_ID` sucht, findet in fünf von sieben Tabellen nichts und schließt
fälschlich, sie hätten mit der Variante nichts zu tun.

### Der Variantenkopf: vier Felder

Ist-Zustand und Variante unterscheiden sich in `TableProjekt` in **genau vier**
Feldern — alles andere ist identisch:

```
PROJEKT_ID    2  →  3
PROJEKT_NR    1  →  2
VarianteID    fehlt  →  2                    ← beim Ist-Zustand nicht vorhanden
VarianteBez   fehlt  →  "Neue_Variante_Test" ← beim Ist-Zustand nicht vorhanden
```

Der Ist-Zustand ist also nicht „Variante 0", sondern die Zeile **ohne** die beiden
Variantenfelder.

### Fenster sanieren heißt: das Feld anlegen

`SANK_ZAHL` steht in den Fenstersätzen **gar nicht** — die Anwesenheitskarte meldet
„fehlt". Es gibt nichts zu überschreiben; das Feld muss erst eingefügt und in der
Karte freigeschaltet werden. Genau daran scheitert jedes Anker-Verfahren still: es
findet nichts und meldet keinen Fehler.

Als Vorbild dient die in der Software sanierte Wand. Sie trägt:

```
REDFAKTOR   1,0      ← war schon da, auch bei den Fenstern
SANK_ZAHL   0,20     ← das einzige, was hinzukommt
SANBEZ, SANK_ZAHL_BER, SANDICKE, SANLAMBDA, SANKOSTEN*   fehlen auch bei ihr
```

**Ein Bauteil gilt als saniert, sobald `SANK_ZAHL` existiert.** Mehr braucht es nicht.

### Das Rezept

Erprobt am 11.08.2026, Werkzeug:
[`werkzeuge/bdexit/variante-bauen.ps1`](werkzeuge/bdexit/variante-bauen.ps1).

```powershell
# je Tabelle: vollstaendig einlesen - die Satzgrenzen ergeben sich dabei
$t = Tabelle "$Ziel\TableHausDat.BDExit"

# den Satz der Vorlage ueber das ERSTE Feld finden
$key = $t.Kopf.Felder[0].Name              # HAUPTHAUS_ID, ANLAGE_ID, ...
$q   = $t.Saetze | Where-Object { (Wert $_ $key) -eq $VonProj }

# feldweise neu aufbauen, dabei Werte setzen oder ANLEGEN
$satz = BdeSchreib $t.Bytes $t.Kopf $q @{ $key = $NeuProj }

# anhaengen, Satzzaehler und Autowert nachziehen
Sichere $t $satz 1 $auto
```

Zusätzlich:

```
TableProjekt   PROJEKT_NR +1, VarianteID +1, VarianteBez = neuer Name
               AUTOINCVALUE  4 → 5
TableHuellfl   je Bauteil: HUELL_ID fortlaufend ab 115, PROJ_ID = neu
               Fenster (KENNZEICHEN "FA"): SANK_ZAHL anlegen
               AUTOINCVALUE  115 → 153
alle Tabellen  Satzzähler bei Offset 14 um die Zahl neuer Sätze erhöhen
```

Der Name muss **nicht** mehr gleich lang sein wie die Vorlage — beim feldweisen
Aufbau verschiebt sich nichts.

### Ergebnis

```
                Ist-Zustand   Neue_Variante_Test   Variante_Fenster18
HAUSFORM              1              1                    1
Außenwand          0,24           0,24 → 0,20          0,24 → 0,20
Fenster            1,30           1,30                 1,30 → 0,95
```

Die Variante erscheint in der Liste, trägt eigene Zonen und U-Werte und lässt sich
normal weiterbearbeiten. **Die SQL-Modellkopie aus Abschnitt 1 wurde dabei nicht
angerührt** — sie ist zum Anlegen nicht nötig.

### Was die drei Fehlversuche gekostet haben

Der Vollständigkeit halber, weil jeder einen eigenen Fehler hatte:

| # | Fehler | Symptom |
|---|---|---|
| 1 | Satzanfang auf die `HUELL_ID` gelegt — 21 Bytes zu spät, die Anwesenheitskarte gehört zum Satz | Einlesefehler |
| 2 | nur `TableProjekt` geklont, `TableHuellfl` weggelassen | Variante sichtbar, ohne Zonen und U-Werte |
| 3 | fünf Tabellen ergänzt, aber `TableZusatz` über eine Heuristik gefunden — **6 Bytes daneben** | Einlesefehler |

Gemeinsamer Nenner: **überall dort, wo geraten wurde.** Die Heuristik in Versuch 3
suchte „irgendwo den int32-Wert 3" und traf einen Zufallstreffer sechs Bytes hinter
dem echten Satzanfang. Erst der vollständige Satzleser hat das Raten überflüssig
gemacht — und danach ging es auf Anhieb.

Nebenbei gelernt: **die Software sortiert den Container beim Speichern um.** Nach
einem Lauf stand `PROJ_ID 3` vorn und `HUELL_ID` lief bis 152 statt 114. Feste
Offsets sind schon deshalb wertlos.

Zum Vergleich: `TableProjekt` endet auf `01 00`, `TableHuellfl` dagegen auf
`06 00 00 00 00 00`, `TableHeizung` direkt hinter dem Kopf (es hat keine Sätze). Einen
einheitlichen Dateiabschluss gibt es also nicht — die vermeintlichen Abschlussbytes
sind schlicht das Ende des letzten Satzes.

## 12. Anleitung: eine Variante sicher anlegen

Erprobt am 11.08.2026, mehrfach durchlaufen. Wer sich daran hält, bekommt keinen
Einlesefehler — **jeder gescheiterte Versuch hatte seine Ursache in einem
übersprungenen Schritt**, nicht in einer Eigenheit der Software.

### Die Grundregel

> **Nichts raten. Was sich herleiten lässt, wird hergeleitet.**

Feste Offsets, Bitmuster-Suchen und „der Wert steht ungefähr dort" sind die Ursache
aller drei Fehlversuche gewesen. Der Container beschreibt sich selbst vollständig —
es gibt keinen Grund zu schätzen.

### Vorher

| | |
|---|---|
| **Sicherung** | aktuellen Container aus `PrMedia` ziehen und als Datei ablegen. Ohne Rückweg nicht anfangen. |
| **`Energie.exe` prüfen** | muss beendet sein — **auch die verwaiste Instanz ohne Fenster** (siehe Abschnitt 13). |
| **frisch holen** | immer direkt vor dem Bauen aus der Datenbank lesen, nie auf einem Zwischenstand aufbauen. Die Software sortiert um und schreibt neu. |

### Die Schritte

```
 1  Energie.exe prüfen        Get-Process -Name Energie  →  läuft?  Abbruch.
 2  Container holen           SELECT Media FROM PrMedia …   Größe merken!
 3  entpacken                 neun .BDExit, keine Ordner
 4  alle Tabellen einlesen    fortlaufend ab Kopf.Daten, Satz für Satz
                              MUSS exakt am Dateiende enden
                              MUSS so viele Sätze liefern wie der Kopf sagt
 5  Rückschreibprobe          einen Satz unverändert neu bauen
                              MUSS Byte für Byte gleich sein   ← sonst STOPP
 6  Vorlage finden            über das ERSTE Feld der Tabelle (= Projektnummer),
                              nicht über einen Feldnamen "PROJ_ID"
 7  sechs Tabellen klonen     TableProjekt, TableHausDat, TableAnlage,
                              TableAnbauDat, TableResult, TableZusatz
                              je ein Satz, erstes Feld auf die neue Nummer
    dabei TableProjekt        PROJEKT_NR +1, VarianteID +1, VarianteBez = Name
 8  TableHuellfl klonen       ALLE Bauteile der Vorlage
                              PROJ_ID = neu, HUELL_ID fortlaufend ab max+1
 9  Zähler nachziehen         Offset 14 (uint16) um die Zahl neuer Sätze erhöhen
                              AUTOINCVALUE in TableProjekt und TableHuellfl
10  Gegenprobe                alle neun Tabellen erneut vollständig einlesen
11  zippen                    neun Einträge, dieselben Namen, keine Ordner
12  schreiben                 vorher DATALENGTH prüfen == in Schritt 2 gemerkt
                              sonst ABBRECHEN statt überschreiben
                              danach DATALENGTH gegenprüfen
```

Schritte 4, 5, 10 und 12 sind die Sicherungen. Sie kosten Sekunden und fangen genau
die Fehler ab, die sonst erst die Software meldet — dann aber ohne Hinweis worauf.

### Fertig heißt

```powershell
.\variante-bauen.ps1 -Sicherung .\jetzt.zip -Ziel .\neu `
                     -Name 'Variante_XY' -VonProj 4 -NeuProj 5 -Fenster 0.95
```

Das Skript macht die Schritte 3–11 und liest am Ende jede Tabelle noch einmal
vollständig durch. Läuft das durch, ist der Container in sich stimmig.

Einzelne Bauteilarten nachträglich sanieren:

```powershell
.\saniere.ps1 -Ordner .\neu -Proj 5 -Kennzeichen DA -Wert 0.14
```

### Danach

Öffnen. Erscheint *„Beim Einlesen der Projektdaten ist ein Fehler aufgetreten"*:
**„Nein"** wählen, schließen, Sicherung zurückschreiben. Niemals „Ja" — der
Sicherungspunkt der Software ist nicht derselbe wie deine Sicherung.

Prüfen, ob die Variante wirklich vollständig ist — nicht nur, ob sie in der Liste
steht:

| | |
|---|---|
| Variantenliste | neue Zeile mit dem gewählten Namen |
| Flächenelemente | alle Bauteile mit U-Werten, nicht leer |
| **Gebäudeart** | **Wohngebäude** — steht sie auf Nichtwohngebäude, fehlt `TableHausDat` |
| Zonen | vorhanden |

Die dritte Zeile ist die wichtige. Eine Variante kann sichtbar sein und trotzdem
kaputt — und die Gebäudeart lässt sich **nachträglich nicht mehr umstellen**.

---

## 12a. Kontrollmechanismen — warum Selbstprüfungen nicht reichen

Am 13.08.2026 lief ein kompletter Sanierungsfahrplan durch alle Prüfungen und war
trotzdem falsch: die Varianten **zeigten** sanierte U-Werte und **rechneten** mit den
alten. Die Nutzenergie sank um 6 % statt um ein Drittel.

### Die Ursache ist eine Klasse, kein Einzelfall

Derselbe Sachverhalt steht an zwei Stellen:

| | |
|---|---|
| `TableHuellfl.SANK_ZAHL` | was die Oberfläche anzeigt |
| `Kernel18599V5` → `Construction.fU` / `Window.fU` | was gerechnet wird |

Die Software gleicht beides ab — **aber erst, wenn die Variante geöffnet wird.** Ein
von außen gebauter Fahrplan bleibt bis dahin unstimmig, und wer die Ergebnisse
ausliest, ohne jede Variante einmal anzuklicken, bekommt stillschweigend falsche
Zahlen.

Dieselbe Ursache hatten: die Vorlauftemperatur (am Erzeuger gesetzt statt am
Heizkreis), die Wärmepumpen-Senke (dort gesetzt, wo die Software nie schreibt), die
fehlende Warmwasser-Verteilung (Leser *und* Schreiber blind), die verlorene zweite
Übergabe (nur `Emissions[0]` gelesen).

### Warum keine der bisherigen Prüfungen anschlug

Alle waren **Selbstprüfungen**. Sie beantworten dieselbe Frage:

```
Rückschreibprobe byte-identisch     steht da, was ich geschrieben habe?
Satzzahl == Kopf                    steht da, was ich geschrieben habe?
Rundlauf lesen -> schreiben         steht da, was ich geschrieben habe?
```

Keine fragt, ob das Geschriebene **die Stelle erreicht, die rechnet**. Eine
Selbstprüfung kann das grundsätzlich nicht — sie kennt nur die eine Darstellung, die
sie selbst beschrieben hat.

### Die drei Prüfungen, die es können

`werkzeuge/bdexit/pruefe-variante.ps1`:

| | | findet |
|---|---|---|
| **1 Vollständigkeit** | Satz in allen neun Tabellen, Bauteilzahl wie im Ist | halb geklonte Varianten |
| **2 Querprobe** | Bauteilliste **gegen** Rechenmodell, Bauteil für Bauteil | genau diesen Fehler |
| **3 Wirkungsprobe** | sinkt `UA` entlang des Fahrplans monoton? | **auch Fehler an Stellen, die niemand kennt** |

Die dritte ist die wichtigste. Querprobe 2 findet nur, was ich schon kenne — sie
vergleicht zwei Darstellungen, die ich beide benennen kann. Steht der Sachverhalt an
einer **dritten** Stelle, die noch niemand entdeckt hat, schweigt sie. Die
Wirkungsprobe nicht: **bewegt sich die Physik nicht, ist die Maßnahme nicht
angekommen** — unabhängig davon, welche Darstellung übersehen wurde.

Beide schlugen am fehlerhaften Stand unabhängig voneinander an:

```
Querprobe       "Liste sagt U 0.140, Modell rechnet mit 0.240"    Varianten 4, 5, 6
Wirkungsprobe   "UA STEIGT gegenueber der Vorstufe"               2_Dach
```

### Die Regel

> **Ein Schreibvorgang gilt erst als erfolgreich, wenn sich die Größe bewegt hat,
> die er bewegen sollte.** Nicht, wenn er sich zurücklesen lässt.

Praktisch: nach jeder Sanierungsmaßnahme `UA` messen (`ibp-bauteile.exe` gibt es
aus), nach jeder Anlagenmaßnahme die Endenergie. Ändert sich nichts, ist die
Änderung nicht angekommen — auch wenn jede andere Prüfung grün ist.

### Zum Vergleich: wie ein Fahrplan aussieht, der trägt

`20260626_HottCAD_82024`, echte Bauteilaufnahme:

```
Ist-Zustand      UA 246,2 W/K
Fenster/Türe        181,1        -26,4 %
Dach                104,1        -57,7 %
Außenwand            81,0        -67,1 %
Kellerdecke          63,0        -74,4 %
```

Zum Gegenlesen: ein Projekt mit Platzhalter-U-Werten aus dem HottCAD-Import
(26 Außenwände auf exakt 0,240) kommt über **−19,5 %** nicht hinaus. Wenn die
Wirkungsprobe eine auffällig kleine Wirkung meldet, ist die erste Frage deshalb
nicht „was ist am Werkzeug kaputt", sondern **„trägt der Ist-Zustand echte
Bauteile?"**

---

## 13. Fehlerquellen

Alle hier aufgeführten Fälle sind eingetreten, keiner ist theoretisch.

### Was einen Einlesefehler auslöst

| Ursache | woran man es merkt |
|---|---|
| **Satzgrenze geraten.** Eine Suche nach „irgendwo steht der Wert *n*" trifft Zufallstreffer — in `TableZusatz` sechs Bytes hinter dem echten Satzanfang. | Einlesefehler, ohne Hinweis worauf |
| **Satzanfang auf das erste Feld gelegt.** Die Anwesenheitskarte (21 bzw. 30 Bytes) gehört zum Satz. Sonst besteht jeder Klon aus „Ende von Satz *i* + Vorspann von Satz *i+1*". | Einlesefehler |
| **Satz abgeschnitten**, weil die letzten Bytes der Datei als Abschluss gedeutet wurden. Einen einheitlichen Dateiabschluss gibt es nicht. | Einlesefehler |

Der gemeinsame Nenner: **überall dort, wo geraten wurde.** Mit dem fortlaufenden
Satzleser (Abschnitt 8) entfällt jede dieser Fehlerquellen.

### Was still schiefgeht — ohne Fehlermeldung

Diese Fälle sind gefährlicher, weil nichts sie meldet:

| Ursache | Folge |
|---|---|
| **Nur `TableProjekt` + `TableHuellfl` geklont.** | Variante erscheint, gilt aber als **Nichtwohngebäude — nachträglich nicht änderbar**. Es fehlt `TableHausDat` mit `HAUSFORM`. |
| **Nur `TableProjekt` geklont.** | Variante erscheint ohne Zonen und ohne U-Werte. |
| **Satzzähler bei Offset 14 nicht erhöht.** | Die Software liest die neuen Sätze gar nicht und meldet nichts. Die Liste bleibt bei der alten Anzahl. |
| **`AUTOINCVALUE` nicht hochgezählt.** | Die Software vergibt beim nächsten Anlegen doppelte Schlüssel. |
| **Ein Feld überschreiben wollen, das fehlt.** `SANK_ZAHL` existiert bei unsanierten Bauteilen **nicht** — bei allen 17 Fenstern zum Beispiel. Ein Anker-Verfahren findet nichts und meldet keinen Fehler. | Der Wert steht nachher nicht drin. Das Feld muss angelegt werden: Bit in der Karte löschen und 8 Bytes einfügen. |
| **Feste Abstände über Bauteilarten hinweg.** Fehlende Felder belegen kein Byte, also hat jede Bauteilart ihr eigenes Satzbild. Was bei einer Wand trägt, geht beim Fenster ins Leere. | falscher Wert oder gar keiner |

### Was von außen überschrieben wird

| Ursache | Folge |
|---|---|
| **`Energie.exe` läuft beim Schreiben.** | Die Software überschreibt beim nächsten Speichern kommentarlos. |
| **Verwaiste Instanz.** Das Schließen des Fensters beendet den Prozess nicht zuverlässig: `MainWindowHandle 0`, kein Titel, mehrere hundert MB. In dieser Sitzung zweimal aufgetreten — einmal lief sie **34 Stunden**. | dasselbe, nur unsichtbar. Der Prozesscheck fängt sie, die Sichtprüfung am Bildschirm nicht. |
| **Auf einem Zwischenstand gebaut.** Die Software schreibt den Container bei jedem Speichern neu und **sortiert dabei um** — nach einem Lauf stand `PROJ_ID 3` vor 2, und `HUELL_ID` lief bis 152 statt 114. | Der eigene Stand überschreibt die Arbeit der Software. Abhilfe: vor dem `UPDATE` prüfen, dass `DATALENGTH` noch dem entspricht, aus dem gebaut wurde. |

### Fallen in PowerShell

Kosten Zeit, ohne mit dem Format zu tun zu haben:

| | |
|---|---|
| `byte[] + byte[]` ergibt `Object[]` | vor der Übergabe nach `[byte[]]` wandeln |
| Rückgabe eines Feldes wird **aufgefaltet** | `return ,[byte[]] $x` — das führende Komma ist nicht optional |
| **Variablennamen sind nicht Groß-/Kleinschreibungs-empfindlich** | ein Zähler `$fenster` überschreibt den Parameter `$Fenster` |
| Nicht-ASCII in einer `.ps1` ohne BOM | wird als ANSI gelesen; ein Gedankenstrich beendet dann eine Zeichenkette |

---

## 14. Was offen ist

Erledigt seit dem letzten Stand:

- ~~Der fortlaufende Satzleser~~ — steht, alle neun Tabellen lesen und schreiben
  verlustfrei (Abschnitt 8).
- ~~Eine Variante anlegen~~ — erprobt, ohne SQL-Modellkopie (Abschnitt 11).

Offen:

- **Wodurch sich die beiden Wege der Anlagenerfassung entscheiden** (`TableAnlage` des
  Energieberaters gegen den IBP-Graphen). Verdacht weiterhin `RECHENVERFAHREN`.
- **`TableZusatz`** — lesbar, aber inhaltlich ungeklärt. Trägt eigene
  BinaryFormatter-Abschnitte des IBP-Modells und ändert sich bei jedem Speichern.
- **Der IBP-Blob bleibt beim Anlegen unberührt.** Die neue Variante rechnet
  offenbar aus Ist + `SAN*`; ob das für alle Rechenverfahren gilt, ist nicht geprüft.
- **`4 / 06` (Datum)** wird nur roh durchgereicht, nicht gedeutet. Zum Klonen reicht
  das; wer ein Datum *setzen* will, muss die Kodierung noch klären.
- **Anlagentechnik je Variante ändern.** Der Satz in `TableAnlage` gehört jetzt der
  Variante und trägt `…_ALT` / `…_NEU` — geschrieben wurde dort noch nichts.
