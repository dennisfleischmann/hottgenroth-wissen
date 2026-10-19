---
name: isfp-druckapplikation-fernsteuern
description: "MeinSanierungsfahrplan.exe erzeugt die PDFs im Stapelbetrieb (--infile/--create-pdf/--outfile-sfp/--outfile-uh/--logfile), lässt die Eingabedatei unverändert und protokolliert selbst, was fehlt"
metadata: 
  node_type: memory
  type: reference
  originSessionId: a9df26c4-f679-4aee-bc74-1016fcac6cb2
  modified: 2026-09-27T08:35:09.358Z
---

Die Druckapplikation braucht keinen Menschen:

```
MeinSanierungsfahrplan.exe
  --infile <projekt.mSFPprojekt>   --create-pdf | --preview
  --outfile-sfp <isfp.pdf>         --outfile-uh <umsetzungshilfe.pdf>
  --logfile <lauf.log>             --disable-gpu
```

Am 27.09.2026 gemessen: **28,8 s, Exitcode 0**, iSFP 17 Seiten / 2,2 MB,
Umsetzungshilfe 43 Seiten / 2,4 MB. `--disable-gpu` ist auf einem Dienstkonto
ohne Sitzung nötig.

**Der Stapelbetrieb verändert die Eingabedatei nicht** — sie war danach
byte-gleich. Das ist der Unterschied zum Öffnen von Hand: dort hält die
Anwendung die Datei und schreibt sie beim Schließen zurück, wobei sie jedes
Bild auf rund 300 px herunterrechnet ([[druckanwendung-fliesst-nicht-zurueck]]).

**`--logfile` ist der maßgebliche Prüfbericht.** Ist er leer, ist nichts zu
beanstanden. Ist etwas offen, erzeugt die Anwendung **gar keine PDF** und
schreibt stattdessen Zeilen wie „Das Element 'Titelbild' ist nicht vorhanden."
oder „Der Wert im Feld 'Bildbeschreibung' … ist zu kurz."

**Why:** Vorher gab es keinen belastbaren Maßstab dafür, wann ein Fahrplan
fertig ist — nur Beobachtungen aus Fehlversuchen.

**How to apply:** `hottgenroth-agent/tools/Print-Isfp.ps1` holt den Stand aus
`PrMedia`, druckt und legt `druck.json` mit Zustand, Exitcode, Dauer, Dateien
und dem Protokoll ab.

Vorhersagen lässt sich das Ergebnis mit `App\Services\IsfpVollstaendigkeit`:
der Dienst liest `resources/isfp/schema.json` (aus dem in der EXE steckenden
`iSFPProjekt.xsd`, 134 Pfade / 56 Pflichtfelder) und meldet dieselben Lücken.
Am 27.09.2026 gegengeprüft — **16 Warnungen der Anwendung, 16 Mängel im
Dienst**, und bei der fertigen Datei beide null. Zwei Prüfungen stehen nicht im
Schema und mussten aus dem Protokoll ergänzt werden: `Unterschrift` und
`Titelbild` müssen als Bild vorhanden sein.

Eine Falle im Schema: eine Sanierungskomponente führt drei Ausführungsplätze.
Leere sind nur dann ein Mangel, wenn der zugehörige Platz in
`ausFuehrungKurzbeschreibung` belegt ist — ohne diese Ausnahme meldet ein
fertiger Fahrplan 26 Lücken, die keine sind.
