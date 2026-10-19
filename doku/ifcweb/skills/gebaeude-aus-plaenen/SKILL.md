---
name: gebaeude-aus-plaenen
description: Aus Grundrissen, Schnitten und Fotos die Gebaeudehuelle mit Dach zeichnen - Aussenwaende je Geschoss und Dachflaechen. Ausloeser - Plan hochgeladen, Grundriss, Schnitt, Foto vom Haus, Gebaeude nachbauen, Huelle zeichnen.
erprobungsstand: teilweise-gemessen
---

**Stand:** Die einzelnen Schritte sind erprobt — Aussenring, Geschosse und
Satteldach hat der Agent im Prüfstand selbst gebaut. **Der Weg von einer echten
Unterlage dorthin ist noch nie gelaufen.** Behandle das erste Mal entsprechend:
Beschreibung zeigen, bestätigen lassen, dann bauen.

**Vokabular:** `schema/gebaeudebeschreibung.md` — dort stehen die Felder, die
Regel „zwei von drei Höhenangaben genügen", und welche Dachformen heute wirklich
baubar sind.

## Der Ablauf

**Erst beschreiben, dann bauen.** Nie in einem Zug von der Unterlage zum
Werkzeugaufruf — die Beschreibung ist das, was ein Mensch prüfen kann.

1. **Lesen.** Grundriss → Kontur und Wandstärke. Schnitt → Höhen. Foto → Dachform.
2. **Beschreibung aufstellen** und dem Nutzer **zeigen**. Jede Zahl mit ihrer
   Herkunft: „Traufhöhe 0,80 m — Schnitt A-A, Maßkette links."
3. **Lücken benennen, nicht füllen.** Was nicht bemaßt ist, wird erfragt.
4. **Bauen**, in dieser Reihenfolge: Geschosse → Außenring je Geschoss → Dach.
5. **Prüfen**: `projekt_lesen`, dann die Wirkungsprobe in HottCAD durch den Nutzer.

## Reihenfolge beim Bauen

Sie ist nicht beliebig:

- **Geschosse zuerst.** Ohne Geschoss kein Bezug für Wände.
- **Außenring von unten nach oben.** Das erste Geschoss über
  `aussenring_anlegen`, jedes weitere über `geschosswaende_kopieren` — das
  verschiebt z richtig und baut die prev/next-Kette auf die Kopien um.
- **Dach zuletzt**, und **nur wenn das Dachgeschoss Wände hat**. Sonst schwebt
  es über einem offenen Geschoss und es entstehen keine Giebeldreiecke.
- Den Grundriss fürs Dach **nicht aus der Beschreibung nehmen**, sondern über
  `projekt_lesen` aus den gebauten Wänden. Dort steht er in genau der Form, die
  `-Grundriss` erwartet — und stimmt garantiert mit dem überein, was wirklich
  im Modell steht.

## Fallen

- **Firsthöhe im Schnitt ist über Gelände bemaßt**, gebraucht wird sie über der
  Traufe. Differenz bilden, nicht abschreiben.
- **Traufhöhe ist der Kniestock**, gemessen ab Oberkante Dachgeschoss — nicht ab
  Gelände. 0 heißt: das Dach sitzt direkt auf der Geschossdecke auf.
- **Maßstab prüfen, nicht am Bild messen.** Bemaßte Zahlen im Plan schlagen jede
  Messung am Bildschirm. Steht keine Maßkette da, frag.
- **Nicht baubare Dachformen nennen, statt sie zu ersetzen.** Ein Walmdach als
  Satteldach zu bauen, weil das geht, wäre ein stiller Fehler in der Bilanz.
  Sag, dass es nicht geht, und biete an, den Rest zu bauen.
- **Nur Wände und Dach.** Fenster, Türen, Innenwände und Räume gehören nicht
  dazu. Räume sind ein eigener Schritt und **anlegbar** — die frühere Notiz,
  das ginge nicht, ist widerlegt (siehe Fertigkeit `fehlerbilder`).
- **Keine Vorlage im Projekt?** `vorlagen_zeigen` sagt, welche Seitendatenbank
  eine hat. Den Namen nicht raten.

## Was du nicht aus Unterlagen holen kannst

Wandstärke, wenn sie nicht bemaßt ist. Ob eine Wand tragend ist. Den
Dachaufbau. Alles davon ist zu erfragen — geschätzt sieht es im Modell aus wie
gemessen, und der Fehler fällt erst in der Energiebilanz auf.
