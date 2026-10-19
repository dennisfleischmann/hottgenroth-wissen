// Entfernt die Heizung aus einem IBP-Blob - ueber die Delete-API des Modells.
//
// Nachgebaut wird, was die Software beim Loeschen der Heizung tut. Gemessen an
// ihrem Ergebnis bleiben die Pooltypen fuer Uebergabe, Leitungen und Pumpen
// stehen; entfernt werden Einheit, Heizkreis und der Erzeugertyp:
//
//   vorher   UnitHeating 1  CircuitHeatWater 1  P58Generators 1
//            P58Emissions 1  P58CircuitPipes 3  P58CircuitPumps 1
//   nachher  UnitHeating 0  CircuitHeatWater 0  P58Generators 0
//            P58Emissions 1  P58CircuitPipes 3  P58CircuitPumps 1
//
// Deshalb NICHT DeleteAllUnusedEmissionsP58 / …CircuitPipesP58 / …CircuitPumpsP58
// aufrufen - die Software raeumt dort nicht auf, und ein Unterschied zu ihrem
// Ergebnis waere ein unnoetiges Risiko.
//
//   csc /platform:x64 /out:ibp-delete-heating.exe IbpDeleteHeating.cs
//   ibp-delete-heating.exe <blob.bin> <blob-ohne.bin>

using System;
using System.Collections;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpDeleteHeating
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    private static int Main(string[] args)
    {
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        object g;
        using (var s = File.OpenRead(args[0])) g = new BinaryFormatter().Deserialize(s);

        Console.WriteLine("vorher : " + Stand(g));

        // ZUERST das Warmwasser. Sein Erzeuger kann als LinkedToHeating auf die
        // Erzeugerkomponente der Heizung zeigen; wird die zuerst geloescht,
        // bleibt ein toter Verweis zurueck und jeder spaetere Zugriff auf den
        // Warmwassererzeuger wirft eine NullReferenceException. Der Graph waere
        // dann nicht mehr reparierbar, ohne ihn ganz neu aufzubauen.
        var wwEinheit = Element(Hole(g, "UnitDHW"), 0);
        if (wwEinheit != null)
        {
            var wg = Hole(wwEinheit, "Generators");
            for (var i = Zahl(wg) - 1; i >= 0; i--)
            {
                var k = Element(wg, i);
                Console.WriteLine("  WW-Erzeuger weg: " + Hole(k, "strObjectID"));
                Ruf(wwEinheit, "DeleteGenerator", new object[] { (string) Hole(k, "strObjectID") });
            }
            var ws = Hole(wwEinheit, "Storage");
            for (var i = Zahl(ws) - 1; i >= 0; i--)
            {
                var k = Element(ws, i);
                Ruf(wwEinheit, "DeleteStorage", new object[] { (string) Hole(k, "strObjectID") });
            }
        }
        var wwKreis = Element(Hole(g, "CircuitDHW"), 0);
        if (wwKreis != null)
        {
            var we = Hole(wwKreis, "Emissions");
            for (var i = Zahl(we) - 1; i >= 0; i--)
                Ruf(wwKreis, "DeleteEmission", new object[] { (string) Hole(Element(we, i), "strObjectID") });
            var wv = Hole(wwKreis, "Distributions");
            for (var i = Zahl(wv) - 1; i >= 0; i--)
                Ruf(wwKreis, "DeleteDistribution", new object[] { (string) Hole(Element(wv, i), "strObjectID") });
        }
        if (wwEinheit != null || wwKreis != null)
        {
            Ruf(g, "DeleteAllUnitsDHW", new object[0]);
            Ruf(g, "DeleteAllCircuitsDHW", new object[0]);
        }

        // Dann die Heizung. Erst die KOMPONENTEN, dann die Huellen: das
        // Loeschen der Einheit allein gibt die Verweise auf die Pooltypen nicht
        // frei - deren iReferenceCount bleibt auf 1, und
        // DeleteAllUnusedGeneratorsP58 laesst den Typ dann stehen.
        var einheit = Element(Hole(g, "UnitHeating"), 0);
        if (einheit != null)
        {
            var gen = Hole(einheit, "Generators");
            for (var i = Zahl(gen) - 1; i >= 0; i--)
            {
                var k = Element(gen, i);
                Console.WriteLine("  Erzeuger-Komponente weg: " + Hole(k, "strObjectID"));
                Ruf(einheit, "DeleteGenerator", new object[] { (string) Hole(k, "strObjectID") });
            }
        }

        var kreis = Element(Hole(g, "CircuitHeatWater"), 0);
        if (kreis != null)
        {
            var em = Hole(kreis, "Emissions");
            for (var i = Zahl(em) - 1; i >= 0; i--)
            {
                var k = Element(em, i);
                Console.WriteLine("  Uebergabe-Komponente weg: " + Hole(k, "strObjectID"));
                Ruf(kreis, "DeleteEmission", new object[] { (string) Hole(k, "strObjectID") });
            }
            var vt = Hole(kreis, "Distributions");
            for (var i = Zahl(vt) - 1; i >= 0; i--)
            {
                var k = Element(vt, i);
                Console.WriteLine("  Verteilung weg: " + Hole(k, "strObjectID"));
                Ruf(kreis, "DeleteDistribution", new object[] { (string) Hole(k, "strObjectID") });
            }
        }

        Ruf(g, "DeleteAllUnitsHeating", new object[0]);
        Ruf(g, "DeleteAllCircuitsHeatWater", new object[0]);
        Ruf(g, "DeleteAllUnusedGeneratorsP58", new object[0]);

        Console.WriteLine("nachher: " + Stand(g));

        using (var s = File.Create(args[1])) new BinaryFormatter().Serialize(s, g);

        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);
        Console.WriteLine("gelesen: " + Stand(erneut) + "   (" + new FileInfo(args[1]).Length + " B)");
        return 0;
    }

    private static string Stand(object g)
    {
        return "UnitHeating=" + Zahl(Hole(g, "UnitHeating"))
            + "  CircuitHeatWater=" + Zahl(Hole(g, "CircuitHeatWater"))
            + "  P58Generators=" + Zahl(Hole(g, "P58Generators"))
            + "  P58Emissions=" + Zahl(Hole(g, "P58Emissions"))
            + "  Pipes=" + Zahl(Hole(g, "P58CircuitPipes"))
            + "  Pumps=" + Zahl(Hole(g, "P58CircuitPumps"))
            + "  Zones=" + Zahl(Hole(g, "Zones"))
            + "  Constructions=" + Zahl(Hole(g, "Constructions"));
    }

    // Die Delete-Methoden sind durchweg ueberladen - je eine Fassung fuer die
    // Kennung und eine fuer das Objekt. Ohne Angabe der Parametertypen wirft
    // GetMethod eine AmbiguousMatchException.
    private static object Ruf(object o, string name, object[] args)
    {
        var typen = new Type[args.Length];
        for (var i = 0; i < args.Length; i++) typen[i] = args[i].GetType();

        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var m = t.GetMethod(name, Sicht | BindingFlags.DeclaredOnly, null, typen, null);
            if (m != null) return m.Invoke(o, args);
        }
        Console.Error.WriteLine("  ! " + name + "(" + typen.Length + " Arg) nicht gefunden");
        return null;
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
