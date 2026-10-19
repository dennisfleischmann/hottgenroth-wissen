---
name: isfp-komponenten-kommen-aus-dem-container
description: "Die iSFP-Maske legt Komponenten dort an, wo sich ein Beschreibungstext gegenüber der Vorgängervariante ÄNDERT — SANBEZ für die Hülle, Beschr_Heiz/Beschr_Wass/Beschr_Luft für die Anlagen; InvestKostenText liefert nur die Kosten"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1f0988c2-fbda-498e-bc4f-0bd047948fdc
  modified: 2026-09-26T13:22:05.453Z
---

Die Meldung *„Dieses Maßnahmenpaket enthält keine Maßnahmenkomponenten! Komponenten
werden anhand der Beschreibungstexte der zugehörigen Sanierungsvariante angelegt"*
ist wörtlich zu nehmen: **Beschreibungstexte**, und zwar dort, wo sie sich gegenüber
der Vorgängervariante **ändern**.

| Seite | Feld in | Wirkung |
|---|---|---|
| Hülle | `TableHuellfl.SANBEZ` | je neuer Text eine Komponente (SK_DACH, SK_WAND, …) |
| Heizung | `TableAnlage.Beschr_Heiz` | Komponente dort, wo der Text wechselt |
| Warmwasser | `TableAnlage.Beschr_Wass` | ebenso |
| Lüftung | `TableAnlage.Beschr_Luft` | ebenso |
| Kosten | `TableAnlage.InvestKostenText` | **nur die Beträge**, keine Komponente |

**`InvestKostenText` erzeugt keine Komponente.** Format
`Bezeichnung|Invest|Invest_EE|Betrieb`, Zeilen mit CRLF; die Software summiert daraus
selbst `InvestKosten` und `InvestKosten_EE`. Genau daran erkennt man, dass sie das Feld
gelesen hat — bei Klenke standen nach dem Schreiben 25.900 / 57.700 / 70.900 € in den
Summenfeldern, und die Pakete blieben trotzdem leer.

**Why:** Am 26.09.2026 bei Klenke. MP4 trug die Wärmepumpe im Rechenmodell (nur
`HeatPump`, Endenergie 4.545 gegen 13.568 kWh in MP3) **und** vier Kostenzeilen — und
blieb in der Maske leer. `Beschr_Heiz` stand dort noch auf „Brennwert-Kessel, Heizöl EL",
identisch mit MP3. In MP5 hatte die Software den Text auf „Wärmepumpe Luft-Wasser,
Strom-Mix" gezogen, und **nur dort** erschienen Heizung und Warmwasser — im falschen
Paket, acht Jahre zu spät. Warum sie ihn in MP5 nachzog und in MP4 nicht, obwohl beide
dasselbe Modell tragen und beide gerechnet sind, ist offen.

**How to apply:** Nach jedem Anlagenwechsel von außen `Beschr_Heiz` und `Beschr_Wass`
in **der** Variante setzen, ab der die neue Anlage gilt — byte-gleich zu dem Text, den
die Software anderswo selbst geschrieben hat, samt abschließendem CRLF:

```powershell
$wp = "Wärmepumpe Luft-Wasser, Strom-Mix`r`n"
.\setze-feld.ps1 -Tabelle TableAnlage -Feld Beschr_Heiz -Wert $wp -Proj 6
.\setze-feld.ps1 -Tabelle TableAnlage -Feld Beschr_Wass -Wert $wp -Proj 6
```

**Folgen für die Fahrplanung** — [[isfp-technikpaket-braucht-anker]]:
Ein Paket, in dem sich **kein** Beschreibungstext ändert, bleibt leer. Eine PV-Anlage
hat gar kein `Beschr_`-Feld und kann allein nie eine Komponente erzeugen; bei Hesse
stand sie im selben Paket wie die Wärmepumpe und erschien als dritte Ausführung von
`SK_HEIZUNG`. Eine Lüftung, die nicht im Modell steht, lässt `Beschr_Luft` auf „Keine
Lüftung vorhanden" und bleibt damit unsichtbar.

**Die Maske ordnet Paket N der N-ten Variante zu — über die Reihenfolge, nicht über
den Namen.** Gemessen am 30.09.2026 bei Klenke: die Maske führte fünf Pakete mit den
Namen des fs-app-Fahrplans (MP1 Kellerdecke … MP5 Fenster), der Container fünf
handangelegte Varianten (OGD, Fassade, Heizung tauschen, Keller u. Fenstertausch,
Kellerboden). Die Komponenten folgten strikt der Position: Paket 1 „Dach" (Var 1 OGD),
Paket 3 „Heizung"+„Warmwasser" (Var 3), Paket 5 „Keller" (Var 5). Passen Namen und
Positionen nicht zusammen, druckt der iSFP zu jedem Paketnamen die Maßnahmen einer
fremden Variante — und nichts daran sieht nach einem Fehler aus. Deshalb: **vor dem
Aktualisieren die Variantenliste gegen die Paketliste halten**, nicht nur die Anzahl.

Direkt in `PrMedia` → `iSFP2.xml` geschriebene Komponenten verwirft die Maske beim
Aktualisieren. Was an einem Beschreibungstext hängt, überlebt samt Namen, Texten und
Skizzen. Reihenfolge deshalb: **erst Container füllen, dann in der Maske aktualisieren,
dann die Texte schreiben.**
