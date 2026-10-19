---
name: rettung-geloeschtes-wiederholen
description: "Versehentlich Gelöschtes in Hottgenroth retten — Prozess abschießen statt Fenster schließen, Sicherung läuft bei offener Software"
metadata: 
  node_type: memory
  type: project
  originSessionId: fdf1bab8-40f6-4105-b941-4da9f0cf12f2
  modified: 2026-10-01T15:46:48.837Z
---

Ist in der Software etwas versehentlich gelöscht (eine Etage, ein Bauteil), steht
der alte Stand **noch in der Datenbank**: die Änderung lebt im Speicher der
laufenden `Energie.exe` und geht erst beim Speichern bzw. Schließen hinein.

Reihenfolge, die zählt:

1. **Strg+Z**, solange das HottCAD-Fenster offen ist. Nur dieser Weg kostet
   nichts anderes.
2. Sonst `hottgenroth-agent/tools/Sichere-Projektdatenbank.ps1` — sichert
   `COPY_ONLY` und läuft **absichtlich bei offener Software**. Es nennt die
   Geschosszahl je Projekt, daran sieht man, ob die Etage noch drin ist.
3. Dann im Task-Manager **Task beenden**, nicht das Fenster zumachen — das
   Zumachen ist der Schreibvorgang. Danach prüfen, dass kein `Energie.exe`
   übrig ist ([[energie-exe-verwaiste-instanz]]).
4. `-Einspielen` legt die Sicherung als Seitendatenbank daneben;
   `bauteile/tools/Restore-Projekt.ps1` kopiert das **eine** Projekt zurück und
   lässt die anderen in Ruhe.

**Why:** Das Herunterfahren über das Startmenü bittet die Programme, sich zu
beenden — es löst genau das Zurückschreiben aus, das verhindert werden soll. Und
ein harter Druck auf den Power-Knopf riskiert den Wiederherstellungslauf der
LocalDB, ohne mehr zu erreichen als „Task beenden".

**How to apply:** Nie den Export- oder Brückenweg als ersten Schritt gegen die
Datenbank fahren, die den einzigen guten Stand trägt — erst sichern, dann an der
eingespielten Seitendatenbank arbeiten ([[projektexport-api]]).
