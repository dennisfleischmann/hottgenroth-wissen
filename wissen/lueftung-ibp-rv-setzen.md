---
name: lueftung-ibp-rv-setzen
description: "ibp-rv-setzen.exe allein GENÜGT NICHT: es lässt enRVSystem auf ExhaustSystem, und der Kern verwirft die Wärmerückgewinnung dann vollständig"
metadata:
  type: reference
---

> **ACHTUNG — das Werkzeug allein reicht nicht.** `ibp-rv-setzen.exe` setzt
> `feta_WRG`, fasst aber `enRVSystem` nie an, und
> `AddDomainForMechanicalVentilationForResidentialZone` legt die Domäne mit dem
> Vorgabewert `ExhaustSystem` an. Ohne den Nachschritt bleibt die
> Wärmerückgewinnung wirkungslos.
>
> **Belegt ist das am Quelltext, NICHT an einer Messung** (korrigiert am
> 28.09.2026): `feta_WUET_mth` wird ausschließlich **innerhalb** des Zweigs
> `if (flag)` geschrieben, und `flag` hängt an `domain.enRVSystem` **und**
> `bRVHeatExchanger` (`Calculate_SupplyAirTemperatureResidential_Monthly`). Von
> dort geht der Wert in die Zonenbilanz:
> `p0MonthlyValue[i] = num + feta_WUET_mth[i] * (num2 - num)` →
> `Q_b_nutz.H_V.ftheta_V_mech` (`IBP18599kernelNavigator2018.cs:5446ff`).
>
> **Der ursprünglich zitierte Messbeleg war falsch gelesen.** Ich hatte
> `feta_WUET_mth.fValue = 0` angeführt — dieser Steckplatz ist bei einem
> **Wirkungsgrad grundsätzlich 0**, vorher wie nachher, siehe
> [[ibp-blob-lesefallen]]. Aussagekräftig sind die zwölf Monatsfelder: nach dem
> Nachschritt stehen sie bei Klenke MP5 auf `0,832 = 0,8 × 1,04`
> (`ff_v_WUET_Frost = −0,04`).
>
> **Die GRÖSSE der Wirkung ist weiter offen.** Endenergie MP5 fiel 4.163 → 3.607
> (−556 kWh/a), die Lüftungs-Hilfsenergie stieg 68,19 → 238,67. Dasselbe Feld
> schaltet aber auch den mechanischen **Zuluftstrom** zu
> (`fn_mech_ZUL` 0 → 0,4 1/h, `IBP18599kernelNavigator.cs:12871`, dazu
> `CalculateSupplyAirVolumeFlow_Residential` ab :22865) — die −556 sind also eine
> **Nettozahl über mindestens zwei gekoppelte Wege**, und der Blob teilt sie auf
> keinen davon auf: die Zonen-Ergebnisschicht (`P2Results`) wird **nie
> gespeichert**. Für 83 % Rückgewinnung an einem EFH sind ~2.100 kWh/a
> eingesparte Wärme eher **wenig**. Wer die Wirkung wirklich belegen will,
> braucht den Rechenlauf ohne Oberfläche mit Zugriff auf `P2Results` im Speicher
> ([[rechenlauf-ohne-oberflaeche]]).
>
> **Pflichtschritt nach jedem Lauf:**
> ```powershell
> ibp-feld-setzen.exe blob.bin neu.bin ^
>   "Zones[0].ZoneVentilation.DomainsForMechanicalVentilationForResidentialZones[0].enRVSystem" 1
> ```
> `RVSystem`: 0 ExhaustSystem · **1 SupplyAndExhaustVentilationSystem** ·
> 2 AirHeatingSystem · 3 SupplySystem.
>
> Zweiter Fall derselben Art: `bp_el_Vent_Standard` bleibt auf `True`, deshalb
> holt der Kern die Ventilatorleistung bei **jedem** Lauf neu aus
> `Get_p_el_Vent_rv(operatingData.enRVSystem, …)` — Abluftanlage und
> Zu-/Abluftanlage mit WRG sind dort verschiedene Tabellenzeilen. Der
> Hilfsenergiesprung 68,19 → 238,67 ist genau **3,500**, zerlegbar in 1,2 × 2,9167
> = 0,35/0,12. Die Tabelle selbst liegt in einem externen Parameter-Blob, die
> Zahlen sind **nicht** im Quelltext nachlesbar — ob 0,35 der Abluft- oder der
> Zu-/Abluftwert ist, ist damit **offen**. Leistung und Schalter gehören zusammen
> gesetzt, oder die Leistung gar nicht erst planen.
>
> **Nicht als Prüfgröße verwenden:** `Zones[0].P3Results.ft_WRG` (Teil-3-Größe
> der RLT-Rechnung, bei einer Wohnzone bauartgemäß 0) und alles unter
> `UnitRV[0].OperatingData.*` (wird gar nicht serialisiert, siehe
> [[ibp-blob-lesefallen]]).

Das Austauschformat (`ibp-anlage-lesen/-setzen`) führt **keine Lüftung**. Dafür
gibt es ein eigenes, undokumentiertes Programm:

```powershell
ibp-rv-setzen.exe blob.bin neu.bin wrg=0.8 vorwaermung=0 zone=0
ibp-feld-setzen.exe neu.bin fertig.bin "UnitRV[0].strName" "Lüftungsanlage 1"
```

- `wrg` → `UnitRV[0].feta_WRG`. **Bei FS ist der Wärmerückgewinnungsgrad immer
  80 %** (Dennis, 27.09.2026).
- `vorwaermung` schaltet **allein** `bElectricalPreheating`. Bei dezentralen
  Geräten aus — die lösen den Frostschutz anders. Hesse hat sie an, ist aber
  eine zentrale Anlage.
- Der zweite Aufruf ist Pflicht: das Programm schreibt `strName` als
  „Lueftungsanlage 1" ohne Umlaut, und der Name landet im Ausdruck
  ([[varianten-umlaute]]).

**Geschrieben und gerechnet am 27./28.09.2026** an `V4DZX_Nadine Klenke` MP5 — die Struktur trägt, die Wirkungsgröße ist offen (siehe oben). Die Struktur ist
deckungsgleich mit einem Stand, den die Software selbst geschrieben hat
(`EG2KU_Hesse_260815`): `UnitRV` 864 Zeilen, `CircuitHeatAirRV` 714, je 218
Felder, gleiche Verdrahtung. UA bleibt unverändert, die Wärmepumpe unangetastet.

**Was das Werkzeug anders vorgibt als die Software:** `fp_el_Vent` 0,35 statt
0,20 · `enumFanType` 1 statt 0 · `bRVHeatExchanger` True statt False. Die
Software hängt ihrer Einheit zusätzlich einen Katalogschlüssel an
(`strAdditionalInfo = Lüftungssystem=RV_A2222`), das Werkzeug nicht.

**Der Grad steht an ZWEI Stellen, und sie tun Verschiedenes:**

| | wo | wofür |
|---|---|---|
| `UnitRV[0].feta_WRG` | Rechenmodell | die **Endenergie** — ob die Rückgewinnung wirkt |
| `NumEdit_WRG_Grad_LuftAnlg_1…5` | iSFP-Maske, Reiter Kennwerte | die **Zahl im Ausdruck**, `<WRG_Grad>` im Export |

Der Maskenwert ist ein **eingebbares** `NumEdit`, je Paket eines, direkt neben
`ComboBox_LuftAnlg_*` (der Anlagenart) und `NumEdit_Baujahr_LuftAnlg_*`. In
derselben Zeile stehen `NumEdit_Invest_*` und `NumEdit_Invest_EEff_*` — daher
sind die Investitionen im Überblick leer, solange dort nichts getippt wurde.
Namen aus den Delphi-Formularen der `Energie.exe`
([[energie-exe-delphi-formulare]]).

**Beides setzen.** Nur die Maske: der Fahrplan zeigt 80 %, gerechnet wird ohne
Rückgewinnung. Nur das Modell: richtig gerechnet, im Ausdruck stehen 0 %.

**Förderseitig** (BEG EM 17.08.2026, Nr. 2.1.1, Wohngebäude): Anlagen mit
Wärmeübertrager brauchen WBG ≥ 80 % bei P_el,Vent ≤ 0,45 W/(m³/h) oder
WBG ≥ 75 % bei ≤ 0,35. **Der WBG der Richtlinie ist nicht `feta_WRG` nach
DIN 18599** — Hesse steht dort auf 0,70 und wird trotzdem gefördert.

Offen: ob die Software `TableAnlage.Beschr_Luft` beim Rechnen nachzieht. Tut sie
es nicht, fehlt die Komponente `SK_LUEFTUNG` und der Text muss von Hand gesetzt
werden — [[isfp-komponenten-kommen-aus-dem-container]].
