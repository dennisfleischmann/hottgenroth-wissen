---
name: geschoss-einfuegen-kollidiert-mit-darueberliegendem
description: "geschoss_anlegen verschiebt darueberliegende Geschosse NICHT — ein eingeschobenes Geschoss bekaeme still dieselbe Hoehenlage; erst geschoss_aendern raeumt Platz (aus zwei Probelaeufen, nicht geschrieben)"
metadata:
  type: project
  stand: geschlossen
---

`geschoss_anlegen` rechnet die Hoehenlage allein aus `-Bezug` und `-Lage` und schreibt sie hin.
Es prueft NICHT, ob dort schon ein Geschoss steht, und es zieht darueberliegende Geschosse NICHT
nach. Nur `geschoss_aendern` rechnet die Kette nach ("alle Geschosse DARUEBER ruecken mit, deren
Bauteile werden im z verschoben").

Folge: Wer ein Geschoss zwischen zwei bestehende einschiebt — der Normalfall beim Aufstocken,
"neues OG zwischen EG und DG" — bekommt zwei Geschosse auf identischer Hoehenlage. Der Probelauf
wirft dabei keinen Fehler. Die Wandpunkte beider Geschosse truegen dann dasselbe z
(ElevationOfRefHeight ist zugleich das z der Wandpunkte), die Geschosse steckten ineinander.

Daraus folgt die Reihenfolge beim Einschieben:

1. ZUERST das darueberliegende Geschoss per `geschoss_aendern` um eine Geschosshoehe hochsetzen
   (hier DG 3.0 -> 5.8). Der Probelauf muss "n Bauteile: z um X m verschieben" melden.
2. DANN `geschoss_anlegen` fuer das neue Geschoss.
3. Dann die Waende per `geschosswaende_kopieren`.

Was daraus NICHT folgt: dass diese Reihenfolge kollisionsfrei durchlaeuft. Das ist nie geschrieben
und nie am Bestand nachgesehen worden — siehe "Nicht gemessen".

Beim Anbauen NACH OBEN (neues Geschoss ueber dem obersten) sollte das Problem nicht auftreten —
dort ist die Hoehenlage rechnerisch frei.

Der Probelauf zeigt die Kollision, aber er benennt sie nicht als Warnung: man muss die gemeldete
Hoehenlage selbst gegen die Geschosstabelle halten, die er direkt darunter ausgibt.

**Zusatzfund — der Kopfkommentar von `Set-Geschoss.ps1` steht falsch herum.** Unter "WAS ES NICHT
KANN" steht dort woertlich: "Ein Geschoss einschieben. Dafuer New-Geschoss.ps1 nehmen und die
darueber liegenden anschliessend hiermit nachziehen." Das ist genau die umgekehrte Reihenfolge —
erst einschieben, dann nachziehen —, also die, die die Kollision erzeugt. Der Kommentar gehoert
korrigiert (`C:\Projekte_Dev\energieberatung\bauteile\tools\Set-Geschoss.ps1`, Abschnitt "WAS ES
NICHT KANN"); bis dahin nicht nach ihm arbeiten.

**Beleg:** 21.08.2026, Test0001 (UUID 2c5ac804-0dcc-4560-88a7-7b8827ff69f8). Ausgangsstand:
EG Hoehenlage 0.2, DG Hoehenlage 3.0, Geschosshoehe je 2.8. Beide Schritte waren PROBELAEUFE,
geschrieben wurde nichts. Probelauf 1: `geschoss_anlegen -Name OG -Typ OG -Bezug EG -Lage darueber`
meldet woertlich "Neu: OG (FloorType 2), darueber von 'EG', Hoehenlage 3 m" — also exakt die
Hoehenlage, auf der das DG bereits steht; die mitgelieferte Geschosstabelle desselben Probelaufs
zeigt DG weiterhin auf 3. Probelauf 2: `geschoss_aendern -Geschoss DG -Hoehenlage 5.8` meldet
"DG 4 Bauteile: z um 2.8 m verschieben". In `BmFloor` steht danach unveraendert EG 0.2 und DG 3.0,
ein Geschoss namens OG existiert datenbankweit nicht. Der frueher hier behauptete Endstand
"DG 5.8 / OG 3.0 / EG 0.2" hat nie existiert und ist gestrichen.

**Nicht gemessen:** Der handlungsleitende Satz — dass die Reihenfolge "erst anheben, dann
einfuegen" kollisionsfrei anlegt — ist ungeprueft. Ein Probelauf zeigt, was das Skript vorhaette,
nicht was danach im Bestand steht; es wurde nie ausgefuehrt und nie nachgesehen. Gemessen ist
allein: die vom Probelauf gemeldete Ziel-Hoehenlage 3 m kollidiert mit dem dort stehenden DG, und
`geschoss_aendern` kuendigt die Verschiebung der 4 DG-Bauteile an. Geschlossen (nicht gemessen)
sind ausserdem: dass Anbauen nach oben unproblematisch ist (aus der Rechenregel Hoehenlage =
Hoehenlage darunter + Geschosshoehe), und dass die Wandpunkte ihr z aus ElevationOfRefHeight
beziehen (aus einem anderen Eintrag uebernommen).

**Why:** Ein stiller Fehler der teuersten Sorte: alle Zeilen stehen korrekt da, der Vergleich ist
sauber, und das Gebaeude haette trotzdem zwei ineinandersteckende Geschosse. Auffallen wuerde es
erst in der Kubatur oder gar erst in der Bilanz. Beim Aufstocken ist das Einschieben der Regelfall,
nicht die Ausnahme. Und die einzige Stelle, an der ein Bearbeiter die Reihenfolge nachschlagen
wuerde — der Kopfkommentar von `Set-Geschoss.ps1` — raet derzeit zur falschen.

**How to apply:** Vor jedem `geschoss_anlegen` die Zielhoehenlage aus dem Probelauf gegen die
vorhandenen Hoehenlagen aus `projekt_lesen` halten. Ist sie belegt, erst `geschoss_aendern` am
darueberliegenden Geschoss, dann anlegen — nie umgekehrt, sonst muesste man zwei gleich hohe
Geschosse auseinandersortieren. Weil die Wirkung dieser Reihenfolge nicht gemessen ist: nach dem
ersten scharfen Durchlauf `BmFloor` auszaehlen (Hoehenlagen aller Geschosse) und diesen Eintrag
auf "gemessen" heben oder korrigieren.
