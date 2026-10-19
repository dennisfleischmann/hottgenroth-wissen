// Liest die komplette Heizungskonfiguration aus dem IBP-Blob.
//
// ibp-dump.exe zeigt nur die Pools (P58Generators, P58Emissions, ...). Die
// eigentliche Verdrahtung steht aber in den Einheiten und Kreisen:
//
//   DIN18599Building
//     Zones                Nutzungszonen
//     UnitHeating          Erzeugereinheiten  -> Generators (Komponenten)
//     Circuits             Heizkreise         -> Emissions, Distribution
//                                                Distribution -> Pipes, Pumps
//     EnergySources        Brennstoffe
//
// Der Aufbau ist durchgehend zweistufig: ein TYP im Pool des Gebaeudes
// (P58HeatGeneratorBoiler, teilbar, daher iReferenceCount) und eine KOMPONENTE
// in der Einheit (P58HeatGeneratorBoilerComponent), die auf ihn zeigt.
//
//   csc /platform:x64 /out:ibp-heating.exe IbpHeating.cs

using System;
using System.Collections;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpHeating
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    private static readonly string[] Uebergehen =
    {
        "ConstructionElements", "Constructions", "Windows", "FenestrationSystems",
        "ShadingSystems", "LightingDomains", "PartialUses", "Zones"
    };

    private static int Main(string[] args)
    {
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        object g;
        using (var s = File.OpenRead(args[0])) g = new BinaryFormatter().Deserialize(s);

        // Erst zeigen, welche Sammlungen das Gebaeude ueberhaupt fuehrt - Namen
        // zu erraten kostet nur Zeit.
        if (args.Length > 1 && args[1] == "--sammlungen")
        {
            foreach (var p in g.GetType().GetProperties(Sicht)
                     .Where(x => x.CanRead && x.GetIndexParameters().Length == 0)
                     .OrderBy(x => x.Name))
            {
                object w; try { w = p.GetValue(g, null); } catch { continue; }
                if (w == null || w is string) continue;
                var n = Zahl(w);
                if (n > 0) Console.WriteLine(p.Name.PadRight(34) + n.ToString().PadLeft(4) + "  " + w.GetType().Name);
            }
            return 0;
        }

        foreach (var name in new[] { "Zones", "EnergySources", "UnitHeating", "CircuitHeatWater", "UnitDHW", "CircuitDHW",
                                     "P58Generators", "P58Emissions", "P58CircuitPipes",
                                     "P58CircuitPumps", "P58Storages" })
        {
            var sammlung = Hole(g, name);
            Console.WriteLine("=== " + name + " === " + (sammlung == null ? "(nicht vorhanden)" : Zahl(sammlung) + " Stueck"));
            Zeige(sammlung, 1);
            Console.WriteLine();
        }
        return 0;
    }

    private static void Zeige(object sammlung, int tiefe)
    {
        if (sammlung == null || tiefe > 8) return;
        var n = Zahl(sammlung);
        for (var i = 0; i < n; i++)
        {
            var o = Element(sammlung, i);
            if (o == null) continue;
            var ein = new string(' ', tiefe * 2);
            Console.WriteLine(ein + "[" + i + "] " + o.GetType().Name
                + "  '" + Lies(o, "strName") + "'  " + Lies(o, "strObjectID"));

            // Skalare und Zeichenketten. Die Zeichenketten sind wichtig: die
            // Verknuepfung zum Brennstoff steht als strEnergySourceID drin,
            // nicht als Objektverweis.
            foreach (var p in o.GetType().GetProperties(Sicht)
                     .Where(x => x.CanRead && x.GetIndexParameters().Length == 0)
                     .Where(x => x.PropertyType.IsPrimitive || x.PropertyType.IsEnum
                              || x.PropertyType == typeof(string))
                     .OrderBy(x => x.Name))
            {
                if (p.Name == "strObjectID" || p.Name == "strName") continue;
                object w; try { w = p.GetValue(o, null); } catch { continue; }
                if (w == null) continue;
                var t = w.ToString();
                if (t == "0" || t == "False" || t == "-1" || t.Length == 0) continue;
                Console.WriteLine(ein + "    " + p.Name.PadRight(30) + t);
            }

            // Verweise auf andere Objekte des Modells
            foreach (var p in o.GetType().GetProperties(Sicht)
                     .Where(x => x.CanRead && x.GetIndexParameters().Length == 0)
                     .Where(x => x.PropertyType.Namespace != null
                              && x.PropertyType.Namespace.StartsWith("DIN18599"))
                     .OrderBy(x => x.Name))
            {
                object w; try { w = p.GetValue(o, null); } catch { continue; }
                if (w == null) continue;
                var id = Hole(w, "strObjectID");
                if (id != null)
                    Console.WriteLine(ein + "    -> " + p.Name.PadRight(27) + w.GetType().Name + "  " + id);
                else if (Zahl(w) > 0)
                {
                    Console.WriteLine(ein + "    -> " + p.Name.PadRight(27) + "(" + Zahl(w) + ")");
                    // Die Gebaeudehuelle haengt an der Zone und ist hier nicht
                    // das Thema - 38 Bauteile wuerden die Anlagentechnik zudecken.
                    if (!Uebergehen.Contains(p.Name)) Zeige(w, tiefe + 2);
                }
            }
        }
    }

    private static object Hole(object o, string name)
    {
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var p = t.GetProperty(name, Sicht | BindingFlags.DeclaredOnly);
            if (p != null && p.GetIndexParameters().Length == 0) return p.GetValue(o, null);
            var f = t.GetField(name, Sicht | BindingFlags.DeclaredOnly);
            if (f != null) return f.GetValue(o);
        }
        return null;
    }

    private static object Lies(object o, string name)
    {
        var w = Hole(o, name);
        return w == null ? "" : w;
    }

    private static object Element(object s, int i)
    {
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
