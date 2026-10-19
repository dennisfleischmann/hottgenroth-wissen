---
name: umriss-aendern-statt-ersetzen
description: "Einen Grundriss ändert man durch Verschieben der Ecken, nicht durch Löschen und Neubauen — die Wand behält U-Wert, Katalogverweis und Hüllflächen-Flag"
metadata:
  type: project
  stand: gemessen
---

Ein Grundriss wird geändert, indem die **Eckpunkte verschoben** werden. Die
Wände bleiben dabei dieselben Bauteile. Löschen und Neubauen ist der
Ausweichweg — nötig nur, wenn sich die **Zahl** der Ecken ändert.

**Was daran hängt und beim Löschen verloren geht.** Die Wandzeichnung führt
`u_value`, `u_valueDimGuid`, `u_valueDimName` und `u_value_marker`; dazu kommt
`BmElementEnergyConsulting.CladdingSurface` über dieselbe UUID am Element. Eine
neu gebaute Wand steht richtig und rechnet falsch — und das fällt erst in der
Energiebilanz auf, nicht beim Hinsehen.

**Die Arbeitsteilung mit HottCAD:**

> Zu schreiben sind die **Eckpunkte, die Gehrungen und die `prev`/`next`-Kette**.
> Alles Abgeleitete holt sich die Software beim nächsten Öffnen — nie von Hand
> nachziehen.

Eine Wand ist ein Trapez aus vier Punkten: `p1`/`p2` außen, `p3`/`p4` innen. Die
innere Ecke ist **nicht** „außen minus Wandstärke", sondern der Schnittpunkt der
beiden um die Wandstärke nach innen versetzten Kantenlinien. Beim Rechteck ist
das dasselbe, bei einer L-Form nicht: an der einspringenden Ecke liegt die innere
Ecke weiter außen als die äußere. Fertige Rechnung in
`bauteile/tools/New-Aussenring.ps1`.

Eine bewegte Ecke gehört **zwei** Wänden. Wer nur eine anfasst, hinterlässt eine
offene Ecke.

**Beleg:** Gemessen am 18.08.2026 an *Test0001*: eine Wand allein über
`BmData.ClassValue` (`LongDesc='CADXMLData'`) um 2 m verschoben, Projekt
geöffnet, angesehen, geschlossen, Aufnahmen verglichen. HottCAD zeichnete die
Wand an der neuen Stelle und gab den `<points>`-Block **zeichengleich** zurück.
Selbst nachgerechnet hat es: `GrossArea`/`NetArea` 152,187 → 181,581, `Height`
10,355 → 12,355, dazu `Volume` und Fließkommarauschen in `Width`/`Thickness`;
der Plattenumriss wuchs von 4 auf 6 Punkte, `building_data` wurde neu
geschrieben. **Nicht** nachgezogen hat es die Anschlüsse: die drei Nachbarwände
behielten ihre Gehrungen zur alten Lage, die Ecken blieben offen. Die
Gehrungsformel ist an den vier Wänden nachgerechnet, die HottCAD in Test0001
selbst gezeichnet hat — alle sechzehn Punkte stimmen. Die zitierten Attribute
stammen aus der Zeichnung von `AW 002` (Aufnahme vom 21.08.2026).

**Nicht gemessen:** Der Messversuch war eine **Parallelverschiebung einer
ganzen Wand**, bewusst so gewählt, weil dabei Länge, Fläche und Dicke stimmig
bleiben. Das Verschieben einer **einzelnen Ecke** — das zwei Wände verkürzt oder
verlängert — ist daraus geschlossen, nicht selbst gelaufen. Dass HottCAD auch
dort die Längen sauber nachrechnet, ist plausibel (es hat `Width` und `Height`
beim Versuch angefasst), aber offen. Ebenso offen: ob es den Widerspruch zu den
unveränderten `bottom_planes` bemerkt. Ein Werkzeug für „gib dem Geschoss diesen
Umriss und lass die Wände leben" gibt es noch nicht.

**Why:** Die naheliegende Lösung — Ring weg, Ring neu — ist die teure. Sie
kostet je Wand den Katalogverweis und die Hüllflächen-Kennzeichnung, und der
Schaden zeigt sich nicht im Modell, sondern erst in der Bilanz. Umgekehrt ist
das Verschieben billig: HottCAD trägt fast alles selbst nach, zu rechnen bleibt
allein die Gehrung.

**How to apply:** Erst `projekt_lesen` — es gibt die Außenkontur je Geschoss in
genau der Form, die `Polygon` erwartet. Eckenzahl vergleichen: gleich → jede
Ecke 1:1 an ihre neue Stelle, beide anliegenden Wände anfassen, `p3`/`p4` neu
aus der Gehrungsrechnung. Anders → so viel wie möglich zuordnen und verschieben,
nur der Rest wird angelegt oder entfernt, und nur dafür braucht es die
Löscherlaubnis. Siehe [[hottcad-cadxmldata-fuehrend]] und
[[bmelement-huellflaeche-flag]].
