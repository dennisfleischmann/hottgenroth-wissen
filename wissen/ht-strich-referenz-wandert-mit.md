---
name: ht-strich-referenz-wandert-mit
description: "Beim HT'-Nachweis wandert der Grenzwert mit der Geometrie mit — ein Bauteil zu verbessern, das schon besser als die Referenz ist, verschlechtert den Abstand"
metadata: 
  node_type: memory
  type: project
  originSessionId: 405e3c82-5fe2-4d06-8300-0a56695266e5
  modified: 2026-09-25T13:18:36.631Z
---

Der HT'-Grenzwert einer EH-Stufe ist **kein fester Wert**, sondern ein Prozentsatz
des Referenzgebäudes (EH40: 55 %). Das Referenzgebäude hat **dieselbe Geometrie und
dieselben Temperaturkorrekturfaktoren** wie das Ist-Gebäude, nur die U-Werte aus
GEG Anlage 1 Tabelle 1 (AW 0,28 · Dach 0,20 · Fenster 1,30 · Tür 1,80 ·
erdberührt 0,35 · ΔU_WB **fest 0,05**).

**Daraus folgt die Prüfgröße: Ist-U / Referenz-U je Bauteilart.** Alles über dem
geforderten Prozentsatz zieht den Nachweis nach unten, alles darunter trägt ihn.
Ein Bauteil zu „verbessern", dessen Verhältnis schon unter dem Prozentsatz liegt,
**verschlechtert den Abstand** — weil der Grenzwert stärker fällt als der Ist-Wert.

**Am Fx erdberührter Bauteile zu drehen geht deshalb fast immer nach hinten los.**
Gemessen am Projekt `3QHTK_Lennart Krause` (DHH, EH40, 25.09.2026): Bodenplatte
U 0,124 gegen Referenz 0,35 = Verhältnis 0,355. Fx von 0,75 auf 0,50 senken
brachte dem Ist-Wert −0,0082, nahm dem Grenzwert aber −0,0127 — unterm Strich ein
Verlust. Fx **erhöhen** half rechnerisch.

**Der einzige Hebel, der voll durchschlägt, ist der Wärmebrückenzuschlag**, weil
die Referenz dort mit ihrem eigenen festen Zuschlag rechnet und nicht mitwandert.
Jede Senkung von `TableHausDat.BERUECKSWB` ([[bdexit-format]], daneben
`WBPAUSCHAL=1`) geht 1:1 in den Ist-Wert und lässt den Grenzwert stehen.

**Den Grenzwert selbst nachzubauen ist bisher nicht gelungen.** Er steht weder im
`eberater.zip` noch im Kernel-Blob — die Software rechnet ihn beim Anzeigen. Ein
Nachbau aus GEG Anlage 1 Tabelle 1 mit ΔU_WB 0,05 und × 0,55 lag im Projekt oben
um 0,008 zu hoch (0,2368 gegen angezeigte 0,229). **Für Abstandsrechnungen also
den angezeigten Grenzwert nehmen, nicht den eigenen** — und ihn nach jeder
Geometrieänderung neu ablesen. Der Ist-Wert dagegen ist exakt nachrechenbar:
Σ(A·U·Fx)/ΣA + ΔU_WB trifft `TableResult.HTSTRICH` auf vier Stellen.

**Why:** Der intuitive erste Griff bei knappem HT' ist der Temperaturkorrektur-
faktor der Bodenplatte, weil er als reiner Rechenparameter ohne Bauteilwechsel
aussieht. Genau der macht es schlimmer.

**How to apply:** Vor jeder Maßnahme die Verhältnistabelle Ist-U/Ref-U je
Bauteilart aufstellen und nur dort ansetzen, wo das Verhältnis **über** dem
Prozentsatz der Stufe liegt. Skripte dazu im Scratchpad-Muster: Hüllflächen aus
`TableHuellfl` je Satz (`KENNZEICHEN`, `FLAECHE`, `K_ZAHL`, `REDFAKTOR`),
Gegenprobe gegen `TableResult.HTSTRICH` — trifft die Nachrechnung diesen Wert auf
vier Stellen, stimmt das Modell. Siehe [[wirkungsprobe-statt-selbstpruefung]] und
[[eh-haus-pflichtbestandteile]].
