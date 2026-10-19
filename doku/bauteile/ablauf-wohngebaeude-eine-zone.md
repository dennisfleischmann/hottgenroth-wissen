# Ablauf: Wohngebäude als Einzonenmodell herstellen

Handlungsanweisung, nicht Datenmodell — das steht in
[`hottgenroth-raum-zone-sql.md`](hottgenroth-raum-zone-sql.md). Hier steht, was
man **tut**, in welcher Reihenfolge, und woran man merkt, dass es falsch läuft.

Gilt für Wohngebäude nach dem Schema: **eine** DIN-18599-Zone, Nutzungsprofil
„42 - Wohnung Einfamilienhaus", jeder Raum entweder **beheizt** oder
**unbeheizt** — keine dritte Stufe.

---

## Der ganze Ablauf ist ein Aufruf

```powershell
cd C:\Projekte_Dev\energieberatung\bauteile\tools

# immer zuerst trocken
.\Setup-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller -Probelauf

# dann echt
.\Setup-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller
```

Das Skript tut sechs Dinge und prüft sich am Ende selbst:

| # | Schritt | wird übersprungen, wenn |
|---|---|---|
| 0 | Vorbedingungen | — bricht ab, statt zu übergehen |
| 1 | Sicherung der Datenbank | `-Probelauf` oder `-OhneSicherung` |
| 2 | DIN-18599-Zone anlegen | schon eine vorhanden (`InfoDesc` wird dann nachgetragen) |
| 3 | Nutzungsprofil anhängen | schon eines an der Zone |
| 4 | Raumstempel setzen | — |
| 5 | Räume der Zone zuordnen | im Probelauf, falls die Zone erst entstehen müsste |
| 6 | Invarianten prüfen | — |

Abweichende Vorgaben:
`-Raumart 0` lässt die Raumarten stehen und setzt nur den Heizstatus ·
`-Name "Zimmer"` ändert den Basisnamen ·
`-Profil "43 - Wohnung Mehrfamilienhaus" -ProfileUsageType 35` für ein MFH.

> **`ProfileUsageType` ist nicht die Zahl im Profilnamen.** 42 → **34**,
> 43 → **35**. Wer 42 einträgt, bekommt „36 Labor". Die Tabelle steht in
> [`hottgenroth-raum-zone-sql.md`, Abschnitt 6](hottgenroth-raum-zone-sql.md).

---

## Vorbedingungen — was erfüllt sein muss

**1. Keine Hottgenroth-Anwendung offen.** Sie schreibt ihr Modell beim Beenden
zurück und verwirft jede Änderung von außen, ohne Meldung. Der Prozess heißt
nicht immer `Energie` — der EE-Berater läuft als **`EEBerater`**.
`Assert-SoftwareZu` prüft sieben Namen und nennt Fenstertitel und Startzeit.

**2. Die Räume sind gezeichnet.** Das Skript kann keine anlegen: Polygon und die
Verweise auf die umschließenden Bauteile rechnet HottCAD aus der Zeichnung. Ohne
Räume bricht es ab.

**3. Jedes Geschoss mit Räumen ist zugeteilt.** Steht ein Geschoss in keiner der
beiden Listen, bricht es ab — das ist Absicht. Ein vergessenes Geschoss wäre
sonst ein stiller Fehler in der Bilanz.

**4. Der EE-Berater wurde einmal benutzt.** Sonst gibt es keine Zonenkennung
`P0Zone_n[HASH8]` zu lesen, und `InfoDesc` bleibt leer. Das Skript läuft trotzdem
durch und warnt.

**5. Eine Zone als Vorlage existiert.** Beim Anlegen wird eine vorhandene
`BmZone` des Projekts kopiert, damit `BIMUUID`, `ParentUUID` und alle Sentinels
von selbst stimmen. Die Software legt beim ersten Öffnen drei Brandschutzzonen
an — hat ein Projekt gar keine, einmal öffnen und speichern.

---

## Was am Ende gelten muss

`Test-Wohngebaeude.ps1` prüft es und ist jederzeit gefahrlos aufrufbar, auch bei
laufender Software:

```powershell
.\Test-Wohngebaeude.ps1 -Projekt "Pohlstra" -Beheizt EG,DG1,DG2 -Unbeheizt Keller
```

21 Aussagen in fünf Gruppen. Die wichtigsten:

- **genau eine** Zone mit `ZoneType 5`, am Gebäude, `HeatingType 1`, mit `BmZoneData`
- **genau ein** Nutzungsprofil an der Zone, `StandardType 2`, mit `PdProfile` und `PdProfileUsage`
- `BmRoom.HeatingType` **und** `heating_type` im CAD-XML stimmen bei jedem Raum überein
- beheizte Räume in der Zone, unbeheizte nicht, keiner in mehr als einer
- keine Waisen, und `RepositoryType 1` ist vorhanden

Der Rückgabewert ist die Fehlerzahl — in einem Skript verwendbar.

**Danach die Wirkungsprobe in der Software.** Zahlen in der Datenbank beweisen
nur, dass die Zeilen stehen. Zu prüfen: erscheinen die Stempel im Grundriss,
zeigt die Zone die richtige Anzahl Räume, und **rechnet sie ihre Fläche nach**?
Solange die Zonenfläche auf dem Sentinel `-987654321,99` steht, hat die Software
die Zuordnungen gelesen, aber nicht verrechnet.

---

## Wenn etwas schiefgeht

**Ein Projekt zurückholen**, ohne die anderen anzufassen:

```powershell
# Sicherung als Seitendatenbank einspielen, dann nur dieses Projekt kopieren
sqlcmd -S "(localdb)\HSETU" -E -Q "RESTORE DATABASE HsetuPrjProbe FROM DISK='…\x.bak' WITH MOVE 'HsetuPrjData.data' TO '…\Probe.mdf', MOVE 'HsetuPrjData.log' TO '…\Probe_log.ldf', REPLACE"
.\Restore-Projekt.ps1 -Projekt "Pohlstra" -Quelle HsetuPrjProbe -Probelauf
```

Ein Voll-Restore von `HsetuPrjData` wäre falsch — er setzt **alle** Projekte
zurück, in dieser Datenbank über 40.

| Befund | Ursache |
|---|---|
| „Eine Hottgenroth-Anwendung ist offen" | zu schließen; auch ein Fenster ohne Titel kann ein laufender Prozess sein |
| „Das Projekt hat keine Raeume" | in HottCAD zeichnen — das kann kein Skript |
| „Diese Geschosse haben Raeume, sind aber nicht zugeteilt" | Geschoss in `-Beheizt` oder `-Unbeheizt` ergänzen |
| „Raumart N ist im Katalog nicht enthalten" | die `mrt*`-Bezeichnung ist unbekannt; nicht erfinden, andere Raumart wählen oder `-Raumart 0` |
| „Zone nicht eindeutig: 0 Treffer" | im Probelauf normal, wenn die Zone erst entstehen müsste |
| `[warn] BmZone.InfoDesc = Zonenkennung` | Naht zum EE-Berater fehlt — kommt vor (bei *Werner Grotz* gemessen), die 18599-Rechnung sieht die Zone dann nicht |
| `[warn] jeder Raum hat ein CAD-XML` | ältere Projekte haben keines; der Stempel steht dann nur in `BmRoom` |

---

## Grenzen

Was dieser Ablauf **nicht** leistet:

- **~~Räume anlegen.~~ Widerlegt am 20.08.2026.** Hier stand jahrelang, ein
  Raum trage Verweise auf die ihn begrenzenden Bauteile und die rechne HottCAD
  aus geometrischer Nachbarschaft, also sei er nicht von außen anzulegen. Der
  Schluss war falsch herum: **weil** die Software sie rechnet, muss man sie
  nicht liefern. Beleg: *Wohnraum 21 / DG2-R1* in Pohlstraße, am 17.08. um
  04:01 von außen geschrieben (nur `BmRoom`, `BmRoomData`, Zeichnung), die
  vierzehn Verweise ergänzte HottCAD um 11:01 beim Öffnen selbst.
- **Eine zweite Zone.** Der `[HASH8]` in `P0Zone_n[…]` ist nicht nachbildbar. Bei
  einem Wohngebäude braucht es nur eine, deren Kennung im EE-Berater schon steht.
- **Den Übertrag in die `eberater.zip`.** Zone, Profil und Zuordnung bleiben im
  Gebäudemodell; was den Übertrag auslöst, ist ungeklärt.
- **`PmSpace` erzeugen.** Die Anlagenseite entsteht durch einen Schritt, der
  nicht isoliert werden konnte.

---

## Erprobungsstand

| Projekt | wie geprüft |
|---|---|
| *Pohlstraße 133* | vollständig **geschrieben**: Zone, Profil, 21 Stempel, 21 Zuordnungen; nach einem Totalverlust 1265 Zeilen zurückgeholt; Invarianten grün |
| *Werner Grotz* | trocken; deckte auf, dass `InfoDesc` leer sein kann und dass ein Projekt **zwei** eberater-Container führen kann |
| *88011-24 Murat Sen* | trocken; Pfad „Zone existiert noch nicht", Räume ohne CAD-XML |

**In fremde Projekte wurde noch nicht geschrieben** — nur trocken gerechnet. Der
erste echte Lauf auf einem weiteren Projekt gehört Schritt für Schritt begleitet.
