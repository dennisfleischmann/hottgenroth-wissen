---
name: hottcad-walmdach-ist-ein-element
description: "Ein Walmdach ist EIN Element type='HippedRoof' mit 4 Kantenmittelpunkten, nicht vier Polygonal-Ebenen; BmElement.Slope traegt dabei den Sentinel"
metadata:
  type: project
  stand: geschlossen
---

Die offene Frage aus hottgenroth-dachtypen-stand ('vier Polygonal-Ebenen oder etwas anderes?') ist beantwortet: ETWAS ANDERES. Alles Folgende steht auf genau ZWEI Exemplaren im Bestand, beide auf 45 Grad.

1. Ein Walmdach ist EIN einziges roof-Element, <Roof count="1">, type="HippedRoof". Es gibt KEIN plane_definition und keine Geometrie je Flaeche. HottCAD rechnet alle vier Flaechen, Grate und First selbst.

2. <points count="4"> sind NICHT die Umrissecken, sondern die vier KANTENMITTELPUNKTE des umschliessenden Rechtecks, also ein Kreuz aus Laengs- und Querachse: (xmin,ycen) (xmax,ycen) (xcen,ymin) (xcen,ymax). Nachgerechnet an beiden Exemplaren, Mittelpunkte beider Achsen fallen exakt zusammen. Das z aller vier Punkte ist gleich; ob dieses z immer die Traufhoehe ist, traegt nur EINES der beiden Exemplare - beim anderen faellt es nicht mit der Traufhoehe zusammen. Also: gleiches z annehmen, Traufhoehe nicht voraussetzen. Das ist eine voellig andere Konvention als bei Polygonal, wo die Ecken des 3D-Umrisses stehen.

3. BmElement.Slope traegt bei HippedRoof den SENTINEL -987654321.99, nicht die Gradzahl. Bei Polygonal steht dort die Neigung in Grad (50, 10, 45, 30 ...), bei Flat 0. Die Neigung eines Walmdachs steht ausschliesslich im XML-Attribut slope, im Bogenmass. Nur 4 von 52 Daechern fuehren ueberhaupt ein slope-Attribut im roof-Tag: die 2 HippedRoof (0.785398163397448 = 45 Grad) und die 2 Assistant (0.663225 = 38 Grad).

4. Als Unterscheidungsmerkmal im XML taugt genau EIN Attribut: slope_entered="True". Es kommt nur bei HippedRoof vor. Die frueher hier gelisteten Begleiter unterscheiden NICHT:
   - gable_mode und gable_mode2 (beide "OrthogonalToPlane") fuehren ALLE 52 Daecher im Bestand, jeden Typs.
   - flap_tile und half_hipped_width="2" fuehren neben den HippedRoof auch alle 8 Flachdaecher.
   - ridge_height fuehren beide HippedRoof (siehe 5.), ob ausschliesslich, ist nicht ausgezaehlt.
   Wer ein Walmdach an gable_mode oder half_hipped_width erkennen will, erkennt jedes zweite Dach als Walmdach.

5. ridge_height ist an beiden Exemplaren konsistent: ridge_height = (halbe kurze Spannweite - d), wobei d der dritte Wert in flap_tile ist. Exemplar 1: halbe Spannweite 3.78550, d 0.25000, ridge_height 3.53550 - Treffer auf 14 Nachkommastellen. Exemplar 2: 3.83900 - 0.042768 = 3.796232, ridge_height 3.79623.

WICHTIGE GRENZE: Beide Exemplare stehen auf exakt 45 Grad. Weil tan(45)=1 ist, laesst sich aus ihnen NICHT ablesen, ob ridge_height mit tan(slope) skaliert oder wie es bei anderen Neigungen zu rechnen ist. Fuer jede Neigung ausser 45 Grad gibt es im ganzen Bestand kein Muster.

Ausserdem: es gibt KEIN Werkzeug fuer Walmdaecher. New-Satteldach.ps1 und New-Dach.ps1 erzeugen ausschliesslich Polygonal-Ebenen.

**Beleg:** Ausgezaehlt 2026 in HsetuPrjData ueber alle CADXMLData-Zeichnungen mit '<roof '. Verteilung roof/@type: Polygonal 40, Flat 8, HippedRoof 2, Assistant 2. Die beiden HippedRoof stehen an den Zeilen mit ReferenceUUID b544f648-1e72-4338-adb2-4cf9f1b39307 (Projekt Test123) und 4d97edc6-69fa-4630-b988-2693e4a9e73a (Test123_1) - ReferenceUUID ist der Zeilenschluessel, BmData.UUID bezeichnet nur die Datenart und adressiert die Zeile nicht. Beide XML im Rohtext gelesen. Die Zahlen 52, 40, 8, 2, 2 sowie die Zaehlungen in Punkt 4 sind ausgezaehlt.

**Nicht gemessen:** Ausgezaehlt ist die Typverteilung und welches Attribut wie oft vorkommt. GESCHLOSSEN, nicht gemessen, ist alles, was aus den zwei vorhandenen HippedRoof verallgemeinert wird: die Konvention 'points = Kantenmittelpunkte' (an 2 Faellen nachgerechnet), die Formel ridge_height = halbe kurze Spannweite - flap_tile[3] (an 2 Faellen, beide 45 Grad, Exemplar 2 nur auf 6 Stellen), und dass der Sentinel -987654321.99 bei JEDEM HippedRoof steht und nicht nur bei diesen beiden. Die Ausschliesslichkeit von ridge_height ist gar nicht geprueft. 'z aller vier Punkte gleich' ist an beiden Faellen gesehen; 'z = Traufhoehe' gilt nur an einem und ist damit widerlegt, nicht bestaetigt.

**Why:** Wer ein Walmdach als vier Polygonal-Flaechen nachbaut, erzeugt ein Gebilde, das HottCAD so nie geschrieben haette - es sieht in der Datenbank plausibel aus und ist strukturell ein anderer Dachtyp. Wer BmElement.Slope mit der Gradzahl fuellt statt mit dem Sentinel, weicht ebenfalls vom gemessenen Muster ab. Und wer beim Suchen oder Pruefen auf gable_mode, flap_tile oder half_hipped_width abstellt, greift Dutzende Nicht-Walmdaecher mit ab. Alle drei sind stille Fehler.

**How to apply:** Walmdach nicht aus Polygonal-Flaechen zusammensetzen. Zum Erkennen im XML slope_entered="True" pruefen, sonst nichts. Fuer ein Walmdach bei 45 Grad liegt ein vollstaendig vermessenes Muster vor, das sich als Zeilenkopie nachbauen liesse - beim Kopieren z aller vier Punkte gleich setzen, aber nicht ungeprueft auf die Traufhoehe legen. Fuer JEDE andere Neigung, etwa die haeufig verlangten 40 Grad, fehlt die Regel fuer ridge_height - dann einen Menschen bitten, ein Walmdach mit dieser Neigung einmal in HottCAD zu bauen, und daran messen.
