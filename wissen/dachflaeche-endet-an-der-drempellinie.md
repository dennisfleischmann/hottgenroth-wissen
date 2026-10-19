---
name: dachflaeche-endet-an-der-drempellinie
description: "Bei Dachgeschossen mit Abseite nimmt die Hüllflächenermittlung nur die Dachfläche über den Räumen — der Rest fällt still heraus, ohne Ersatzfläche"
metadata: 
  node_type: memory
  type: project
  originSessionId: 405e3c82-5fe2-4d06-8300-0a56695266e5
  modified: 2026-09-25T13:13:26.473Z
---

Die Hüllflächenermittlung folgt den **Räumen**, nicht der Zeichnung. Enden die
DG-Räume an einer Drempel-/Abseitenlinie, wandert nur die Dachfläche oberhalb
davon in `TableHuellfl` — und die begrenzenden Flächen der Abseite
(Drempelwand, Abseitenboden) entstehen **nicht von selbst**. Die thermische
Hülle ist dort schlicht offen, ohne jede Meldung.

Gemessen am Projekt `3QHTK_Lennart Krause` (25.09.2026): Grundriss 7,27 × 11,215 m,
Satteldach 25°. Dachfläche über beheiztem Grundriss **89,96 m²**, im gerechneten
Modell nur **63,97 m²** — 25,99 m² fehlten. Abschnitt bei rund 0,95 m über
DG-Fußboden. Bei einem Holzbau mit durchlaufender Dämmung zwischen den Sparren
gehört die Abseite in die Hülle, die volle Fläche ist die richtige.

**Prüfgriff, drei Zahlen nebeneinander:**
- `BmElement` `RepositoryType 3` (Zeichnung): `Roof … Seite 1/2`, hier je 56,89 m²
  — das ist die Dachfläche **mit** Überständen, nie der Hüllwert.
- Geometrie: Grundfläche / cos(Neigung) — hier 81,53 / cos 25° = 89,96 m².
- `RepositoryType 1` (gerechnetes Gebäude): Summe der `Roof …-n` — muss der
  Geometrie entsprechen, nicht der Zeichnung.

Die Außenkontur aus `Show-Projekt.ps1` trifft die Bodenplatte exakt (7,27 × 11,215
= 81,53 gegen `FLAECHE` 81,53665) — sie ist damit der verlässliche Bezug für
diesen Vergleich. Siehe [[bmelement-zwei-repositories]] und
[[hsetu-geometrie-in-geodesc]].

**Why:** Nichts an der Oberfläche zeigt die Lücke an; der Nachweis rechnet
widerspruchsfrei durch und ist trotzdem nicht prüffähig. Gefunden nur, weil die
Dachfläche gegen die Bodenplatte auffällig klein wirkte.

**How to apply:** Bei jedem DG mit Abseite die drei Zahlen vergleichen, bevor
ein Nachweis rausgeht. Ergänzen verschlechtert den HT'-Abstand meist leicht (das
Dach liegt beim Ist/Ref-Verhältnis über der Stufe, siehe
[[ht-strich-referenz-wandert-mit]]) — hier von −0,0011 auf −0,0016.
