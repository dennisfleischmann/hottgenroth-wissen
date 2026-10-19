---
name: wohngebaeude-einzonenmodell
description: "Wohngebäude als Einzonenmodell herstellen — ein Aufruf, Vorbedingungen und Invariantenprüfung; Ablauf im bauteile/-Repo"
metadata: 
  node_type: memory
  type: project
  originSessionId: a79f8008-5d86-4c71-9f3c-51871403afa1
  modified: 2026-08-17T21:42:33.541Z
---

Für ein Wohngebäude nach dem Standardschema (**eine** DIN-18599-Zone, Profil
„42 - Wohnung Einfamilienhaus", je Raum nur **beheizt** oder **unbeheizt**) gibt
es einen fertigen Ablauf. Nicht selbst zusammenstückeln:

```powershell
cd C:\Projekte_Dev\energieberatung\bauteile\tools
.\Setup-Wohngebaeude.ps1 -Projekt "<Name>" -Beheizt EG,DG1,DG2 -Unbeheizt Keller -Probelauf
.\Setup-Wohngebaeude.ps1 -Projekt "<Name>" -Beheizt EG,DG1,DG2 -Unbeheizt Keller
```

Sechs Schritte in einem Aufruf: Vorbedingungen → Sicherung → Zone → Nutzungsprofil
→ Raumstempel → Zonenzuordnung → Invariantenprüfung. Prüfen allein geht jederzeit
gefahrlos mit `Test-Wohngebaeude.ps1` (21 Invarianten, Rückgabewert = Fehlerzahl).

Handlungsanweisung: `bauteile/docs/ablauf-wohngebaeude-eine-zone.md`.
Datenmodell dahinter: [[raum-zone-raumstempel]].

Vier Dinge, die man vorher wissen muss:

- **Räume anlegen geht** — das war jahrelang als Grenze notiert und ist
  widerlegt. Am 17.08.2026 wurde *Wohnraum 21 / DG2-R1* in Pohlstraße von außen
  geschrieben: nur `BmRoom`, `BmRoomData` und die Zeichnung. Die vierzehn
  Verweise auf die begrenzenden Bauteile trug **HottCAD sieben Stunden später
  beim Öffnen selbst nach**. Der alte Denkfehler war die Umkehrung: weil die
  Software die Verweise rechnet, muss man sie gerade NICHT liefern.
- **`ProfileUsageType` ist nicht die Zahl im Profilnamen.** „42 Einfamilienhaus"
  ist intern **34**, „43 Mehrfamilienhaus" ist **35**. Mit 42 bekommt man
  „36 Labor". Ab Nummer 34 laufen Anzeige und Aufzählung auseinander.
- **Der Prozess heißt nicht immer `Energie`** — der EE-Berater läuft als
  `EEBerater`. Siehe [[energie-exe-verwaiste-instanz]].
- **Ein Projekt kann mehrere eberater-Container in `PrMedia` führen.** Maßgeblich
  ist der mit dem jüngsten `StampEdit`; der andere ist ein Überrest.

**Why:** Der Ablauf hat vier Einzelschritte in fester Reihenfolge, und jeder
Fehler darin ist still — ein vergessenes Geschoss, ein Raum in keiner Zone, ein
Heizstatus, der nur an einer der beiden Stellen gesetzt ist. Deshalb prüft der
Ablauf seine Vorbedingungen vorher und seine Invarianten hinterher, statt sich
auf die Reihenfolge im Kopf zu verlassen.

**How to apply:** Immer erst `-Probelauf`. Danach die Wirkung in der Oberfläche
ansehen, nicht nur die Zeilen ([[wirkungsprobe-statt-selbstpruefung]]) — solange
die Zonenfläche auf dem Sentinel steht, hat die Software die Zuordnungen nicht
verrechnet. Geht etwas verloren: `Restore-Projekt.ps1` holt **ein** Projekt aus
einer Sicherung zurück; ein Voll-Restore würde alle 40 zurücksetzen.
