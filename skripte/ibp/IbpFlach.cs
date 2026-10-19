// Schreibt alle Zahlen-, Wahrheits- und Textwerte eines IBP-Blobs flach heraus,
// je Zeile ein Pfad und ein Wert.
//
// Zweck: zwei Staende vergleichbar machen. Wer wissen will, welches Feld hinter
// einer Einstellung der Oberflaeche steckt, macht einen Schnappschuss, stellt
// sie um, macht den zweiten - und die Differenz nennt das Feld. Das ist der
// verlaesslichste Weg, den es gibt: er setzt kein Vorwissen ueber das Modell
// voraus und findet auch Felder, die niemand vermutet haette.
//
// Rueckverweise werden ausgelassen (Building, ContainedIn, Parent, …), sonst
// laeuft der Durchlauf im Kreis. Ergebnisse ebenfalls: sie aendern sich bei
// jeder Neuberechnung und wuerden die Differenz zumuellen.
//
//   csc /platform:x64 /out:ibp-flach.exe IbpFlach.cs
//   ibp-flach.exe <blob.bin> [tiefe=6] [mit-ergebnisse]

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpFlach
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    // Rueckverweise auf den Wirt. Ohne diese Liste laeuft der Durchlauf endlos
    // im Kreis, weil fast jedes Objekt sein Gebaeude kennt.
    private static readonly HashSet<string> Aus = new HashSet<string>
    {
        "Building", "ContainedIn", "Parent", "Zone", "Zone1", "Zone2",
        "alReferenceList", "theLCACalculationElements"
    };

    private static readonly List<string> Zeilen = new List<string>();
    private static readonly HashSet<object> Gesehen =
        new HashSet<object>(new ReferenzVergleich());
    private static int maxTiefe = 6;
    private static bool mitErgebnissen;

    private static int Main(string[] args)
    {
        if (args.Length < 1) { Console.Error.WriteLine("Aufruf: ibp-flach.exe <blob.bin> [tiefe] [mit-ergebnisse]"); return 2; }
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };
        foreach (var a in args.Skip(1))
        {
            if (a == "mit-ergebnisse") mitErgebnissen = true;
            else int.TryParse(a, out maxTiefe);
        }

        object g;
        using (var s = File.OpenRead(args[0])) g = new BinaryFormatter().Deserialize(s);

        Geh(g, "", 0);
        Zeilen.Sort(StringComparer.Ordinal);
        foreach (var z in Zeilen) Console.WriteLine(z);
        return 0;
    }

    private static void Geh(object o, string pfad, int tiefe)
    {
        if (o == null || tiefe > maxTiefe) return;
        if (!Gesehen.Add(o)) return;

        var liste = o as IEnumerable;
        if (liste != null && !(o is string))
        {
            var i = 0;
            foreach (var e in liste)
            {
                if (e != null && !Einfach(e.GetType())) Geh(e, pfad + "[" + i + "]", tiefe + 1);
                i++;
                if (i > 400) break;   // Monatswerte und Ergebnisreihen ufern sonst aus
            }
            return;
        }

        foreach (var p in o.GetType().GetProperties(Sicht)
                 .Where(x => x.GetIndexParameters().Length == 0).OrderBy(x => x.Name, StringComparer.Ordinal))
        {
            if (Aus.Contains(p.Name)) continue;
            if (!mitErgebnissen && (p.Name.StartsWith("Results") || p.Name.Contains("Result"))) continue;

            object v;
            try { v = p.GetValue(o, null); } catch { continue; }
            if (v == null) continue;

            var neu = pfad.Length == 0 ? p.Name : pfad + "." + p.Name;
            if (Einfach(v.GetType()))
            {
                Zeilen.Add(neu + " = " + Text(v));
                continue;
            }
            Geh(v, neu, tiefe + 1);
        }
    }

    private static bool Einfach(Type t)
    {
        return t.IsPrimitive || t.IsEnum || t == typeof(string) || t == typeof(decimal);
    }

    private static string Text(object v)
    {
        if (v is float) return ((float) v).ToString("0.######", CultureInfo.InvariantCulture);
        if (v is double) return ((double) v).ToString("0.######", CultureInfo.InvariantCulture);
        return Convert.ToString(v, CultureInfo.InvariantCulture);
    }

    // Gleichheit ueber die Objektidentitaet, nicht ueber Equals: manche Typen
    // im Modell vergleichen wertgleich und wuerden sich sonst gegenseitig
    // ausschliessen.
    private sealed class ReferenzVergleich : IEqualityComparer<object>
    {
        public new bool Equals(object a, object b) { return ReferenceEquals(a, b); }
        public int GetHashCode(object o) { return System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(o); }
    }
}
