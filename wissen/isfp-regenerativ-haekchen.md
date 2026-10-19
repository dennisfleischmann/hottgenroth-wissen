---
name: isfp-regenerativ-haekchen
description: "Die iSFP-Warnung „keine regenerativen Energien\" kommt vom Häkchen im Energieberater, nicht von der Anlagentechnik — es gibt es sechsmal, je Spalte eines"
metadata:
  node_type: memory
  type: project
  originSessionId: 4f0538bd-ca70-49d8-9f49-7c802c435628
  modified: 2026-09-12T03:31:43.534Z
---

Meldung beim Start der iSFP-Anwendung:
*„WARN - Allg. Inf. und Vorb.: Für die Heizung können keine regenerative Energien
verwendet werden. Dies muss begründet werden."*

**Sie hat nichts mit der Anlagentechnik zu tun.** Eine Wärmepumpe kann im
Zielzustand stehen und rechnen — die Meldung kommt trotzdem. Gesteuert wird das
Feld `regenerativ_nutzung_heizung` allein von **Häkchen im iSFP-Dialog des
Energieberaters**, Reiter Anlagentechnik. Die Delphi-Formulare in `Energie.exe`
zeigen sie ([[energie-exe-delphi-formulare]]):

| Steuerelement | Spalte |
|---|---|
| `CheckBox_RegenNutz_Hz` / `_Ww` | **Ist-Zustand** |
| `CheckBox_RegenNutz_Hz_1` … `_5` | **Maßnahmenpaket 1–5** |
| `Edit_RegenNutz_Hz…` / `_WW…` | Erläuterungstext je Spalte (max. 160 Zeichen) |
| `Memo_Keine_RegenNutz_Hz` | Begründungsfeld, falls wirklich nichts geht |

**`MeinSanierungsfahrplan.exe` liest den Zielzustand, nicht den Ist-Zustand.** Der
Prüftext im Programm lautet ausgeschrieben „Für die **zukünftige** Anlagentechnik
des Gebäudes können keine erneuerbaren Energien zur Erzeugung von Heizwärme genutzt
werden". Ein Haken im Ist-Zustand hilft also nicht, und das Begründungsfeld
(`erlaeuterung_keine_regenerative_nutzung_heizung`) leer zu lassen löst die Warnung aus.

**Why:** Der Haken sitzt seit dem 28.07.2026 durchgängig in der **falschen Spalte**
— im Ist statt im Zielzustand. Belegt an allen 47 iSFP-Exporten der LocalDB
([[isfp-export-pruefen]]): bis Strackerjan (10.07.2026) stand er richtig
(Ist = false, letztes Paket = true), ab Köhn (28.07.2026) invertiert
(Ist = true, alle Pakete = false). Betroffen: Köhn, Pohlstraße, Krüger, Hesse,
Wiemers, Voigt, Birinci, Parker, Röhlings, Messinger. Die Softwareversion ist auf
beiden Seiten 13.5.0 — **kein Update-Effekt, ein Eingabefehler**.

Zweiter Schaden: der Haken im Ist behauptet auf Seite „Ihr Gebäude heute"
regenerative Wärme, obwohl dort meist ein Gas- oder Ölkessel steht. Das Symbol
wird gedruckt.

**How to apply:** Häkchen **Heizung und Warmwasser in den Paketspalten** setzen, in
denen die Wärmepumpe steckt (mindestens im letzten = Zielzustand), Erläuterungsfeld
„Wärmepumpe", **Haken im Ist entfernen**, exportieren, iSFP-App neu starten.
Das Begründungsfeld nur füllen, wenn wirklich keine erneuerbare Wärme möglich ist —
nicht, um die Warnung wegzubekommen.

Erprobt am 12.09.2026 an `CCKZL_Messinger_260908`: MP4 „Heizung" und MP5 „Sonstiges"
trugen `HT_WP`, Strom-Mix, JAZ 3 — und trotzdem `regenerativ_nutzung_heizung=false`.
Nach dem Umsetzen der Haken lief es.
