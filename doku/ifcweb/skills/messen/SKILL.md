---
name: messen
description: Herausfinden, was die Software beim Klicken schreibt - Momentaufnahme, spaltengenauer Vergleich, SQL-Mitschnitt. Ausloeser - was schreibt die Software, unbekannter Bereich, vermessen, warum ist das weg, wiederherstellen.
erprobungsstand: erprobt
---

**Stand:** Der Zyklus hat das Bauteil-, Varianten- und Raum/Zonen-Datenmodell
aufgeklärt. Erprobt.

## Zyklus

`snapshot` vor dem Schritt → der Nutzer tut **einen** Schritt in der Software und
speichert → `snapshot` danach → `diff`. Für die *Reihenfolge* der Schreibvorgänge
zusätzlich der SQL-Mitschnitt; der Vergleich zeigt nur den Endzustand.

Bitte den Nutzer um **einen Schritt je Runde**. Am Stück lässt sich nicht
zuordnen, was wozu gehört.

## Fallen

- **Die Extended-Events-Session überlebt keinen LocalDB-Neustart.** Die Instanz
  fährt nach Leerlauf herunter; die Session bleibt angelegt und läuft nicht mehr.
  `STARTUP_STATE = ON` behebt es.
- **Häufigster Wert ist nicht typischer Wert.** Eine Auswertung über alle Räume
  der Datenbank wird von Altprojekten ohne CAD-XML beherrscht.
- **Verlorenes zurückholen:** `restore_projekt` holt **ein** Projekt aus einer
  Sicherung. Ein Voll-Restore wäre falsch — er setzt alle 40 zurück.
