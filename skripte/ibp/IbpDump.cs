// Liest eine Kernel18599V5.bin und schreibt ihren Inhalt lesbar heraus.
//
// Warum ein eigenes Programm und nicht die Bruecke: der Graph ist verschachtelt
// und besteht aus Hashtables. Ueber die generischen Schritte der Bruecke waere
// jeder Knoten ein eigener Aufruf; hier laeuft ein Durchlauf.
//
// Bauen (csc aus dem .NET Framework, x64):
//   csc /platform:x64 /out:ibp-dump.exe IbpDump.cs

using System;
using System.Collections;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpDump
{
    private static string _installation = @"C:\Program Files\HSETU\Energieberater2022";

    private static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("Aufruf: ibp-dump.exe <datei.bin> [tiefe]");
            return 2;
        }

        int tiefe = args.Length > 1 ? int.Parse(args[1]) : 3;

        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var kurz = new AssemblyName(e.Name).Name;
            var pfad = Path.Combine(_installation, kurz + ".dll");
            return File.Exists(pfad) ? Assembly.LoadFrom(pfad) : null;
        };

        object wurzel;
        using (var strom = File.OpenRead(args[0]))
        {
            wurzel = new BinaryFormatter().Deserialize(strom);
        }

        Console.WriteLine("Wurzel: " + wurzel.GetType().FullName);
        Console.WriteLine();

        // Die Aeste, die die Anlagentechnik tragen. Alles andere waere Rauschen.
        // Die flachen Sammlungen am Gebaeude tragen die Geraete; die Units und
        // Circuits verweisen nur darauf. Wer den Kessel sucht, sucht in
        // P58Generators.
        var aeste = args.Length > 2
            ? args[2].Split(',')
            : new[] { "P58Generators", "P58Storages", "P58Emissions", "P58CircuitPipes", "P58CircuitPumps" };

        foreach (var ast in aeste)
        {
            var wert = Hole(wurzel, ast);

            Console.WriteLine("═══ " + ast + " ═══");

            if (wert == null) { Console.WriteLine("  (leer)"); Console.WriteLine(); continue; }

            var tabelle = wert as IDictionary;

            if (tabelle != null)
            {
                Console.WriteLine("  " + tabelle.Count + " Eintrag/Eintraege");

                foreach (DictionaryEntry e in tabelle)
                {
                    Console.WriteLine();
                    Console.WriteLine("  ── Schluessel " + e.Key + "  ──  " +
                        (e.Value == null ? "null" : e.Value.GetType().Name));
                    Zeige(e.Value, "    ", tiefe);
                }
            }
            else
            {
                Zeige(wert, "  ", tiefe);
            }

            Console.WriteLine();
        }

        return 0;
    }

    private static object Hole(object o, string name)
    {
        var t = o.GetType();

        var f = t.GetField(name, BindingFlags.Public | BindingFlags.Instance);
        if (f != null) return f.GetValue(o);

        var p = t.GetProperty(name, BindingFlags.Public | BindingFlags.Instance);
        return p != null ? p.GetValue(o, null) : null;
    }

    /// <summary>
    /// Gibt ein Objekt aus: erst die Werte, dann die verschachtelten Objekte.
    ///
    /// Sentinel und Nullwerte bleiben weg - bei ueber hundert Feldern je Klasse
    /// waere die Ausgabe sonst nicht zu lesen. Was fehlt, ist nicht gesetzt.
    /// </summary>
    private static void Zeige(object o, string einzug, int tiefe)
    {
        if (o == null || tiefe < 0) return;

        var t = o.GetType();

        var glieder = t.GetFields(BindingFlags.Public | BindingFlags.Instance).Cast<MemberInfo>()
            .Concat(t.GetProperties(BindingFlags.Public | BindingFlags.Instance).Where(p => p.GetIndexParameters().Length == 0))
            .OrderBy(m => m.Name);

        var tiefer = new System.Collections.Generic.List<Tuple<string, object>>();

        foreach (var m in glieder)
        {
            object w;
            Type wt;

            try
            {
                var f = m as FieldInfo;
                if (f != null) { w = f.GetValue(o); wt = f.FieldType; }
                else { var p = (PropertyInfo) m; w = p.GetValue(o, null); wt = p.PropertyType; }
            }
            catch { continue; }

            if (w == null) continue;

            if (wt.IsPrimitive || wt == typeof(string) || wt.IsEnum || wt == typeof(decimal))
            {
                if (Uninteressant(w)) continue;
                Console.WriteLine(einzug + m.Name.PadRight(34) + " " + Text(w));
                continue;
            }

            var d = w as IDictionary;
            if (d != null) { if (d.Count > 0) tiefer.Add(Tuple.Create(m.Name + " [" + d.Count + "]", w)); continue; }

            var l = w as IList;
            if (l != null) { if (l.Count > 0) tiefer.Add(Tuple.Create(m.Name + " [" + l.Count + "]", w)); continue; }

            if (wt.Namespace != null && wt.Namespace.StartsWith("DIN18599")) tiefer.Add(Tuple.Create(m.Name, w));
        }

        foreach (var kind in tiefer)
        {
            Console.WriteLine(einzug + "· " + kind.Item1 + "  (" + kind.Item2.GetType().Name + ")");

            var d = kind.Item2 as IDictionary;
            if (d != null)
            {
                foreach (DictionaryEntry e in d)
                {
                    Console.WriteLine(einzug + "  [" + e.Key + "] " + (e.Value == null ? "null" : e.Value.GetType().Name));
                    Zeige(e.Value, einzug + "    ", tiefe - 1);
                }
                continue;
            }

            var l = kind.Item2 as IList;
            if (l != null)
            {
                for (int i = 0; i < l.Count && i < 12; i++)
                {
                    Console.WriteLine(einzug + "  [" + i + "] " + (l[i] == null ? "null" : l[i].GetType().Name));
                    Zeige(l[i], einzug + "    ", tiefe - 1);
                }
                continue;
            }

            Zeige(kind.Item2, einzug + "  ", tiefe - 1);
        }
    }

    /// <summary>Sentinel und Vorgabewerte, die nichts aussagen.</summary>
    private static bool Uninteressant(object w)
    {
        if (w is bool) return !(bool) w;
        if (w is string) return ((string) w).Length == 0;

        double d;
        try { d = Convert.ToDouble(w); } catch { return false; }

        return d == 0d || Math.Abs(Math.Abs(d) - 987654321.99) < 0.01 || d == -1d || d == -999d
            || Math.Abs(d - 1e30) < 1e20 || Math.Abs(d + 1e30) < 1e20;
    }

    private static string Text(object w)
    {
        if (w is double || w is float)
        {
            return Convert.ToDouble(w).ToString("0.####", System.Globalization.CultureInfo.InvariantCulture);
        }

        return Convert.ToString(w, System.Globalization.CultureInfo.InvariantCulture);
    }
}
