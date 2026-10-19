---
name: zone-und-raeume
description: Wohngebaeude als Einzonenmodell herstellen - Zone anlegen, Nutzungsprofil setzen, Raumstempel vergeben, Raeume der Zone zuordnen. Ausloeser - Zone anlegen, Raeume einstellen, beheizt/unbeheizt setzen, Raumstempel, neues Wohngebaeude-Projekt.
erprobungsstand: geschrieben-und-gegengeprueft
---

**Stand:** An *Pohlstraße 133* vollständig geschrieben und spaltengenau
gegengeprüft; nach einem Totalverlust 1265 Zeilen zurückgeholt. Trocken geprüft an
*Werner Grotz* und *Murat Sen*. **In fremde Projekte wurde noch nicht
geschrieben** — der erste echte Lauf auf einem weiteren Projekt gehört Schritt für
Schritt begleitet.

**Ablauf:** `bauteile/docs/neues-projekt-zone-und-raeume.md` (Kurzfassung),
`bauteile/docs/ablauf-wohngebaeude-eine-zone.md` (vollständig).
**Datenmodell:** `bauteile/docs/hottgenroth-raum-zone-sql.md`.

## Was du vorher brauchst

Vier Angaben. Fehlt eine, frag nach statt zu raten: **Projekt** (Ausschnitt oder
GUID) · **beheizte Geschosse** · **unbeheizte Geschosse** · **Ausnahmen je Raum**.
Jedes Geschoss mit Räumen muss zugeteilt sein — das Werkzeug bricht sonst ab, und
das ist Absicht.

## Fallen

- **`ProfileUsageType` ist nicht die Nummer im Profilnamen.** Profil 42
  Einfamilienhaus ist intern **34**. Nimm die Zahl aus
  `daten/nutzungsprofile.tsv`, rechne sie nie.
- **Die Zone heißt hinterher nicht mehr wie beim Anlegen.** Die Software benennt
  sie beim Zuweisen des Profils nach dem Profil um. Zuordnungen laufen deshalb
  über die Zonen-UUID, nicht über den Namen — das Werkzeug macht das schon.
- **Nach einer raumgenauen Ausnahme meldet die Invariantenprüfung diesen Raum als
  Fehler**, weil sie je Geschoss argumentiert. Erwartet. Nenn es dem Nutzer, damit
  er es später nicht für einen echten Fehler hält.
- **Raumstempel und Zweiteilung widersprechen sich.** Die Raumart bringt ihren
  eigenen Heizstatus mit (Flur `4`, Keller/Dach/Garage `2`). Wer nur beheizt oder
  unbeheizt führen will, entkoppelt den Status vom Stempel. Das ist eine
  Projektentscheidung — triff sie nicht selbst, frag.
