// Liest den Bauteilbestand eines Projekts klassifiziert aus - die Grundlage
// jeder Planung: welche Bauteilarten liegen vor, wie gross, wie orientiert,
// mit welchem U-Wert.
//
//   ibp-bauteile.exe <blob.bin> [zone=0] [csv]
//
// Das Modell klassifiziert selbst, es muss nichts geraten werden:
//
//   enEnEV09ConstructionElementType   Wand/Fenster gegen Aussenluft, Dach als
//                                     Systemgrenze, Decke zum unbeheizten
//                                     Dachraum, Boden gegen Erdreich, ...
//   enAdjacentTo                      ZoneOutside / ZoneUnconditionedZone /
//                                     ZoneGround / ZoneZone
//   enOrientation, enIncline          Himmelsrichtung und Neigung
//   Construction.fU                   U-Wert des zugeordneten Aufbaus
//
// Fenster haengen als FenestrationSystems am Bauteil, nicht daneben - sie
// werden deshalb je Bauteil mit ausgegeben.
//
//   csc /platform:x64 /out:ibp-bauteile.exe IbpBauteile.cs

using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpBauteile
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

        var csv = args.Any(a => a == "csv");
        var zoneNr = 0;
        foreach (var a in args) if (a.StartsWith("zone=")) zoneNr = int.Parse(a.Substring(5));

        var zone = Element(Hole(g, "Zones"), zoneNr);
        if (zone == null) { Console.Error.WriteLine("Zone " + zoneNr + " gibt es nicht."); return 1; }

        var teile = Hole(zone, "ConstructionElements");
        var n = Zahl(teile);

        if (csv) Console.WriteLine("Nr;Bezeichnung;Art;Angrenzend;Ausrichtung;Neigung;Flaeche;U;Aufbau;Fenster");
        else
        {
            Console.WriteLine("Zone '" + Hole(zone, "strName") + "'   " + n + " Bauteile");
            Console.WriteLine();
            Console.WriteLine("Nr  Bezeichnung                          Art                                Angrenzend      Ausr.  Neig.   Flaeche   U-Wert");
        }

        double summe = 0, uaOpak = 0, uaFenster = 0, flaecheFenster = 0;
        for (var i = 0; i < n; i++)
        {
            var t = Element(teile, i);
            var bau = Hole(t, "Construction");
            var u = bau == null ? (object) null : Hole(bau, "fU");
            var flaeche = Convert.ToDouble(Hole(t, "fA") ?? 0f);
            summe += flaeche;

            var fen = Hole(t, "FenestrationSystems");
            var fenZahl = Zahl(fen);

            // Waermedurchgang aufsummieren. Das ist die Groesse, an der sich
            // ablesen laesst, ob eine Sanierungsmassnahme im Rechenmodell
            // angekommen ist - ein U-Wert in der Bauteilliste allein beweist
            // das nicht. Fenster haengen als FenestrationSystem am Bauteil und
            // tragen ihre eigene Flaeche; das Bauteil steht dann auf 0.
            if (u != null) uaOpak += Convert.ToDouble(u) * flaeche;
            for (var q = 0; q < fenZahl; q++)
            {
                var fs = Element(fen, q);
                var w = Hole(fs, "Window");
                if (w == null) continue;
                var af = Convert.ToDouble(Hole(fs, "fA") ?? 0f);
                uaFenster += Convert.ToDouble(Hole(w, "fU")) * af;
                flaecheFenster += af;
            }

            if (csv)
                Console.WriteLine(string.Join(";", new[]
                {
                    (i + 1).ToString(), "" + Hole(t, "strName"), "" + Hole(t, "enEnEV09ConstructionElementType"),
                    "" + Hole(t, "enAdjacentTo"), "" + Hole(t, "enOrientation"), "" + Hole(t, "enIncline"),
                    flaeche.ToString("0.00", CultureInfo.InvariantCulture),
                    u == null ? "" : Convert.ToDouble(u).ToString("0.000", CultureInfo.InvariantCulture),
                    bau == null ? "" : "" + Hole(bau, "strName"), fenZahl.ToString()
                }));
            else
                Console.WriteLine("{0,3}  {1,-36} {2,-34} {3,-15} {4,-6} {5,-7} {6,8:0.00}  {7}",
                    i + 1, Kurz("" + Hole(t, "strName"), 36),
                    Kurz("" + Hole(t, "enEnEV09ConstructionElementType"), 34),
                    Kurz("" + Hole(t, "enAdjacentTo"), 15),
                    Kurz("" + Hole(t, "enOrientation"), 6),
                    Kurz("" + Hole(t, "enIncline"), 7),
                    flaeche,
                    u == null ? "(kein Aufbau)" : Convert.ToDouble(u).ToString("0.000") + (fenZahl > 0 ? "   " + fenZahl + " Fenster" : ""));
        }

        if (csv) return 0;

        // Zusammenfassung nach Art - das ist die Planungsgrundlage
        Console.WriteLine();
        Console.WriteLine("nach Bauteilart:");
        Console.WriteLine("Art                                          Anzahl    Flaeche   U min    U max");
        var nachArt = Enumerable.Range(0, n).Select(i => Element(teile, i))
            .GroupBy(t => "" + Hole(t, "enEnEV09ConstructionElementType"))
            .OrderByDescending(x => x.Sum(t => Convert.ToDouble(Hole(t, "fA") ?? 0f)));
        foreach (var gr in nachArt)
        {
            var us = gr.Select(t => Hole(t, "Construction")).Where(b => b != null)
                       .Select(b => Convert.ToDouble(Hole(b, "fU"))).ToArray();
            Console.WriteLine("{0,-44} {1,6} {2,10:0.00}   {3,6} {4,8}",
                Kurz(gr.Key, 44), gr.Count(), gr.Sum(t => Convert.ToDouble(Hole(t, "fA") ?? 0f)),
                us.Any() ? us.Min().ToString("0.000") : "-",
                us.Any() ? us.Max().ToString("0.000") : "-");
        }
        Console.WriteLine();
        // Die Bauteilflaeche fA eines Fensterbauteils ist 0 - die Flaeche haengt
        // am FenestrationSystem. Wer nur fA summiert, meldet die Huellflaeche
        // um die Fensterflaeche zu klein und merkt es nicht: hier waren es
        // 505,26 statt 532,64 m2, und die Oberflaeche zeigt 532,6.
        Console.WriteLine("Huellflaeche gesamt: " + (summe + flaecheFenster).ToString("0.00") + " m2"
            + "   opak " + summe.ToString("0.00")
            + "   Fenster " + flaecheFenster.ToString("0.00"));
        Console.WriteLine("UA gesamt: " + (uaOpak + uaFenster).ToString("0.0") + " W/K"
            + "   opak " + uaOpak.ToString("0.0")
            + "   Fenster " + uaFenster.ToString("0.0"));

        // Aufbauten im Pool - hier haengt die Schichtplanung an
        var bauten = Hole(g, "Constructions");
        Console.WriteLine();
        Console.WriteLine("Aufbauten im Pool: " + Zahl(bauten));
        for (var i = 0; i < Zahl(bauten); i++)
        {
            var b = Element(bauten, i);
            Console.WriteLine("  {0,-40} U = {1,7:0.000}   {2}",
                Kurz("" + Hole(b, "strName"), 40), Convert.ToDouble(Hole(b, "fU") ?? 0f), Hole(b, "strObjectID"));
        }
        return 0;
    }

    private static string Kurz(string s, int n)
    {
        if (s == null) return "";
        return s.Length <= n ? s : s.Substring(0, n - 1) + "…";
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
