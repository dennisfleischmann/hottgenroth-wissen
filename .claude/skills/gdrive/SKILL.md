---
name: gdrive
description: Kundenunterlagen aus Google Drive holen — Vor-Ort-Aufnahmen, Checklisten, Fotos, Grundrisse. Auslöser: Datei aus Drive, Unterlagen, Vor-Ort-Ordner, Fensterliste, Fotocheckliste, DENA-Liste, "liegt im Drive".
---

**Stand:** Erprobt am 23.08.2026 — Token geholt, Ordner durchsucht, PDF und
Google-Doc heruntergeladen. Läuft ohne jede Anmeldung im Browser.

## Der Zugang läuft NICHT über die lokale App

Das ist die Falle, in die ich zuerst gelaufen bin. Die lokale Installation hat
`GDRIVE_ENABLED=false`, keine Client-Zugangsdaten und **null** Nutzer mit
`google_refresh_token`. `config/gdrive.php` kennt auch kein Dienstkonto, nur
Nutzer-OAuth. Von hier aus kommt man über die App also nicht an Drive — und der
Weg über einen MCP-Connector scheitert an derselben Anmeldung.

**Stattdessen gibt die Produktion ein frisches Access-Token heraus**, gegen ein
gemeinsames Geheimnis:

```
https://www.fs-energieberater.de/api/google-drive/token
Header: X-App-Secret: <GDRIVE_TOKEN_API_SECRET aus .env>
```

Zwei Dinge, die sonst Zeit kosten:

- **Immer `www.` benutzen.** Die Root-Domain antwortet mit 301, und curl wirft
  beim Weiterleiten den `X-App-Secret`-Header weg — die Anfrage kommt dann ohne
  Geheimnis an und wird abgewiesen.
- **Das Geheimnis steht in `.env`** als `GDRIVE_TOKEN_API_SECRET`. Von dort
  lesen, nie in eine Datei schreiben, die im Repo landen kann.

Die Antwort führt `access_token`, `expires_in` (rund 30 Minuten), `scopes`,
`account` und `refreshed`. Mit `?include_refresh_token=1` kommt zusätzlich das
Refresh-Token — das braucht man nur, wenn ein anderes System selbst erneuern
soll, hier also nie.

## Werkzeug

`gdrive.sh` neben dieser Datei. Es holt das Token selbst und kommt ohne `jq`
aus (das ist auf dieser Maschine nicht installiert).

```bash
.claude/skills/gdrive/gdrive.sh suchen "Fensterliste"
.claude/skills/gdrive/gdrive.sh liste  <Ordner-ID>
.claude/skills/gdrive/gdrive.sh wo     <ID>            # Name + Elternordner
.claude/skills/gdrive/gdrive.sh holen  <Datei-ID> <Zielpfad>
.claude/skills/gdrive/gdrive.sh export <Datei-ID> <Zielpfad> [MIME]
.claude/skills/gdrive/gdrive.sh docanlegen <HTML> <Name> <Ordner-ID>        # schreibt!
.claude/skills/gdrive/gdrive.sh hochladen  <Datei> <Name> <Ordner-ID> [MIME]  # schreibt!
```

**Die letzten beiden schreiben** — alle übrigen Befehle sind lesend.

`docanlegen` lädt eine HTML-Datei
hoch und lässt Drive sie in ein Google Doc umwandeln. Überschriften, Tabellen
und Listen kommen durch; `<pre>` landet in Courier, ASCII-Skizzen bleiben also
ausgerichtet. Der Rumpf wird von Hand als `multipart/related` gebaut — `curl -F`
erzeugt `multipart/form-data`, und das nimmt die Drive-API für den kombinierten
Aufruf aus Metadaten und Inhalt nicht an.

`hochladen` schreibt ebenfalls, lädt aber **unverändert** hoch, ohne Umwandlung
— für `.xlsx`, PDF, Bilder.

Damit entsteht der **Lage-Steckbrief**: die Meta-Datei im Plan-Ordner, die
beantwortet, *welches* Gebäude gemeint ist und wie es liegt. Ohne sie ist bei
angebauter Bebauung nicht entscheidbar, welche Einheit ein Grundriss zeigt und
welche Wand die Haustrennwand ist.

Sie ist eine **Tabelle mit genau fünf Spalten**, eine Zeile je Gebäude:
Gebäude · Haustürfassade zeigt nach · Haustrennwände zeigen nach · Im Plan ist
unsere Einheit · Erkennungsmerkmal. Erzeugt von
`sanierungsfahrplan-agent/referenz/lage-steckbrief.php`; ausgefülltes Beispiel
im Plan-Ordner von XWSKQ.

`holen` funktioniert nicht für Google-eigene Formate. Ein Google Doc braucht
`export` mit `text/plain`, ein Sheet mit `text/csv`. Woran man sie erkennt:
`mimeType` beginnt mit `application/vnd.google-apps.`.

**`includeItemsFromAllDrives=true` und `supportsAllDrives=true` gehören an jede
Abfrage.** Ohne sie findet die Suche nichts, was in einer geteilten Ablage
liegt — und dort liegen die Kundenordner. Das Skript setzt beides.

## Wie die Ablage aufgebaut ist

Je Auftrag ein Ordner, benannt nach dem Muster

```
{PREFIX}_{Kundenname}_Vor-Ort        z. B.  XWSKQ_Holger Hoffmann_Vor-Ort
```

Der Präfix ist das CRM-Kürzel. Typischer Inhalt:

| Datei | was drinsteht |
|---|---|
| `Fenster Checkliste_{Kunde}.pdf` | Fenstermaße der Aufnahme |
| `Fotocheckliste_{Kunde}.pdf` | Fotoprotokoll |
| `DENA Liste mit Gebäudehülle_{Kunde}.pdf` | Bauteile der Hülle |
| `Hinweise_{Kunde}` (Google Doc) | Freitext des Aufnehmers — **immer zuerst lesen** |
| `Fotos/` | Bilder, oft auch die Grundrisse |

Die Hinweise sind ein Google Doc, also `export`, nicht `holen`. Sie sind kurz
und beantworten regelmäßig Fragen, die man sonst aus Plänen raten müsste
(Baujahr der Fenster, Sonderformen, was zum beheizten Bereich gehört).

Der schnellste Einstieg ist nicht die Ordnersuche, sondern die **Dateisuche
nach dem Kundennamen** — `suchen "Hoffmann"` liefert die Dateien samt
Eltern-ID, `wo <Eltern-ID>` nennt dann den Auftragsordner.

## Grenze: gescannte PDF

Die Checklisten sind **Fotos, keine Textdokumente** — eine Seite, ein Bild,
null Schriften. Text herausziehen bringt daher nichts; man muss die Seite
ansehen. Dafür fehlt auf dieser Maschine ein PDF-Werkzeug (kein poppler, kein
Ghostscript, kein echtes Python; die App hat mit `dompdf` nur einen Schreiber).

Ein Bild von Hand aus dem PDF zu schneiden ist ein Irrweg — alle Ströme sind
`FlateDecode`, die Wörterbücher liegen in gepackten Objektströmen, und die
Bytefolge `stream` kommt auch in Binärdaten vor. Das ist ein PDF-Parser, kein
Einzeiler; ich habe es versucht und wieder verworfen.

Zwei gangbare Wege, beide brauchen eine Entscheidung des Nutzers:

- **poppler portabel** nach `C:\Projekte_Dev\tools\poppler` (ZIP, kein
  Installer, keine Adminrechte, dieselbe Stelle wie `php84`). Danach
  `pdftoppm -r 200 -png` und die Seite als Bild lesen.
- **Drive als Wandler:** die PDF per `files.copy` nach
  `application/vnd.google-apps.document` kopieren — Drive führt dabei eine
  Texterkennung aus. Bei **Handschrift ist das Ergebnis schlecht**, und es legt
  eine Datei in fremdem Drive an, die man wieder aufräumen muss.

Für handschriftlich ausgefüllte Checklisten ist Ansehen richtig und
Texterkennung falsch.
