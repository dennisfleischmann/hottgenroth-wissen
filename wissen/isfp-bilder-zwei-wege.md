---
name: isfp-bilder-zwei-wege
description: Fotos liegen in PrMedia 14/15 mit XimMediaType als Funktion und kommen erst beim Erzeugen der .mSFPprojekt in die XML; Prinzipskizzen liegen direkt in der iSFP2.xml
metadata: 
  node_type: memory
  type: reference
  originSessionId: a9df26c4-f679-4aee-bc74-1016fcac6cb2
  modified: 2026-09-27T07:09:30.057Z
---

Zwei Bildsorten im iSFP, die nichts miteinander zu tun haben.

**Fotos** (Titelbild, „Foto heute", Ansichten) liegen in `PrMedia`,
`MediaType` 14 oder 15 — gepflegt in der Bilderverwaltung von Hottgenroth.
In der `iSFP2.xml` steht nur das leere Gerüst. **In allen 59 Projekten der
LocalDB ist jeder Foto-Stream in der `iSFP2.xml` leer**; die Bytes setzt die
Software erst ein, wenn sie die `.mSFPprojekt` erzeugt. Ein leerer Stream ist
also kein Mangel, und Fotos dort hineinzuschreiben ist falsch.

| Spalte in `PrMedia` | im iSFP |
|---|---|
| `XimMediaType` | **Funktion** — 10 Titelbild, 12 Foto heute, 13 Ansicht, 1 Unterlage/Plan, 0 ohne |
| `Category` | Reihenfolge innerhalb der Funktion |
| `ShortDesc` | `titel` |
| `InfoDesc` | `beschreibung` |
| `MediaCopyright` | `bildquelle` |

Funktion 12 hat in fast jedem Projekt genau 4 Bilder, Funktion 10 genau 1,
Funktion 13 beliebig viele — und die Anzahl stimmt jeweils exakt mit den
`item`-Knoten unter `fotos/` überein. Feld für Feld an Messinger und Bieche
nachgewiesen.

**Prinzipskizzen** je Maßnahme sind das Gegenteil: in der iSFP-Maske oder in
der Druckanwendung hochgeladen und **direkt** in der `iSFP2.xml` gespeichert.
`isfp-texte-fuellen.ps1` füllt sie aus dem Ordner `Maßnahmenbilder`.

**Why:** Ich hatte aus „null Foto-Streams in der XML" geschlossen, die Bilder
fehlten im Projekt, und wollte sie aus der `.mSFPprojekt` zurückschreiben. Sie
waren die ganze Zeit da. Der Abgleich über alle Projekte hat es widerlegt.

**How to apply:** Zwei Wege, je nachdem was ansteht.

*Prüfen:* `isfp-fertigstellen.ps1 -Projekt '…'` zeigt unter *Bilder in
Hottgenroth*, welchem Bild Funktion, Name oder Beschreibung fehlt. Ein Bild mit
`XimMediaType` 0 erscheint im Fahrplan überhaupt nicht.

*Anlegen:* das MCP-Werkzeug **`import_hottgenroth_bilder`** (Recht
`hottgenroth:schreiben`, Regel HA-12). Bilder zuerst an `POST /api/mcp/dateien`,
dann den `schluessel` mit `funktion`, `name` und `beschreibung` übergeben. Auf
dem Arbeitsplatz läuft `hottgenroth-agent/tools/Import-Bilder.ps1`. Mit
`vorschau: true` prüft der Lauf nur. Energie.exe muss geschlossen sein.
Siehe [[druckanwendung-fliesst-nicht-zurueck]] und [[isfp-drei-stufen]].
