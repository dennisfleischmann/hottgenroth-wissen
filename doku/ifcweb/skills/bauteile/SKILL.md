---
name: bauteile
description: Bauteile und Huellflaechen - Katalog, U-Werte, Schichten, Bauteile aus einem anderen Projekt uebernehmen. Ausloeser - Bauteil, U-Wert, Huellflaeche, Aufbau, Katalog, sqproj uebernehmen.
erprobungsstand: teils-widerlegt
---

> **Warnung.** Die tragende Annahme des Übernahme-Entwurfs ist **widerlegt**: die
> Software schreibt ihre Zeilen nicht, sie serialisiert ihr Objektmodell. Ein
> zeilenweiser Kopiervorgang erzeugt einen Bestand, den das Modell so nie erzeugt
> hätte — gemessen: gleiche Bauteile, gleiche Geometrie bis aufs Byte, aber fremde
> Variantenwurzeln und ein leeres HottCAD-Modell. **Schreibe hier nicht selbst.**
> Lauf trocken, berichte, und gib an den Nutzer zurück.

**Stand:** Lesen erprobt. Anlegen per INSERT erprobt, aber mit Einschränkungen.
Kopieren zwischen Projekten **nicht** tragfähig auf dem gebauten Weg; der gangbare
Weg wäre die Software-API über die Brücke, und die Kette ist unfertig.

**Datenmodell:** `bauteile/docs/hottgenroth-bauteil-sql.md`.
**Entwurf und Widerlegung:** `hottgenroth-agent/docs/bauteile-uebernehmen.md`.

## Fallen

- **`VariantRoot` ist Text, kein `uniqueidentifier`** — enthält aber eine GUID.
  Eine Typregel übersieht die Spalte; das macht Kopien still unbrauchbar.
- **Nicht jede GUID wird umgeschrieben.** `FrameOI3UId` und `GlazingOI3UId` zeigen
  in die geräteweite TIM-Datenbank. Wer sie mitmappt, zerschneidet den Verweis
  still — das Bauteil sieht danach normal aus und hat keine Ökobilanzdaten mehr.
- **Sentinels sind Werte, keine Fehler.** `RValue` steht bei schichtlosen Bauteilen
  auf dem Sentinel ohne Vorzeichen. Wer das repariert, macht es kaputt.
