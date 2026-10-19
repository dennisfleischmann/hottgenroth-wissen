# Neues Projekt: Zone „Wohnen" anlegen und Räume einstellen

Für jedes **neue** Wohngebäude, das dem Standardschema folgt: eine Zone,
Nutzungsprofil „42 - Wohnung Einfamilienhaus", je Raum nur **beheizt** oder
**unbeheizt**.

Datenmodell: [`hottgenroth-raum-zone-sql.md`](hottgenroth-raum-zone-sql.md).
Ausführlicher Ablauf mit allen Vorbedingungen:
[`ablauf-wohngebaeude-eine-zone.md`](ablauf-wohngebaeude-eine-zone.md).
**Dieses Blatt ist die Kurzfassung für den Regelfall.**

---

## Was ich vorher wissen muss

Ohne diese vier Angaben kann ich nicht anfangen. Fehlt eine, frage ich nach,
statt zu raten.

| # | Angabe | Beispiel |
|---|---|---|
| 1 | **Projekt** — Namensausschnitt oder GUID | `"Pohlstra"` |
| 2 | **Geschosse beheizt** | `EG, DG1, DG2` |
| 3 | **Geschosse unbeheizt** | `Keller` |
| 4 | **Ausnahmen je Raum**, falls es welche gibt | `EG-R9 unbeheizt` |

**Jedes Geschoss mit Räumen muss in 2 oder 3 stehen.** Ein vergessenes Geschoss
ist ein stiller Fehler in der Bilanz — deshalb bricht der Ablauf ab, statt es
stillschweigend zu übergehen. Ein Namensausschnitt, der auf zwei Projekte passt,
bricht ebenfalls ab; dann brauche ich die GUID.

**Die Räume müssen vorhanden sein.** Ist das Projekt raumlos, bricht der Ablauf
mit genau diesem Hinweis ab.

> Hier stand bis zum 20.08.2026: „Zeichnen kann ich sie nicht — die Verweise auf
> die umschließenden Bauteile rechnet HottCAD aus der Zeichnung." Der zweite
> Halbsatz stimmt, der erste folgt nicht daraus. **Weil** die Software sie
> rechnet, muss man sie nicht liefern. Beleg: *Wohnraum 21 / DG2-R1* in
> Pohlstraße wurde am 17.08. um 04:01 von außen geschrieben — nur `BmRoom`,
> `BmRoomData` und die Zeichnung; die vierzehn Verweise ergänzte HottCAD um
> 11:01 beim Öffnen selbst.

**Keine Hottgenroth-Anwendung darf offen sein.** Auch nicht der EE-Berater — der
läuft als Prozess `EEBerater`, nicht `Energie`.

---

## Der Regelfall: ein Aufruf

```powershell
cd C:\Projekte_Dev\energieberatung\bauteile\tools

# 1. trocken - zeigt, was passieren würde, schreibt nichts
.\Setup-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller -Probelauf

# 2. echt - sichert vorher selbst und prüft hinterher selbst
.\Setup-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller
```

Das deckt beide Aufgaben ab:

**Aufgabe 1 — Zone „Wohnen".** Existiert keine `ZoneType-5`-Zone, wird eine
angelegt: `BmZone` + `BmZoneData` unter derselben UUID, als Kopie einer
vorhandenen Zone des Projekts (so stimmen `BIMUUID`, `ParentUUID` und alle
Sentinels von selbst), mit `ZoneType 5`, `HeatingType 1`, Name aus `-ZoneName`
(Vorgabe `Wohnen`). Dann kommt das Nutzungsprofil dran — drei Zeilen unter einer
UUID in `PdProfile`, `PdProfileUsage`, `PdProfileReference`.

> **Die Zone heißt danach nicht mehr „Wohnen".** Beim Zuweisen des Profils
> benennt die Software sie nach dem Profil um, zu „Wohnung Einfamilienhaus". Das
> ist normal und an Pohlstraße beobachtet. Deshalb arbeitet Schritt 5 über die
> **UUID** der Zone, nicht über ihren Namen — sonst würde ein zweiter Lauf sie
> nicht mehr finden.

**Aufgabe 2 — Raumstempel und Zonenzugehörigkeit.** Beheizte Geschosse bekommen
Raumart 1 („Wohnraum", fortlaufend numeriert), `HeatingType 1`, 20 °C,
`room_type="mrtLiving"`, `air_change="0.5"` — jeweils in `BmRoom` **und** im
CAD-XML. Unbeheizte bekommen `HeatingType 2` und 10 °C, ihre Raumart bleibt
stehen. Danach werden alle beheizten Räume der Zone zugeordnet und die
unbeheizten daraus entfernt.

---

## Ausnahmen, die nicht dem Geschoss folgen

Wenn ein einzelner Raum vom Geschoss abweicht — Heizungsraum im beheizten EG,
ausgebautes Zimmer im unbeheizten Keller — nach dem Ablauf raumgenau nachziehen.
`-Geschoss *` hebt die Geschossgrenze auf, `-Raum` nennt die Raumnummern:

```powershell
# EG-R9 doch unbeheizt
.\Set-Raumstempel.ps1 -Projekt "Pohlstra" -Geschoss * -Raum EG-R9 -Status unbeheizt
.\Set-Raum-Zone.ps1   -Projekt "Pohlstra" -Zone "Einfamilienhaus" -Geschoss * -Raum EG-R9 -Entfernen

# danach immer erneut prüfen - die Invarianten kennen die Ausnahme nicht!
.\Test-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller
```

> Nach einer raumgenauen Ausnahme meldet `Test-Wohngebaeude.ps1` diesen Raum als
> Fehler, weil die Prüfung je Geschoss argumentiert. Das ist erwartet. Ein
> Ausnahmeraum gehört in die Projektnotiz, sonst hält man den Befund später für
> einen echten Fehler.

---

## Abweichende Vorgaben

| Fall | Zusatz |
|---|---|
| Mehrfamilienhaus | `-Profil "43 - Wohnung Mehrfamilienhaus" -ProfileUsageType 35` |
| Zone anders benennen | `-ZoneName "Wohnen EG"` |
| Raumarten unangetastet lassen | `-Raumart 0` (setzt nur den Heizstatus) |
| Anderer Basisname | `-Name "Zimmer"` |

> **`ProfileUsageType` ist nicht die Zahl im Profilnamen.** 42 → **34**,
> 43 → **35**. Mit 42 bekommt man „36 Labor".

---

## Woran ich erkenne, dass es gut ist

1. `Setup-Wohngebaeude.ps1` endet mit **„Alles in Ordnung."** — 21 Invarianten
   grün, Rückgabewert 0.
2. **Wirkungsprobe in der Software.** Zahlen in der Datenbank beweisen nur, dass
   die Zeilen stehen. Zu prüfen: Stempel im Grundriss lesbar, die Zone zeigt die
   richtige Anzahl Räume, und sie **rechnet ihre Fläche nach**. Solange die
   Zonenfläche auf `-987654321,99` steht, hat die Software die Zuordnungen
   gelesen, aber nicht verrechnet.

Häufige Meldungen und was sie bedeuten, stehen in
[`ablauf-wohngebaeude-eine-zone.md`](ablauf-wohngebaeude-eine-zone.md#wenn-etwas-schiefgeht).

Geht etwas verloren: `Restore-Projekt.ps1` holt **ein** Projekt aus einer
Sicherung zurück. Ein Voll-Restore von `HsetuPrjData` wäre falsch — er setzt alle
über 40 Projekte zurück.

---

## Grenzen, die auch dieser Ablauf nicht verschiebt

- **Räume anlegen** — nicht möglich. Der Nutzer zeichnet, das Skript macht alles
  danach.
- **Eine zweite Zone** — der `[HASH8]` in `P0Zone_n[…]` ist nicht nachbildbar.
  Für ein Wohngebäude reicht die eine, deren Kennung im EE-Berater schon steht.
- **Der Übertrag in die `eberater.zip`** — Zone, Profil und Zuordnung bleiben im
  Gebäudemodell. Was den Übertrag auslöst, ist ungeklärt. Bis dahin sieht die
  18599-Rechnung die Zone nicht.
- **`InfoDesc` kann leer bleiben**, wenn der EE-Berater noch nicht benutzt wurde.
  Der Ablauf warnt und läuft weiter.
