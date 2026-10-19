# Belegfälle

Doku beschreibt Regeln, Werkzeuge setzen sie um — beides kann falsch sein, ohne
dass es auffällt. Hier liegt das Dritte: **die exakten Bytes eines Modells, das
in der Software nachweislich richtig ausgesehen hat.**

Jeder Fall hat drei Aufgaben:

1. **Beweis.** Nicht „die Regel lautet so", sondern „so sah es aus, als es
   funktioniert hat".
2. **Rückfall.** Eine spätere Sitzung hält ihre eigene Ausgabe dagegen, statt
   die Regel neu herzuleiten.
3. **Regression.** Wer ein Werkzeug ändert, lässt es gegen den Fall laufen und
   vergleicht. Genau so wurde `New-Satteldach.ps1` geprüft — es liefert für das
   L-Dach dieselben sechzehn Punkte, die hier liegen.

## Aufbau

```
<fall>/
  fall.md          Herkunft, Bestätigung, Geschosse, Bauteile
  zeichnung/       je Bauteil eine .xml -- das ist die Wahrheit
```

Verglichen wird über den **Bauteilnamen**, nicht über UUIDs: die sind bei jedem
Lauf andere.

## Neuen Fall anlegen

Erst wenn ein Mensch das Ergebnis in HottCAD gesehen und bestätigt hat. Ein Fall,
den nur die Datenbank gesehen hat, beweist nichts — das Pultdach stand sauber in
allen Spalten und ergab trotzdem keine Fläche.

```powershell
.\Export-Referenzfall.ps1 -Projekt "Test0001" -Fall "walmdach" `
  -Bestaetigt "Am TT.MM.JJJJ in HottCAD geöffnet und bestätigt: <Wortlaut>" `
  -Beschreibung "..." [-NamePraefix Dach] [-Datenbank HsetuPrjProbe]
```

`-Bestaetigt` ist Pflichtparameter. Das ist Absicht.

## Vorhandene Fälle

| Fall | Was er belegt |
|---|---|
| `l-satteldach` | Satteldach über L-Grundriss: vier Flächen, zwei Firste auf gleicher Höhe, Kehle und Grat. Dazu der komplette Baukörper — vier Geschosse, Außenringe in Rechteck und L-Form, erzeugte Platten. |
