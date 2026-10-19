// Legt eine vollstaendige Anlagentechnik nach DIN 18599 in einem Projekt an -
// Heizung, Speicher, Warmwasser - aus dem Format, das ibp-anlage-lesen.exe
// ausgibt.
//
//   ibp-anlage-setzen.exe <blob-rein> <blob-raus> <anlage.json>
//
// Damit wird "Anlage aus Projekt A nach Projekt B uebernehmen" zum Zweizeiler:
//
//   ibp-anlage-lesen.exe  A.bin > anlage.json
//   ibp-anlage-setzen.exe B.bin B-neu.bin anlage.json
//
// Woher das JSON stammt, ist unerheblich - aus einem Projekt oder aus einer
// externen Quelle.
//
// Vier Dinge, die je einen Fehlschlag gekostet haben:
//
//  * pID darf NICHT leer sein. Sonst legt die Fabrik das Objekt an, gibt es
//    zurueck - und traegt es nicht in die Sammlung ein, ohne Fehlermeldung.
//    Ob die Kennung frei war, verraet nur das Wachstum der Sammlung.
//  * Die Beziehungsmatrix UnitCircuitInterrelation traegt die Verknuepfung
//    Einheit <-> Kreis. Ohne sie rechnet die Software 0,01 kW und schreibt
//    "Keine Heizung vorhanden".
//  * Die Leitungsart (HdPipeType) entscheidet ueber die Laenge, die das Modell
//    aus der Geometrie ableitet. Ohne sie sind alle Leitungen Verteilleitung.
//  * Die b*_Standard-Flags bleiben auf True. Sie auszuschalten und Kennwerte
//    von Hand zu setzen macht die Oberflaeche unbrauchbar.
//
// Pooltypen werden immer NEU angelegt, nie aus dem Bestand gegriffen: in einem
// Projekt mit Warmwasser haette der Heizkreis sonst dessen Leitungstypen
// abgeraeumt.
//
//   csc /platform:x64 /r:System.Web.Extensions.dll /out:ibp-anlage-setzen.exe IbpAnlageSetzen.cs

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;
using System.Web.Script.Serialization;

internal static class IbpAnlageSetzen
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    private static object bau;          // DIN18599Building
    private static object heizEinheit;  // fuer die Verknuepfung des Warmwassers
    private static object heizErzeuger; // dito - der Kessel, der das WW mitmacht
    // Auslegungstemperatur des HEIZKREISES. Sie ist der eine massgebliche Wert:
    // die Oberflaeche zeigt ihn an, und die Uebertemperatur der Uebergabe wird
    // aus ihm gerechnet. 70/55 ist der Vorgabewert des Modells - erhoben an 84
    // realen Projekten der LocalDB, siehe DIN18599-ANLAGENTECHNIK.md.
    private static float vorlauf = 70, ruecklauf = 55;
    private static bool auslegungGesetzt;   // sonst Kreis nicht anfassen
    private static bool waermepumpe;        // steuert die Vorgabe zum Abgleich

    private static int Main(string[] args)
    {
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        if (args.Length < 3)
        {
            Console.Error.WriteLine("ibp-anlage-setzen.exe <rein> <raus> <anlage.json>");
            return 2;
        }

        var json = (Dictionary<string, object>) new JavaScriptSerializer()
            .DeserializeObject(File.ReadAllText(args[2]));

        using (var s = File.OpenRead(args[0])) bau = new BinaryFormatter().Deserialize(s);
        Console.WriteLine("vorher : " + Stand(bau));

        var zone = Element(Hole(bau, "Zones"), 0);
        if (zone == null) { Console.Error.WriteLine("Keine Zone - ohne Zone keine Uebergabe."); return 1; }
        var zoneID = (string) Hole(zone, "strObjectID");
        Console.WriteLine("Zone   : " + Hole(zone, "strName") + "  " + zoneID);

        var matrix = Hole(bau, "UnitCircuitInterrelation");
        if (matrix == null) { Console.Error.WriteLine("UnitCircuitInterrelation fehlt"); return 1; }
        // Erst wegraeumen, was schon da ist. Sonst haengt das Ergebnis von der
        // Vorgeschichte ab: NewUnitDHW wirft eine NullReferenceException, wenn
        // bereits eine Warmwassereinheit existiert, und beim Heizkreis entstand
        // stillschweigend ein Doppel (WW=2, WWKreis=2). Nach dem Raeumen
        // bestimmt allein das JSON das Ergebnis - mehrfaches Ausfuehren ist
        // unschaedlich.
        // Reihenfolge ist NICHT beliebig: das Warmwasser zeigt mit
        // LinkedToHeating auf die Erzeugerkomponente der Heizung. Wer die
        // Heizung zuerst loescht, laesst einen toten Verweis zurueck, und
        // P8DHWGeneratorLinkedToHeating wirft beim naechsten Zugriff eine
        // NullReferenceException. Also Warmwasser zuerst.
        Raeume("UnitDHW", "CircuitDHW", "DeleteAllUnitsDHW", "DeleteAllCircuitsDHW", matrix);
        Raeume("UnitHeating", "CircuitHeatWater", "DeleteAllUnitsHeating", "DeleteAllCircuitsHeatWater", matrix);
        // Auch die verwaisten Pooltypen wegraeumen. Sonst haeufen sie sich bei
        // jedem Lauf an - gemessen: Uebergaben 3 -> 5 -> 7, Rohre 6 -> 9 -> 12.
        // DeleteAllUnused* entfernt nur, worauf nichts mehr zeigt.
        MatrixAufraeumen(matrix);
        foreach (var m in new[] { "DeleteAllUnusedGeneratorsP58", "DeleteAllUnusedStoragesP58",
                                  "DeleteAllUnusedEmissionsP58", "DeleteAllUnusedCircuitPipesP58",
                                  "DeleteAllUnusedCircuitPumpsP58" })
            Ruf(bau, m);
        Console.WriteLine("geraeumt: " + Stand(bau));

        var matrixVorher = Zahl(Hole(matrix, "Interrelations"));

        var erwartet = 0;
        if (Karte(json, "heizung") != null) { Heizung(Karte(json, "heizung"), zoneID, matrix); erwartet++; }
        if (Karte(json, "warmwasser") != null) { Warmwasser(Karte(json, "warmwasser"), zoneID, matrix); erwartet++; }

        Console.WriteLine();
        Console.WriteLine("nachher: " + Stand(bau));

        using (var s = File.Create(args[1])) new BinaryFormatter().Serialize(s, bau);
        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);

        var m2 = Zahl(Hole(Hole(erneut, "UnitCircuitInterrelation"), "Interrelations"));
        var ok = m2 == matrixVorher + erwartet;
        Console.WriteLine("geprueft: Matrix " + matrixVorher + " -> " + m2
            + " (erwartet +" + erwartet + ")   " + Stand(erneut));
        Console.WriteLine("          " + (ok ? "vollstaendig" : "UNVOLLSTAENDIG"));
        return ok ? 0 : 1;
    }

    // ------------------------------------------------------------- Raeumen

    /// <summary>
    /// Entfernt eine vorhandene Einheit samt Kreis. Erst die KOMPONENTEN, dann
    /// die Huellen: das Loeschen der Einheit allein gibt die Verweise auf die
    /// Pooltypen nicht frei, deren iReferenceCount bleibt auf 1, und
    /// DeleteAllUnused* laesst den Typ dann stehen.
    /// </summary>
    /// <summary>
    /// Entfernt Beziehungen, deren Einheit oder Kreis es nicht mehr gibt.
    ///
    /// Noetig, weil das Loeschen einer Einheit ihre Beziehungen NICHT mitnimmt.
    /// Nach einem ibp-delete-heating bleiben sie als Leichen stehen, und die
    /// Zaehlung "vorher + erwartet" geht nicht mehr auf. Welche Kennungen noch
    /// gueltig sind, wird aus dem Modell erhoben - alle Sammlungen, die Unit
    /// oder Circuit heissen -, nicht aus einer festen Liste.
    /// </summary>
    private static void MatrixAufraeumen(object matrix)
    {
        var gueltig = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in bau.GetType().GetProperties(Sicht)
                 .Where(x => x.CanRead && x.GetIndexParameters().Length == 0)
                 .Where(x => x.Name.StartsWith("Unit") || x.Name.StartsWith("Circuit")))
        {
            object w; try { w = p.GetValue(bau, null); } catch { continue; }
            for (var i = 0; i < Zahl(w); i++)
            {
                var id = Hole(Element(w, i), "strObjectID") as string;
                if (id != null) gueltig.Add(id);
            }
        }

        // DeleteRelation taugt hier NICHT: es ruft intern GetUnit(pID) auf und
        // wirft eine NullReferenceException, sobald die Einheit fehlt - also
        // genau in dem Fall, den wir aufraeumen wollen. Der Eintrag wird
        // deshalb direkt aus der IBPHashtable entfernt, ueber ihren Schluessel.
        var innen = Hole(matrix, "Interrelations");
        var tot = new List<string>();
        for (var i = 0; i < Zahl(innen); i++)
        {
            var e = Element(innen, i);
            var u = Hole(e, "strIDUnit") as string;
            var k = Hole(e, "strIDCircuit") as string;
            if (u != null && k != null && gueltig.Contains(u) && gueltig.Contains(k)) continue;
            var schluessel = Ruf(innen, "GetKeyAt", i) as string;
            if (schluessel != null) tot.Add(schluessel);
        }
        foreach (var s in tot) Ruf(innen, "Remove", s);
        if (tot.Count > 0) Console.WriteLine("  " + tot.Count + " verwaiste Matrixbeziehung(en) entfernt");
    }

    private static void Raeume(string einheitSammlung, string kreisSammlung,
                               string einheitWeg, string kreisWeg, object matrix)
    {
        var einheit = Element(Hole(bau, einheitSammlung), 0);
        if (einheit == null && Zahl(Hole(bau, kreisSammlung)) == 0) return;

        if (einheit != null)
        {
            Weg(einheit, "Generators", "DeleteGenerator");
            Weg(einheit, "Storage", "DeleteStorage");
            var id = (string) Hole(einheit, "strObjectID");
            if (id != null) Ruf(matrix, "DeleteAllRelationsOfUnit", id);
        }
        var kreis = Element(Hole(bau, kreisSammlung), 0);
        if (kreis != null)
        {
            Weg(kreis, "Emissions", "DeleteEmission");
            Weg(kreis, "Distributions", "DeleteDistribution");
            var id = (string) Hole(kreis, "strObjectID");
            if (id != null) Ruf(matrix, "DeleteAllRelationsOfCircuit", id);
        }
        Ruf(bau, einheitWeg);
        Ruf(bau, kreisWeg);
    }

    // Duldet einen bereits beschaedigten Graphen. Ein Warmwassererzeuger, dessen
    // LinkedToHeating-Ziel schon geloescht wurde, wirft beim Aufraeumen eine
    // NullReferenceException aus dem Modell heraus. Das darf den ganzen Lauf
    // nicht abbrechen - die Einheit wird gleich darauf ohnehin als Ganzes
    // entfernt.
    private static void Weg(object wirt, string sammlung, string methode)
    {
        var s = Hole(wirt, sammlung);
        for (var i = Zahl(s) - 1; i >= 0; i--)
        {
            var k = Element(s, i);
            var id = (string) Hole(k, "strObjectID");
            if (id == null) continue;
            try { Ruf(wirt, methode, id); }
            catch (Exception e)
            {
                var u = e.InnerException ?? e;
                Console.Error.WriteLine("  ! " + methode + "(" + id + ") : " + u.GetType().Name
                    + " - beschaedigter Verweis, wird mit der Einheit entfernt");
            }
        }
    }

    // ------------------------------------------------------------- Heizung

    private static void Heizung(Dictionary<string, object> h, string zoneID, object matrix)
    {
        var einheit = Neu(bau, "NewUnitHeating", "P5HeatGenerationUnit", "Heizwärme-Erzeugung", bau, "UnitHeating");
        heizEinheit = einheit;

        // Die Auslegungstemperatur gehoert zum HEIZKREIS, nicht zum Erzeuger.
        // Ein Projekt der Erhebung fuehrt Kreis 80/60 neben Kessel 70/55, ein
        // weiteres Kreis 66/51 neben Kessel 70/55 - die Werte sind unabhaengig,
        // und die Uebertemperatur der Uebergabe folgt in beiden Faellen dem
        // KREIS. Deshalb steht sie hier eine Ebene ueber den Erzeugern.
        // Der Rueckgriff auf den ersten Erzeuger haelt aeltere
        // Austauschdateien gueltig, die sie noch dort tragen.
        var auslegung = Karte(h, "auslegung");
        var ersterErzeuger = Liste(h, "erzeuger").FirstOrDefault();
        vorlauf = Komma(auslegung, "vorlauf", Komma(ersterErzeuger, "vorlauf", 70));
        ruecklauf = Komma(auslegung, "ruecklauf", Komma(ersterErzeuger, "ruecklauf", 55));

        // Ohne Angabe bleibt der Kreis unangetastet. Der Vorgabewert 0/0 heisst
        // "nie gesetzt" und ist nicht dasselbe wie eine ausdrueckliche 70/55:
        // wer ihn ungefragt fuellt, macht aus einem unberuehrten Projekt eines
        // mit gesetzter Auslegung. Fuer die Uebertemperatur wird 0/0 aber wie
        // 70/55 gerechnet - so wie es die Software auch tut.
        auslegungGesetzt = auslegung != null;

        foreach (var e in Liste(h, "erzeuger"))
        {
            // Die Bauart entscheidet ueber die Fabrik. Alle Bauarten sind
            // zweistufig aufgebaut - Pooltyp am Gebaeude, Komponente an der
            // Einheit - und die Fabriken heissen durchgaengig
            // NewHeatGenerator<Bauart> und NewGenerator<Bauart>.
            //   HpHeatPumpType  0 AirToWater  2 BrineToWater  3 WaterToWater
            //                   6 ExhaustToWater
            var art = Fabrikname(e, "bauart", "NewHeatGenerator", "NewGenerator", "Erzeuger");
            var wp = art.Contains("HeatPump");
            if (wp) waermepumpe = true;

            var typ = Neu(bau, "NewHeatGenerator" + art, "Erzeugertyp", bau, "P58Generators");

            // Nur setzen, was die Austauschdatei auch mitbringt. Fruehere
            // Fassungen schrieben enumBoilerType als Vorgabe - an einer
            // Solaranlage gibt es das Feld nicht, und der Erzeuger waere
            // stillschweigend halb konfiguriert gewesen.
            if (e.ContainsKey("wp_typ")) Setze(typ, "enumHeatPumpType", (short) Ganz(e, "wp_typ", 0));
            if (e.ContainsKey("typ")) Setze(typ, "enumBoilerType", (short) Ganz(e, "typ", 3));
            if (e.ContainsKey("zusatz")) Setze(typ, "enumBoilerTypeAdditional", (short) Ganz(e, "zusatz", 1));
            if (e.ContainsKey("baujahr")) Setze(typ, "sGeneratorAge", (short) Ganz(e, "baujahr", 2000));

            var k = Neu(einheit, "NewGenerator" + art, "Erzeuger", einheit, "Generators");
            Setze(k, "Generator", typ);
            Setze(k, "strEnergySource", Text(e, "brennstoff", "Brennstoff_ErdgasH"));
            var kw = Komma(e, "leistung_kw", 0);
            if (kw > 0) Setze(k, "fQdot_N", kw);
            // Eigene Auslegung des Erzeugers - NICHT die des Kreises. Fehlt sie
            // im JSON, bleibt der Vorgabewert der Fabrik stehen, so wie es die
            // Software auch tut: sie laesst den Kessel auf 70/55, wenn der
            // Anwender nur die Auslegungstemperatur des Kreises aendert.
            if (e.ContainsKey("vorlauf")) Setze(k, "ftheta_VA", Komma(e, "vorlauf", 70));
            if (e.ContainsKey("ruecklauf")) Setze(k, "ftheta_RA", Komma(e, "ruecklauf", 55));

            // Die Senkentemperatur der Waermepumpe (ftheta_si_out/in) NICHT aus
            // der Auslegung ableiten. In allen 24 Waermepumpenprojekten der
            // Erhebung steht sie auf 60/50, auch dort wo der Kreis 35/28 fuehrt
            // - die Software fasst sie nie an, sie beschreibt den Pruefpunkt
            // der Kennlinie. Wer sie mitzieht, verbessert die Arbeitszahl
            // gegenueber dem, was die Software selbst rechnen wuerde.
            // Deshalb nur auf ausdrueckliche Angabe.
            if (wp && e.ContainsKey("senke_vorlauf"))
            {
                Setze(k, "ftheta_si_out", Komma(e, "senke_vorlauf", 60));
                Setze(k, "ftheta_si_in", Komma(e, "senke_ruecklauf", 50));
            }
            if (heizErzeuger == null) heizErzeuger = k;
            Console.WriteLine("  Erzeuger: " + (wp ? "Waermepumpe Typ " + Hole(typ, "enumHeatPumpType")
                    : "Kessel Typ " + Hole(typ, "enumBoilerType") + "/" + Hole(typ, "enumBoilerTypeAdditional"))
                + "  Baujahr " + Hole(typ, "sGeneratorAge") + "  " + Hole(k, "strEnergySource"));
        }

        // Speicher an der Einheit. Die Sammlung heisst Storage, nicht Storages.
        foreach (var sp in Liste(h, "speicher"))
        {
            var typ = Neu(bau, "NewHeatStorage", "P58Storage", "Speichertyp", bau, "P58Storages");
            Setze(typ, "sAgeStorage", (short) Ganz(sp, "baujahr", 2000));
            Setze(typ, "bCirculationPumpDHW", Wahr(sp, "zirkulation"));
            var k = Neu(einheit, "NewStorage", "P58StorageComponent", "Heizungsspeicher", einheit, "Storage");
            Setze(k, "Storage", typ);
            Setze(k, "bStorageGeneratorSameRoom", Wahr(sp, "gleicher_raum"));
            Console.WriteLine("  Speicher: Baujahr " + Hole(typ, "sAgeStorage"));
        }

        var kreis = Neu(bau, "NewCircuitHeatWater", "P5HeatWaterCircuit", "Verteilung", bau, "CircuitHeatWater");

        // DAS ist die Auslegungstemperatur, die die Oberflaeche in der
        // Verteilung anzeigt: sie haengt am HEIZKREIS, nicht am Erzeuger.
        // Bleibt sie auf dem Vorgabewert, steht dort 70/55 - egal was an der
        // Erzeugerkomponente oder an deren Senke gesetzt ist. An der Einheit
        // ist ftheta_VA schreibgeschuetzt, dort geht es nicht.
        if (auslegungGesetzt)
        {
            Setze(kreis, "ftheta_VA", vorlauf);
            Setze(kreis, "ftheta_RA", ruecklauf);

            // Der Schalter "niedrige Temperaturebene". Er gehoert zur
            // Auslegung dazu: die Oberflaeche setzt ihn mit, wenn im
            // Waermepumpendialog 35/28 gewaehlt wird, und ohne ihn bleibt die
            // Arbeitszahl auf dem Wert der hohen Temperaturebene - bei sonst
            // gleichen 35/28. Genau so ist es einmal passiert.
            //
            // Abgeleitet aus der Vorlauftemperatur, weil ein Vergessen hier
            // still teuer ist; mit "niedrige_temperatur" ausdruecklich
            // ueberschreibbar.
            var niedrig = auslegung != null && auslegung.ContainsKey("niedrige_temperatur")
                ? Wahr(auslegung, "niedrige_temperatur")
                : vorlauf <= 45f;
            Setze(kreis, "bLowerTemperatureLevel", niedrig);
            Console.WriteLine("  Auslegung: " + vorlauf + "/" + ruecklauf
                + " Grad am Heizkreis, niedrige Temperaturebene "
                + (niedrig ? "ja" : "nein"));
        }
        Verteilung(kreis, Karte(h, "verteilung"), "P58CircuitPipe", "P58CircuitPumps");

        // Ein Kreis kann mehrere Uebergaben fuehren - Heizkoerper und daneben
        // eine Flaechenheizung im Bad. Deshalb eine Schleife; ein einzelnes
        // Objekt statt einer Liste wird weiterhin angenommen.
        foreach (var u in ListeOderEinzel(h, "uebergabe"))
        {
            // Flaechenheizung, Heizkoerper oder eine der uebrigen Bauarten.
            // Eine Waermepumpe mit Heizkoerpern und 70/55 Grad waere fachlich
            // Unsinn - reale WP-Projekte fuehren WaterPanel mit 35/28 Grad.
            // Die Bauart kommt deshalb aus dem JSON und wird nicht geraten.
            var uebArt = Fabrikname(u, "bauart", "NewHeatEmission", null, "Übergabe");
            var uebTyp = Neu(bau, "NewHeatEmission" + uebArt, "Übergabetyp", bau, "P58Emissions");
            if (u.ContainsKey("regelung")) Setze(uebTyp, "enumControlType", (short) Ganz(u, "regelung", 3));
            // enumPositionCircuit beschreibt die Lage im Heizkreis und gibt es
            // nur am Heizkoerper - eine Flaechenheizung kennt sie nicht.
            if (uebArt == "WaterRadiator") Setze(uebTyp, "enumPositionCircuit", (short) 1);
            if (u.ContainsKey("raumhoehe")) Setze(uebTyp, "fRoomHeight", Komma(u, "raumhoehe", 3));
            var ueb = Neu(kreis, "NewEmissionHeatWater", "P5HeatEmissionComponent", "Übergabe", kreis, "Emissions");
            Setze(ueb, "Emission", uebTyp);
            // Bewusst die Zone des ZIELmodells, nicht die aus der Datei: nur so
            // laesst sich eine Anlage aus einem anderen Projekt uebernehmen,
            // ohne dass der Verweis ins Leere zeigt.
            Setze(ueb, "strIDLink", zoneID);
            Setze(ueb, "fContribution", Komma(u, "anteil", 1));
            // Uebertemperatur der Heizflaeche: mittlere Heizmitteltemperatur
            // ueber Raumtemperatur, gerechnet aus der Auslegung des KREISES.
            // Bestaetigt an 12 von 12 Projekten mit gesetztem Kreis - auch an
            // den schiefen Faellen: 80/60 -> 50, 66/51 -> 38,5, 55/45 -> 30.
            //
            // Nur fuer Heizkoerper. Bei Flaechenheizung steht das Feld in allen
            // 15 erhobenen Projekten auf 0, obwohl der Kreis dort 35/28 fuehrt:
            // die Uebertemperatur ergibt sich bei ihr aus der Heizflaeche, nicht
            // aus der Vorlauftemperatur; bei NonEnergetic ebenso. Die Formel
            // dort anzuwenden waere ein Wert, den die Software nie erzeugt.
            Setze(ueb, "fTemperatureRise", uebArt == "WaterRadiator" ? (vorlauf + ruecklauf) / 2f - 20f : 0f);
            Console.WriteLine("  Übergabe: " + uebArt + "  Regelung " + Hole(uebTyp, "enumControlType") + "  Zone " + zoneID);
        }

        Verbinde(matrix, einheit, kreis);
    }

    // ---------------------------------------------------------- Warmwasser

    private static void Warmwasser(Dictionary<string, object> w, string zoneID, object matrix)
    {
        var einheit = Neu(bau, "NewUnitDHW", "P8DHWGenerationUnit", "Warmwasser-Erzeugung", bau, "UnitDHW");

        foreach (var e in Liste(w, "erzeuger"))
        {
            var art = Text(e, "bauart", "LinkedToHeating");
            // Der haeufigste Fall im Bestand: das Warmwasser haengt am
            // Heizkessel und hat keinen eigenen Erzeuger.
            // Die DHW-Einheit erbt von P58GenerationUnit und kann deshalb auch
            // eine Waermepumpe aufnehmen - reale Projekte machen genau das,
            // statt das Warmwasser an einen Kessel zu haengen.
            if (art == "LinkedToHeating" && heizErzeuger != null
                && heizErzeuger.GetType().Name.Contains("HeatPump"))
            {
                Console.Error.WriteLine("  ! LinkedToHeating geht nur mit einem Kessel. "
                    + "Bei einer Waermepumpe braucht das Warmwasser einen eigenen Erzeuger "
                    + "(bauart HeatPump) - siehe ein reales WP-Projekt als Vorlage.");
                continue;
            }
            var fabrik = art == "HeatPump" ? "NewGeneratorHeatPump"
                       : art == "LinkedToHeating" ? "NewGeneratorLinkedToHeating"
                       : art == "Electric" ? "NewGeneratorElectric"
                       : art == "GasFlowHeater" ? "NewGeneratorGasFlowHeater"
                       : art == "HeatedStorage" ? "NewGeneratorHeatedStorage"
                       : "NewGeneratorStation";
            var k = Neu(einheit, fabrik, "P8DHWGenerator", "Erzeuger", einheit, "Generators");
            if (art == "HeatPump")
            {
                var wtyp = Neu(bau, "NewHeatGeneratorHeatPump", "P58HeatGeneratorHeatPump", "WW-Erzeugertyp", bau, "P58Generators");
                Setze(wtyp, "enumHeatPumpType", (short) Ganz(e, "wp_typ", 0));
                Setze(wtyp, "sGeneratorAge", (short) Ganz(e, "baujahr", 2000));
                Setze(k, "Generator", wtyp);
            }
            var bs = Text(e, "brennstoff", null);
            if (bs != null) Setze(k, "strEnergySource", bs);

            // LinkedToHeating heisst: das Warmwasser haengt an einem KONKRETEN
            // Kessel. Der Verweis geht auf die Erzeuger-KOMPONENTE der Heizung,
            // nicht nur auf deren Einheit - beide Kennungen sind noetig.
            if (art == "LinkedToHeating")
            {
                if (heizErzeuger == null)
                {
                    Console.Error.WriteLine("  ! LinkedToHeating ohne Heizung - kein Erzeuger zum Anhaengen");
                }
                else
                {
                    // LinkedUnit NICHT setzen - die Eigenschaft ist
                    // schreibgeschuetzt, und das Modell traegt sie beim Setzen
                    // von LinkedGenerator selbst nach (geprueft: beide
                    // Kennungen stehen danach richtig).
                    Setze(k, "LinkedGenerator", heizErzeuger);
                    Console.WriteLine("  WW-Erzeuger: " + art + "  -> " + Hole(k, "strLinkedGeneratorID"));
                    continue;
                }
            }
            Console.WriteLine("  WW-Erzeuger: " + art);
        }

        foreach (var sp in Liste(w, "speicher"))
        {
            var typ = Neu(bau, "NewHeatStorage", "P58Storage", "Speichertyp", bau, "P58Storages");
            Setze(typ, "sAgeStorage", (short) Ganz(sp, "baujahr", 2000));
            Setze(typ, "bCirculationPumpDHW", Wahr(sp, "zirkulation"));
            var k = Neu(einheit, "NewStorage", "P58StorageComponent", "Warmwasserspeicher", einheit, "Storage");
            Setze(k, "Storage", typ);
            Console.WriteLine("  WW-Speicher: Baujahr " + Hole(typ, "sAgeStorage"));
        }

        var kreis = Neu(bau, "NewCircuitDHW", "P8DHWCircuit", "DHWKreis", bau, "CircuitDHW");
        var uebTyp = Neu(bau, "NewDHWEmission", "P8DHWEmission", "WW-Übergabetyp", bau, "P58Emissions");
        var ueb = Neu(kreis, "NewEmissionDHW", "P8DHWEmissionComponent", "WW-Übergabe", kreis, "Emissions");
        Setze(ueb, "Emission", uebTyp);
        Setze(ueb, "strIDLink", zoneID);
        Setze(ueb, "fContribution", 1f);

        // Verteilung des Warmwasserkreises. Sie wurde hier lange gar nicht
        // angelegt - der Reiter "Verteilung" beim Warmwasser blieb leer, und
        // weil der Leser sie ebenfalls nicht kannte, fiel es keinem Rundlauf
        // auf. Vorgaben: ohne Zirkulation, zentral ueber Steigestrang,
        // Gruppe 1. Genau so fuehren es die Waermepumpenprojekte der Erhebung.
        //   HdNetTypeDHW       0 Steigestraenge, 1 Etage, 2 dezentral
        //   HdCirculationType  0 mit, 1 ohne Zirkulation, 2 Begleitheizung
        //   HdDistributionType 0 zentral, 1 dezentral
        // Nur anlegen, wenn die Austauschdatei eine beschreibt. Werner Grotz
        // fuehrt Warmwasser OHNE Verteilung - ein Zustand, den die Software
        // selbst erzeugt hat. Sie ungefragt zu ergaenzen waere dieselbe Art
        // Erfindung wie ein Vorgabewert an einer nie gesetzten Stelle, nur mit
        // freundlicherem Vorzeichen.
        var wv = Karte(w, "verteilung");
        if (wv == null)
        {
            Console.WriteLine("  WW-Verteilung: keine angegeben, keine angelegt");
            Verbinde(matrix, einheit, kreis);
            return;
        }
        var wvert = Neu(kreis, "NewDistribution", "WW-Verteilung", kreis, "Distributions");
        Setze(wvert, "enumNetTypeDHW", (short) Ganz(wv, "netz", 0));
        Setze(wvert, "enumCirculation", (short) Ganz(wv, "zirkulation", 1));
        Setze(wvert, "enumBuildingGroup", (short) Ganz(wv, "gruppe", 0));
        Setze(wvert, "enumDistributionType", (short) Ganz(wv, "zentral", 0));
        if (wv != null && wv.ContainsKey("system"))
            Setze(wvert, "enumDHWSystemType", (short) Ganz(wv, "system", 0));
        Console.WriteLine("  WW-Verteilung: Netz " + Hole(wvert, "enumNetTypeDHW")
            + ", Zirkulation " + Hole(wvert, "enumCirculation")
            + ", Gruppe " + Hole(wvert, "enumBuildingGroup"));

        Verbinde(matrix, einheit, kreis);
    }

    // ------------------------------------------------------------- Bausteine

    private static void Verteilung(object kreis, Dictionary<string, object> v, string rohrTyp, string pumpenPool)
    {
        var vert = Neu(kreis, "NewDistribution", "P5HeatDistribution", "Verteilung", kreis, "Distributions");
        Setze(vert, "enumNetworkType", (short) Ganz(v, "netz", 1));
        Setze(vert, "fGamma", Komma(v, "gamma", 0.35f));
        Setze(vert, "sNumberOfRadiators", (short) Ganz(v, "heizkoerper", 1));

        // Hydraulischer Abgleich. Er gehoert bei einer Waermepumpensanierung
        // immer dazu - fachliche Vorgabe, und die Software haelt sich daran:
        // in allen 24 Waermepumpenprojekten der Erhebung steht an der
        // Verteilung HdHydraulicBalance = 2 (Option3), bei Kesseln dagegen
        // ueberwiegend 0. Deshalb ist er hier bei Waermepumpen voreingestellt
        // und laesst sich mit "abgleich" ausdruecklich anders setzen.
        var abgleich = Ganz(v, "abgleich", waermepumpe ? 2 : 0);
        Setze(vert, "enumHydraulicBalance", (short) abgleich);

        // Netzform und Gebaeudegruppe. Vorgabe Etagenring / Gruppe 1: so
        // fuehren es 22 der 24 Waermepumpenprojekte der Erhebung.
        //   HdNetTypeHeating 0 Etagenring, 1 Etagenverteilung,
        //   2 Steigestraenge, 3 Strahlungs-/Luftheizung, 4 Fussboden
        if (v != null && v.ContainsKey("netz_heizung"))
            Setze(vert, "enumNetworkTypeHeating", (short) Ganz(v, "netz_heizung", 0));
        if (v != null && v.ContainsKey("gruppe"))
            Setze(vert, "enumBuildingGroup", (short) Ganz(v, "gruppe", 0));

        foreach (var l in Liste(v, "leitungen"))
        {
            var typ = Neu(bau, "NewHeatingCircuitPipe", rohrTyp, "Leitungstyp", bau, "P58CircuitPipes");
            Setze(typ, "enumPipeInsulation", (short) Ganz(l, "daemmung", 2));
            var k = Neu(vert, "NewPipe", "P58CircuitPipeComponent", "Leitung", vert, "Pipes");
            Setze(k, "Pipe", typ);
            Setze(k, "enumPipeType", (short) Ganz(l, "art", 0));
            Setze(k, "enumPositionType", (short) Ganz(l, "lage", 1));
        }
        Console.WriteLine("  Verteilung: " + Zahl(Hole(vert, "Pipes")) + " Leitungen");

        // Das Kreuz an der Pumpe gehoert zur Aufzaehlung an der Verteilung:
        // 18 von 18 Waermepumpenprojekten mit Pumpe fuehren beides gemeinsam.
        // Nur eines von beiden zu setzen waere ein halb abgeglichenes System.
        var pumpeAbgleich = v != null && v.ContainsKey("abgleich_pumpe")
            ? Wahr(v, "abgleich_pumpe")
            : abgleich != 0;

        var pumpen = v == null ? 1 : Ganz(v, "pumpen", 1);
        for (var i = 0; i < pumpen; i++)
        {
            var typ = Neu(bau, "NewHeatingCircuitPump", "P58CircuitPump", "Pumpentyp", bau, pumpenPool);
            var k = Neu(vert, "NewPump", "P58CircuitPumpComponent", "Pumpe", vert, "Pumps");
            Setze(k, "Pump", typ);
            Setze(k, "bHydraulicBalance", pumpeAbgleich);
            // Regelung und Auslegung der Pumpe.
            //   HdPumpControl      0 ungeregelt, 1 delta-p konstant,
            //                      2 delta-p variabel
            //   HdDimensioningPump 0 ueberdimensioniert, 1 optimiert
            // Eine neu eingebaute Pumpe ist ausgelegt, nicht ueberdimensioniert
            // - alle 24 Waermepumpenprojekte der Erhebung fuehren "optimiert".
            if (v != null && v.ContainsKey("pumpe_regelung"))
                Setze(k, "enumPumpControl", (short) Ganz(v, "pumpe_regelung", 1));
            if (v != null && v.ContainsKey("pumpe_auslegung"))
                Setze(typ, "enumDimensioningPump", (short) Ganz(v, "pumpe_auslegung", 1));
        }
        if (abgleich != 0 || pumpeAbgleich)
            Console.WriteLine("  Hydraulischer Abgleich: Verteilung " + abgleich
                + ", Pumpe " + (pumpeAbgleich ? "ja" : "nein"));
    }

    private static void Verbinde(object matrix, object einheit, object kreis)
    {
        Ruf(matrix, "AddRelation", (string) Hole(einheit, "strObjectID"),
                                   (string) Hole(kreis, "strObjectID"), 1f);
        Anhaengen(Hole(einheit, "alReferenceList"), (string) Hole(kreis, "strObjectID"));
        Anhaengen(Hole(kreis, "alReferenceList"), (string) Hole(einheit, "strObjectID"));
        Console.WriteLine("  Matrix  : " + Hole(einheit, "strObjectID") + " <-> " + Hole(kreis, "strObjectID"));
    }

    // ------------------------------------------------------------ Werkzeuge

    // Fassung ohne Typnamen: er ist der Rueckgabetyp der Fabrik und wird beim
    // Modell erfragt. Noetig, seit die Fabrik selbst aus der Bauart entsteht -
    // sonst muesste zu jedem "NewHeatGenerator<X>" der Klassenname von Hand
    // danebenstehen, und die Vorsaetze sind unregelmaessig (P5, P58, P6).
    private static object Neu(object wirt, string fabrik, string bezeichnung,
                              object besitzer, string sammlung)
    {
        var m = wirt.GetType().GetMethod(fabrik, Sicht, null,
                    new[] { typeof(string), typeof(string) }, null);
        if (m == null) throw new InvalidOperationException("Fabrik " + fabrik + " gibt es nicht");
        return Neu(wirt, fabrik, m.ReturnType.Name, bezeichnung, besitzer, sammlung);
    }

    private static object Neu(object wirt, string fabrik, string typname, string bezeichnung,
                              object besitzer, string sammlung)
    {
        for (var nr = 1; nr < 1000; nr++)
        {
            var vorher = Zahl(Hole(besitzer, sammlung));
            var o = Ruf(wirt, fabrik, Kennung(typname, nr), bezeichnung + " " + nr);
            if (Zahl(Hole(besitzer, sammlung)) > vorher) return o;
        }
        throw new InvalidOperationException("keine freie Kennung fuer " + typname);
    }

    private static string Kennung(string typ, int nr)
    {
        unchecked
        {
            uint h = 2166136261;
            foreach (var c in typ + "_" + nr) { h ^= c; h *= 16777619; }
            return typ + "_" + nr + "[" + h.ToString("X8") + "]";
        }
    }

    // Loest eine Bauart aus der Austauschdatei zu einem Fabriknamen auf.
    //
    // Frueher stand hier "wp = art == \"HeatPump\"", sonst Kessel. Damit wurde
    // aus jeder unbekannten Bauart still ein Kessel: eine Solaranlage, ein
    // Einzelofen, eine Sorptionswaermepumpe. Beim Rundlauf ueber 84 Projekte
    // traf das 13 Stueck, ohne eine einzige Meldung. Genau diese Klasse Fehler
    // - ein Wert wird durch einen Vorgabewert ersetzt, und niemand merkt es -
    // ist der Grund fuer diese Funktion: was nicht aufloesbar ist, wird
    // abgebrochen, nicht ersetzt.
    //
    // Die Zuordnung ist nicht eingetragen, sondern gemessen: die Fabriken am
    // Modell heissen New<Vorsatz><Bauart>, und ihr Rueckgabetyp nennt die
    // Klasse. Beides wird zur Laufzeit erfragt. Angenommen wird sowohl der
    // kurze Name ("HeatPump") als auch der volle Klassenname
    // ("P58HeatGeneratorHeatPump"), damit aeltere Austauschdateien gelten.
    private static string Fabrikname(Dictionary<string, object> d, string schluessel,
                                     string vorsatz, string vorsatzKomponente, string wofuer)
    {
        var gewuenscht = Text(d, schluessel, null);
        var moeglich = new List<string>();

        foreach (var m in bau.GetType().GetMethods(Sicht))
        {
            if (!m.Name.StartsWith(vorsatz) || m.GetParameters().Length != 2) continue;
            var kurz = m.Name.Substring(vorsatz.Length);
            if (kurz.Length == 0) continue;
            // Ohne passende Komponentenfabrik an der Einheit liesse sich der
            // Pooltyp anlegen, aber nie verwenden.
            if (vorsatzKomponente != null
                && heizEinheit.GetType().GetMethod(vorsatzKomponente + kurz, Sicht) == null) continue;
            moeglich.Add(kurz);
            if (gewuenscht == null) continue;
            if (string.Equals(kurz, gewuenscht, StringComparison.OrdinalIgnoreCase)
                || string.Equals(m.ReturnType.Name, gewuenscht, StringComparison.OrdinalIgnoreCase))
                return kurz;
        }

        if (gewuenscht == null)
            throw new InvalidOperationException(wofuer + ": keine Bauart angegeben. Moeglich: "
                + string.Join(", ", moeglich.OrderBy(x => x)));

        moeglich.Sort();
        throw new InvalidOperationException(wofuer + ": Bauart '" + gewuenscht
            + "' ist dem Modell unbekannt. Moeglich: " + string.Join(", ", moeglich));
    }

    private static Dictionary<string, object> Karte(Dictionary<string, object> d, string n)
    {
        object w;
        if (d == null || !d.TryGetValue(n, out w) || w == null) return null;
        return w as Dictionary<string, object>;
    }

    private static IEnumerable<Dictionary<string, object>> Liste(Dictionary<string, object> d, string n)
    {
        object w;
        if (d == null || !d.TryGetValue(n, out w) || w == null) yield break;
        var arr = w as object[];
        if (arr == null) yield break;
        foreach (var e in arr) { var k = e as Dictionary<string, object>; if (k != null) yield return k; }
    }

    // Nimmt beides an: eine Liste von Objekten oder ein einzelnes Objekt.
    // Der Leser schreibt heute Listen, aeltere Austauschdateien tragen dort
    // noch ein einzelnes Objekt - beide sollen gelten.
    private static IEnumerable<Dictionary<string, object>> ListeOderEinzel(
        Dictionary<string, object> d, string n)
    {
        var eines = Karte(d, n);
        if (eines != null) { yield return eines; yield break; }
        foreach (var x in Liste(d, n)) yield return x;
    }

    private static int Ganz(Dictionary<string, object> d, string n, int vorgabe)
    {
        object w;
        if (d == null || !d.TryGetValue(n, out w) || w == null) return vorgabe;
        return Convert.ToInt32(w, CultureInfo.InvariantCulture);
    }

    private static float Komma(Dictionary<string, object> d, string n, float vorgabe)
    {
        object w;
        if (d == null || !d.TryGetValue(n, out w) || w == null) return vorgabe;
        return Convert.ToSingle(w, CultureInfo.InvariantCulture);
    }

    private static string Text(Dictionary<string, object> d, string n, string vorgabe)
    {
        object w;
        if (d == null || !d.TryGetValue(n, out w) || w == null) return vorgabe;
        return w.ToString();
    }

    private static bool Wahr(Dictionary<string, object> d, string n)
    {
        object w;
        if (d == null || !d.TryGetValue(n, out w) || w == null) return false;
        return Convert.ToBoolean(w);
    }

    private static string Stand(object g)
    {
        return "Heiz=" + Zahl(Hole(g, "UnitHeating")) + " Kreis=" + Zahl(Hole(g, "CircuitHeatWater"))
            + " WW=" + Zahl(Hole(g, "UnitDHW")) + " WWKreis=" + Zahl(Hole(g, "CircuitDHW"))
            + " Erz=" + Zahl(Hole(g, "P58Generators")) + " Spei=" + Zahl(Hole(g, "P58Storages"))
            + " Ueb=" + Zahl(Hole(g, "P58Emissions")) + " Rohr=" + Zahl(Hole(g, "P58CircuitPipes"))
            + " Pump=" + Zahl(Hole(g, "P58CircuitPumps"));
    }

    private static object Ruf(object o, string name, params object[] args)
    {
        var typen = new Type[args.Length];
        for (var i = 0; i < args.Length; i++) typen[i] = args[i].GetType();
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var m = t.GetMethod(name, Sicht | BindingFlags.DeclaredOnly, null, typen, null);
            if (m != null) return m.Invoke(o, args);
        }
        throw new InvalidOperationException(name + "(" + typen.Length + ") nicht gefunden an " + o.GetType().Name);
    }

    private static void Setze(object o, string name, object wert)
    {
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var p = t.GetProperty(name, Sicht | BindingFlags.DeclaredOnly);
            if (p != null && p.CanWrite) { p.SetValue(o, wert, null); return; }
            var f = t.GetField(name, Sicht | BindingFlags.DeclaredOnly);
            if (f != null) { f.SetValue(o, wert); return; }
        }
        Console.Error.WriteLine("  ! '" + name + "' nicht schreibbar an " + o.GetType().Name);
    }

    private static object Hole(object o, string name)
    {
        if (o == null) return null;
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var p = t.GetProperty(name, Sicht | BindingFlags.DeclaredOnly);
            if (p != null && p.GetIndexParameters().Length == 0) return p.GetValue(o, null);
            var f = t.GetField(name, Sicht | BindingFlags.DeclaredOnly);
            if (f != null) return f.GetValue(o);
        }
        return null;
    }

    private static void Anhaengen(object liste, string wert)
    {
        if (liste == null) return;
        var m = liste.GetType().GetMethod("Add", new[] { typeof(object) })
             ?? liste.GetType().GetMethod("Add", new[] { typeof(string) });
        if (m != null) m.Invoke(liste, new object[] { wert });
    }

    private static object Element(object s, int i)
    {
        if (s == null || Zahl(s) <= i) return null;
        var idx = s.GetType().GetProperty("Item", new[] { typeof(int) });
        if (idx != null) return idx.GetValue(s, new object[] { i });
        var l = s as IList;
        return l != null ? l[i] : null;
    }

    private static int Zahl(object s)
    {
        if (s == null || s is string) return 0;
        var p = s.GetType().GetProperty("Count");
        if (p != null) return (int) p.GetValue(s, null);
        var a = s as Array;
        return a != null ? a.Length : 0;
    }
}
