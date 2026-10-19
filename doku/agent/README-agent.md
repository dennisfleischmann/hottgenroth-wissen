# Hottgenroth-Agent

Fernsteuerung der Hottgenroth-Arbeitsplätze. Der Server stellt Aufgaben ein,
der Agent auf dem jeweiligen Rechner holt sie ab, führt sie gegen die lokale
LocalDB aus und meldet das Ergebnis zurück.

**Der Client kennt keine festen Aufgabentypen.** Eine Aufgabe ist eine Liste
von Schritten, jeder Schritt ruft einen kleinen, allgemeinen Baustein auf. Neue
Fähigkeiten entstehen dadurch, dass der Server diese Bausteine anders
zusammensetzt — der Agent auf dem Arbeitsplatz muss dafür nie angefasst oder neu
ausgerollt werden. Genau das war das Ziel: **Server erweiterbar, Client stabil.**

## Warum Polling

Die Hottgenroth-Software hält ihre Daten in `(localdb)\HSETU` auf dem
Arbeitsplatz. Von außen ist diese Instanz nicht erreichbar — der Rechner steht
hinter NAT, hat keine feste Adresse und ist nicht immer an. Deshalb die
Umkehrung der üblichen Richtung: **der Agent fragt, der Server antwortet.**

```
  fortrabbit (Laravel)                     Arbeitsplatz (Windows)
  ┌────────────────────────┐               ┌──────────────────────────┐
  │ hottgenroth_tasks      │◀── register ──│ hottgenroth-agent.exe    │
  │ hottgenroth_agents     │◀── claim ─────│                          │
  │ hottgenroth_task_events│─── Auftrag ──▶│  Step-Engine             │
  │   (payload.steps)      │◀── progress ──│   └─ Bausteine (13)      │
  │                        │◀── complete ──│          ▼               │
  └────────────────────────┘               │  (localdb)\HSETU         │
                                           └──────────────────────────┘
```

Es wird nie eine Verbindung zum Client geöffnet. Der Agent braucht ausgehendes
HTTPS, sonst nichts.

## Das Aufgabenmodell

Eine Aufgabe ist JSON mit einer Liste `steps`. Jeder Schritt nennt einen
Baustein (`use`), seine Parameter (`with`) und optional einen Namen (`register`),
unter dem sein Ergebnis späteren Schritten zur Verfügung steht. Über
`{{ … }}`-Templates greifen Schritte auf diese Ergebnisse zu.

```json
{
  "steps": [
    { "name": "Datei laden", "use": "http.download",
      "with": { "url": "files/kunde.sqproj" }, "register": "datei" },

    { "name": "Importieren", "use": "project.import",
      "with": { "path": "{{ datei.path }}", "projectName": "Kunde XY",
                "regenerateGuids": true, "dryRun": false }, "register": "imp" },

    { "name": "Gegenprobe", "use": "sql.query",
      "with": { "sql": "SELECT COUNT(*) FROM PrProject WHERE UUID = '{{ imp.project_guid }}'" },
      "register": "check" },

    { "name": "Muss genau 1 sein", "use": "assert",
      "with": { "that": "{{ check.scalar }}", "equals": "1",
                "message": "Projekt wurde nicht angelegt" } }
  ]
}
```

Das ist ein neuer Auftragstyp — „Projekt importieren und verifizieren" — und
enthält **keine Zeile neuen Client-Code.** Der Auftrags-`type` (z. B.
`kunde.projekt.einspielen`) ist nur ein Etikett fürs Protokoll und frei wählbar.

Steuerfelder je Schritt:

| Feld | Wirkung |
|---|---|
| `use` | Baustein (Pflicht) |
| `with` | Parameter, mit `{{ … }}`-Templates |
| `register` | Ergebnis unter diesem Namen für spätere Schritte merken |
| `when` | Schritt nur ausführen, wenn der Wert wahr ergibt |
| `continueOnError` | Fehler im Schritt nicht abbrechen lassen |

`{{ pfad }}` löst typerhaltend auf: steht ein Wert nur aus einem Platzhalter, wird
der echte Typ eingesetzt (Zahl bleibt Zahl); eingebettet wird als Text ersetzt.
Pfade greifen in Objekte und Listen: `{{ check.rows[0][1] }}`.

### Bausteine

```
  agent.diagnose   Umgebung: Datenbanken, Projektzahl, laufende Prozesse
  sql.query        Lesende Abfrage → Zeilen als JSON (Feld "scalar" für Einzelwerte)
  sql.script     ! Schreibendes SQL: Dry-Run, Transaktion, Schlüsselprüfung
  hsetu.bridge   ! Hottgenroth-API aufrufen — die Software importiert selbst
  project.import ! .sqproj zeilenweise importieren (alt, siehe hsetu.bridge)
  bauteile.import! Bauteile einspielen, optional mit Präfix
  http.download  ! Datei vom Server holen
  http.upload    ! Datei(en) zum Server liefern — einzeln oder alle aus einem Manifest
  file.read        Textdatei lesen
  file.write     ! Textdatei schreiben (UTF-8 mit BOM)
  file.list        Verzeichnis auflisten
  shell.run      ! Beliebigen Befehl ausführen (PowerShell/cmd)
  assert           Bedingung prüfen, sonst Abbruch
  set              Werte für spätere Schritte festhalten
  sleep            Warten

  ! = kann Daten verändern      Aktuelle Liste: hottgenroth-agent.exe --list
```

**`shell.run` ist der Baustein, der den Client endgültig erweiterungsfrei
macht** — was sich auf dem Rechner überhaupt anstoßen lässt, lässt sich damit
anstoßen, ohne den Agent neu auszurollen. Entsprechend weit reicht er: wer den
Server oder das Token kontrolliert, hat damit Codeausführung auf dem
Arbeitsplatz. Auf Rechnern, die das nicht anbieten sollen, `AllowShell` auf
`false` setzen; die übrigen zwölf Bausteine laufen weiter. Jeder `shell.run`
wird vollständig protokolliert.

## Einrichtung

### Server

```bash
php artisan migrate
```

In `.env`:

```
HOTTGENROTH_AGENT_TOKEN=<langes Zufallstoken>
HOTTGENROTH_POLL_INTERVAL=15
# lokal 'local', in Produktion 's3' (siehe unten)
HOTTGENROTH_STORAGE_DISK=local
```

Hochgeladene Dateien landen auf der konfigurierten Disk unter dem Präfix
`hottgenroth/uploads/` (bei `local` also `storage/app/hottgenroth/uploads/`, bei
`s3` im Bucket). Der Download-Endpunkt lässt nur Schlüssel unterhalb dieses
Präfixes zu (kein `..`).

### Client bauen

```powershell
cd hottgenroth-agent
.\build.ps1                     # self-contained Single-File → dist\hottgenroth-agent.exe
.\build.ps1 -FrameworkDependent # kleine EXE, setzt .NET 10 auf dem Zielrechner voraus
```

Die Vorgabe ist **self-contained**: eine einzige `hottgenroth-agent.exe` (~122 MB),
die das .NET-Runtime mitbringt und auf jedem Windows-Arbeitsplatz läuft — auch
ohne installiertes .NET. Das Ergebnis liegt in `dist\`. Seit 2.1.0 steckt darin
auch das Windows-Desktop-Framework für das Tray-Symbol; das sind die knapp 40 MB
gegenüber der Fassung davor.

Verteilen heißt: `dist\hottgenroth-agent.exe` auf den Arbeitsplatz kopieren und
daneben eine `appsettings.local.json` anlegen. Sie überschreibt
`appsettings.json` und gehört nicht ins Repository:

```json
{
  "ServerUrl": "https://fs-energieberater.de/api/hottgenroth/agent",
  "Token": "<dasselbe Token wie HOTTGENROTH_AGENT_TOKEN in .env>",
  "Name": "Arbeitsplatz Dennis",
  "AllowShell": true
}
```

Prüfen, ohne etwas zu tun:

```powershell
.\hottgenroth-agent.exe --list      # verfügbare Bausteine
.\hottgenroth-agent.exe --once      # anmelden, genau eine Aufgabe, beenden
```

Alle Schalter:

| Schalter | Wirkung |
|---|---|
| *(keiner)* | läuft im Konsolenfenster, Strg+C beendet |
| `--tray` | läuft ohne Konsolenfenster, mit Symbol im Infobereich der Taskleiste |
| `--once` | registrieren, höchstens einen Auftrag, beenden |
| `--beenden` | beendet den laufenden Agenten und wartet darauf (höchstens 60 s) |
| `--autostart` | startet ab dem nächsten Login automatisch mit `--tray`; zusammen mit `--tray` läuft er gleich los |
| `--autostart-aus` | entfernt den Autostart wieder |
| `--anmelden` / `--abmelden` | persönlichen Zugang im Browser anlegen / wegwerfen |
| `--list` / `--version` | Bausteine / Fassung ausgeben, ohne Serverkontakt |

### Das Tray-Symbol

Mit `--tray` — und damit bei jedem Autostart — sitzt der Agent als Symbol im
Infobereich. **Fehlt das Symbol, läuft kein Agent.** Sonst sagt die Farbe, was er tut:

| Farbe | Zustand |
|---|---|
| grau | startet, meldet sich an |
| grün | läuft, wartet auf Aufträge |
| blau | arbeitet an einem Auftrag |
| orange | erreicht den Server nicht, versucht es weiter |
| rot | steht — der Grund steht im Tooltip und im Menü |

Rechtsklick öffnet das Menü: Zustand und letzter Auftrag, der Server, gegen den
er läuft, **Protokoll öffnen**, **Beim Anmelden starten** und **Beenden**. Läuft
gerade ein Auftrag, fragt Beenden nach — der Auftrag wird abgebrochen und dem
Server als fehlgeschlagen gemeldet. Hört ein Schritt die Abbruchbitte nicht,
wird aus dem Menüpunkt „Sofort beenden".

Unter Windows 11 landet ein neues Symbol zunächst hinter dem Pfeil im Überlauf.
Dauerhaft sichtbar macht man es unter *Einstellungen → Personalisierung →
Taskleiste → Andere Taskleistensymbole*, oder man zieht es mit der Maus heraus.

Drei Dinge verhalten sich im Tray-Betrieb anders als früher:

- **Die Ausgabe geht ins Protokoll** `%LOCALAPPDATA%\HottgenrothAgent\agent.log`,
  jede Zeile mit Zeitstempel, ab 5 MB beim Start rotiert. Bisher startete der
  Autostart den Agenten versteckt, und jede Meldung ging verloren.
- **Bei einer Ablehnung bleibt das Symbol rot stehen**, statt zu verschwinden —
  etwa bei einem abgelaufenen Zugang oder falscher Adresse. Wer morgens
  nachsieht, soll den Grund finden und nicht nur ein fehlendes Symbol.
- **Ist beim Login das Netz noch nicht da, wartet der Agent**, statt sich zu
  beenden. Kein Netz, Zeitüberschreitung und 5xx gelten als vorübergehend;
  401, 403 und 404 nicht. Das gilt für jeden Dauerbetrieb, nicht nur für `--tray`.

Derselbe Agent läuft nur **einmal** — gemessen an `agent_key` und Server-Adresse.
Ein zweiter Start endet mit Code 3 und lässt das laufende Symbol eine Meldung
zeigen. Zwei Installationen gegen verschiedene Server dürfen nebeneinander laufen,
auch wenn sie sich das Arbeitsverzeichnis teilen.

### Auf einem Arbeitsplatz installieren

Ein Befehl, kein Admin nötig — kopiert den Agent ins Benutzerprofil,
konfiguriert ihn, richtet den Autostart beim Login ein und startet ihn gleich
mit Tray-Symbol:

```powershell
cd hottgenroth-agent
.\install.ps1 -ServerUrl "https://www.fs-energieberater.de/api/hottgenroth/agent"
```

Deinstallieren: `.\install.ps1 -Uninstall`.

**`www.` gehört in die Adresse.** Ohne es antwortet die App mit `301` auf die
www-Form, und .NET macht aus einem umgeleiteten `POST` ein `GET` — der Rumpf
wäre weg. Die mitgelieferte `appsettings.json` trägt die www-Form deshalb schon.

#### Für einen Kollegen verteilen

`build.ps1` legt neben die EXE drei Dateien, die zusammen das Paket ergeben:
`install.ps1`, **`Einrichten.cmd`** (Doppelklick-Starter mit der
Produktionsadresse) und **`Anleitung.html`** (die Anleitung für den Menschen am
Arbeitsplatz — Entpacken, SmartScreen, Browser-Anmeldung, Symbolfarben,
Fehlersuche, Deinstallation).

```powershell
.uild.ps1 -Ziel "$env:TEMP\Hottgenroth-Agent"
Compress-Archive "$env:TEMP\Hottgenroth-Agent" "$env:USERPROFILE\Downloads\Hottgenroth-Agent.zip"
```

Das ZIP geht an den Kollegen, dort entpacken und `Einrichten.cmd` doppelklicken.
`Einrichten.cmd` nimmt vorher die Download-Markierung von den Dateien
(`Unblock-File`), sonst meldet sich SmartScreen mitten in der Einrichtung.

**Smart App Control kommt zuerst.** Auf neu aufgesetzten Windows-11-Rechnern ist
der Windows-Eigenschutz an und blockiert unsignierte Programme — erst `install.ps1`
(„Eine Anwendungsrichtlinie hat diese Datei blockiert"), dann die EXE mit
„*wurde durch die Device Guard-Richtlinie Ihrer Organisation blockiert*". Die Meldung
nennt eine Unternehmensrichtlinie und meint den Eigenschutz; Adminrechte helfen nicht.
Eine Zeile beendet die Suche:

```powershell
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState
```

`1` heißt an. Abschalten unter *Windows-Sicherheit → App- und Browsersteuerung →
Intelligente App-Steuerung*, und das ist **endgültig** — zurück geht nur mit einer
Neuinstallation. Erst danach läuft `Einrichten.cmd` durch. (Gemessen am 01.10.2026;
`Win32_DeviceGuard`, die `.cip`-Liste und `citool` führen alle in die Irre, weil sie
Eigenschutz und Firmenpolitik nicht unterscheiden.)

**Vorher freischalten:** der Kollege braucht unter `/admin/users` das Recht
*„Diesen Rechner als eigenen Hottgenroth-Arbeitsplatz anmelden"*
(`hottgenroth:arbeitsplatz`) — ohne das endet die Anmeldung im Browser mit `400`.
`appsettings.local.json` wird **nicht** mitgepackt: das Paket enthält kein Token,
und der Rechner bekommt beim ersten Start einen Besitzer statt ein geteiltes
Geheimnis.

#### Anmelden im Browser — der Weg ohne Token

Statt ein Token in die Konfiguration zu kopieren, meldet sich der Rechner selbst
an. Ohne hinterlegtes Token tut der Agent das beim ersten Start von allein,
erzwingen lässt es sich mit:

```powershell
hottgenroth-agent.exe --anmelden
```

Ein Browserfenster geht auf, der Berater meldet sich an und bestätigt — danach
**gehört dieser Rechner ihm**, und über MCP sieht er seine Projekte. Der Zugang
liegt DPAPI-verschlüsselt in `%LOCALAPPDATA%\HottgenrothAgent\anmeldung.dat`;
eine kopierte Datei ist auf einem anderen Rechner oder Konto wertlos. Das
Zugangstoken erneuert sich selbst, `--abmelden` wirft es weg.

Voraussetzung ist ein einmaliger Klick durch einen Admin: unter `/admin/users`
muss der Berater das Recht **hottgenroth:arbeitsplatz** tragen, sonst bietet die
Zustimmungsseite es nicht an und die Anmeldung endet mit 400. Das ist Absicht —
die Zustimmungsseite ist kein Selbstbedienungsladen.

Der Weg über `-Token` funktioniert unverändert weiter. Ein so angemeldeter
Arbeitsplatz gehört nur niemandem und bleibt deshalb über MCP unsichtbar; die
Umstellung geschieht also Rechner für Rechner, ohne Stichtag.

**Der Agent läuft bewusst als der angemeldete Benutzer, nicht als Dienst.** Die
Hottgenroth-Datenbank `(localdb)\HSETU` ist eine benutzergebundene
LocalDB-Instanz — nur das Konto, unter dem Hottgenroth läuft, sieht sie. Ein
Windows-Dienst unter `SYSTEM` käme nicht an die Datenbank — und ein Tray-Symbol
hätte er auch nicht. Deshalb liegt der Start als Verknüpfung im Autostart-Ordner
(läuft beim Login im richtigen Konto), nicht bei `sc.exe`. Angelegt wird sie von
der EXE selbst (`--autostart`); `install.ps1` ruft nur das auf.

Die Verknüpfung startet `wscript.exe` mit `start-agent.vbs` neben der EXE, und
das VBS startet `hottgenroth-agent.exe --tray` mit Fensterstil 0. Der Umweg ist
nötig, weil der Agent ein Konsolenprogramm bleibt (sonst warteten PowerShell und
cmd nicht auf `--once`) — direkt gestartet blitzte ein Konsolenfenster auf, mit
Windows Terminal als Standard sogar ein ganzes Terminal. **Bekanntes
Verfallsdatum:** Microsoft hat VBScript abgekündigt und will es ab etwa 2027
standardmäßig abschalten. Dann braucht es einen anderen unsichtbaren Starter.

Der `agent_key` entsteht beim ersten Start und liegt in
`%LOCALAPPDATA%\HottgenrothAgent\agent-key.txt`. Er ist die Identität des
Arbeitsplatzes — wird die Datei gelöscht, erscheint der Rechner am Server als
neuer Agent.

### Voraussetzungen auf der Produktionsseite

Bevor der Projekt-Import in Produktion funktioniert, muss dort alles davon stehen:

1. **Code deployt** (`./deploy.sh` bzw. GitHub Actions) — damit Migration,
   Routen und `config/hottgenroth.php` live sind.
2. **`HOTTGENROTH_AGENT_TOKEN`** in der Produktions-`.env` gesetzt — derselbe
   Wert, der beim Agent als `-Token` eingetragen wird.
3. **`HOTTGENROTH_STORAGE_DISK=s3`** plus die AWS_*-Zugangsdaten der Object
   Storage — sonst fällt der Upload still auf die lokale (flüchtige) Platte
   zurück und der Agent-Download endet mit `404`. Werte aus dem fortrabbit-
   Dashboard („Object Storage → Access from this App"):

   ```
   HOTTGENROTH_STORAGE_DISK=s3
   AWS_ACCESS_KEY_ID=<Access Key ID>
   AWS_SECRET_ACCESS_KEY=<ssh …@deploy.<region>.frbit.com secrets OBJECT_STORAGE.SECRET>
   AWS_BUCKET=<Bucket = i. d. R. Access Key ID>
   AWS_ENDPOINT=https://objects.<region>.frbit.com
   AWS_DEFAULT_REGION=eu-west-1   # beliebig, nur nicht leer
   AWS_USE_PATH_STYLE_ENDPOINT=true
   ```

Fehlt das Token, antwortet der Server mit `500 server_misconfigured`; bei
falschem Token mit `401`. Ist die Storage-Konfiguration fehlerhaft, meldet der
Upload jetzt `500` mit Hinweis (statt still fehlzuschlagen).

Die S3-Disk braucht das Composer-Paket `league/flysystem-aws-s3-v3` (ist in
`composer.json`); der Deploy zieht es über `composer install`.

### Lokales Testsetup

Auf dem Hottgenroth-Arbeitsplatz ist kein PHP systemweit installiert. Für Tests
liegt ein portables PHP 8.4 unter `C:\Projekte_Dev\tools\php84`, Composer
daneben als `composer.phar`.

```powershell
cd hottgenroth-agent
.\lokal-test.ps1          # startet Laravel auf 127.0.0.1:8090
.\lokal-test.ps1 -Stop    # beendet es wieder
```

Das Skript gibt anschließend die passenden Befehle für Aufgabe und Agent aus.

Zwei Eigenheiten dieser Umgebung, die das Skript abfängt: `php artisan serve`
scheitert hier am Binden des Ports (der eingebaute Server direkt gestartet
funktioniert), und `bcmath` ist im Windows-Build fest eingebaut — eine
`extension=bcmath`-Zeile in der `php.ini` erzeugt nur eine Warnung.

Auf einer Windows-Shell gehen bei `--payload='{"a":1}"` regelmäßig
Anführungszeichen verloren. Dafür gibt es `--payload-file`.

## Aufgaben stellen — im Browser

Der übliche Weg. Interne Seite **Hottgenroth-Aufgaben**, erreichbar für die
Rollen `admin` und `projekte` (Menü: Admin- bzw. ERP-Dropdown):

```
/admin/hottgenroth
```

Die Seite zeigt:

- **Arbeitsplätze** mit Online-Ampel (grün = in den letzten 3 Minuten gemeldet).
- **Projekt importieren**: `.sqproj` per Datei-Upload, Zielarbeitsplatz wählen,
  Projektname und **Projektgruppe** (der Ordner, in dem das Projekt in der
  Software erscheint — sinnvollerweise die Projektreferenz) → **Importieren**.
  Unter *Verfahren* steht die Vorgabe auf „Über die Software importieren"; der
  alte zeilenweise Weg bleibt als Rückfalltür, solange nicht überall die Brücke
  ausgerollt ist. Probelauf und GUID-Neuvergabe gehören nur zu diesem alten Weg.
- **Diagnose**-Schnellaktion an den gewählten Arbeitsplatz (schreibt nichts).
- **Auftragsliste** mit Statusfarben und Fortschrittsbalken, dazu eine
  Detailansicht mit Live-Verlauf und Ergebnis. Alles aktualisiert sich alle
  5 Sekunden von selbst.

Was beim Upload passiert: die Datei landet auf der konfigurierten Disk unter
`hottgenroth/uploads/` (Produktion: fortrabbit Object Storage), und es entsteht
ein Auftrag mit genau einem Schritt —

```json
{ "steps": [ { "use": "project.import", "with": {
    "url": "files/uploads/<datei>.sqproj",
    "projectName": "…", "regenerateGuids": true, "dryRun": false,
    "database": "HsetuPrjData" }, "register": "import" } ] }
```

Der gewählte Agent pollt, lädt die Datei über den token-geschützten
`files/`-Endpunkt und importiert sie in seine LocalDB. Der Import ist an genau
diesen Arbeitsplatz gebunden, weil die Datenbank dort liegt.

Grenzen: Upload bis **128 MB** (deckungsgleich mit `post_max_size`/
`upload_max_filesize` und nginx `client_max_body_size` in der Produktion).
Größere Projekte müssten gechunkt werden. Hochgeladene Dateien bleiben in der
Object Storage liegen; ein Scheduler-Lauf (`hottgenroth:task prune`, täglich in
`routes/console.php`) löscht sie nach 7 Tagen.

Serverseitig: `app/Http/Controllers/Admin/HottgenrothTaskController.php`,
`resources/views/admin/hottgenroth.blade.php`, Routen in `routes/web.php`
(Gruppe `['auth','role:admin,projekte']`).

## Bauteilbestand einsammeln

Zweite interne Seite, **Hottgenroth-Bauteile**, gleiche Rollen:

```
/admin/hottgenroth/bauteile
```

Sie zeigt den Bestand als **Ordneransicht**, so wie die Software ihn führt:
Arbeitsplatz › Gruppe › Projekt, mit Name, Nummer, Erzeugt und Bearbeitet. Zu
einem geöffneten Projekt kommen darunter die Bauteile mit Typ, U-Wert und
vollständigem Schichtaufbau, Gefach-Abschnitte inklusive. Die Daten liegen in
`(localdb)\HSETU` auf dem Rechner; hier steht ein **Spiegel**.

Zwei Knöpfe:

- **Bauteile abrufen** (je Projekt) — stellt den Auftrag `bauteile.export`.
- **Abbild anfordern** (je Arbeitsplatz) — stellt `projekte.liste`.

Das Abbild muss man normalerweise nicht anfordern: der Server tut es von selbst,
**nach jeder Anmeldung** eines Agents und **nach jedem Import**. Steht schon ein
Abbild-Auftrag aus, kommt kein zweiter dazu — ein Agent, der beim Ausrollen
mehrfach neu startet, erzeugte sonst einen Stapel identischer Aufträge.

`projekte.liste` sind zwei lesende `sql.query`-Schritte:

```sql
-- Ordner
SELECT ... FROM XmProjectGroup
-- Inhalt: XmProject ist die Sichtbarkeitsschicht, PrProject das eigentliche Projekt
SELECT ... FROM XmProject x JOIN PrProject p ON p.GroupUUID = x.PRJGroupUUID
 WHERE p.VariantType = 2
```

Der Join geht über die **Gruppen**-UUID. `XmProject.PRJProjectUUID` und
`.ProjectUUID` sehen naheliegender aus, treffen `PrProject.UUID` aber nicht (am
09.08.2026 gegen echte Daten geprüft: null Treffer). Angezeigt wird der Name aus
`XmProject` — den sieht der Anwender in der Software; er kann von
`PrProject.LongDesc` abweichen, nach einem Brückenimport regelmäßig.

Was der Arbeitsplatz nicht mehr meldet, wird **markiert, nicht gelöscht**: am
Projekt hängen der gespiegelte Bauteilbestand und die Herkunft. Gruppen tragen
keine eigenen Daten und verschwinden. Ein abgeschnittenes Ergebnis
(Zeilengrenze erreicht) löscht und markiert **gar nichts** — dort fehlen Zeilen,
die es gibt.

**Am Agent ist für beides nichts zu ändern.** `bauteile.export` sind vier lesende
`sql.query`-Schritte (Projektkopf, Bauteile, Gefach-Abschnitte, Schichten) über
`TcBasis`/`TcBuildingElementDimension`/`…Layer`/`…LayerSection`; das Ergebnis
kommt über den regulären `complete`-Aufruf zurück. Kein neuer Baustein, kein
Rollout — der Fall aus [„Einen neuen Auftragstyp bauen"](#einen-neuen-auftragstyp-bauen),
diesmal in echt.

Vier Dinge, die der Server beim Einlesen tut und die man kennen sollte:

- **Variantenkopien werden am Namen getrennt.** Die Software legt je
  Sanierungsvariante eine vollständige Kopie jedes Bauteils an
  (`VAR Heizung: Außenwand`). Ein Projekt mit 16 Bauteilen und 5 Varianten hat
  82 Katalogzeilen; die Liste zeigt darum standardmäßig nur den Ist-Zustand.
- **Sentinel-Werte werden zu `null`.** `±987654321,99` heißt „nicht gesetzt" —
  als Zahl angezeigt wäre es ein absurder R-Wert. Nur im Spiegel; auf dem
  Arbeitsplatz bleibt der Wert unangetastet.
- **Der Spiegel wird ersetzt, nicht zusammengeführt.** Ein am Arbeitsplatz
  gelöschtes Bauteil verschwindet damit auch hier.
- **Ein `.sqproj`-Import legt seine Quelle selbst an.** Erst dadurch weiß der
  Server, welches Projekt aus welcher Datei entstanden ist.

Erreicht eine Abfrage ihre Zeilengrenze (3.000 Bauteile, 20.000 Schichten), ist
der Spiegel unvollständig und wird in der Liste als „gekürzt" markiert.

Serverseitig: `app/Services/HottgenrothBauteilSync.php` (Auftrag bauen und
Ergebnis einlesen), `app/Http/Controllers/Admin/HottgenrothBauteilController.php`,
`app/Models/HottgenrothProjekt.php`, `HottgenrothBauteil.php`,
`HottgenrothBauteilSchicht.php`, `resources/views/admin/hottgenroth-bauteile.blade.php`.

Der umgekehrte Weg — Bauteile aus einer Quelle **auswählen und in ein Projekt
kopieren** — ist als Entwurf beschrieben, aber noch nicht gebaut:
[`docs/bauteile-uebernehmen.md`](docs/bauteile-uebernehmen.md).

## Aufgaben stellen — auf der Kommandozeile

Für Automatisierung und Fortgeschrittene. Nutzlast als Datei übergeben — auf
einer Windows-Shell gehen bei `--payload='{"a":1}'` regelmäßig
Anführungszeichen verloren:

```bash
# Was ist registriert, wer ist online?
php artisan hottgenroth:task agents

# Verbindung prüfen: schreibt nichts, beweist die ganze Kette
php artisan hottgenroth:task add --type=agent.diagnose \
  --payload='{"steps":[{"use":"agent.diagnose"}]}'

# Mehrstufige Aufgabe aus einer Datei (Name frei wählbar)
php artisan hottgenroth:task add --type=kunde.projekt.einspielen \
  --payload-file=auftrag.json --agent=fslaptop1-…

# Verlauf und Ergebnis
php artisan hottgenroth:task show --id=42
php artisan hottgenroth:task list
```

Ohne `--agent` darf jeder Agent den Auftrag übernehmen. Bei allem, was die
lokale Datenbank betrifft, gehört der Arbeitsplatz dazu.

## Bausteine im Detail

### `hsetu.bridge`

Der Weg, auf dem ein Projekt so importiert wird, wie die Software es selbst tut.

```json
{ "use": "hsetu.bridge", "with": {
    "timeoutSeconds": 1500,
    "steps": [
      { "use": "new",  "type": "TFWDesktopDalHelper", "register": "helfer" },
      { "use": "call", "target": { "$ref": "helfer" }, "method": "GetDalsAndProvider",
        "args": [ { "$enum": "TFWDatabaseConfigType.dctProject" } ], "register": "ziel" }
    ] }}
```

**Warum das nötig ist.** Die Software importiert eine `.sqproj` *nicht* als
Kopiervorgang. Sie lädt die Datei in ihr Objektmodell, erzeugt dort neue Objekte
und lässt einen Serializer die Zeilen schreiben — die Zeilen sind ein Nebenprodukt
des Modells. `project.import` kopiert sie stattdessen wörtlich und reproduziert
dessen Regeln nicht. Am 09.08.2026 gemessen: gleiche Bauteile, gleiche Elemente,
gleiche Geometrie bis aufs Byte — aber fremde Varianten-Wurzeln, und in der
Software ein leeres HottCAD-Modell. Über die Brücke stimmen sie mit dem Original
überein.

Die Nutzlast wird unverändert an [`bridge/`](bridge/) durchgereicht; die
Operationen (`types`, `members`, `new`, `call`, `get`, `set`) stehen dort. Der
Baustein kennt keine Anwendungsfälle — den Ablauf stellt der Server zusammen
(`app/Services/HottgenrothBrueckenImport.php`).

Zwei Dinge dazu:

- **Die Brücke muss neben dem Agent liegen.** `build.ps1` nimmt sie mit, sofern
  sie gebaut ist; sonst baut es sie. Fehlt sie, meldet der Baustein das mit den
  durchsuchten Pfaden.
- **`AllowBridge: false`** schaltet ihn auf einem Arbeitsplatz ab. Er reicht
  ähnlich weit wie `shell.run`, nur in eine andere Richtung: über ihn lässt sich
  jede Methode der Hottgenroth-API aufrufen, auch jede schreibende.

### `project.import`

```json
{ "use": "project.import", "with": {
    "url": "files/Strackerjan.sqproj",
    "projectName": "Strackerjan (Import)",
    "regenerateGuids": true,
    "dryRun": false,
    "database": "HsetuPrjData" }}
```

Statt `url` geht auch `path`, wenn die Datei schon auf dem Rechner liegt (etwa
aus einem vorangehenden `http.download`-Schritt: `"path": "{{ datei.path }}"`).

Eine `.sqproj` ist trotz der Endung eine SQLite-Datenbank mit denselben
Tabellen und Spalten wie `HsetuPrjData` — der Import ist deshalb ein
Kopiervorgang, keine Formatumwandlung. Zwei Fallstricke sind im Code
abgefangen: die **Spaltenreihenfolge** weicht zwischen Quelle und Ziel ab
(jedes INSERT nennt seine Spalten ausdrücklich), und die **GUIDs** müssen bei
einem zweiten Import derselben Datei neu vergeben werden, sonst kollidieren die
Primärschlüssel. `regenerateGuids` bildet nach, was die Oberfläche selbst tut;
die Null-GUID `AAAAAAAA-…` bleibt dabei unangetastet, weil sie „keine Referenz"
bedeutet.

Liefert `project_guid` — direkt weiterverwendbar, etwa als Ziel für einen
folgenden `bauteile.import`-Schritt. Nach dem Import muss die Software **neu
gestartet** werden, sie liest den Projektkatalog beim Laden.

### `bauteile.import`

```json
{ "use": "bauteile.import", "with": {
    "project": "{{ imp.project_guid }}",
    "prefix": "VAR Fassade: ",
    "dryRun": false,
    "bauteile": [{
      "name": "Aussenwand WDVS 16 cm",
      "groupType": 1,
      "usageType": 2,
      "schichten": [
        { "name": "Gipsputz ohne Zuschlag", "lambda": 0.51, "dicke": 0.015,
          "dichte": 1200, "kapazitaet": 1.0, "muUnten": 10, "muOben": 35,
          "materialgruppe": 1, "katalogpfad": "1.1.6" },
        { "name": "Polystyrol PS, WLG 035", "lambda": 0.035, "dicke": 0.16,
          "dichte": 30, "kapazitaet": 1.5, "muUnten": 80, "muOben": 250,
          "materialgruppe": 5, "katalogpfad": "5.5.1.3",
          "layerType": 3, "materialType": 1 }
      ]
    }] }}
```

`project` ist eine GUID oder ein Namensfragment (das genau ein Projekt treffen
muss). `dicke` in **Metern**, Schichten von **innen nach außen**. U-Wert, R-Wert
und der Legacy-Block `ElementMeta` werden daraus berechnet — inklusive der
Umrechnung auf Zentimeter, die `ElementMeta` dort erwartet.

`groupType`: 1 Wand, 2 Tür, 3 Fenster, 4 Boden/Decke, 5 Dach.
`usageType`: 1 gegen beheizt, 2 gegen außen, 4 gegen Erdreich,
6 gegen unbeheizt (Wand), 7 Decke gegen unbeheizt, 8 Boden gegen Keller.

Der `usageType` ist nicht kosmetisch: die Software leitet daraus Rsi und Rse ab
und überschreibt abweichende Werte. Ein falscher Typ führt über falsche
Übergangswiderstände zu einem falschen U-Wert.

Statt alle Spalten von Hand zu setzen — `TcBasis` allein hat 212 — klont der
Writer eine vorhandene Bauteilzeile und überschreibt nur die fachlichen Felder.
Dadurch stimmen sämtliche Sentinel-Werte (Null-Float −987654321,99, Null-Int
−999, leeres Datum 1899-12-30) von selbst. Hintergrund in
[`bauteile/docs/hottgenroth-bauteil-sql.md`](../bauteile/docs/hottgenroth-bauteil-sql.md).

Der Baustein legt Bauteile **neu** an, aus einer Schichtliste. Bauteile, die es
schon gibt, aus einer `.sqproj` oder einem anderen Projekt zu übernehmen, ist
eine andere Aufgabe — Entwurf dazu in
[`docs/bauteile-uebernehmen.md`](docs/bauteile-uebernehmen.md) (noch nicht gebaut).

### `sql.script`

Drei Vorgaben, die greifen, solange man sie nicht ausdrücklich abschaltet:

1. **Transaktion** — alles oder nichts.
2. **Probelauf** — `dryRun` ist die Vorgabe. Ohne ausdrückliches
   `"dryRun": false` wird am Ende zurückgerollt.
3. **Schlüsselprüfung** — ein `DELETE` oder `UPDATE`, das eine Tabelle mit
   zusammengesetztem Primärschlüssel nur über einen Teil davon anspricht, wird
   abgewiesen (mit `"allowPartialKey": true` ausdrücklich zulassen).

Punkt 3 ist aus Schaden gelernt. In `BmData` und `BmPropertySet` lautet der
Schlüssel `(ReferenceUUID, UUID)`, in `PdProfileReference`
`(ReferenceToUUID, UUID)`. Die `UUID`-Hälfte ist dort **projektübergreifend
geteilt**. Ein `DELETE FROM BmData WHERE UUID IN (…)` mit 74 GUIDs eines
einzelnen Projekts löscht rund 28.000 Zeilen quer durch alle Projekte. Genau
das ist am 08.08.2026 passiert.

Zusätzlich empfohlen: `expectedRows` mitgeben. Weicht die Zahl der betroffenen
Zeilen ab, rollt der Auftrag zurück, statt den Schaden zu committen.

```json
{ "use": "sql.script", "with": {
    "sql": "DELETE FROM BmData WHERE ReferenceUUID = '…' AND UUID = '…'",
    "dryRun": false,
    "expectedRows": 1 }}
```

## Einen neuen Auftragstyp bauen

Der Regelfall: **gar kein Code.** Der Auftragstyp entsteht als Zusammenstellung
vorhandener Bausteine in `payload.steps` — geschrieben am Server, nicht am
Client. Für „Projekt importieren und verifizieren", „Software beenden, Bauteile
einspielen, neu starten", „Wartungsabfrage über alle Datenbanken" ist nichts am
Arbeitsplatz zu ändern.

Ein **neuer Baustein** ist nur nötig, wenn eine Fähigkeit fehlt, die sich nicht
aus den vorhandenen zusammensetzen lässt. Dann eine Klasse, eine Zeile in der
Registrierung:

```csharp
public sealed class MeinBaustein : IStepPrimitive
{
    public string Name => "mein.baustein";
    public string Description => "Was der Baustein tut";
    public bool Writes => false;   // true, wenn er Daten verändern kann

    public async Task<JsonNode?> ExecuteAsync(StepContext ctx, CancellationToken ct)
    {
        var wert = ctx.Require("parameter");
        await ctx.ReportAsync("Zwischenstand …", 50, ct: ct);
        return new JsonObject { ["ergebnis"] = wert };
    }
}
```

Danach in `Program.BaueBausteine()` eintragen. Der Baustein steht damit allen
Aufträgen zur Verfügung und taucht in `--list` auf. Weil jeder Agent `*` als
Fähigkeit meldet, ist ein Rollout in Etappen unkritisch: ein Auftrag, der einen
noch nicht ausgerollten Baustein nutzt, scheitert auf einem alten Agent sauber
mit „Unbekannter Baustein" und wird nicht als erledigt verbucht.

## Sicherheit

Ein Client, der jeden Auftrag ausführt, verlagert die Verantwortung auf Server
und Token. Wer beides kontrolliert, kann auf dem Arbeitsplatz beliebigen Code
ausführen (`shell.run`). Die folgenden Grenzen bleiben trotzdem bestehen:

- **Token** in `.env` und `appsettings.local.json`, Vergleich über `hash_equals`.
- **`shell.run` ist abschaltbar** — `AllowShell: false` in der
  `appsettings.local.json` eines Arbeitsplatzes nimmt den weitreichendsten
  Baustein heraus, ohne die übrigen zu verlieren.
- **Datenbank-Freigabeliste**: `AllowedDatabases` begrenzt, welche Datenbanken
  ein Auftrag überhaupt anfassen kann.
- **Schreibschutz per Vorgabe**: `sql.script` läuft ohne `"dryRun": false` als
  Probelauf, und die Schlüsselprüfung ist als Vorgabe aktiv. Beides lässt sich
  pro Auftrag aufheben — aber nur ausdrücklich, nicht versehentlich.
- **`sql.query` ist ausschließlich lesend** — Kommentare werden vor der Prüfung
  entfernt, damit sich kein `DELETE` hinter `/* … */` verstecken lässt.
- **Vollständiges Protokoll**: jeder Schritt und jeder `shell.run` landet als
  Event am Auftrag. Was einen Rechner verändert hat, ist nachvollziehbar.
- **Zuständigkeit**: einen Auftrag darf nur der Agent abschließen, der ihn
  übernommen hat.
- **Pfadprüfung** beim Download: erst auflösen, dann gegen die Ablage
  vergleichen, damit weder `..` noch Symlinks herausführen.

## Betrieb

Verwaiste Aufträge — Agent hat übernommen, ist dann abgestürzt — stellt der
Scheduler alle fünf Minuten zurück (`hottgenroth:task reclaim`, eingetragen in
`routes/console.php`). Die Frist steht pro Auftrag in `timeout_seconds`,
Vorgabe 30 Minuten.

**Läuft die Software, während geschrieben wird?** `agent.diagnose` meldet das
unter `projektsoftware_laeuft` (`software_laeuft` bleibt als zweiter Name
daneben stehen). Neue Zeilen (`INSERT`) überstehen den laufenden Betrieb,
`UPDATE`s dagegen nicht zuverlässig: die Software hält geöffnete Datensätze im
Speicher und schreibt ihren Stand zurück. Vor schreibenden Aufträgen also
schließen — ein `assert` auf `projektsoftware_laeuft` gehört an den Anfang jedes
Auftrags, der `UPDATE`s macht.

Daneben stehen `projektsoftware` (je Prozess `name`, `pid`, `fenster`, `seit`,
`verwaist`) und `hintergrunddienste`. Die Trennung ist der Punkt: `HsetuServices`
und `Hsetu.Update.Check` laufen ständig und halten kein Projektmodell — sie
mitzuzählen hieß, die Antwort war praktisch immer „ja“. Umgekehrt kannte die
Liste bis zum 19.09.2026 weder `EEBerater` noch `HottCAD`, die beiden
Anwendungen, um die es geht.

`verwaist` (kein Fenster) ist der Fall, den ein Mensch nicht sehen kann: er hält
den Prozess für beendet, und das Projekt hängt trotzdem. Einzige Ausnahme ist
`Building3D`, der 3D-Kern von HottCAD — der hat nie eines.

## Aufbau

```
src/HottgenrothAgent/
  Program.cs                     Poll-Schleife, Bausteinregistrierung, steps-Erkennung
  AgentOptions.cs                Konfiguration, agent_key, Datenbank-Freigabe, AllowShell
  AgentZustand.cs                was der Agent gerade tut — geschrieben von der Schleife, gelesen vom Symbol
  ServerClient.cs                register / claim / progress / complete / fail
  Tray/
    TrayAnzeige.cs               Symbol, Menü, Farben; eigener STA-Thread
    Einzelinstanz.cs             ein Agent je agent_key + Server; Signale "zeigen" und "beenden"
    Autostart.cs                 Verknüpfung + start-agent.vbs im Autostart-Ordner
    Protokoll.cs                 Konsolenausgabe → agent.log; Lösen vom Konsolenfenster
  Steps/
    IStepPrimitive.cs            Baustein-Vertrag
    StepContext.cs               aufgelöste Parameter, Fortschrittskanal, Auftragsnummer
    StepEngine.cs                Schrittfolge, Variablen, {{ }}-Templating, when
    Primitives/
      ShellRunPrimitive.cs       shell.run
      SqlPrimitives.cs           sql.query, sql.script
      HottgenrothPrimitives.cs   project.import, bauteile.import
      FilePrimitives.cs          http.download, http.upload, file.read/write/list
      HsetuBridgePrimitive.cs    hsetu.bridge — ruft bridge\hsetu-bridge.exe auf
      UtilityPrimitives.cs       agent.diagnose, assert, set, sleep
bridge/                          Brücke zur Hottgenroth-API (.NET Framework 4.8)
  HsetuBridge.cs                 reflexionsgesteuert, kennt keine Anwendungsfälle
  build.ps1                      csc.exe aus dem Framework, kein SDK nötig
  Hottgenroth/
    SqprojReader.cs              .sqproj (SQLite) lesen
    ProjectImporter.cs           Projekt schreiben, GUID-Neuvergabe
    BauteilWriter.cs             Bauteile anlegen, ElementMeta erzeugen
    SchemaCatalog.cs             Spaltentypen und echte Primärschlüssel
```

Serverseitig unverändert generisch — er kennt die Bausteine nicht, er stellt nur
`steps` zu: `app/Http/Controllers/Api/HottgenrothAgentController.php`,
`app/Models/Hottgenroth*.php`, `app/Console/Commands/HottgenrothTask.php`,
`config/hottgenroth.php`, Routen am Ende von `routes/api.php`.
