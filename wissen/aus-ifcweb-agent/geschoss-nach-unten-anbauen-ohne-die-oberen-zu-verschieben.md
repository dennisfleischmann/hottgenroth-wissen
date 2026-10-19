---
name: geschoss-nach-unten-anbauen-ohne-die-oberen-zu-verschieben
description: "Keller unter das unterste Geschoss haengen: geschoss_anlegen setzt die Hoehenlage auf Bezug minus dessen Geschosshoehe (nicht der neuen), danach geschoss_aendern IMMER mit expliziter Hoehenlage — sonst rutschen alle Geschosse darueber samt Waenden"
metadata:
  type: project
  stand: gemessen
---

Die Zielhoehenlage eines nach unten angebauten Geschosses ist Hoehenlage_Bezug minus (gewuenschte lichte Hoehe + Deckenstaerke), hier 0.2-(2.4+0.2) = -2.4. geschoss_anlegen kann das nicht, es kennt keine Hoehenparameter und kopiert die Kenngroessen der Vorlage. Also zweistufig: anlegen, dann geschoss_aendern mit Hoehenlage UND LichteHoehe zusammen. Der springende Punkt ist die explizite Hoehenlage: Set-Geschoss.ps1 rechnet fuer jedes Geschoss darueber NeuBezug = darunter.NeuBezug + NeuHoehe + NeuDecke. Laesst man die Hoehenlage weg (Vorgabe NaN = bleibt -2.6) und setzt nur LichteHoehe 2.4, schrumpft die Kellergeschosshoehe auf 2.6 und EG landet auf -2.6+2.6 = 0.0 — EG und DG waeren mit allen 8 Waenden um 0.2 m nach unten gewandert.

**Beleg:** 22.08.2026, Test0001 (2c5ac804-0dcc-4560-88a7-7b8827ff69f8), scharf ausgefuehrt. Ausgangsstand EG 0.2 / DG 3.0, Geschosshoehe je 2.8. geschoss_anlegen -Name Keller -Typ Keller -Bezug EG -Lage darunter meldete Hoehenlage -2.5999999999999996, also 0.2-2.8 (die Geschosshoehe des BEZUGSgeschosses, nicht die gewuenschte des Kellers). Anschliessend geschoss_aendern -Geschoss Keller -Hoehenlage -2.4 -LichteHoehe 2.4: Probelauf markierte nur den Keller mit '*', EG und DG ohne '>' (mitverschoben), '0 Bauteile' betroffen. Nach dem scharfen Lauf zeigt projekt_lesen Keller -2.4/2.4/2.6, EG 0.2/2.6/2.8, DG 3.0/2.6/2.8. Snapshot-Diff vor/nach: +4 Zeilen (BmFloor, BmFloorData, 2x BmData), 0 geaendert, 0 weg; BmElement taucht im Diff nicht auf, die 8 Waende sind unangetastet.

**Nicht gemessen:** Gemessen ist nur der Anbau UNTEN, unterhalb aller vorhandenen Geschosse. Der Einschub ZWISCHEN zwei Geschosse (Eintrag geschoss-einfuegen-kollidiert-mit-darueberliegendem) bleibt weiterhin ungemessen — dieser Lauf sagt darueber nichts aus, ausser dass die Rechenregel von Set-Geschoss.ps1 (Stapeln ab dem geaenderten Geschoss aufwaerts) sich so verhaelt wie im Quelltext beschrieben. Die Wirkungsprobe in HottCAD steht aus: das Projekt wurde nach der Aenderung nicht geoeffnet, der Geschossdialog also nicht gesehen. Der Keller hat keine Waende, deshalb ist ungeprueft, ob bei besetztem Geschoss wirklich kein z verschoben wird — gemeldet wurden 0 Bauteile.

**Why:** Der Auftrag lautete ausdruecklich, die vorhandenen Waende unangetastet zu lassen. Der bequeme Einzelaufruf (nur LichteHoehe) haette acht Waende still im z verschoben, und der Snapshot-Diff haette das als beabsichtigte Aenderung ausgewiesen, weil die Zahlen in sich stimmig geblieben waeren.

**How to apply:** Beim Anbauen nach unten die Zielhoehenlage vorher von Hand ausrechnen und in geschoss_aendern zusammen mit der lichten Hoehe uebergeben. Im Probelauf ist das Abnahmekriterium: nur das neue Geschoss traegt '*', kein anderes traegt '>', und die Bauteilzeilen der uebrigen Geschosse fehlen ganz.
