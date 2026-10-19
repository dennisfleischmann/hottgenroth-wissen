// Untersucht die Beziehungsmatrix zwischen Erzeugereinheiten und Kreisen.
//
// Verdacht: P0UnitCircuitInterrelationMatrix ist der eigentliche Traeger der
// Verknuepfung Einheit <-> Heizkreis. Beim Nachbau am 12.08.2026 wurde sie nicht
// gefuellt, und die Software rechnete daraufhin fQdot_N = 0,01 kW und schrieb
// "Keine Heizung vorhanden" - obwohl alReferenceList auf beiden Seiten stimmte.
//
// Das Werkzeug sucht die Matrix am Gebaeude (der Eigenschaftsname ist unbekannt),
// listet ihre Methoden und zeigt ihren Inhalt.
//
//   csc /platform:x64 /out:ibp-matrix.exe IbpMatrix.cs
//   ibp-matrix.exe <blob.bin>

using System;
using System.Collections;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpMatrix
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

        // 1. Wo haengt sie? Alle Eigenschaften des Gebaeudes nach dem Typ absuchen.
        Console.WriteLine("=== Eigenschaften des Gebaeudes mit 'Matrix' oder 'Interrelation' im Typ ===");
        object matrix = null; string wo = null;
        foreach (var p in g.GetType().GetProperties(Sicht)
                 .Where(x => x.CanRead && x.GetIndexParameters().Length == 0)
                 .OrderBy(x => x.Name))
        {
            object w; try { w = p.GetValue(g, null); } catch { continue; }
            if (w == null) continue;
            var tn = w.GetType().Name;
            if (tn.IndexOf("Matrix", StringComparison.OrdinalIgnoreCase) < 0
             && tn.IndexOf("Interrelation", StringComparison.OrdinalIgnoreCase) < 0) continue;
            Console.WriteLine("  " + p.Name.PadRight(38) + tn);
            if (matrix == null) { matrix = w; wo = p.Name; }
        }
        if (matrix == null)
        {
            Console.WriteLine("  keine gefunden - auch Felder absuchen:");
            foreach (var f in g.GetType().GetFields(Sicht).OrderBy(x => x.Name))
            {
                object w; try { w = f.GetValue(g); } catch { continue; }
                if (w == null) continue;
                var tn = w.GetType().Name;
                if (tn.IndexOf("Matrix", StringComparison.OrdinalIgnoreCase) < 0
                 && tn.IndexOf("Interrelation", StringComparison.OrdinalIgnoreCase) < 0) continue;
                Console.WriteLine("  (Feld) " + f.Name.PadRight(31) + tn);
                if (matrix == null) { matrix = w; wo = f.Name; }
            }
        }
        if (matrix == null) { Console.WriteLine("  NICHTS GEFUNDEN"); return 1; }

        // 2. Was kann sie?
        Console.WriteLine();
        Console.WriteLine("=== " + matrix.GetType().Name + "  (an '" + wo + "') ===");
        foreach (var m in matrix.GetType().GetMethods(Sicht)
                 .Where(x => !x.Name.StartsWith("get_") && !x.Name.StartsWith("set_"))
                 .Where(x => x.DeclaringType != typeof(object))
                 .OrderBy(x => x.Name))
            Console.WriteLine("  " + m.Name + "(" + string.Join(", ",
                m.GetParameters().Select(p => p.ParameterType.Name + " " + p.Name).ToArray())
                + ") -> " + m.ReturnType.Name);

        Console.WriteLine();
        Console.WriteLine("  Eigenschaften:");
        foreach (var p in matrix.GetType().GetProperties(Sicht)
                 .Where(x => x.CanRead && x.GetIndexParameters().Length == 0).OrderBy(x => x.Name))
        {
            object w; try { w = p.GetValue(matrix, null); } catch { continue; }
            Console.WriteLine("    " + p.Name.PadRight(30) + (w == null ? "(null)" : w.ToString()));
        }

        // 3. Was steht drin?
        Console.WriteLine();
        Console.WriteLine("  Inhalt:");
        // Die Matrix selbst hat kein Count - die Beziehungen liegen in der
        // IBPHashtable "Interrelations".
        var innen = matrix.GetType().GetProperty("Interrelations", Sicht);
        if (innen != null) matrix = innen.GetValue(matrix, null);
        var n = Zahl(matrix);
        Console.WriteLine("    Count = " + n);
        for (var i = 0; i < n; i++)
        {
            var e = Element(matrix, i);
            if (e == null) { Console.WriteLine("    [" + i + "] (null)"); continue; }
            Console.WriteLine("    [" + i + "] " + e.GetType().Name);
            foreach (var p in e.GetType().GetProperties(Sicht)
                     .Where(x => x.CanRead && x.GetIndexParameters().Length == 0).OrderBy(x => x.Name))
            {
                object w; try { w = p.GetValue(e, null); } catch { continue; }
                if (w == null) continue;
                var t = w.ToString();
                if (t == "0" || t == "False" || t.Length == 0) continue;
                Console.WriteLine("        " + p.Name.PadRight(28) + t);
            }
        }
        return 0;
    }

    private static object Element(object s, int i)
    {
        var idx = s.GetType().GetProperty("Item", new[] { typeof(int) });
        if (idx != null) { try { return idx.GetValue(s, new object[] { i }); } catch { return null; } }
        var l = s as IList;
        return l != null ? l[i] : null;
    }

    private static int Zahl(object s)
    {
        if (s == null || s is string) return 0;
        var p = s.GetType().GetProperty("Count");
        if (p != null) { try { return (int) p.GetValue(s, null); } catch { return 0; } }
        var a = s as Array;
        return a != null ? a.Length : 0;
    }
}
