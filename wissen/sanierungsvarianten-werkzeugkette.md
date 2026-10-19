---
name: sanierungsvarianten-werkzeugkette
description: "Fünf Skripte bauen ein Maßnahmenpaket von außen — container.ps1, variante-bauen, setze-massnahme, uwerte-uebernehmen, pruefe-variante; uwerte-uebernehmen ist der Schritt, den man vergisst"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-12T13:52:12.744Z
---

Ein Maßnahmenpaket lässt sich vollständig von außen bauen. Die Kette steht in
`C:\Projekte_Dev\hsetu-decompiled\werkzeuge\bdexit\`:

```powershell
.\container.ps1        -Projekt 'Name' -Ordner .\arbeit          # holen + sichern + entpacken
.\variante-bauen.ps1   -Ordner .\arbeit -VonProj 2 -Name 'Dach, PV'
.\setze-massnahme.ps1  -Ordner .\arbeit -Proj 17 ...             # Ziel-U + Kosten
.\uwerte-uebernehmen.ps1 -Ordner .\arbeit -Proj 17               # ← NICHT vergessen
.\zeige-massnahmen.ps1 -Ordner .\arbeit                          # Gegenprobe
.\container.ps1        -Projekt 'Name' -Ordner .\arbeit -Zurueck
```

**`uwerte-uebernehmen.ps1` ist der Schritt, der stillschweigend fehlt.**
`setze-massnahme.ps1` setzt `SANK_ZAHL` — den **angezeigten** sanierten U-Wert.
Gerechnet wird aus `TableZusatz.Kernel18599V5`, und der wird beim Anlegen einer
Variante unverändert mitkopiert. Ohne diesen Schritt **zeigt** die Variante
sanierte Werte und **rechnet** mit den alten. Das fällt nirgends auf.

**`Select-Object -First N` auf diese Skripte bricht die Pipeline ab** und lässt
eine halb gebaute Variante zurück (`PROJ_ID 4 hat keine Bauteile`). Sie geben
fortlaufend aus; mit `Tee-Object` in eine Datei schreiben und danach filtern,
nie im Lauf verkürzen. Der Arbeitsordner ist dann nur noch zu verwerfen — neu
holen und neu bauen. Die zweite Schalterfalle:
[[container-vorschau-braucht-zurueck]].

**Was die drei Prüfungen nicht abdecken: die Verknüpfung.** `VarianteID` muss
auf den Ist-Zustand zeigen, sonst sind die Varianten rechnerisch einwandfrei und
in der Software trotzdem unbrauchbar — [[varianteid-verweist-auf-ist-zustand]].
Nach dem Bauen also zusätzlich `VarianteID` je Satz ansehen.

`container.ps1` trägt die vier Regeln, an die man sonst einzeln denken muss:
Energie.exe muss beim Zurückschreiben zu sein (sonst Abbruch mit PID,
[[energie-exe-verwaiste-instanz]]), beim Holen wird mit SHA-256 gesichert, vor
dem Schreiben läuft der Prüfstein über alle neun Tabellen, danach die Gegenprobe
aus der Datenbank. Ersetzt werden nur geänderte Tabellen. Ein mehrdeutiger
Projektname wird abgewiesen statt geraten.

**Why:** Am 12.09.2026 lief jeder dieser Schritte achtmal von Hand, mit inline
zusammengeschriebenem SQL. Jedes Mal war eine der vier Regeln neu zu bedenken.

Format und Aufbau des Containers: [[energieberater-sanierungsvarianten]] ·
[[bdexit-format]]. Die Felder einer Maßnahme: [[sanierungsmassnahme-acht-felder]].
Anlagentechnik: [[ibp-sammlungen-schreiben]].
