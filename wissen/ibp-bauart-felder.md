---
name: ibp-bauart-felder
description: Im IBP-Modell nie einen Wert durch einen Vorgabewert ersetzen und nie einen Wert aus einer anderen Bauart übernehmen — beides scheitert lautlos
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 49e4b8c1-37be-419d-98a1-aa61b55d2177
  modified: 2026-08-12T22:08:02.963Z
---

**Regel: lautlos ist der Feind.** Ein Feld, das nie beschrieben wurde, und ein Feld,
das mit dem Wert einer fremden Bauart beschrieben wurde, sehen im Ergebnis gleich
aus — plausibel und falsch. Deshalb: nichts durch einen Vorgabewert ersetzen, und
vor jeder Übernahme prüfen, welches Feld für die **Ziel**bauart gilt.

**Die Auslegungstemperatur hängt am `P5HeatWaterCircuit`** (`ftheta_VA`/`ftheta_RA`),
nicht am Erzeuger. Das kostete vier Anläufe: Erzeugerkomponente und Senke ändern die
Anzeige nicht, an der Einheit ist das Feld schreibgeschützt. Gefunden erst, als der
angezeigte Wert im Klartext bekannt war — 70/55 ist der Vorgabewert, also war das
Feld **nie berührt**. Bei so etwas ist eine Zahl vom Nutzer mehr wert als drei
Vermutungen; Screenshots erreichen mich oft nicht.

Weitere belegte Fälle, jeder hat einen falschen Schreibvorgang gekostet:

| | Kessel / Heizkörper | Wärmepumpe / Flächenheizung |
|---|---|---|
| Regelung | `HceControlTypeRadiator` | `HceControlTypePanelWater` (gleiche Zahlen, andere Bedeutung) |
| Bauart-Kennung | `enumBoilerType` + `…Additional` | `enumHeatPumpType` |
| `fTemperatureRise` | `(VL+RL)/2 − 20` aus dem **Kreis** | 0 — die Formel gilt dort nicht |
| Senke `ftheta_si_out/in` | – | **nie setzen**, 24 von 24 Projekten lassen 60/50 stehen |

Zwei verwandte Fallen: **`enumPipeType`** sitzt an der Leitungs*komponente*, nicht am
Pooltyp (sonst 584 m statt 227 m). **`fTemperatureRise`** wird von keiner Fabrik
gesetzt.

**How to apply:** Gegen **reale Projekte derselben Bauart** erheben, nicht gegen die
vorhandene Referenz — 84 Blobs aus `PrMedia` gleichzeitig zu befragen ist billig und
beantwortet in einem Durchlauf, was jede Vermutung offenlässt. Dann der Rundlauf
`lesen → löschen → setzen` über alle: er hat 13 stillschweigend zu Kesseln gewordene
Erzeuger, eine verlorene zweite Übergabe und eine nie angelegte Warmwasser-Verteilung
aufgedeckt. Aber Vorsicht — **er findet nur, was mindestens eine Seite kennt**; waren
Leser und Schreiber an derselben Stelle blind, ist der Rundlauf in sich stimmig.
Im Schreiber bricht `Fabrikname()` bei unbekannter Bauart ab, statt zu ersetzen.

Gehört zu [[funktionen-wiederverwendbar]] — dieselbe Ursache: eine Annahme aus dem
einen Fall auf einen anderen übertragen, ohne sie zu prüfen.
