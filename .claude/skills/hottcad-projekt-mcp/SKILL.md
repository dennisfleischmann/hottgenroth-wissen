---
name: hottcad-projekt-mcp
description: Über den MCP-Zugang (FS Connector) ein HottCAD-Projekt in Hottgenroth anlegen und befüllen — Adressdaten (Eigentümer/Kundenadresse, Projektadresse, Planer) einspielen, Komponenten (Bauteile) hinzufügen, Bilder hochladen und mit Typ, Bildname und Beschreibung in die Bilderverwaltung legen, und die fertige .sqproj per Download-Link ausgeben. Auslöser: "Projekt in Hottgenroth anlegen", "Adresse/Kunde/Planer eintragen", "Bauteile/Komponenten ins Projekt", "Fotos/Bilder hochladen", "Titelbild/Ansicht/Zonierung", "welche Bildtypen gibt es", "Download-Link der Projektdatei".
---

**Stand:** 10.10.2026, live. Einmal vollständig durchgelaufen (Vorgang 264: Vorlage,
drei Kontakte, eine Komponente, Export, Download-Link ohne Anmeldung geprüft). Der
Bildteil im selben Auftrag ist einzeln erprobt, im Gesamtlauf noch nicht.

## Die Werkzeuge

Alles läuft über den FS Connector: einmal `werkzeuge_suchen` (Bereich `hottgenroth`),
dann je Aufruf

```
werkzeug_ausfuehren { "name": "<werkzeug>", "argumente": { … } }
```

| Werkzeug | Wofür | Recht |
|---|---|---|
| `create_hottcad_projekt` | neues Projekt aus der Basisvorlage, mit Adressdaten, optional Komponenten und Bildern, zum Schluss Export | `hottgenroth:schreiben` |
| `import_hottgenroth_bilder` | Bilder in ein **vorhandenes** Projekt | `hottgenroth:schreiben` |
| `add_components` | Bauteile in ein **vorhandenes** Projekt, auch an Flächen zuweisen | `hottgenroth:schreiben` |
| `export_hottgenroth_projekt` | vorhandenes Projekt als `.sqproj` in die fs-app | `hottgenroth:lesen` |
| `get_vorgang` | was aus einem Auftrag wurde, mit Download-Link | `hottgenroth:lesen` |
| `search_zoho` | das Zoho-Projekt finden (Bereich `zoho`) | Zoho-Lesen |

Alle Aufträge laufen auf dem Arbeitsplatz des Beraters. **Hottgenroth muss dort
geschlossen sein** (Energieberater, EE-Berater, HottCAD) — sonst bricht der Auftrag
ab, bevor er etwas schreibt. Frag vorher danach.

**Formatregel:** In Text an den Menschen nie eine GUID oder lange Record-ID. Projekte
heißen bei Referenz und Kundenname („3QHTK, Lennart Krause"). In Argumenten dagegen
IDs und Schlüssel unverändert aus der vorigen Antwort kopieren.

---

## 1 — Adressdaten einspielen

Die Adressdaten tippst du **nicht** ab. Du nennst nur das Zoho-Projekt; das Werkzeug
holt den Rest selbst:

| Reiter in Hottgenroth | Quelle | Inhalt |
|---|---|---|
| **Eigentümer** (Kundenadresse) | Zoho: Kontakt im Lookup `Kunde` | Anrede, Vor- und Nachname, Straße, Hausnummer, PLZ, Ort, E-Mail, Telefon |
| **Projektadresse** | Zoho: `Gebaeudedaten` des Projekts | Straße, Hausnummer, PLZ, Ort |
| **Planer** | fest hinterlegt | FS Energieberater GmbH, Angelika-Machinek-Straße 14, 60486 Frankfurt am Main |

**Schritt 1 — Zoho-Projekt finden:**

```
search_zoho { modul: "Projekte", wort: "3QHTK" }
```

Die `id` des Treffers ist die `crm_project_id`. Mehrere Treffer: Referenz, Name und
Status zeigen und fragen.

**Schritt 2 — Vorschau (Haltepunkt):**

```
create_hottcad_projekt { crm_project_id: "824764000038701660", vorschau: true }
```

Es passiert nichts. Leg dem Menschen in Klartext vor, was die Antwort unter
`eigentuemer`, `projektadresse`, `planer` und `gruppe` zeigt, und hol sein Ja.
Steht unter `hinweise` „als Kundenadresse gilt die Objektadresse", hatte der Kontakt
keine eigene Anschrift — ansprechen.

**Schritt 3 — anlegen:** derselbe Aufruf ohne `vorschau` (Komponenten und Bilder
siehe unten, sie gehören in denselben Aufruf).

Fehlt etwas im CRM, wird **nichts** angelegt — nicht raten, dem Menschen sagen:

| Code | Was fehlt | Wer behebt |
|---|---|---|
| `kunde_fehlt` | kein Kunde mit Nachnamen am Projekt | Mensch setzt den Lookup `Kunde` |
| `objektadresse_fehlt` | Straße oder Ort in den Gebäudedaten | Mensch ergänzt die Gebäudedaten |
| `projekt_unbekannt` | keine Zoho-Projekt-ID | ID aus `search_zoho` nehmen |
| `vorlage_fehlt` | keine Basisvorlage hinterlegt | Admin lädt sie unter `/admin/hottgenroth` hoch |

**Nur für neue Projekte.** Ein vorhandenes Projekt nachträglich mit Adressen füllen
kann kein Werkzeug.

---

## 2 — Komponenten hinzufügen

Komponenten sind Bauteile aus dem FS-Bauteilkatalog (Außenwand, Dach, Fenster …).

### Beim Anlegen (`create_hottcad_projekt`)

Zwei Wege, auch zusammen:

- **`mit_komponenten: true`** — die Bauteile, die am FS-Projekt desselben
  Zoho-Projekts hängen (dort vorher mit `add_component_to_project` zugeordnet).
- **`komponenten`** — eigene Liste, je Eintrag:

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `catalog_component_id` | ja | `component_id` aus `find_building_components` |
| `component_type` | nein | als was der Eintrag gemeint ist, z. B. `Außenwand` |
| `variante` | nein | Aufbauvariante, wenn das Datenblatt mehrere führt |
| `name` | nein | abweichender Name im Projektkatalog |

Höchstens 8 zusammen.

```
create_hottcad_projekt {
  crm_project_id: "…",
  komponenten: [ { catalog_component_id: 422, component_type: "Außenwand" } ]
}
```

**Sie kommen in den Katalog des Projekts, nicht an Flächen.** Ein neues Projekt hat
noch keine gezeichneten Flächen. Sag das dem Menschen so. Die Vorschau zeigt sie unter
`komponenten` mit `art`, `lage` und Schichtzahl oder U-Wert.

### Später an Flächen zuweisen (`add_components`)

Ist das Modell gezeichnet und steht das Projekt im Spiegel
(`get_hottgenroth_components`), weist `add_components` die Bauteile Flächen zu — mit
`element_uids` aus `get_hottgenroth_components` (`flaechen_einzeln: true`) und immer
erst mit `probelauf: true`. Danach einmal `export_hottgenroth_projekt`, damit die Datei
in der fs-app die Zuweisung enthält.

| Code | Bedeutung | Was du tust |
|---|---|---|
| `fs_projekt_ohne_bauteile` | `mit_komponenten` gesetzt, am FS-Projekt hängt keins | erst `add_component_to_project`, oder als `komponenten` nennen |
| `flaechen_nicht_moeglich` | `element_uids` beim Anlegen angegeben | ohne Flächen angeben, zuweisen später |
| `fenster_ohne_g_wert`, `u_wert_mehrdeutig`, `bauteilart_ohne_weg` | Katalogeintrag nicht einspielbar | anderen Treffer wählen — keinen Wert raten |

Ein Bauteil, das sich nicht auflösen lässt, verhindert den **ganzen** Auftrag.

---

## 3 — Bilder hochladen

### Schritt A — die Datei an den Server

Die Bytes reisen **nicht** durch den Werkzeugaufruf. Jedes Bild geht vorher als
gewöhnlicher HTTP-Upload an den Server, mit demselben Bearer-Token wie der MCP-Zugang:

```
POST https://www.fs-energieberater.de/api/mcp/dateien
Authorization: Bearer <Token>
Content-Type: multipart/form-data   — Feld "datei"
```

```bash
curl -X POST https://www.fs-energieberater.de/api/mcp/dateien \
     -H "Authorization: Bearer fsmcp_…" \
     -F "datei=@C:/Fotos/fassade.jpg"
# -> {"schluessel":"files/uploads/fassade-20261010-101500-ab12cd.jpg","groesse_mb":2.1,"sha256":"…"}
```

- Erlaubt: **JPEG und PNG** (`.jpg`, `.jpeg`, `.png`), bis **40 MB** je Datei. Der Server
  öffnet das Bild und weist eine umbenannte Datei ab.
- Recht: `hottgenroth:schreiben`.
- In PowerShell `Invoke-WebRequest -InFile` und `Content-Length` setzen lassen — der
  Server verwirft Uploads mit `Transfer-Encoding: chunked`.

**Kannst du keinen HTTP-Upload machen** (reiner Chat am Connector, ohne Datei- oder
Netzwerkzugriff): dann gibt es von dir aus keinen Weg, ein Bild hochzuladen. Leg das
Projekt ohne Bilder an und sag dem Menschen, dass er die Bilder in Hottgenroth selbst in
die Bilderverwaltung legt — oder ein Client mit Upload sie danach mit
`import_hottgenroth_bilder` nachreicht. Erfinde keinen `schluessel`.

### Schritt B — das Bild ins Projekt

**Neues Projekt:** als `bilder` im selben `create_hottcad_projekt`-Aufruf.
**Vorhandenes Projekt:** `import_hottgenroth_bilder { projekt: "…", bilder: [ … ] }`.
Beide nehmen dieselben Einträge:

| Feld | Pflicht | In Hottgenroth | Bedeutung |
|---|---|---|---|
| `schluessel` | ja | — | aus der Upload-Antwort, unverändert |
| `funktion` | ja | **Typ** | siehe Tabelle unten |
| `name` | ja | **Bildname** | wie er gedruckt wird: „Fassade Süd", kein Dateiname |
| `beschreibung` | nein, aber gewünscht | **Beschreibung** | was zu sehen ist und warum es wichtig ist |
| `bildquelle` | nein | **Copyright** | Urheber, wenn nicht vom Berater |
| `reihenfolge` | nein | Platz | innerhalb des Typs, ab 1; weglassen = nächster freier |

Eine gute Beschreibung: „Verputzte Außenwand ohne Dämmung, Carport an der
Giebelseite" — nicht „Fassade". Zu kurze Texte bemängelt die Druckprüfung des
Fahrplans.

### Die Bildtypen (`funktion`)

| `funktion` | Typ in Hottgenroth | Wofür | Anzahl |
|---|---|---|---|
| `titelbild` | Titelbild | Titelseite des Sanierungsfahrplans | genau 1 |
| `foto_heute` | Aktueller Stand | Abschnitt „Ihr Haus heute": Fassade, oberste Geschossdecke, Heizung, Fenster | üblicherweise 4 |
| `ansicht` | Ansicht | Gebäudeansichten im Fahrplan | beliebig |
| `unterlage` | benutzerdefiniert | Pläne, Grundrisse — **nicht** im Fahrplan, nur beim Projekt | beliebig |
| `zonierung` | Zonierung | Zonierungsskizze nach DIN V 18599 — nicht im Fahrplan | beliebig |
| `systemgrenze` | Systemgrenze | Skizze der thermischen Hülle — nicht im Fahrplan | beliebig |
| `unterschrift` | Unterschrift | Unterschrift des Beraters, setzen die Berichte ein | genau 1 |

Wähl den Typ nach dem, **was auf dem Bild ist**. Unsicher (Grundriss oder Zonierung?):
fragen. Andere Typen gibt es nicht; ein Bild ohne Typ erscheint in keinem Fahrplan.

```
create_hottcad_projekt {
  crm_project_id: "…",
  bilder: [
    { schluessel: "files/uploads/fassade-….jpg", funktion: "titelbild",
      name: "Ansicht Straße", beschreibung: "Doppelhaushälfte, verputzt, Satteldach" },
    { schluessel: "files/uploads/heizung-….jpg", funktion: "foto_heute", reihenfolge: 3,
      name: "Heizung", beschreibung: "Gas-Niedertemperaturkessel von 1998 im Keller" }
  ]
}
```

| Code | Bedeutung | Was du tust |
|---|---|---|
| `datei_unbekannt` | Schlüssel nicht aus dem Upload, keine JPEG/PNG, oder nicht in der Ablage | erneut hochladen, neuen `schluessel` nehmen |
| `funktion_unbekannt` | Typ gibt es nicht | einen aus der Tabelle |
| `bild_unbrauchbar` | z. B. ohne Namen, oder zwei Bilder auf demselben Platz | ergänzen bzw. `reihenfolge` korrigieren |
| `zu_viele_bilder` | mehr als 20 je Aufruf | aufteilen |

Bei `create_hottcad_projekt` verhindert ein unbrauchbares Bild den ganzen Auftrag —
es entsteht kein Projekt ohne die gewünschten Bilder.

**Handyfotos können quer liegen.** Die Bilderverwaltung beachtet die Drehangabe des
Fotos nicht; der Berater dreht sie dort mit dem Drehen-Knopf. Das ist kein Fehler.

**Vorhandene Bilder ändern** (Name, Beschreibung, Typ) geht über keinen Weg — das macht
der Berater in der Bilderverwaltung.

---

## 4 — Ergebnis und Download-Link

`create_hottcad_projekt` antwortet mit dem Status `angestossen` und einer `vorgang_id`;
zum Schluss exportiert es das Projekt als `.sqproj` in die fs-app (Parameter `export`,
Vorgabe `true`; `false` lässt das weg). Dann:

```
get_vorgang { vorgang_id: 264 }
```

Nach etwa einer Minute, dann im Abstand von ein, zwei Minuten — nicht in einer
Schleife. Der Auftrag läuft: Vorlage → Adressen → Komponenten → Bilder → Export.

- **erledigt** → unter `dateien` steht die `.sqproj` mit `groesse_mb`, `link` und
  `gueltig_bis`. **Gib den `link` dem Menschen**, als klickbaren Link. Er funktioniert
  ohne Anmeldung und gilt 72 Stunden; jeder `get_vorgang`-Aufruf stellt einen frischen
  aus.
- **erledigt, aber `export_fehlt`** → Projekt angelegt, nur die Datei fehlt (z. B. über
  128 MB). `export_hottgenroth_projekt` holt sie nach — **nicht**
  `create_hottcad_projekt` erneut.
- **gescheitert, `geschrieben: false`** → nichts angelegt; meist war Hottgenroth offen.
  Schließen lassen, dann derselbe Aufruf noch einmal.
- **gescheitert, `geschrieben: "ungewiss"`** → **nicht wiederholen.** Projekt liegt
  vermutlich schon da. Der Mensch sieht in Hottgenroth nach; fehlende Bilder mit
  `import_hottgenroth_bilder`.

Zum Abschluss sagen: **Hottgenroth neu starten**, dann steht das Projekt in der Gruppe
aus `gruppe` (z. B. `3QHTK_Lennart Krause_261010`). Es trägt den Namen der Vorlage —
bekannt, kein Fehler.

**Nicht zweimal anlegen.** Jeder Lauf von `create_hottcad_projekt` legt ein weiteres
Projekt an. `lief_schon`, `schon_angelegt` und `vorheriger_lauf_unvollstaendig` sagen,
dass es schon einen gibt; ein zweites nur auf ausdrücklichen Wunsch mit dem Parameter
`erneut` (`true`).
