---
name: geometrie-aendern
description: Vorhandene Geometrie umformen statt neu bauen - Ecken verschieben, Umriss aendern, Wand versetzen, ohne die Bauteile zu verlieren. Ausloeser - Grundriss stimmt nicht, Ecke verschieben, Umriss aendern, Gebaeude ist zu breit, Wand an die richtige Stelle, Masse korrigieren, Plan weicht ab.
erprobungsstand: teilweise-gemessen
---

**Stand:** Der Mechanismus ist **gemessen** (18.08.2026, Test0001). Die einzelne
Operation „eine Ecke verschieben" ist daraus **gerechnet**, aber nicht selbst
gelaufen, und ein Werkzeug dafür gibt es noch nicht. Bis dahin: trocken rechnen,
zeigen, was herauskäme, und an den Nutzer zurückgeben.

---

## Der Satz, um den es geht

> Einen Grundriss zu ändern heißt **Ecken verschieben**, nicht Wände ersetzen.

In der Oberfläche zieht man eine Ecke an die neue Stelle, die beiden anliegenden
Wände folgen. Von außen geht dasselbe — und es ist der **Regelweg**. Entfernen
und neu bauen ist der Ausweichweg für den Fall, dass sich die Zahl der Ecken
ändert.

## Warum das nicht bloß eleganter ist

An einer Wand hängt mehr als ihre Lage. Das steht im Klartext in ihrer eigenen
Zeichnung:

```xml
<wall name="AW 002" GUID="728c…" floor="67710EBF…"
      u_value="0.9"
      u_valueDimGuid="ea642129-8191-4688-b6ee-fb785f5d30be"
      u_valueDimName="Massive Konstruktion – Zweischalige Wandaufbauten mit Dämmschicht"
      u_value_marker="AW_36_5" height="2.6"
      wall_type="OuterContour" prev="e301e413…" next="5f646d1a…">
```

Dazu kommt, außerhalb der Zeichnung, das Hüllflächen-Flag
`BmElementEnergyConsulting.CladdingSurface` — über dieselbe UUID am Element.

Wer die Wand löscht und eine neue baut, wirft **den Katalogverweis, den U-Wert,
den Schichtaufbau und die Hüllflächen-Kennzeichnung** weg. Die neue Wand steht
richtig und rechnet falsch, und das fällt erst in der Bilanz auf. Deshalb ist
Löschen hier nicht die einfache Lösung, sondern die teure.

## Was HottCAD übernimmt und was nicht

Gemessen am 18.08.2026 an Test0001: **eine** Wand nur über
`BmData.ClassValue` (`LongDesc='CADXMLData'`) um 2 m verschoben, Projekt
geöffnet, angesehen, geschlossen, verglichen.

| | |
|---|---|
| **Es liest die Zeichnung** | Die Wand stand an der neuen Stelle. Der geschriebene `<points>`-Block kam **zeichengleich** zurück — nicht normalisiert, nicht überschrieben. |
| **Es rechnet alles Abgeleitete nach** | `GrossArea` 152,187 → 181,581, dazu `NetArea`, `Volume`, `Height` 10,355 → 12,355, sogar Fließkommarauschen in `Width`/`Thickness`. Der Plattenumriss folgte von 4 auf 6 Punkte, `building_data` wurde neu geschrieben. |
| **Es repariert die Anschlüsse NICHT** | Die drei Nachbarwände behielten ihre Gehrungen zur alten Lage. Die Ecken blieben offen. |

Daraus die Arbeitsteilung, und sie ist der ganze Skill:

> Zu schreiben sind **die Eckpunkte, die Gehrungen und die `prev`/`next`-Kette**.
> Alles andere holt sich die Software beim nächsten Öffnen — **abgeleitete Werte
> also nie von Hand nachziehen.**

## Wie eine Wand aufgebaut ist

Vier Punkte, in dieser Reihenfolge, jeder als `x;y;z`:

```
  p1 ──────────────── p2      p1, p2  die beiden AEUSSEREN Ecken dieser Wand
   │                   │      p3, p4  die zugehoerigen INNEREN Ecken
  p4 ──────────────── p3      z       die Hoehenlage des Geschosses
```

Jede Wand ist ein Trapez zwischen Außen- und Innenkontur.

## Die Gehrung — das Einzige, was wirklich gerechnet werden muss

Die innere Ecke ist **nicht** „außen minus Wandstärke in x und y". Sie ist der
**Schnittpunkt der beiden um die Wandstärke nach innen versetzten Kantenlinien**:

1. Jede Kante als Einheitsvektor `u` schreiben.
2. Bei Gegenuhrzeigersinn zeigt `(-uy, ux)` nach innen — Kante um die Wandstärke
   dorthin versetzen.
3. Die versetzten Linien zweier benachbarter Kanten schneiden. Das Kreuzprodukt
   der beiden Richtungen ist der Nenner; ist es ~0, laufen die Kanten parallel
   und der Versatzpunkt selbst gilt.

Beim Rechteck läuft das auf „minus Wandstärke" hinaus. **Bei einer L-Form nicht:**
an der einspringenden Ecke liegt die innere Ecke weiter *außen* als die äußere,
und nur die Schnittpunktrechnung trifft das. Deshalb allgemein rechnen, nie als
Sonderfall.

Die Rechnung steht fertig in `bauteile/tools/New-Aussenring.ps1` und ist an den
vier Wänden nachgerechnet, die HottCAD in Test0001 selbst gezeichnet hat — alle
sechzehn Punkte stimmen.

**Umlaufsinn:** Gegenuhrzeigersinn wird vorausgesetzt. Ein im Uhrzeigersinn
angegebenes Polygon wird über die Flächenformel erkannt und umgedreht — gemessen,
nicht geraten.

## Vorgehen

1. **Ist-Stand holen.** `projekt_lesen` gibt die Außenkontur je Geschoss in genau
   der Form aus, die `Polygon` erwartet. Damit lässt sich Punkt gegen Punkt
   vergleichen.
2. **Eckenzahl vergleichen.**
   - **Gleich** → 1:1-Zuordnung, jede Ecke an ihre neue Stelle. Alle Wände
     bleiben, mit allem, was an ihnen hängt.
   - **Anders** (Rechteck wird L) → so viele Ecken wie möglich zuordnen und
     verschieben; nur für den Rest kommen Wände dazu oder fallen weg. Nur dieser
     Rest braucht `loeschenErlaubt`.
3. **Je betroffener Wand:** p1/p2 auf die neuen äußeren Ecken setzen, p3/p4 aus
   der Gehrungsrechnung neu bestimmen. **Beide Nachbarn einer bewegten Ecke sind
   betroffen**, nicht nur eine Wand.
4. **`prev`/`next` prüfen.** Solange keine Wand dazukommt oder wegfällt, bleibt
   die Kette wie sie ist. Ändert sich die Zahl, ist sie ringsum neu zu setzen —
   HottCAD zieht das nicht nach.
5. **Nichts Abgeleitetes anfassen.** Keine Fläche, kein Volumen, keine Höhe.
6. **Wirkungsprobe.** Sag dem Menschen, worauf er schauen soll: geschlossene
   Ecken, keine Überstände, die Wand an der erwarteten Stelle.

## Werkzeuglage — hier ist die Lücke

| Werkzeug | kann | kann nicht |
|---|---|---|
| `wandversatz` | **eine** Wand parallel verschieben | Ecken bewegen; Länge bleibt gleich |
| `aussenring_anlegen` | einen Ring **neu** bauen, beliebiges Polygon, mit Gehrung | vorhandene Wände weiterverwenden |
| — | | **„gib dem Geschoss diesen Umriss und lass die Wände leben"** |

Das dritte fehlt. `wandversatz` ist bewusst eine Parallelverschiebung: dabei
bleiben Länge, Fläche und Dicke stimmig, und genau deshalb taugte sie als
Messwerkzeug — jede andere Änderung hätte das Messergebnis vermischt.

**Solange das Werkzeug fehlt:** rechne den Zielumriss und die neuen Punkte aus,
zeig sie, und gib zurück. **Baue den Ring nicht ersatzweise neu** — das ist genau
der Verlust, den dieser Skill verhindern soll.

## Fallstricke

- **Zwei Wände je Ecke.** Eine bewegte Ecke gehört zwei Wänden. Wer nur eine
  anfasst, hinterlässt eine offene Ecke, die im Modell wie ein Zeichenfehler
  aussieht.
- **Die z-Lage nicht mitverschieben.** `z` ist die Höhenlage des Geschosses und
  hat mit dem Grundriss nichts zu tun.
- **`bottom_planes` bleiben stehen.** Beim Messversuch wurden sie bewusst nicht
  angefasst; ob HottCAD den Widerspruch bemerkt, ist **offen**.
- **Andere Geschosse folgen nicht von selbst.** Jedes Geschoss hat seinen eigenen
  Ring. Soll das ganze Haus schmaler werden, ist jedes einzeln dran.
