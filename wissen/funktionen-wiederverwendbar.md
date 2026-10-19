---
name: funktionen-wiederverwendbar
description: "Alle Funktionen und Werkzeuge müssen wiederverwendbar sein — parametriert statt fest einkodiert, und gegen ein zweites Projekt geprüft"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-12T00:19:17.555Z
---

Werkzeuge werden **wiederverwendbar** gebaut, nicht als Nachbau eines Einzelfalls.
Konkret heißt das: Werte und Kennungen als **Parameter**, Kennungen **erzeugen** statt
aus einem Vorlageprojekt übernehmen, benötigte Objekte **anlegen** statt vorauszusetzen,
und Auswahl (Zone, Variante, Projekt) explizit statt `[0]`.

**Und gegengeprüft an einem zweiten Projekt**, bevor etwas als fertig gilt.

**Why:** Am 12.08.2026 mehrfach passiert — `ibp-build-heating.exe` sah fertig aus,
enthielt aber sechs Kennungen aus „Werner Grotz", ein Dutzend Werte dieser Anlage, und
hängte sich an Pooltypen, **die dort nur zufällig noch vorhanden waren**. In einem
Projekt ohne vorherige DIN-18599-Erfassung sind diese Pools leer; das Werkzeug hätte
einen Heizkreis ohne Rohre, Pumpe und Übergabe erzeugt. Am Ursprungsprojekt allein
fällt so etwas **nie** auf.

**How to apply:** Vor „fertig" drei Fragen: Welche Konstante stammt aus dem
Testprojekt? Was setze ich voraus, statt es anzulegen? Was passiert bei leerer
Sammlung / mehreren Zonen / mehreren Varianten? Dann an einem zweiten Projekt laufen
lassen — offline reicht für die Struktur, geschrieben wird nur nach Rückfrage.

Gilt für alles in `hsetu-decompiled/werkzeuge/`, siehe [[din18599-modell-fabriken]] und
[[energieberater-sanierungsvarianten]].
