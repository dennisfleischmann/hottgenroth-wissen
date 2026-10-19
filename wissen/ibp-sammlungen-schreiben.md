---
name: ibp-sammlungen-schreiben
description: "ibp-sammlung.exe schreibt in Sammlungen des IBP-Modells (Zonenverweise, Pumpen); der Schalter enumAmbientType allein genügt nicht — ohne Zoneneintrag fällt die Gutschrift still durch"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-12T13:53:12.445Z
---

`ibp-feld-setzen.exe` bricht ab, sobald ein Pfad auf einer Sammlung endet
(„Pfad endet auf einer Sammlung, nicht auf einem Feld"). Dafür gibt es jetzt
**`ibp-sammlung.exe`** in `werkzeuge/ibp/`, mit derselben Pfadschreibweise:

```powershell
$p = "CircuitHeatWater[0].Distributions[0].Pipes[2].AmbientTemperature.AmbientZone"
ibp-sammlung.exe k.bin -       $p                                  # zeigen
ibp-sammlung.exe k.bin neu.bin $p anhaengen "P0Zone_1[E9BB54E1]"
ibp-sammlung.exe k.bin neu.bin "CircuitDHW[0].Distributions[0].Pumps" entfernen 0
```

`IBPArrayList` trägt `Add`, `Insert`, `Remove`, `RemoveAt`, `Clear`, `Count` und
einen Indexer.

**Der Schalter allein genügt nicht.** Ein Rohr trägt `enumAmbientType = 2`
(„in Zone"), und *welche* Zone gemeint ist, steht als Objektkennung daneben in
`AmbientZone`. Wer nur den Schalter setzt und die Liste leer lässt, bekommt ein
Modell, das „in Zone" behauptet und die Verluste trotzdem **niemandem**
gutschreibt: `P58Calculator.AddUpSinksAndSourcesZone` steigt bei einem leeren
Eintrag wortlos aus. **Immer erst anhängen, dann den Schalter setzen.**

`enumAmbientType`: `1` = *in keiner Zone – im Unbeheizten*, `2` = *in Zone*.
Die Zonenkennung ist in allen Varianten eines Projekts dieselbe.

**`ibp-anlage-setzen.exe` setzt die Lage JEDES Rohrs auf `enumAmbientType = 1`
zurück und leert `AmbientZone`** — das Austauschformat kennt die Lage nicht, sein
`lage`-Schlüssel landet nicht dort. Nach jedem Anlagenbau also alle Rohre
nachziehen, sonst rechnet die neue Variante mit Verteilverlusten, die keiner Zone
gutgeschrieben werden, während der Ist-Zustand sie noch hat. Am 26.09.2026 bei
Klenke an MP4 und MP5 aufgetreten; fertiges Skript dafür:
`rohre-in-zone.ps1` (anhängen, Schalter, Gegenprobe je Rohr).

**Why:** Eine Verteilleitung „in keiner Zone" verliert ihre gesamte Wärme. Am
12.09.2026 lagen so 105,8 m Leitung bei U = 0,2 W/(m·K) im Unbeheizten — rund
2.500 kWh/a, die keinem Raum gutgeschrieben wurden.

**Beim Entfernen aus `Pumps`** bleibt der Pumpentyp im Vorrat (`P58CircuitPumps`)
stehen; nur der Verweis der Verteilung verschwindet. Ob die Software den
`iReferenceCount` nachzieht, ist offen — nach dem Zurückschreiben prüfen.

Verwandt: [[din18599-modell-fabriken]] · [[ibp-bauart-felder]] ·
[[sanierungsvarianten-werkzeugkette]].
