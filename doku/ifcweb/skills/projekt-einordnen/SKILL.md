---
name: projekt-einordnen
description: Nach der Projektwahl feststellen, ob das Projekt leer ist oder schon bearbeitet - und bei einem bearbeiteten den ganzen Bestand lesen, bevor irgendetwas getan wird. Ausloeser - Projekt ausgewaehlt, was ist in dem Projekt drin, leeres Projekt, bestehendes Projekt, Kontext laden, Projekt analysieren.
erprobungsstand: erprobt-lesend
---

**Stand:** Rein lesend, am Bestand ausgezaehlt (22.08.2026, 107 Projekte). Es
wird nichts geschrieben.

---

Steht das Projekt fest ([[projekt-waehlen]]), **sieh nach, was darin ist, bevor
du irgendetwas tust.** Zwei Wege, und der Unterschied ist nicht kosmetisch: im
einen kann nichts verlorengehen, im anderen alles.

## Leer ist nicht gleich leer

Ausgezählt über alle 107 Projekte — drei Zustände, nicht zwei:

| Zustand | Projekte | woran erkennbar |
|---|---|---|
| **völlig leer** | 3 | keine Geschosse, keine Bauteile, keine Räume, keine Zonen |
| **nur Geschosse** | 5 | Geschosse da, aber nichts darin |
| **bearbeitet** | 99 | alles andere |

```sql
SELECT (SELECT COUNT(*) FROM BmFloor   f WHERE f.ProjectUUID = '<UUID>') AS Geschosse,
       (SELECT COUNT(*) FROM BmElement e WHERE e.ProjectUUID = '<UUID>') AS Bauteile,
       (SELECT COUNT(*) FROM BmRoom    r WHERE r.ProjectUUID = '<UUID>') AS Raeume,
       (SELECT COUNT(*) FROM BmZone    z WHERE z.ProjectUUID = '<UUID>') AS Zonen
```

**Bei `BmElement` nicht auf `RepositoryType` filtern.** Ein frisch gezeichnetes
Projekt führt seine Bauteile in Repo 3, ein gerechnetes in Repo 1. Wer nur eines
zählt, hält das andere für leer — siehe [[bmelement-zwei-repositories]].

## Weg A — völlig leer

> **„Leeres Projekt gefunden."**

Dann direkt weiter im Ablauf: Stufe 1, Kubatur. Sag, welche Unterlagen du
brauchst. Kein Grund für eine Analyse — es gibt nichts zu analysieren, und ein
langer Bericht über nichts kostet nur Zeit.

## Der Zwischenfall — nur Geschosse

Nicht als „leer" durchwinken. Sag konkret, was da ist:

> „Das Projekt ist bis auf die Geschossstruktur leer — es hat EG, OG und DG, aber
> keine Wände. Ich baue die Ringe in diese vorhandenen Geschosse hinein."

Der Unterschied zählt, weil die Geschosse ein **Ist-Stand** sind, gegen den
abgeglichen wird (siehe `schema/gebaeudebeschreibung.md`): passen Namen und Höhen zu
dem, was der Nutzer will, bleiben sie stehen. Ein Geschoss zu löschen, weil es
„eh leer war", nimmt ihm seine Höhenlage — und die steht nicht in den Plänen.

## Weg B — bearbeitet

> **„Existierendes Projekt gefunden."**

Erst **lesen**, dann bereitstehen. Nichts vorschlagen, nichts anfassen, solange
du den Bestand nicht kennst — sonst berätst du über ein Gebäude, das du nicht
gesehen hast.

### Was gelesen wird

**1. Geometrie** — `projekt_lesen`. Geschosse mit Höhenlage, Bauteile je
Geschoss, Außenkontur je Geschoss. Das ist der eine Aufruf, der die Zeichnung
erschließt.

**2. Bauteile** — Arten, Stärken, und vor allem: **wie viele ohne
Katalogzuweisung**. Ein Bauteil ohne Katalogverweis hat keinen belastbaren
U-Wert und rechnet still falsch.

```sql
SELECT e.ElementType, COUNT(*) AS Anzahl,
       SUM(CASE WHEN e.CatalogBasisUUID IS NULL
                  OR e.CatalogBasisUUID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                THEN 1 ELSE 0 END) AS ohne_Katalog
FROM   BmElement e
WHERE  e.ProjectUUID = '<UUID>' AND e.RepositoryType = 1
GROUP  BY e.ElementType ORDER BY 2 DESC
```

`ElementType`: **1** Wand · **2** Fenster · **3** Tür · **4** Decke · **5** Dach ·
**11** Bodenplatte. Übersetz die Zahlen, bevor du sie zeigst — eine Tabelle aus
Typnummern ist keine Auskunft.

Ausprobiert an einem Projekt mit 152 gerechneten Bauteilen: 89 Wände (40 ohne
Katalog), 19 Türen (2), 18 Decken (0), 12 Fenster (8), 10 Bodenplatten (0),
3 Dächer (3). Also **54 von 152 ohne belastbaren U-Wert** — das ist der Befund,
den so eine Abfrage sichtbar macht und der sonst niemandem auffällt.

**Die Spalte sitzt auf `BmElement`, nicht auf `BmElementDimensioning`.** Der
erste Entwurf dieses Skills verband die falsche Tabelle und lief in „Invalid
column name" — genau der Fehler, vor dem der Gedächtniseintrag warnt.

Der Wert `aaaaaaaa-…` ist der **Sentinel** für „nicht zugewiesen", nicht `NULL` —
wer auf `IS NULL` prüft, findet nichts und meldet fälschlich „alles zugewiesen".
Siehe [[bmelement-katalogzuweisung-catalogbasisuuid]].

**3. Anlagentechnik und iSFP** — beides liegt als Blob in `PrMedia`, nicht in
eigenen Tabellen:

```sql
SELECT MediaName, CONVERT(char(10), StampEdit, 104) AS Stand
FROM   PrMedia WHERE ProjectUUID = '<UUID>'
  AND  MediaName IN ('eberater.zip', 'Kernel18599V5.bin', 'iSFP2.xml')
```

Gemessen über alle Projekte: `eberater.zip` und `Kernel18599V5.bin` in je **90**
Projekten, `iSFP2.xml` in **37**. Fehlt `eberater.zip`, gibt es **keine**
DIN-18599-Anlagentechnik — dann ist das eine Aussage, kein Versäumnis, und
gehört so gesagt. Nicht auf „irgendeine PrMedia-Zeile" prüfen: dort liegen auch
Fotos und Logos, ein Projekt mit einem Bild sähe sonst ausgestattet aus.

### Was du danach sagst

> **„Ich habe das Projekt gelesen und stehe dir jetzt zur Verfügung."**

Davor eine **kurze** Übersicht — was da ist, in welchem Zustand, und was fehlt:

```
Existierendes Projekt gefunden: PY5LT_Krüger_260813  [DB24A001]

  Geschosse     Keller, EG, DG   (Höhen 0,00 / 2,80 / 5,60)
  Gezeichnet    91 Bauteile      Außenwände 24, Innenwände 31, Decken 12, Dach 4
  Gerechnet     152 Bauteile     davon 54 ohne Katalogzuweisung
  Räume         14 in 1 Zone
  Anlagentechnik  eberater.zip vom 13.08.2026
  iSFP            nicht vorhanden

Ich habe das Projekt gelesen und stehe dir jetzt zur Verfügung.
```

**Eine Übersicht, kein Abzug.** Bei 253 Bauteilen werden nicht 253 Zeilen
ausgegeben — gezählt und gruppiert wird. Wer alles zeigt, hat nichts gezeigt.

**Und sag, was du NICHT angesehen hast.** Der Inhalt von `eberater.zip` etwa ist
mit diesen Abfragen nicht gelesen, nur seine Anwesenheit. „Anlagentechnik
vorhanden" heißt nicht „Anlagentechnik geprüft".

## Fallstricke

- **Nicht mit dem Namen weiterarbeiten**, sondern mit der UUID — 19 von 107
  Projekten teilen ihren Namen mit einem anderen.
- **Ein leeres Projekt ist keine Einladung.** Auch dort wird erst beschrieben und
  bestätigt, bevor gebaut wird. Leer heißt nur: es kann nichts verlorengehen.
- **Ein bearbeitetes Projekt ist keine Aufforderung zum Aufräumen.** Was du für
  überflüssig hältst, kann Absicht sein. Melde es, ändere es nicht.
- **Diese Einordnung ist rein lesend.** Kommt dabei der Wunsch auf, etwas
  „schnell geradezuziehen", gehört das in den normalen Ablauf mit Probelauf und
  Freigabe — nicht in die Bestandsaufnahme.
