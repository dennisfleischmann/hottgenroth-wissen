// Legt eine vollstaendige Heizungsanlage nach DIN 18599 in einem Projekt an -
// ausschliesslich ueber die Fabrikmethoden des IBP-Modells.
//
//   ibp-build-heating.exe <blob-rein> <blob-raus> [name=wert ...]
//
//     kessel=3          HgBoilerType: 2 Standard, 3 Niedertemperatur, 4 Brennwert
//     zusatz=1          HgStandardLowTemperatureBoilerType: 1 = Geblaese
//     brennstoff=Brennstoff_ErdgasH
//     leistung=14.8     kW      baujahr=2006
//     vorlauf=70        ruecklauf=55
//     zone=0            Index in Zones
//     regelung=3        HceControlType des Heizkoerpers (3 = P-Regler)
//     daemmung=2        HdPipeInsulation der Leitungen (2 = vor 1980)
//
// Aufbau (zweistufig: TYP im Pool des Gebaeudes, KOMPONENTE in der Struktur):
//
//   UnitHeating       P5HeatGenerationUnit
//     Generators      P58HeatGeneratorBoilerComponent -> P58HeatGeneratorBoiler
//   CircuitHeatWater  P5HeatWaterCircuit
//     Distributions   P5HeatDistribution -> Pipes (3), Pumps (1)
//     Emissions       P5HeatEmissionComponent -> P5HeatEmissionWaterRadiator
//   UnitCircuitInterrelation.AddRelation(Einheit, Kreis, 1)
//
// Drei Dinge, die je einen Fehlschlag gekostet haben:
//
//  * pID darf NICHT leer sein. Sonst legt die Fabrik das Objekt an, gibt es
//    zurueck - und traegt es nicht in die Sammlung ein, ohne Fehlermeldung.
//    Die Sammlungen sind IBPHashtable, also nach Kennung geschluesselt.
//  * Die Beziehungsmatrix ist der eigentliche Traeger der Verknuepfung
//    Einheit <-> Kreis. Ohne sie rechnet die Software fQdot_N = 0,01 kW und
//    schreibt "Keine Heizung vorhanden" - alReferenceList allein genuegt nicht.
//  * Die b*_Standard-Flags bleiben auf True. Sie auszuschalten und Kennwerte
//    von Hand zu setzen hat die Oberflaeche unbrauchbar gemacht.
//
// Pooltypen (Leitung, Pumpe, Heizkoerper) werden ANGELEGT, wenn sie fehlen.
// Ein Projekt ohne vorherige DIN-18599-Erfassung hat dort naemlich nichts.
//
//   csc /platform:x64 /out:ibp-build-heating.exe IbpBuildHeating.cs

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpBuildHeating
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    // Eine Heizung braucht drei Leitungsarten. HdPipeType:
    //   2 ConnectionPipe (Anbindeleitung), 1 RiserPipe (Steigstrang),
    //   0 DistributionPipe (Verteilleitung).
    // Ohne die Art sind alle drei Verteilleitung, und das Modell leitet aus der
    // Geometrie eine viel zu lange Strecke ab (gemessen: 584 m statt 27+5+195).
    private static readonly int[] Leitungsart = { 2, 1, 0 };

    private static Dictionary<string, string> P = new Dictionary<string, string>();

    private static int Main(string[] args)
    {
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        if (args.Length < 2) { Console.Error.WriteLine("ibp-build-heating.exe <rein> <raus> [name=wert ...]"); return 2; }
        foreach (var a in args.Skip(2))
        {
            var i = a.IndexOf('=');
            if (i > 0) P[a.Substring(0, i).ToLowerInvariant()] = a.Substring(i + 1);
        }

        object g;
        using (var s = File.OpenRead(args[0])) g = new BinaryFormatter().Deserialize(s);

        Console.WriteLine("vorher : " + Stand(g));

        var zonen = Hole(g, "Zones");
        var zone = Element(zonen, Ganz("zone", 0));
        if (zone == null) { Console.Error.WriteLine("Keine Zone im Modell - ohne Zone keine Uebergabe."); return 1; }
        var zoneID = (string) Hole(zone, "strObjectID");
        Console.WriteLine("Zone   : " + Hole(zone, "strName") + "  " + zoneID);
        Console.WriteLine();

        // ------------------------------------------------------- Erzeugung
        var kesselTyp = Neu(g, "NewHeatGeneratorBoiler", "P58HeatGeneratorBoiler", "Erzeugertyp", g, "P58Generators");
        Setze(kesselTyp, "enumBoilerType", (short) Ganz("kessel", 3));
        Setze(kesselTyp, "enumBoilerTypeAdditional", (short) Ganz("zusatz", 1));
        Setze(kesselTyp, "sGeneratorAge", (short) Ganz("baujahr", 2006));

        var einheit = Neu(g, "NewUnitHeating", "P5HeatGenerationUnit", "Heizwärme-Erzeugung", g, "UnitHeating");

        var kessel = Neu(einheit, "NewGeneratorBoiler", "P58HeatGeneratorBoilerComponent", "Erzeuger", einheit, "Generators");
        Setze(kessel, "Generator", kesselTyp);
        Setze(kessel, "strEnergySource", Text("brennstoff", "Brennstoff_ErdgasH"));
        Setze(kessel, "fQdot_N", Komma("leistung", 14.8f));
        Setze(kessel, "ftheta_VA", Komma("vorlauf", 70f));
        Setze(kessel, "ftheta_RA", Komma("ruecklauf", 55f));
        Console.WriteLine("Kessel : " + Hole(kessel, "strObjectID") + "  Typ " + Hole(kesselTyp, "enumBoilerType")
            + "/" + Hole(kesselTyp, "enumBoilerTypeAdditional") + "  " + Hole(kessel, "fQdot_N") + " kW  "
            + Hole(kessel, "strEnergySource"));

        // ------------------------------------------------------- Heizkreis
        var kreis = Neu(g, "NewCircuitHeatWater", "P5HeatWaterCircuit", "Verteilung", g, "CircuitHeatWater");
        var vert = Neu(kreis, "NewDistribution", "P5HeatDistribution", "Verteilung", kreis, "Distributions");
        Setze(vert, "enumNetworkType", (short) 1);          // DoublePipeNetwork
        Setze(vert, "sNumberOfRadiators", (short) 1);

        // Leitungen: je eine Anbinde-, Steig- und Verteilleitung, jede mit
        // EIGENEM Pooltyp.
        //
        // Frueher wurden hier die ersten drei vorhandenen Typen wiederverwendet.
        // Das ging nur an dem Projekt gut, in dem die Software beim Loeschen
        // genau drei passende Typen hatte liegen lassen. In einem Projekt mit
        // Warmwasser hat der Heizkreis so die WARMWASSER-Typen abgegriffen -
        // gemessen: Heizung hing an Pipe 7/8/9, der Nachbau nahm 1/2/3.
        // Ein Leitungstyp traegt die Daemmung, ein Uebergabetyp Regelung und
        // Raumhoehe. Fremde Werte zu erben ist schlimmer, als eigene anzulegen.
        for (var i = 0; i < Leitungsart.Length; i++)
        {
            var typ = Neu(g, "NewHeatingCircuitPipe", "P58CircuitPipe", "Leitungstyp", g, "P58CircuitPipes");
            Setze(typ, "enumPipeInsulation", (short) Ganz("daemmung", 2));
            var k = Neu(vert, "NewPipe", "P58CircuitPipeComponent", "Leitung", vert, "Pipes");
            Setze(k, "Pipe", typ);
            Setze(k, "enumPipeType", (short) Leitungsart[i]);
            Setze(k, "enumPositionType", (short) 1);
            Console.WriteLine("  Leitung " + (i + 1) + ": Art " + Leitungsart[i] + "  -> " + Hole(typ, "strObjectID"));
        }

        var pumpeTyp = Neu(g, "NewHeatingCircuitPump", "P58CircuitPump", "Pumpentyp", g, "P58CircuitPumps");
        var pumpe = Neu(vert, "NewPump", "P58CircuitPumpComponent", "Pumpe", vert, "Pumps");
        Setze(pumpe, "Pump", pumpeTyp);
        Console.WriteLine("  Pumpe   : -> " + Hole(pumpeTyp, "strObjectID"));

        // ------------------------------------------------------- Uebergabe
        var uebTyp = Neu(g, "NewHeatEmissionWaterRadiator", "P5HeatEmissionWaterRadiator", "Übergabetyp", g, "P58Emissions");
        Setze(uebTyp, "enumControlType", (short) Ganz("regelung", 3));   // P-Regler
        Setze(uebTyp, "enumPositionCircuit", (short) 1);
        Setze(uebTyp, "fRoomHeight", 3f);

        var ueb = Neu(kreis, "NewEmissionHeatWater", "P5HeatEmissionComponent", "Übergabe", kreis, "Emissions");
        Setze(ueb, "Emission", uebTyp);
        Setze(ueb, "strIDLink", zoneID);                    // versorgte Zone
        Setze(ueb, "fContribution", 1f);                    // 100 %
        Console.WriteLine("  Übergabe: -> " + Hole(uebTyp, "strObjectID") + "   Zone " + Hole(ueb, "strIDLink"));

        // ------------------------------------------- Einheit <-> Kreis verbinden
        var matrix = Hole(g, "UnitCircuitInterrelation");
        if (matrix == null) { Console.Error.WriteLine("UnitCircuitInterrelation fehlt"); return 1; }
        // Die Matrix fuehrt AUCH die Beziehungen von Warmwasser und Lueftung.
        // Also relativ pruefen: genau ein Eintrag mehr als vorher, nicht "== 1".
        var matrixVorher = Zahl(Hole(matrix, "Interrelations"));
        Ruf(matrix, "AddRelation", (string) Hole(einheit, "strObjectID"),
                                   (string) Hole(kreis, "strObjectID"), 1f);
        Anhaengen(Hole(einheit, "alReferenceList"), (string) Hole(kreis, "strObjectID"));
        Anhaengen(Hole(kreis, "alReferenceList"), (string) Hole(einheit, "strObjectID"));
        Console.WriteLine();
        Console.WriteLine("Matrix : " + Hole(einheit, "strObjectID") + " <-> " + Hole(kreis, "strObjectID"));

        // ------------------------------------------- schreiben und gegenlesen
        using (var s = File.Create(args[1])) new BinaryFormatter().Serialize(s, g);
        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);

        Console.WriteLine("nachher: " + Stand(erneut) + "   (" + new FileInfo(args[1]).Length + " B)");

        var e2 = Element(Hole(erneut, "UnitHeating"), 0);
        if (e2 == null) { Console.Error.WriteLine("FEHLER: Einheit nicht eingetragen"); return 1; }
        var k2 = Element(Hole(e2, "Generators"), 0);
        // Die eigene Beziehung im wieder eingelesenen Graphen suchen - nicht
        // bloss zaehlen. Zaehlen ginge schief, sobald das Projekt Warmwasser
        // oder Lueftung hat: deren Beziehungen stehen in derselben Matrix.
        var m2 = Hole(Hole(erneut, "UnitCircuitInterrelation"), "Interrelations");
        var eID = (string) Hole(Element(Hole(erneut, "UnitHeating"), 0), "strObjectID");
        var kID = (string) Hole(Element(Hole(erneut, "CircuitHeatWater"), 0), "strObjectID");
        var gefunden = false;
        for (var i = 0; i < Zahl(m2); i++)
        {
            var e = Element(m2, i);
            if ((string) Hole(e, "strIDUnit") == eID && (string) Hole(e, "strIDCircuit") == kID) gefunden = true;
        }
        Console.WriteLine("geprueft: Kessel " + Hole(Hole(k2, "Generator"), "enumBoilerType")
            + "/" + Hole(Hole(k2, "Generator"), "enumBoilerTypeAdditional")
            + "  " + Hole(k2, "fQdot_N") + " kW  Baujahr " + Hole(Hole(k2, "Generator"), "sGeneratorAge"));
        Console.WriteLine("          Matrix " + matrixVorher + " -> " + Zahl(m2)
            + "  eigene Beziehung " + (gefunden ? "vorhanden" : "FEHLT"));

        var voll = gefunden
            && Zahl(m2) == matrixVorher + 1
            && Zahl(Hole(Element(Hole(erneut, "CircuitHeatWater"), 0), "Emissions")) >= 1
            && Zahl(Hole(Element(Hole(Element(Hole(erneut, "CircuitHeatWater"), 0), "Distributions"), 0), "Pipes")) == Leitungsart.Length;
        Console.WriteLine("          Kette vollstaendig: " + (voll ? "ja" : "NEIN"));
        return voll ? 0 : 1;
    }

    // ---------------------------------------------------------------- Helfer

    // Legt ein Objekt ueber seine Fabrik an und vergibt dabei eine freie
    // Kennung nach dem Muster Typname_N[HEX8].
    //
    // Ob die Kennung frei war, laesst sich NUR am Wachstum der Sammlung
    // ablesen: ist sie vergeben, liefert die Fabrik den VORHANDENEN Eintrag
    // zurueck - und der traegt die gesuchte Kennung natuerlich auch. Ein
    // Vergleich der strObjectID geht deshalb immer gut aus. Genau daran haben
    // in einem Projekt mit leerem Pool alle drei Leitungen auf denselben Typ
    // gezeigt.
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

    private static int Ganz(string name, int vorgabe)
    {
        string w; return P.TryGetValue(name, out w) ? int.Parse(w, CultureInfo.InvariantCulture) : vorgabe;
    }

    private static float Komma(string name, float vorgabe)
    {
        string w;
        return P.TryGetValue(name, out w)
            ? float.Parse(w.Replace(',', '.'), CultureInfo.InvariantCulture) : vorgabe;
    }

    private static string Text(string name, string vorgabe)
    {
        string w; return P.TryGetValue(name, out w) ? w : vorgabe;
    }

    private static string Stand(object g)
    {
        return "Zonen=" + Zahl(Hole(g, "Zones"))
            + "  Bauteile=" + Zahl(Hole(g, "Constructions"))
            + "  Einheit=" + Zahl(Hole(g, "UnitHeating"))
            + "  Kreis=" + Zahl(Hole(g, "CircuitHeatWater"))
            + "  Erz=" + Zahl(Hole(g, "P58Generators"))
            + "  Ueberg=" + Zahl(Hole(g, "P58Emissions"))
            + "  Rohre=" + Zahl(Hole(g, "P58CircuitPipes"))
            + "  Pumpen=" + Zahl(Hole(g, "P58CircuitPumps"));
    }

    // Mit Parametertypen suchen: die Modellmethoden sind durchweg ueberladen
    // (AddRelation gibt es dreimal), und GetMethod ohne Typen wirft dann eine
    // AmbiguousMatchException.
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
