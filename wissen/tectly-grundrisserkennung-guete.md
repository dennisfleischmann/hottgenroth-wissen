---
name: tectly-grundrisserkennung-guete
description: "Was Tectly aus einem gescannten Grundriss herausholt und was nicht — am 25.09.2026 an zwei Scans gegen die gedruckten Raumflächen gemessen"
metadata:
  type: project
---

Gemessen am Testprojekt `e4faef50-9eac-44f0-bf99-2f96fc23be3c` (zwei Scans,
EG und Keller). Werkzeuge im Sitzungsordner; der Weg ist reproduzierbar:
Überlagerung der API-Geometrie auf das Seitenbild, dann gegen die **im Plan
gedruckten Raumflächen** rechnen.

**Koordinaten sind relativ zur `pageSection` des Plans, nicht zur Seite.**
Das war die erste Fehlerquelle — mit Seitenbezug liegt alles versetzt und zu
groß. `x_m = x_rel / horizontalScale` stimmt trotzdem, weil `horizontalScale`
schon je Ausschnitts-Einheit definiert ist. `horizontalScale·Ausschnittbreite_px`
und `verticalScale·Ausschnitthöhe_px` ergeben **dieselbe** Zahl: die Pixel je
Meter (hier 85,00).

## Was trägt

- **Der Maßstab ist genau.** Sieben Räume gegen ihre gedruckten m² gerechnet:
  Summe 61,76 gegen 61,75 m², Abweichung **0,02 %**. Kleinste Quadrate ergeben
  85,01 px/m gegen Tectlys 85,00.
- Wandzüge sitzen genau auf den gezeichneten Wänden.
- Räume werden einzeln erfasst (9 von 10 echten).

## Was nicht trägt

- **Der Maßstab wird nicht automatisch gefunden.** Auf *beiden* Plänen stand
  `horizontalScaleProcessingStatus: Negative`; der Kellerplan hat gar keinen.
  Alles hängt an einer Kalibrierung von Hand.
- **Die Schräglage des Scans wird nicht herausgerechnet.** Tectly rastet jedes
  Element für sich auf die Achsen. Aus 1,1–1,6° Verdrehung wird eine Treppe:
  dieselbe gerade Außenwand kommt als x = 6,036 / 6,177 / 6,318 heraus — 28 cm
  Versatz auf 10 m. Erst drehen, dann orthogonalisieren.
- **Wandbänder sind ~6 cm je Seite zu breit** — Außenwand 0,30–0,33 statt 0,24 m.
  Konstanter Zuschlag, abziehbar.
- **Es sind Wandzüge, keine Einzelwände** (L- und T-förmig, teils außen und innen
  gemischt). Das kleinste umschließende Rechteck liefert darauf Unsinn
  (Dicken bis 3,6 m); `A = L·t, U = 2(L+t)` trifft es.
- **Öffnungen: 8 Fenster + 1 Tür**, davon eine Dublette, eines übersehen, eines
  mit 0,106 m Breite. **Alle Höhen und Brüstungen 0,0** — obwohl die Fenstermaße
  im Plan stehen.
- **Raumnamen fehlen bei 10 von 12.**
- **Scanartefakte werden zu Gebäude**: Ringbuchkante und Seitenrand kommen als
  Raum (66,1 m² und 14,7 m²) und als Wände. Die gelieferte `envelope` schleppt
  sie mit und ist damit unbrauchbar. Filter: Berührung des Ausschnittrands,
  Bandbreite > 0,6 m.
- Kein Geschosstyp, keine lichte Höhe, keine Deckenstärke.

**Why:** Die Streuung je Raum (−4,9 % bis +13,6 %) sieht nach einem Maßstabs-
fehler aus und ist keiner — sie hebt sich in der Summe auf 0,02 % auf. Wer nur
einen Raum prüft, verwirft ein gutes Ergebnis oder vertraut einem schlechten.

**How to apply:** Tectly liefert **Topologie und Lage**, der Plan liefert die
**Maße**. Beides zusammenlegen: Maßketten und Fenstermaße aus dem Scan lesen
(sie schließen und sind damit selbst prüfbar — 24+2,50+24+1,70+4,205+24 = 9,125),
Tectlys Wandachsen auf die Stationen der Maßkette einrasten, Höhen und
Brüstungen aus den Fensterbemaßungen ergänzen. Ergebnis geht ins FS-Format
([[hottcad-cadxmldata-fuehrend]]) und von dort über `New-Aussenring.ps1` weiter.

## Einrasten auf die Masskette (25.09.2026)

Werkzeuge im Hauptrepo unter `tectly/` (untracked, nicht im Deploy), Beschreibung
in `tectly/README.md`. `einrasten.py` entschert und rastet ein; **Scherung und
Versatz muessen gemeinsam gesucht werden** — allein aus der Haeufung der Kanten
geschaetzt, schiebt eine grosse Scherung auch fremde Waende aufeinander und sieht
dabei besser aus (−2,55 Grad statt der an der Wand gemessenen 1,6).

Erreicht: quer **79 %** der Wandkantenlaenge auf einer Station, mittlerer Versatz
64 mm, Spannweite 9,148 gegen 9,125 m. Laengs nur 44 %, weil dort nur **eine**
Kette mit 8 Stationen vorliegt — die Laengsmasse stehen im Plan innerhalb der
Zeichnung als Raummasse, nicht als Kette.

**Fenstermasse stehen am Plan als Breite ueber Hoehe** (`1,885/1,345`), bei Tueren
`88,5/2,005`. An der Oeffnungsbreite nachgemessen bestaetigt. Tectly liefert dafuer
durchgehend 0.
