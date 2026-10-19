---
name: container-ergebnisse-gehoeren-der-software
description: "Giftwerttest: die Software rechnet beim Öffnen neu und überschreibt TableHeizung/TableResult — Ergebnisse selbst zu schreiben ist zwecklos"
metadata:
  type: reference
---

**Gemessen am 27.09.2026** an `ZZTEST_Rechenlauf_260927` mit gepflanzten Giftwerten,
die kein Rechenkern erzeugt haben kann.

| Feld | gepflanzt | nach einmal Öffnen + Speichern |
|---|---|---|
| `TableHeizung.Qh` | 99.999 | **7114,45703125** |
| `TableResult.EBilanz` → `Q_Heiz` | 88.888 | **7114,45715332031** |
| `TableResult.EBilanz` → `Q_End` | 77.777 | **2705,82200622559** |

**Die Ergebnisse gehören der Software.** Sie selbst zu schreiben ist zwecklos — beim
nächsten Besuch der Variante werden sie ersetzt. Der Weg, das manuelle Öffnen
einzusparen, führt damit **nicht** über das Schreiben der Ergebnisse, sondern nur über
das Fernsteuern des Öffnens ([[rechenlauf-ohne-oberflaeche]]).

**Sie stellt nicht wieder her, sie rechnet neu.** Vorher stand 7138,20 im Container,
danach 7114,46 — 23,7 kWh Unterschied. Die Brücke hatte zuvor exakt die alten 7138
gerechnet. Ein gespeicherter Wert ist also **nicht** reproduzierbar, ohne die
Bedingungen des Laufs zu kennen, unter dem er entstand.

## Ein Speichern ist ein Neuaufbau, kein Schreiben

**Zweiter Lauf am selben Tag, ohne Importaufräumen — fünf von neun Tabellen:**
`TableHeizung`, `TableHuellfl`, `TableProjekt`, `TableResult`, `TableZusatz`.
Der Giftwert wurde erneut auf exakt 7114,45703125 überschrieben: die Rechnung ist
deterministisch, nur eben nicht identisch mit dem zuvor Gespeicherten.

**Die `HUELL_ID` ist flüchtig.** Bei JEDEM Speichern wird die gesamte Bauteiltabelle
gelöscht und neu angelegt: 432–450 → 451–469 → 470–488, bei gleichbleibender
Bytelänge und ohne jede Eingabe des Nutzers. Wer eine `HUELL_ID` festhält, greift
beim nächsten Speichern ins Leere — still. Unsere Werkzeuge wählen über
`KENNZEICHEN` und `BAUTEILBEZ` aus und sind deshalb unbeschadet geblieben; die
`SAN*`-Felder wandern bei der Neuanlage mit (an Klenke über mehrere Speicherläufe
beobachtet). In `TableProjekt` ändern sich nur die Fotopfade ins Temp-Verzeichnis.

**Folge:** Das Speichern nachzubauen hieße, Bauteiltabelle und Blob neu zu erzeugen
und dann zu rechnen — die Maschinerie des Modells. Dieser Weg ist damit erledigt.
Es bleibt die Fernsteuerung über `ETU_CMD` ([[rechenlauf-ohne-oberflaeche]]).

**Beim ERSTEN Öffnen nach einem Import fasst sie sechs Tabellen an** — ohne jede Eingabe des Nutzers:
`TableHeizung`, `TableHuellfl`, `TableProjekt`, `TableResult`, `TableWasser`,
`TableZusatz`. Beim **ersten** Öffnen nach einem Import kommt Aufräumarbeit dazu: alle
19 `TableHuellfl`-Sätze wurden gelöscht und mit neuen `HUELL_ID` neu angelegt, und
`TableProjekt` trug noch Name, UUID und Fotopfade des Quellprojekts
(`C:\Users\wichm\…`), die die Software korrigiert hat. **Was ein normales Speichern
anfasst, ist damit noch nicht gemessen** — dafür braucht es einen zweiten Lauf.

## Nützliches Nebenergebnis: StampEdit verrät den Schreiber

`PrMedia.StampEdit` unterscheidet Schreibvorgänge der Software von unseren:

| MediaName | Zeilen | `StampCreate = StampEdit` |
|---|---|---|
| `eberater.zip` | 131 | 5 — die Software schiebt `StampEdit` vor |
| `Kernel18599V5.bin` | 131 | 5 |
| `iSFP2.xml` | 60 | **59** — die Maske löscht die Zeile und fügt neu ein |

`container.ps1 -Zurueck` bewegt `StampEdit` **nicht**. Wer wissen will, ob seit dem
eigenen Schreiben die Software dran war, schaut also auf diese Spalte — und bei der
`iSFP2.xml` zusätzlich auf `StampCreate`, weil die Zeile dort neu entsteht.
