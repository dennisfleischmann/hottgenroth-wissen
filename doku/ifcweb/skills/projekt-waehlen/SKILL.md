---
name: projekt-waehlen
description: Klaeren, in welchem Hottgenroth-Projekt gearbeitet wird - Projektliste zeigen, auswaehlen lassen, ueber die UUID festhalten. Ausloeser - kein Projekt genannt, Projektname mehrdeutig, Projekt nicht gefunden, welches Projekt, in welchem Projekt soll ich arbeiten.
erprobungsstand: erprobt-lesend
---

**Stand:** Rein lesend und am Bestand ausgezaehlt (22.08.2026, 107 Projekte).
Es wird nichts geschrieben, es ist kein Freigabetor noetig.

**Die Zahlen unten wachsen.** Am 21.08. waren es 102 Projekte und 6 doppelte
Namen, einen Tag spaeter 107 und 7. Nimm sie als Groessenordnung, nicht als
Wahrheit -- kommt es auf die genaue Zahl an, zaehl sie neu aus.

---

## Wann das hier gilt

Bevor irgendetwas geschrieben wird, muss feststehen, **welches** Projekt gemeint
ist. Drei Fälle lösen das aus:

1. Der Nutzer nennt **kein** Projekt.
2. Der genannte Name passt auf **mehr als eines**.
3. Der genannte Name passt auf **keines**.

In allen drei Fällen: Liste zeigen, fragen, und **erst danach weiterarbeiten**.
Nicht raten, nicht „das zuletzt bearbeitete nehmen", nicht die erste Trefferzeile
nehmen.

## Warum das nicht bloß Höflichkeit ist

**Projektnamen sind nicht eindeutig.** Ausgezählt am 22.08.2026: von 107
Projekten teilen sich **19** ihren Namen mit einem anderen, es gibt **7**
mehrfach vergebene Namen, der Spitzenreiter kommt **siebenmal** vor. In der
Liste unten stehen zwei Zeilen `H3STF_Thanhäuser_260820` — verschiedene UUIDs,
verschiedene Bearbeitungsdaten, verschiedene Bauteilzahlen.

Ins falsche Projekt zu schreiben ist der Fehler, der sich am schlechtesten
zurücknehmen lässt: er sieht nirgends nach einem Fehler aus, er steht nur an der
falschen Stelle.

> **Nach der Wahl arbeitest du mit der UUID weiter, nicht mit dem Namen.**

## Die Liste

```sql
SELECT TOP 15
       p.LongDesc                                   AS Projekt,
       CONVERT(char(10), p.StampEdit, 104)          AS Bearbeitet,
       (SELECT COUNT(*) FROM BmFloor f
         WHERE f.ProjectUUID = p.UUID)              AS Gesch,
       (SELECT COUNT(*) FROM BmElement e
         WHERE e.ProjectUUID = p.UUID
           AND e.RepositoryType = 3)                AS Gezeichnet,
       (SELECT COUNT(*) FROM BmElement e
         WHERE e.ProjectUUID = p.UUID
           AND e.RepositoryType = 1)                AS Gerechnet,
       LEFT(CONVERT(varchar(36), p.UUID), 8)        AS UUID8
FROM   PrProject p
ORDER  BY p.StampEdit DESC
```

Über `datenbank_fragen`, mit `Spaltenbreite 30`. Ergebnis:

```
Projekt                        | Bearbeitet | Gesch | Gezeichnet | Gerechnet | UUID8
Test0001                       | 21.08.2026 | 2     | 8          | 0         | 2C5AC804
PY5LT_Krüger_260813            | 21.08.2026 | 3     | 91         | 152       | DB24A001
H3STF_Thanhäuser_260820 (1)    | 21.08.2026 | 4     | 139        | 253       | 8424A001
H3STF_Thanhäuser_260820        | 21.08.2026 | 4     | 137        | 251       | 2A24A001
H3STF_Thanhäuser_260820        | 20.08.2026 | 4     | 137        | 251       | ADEC8EBF
```

**Fünfzehn, nicht hundertsieben.** Wer alles ausgibt, hat nichts gezeigt. Sucht der
Nutzer etwas Älteres, grenz mit `WHERE p.LongDesc LIKE '%…%'` ein.

### Was die Spalten leisten, und warum keine fehlen darf

| Spalte | wozu |
|---|---|
| `LongDesc` | **der** Projektname. `ShortDesc` ist die Kunden-/Projektnummer und bei 62 von 107 leer — als Name unbrauchbar |
| `StampEdit` | zuletzt bearbeitet; sortiert das Naheliegende nach oben |
| `Gesch` | Zahl der Geschosse — zeigt auf einen Blick, ob überhaupt etwas drinsteht |
| `Gezeichnet` | Bauteile mit `RepositoryType = 3` |
| `Gerechnet` | Bauteile mit `RepositoryType = 1` |
| `UUID8` | die ersten acht Stellen — **trennt gleichnamige Projekte** |

**Beide Bauteilzahlen zeigen, nie nur eine.** Gemessen: 98 Projekte führen
Zeilen mit `RepositoryType 3`, 77 mit `RepositoryType 1`. Ein frisch
gezeichnetes Projekt wie Test0001 hat acht Bauteile — alle in Repo 3. Wer nur
Repo 1 zählt, zeigt dort **0** und lässt es aussehen, als wäre es leer. Zu den
beiden Speichern siehe [[bmelement-zwei-repositories]] und
[[hottcad-cadxmldata-fuehrend]].

## So fragst du

`rueckfrage` mit einer **nummerierten** Liste. Der Nutzer soll mit einer Zahl
antworten können, nicht einen Namen abtippen müssen — schon gar keinen, den es
zweimal gibt.

```
Welches Projekt soll ich verwenden?

  1  Test0001                     21.08.  2 Gesch.,   8 gez. /   0 ger.  [2C5AC804]
  2  PY5LT_Krüger_260813          21.08.  3 Gesch.,  91 gez. / 152 ger.  [DB24A001]
  3  H3STF_Thanhäuser_260820 (1)  21.08.  4 Gesch., 139 gez. / 253 ger.  [8424A001]
  4  H3STF_Thanhäuser_260820      21.08.  4 Gesch., 137 gez. / 251 ger.  [2A24A001]
  5  H3STF_Thanhäuser_260820      20.08.  4 Gesch., 137 gez. / 251 ger.  [ADEC8EBF]

Antworte mit der Nummer. Steht deins nicht dabei, nenn mir einen Namensausschnitt,
dann suche ich gezielt.

(3, 4 und 5 heißen gleich und sind drei verschiedene Projekte — deshalb die UUID
dahinter.)
```

Bei gleichnamigen Einträgen **sag ausdrücklich dazu, dass sie verschieden sind.**
Sonst sieht es nach einem Anzeigefehler aus, und der Nutzer wählt aufs Geratewohl.

## Danach

1. Antwort auflösen: Nummer → Zeile → **UUID**. Eine Antwort, die auf mehrere
   Zeilen passt („das Thanhäuser"), ist **keine** Antwort — nachfragen.
2. Die Wahl **bestätigen**, mit Namen *und* UUID, damit der Nutzer einen
   Fehlgriff sofort sieht.
3. **Weitermachen, wo du warst.** Die Projektwahl ist ein Einschub, kein
   Abschluss. Warst du in Stufe 1 der Erhebung, geht es dort weiter — sag,
   welche Unterlagen du jetzt brauchst.
4. Im weiteren Verlauf nicht erneut fragen. Das Projekt steht fest, bis der
   Nutzer es ändert.

## Fallstricke

- **`ShortDesc` ist nicht der Name.** Eine Suche darüber liefert null Zeilen und
  sieht aus wie „Projekt gibt es nicht". Siehe
  [[prproject-name-steht-in-longdesc]]. Bei 62 von 107 ist das Feld ohnehin
  leer.
- **Nicht auf `p.Name` prüfen.** Die Spalte existiert nicht; `UId` und
  `ProjectUId` ebenso wenig. Eine `Id`-Spalte gibt es, sie ist aber nicht der
  Schlüssel.
- **Kein Treffer heißt nicht „gibt es nicht".** Erst ohne `WHERE` zählen, bevor
  du das sagst — der Fehler kann in der Suche liegen.
- **Ein Projekt anzulegen ist etwas anderes** als eines auszuwählen und gehört
  nicht hierher. Frag, statt eines zu erfinden.
