---
name: mcp-listenparameter-nicht-getrennt
description: "Kommagetrennte Geschosslisten kamen bei den PowerShell-Werkzeugen als EIN String an; Fehlermeldung widersprach sich selbst — seit 21.08.2026 trennen die Skripte selbst"
metadata:
  type: project
  stand: gemessen
---

Die Werkzeugbrücke reicht einen kommagetrennten String an [string[]]-Parameter der PowerShell-Skripte durch, OHNE ihn am Komma aufzutrennen. Aus "EG,DG" wird ein einelementiges Array mit dem Wert "EG,DG" statt zwei Elementen. Das liegt am Aufrufweg: `powershell.exe -File` übergibt jedes Argument als einen Wert. Keine der drei Übergabeformen hilft — weder Komma noch Doppelpunkt noch getrennte Argumente trennen die Liste. In der PowerShell-Shell selbst tritt das nicht auf, weil dort `-Beheizt EG,DG` vom Parser als Array-Literal gelesen wird — die Beispiele im Gedächtnis und in den Skriptköpfen sind deshalb irreführend, sie gelten nur für den Shell-Aufruf.

Betroffen waren genau 2 von 23 Werkzeugen im Katalog: `wohngebaeude_pruefen` und `wohngebaeude_einrichten` (Parameter `Beheizt`, `Unbeheizt`). Nur diese beiden führen Listenparameter. Erschwerend: die Parameterbeschreibung im Katalog forderte selbst genau den kaputten String an ("z. B. EG,DG1,DG2").

Die Fehlermeldung ist selbstwidersprüchlich und führt in die Irre: "Diese Geschosse gibt es nicht: EG,DG. Vorhanden: EG, DG." Wer sie wörtlich nimmt, sucht den Fehler in BmFloor — dort stehen die Namen aber exakt richtig.

**Es gab keinen Behelf.** Der naheliegende Ausweg "je Aufruf nur EINEN Geschossnamen" trägt nicht: er funktioniert allein an einem Projekt ohne Räume (wie Test0001, 0 Räume). Sobald ein nicht genanntes Geschoss Räume führt, bricht `Setup-Wohngebaeude.ps1` an der Prüfung "Diese Geschosse haben Raeume, sind aber nicht zugeteilt" ab (damals Zeile 95). Mehrgeschossmodelle waren über die Brücke also schlicht unbenutzbar.

**Nachtrag 21.08.2026 — behoben.** `Test-Wohngebaeude.ps1` und `Setup-Wohngebaeude.ps1` trennen den String jetzt selbst: eine Funktion `Trenne` splittet am Komma, trimmt und wirft Leereinträge weg (`$Werte | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }`). Sie ist idempotent — ein bereits getrenntes Array aus der Shell geht unverändert durch —, damit wirken beide Aufrufwege gleich. Die Parameterbeschreibungen im Katalog wurden mitgeändert: sie verlangen jetzt ausdrücklich "mehrere durch Komma getrennt in EINEM String". Commit im `bauteile/`-Repo: 73b93d8 "Listen selbst trennen".

**Beleg:** 21.08. an Test0001: `wohngebaeude_einrichten -Beheizt "EG,DG" -Probelauf` bricht ab mit "Diese Geschosse gibt es nicht: EG,DG. Vorhanden: EG, DG." Derselbe Aufruf mit `-Beheizt "EG"` passiert die Geschossprüfung und scheitert erst an der nächsten Vorbedingung (keine Räume). `wohngebaeude_pruefen -Beheizt "EG,DG"` meldet ebenso "[FEHL] alle genannten Geschosse existieren / unbekannt: EG,DG". `Setup-Wohngebaeude.ps1` deklarierte `[string[]]$Beheizt` und prüfte `$alle -notcontains $_`; die Ausgabe "unbekannt: EG,DG" ohne Leerzeichen nach dem Komma (gegen "EG, DG" bei `$alle -join ', '`) beweist ein einziges Listenelement. Nachgeprüft am Bestand: `katalog.json` führt 23 Werkzeuge, genau zwei davon mit Listenparameter. Die Behebung steht in beiden Skripten als `function Trenne` (Setup Zeilen 59–63, Test Zeilen 36–40).

**Nicht gemessen:** nichts Handlungsleitendes — die 23/2 sind am Katalog ausgezählt, die drei Übergabeformen einzeln durchprobiert, die Behebung im Quelltext beider Skripte nachgesehen. Geschlossen ist allein die Aussage, dass der Behelf auch an einem Projekt MIT Räumen scheitern würde: das ergibt sich aus der Prüfung "Geschosse mit Raeumen, nicht zugeteilt" im Quelltext, ist aber nicht an einem solchen Projekt vorgeführt worden.

**Why:** Die Meldung zeigt auf die Daten, obwohl die Daten stimmen. Ohne diesen Eintrag sucht die nächste Sitzung im Geschossbestand nach einem Fehler, der dort nicht ist, oder hält die Geschosse fälschlich für kaputt und legt sie neu an. Und der Eintrag hält fest, dass die Trennung jetzt im Skript sitzt, nicht in der Brücke — wer die Skripte kopiert oder ein drittes Werkzeug mit Listenparameter baut, muss `Trenne` mitnehmen.

**How to apply:** Bei "Geschoss gibt es nicht", obwohl `projekt_lesen` es zeigt: zuerst mit einem einzelnen Namen gegenprüfen, statt die Daten zu verdächtigen — dann liegt es am Trennen, nicht am Bestand. Neue Werkzeuge mit Listenparameter: die Trennung ins Skript legen (`Trenne` aus `Setup-Wohngebaeude.ps1` übernehmen), nicht auf die Brücke hoffen; die Funktion ist idempotent und darf auch dort stehen, wo der Shell-Parser schon getrennt hat. Katalogbeschreibungen von Listenparametern immer so formulieren, dass sie den EINEN String verlangen, den die Brücke tatsächlich liefert.
