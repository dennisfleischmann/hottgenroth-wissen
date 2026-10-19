---
name: isfp2-dekompiliert
description: "MeinSanierungsfahrplan 2.6.1.1 ist zerlegt — Ausgabeschicht im Original, 87 Klassen, alle Prüfmeldungen; nur der Maschinencode fehlt"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 32fdc294-1833-481e-a848-ce79a2baf48b
  modified: 2026-09-12T04:59:15.912Z
---

Korpus unter **`C:\Projekte_Dev\isfp2-decompiled`** (außerhalb des Repos, wie
[[hsetu-dekompilierter-korpus]]). Quelle: `MeinSanierungsfahrplan.exe` 2.6.1.1,
PE32/x86, **nativ C++ mit Qt 5** — ILSpy hilft hier nicht.

- `ressourcen/` — 160 Dateien im Original. Die App rendert den iSFP als **HTML in
  einer eingebetteten WebEngine**: 42 Seitenvorlagen (`validierung.html`,
  `sanierungsfahrplan_fahrplan.html`, …), dazu `konnektor.js`, `enums.js`,
  `validierung.js`, `layout.css`.
- `klassen.h` — 87 Klassen aus den Qt-Meta-Object-Daten, exakt, nicht geraten.
  Namensraum `iSFP::` spiegelt die XSD. Jedes Fachfeld trägt seine Prüfregeln als
  Nachbareigenschaften: `<feld>_minLength`, `_maxLength`, `_hint`, `_aliasName`.
- `pruefmeldungen.txt` / `meldungen.txt` / `texte-im-code.txt` — alle Meldungen als
  Klartext mit Platzhaltern und Adresse.
- `werkzeuge/` — sechs C#-Skripte, laufen mit `dotnet run` ohne Installation.

**Das Schema liegt in der EXE, nicht daneben.** Eingebettet 180.731 Bytes gegen
151.633 Bytes der `TiSFPProjekt.xsd` auf der Platte (2022). Nur die eingebettete kennt
`JAZ`, `H_T`, `ETA_s35/s55`, `HT_spez_bestand`, `A_huelle`, `ANGF` — korrigiert
[[isfp-export-pruefen]].

**Nicht dekompiliert:** 2,8 MB x86-Maschinencode. Kein Ghidra, keine JRE auf der
Maschine. Rechenwege (etwa wie die 1290-Zeichen-Gesamtlänge aufsummiert wird) sind so
nicht lesbar.

**Why:** Prüfmeldungen ließen sich bisher nur mit `grep -a` aus der EXE deuten. Jetzt
steht neben der Meldung auch das Feld, seine Länge und die Seite, die es anzeigt —
[[isfp-regenerativ-haekchen]] wäre damit in Minuten statt Stunden belegt gewesen.

**How to apply:** Erst `klassen.h` nach dem Feldnamen durchsuchen, dann
`pruefmeldungen.txt`, dann die Seite in `ressourcen/templates/pages/`. Beim Nachbauen an
anderen Qt-Programmen zwei Fallen: `qRegisterResourceData` wird über einen Thunk
gerufen (`E8` → `FF 25`, nicht `FF 15`), und `QByteArrayData.offset` zählt ab
Satzanfang. Falsche Schrittweiten liefern Wortsalat statt Fehler —
[[wirkungsprobe-statt-selbstpruefung]] gilt auch hier: Ergebnis gegen einen bekannten
Namen prüfen.
