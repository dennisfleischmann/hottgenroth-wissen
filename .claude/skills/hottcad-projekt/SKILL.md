---
name: hottcad-projekt
description: Für einen Kunden ein neues HottCAD-Projekt auf dem Hottgenroth-Arbeitsplatz anlegen — Basisvorlage einspielen, Eigentümer (Kundenadresse), Projektadresse und Planer eintragen, optional Bilder mit Typ, Bildname und Beschreibung dazulegen, und das fertige Projekt als .sqproj in die fs-app exportieren. Auch für einen reinen Export eines vorhandenen Projekts. Auslöser: "leg ein HottCAD-Projekt an", "neues Hottgenroth-Projekt für Kunde X", "Projekt aus der Vorlage", "Kunde und Adresse in Hottgenroth eintragen", "Projektadresse/Eigentümer/Planer setzen", "Fotos ins neue Projekt", Projektreferenz wie 3QHTK zusammen mit Hottgenroth oder HottCAD.
---

**Stand:** 10.10.2026. Erprobt am Arbeitsplatz FSLAPTOP1: Vorlage importiert, drei
Kontakte geschrieben, in der Oberfläche gefüllt, nach Export und Re-Import weiter
gefüllt. Der Bildteil (`bilder`) ist einzeln erprobt (Import-Bilder.ps1 am
Testprojekt), im Gesamtlauf über das Werkzeug noch nicht. Behandle ihn
entsprechend: Ergebnis mit `get_vorgang` prüfen, nicht annehmen.

## Worum es geht

Ein Werkzeug, ein Auftrag: `create_hottcad_projekt` legt auf dem Rechner des
Beraters ein neues Projekt aus der **Basisvorlage** an und trägt ein:

| Reiter in Hottgenroth | Woher | Inhalt |
|---|---|---|
| **Eigentümer** (Kundenadresse) | Zoho: Kontakt im Lookup `Kunde` | Anrede, Vor- und Nachname, Anschrift, E-Mail, Telefon |
| **Projektadresse** | Zoho: `Gebaeudedaten` des Projekts | Straße, Hausnummer, PLZ, Ort |
| **Planer** | fest hinterlegt | FS Energieberater GmbH, Angelika-Machinek-Straße 14, 60486 Frankfurt am Main |

Optional kommen **Bilder** in die Bilderverwaltung, mit Typ, Bildname und
Beschreibung. **Zum Schluss** wird das fertige Projekt als `.sqproj` in die fs-app
exportiert (Seite Hottgenroth-Exporte) — von dort lässt es sich herunterladen und
weitergeben.

Du gibst nur die Zoho-Projekt-ID an. Adressen tippst du nie selbst ab und rätst
sie nie — fehlt etwas im CRM, sagt das Werkzeug es, und der Mensch ergänzt es dort.

**Es verändert den Bestand auf dem Rechner eines Menschen und lässt sich über die
Schnittstelle nicht zurückdrehen.** Deshalb gibt es genau einen Haltepunkt: die
Vorschau, bevor geschrieben wird.

**Formatregel: in Text an den Menschen steht nie eine GUID oder eine lange
Record-ID.** Projekte heißen bei Referenz und Kundenname („3QHTK, Lennart Krause"),
Vorgänge bei ihrer Nummer. In Werkzeugargumenten dagegen wird die ID unverändert
aus der Antwort durchgereicht — kopieren, nicht wiedergeben.

### Wie du die Werkzeuge aufrufst

Am FS Connector laufen alle Werkzeuge über zwei Aufrufe: `werkzeuge_suchen`
(einmal, Bereich `hottgenroth` bzw. `zoho`) und dann
`werkzeug_ausfuehren { "name": "<werkzeug>", "argumente": { … } }`. Die Namen unten
sind die Werkzeugnamen, die du dort einsetzt.

### Voraussetzungen

- Der Zugang trägt das Recht `hottgenroth:schreiben`. Fehlt es, kommt
  `kein_schreibrecht` — das vergibt ein Admin von Hand, nicht du.
- Eine Basisvorlage ist hinterlegt (Admin lädt sie unter `/admin/hottgenroth` hoch,
  Karte „Basisvorlage für neue HottCAD-Projekte"). Fehlt sie: `vorlage_fehlt`.
- Der Arbeitsplatz des Beraters ist an. Ist er aus, bleibt der Auftrag liegen, bis
  er wieder da ist.
- **Hottgenroth ist geschlossen** — Energieberater, EE-Berater und HottCAD. Der
  Auftrag prüft das selbst und bricht sonst vor dem Import ab. Frag trotzdem vorher,
  dann scheitert er nicht erst nach einer Minute.

---

## 1 — Das Zoho-Projekt finden

Der Mensch nennt meist die Projektreferenz (fünf Zeichen, z. B. `3QHTK`) oder den
Kundennamen.

```
search_zoho { modul: "Projekte", wort: "3QHTK" }
```

Die `id` des Treffers ist die `crm_project_id`. Gibt es mehrere Treffer, zeig
Referenz, Name und Status und frag, welcher gemeint ist. Kein Treffer: mit dem
Nachnamen suchen, nicht raten.

## 2 — Vorschau holen (Haltepunkt)

```
create_hottcad_projekt { crm_project_id: "…", vorschau: true }
```

Es passiert nichts auf dem Rechner. Die Antwort trägt `eigentuemer`,
`projektadresse`, `planer`, `gruppe`, `vorlage`, `export`, gegebenenfalls `bilder` und
`hinweise`.

**Leg das dem Menschen in Klartext vor**, nicht als JSON:

> Ich würde für **3QHTK, Lennart Krause** anlegen:
> - Eigentümer: Herr Lennart Krause, Hauptstr. 20, 82387 Antdorf, lennart@…, 0160 …
> - Projektadresse: Am Raut 7, 82387 Antdorf
> - Planer: FS Energieberater GmbH, Frankfurt am Main
> - Gruppe in Hottgenroth: `3QHTK_Lennart Krause_261010`, Vorlage „Basis EFH.sqproj"
> - Danach als Projektdatei in die fs-app (Exporte-Seite)
>
> Hottgenroth muss dafür geschlossen sein. Soll ich?

Achte auf zwei Dinge und sprich sie an:

- **`hinweise`**: steht dort „als Kundenadresse gilt die Objektadresse", hatte der
  Kontakt im CRM keine eigene Anschrift. Das ist bei selbstgenutzten Häusern
  richtig, sonst nicht — frag nach.
- **Leere Anrede**: dann steht im CRM keine „Sehr geehrte(r) Frau/Herr". Das
  Projekt wird trotzdem angelegt, nur ohne Anrede.

Fehlercodes dieser Stufe — **es wurde nichts angelegt**, nur sagen und warten:

| Code | Bedeutung | Was du tust |
|---|---|---|
| `projekt_unbekannt` | Kein Zoho-Projekt mit dieser ID | ID aus `search_zoho` nehmen |
| `kunde_fehlt` | Am Projekt hängt kein Kunde mit Nachnamen | Mensch setzt im CRM den Lookup `Kunde` |
| `objektadresse_fehlt` | In den Gebäudedaten fehlen Straße oder Ort | Mensch ergänzt die Gebäudedaten im CRM |
| `vorlage_fehlt` | Keine Basisvorlage hinterlegt | Admin lädt sie unter `/admin/hottgenroth` hoch |

## 2b — Mit Komponenten (optional)

Will der Mensch die Bauteile gleich mit drin haben:

- **`mit_komponenten: true`** — die Bauteile, die am FS-Projekt desselben
  Zoho-Projekts hängen (dort mit `add_component_to_project` zugeordnet).
- **`komponenten`** — weitere aus dem Katalog: je `catalog_component_id`, optional
  `component_type`, `variante`, `name`. Höchstens 8 zusammen.

Sie kommen in den **Katalog** des neuen Projekts, **nicht an Flächen** — ein neues
Projekt hat noch keine. Sag das dem Menschen so. Zuweisen geht erst mit
`add_components`, wenn das Modell gezeichnet ist; danach einmal
`export_hottgenroth_projekt`, damit die Datei in der fs-app die Zuweisung enthält.

Die Vorschau zeigt unter `komponenten` je Bauteil Name, `art`, `lage` und Schichtzahl
oder U-Wert. Leg sie mit vor.

| Code | Bedeutung | Was du tust |
|---|---|---|
| `fs_projekt_ohne_bauteile` | `mit_komponenten` gesetzt, aber am FS-Projekt hängt keins | erst `add_component_to_project`, oder sie als `komponenten` nennen |
| `flaechen_nicht_moeglich` | ein Eintrag hatte `element_uids` | ohne Flächen angeben |
| `fenster_ohne_g_wert`, `u_wert_mehrdeutig`, `bauteilart_ohne_weg` | wie bei `add_components` | anderen Katalogtreffer wählen — keinen Wert raten |

Ein Bauteil, das sich nicht auflösen lässt, verhindert den **ganzen** Auftrag. Es wird
nichts angelegt.

## 3 — Bilder (optional)

Nur wenn der Mensch Bilder mitgeben will. Jedes Bild muss **vorher** als Datei an
den Server — die Bytes reisen nicht durch den Werkzeugaufruf:

```
POST /api/mcp/dateien   (multipart, Feld "datei", JPEG oder PNG, Bearer-Token)
→ { "schluessel": "files/uploads/fassade-20261010-101500-ab12cd.jpg", … }
```

Kannst du keinen HTTP-Upload machen (reiner Chat am Connector), dann leg das
Projekt **ohne** Bilder an und sag dem Menschen, dass die Bilder danach einzeln
über `import_hottgenroth_bilder` oder von Hand in die Bilderverwaltung kommen.

Je Bild ein Eintrag in `bilder`:

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `schluessel` | ja | aus der Upload-Antwort, unverändert |
| `funktion` | ja | der **Typ**, siehe unten |
| `name` | ja | der **Bildname**, wie er gedruckt wird — „Fassade Süd", kein Dateiname |
| `beschreibung` | nein, aber gewünscht | die **Bildunterschrift**: was zu sehen ist und warum es wichtig ist — „Verputzte Außenwand ohne Dämmung, Carport an der Giebelseite", nicht „Fassade" |
| `bildquelle` | nein | Urheber, wenn das Bild nicht vom Berater ist |
| `reihenfolge` | nein | Platz innerhalb des Typs, ab 1; weglassen = nächster freier |

Die Typen (`funktion`):

| `funktion` | Typ in Hottgenroth | Wofür | Anzahl |
|---|---|---|---|
| `titelbild` | Titelbild | Titelseite des Fahrplans | genau 1 |
| `foto_heute` | Aktueller Stand | Abschnitt „Ihr Haus heute": Fassade, oberste Geschossdecke, Heizung, Fenster | üblicherweise 4 |
| `ansicht` | Ansicht | Gebäudeansichten | beliebig |
| `unterlage` | benutzerdefiniert | Pläne, Grundrisse — **nicht** im Fahrplan | beliebig |
| `zonierung` | Zonierung | Zonierungsskizze nach DIN V 18599 — nicht im Fahrplan | beliebig |
| `systemgrenze` | Systemgrenze | Skizze der thermischen Hülle — nicht im Fahrplan | beliebig |
| `unterschrift` | Unterschrift | Unterschrift des Beraters für die Berichte | genau 1 |

Wähl den Typ nach dem, **was auf dem Bild ist**, nicht nach dem Dateinamen. Bist
du unsicher (Grundriss oder Zonierung?), frag. Einen anderen Typ gibt es nicht —
`funktion_unbekannt` heißt: einer aus der Tabelle.

Zeig die Bilder in der Vorschau mit: dieselbe Vorschau wie in Schritt 2, mit
`bilder` dabei. Die Antwort listet sie mit Typ, Name und Beschreibung.

Fehlercodes der Bildliste — **es wurde nichts angelegt, auch kein Projekt**:

| Code | Bedeutung | Was du tust |
|---|---|---|
| `datei_unbekannt` | Schlüssel nicht aus dem Upload-Ordner, keine JPEG/PNG, oder die Datei liegt nicht in der Ablage | erneut hochladen, den neuen `schluessel` nehmen |
| `funktion_unbekannt` | Typ gibt es nicht | einen aus der Tabelle |
| `bild_unbrauchbar` | z. B. ohne Namen, oder zwei Bilder auf denselben Platz | Eintrag ergänzen bzw. `reihenfolge` korrigieren |
| `zu_viele_bilder` | mehr als 20 | aufteilen: Projekt mit 20, den Rest über `import_hottgenroth_bilder` |

## 4 — Anlegen

Erst nach dem Ja des Menschen, mit **denselben** Argumenten ohne `vorschau`:

```
create_hottcad_projekt { crm_project_id: "…", bilder: [ … ] }
```

Der Export ist Vorgabe. Will der Mensch ausdrücklich keine Datei in der fs-app, setz
`export: false`.

Antwort `status: angestossen` mit `vorgang_id`. **Ruf das Werkzeug danach nicht
noch einmal auf** — jeder Lauf legt ein weiteres Projekt an.

| `status` | Bedeutung | Was du tust |
|---|---|---|
| `angestossen` | Auftrag steht, Arbeitsplatz holt ihn in 20–30 s | weiter mit Schritt 5 |
| `lief_schon` | für dieses Zoho-Projekt läuft schon einer | denselben `vorgang_id` verfolgen, keinen neuen |
| `schon_angelegt` | es gibt schon ein Projekt aus einem früheren Lauf | dem Menschen sagen; ein zweites nur auf ausdrücklichen Wunsch mit `erneut: true` |
| `vorheriger_lauf_unvollstaendig` | ein früherer Lauf brach ab, **nachdem** er zu schreiben begann | Projekt liegt vermutlich schon da — mit `get_vorgang` nachsehen, was fehlt; **nicht** `erneut` setzen, um das zu „reparieren" |

`arbeitsplatz_erreichbar: false` heißt: der Rechner ist aus. Sag es, statt zu warten.

## 5 — Nachverfolgen

Nach etwa einer Minute, dann im Abstand von ein, zwei Minuten — nicht in einer
Schleife:

```
get_vorgang { vorgang_id: 123 }
```

- **erledigt** → Schritt 6. Unter `dateien` steht die `.sqproj` mit `groesse_mb` und
  `link`. Steht dort stattdessen **`export_fehlt`**, ist das Projekt angelegt, nur die
  Datei kam nicht an (z. B. über 128 MB). Dann `export_hottgenroth_projekt` — und
  **nicht** `create_hottcad_projekt` noch einmal.
- **läuft / wartet** → später noch einmal. Der Import dauert je nach Vorlage Minuten.
- **gescheitert, `geschrieben: false`** → es wurde nichts angelegt. Steht in der
  Meldung, dass die Software offen war: Mensch schließt Hottgenroth, dann
  derselbe Aufruf aus Schritt 4 noch einmal. Das ist der einzige Fall, in dem du
  neu aufrufst.
- **gescheitert, `geschrieben: "ungewiss"`** → **nicht wiederholen.** Das Projekt
  ist vermutlich angelegt, aber Kontakte oder Bilder fehlen. Sag dem Menschen, er
  soll in Hottgenroth nachsehen; fehlende Bilder holst du mit
  `import_hottgenroth_bilder` nach. Ein zweiter Lauf legte ein zweites Projekt an,
  und löschen geht über die Schnittstelle nicht.

## 6 — Abschluss

Sag dem Menschen drei Dinge:

1. **Hottgenroth neu starten.** Die Software liest ihren Projektbestand beim Start;
   das neue Projekt erscheint erst danach.
2. **Wo es liegt:** in der Gruppe aus `gruppe`, z. B. `3QHTK_Lennart Krause_261010`.
   **Das Projekt selbst heißt wie die Vorlage** — das ist bekannt und kein Fehler;
   umbenennen kann der Berater es in der Software.
3. **Was er prüfen soll:** Reiter Projektadresse, Planer, Eigentümer; bei Bildern
   die Bilderverwaltung (Typ, Bildname, Beschreibung).
4. **Den Download-Link der Projektdatei.** Aus `dateien`: Name, Größe und den `link` —
   **immer ausgeben**, als klickbaren Link. Er funktioniert ohne Anmeldung und gilt bis
   `gueltig_bis` (72 Stunden). Ist er abgelaufen, `get_vorgang` erneut aufrufen; jeder
   Aufruf stellt einen frischen aus.

   > Die Projektdatei liegt bereit: [3QHTK_Lennart_Krause_261010.sqproj](…) (9,1 MB,
   > Link gültig bis 13.10. 16:00). Du findest sie auch in der fs-app unter Hottgenroth-Exporte.

Fotos vom Handy können in der Bilderverwaltung **quer** liegen — die Software
beachtet die Drehangabe des Fotos nicht überall. Das ist keine Beschädigung; der
Berater dreht sie dort mit dem Drehen-Knopf.

---

## Nur exportieren

Für ein **vorhandenes** Projekt, ohne etwas anzulegen:

```
export_hottgenroth_projekt { projekt: "3QHTK" }
→ get_vorgang { vorgang_id: … }   → dateien[0].link   → dem Menschen geben
```

Ist der Vorgang erledigt, **gib den `link` aus `dateien` aus** — das ist das Ergebnis,
nicht die Meldung „exportiert". Er funktioniert ohne Anmeldung und gilt bis `gueltig_bis`.

- Genügt das Leserecht; am Projekt ändert sich nichts.
- Exportiert wird der **gespeicherte** Stand — frag, ob der Berater gespeichert hat.
- Gefunden wird im Spiegel. Fehlt das Projekt, zuerst `update_hottgenroth_projects`.
- Über 128 MB scheitert der Vorgang mit Größe und Grenze in der Meldung. Sag dann:
  in Hottgenroth über „Projekt exportieren" von Hand.
- Ein neuer Aufruf ist gefahrlos, er erzeugt nur eine weitere Datei. Läuft schon
  einer, kommt `lief_schon` mit demselben Vorgang.

---

## Was nicht geht

- **Ein vorhandenes Projekt nachträglich mit Kunde oder Adresse füllen.** Das
  Werkzeug legt immer ein neues an.
- **Bildname oder Beschreibung eines vorhandenen Bildes ändern.** Weder hier noch
  über `import_hottgenroth_bilder` — das macht der Berater in der Bilderverwaltung.
- **Einen anderen Planer eintragen.** Er ist fest FS Energieberater GmbH.
- **Löschen.** Ein doppelt angelegtes Projekt entfernt ein Mensch in der Software.
- **Projektdateien über 128 MB** in die fs-app laden.
