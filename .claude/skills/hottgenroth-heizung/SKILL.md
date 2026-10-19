---
name: hottgenroth-heizung
description: Die Anlagentechnik eines Hottgenroth-Projekts von außen setzen — Heizung, Speicher, Warmwasser nach DIN 18599, je Variante, mit Wirkungsprobe an der Endenergie. Auslöser: Heizung konfigurieren, Wärmepumpe einbauen, Anlagentechnik setzen, Kessel tauschen, Vorlauftemperatur ändern, Anlage von Projekt A nach B übernehmen, Maßnahmenpaket Anlagentechnik, "die Variante rechnet noch mit dem alten Kessel", "Keine Heizung vorhanden".
---

**Stand:** teilweise gemessen. Belegt ist, dass die Software eine vollständig von
außen erzeugte Anlage **annimmt und behält** (12.08.2026), dass der Rundlauf
lesen→löschen→setzen über 84 reale Projekte läuft, und dass die
Auslegungstemperatur an drei Stellen hängt (13.08.2026). Zwei Werkzeuge der Kette
sind **neu am 26.09.2026** und an vier Containern geprüft, aber noch nicht in
einem vollen Durchlauf am Kundenprojekt: `hole-kernel.ps1` und
`zeige-heizung.ps1`.

**Was daraus folgt: zeigen, nicht behaupten.** Solange die Wirkungsprobe aus
Schritt 8 nicht gelaufen ist, ist eine gesetzte Heizung eine *geschriebene*
Heizung, keine *gerechnete*. Den Unterschied hat diese Kette einmal ein ganzes
Maßnahmenpaket gekostet.

## Zwei Wege — erst den kurzen prüfen

Seit dem 26.09.2026 gibt es die Kette **auch über MCP**, für Projekte auf einem
angemeldeten Arbeitsplatz:

| | MCP | von Hand |
|---|---|---|
| lesen | `get_hottgenroth_heizung` | die Kette unten |
| setzen | `set_hottgenroth_heizung` | die Kette unten |
| Voraussetzung | angemeldeter Arbeitsplatz, `hottgenroth:schreiben` | Zugriff auf den Rechner |

**Nimm MCP, wenn das Projekt auf einem Arbeitsplatz liegt.** Die Werkzeuge stellen
dieselben Schritte zusammen, prüfen die Kette vorab und protokollieren jeden
Befehl am Vorgang; Einzelheiten in [docs/ki-hottgenroth.md](../../../docs/ki-hottgenroth.md).
Der Ablauf unten bleibt maßgeblich für alles, was die Werkzeuge nicht abdecken —
eigene Felder, Diagnose, ein Projekt außerhalb eines Arbeitsplatzes — und
beschreibt, was dort tatsächlich passiert.

**Was auch über MCP ein Mensch tun muss: rechnen lassen** (Schritt 7). Daran
ändert kein Werkzeug etwas.

## Worum es geht

Die DIN-18599-Anlagentechnik liegt **nicht in SQL-Tabellen**, sondern als
.NET-BinaryFormatter-Objektgraph in einem Blob — dem Fraunhofer-IBP-Modell.
Dieser Ablauf ändert ihn von außen: Heizung anlegen, Wärmepumpe einbauen,
Auslegung ändern, Anlage von einem Projekt in ein anderes übernehmen.

**Jede Variante führt ihre eigene Anlagentechnik.** Ein Maßnahmenpaket
„Anlagentechnik" ist genau das: dieselbe Hülle, ein anderer Blob.

## Der Weg nicht verwechseln

Es gibt **zwei** Erfassungswege, und sie teilen keine Felder:

| Weg | wo | wer liest das |
|---|---|---|
| **DIN 18599** | Blob `Kernel18599V5` | dieser Ablauf |
| **vereinfacht (DIN 4701-10)** | `TableAnlage`, 36 × `…_ALT` / 18 × `…_NEU` | der alte Erfassungsweg |

**Die `…_ALT`/`…_NEU`-Felder gehören ausschließlich zum vereinfachten Weg — nie
anfassen.** Die DIN-18599-Erfassung schreibt in `TableAnlage` nur
Beschreibungstexte (`Beschr_Heiz`). `TableHeizung` ist **Ergebnis**, keine
Eingabe.

Und: **die Quelle ist `TableZusatz.Kernel18599V5` je Variante.** Der Anhang
`PrMedia` / `Kernel18599V5.bin` ist nur eine Kopie des gerade aktiven Modells —
wer nur ihn schreibt, sieht in der Software **nichts**, sie überschreibt ihn beim
nächsten Öffnen.

## Vorbedingungen

- Die Werkzeuge liegen in `C:\Projekte_Dev\hsetu-decompiled\werkzeuge\`
  (`ibp/` für den Graphen, `bdexit/` für den Container). Das ist **außerhalb des
  Repos**.
- Die `ibp-*.exe` sind **.NET Framework 4.8, x64** und laden
  `DIN18599DataModel.dll` aus `C:\Program Files\HSETU\Energieberater2022`. Ohne
  installierten Energieberater läuft nichts. In .NET 10 gibt es den
  `BinaryFormatter` nicht mehr — **der Agent auf dem Berater-PC kann diesen
  Schritt nicht selbst tun**, er führt über diese Werkzeuge.
- **`Energie.exe` muss beim Zurückschreiben zu sein.** Ein Prozess ohne Fenster
  zählt auch: einmal lief eine verwaiste Instanz 34 Stunden und hat jeden
  Schreibvorgang rückgängig gemacht. `container.ps1` bricht mit der PID ab.

## Die Kette

```powershell
cd C:\Projekte_Dev\hsetu-decompiled\werkzeuge\bdexit

.\container.ps1      -Projekt 'Name' -Ordner .\arbeit            # 1  holen + sichern
.\zeige-heizung.ps1  -Ordner .\arbeit                            # 2  Ausgangswert
.\hole-kernel.ps1    -Ordner .\arbeit -Proj 2 -Blob .\blob.bin   # 3  Blob herauslösen
..\ibp\ibp-anlage-lesen.exe .\blob.bin > .\anlage.json           #    Ist-Anlage als JSON
                                                                 # 4  JSON bearbeiten ← HALT
..\ibp\ibp-delete-heating.exe .\blob.bin .\blob-leer.bin         # 5  alte Heizung raus
..\ibp\ibp-anlage-setzen.exe  .\blob-leer.bin .\blob-neu.bin .\anlage.json
.\setze-kernel.ps1   -Ordner .\arbeit -Proj 2 -Blob .\blob-neu.bin
.\container.ps1      -Projekt 'Name' -Ordner .\arbeit -Zurueck   # 6  zurück ← HALT
                                                                 # 7  Software: Variante öffnen
.\container.ps1      -Projekt 'Name' -Ordner .\pruef             # 8  Wirkungsprobe
.\zeige-heizung.ps1  -Ordner .\pruef -Fahrplan 2,3,4
```

`-Vorschau` bei `container.ps1` zeigt, was sich ändern würde, ohne zu schreiben.
**Immer zuerst damit laufen.**

---

## 1 — Projekt und Variante wählen

`container.ps1 -Projekt` nimmt einen Teil des Projektnamens oder die UUID; ein
mehrdeutiger Name wird **abgewiesen statt geraten**. Beim Holen wird immer
gesichert (`eberater-ORIGINAL.zip` samt SHA-256).

Welche Variante gemeint ist, muss **explizit** sein — nie „die erste". Die
Variantennummern zeigt Schritt 2; `PROJ_ID 2` ist üblicherweise der Ist-Zustand.

**Frag nach, wenn der Berater die Variante nicht genannt hat.** „Heizung setzen"
kann den Ist-Zustand meinen (Bestandskessel erfassen) oder ein Maßnahmenpaket
(Wärmepumpe). Das sind verschiedene Aufträge.

## 2 — Den Ausgangswert messen, bevor etwas geändert wird

```powershell
.\zeige-heizung.ps1 -Ordner .\arbeit
```

Das ist die Zahl, gegen die in Schritt 8 verglichen wird. Ohne sie gibt es keine
Wirkungsprobe, sondern nur ein Gefühl.

Steht bei der Zielvariante **NICHT GERECHNET**, ist das kein Fehler, sondern der
Normalfall bei einer frisch angelegten Variante — sie führt ein Modell, hat aber
noch kein Ergebnis. Steht es beim **Ist-Zustand**, hat das Projekt noch keine
DIN-18599-Erfassung; dann ist Schritt 3 leer und die Anlage wird neu gebaut.

## 3 — Die vorhandene Anlage lesen

```powershell
.\hole-kernel.ps1 -Ordner .\arbeit                            # welche Varianten haben ein Modell?
.\hole-kernel.ps1 -Ordner .\arbeit -Proj 2 -Blob .\blob.bin
..\ibp\ibp-anlage-lesen.exe .\blob.bin > .\anlage.json
```

Das JSON (rund 1,3 KB) enthält **nur die Felder, die beim Anlegen gebraucht
werden**. Alles Abgeleitete — Wirkungsgrade, Hilfsenergie, Leitungslängen —
bleibt draußen: das rechnet das Modell selbst, und wer es vorgibt, bringt die
Oberfläche zum Hängen.

Gelesenes lässt sich unverändert wieder setzen: `bauart` gilt in der Kurzform
(`HeatPump`) **und** als voller Klassenname (`P58HeatGeneratorHeatPump`). Eine
Bauart, die das Modell nicht kennt, **bricht ab** — sie wird nicht still zu einem
Kessel. Genau das war sie einmal, in 13 von 84 Projekten, ohne eine Meldung.

Tiefer sehen, wenn etwas unklar ist: `ibp-heating.exe blob.bin` zeigt die
Verdrahtung, `ibp-heating.exe --sammlungen` die echten Sammlungsnamen (der
Heizkreis heißt `CircuitHeatWater`, nicht `Circuits`), `ibp-api.exe` alle 746
Typen mit Fabrikmethoden und Aufzählungen. **Namen und Zahlen nicht raten** —
dafür sind diese drei da.

## 4 — Die Zielanlage beschreiben · HALTEPUNKT

Das JSON aus Schritt 3 bearbeiten, oder von einem Vorgabesatz ausgehen:

| Vorgabesatz | wofür |
|---|---|
| `..\ibp\vorgaben\waermepumpe-sanierung.json` | Standardfall: 55/45, Heizkörper |
| `..\ibp\vorgaben\waermepumpe-flaechenheizung.json` | hohe EH-Stufe: 35/28, Flächenheizung |

**Kopieren und projektspezifisch ergänzen, nicht fest verdrahten.** Woher jeder
Wert stammt, steht in `DIN18599-ANLAGENTECHNIK.md`, Abschnitt „Vorgabesatz
Wärmepumpe".

Was dabei immer dazugehört, steht in eigenen Regeln und ist hier nur der
Hinweis: **der hydraulische Abgleich ist Teil jeder Wärmepumpensanierung**, und
zu einem EH-Haus gehört eine **Lüftungsanlage** — eine Wärmepumpe allein reicht
nicht.

**Halt hier an und leg dem Berater vor, was gesetzt werden soll** — in Klartext,
nicht als JSON: Bauart, Brennstoff, Auslegung, Übergabe, Regelung, Abgleich.
Genau hier fallen Verwechslungen auf, die später niemand mehr sieht.

## 5 — Den Blob bauen

```powershell
..\ibp\ibp-delete-heating.exe .\blob.bin .\blob-leer.bin
..\ibp\ibp-anlage-setzen.exe  .\blob-leer.bin .\blob-neu.bin .\anlage.json
```

Die alte Heizung **erst entfernen**, sonst stehen zwei Anlagen im Modell.
`ibp-delete-heating` geht über die Delete-API und lässt die Pooltypen für
Übergabe, Leitungen und Pumpen stehen — genau wie die Software. Nicht
„aufräumen", was sie auch nicht aufräumt.

**Vor dem Schreiben vergleichen**, nicht danach:

```powershell
..\ibp\ibp-heating.exe .\blob-neu.bin > .\neu.txt
Compare-Object (Get-Content .\neu.txt) (Get-Content ..\ibp\referenz-heizung-konfiguriert.txt)
```

`referenz-heizung-konfiguriert.bin/.txt` ist ein Stand, den **die Software selbst**
geschrieben hat. Beim ersten Nachbau blieben so elf abgeleitete Kennwerte übrig —
alles Strukturelle war deckungsgleich, und das war bekannt, **bevor** geschrieben
wurde.

## 6 — Zurückschreiben · HALTEPUNKT

```powershell
.\setze-kernel.ps1 -Ordner .\arbeit -Proj 2 -Blob .\blob-neu.bin
.\container.ps1    -Projekt 'Name' -Ordner .\arbeit -Vorschau     # erst zeigen
.\container.ps1    -Projekt 'Name' -Ordner .\arbeit -Zurueck
```

**Das verändert das Kundenprojekt auf dem Rechner eines Menschen.** Vor dem
`-Zurueck` die Freigabe des Beraters einholen, mit der `-Vorschau` daneben.

`container.ps1` trägt die vier Regeln selbst: Energie.exe muss zu sein, beim
Holen wurde gesichert, vor dem Schreiben läuft der Prüfstein über alle neun
Tabellen, danach die Gegenprobe aus der Datenbank. Nur geänderte Tabellen werden
ersetzt.

## 7 — Die Software rechnen lassen

**Dieser Schritt ist ein Mensch, keine Automatisierung.** Der Berater öffnet das
Projekt **und die betroffene Variante** und speichert.

Das ist nicht verzichtbar: der Blob wird beim Anlegen einer Variante unverändert
mitkopiert, und die Software gleicht ihn **erst beim Öffnen der Variante** ab.
Nicht geöffnete Varianten rechnen mit den alten Werten — genau so sank einmal die
Nutzenergie um 6 % statt um ein Drittel, durch alle Prüfungen hindurch.

## 8 — Wirkungsprobe · verpflichtend

```powershell
.\container.ps1     -Projekt 'Name' -Ordner .\pruef       # frisch holen, nicht .\arbeit
.\zeige-heizung.ps1 -Ordner .\pruef -Fahrplan 2,4,5,6,7,8
```

**Frisch holen ist der Punkt.** Gemessen wird, was die Datenbank sagt, nicht was
im Arbeitsordner liegt — sonst prüft man die eigene Schreibarbeit.

Drei Ausgänge:

| Ausgabe | heißt |
|---|---|
| Endenergie bewegt sich | angekommen |
| **NICHT GERECHNET** | kein Satz in `TableHeizung` — Schritt 7 fehlt, oder die Software hat den Graphen verworfen |
| Endenergie unverändert | geschrieben, aber nicht angekommen |

Bei den letzten beiden ist die erste Frage **nicht** „was ist am Werkzeug
kaputt", sondern: hat die Software `Beschr_Heiz` gesetzt? Steht dort „Keine
Heizung vorhanden", hat sie den Graphen gelesen und nicht verstanden — dann
gegen `referenz-heizung-konfiguriert.txt` vergleichen.

Ein Beispiel für eine bestandene Probe, aus einem echten Fahrplan:

```
  Ist-Zustand            35.788 kWh/a   (Ausgangspunkt)   Brennwert-Kessel, Erdgas E
  Fenster/Türe           28.805 kWh/a      -6.983 (-19,5 %)
  …
  Anlagentechnik          2.014 kWh/a     -15.065 (-88,2 %)  Wärmepumpe Luft-Wasser
```

---

## Fallstricke

Jeder hat mindestens einen Fehlschlag gekostet:

- **`pID` darf nie leer sein.** Sonst legt die Fabrik das Objekt an, gibt es
  zurück — und trägt es **nicht in die Sammlung** ein, ohne Fehlermeldung. Die
  Sammlungen sind nach Kennung geschlüsselt.
- **Die `b*_Standard`-Flags bleiben auf `True`.** Sie auszuschalten und Kennwerte
  von Hand zu setzen hat die Oberfläche unbrauchbar gemacht — kein Fenster mehr,
  Prozess beenden. Wer sie ausschaltet, muss *alle* abhängigen Felder kennen, und
  die Liste ist nicht bekannt.
- **Die Auslegungstemperatur steht an drei Stellen**, alle drei müssen
  zusammenpassen: am Heizkreis, an der Wärmepumpe selbst, und die „niedrige
  Temperaturebene". Fehlt die dritte, bleibt die Arbeitszahl auf der hohen
  Temperaturebene, **obwohl 35/28 dasteht**. `ibp-anlage-setzen.exe` leitet sie
  aus der Vorlauftemperatur ab (≤ 45 °C) und meldet sie.
  *Maßgeblich ist `heizung.auslegung` am Kreis;* `vorlauf` am Erzeuger ist
  optional und wird nur gesetzt, wenn das JSON den Schlüssel führt. Ein echtes
  Flächenheizungsprojekt führt am Kreis 35/28 und am Erzeuger **0** — das ist
  kein Fehler. Trägt der Erzeuger aber einen Wert, muss er zum Kreis passen.
- **Kein Feld aus einer anderen Bauart übernehmen.** Regelung, Bauart-Kennung und
  `fTemperatureRise` heißen bei Kessel/Heizkörper anders als bei
  Wärmepumpe/Flächenheizung — teils mit **gleichen Zahlen und anderer
  Bedeutung**. Die Senke der Wärmepumpe (`ftheta_si_out/in`) **nie setzen**.
- **`enumAmbientType = 2` allein genügt nicht.** Ein Rohr „in Zone" braucht
  zusätzlich den Zoneneintrag in der Verweisliste, sonst schreibt das Modell die
  Verluste **niemandem** gut und steigt wortlos aus. Erst anhängen
  (`ibp-sammlung.exe`), dann den Schalter setzen.
- **Nichts von Hand zusammenstecken.** Für Geräte, Einheiten, Kreise, Zonen gibt
  es Fabrikmethoden; sie setzen Kennungen und Querverweise selbst. Brennstoffe
  liegen fertig im Modell (26 Stück) — man legt keinen an, man verweist.

## Grenzen

- **Geometrie fließt nicht mit.** Ein Projekt, das nur HottCAD hat, trägt einen
  Blob von ~46 KB mit einer leeren Standardzone „Wohnen" — keine Bauteile, keine
  Zonengeometrie. Die Anlagentechnik braucht aber eine Zone, auf die die Übergabe
  zeigt. Bei einem solchen Projekt zuerst die Erfassung in der Software, dann
  dieser Ablauf.
- **Lüftung führt das Austauschformat nicht** — `ibp-anlage-lesen/-setzen`
  kennen Heizung, Speicher und Warmwasser, sonst nichts. Auch über MCP nicht.
  **Dafür gibt es ein eigenes Programm**, in keiner Doku beschrieben:

  ```powershell
  ..\ibp\ibp-rv-setzen.exe blob.bin neu.bin wrg=0.8 vorwaermung=0 zone=0
  ```

  Es legt `UnitRV` und `CircuitHeatAirRV` an; `wrg` landet in
  `UnitRV[0].feta_WRG`, `vorwaermung` schaltet allein
  `bElectricalPreheating` (bei dezentralen Geräten aus — die lösen den
  Frostschutz anders). **Nach dem Lauf `UnitRV[0].strName` berichtigen:** das
  Programm schreibt „Lueftungsanlage 1" ohne Umlaut, und der Name landet im
  Ausdruck.

  Erprobt am 27.09.2026 an `V4DZX_Nadine Klenke`, MP5: die Struktur ist
  **deckungsgleich mit einem Stand, den die Software selbst geschrieben hat**
  (`EG2KU_Hesse_260815`: `UnitRV` 864 Zeilen, `CircuitHeatAirRV` 714, 218
  Felder, gleiche Verdrahtung), UA unverändert. Was das Werkzeug anders
  vorgibt als die Software: `fp_el_Vent` 0,35 statt 0,20, `enumFanType` 1
  statt 0, `bRVHeatExchanger` True statt False — und die Software hängt ihrer
  Einheit einen Katalogschlüssel an (`strAdditionalInfo =
  Lüftungssystem=RV_A2222`). Prüfen, ob das für das Projekt passt.

  **Noch offen:** ob die Software `TableAnlage.Beschr_Luft` beim Rechnen
  selbst nachzieht. Tut sie es nicht, fehlt im iSFP die Komponente
  `SK_LUEFTUNG` — dann von Hand setzen, wie bei `Beschr_Heiz`.

  Förderseitig (BEG EM, Richtlinie 17.08.2026, Nr. 2.1.1, Wohngebäude):
  Anlagen mit Wärmeübertrager brauchen **WBG ≥ 80 % bei P_el,Vent ≤ 0,45
  W/(m³/h)** oder **WBG ≥ 75 % bei ≤ 0,35**. Der WBG der Richtlinie ist
  nicht dasselbe wie `feta_WRG` nach DIN 18599 — Hesse steht dort auf 0,70
  und wird trotzdem gefördert.

## Nachschlagen

- `C:\Projekte_Dev\hsetu-decompiled\DIN18599-ANLAGENTECHNIK.md` — Belege,
  Feldzuordnung, Werkzeugtabelle, Vorgabesatz Wärmepumpe
- `werkzeuge/ibp/README.md` — die Programme im Einzelnen
- `werkzeuge/bdexit/README.md` — Container und Varianten
- Bauteilseite desselben Projekts: Skill `hottgenroth-bauteile`
