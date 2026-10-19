---
name: anlagentechnik
description: DIN-18599-Anlagentechnik - Waermeerzeuger, Heizkreise, Warmwasser, Lueftung im IBP-Modell. Ausloeser - Waermepumpe, Heizung, Anlagentechnik, Vorlauftemperatur, Lueftungsanlage, EH-Stufe.
erprobungsstand: teilweise-gemessen
---

**Stand:** Felder und Fabrikmethoden verstanden, Wirkung **teils** gemessen. Bei
allem, was hier nicht ausdrücklich als gemessen steht: trocken laufen, berichten,
zurückgeben.

**Beschreibung:** `hsetu-decompiled/DIN18599-ANLAGENTECHNIK.md`.

## Wo die Daten liegen

Nicht in den `Pm*`-Tabellen. Quelle ist **`TableZusatz.Kernel18599V5` je
Variante**; die Kopie in `PrMedia` ist nur eine Kopie.

## Fallen

- **Felder gelten je Bauart.** Eine Wärmepumpe rechnet mit `ftheta_si_out`, nicht
  `ftheta_VA`. Regelungs-Aufzählungen tragen gleiche Zahlen mit anderer Bedeutung.
- **`pID` nie leer lassen**, die `b*_Standard`-Flags nie ausschalten.
- **Die Vorlauftemperatur steht an zwei Stellen** — Heizkreis *und* Wärmepumpe.
  Standard 55/45 mit Heizkörpern; hohe EH-Stufe 35/28 **mit Flächenheizung**.
- **Zu einem EH-Haus gehört immer eine Lüftungsanlage** und ein hydraulischer
  Abgleich. Eine Wärmepumpe allein reicht nicht.
- **Nichts durch einen Vorgabewert ersetzen.** Die Auslegungstemperatur hängt am
  Heizkreis, nicht am Erzeuger.
