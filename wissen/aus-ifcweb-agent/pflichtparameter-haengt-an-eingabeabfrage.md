---
name: pflichtparameter-haengt-an-eingabeabfrage
description: "Fehlt einem PowerShell-Werkzeug eine [Parameter(Mandatory)]-Angabe, hängt der Aufruf über die Brücke bis zur Abbruchgrenze statt zu scheitern — beobachtet an wohngebaeude_pruefen/Test0001, Ursache war der weggelassene -Beheizt"
metadata:
  type: project
  stand: geschlossen
---

`wohngebaeude_pruefen` kann ohne Ergebnis in die 600-Sekunden-Abbruchgrenze laufen. Beobachtet an Test0001 — 3 Zonen, 0 Räume, 8 Bauteile, kein Anlagenmodell.

**Die Ursache ist nicht die leere Raummenge, sondern der fehlende Parameter `-Beheizt`.** `Test-Wohngebaeude.ps1` deklariert ihn als `[Parameter(Mandatory = $true)][string[]]$Beheizt`, `katalog.json` führte ihn als `"pflicht": false`. Der Agent ließ ihn deshalb weg. PowerShell fällt bei einer fehlenden Pflichtangabe in die interaktive Eingabeabfrage und wartet auf stdin — eine Pipe, auf die die Werkzeugbrücke nie schreibt. Das Werkzeug rechnet nicht zehn Minuten, es wartet zehn Minuten.

Derselbe Aufruf mit `-Beheizt EG` antwortet in 758 ms mit drei brauchbaren Fehlern. Der Hänger hängt nur an der Brücke: mit geschlossenem stdin bricht der Aufruf sofort mit `MissingMandatoryParameter` ab.

**Allgemeine Regel:** Weicht `katalog.json` beim Feld `pflicht` vom `[Parameter(Mandatory)]` des Skripts ab, entsteht ein Hänger, kein Fehler. Die Abweichung ist von außen unsichtbar — sie zeigt sich erst als Zeitgrenze ohne Meldung.

**Nachtrag, 21.08.2026 — behoben:** `katalog.json` führt `Beheizt` bei `wohngebaeude_pruefen` und `wohngebaeude_einrichten` jetzt als `"pflicht": true`, und die Brücke ruft PowerShell mit `-NonInteractive` auf (`src/werkzeuge.ts:94`, `src/pruefstand.ts:77`). Eine fehlende Pflichtangabe gibt damit sofort einen Fehler statt eines Hängers.

**Beleg:** 21.08.2026, `wohngebaeude_pruefen -Projekt Test0001` ohne `-Beheizt`: Rückgabe „ABBRUCH: Das Werkzeug lief länger als 600 s." Derselbe Aufruf mit `-Beheizt EG`: 758 ms, drei Invariantenfehler. Gegenprobe mit geschlossenem stdin: sofortiger Abbruch mit `MissingMandatoryParameter`. Parameterblock `Test-Wohngebaeude.ps1` Zeile 15: `[Parameter(Mandatory = $true)][string[]]$Beheizt`. Projektzählwerte per `SELECT COUNT(*) FROM BmZone/BmRoom/BmElement` in unter einer Sekunde: 3 Zonen, 0 Räume, 8 Bauteile.

**Nicht gemessen:** Die allgemeine Regel ist geschlossen, nicht ausgezählt — gemessen ist der eine Fall `Beheizt` an `wohngebaeude_pruefen`. Dass jede andere Katalog/Skript-Abweichung bei `pflicht` denselben Hänger erzeugt, folgt aus der PowerShell-Parameterbindung, ist aber nicht Werkzeug für Werkzeug nachgestellt. Ebenfalls nicht gemessen: dass es im Katalog derzeit keine weitere solche Abweichung mehr gibt.

**Why:** Ein Werkzeug, das in eine Zeitgrenze läuft, sieht aus wie ein hängendes System oder ein kaputtes Projekt und kostet in einem unbeaufsichtigten Lauf zehn Minuten für nichts. Die naheliegende Fehldeutung — „das Projekt ist zu leer zum Prüfen" — führt dazu, dass Prüfungen übersprungen werden, die in Wahrheit in unter einer Sekunde geantwortet hätten.

**How to apply:** Läuft ein PowerShell-Werkzeug in die Abbruchgrenze, ohne etwas auszugeben: zuerst den Parameterblock des Skripts gegen den Katalogeintrag halten und jede `Mandatory`-Angabe mitgeben, statt die Projektdaten zu verdächtigen. `-Beheizt` bei `wohngebaeude_pruefen` und `wohngebaeude_einrichten` immer setzen, `-Unbeheizt` ebenso. Bei neuen oder geänderten Werkzeugen `pflicht` in `katalog.json` und `[Parameter(Mandatory)]` im Skript gemeinsam pflegen.
