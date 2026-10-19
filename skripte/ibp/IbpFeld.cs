// Setzt ein einzelnes Feld im IBP-Rechenmodell, angesprochen ueber denselben
// Pfad, den ibp-flach.exe ausgibt.
//
// Damit schliesst sich die Kette: schnappschuss.ps1 zeigt, WELCHES Feld hinter
// einer Einstellung steckt, und dieses Werkzeug setzt es. Kein Suchen im
// dekompilierten Quelltext, kein Raten von Feldnamen.
//
//   ibp-feld-setzen.exe <blob.bin> <neu.bin> <Pfad> <Wert>
//   ibp-feld-setzen.exe <blob.bin> -         <Pfad>            (nur lesen)
//
//   ibp-feld-setzen.exe v7.bin v7neu.bin Zones[0].enumModeThermalBridge 3
//
// Der Wert wird in den Typ des Feldes gewandelt; passt er nicht, bricht das
// Werkzeug ab, statt etwas Falsches zu schreiben. Nach dem Schreiben wird der
// Stand neu eingelesen und gegengeprueft - im Speicher zu setzen beweist
// nicht, dass es auch in der Datei steht.
//
//   csc /platform:x64 /out:ibp-feld-setzen.exe IbpFeld.cs

using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpFeld
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    private static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine("Aufruf: ibp-feld-setzen.exe <blob.bin> <neu.bin|-> <Pfad> [Wert]");
            return 2;
        }
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        var nurLesen = args[1] == "-";
        var pfad = args[2];

        object g;
        using (var s = File.OpenRead(args[0])) g = new BinaryFormatter().Deserialize(s);

        object wirt;
        PropertyInfo eigenschaft;
        FieldInfo feld;
        if (!Zerlege(g, pfad, out wirt, out eigenschaft, out feld)) return 1;

        var typ = eigenschaft != null ? eigenschaft.PropertyType : feld.FieldType;
        var alt = eigenschaft != null ? eigenschaft.GetValue(wirt, null) : feld.GetValue(wirt);
        Console.WriteLine(pfad + " : " + typ.Name + " = " + alt);

        if (nurLesen) return 0;
        if (args.Length < 4) { Console.Error.WriteLine("Wert fehlt"); return 2; }

        // Das Komma ist in der invarianten Kultur ein TAUSENDERtrennzeichen:
        // "0,9" wird klaglos zu 9. Bei einem Wirkungsgrad heisst das 900 %,
        // und es faellt nirgends auf. Deshalb wird ein Dezimalkomma hier
        // erkannt und umgesetzt - und beides zusammen abgelehnt.
        var roh = args[3];
        if (typ == typeof(float) || typ == typeof(double) || typ == typeof(decimal))
        {
            if (roh.IndexOf(',') >= 0 && roh.IndexOf('.') >= 0)
            {
                Console.Error.WriteLine("'" + roh + "' enthaelt Punkt UND Komma - eindeutig schreiben.");
                return 1;
            }
            roh = roh.Replace(',', '.');
        }

        object neu;
        try
        {
            neu = typ.IsEnum
                ? Enum.ToObject(typ, Convert.ToInt64(roh, CultureInfo.InvariantCulture))
                : Convert.ChangeType(roh, typ, CultureInfo.InvariantCulture);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("'" + args[3] + "' passt nicht zu " + typ.Name + ": " + ex.Message);
            return 1;
        }

        if (eigenschaft != null)
        {
            if (!eigenschaft.CanWrite) { Console.Error.WriteLine(pfad + " ist schreibgeschuetzt"); return 1; }
            eigenschaft.SetValue(wirt, neu, null);
        }
        else feld.SetValue(wirt, neu);

        using (var s = File.Create(args[1])) new BinaryFormatter().Serialize(s, g);

        // Gegenprobe am geschriebenen Stand.
        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);
        object w2; PropertyInfo e2; FieldInfo f2;
        if (!Zerlege(erneut, pfad, out w2, out e2, out f2)) return 1;
        var jetzt = e2 != null ? e2.GetValue(w2, null) : f2.GetValue(w2);
        if ("" + jetzt != "" + neu)
        {
            Console.Error.WriteLine("Gegenprobe: steht " + jetzt + " statt " + neu);
            return 1;
        }
        Console.WriteLine(pfad + " = " + alt + " -> " + jetzt
            + "   (" + new FileInfo(args[1]).Length + " B, Gegenprobe bestanden)");
        return 0;
    }

    // Laeuft den Pfad ab und liefert den BESITZER des letzten Schritts, damit
    // dort geschrieben werden kann. Schritte sind "Name" und "Name[i]".
    private static bool Zerlege(object wurzel, string pfad, out object wirt,
                                out PropertyInfo eigenschaft, out FieldInfo feld)
    {
        wirt = wurzel; eigenschaft = null; feld = null;
        var teile = pfad.Split('.');
        for (var i = 0; i < teile.Length; i++)
        {
            var t = teile[i];
            var index = -1;
            var k = t.IndexOf('[');
            if (k >= 0)
            {
                index = int.Parse(t.Substring(k + 1).TrimEnd(']'), CultureInfo.InvariantCulture);
                t = t.Substring(0, k);
            }

            var p = Finde(wirt, t, out feld);
            if (p == null && feld == null)
            {
                Console.Error.WriteLine("'" + t + "' gibt es an " + wirt.GetType().Name + " nicht");
                return false;
            }

            if (i == teile.Length - 1 && index < 0) { eigenschaft = p; return true; }

            var v = p != null ? p.GetValue(wirt, null) : feld.GetValue(wirt);
            if (v == null) { Console.Error.WriteLine("'" + t + "' ist leer"); return false; }
            if (index >= 0)
            {
                v = Element(v, index);
                if (v == null) { Console.Error.WriteLine(t + "[" + index + "] gibt es nicht"); return false; }
            }
            wirt = v;
        }
        Console.Error.WriteLine("Pfad endet auf einer Sammlung, nicht auf einem Feld");
        return false;
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
