// Liest und aendert SAMMLUNGEN im IBP-Rechenmodell - dort, wo
// ibp-feld-setzen.exe mit "Pfad endet auf einer Sammlung" abbricht.
//
// Gebraucht wird das fuer Verweislisten wie AmbientZone: ein Rohr traegt
// enumAmbientType = 2 ("in Zone"), und WELCHE Zone gemeint ist, steht als
// Objektkennung in einer IBPArrayList daneben. Wer nur den Schalter setzt und
// die Liste leer laesst, bekommt ein Modell, das "in Zone" behauptet und die
// Verluste trotzdem niemandem gutschreibt - der Rechenkern steigt bei einem
// leeren Eintrag wortlos aus (P58Calculator.AddUpSinksAndSourcesZone).
//
//   ibp-sammlung.exe <blob.bin> <neu.bin|-> <Pfad> [Befehl] [Wert] [Art]
//
//   Befehle:  zeigen              Vorgabe - Anzahl und Elemente ausgeben
//             anhaengen <Wert>    Add(...)
//             entfernen <Index>   RemoveAt(...)
//             leeren              Clear()
//
//   Art:      text (Vorgabe) | ganz | komma
//
//   ibp-sammlung.exe k.bin -      CircuitHeatWater[0].Distributions[0].Pipes[2].AmbientTemperature.AmbientZone
//   ibp-sammlung.exe k.bin neu.bin CircuitHeatWater[0].Distributions[0].Pipes[2].AmbientTemperature.AmbientZone anhaengen "P0Zone_1[E9BB54E1]"
//
//   csc /platform:x64 /out:ibp-sammlung.exe IbpSammlung.cs
//
// Nach dem Schreiben wird die Datei neu eingelesen und die Sammlung erneut
// ausgegeben. Im Speicher zu aendern beweist nicht, dass es in der Datei steht.

using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpSammlung
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    private static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine("Aufruf: ibp-sammlung.exe <blob.bin> <neu.bin|-> <Pfad> "
                + "[zeigen|anhaengen <Wert>|entfernen <Index>|leeren] [text|ganz|komma]");
            return 2;
        }
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        var nurLesen = args[1] == "-";
        var pfad = args[2];
        var befehl = args.Length > 3 ? args[3].ToLowerInvariant() : "zeigen";
        var wertRoh = args.Length > 4 ? args[4] : null;
        var art = args.Length > 5 ? args[5].ToLowerInvariant() : "text";

        object g;
        using (var s = File.OpenRead(args[0])) g = new BinaryFormatter().Deserialize(s);

        var sammlung = Hole(g, pfad);
        if (sammlung == null) return 1;

        var zahl = sammlung.GetType().GetProperty("Count");
        if (zahl == null)
        {
            Console.Error.WriteLine(pfad + " ist " + sammlung.GetType().Name
                + " und hat kein Count - das ist keine Sammlung.");
            return 1;
        }

        Console.WriteLine("vorher:");
        Zeige(sammlung, pfad);

        if (befehl == "zeigen" || nurLesen)
        {
            if (!nurLesen && befehl != "zeigen")
                Console.Error.WriteLine("Ohne Zieldatei wird nur gezeigt.");
            return 0;
        }

        switch (befehl)
        {
            case "anhaengen":
            {
                if (wertRoh == null) { Console.Error.WriteLine("Wert fehlt"); return 2; }
                object wert;
                switch (art)
                {
                    case "ganz":  wert = int.Parse(wertRoh, CultureInfo.InvariantCulture); break;
                    case "komma": wert = float.Parse(wertRoh.Replace(',', '.'), CultureInfo.InvariantCulture); break;
                    default:      wert = wertRoh; break;
                }
                var add = sammlung.GetType().GetMethod("Add", new[] { typeof(object) });
                if (add == null) { Console.Error.WriteLine("Kein Add(object) an " + sammlung.GetType().Name); return 1; }
                add.Invoke(sammlung, new[] { wert });
                break;
            }
            case "entfernen":
            {
                if (wertRoh == null) { Console.Error.WriteLine("Index fehlt"); return 2; }
                var i = int.Parse(wertRoh, CultureInfo.InvariantCulture);
                var weg = sammlung.GetType().GetMethod("RemoveAt", new[] { typeof(int) });
                if (weg == null) { Console.Error.WriteLine("Kein RemoveAt(int) an " + sammlung.GetType().Name); return 1; }
                weg.Invoke(sammlung, new object[] { i });
                break;
            }
            case "leeren":
            {
                var leer = sammlung.GetType().GetMethod("Clear", Type.EmptyTypes);
                if (leer == null) { Console.Error.WriteLine("Kein Clear() an " + sammlung.GetType().Name); return 1; }
                leer.Invoke(sammlung, new object[0]);
                break;
            }
            default:
                Console.Error.WriteLine("Unbekannter Befehl '" + befehl + "'");
                return 2;
        }

        using (var s = File.Create(args[1])) new BinaryFormatter().Serialize(s, g);

        // Gegenprobe am geschriebenen Stand - nicht am Speicher.
        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);
        var s2 = Hole(erneut, pfad);
        if (s2 == null) { Console.Error.WriteLine("Gegenprobe: Pfad nicht mehr auffindbar"); return 1; }
        Console.WriteLine("nachher (aus der Datei gelesen):");
        Zeige(s2, pfad);
        Console.WriteLine("  " + new FileInfo(args[1]).Length + " B geschrieben");
        return 0;
    }

    private static void Zeige(object sammlung, string pfad)
    {
        var n = (int) sammlung.GetType().GetProperty("Count").GetValue(sammlung, null);
        Console.WriteLine("  " + pfad + " : " + sammlung.GetType().Name + ", Count = " + n);
        for (var i = 0; i < n; i++)
        {
            var e = Element(sammlung, i);
            Console.WriteLine("    [" + i + "] " + (e == null ? "(null)" : e.GetType().Name + " = " + e));
        }
    }

    // Laeuft den Pfad ab und liefert das Objekt AM ENDE - anders als
    // ibp-feld-setzen.exe, das den Besitzer des letzten Schritts braucht.
    private static object Hole(object wurzel, string pfad)
    {
        var wirt = wurzel;
        foreach (var teil in pfad.Split('.'))
        {
            var t = teil;
            var index = -1;
            var k = t.IndexOf('[');
            if (k >= 0)
            {
                index = int.Parse(t.Substring(k + 1).TrimEnd(']'), CultureInfo.InvariantCulture);
                t = t.Substring(0, k);
            }

            FieldInfo feld;
            var p = Finde(wirt, t, out feld);
            if (p == null && feld == null)
            {
                Console.Error.WriteLine("'" + t + "' gibt es an " + wirt.GetType().Name + " nicht");
                return null;
            }

            var v = p != null ? p.GetValue(wirt, null) : feld.GetValue(wirt);
            if (v == null) { Console.Error.WriteLine("'" + t + "' ist leer"); return null; }
            if (index >= 0)
            {
                v = Element(v, index);
                if (v == null) { Console.Error.WriteLine(t + "[" + index + "] gibt es nicht"); return null; }
            }
            wirt = v;
        }
        return wirt;
    }

    private static PropertyInfo Finde(object o, string name, out FieldInfo feld)
    {
        feld = null;
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var p = t.GetProperty(name, Sicht | BindingFlags.DeclaredOnly);
            if (p != null && p.GetIndexParameters().Length == 0) return p;
            var f = t.GetField(name, Sicht | BindingFlags.DeclaredOnly);
            if (f != null) { feld = f; return null; }
        }
        return null;
    }

    private static object Element(object s, int i)
    {
        var idx = s.GetType().GetProperty("Item", new[] { typeof(int) });
        if (idx != null) { try { return idx.GetValue(s, new object[] { i }); } catch { return null; } }
        var l = s as IList;
        return l != null && i < l.Count ? l[i] : null;
    }
}
