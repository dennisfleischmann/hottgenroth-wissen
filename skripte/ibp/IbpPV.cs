// Legt eine Photovoltaikanlage samt Batterie im IBP-Modell an.
//
// Die Anlage haengt an DIN18599Building.UnitRenewable - einem EINZELNEN Objekt
// mit einer Generators-Sammlung darin, nicht an einer Sammlung von Einheiten.
// Wer "UnitRenewable.Count" abfragt, bekommt nichts und schliesst daraus, es
// gebe keine PV. Genau so ist es einmal passiert.
//
//   csc /platform:x64 /out:ibp-pv-setzen.exe IbpPV.cs
//   ibp-pv-setzen.exe <blob.bin> <neu.bin> kwp=20 flaeche=40 ausrichtung=4
//                     neigung=35 batterie=12 eigenverbrauch=1 baujahr=2027
//
//   Orientations   0 Horizontal 1 Sued 2 SuedOst 3 SuedWest 4 Ost 5 West
//                  6 NordWest 7 NordOst 8 Nord
//   PVType         0 monokristallin 1 polykristallin 4 CIS/CIGS
//   PVTechnology   0 kristallin
//   PVVentilation  0 unbelueftet 1 maessig 2 stark hinterlueftet
//   BatteryType    0 Lithium 1 NiFe
//
// Ohne 'eigenverbrauch=1' bleibt bCalculateSelfUse aus - dann steht die
// Batterie im Modell, arbeitet aber nicht.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpPV
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    private static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine("Aufruf: ibp-pv-setzen.exe <blob.bin> <neu.bin> kwp=… flaeche=… [ausrichtung=] [neigung=] [batterie=] [eigenverbrauch=] [baujahr=]");
            return 2;
        }
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        var w = new Dictionary<string, string>();
        foreach (var a in args)
        {
            var i = a.IndexOf('=');
            if (i > 0) w[a.Substring(0, i).ToLowerInvariant()] = a.Substring(i + 1);
        }

        object g;
        using (var s = File.OpenRead(args[0])) g = new BinaryFormatter().Deserialize(s);

        var einheit = Hole(g, "UnitRenewable");
        if (einheit == null) { Console.Error.WriteLine("UnitRenewable fehlt am Gebaeude"); return 1; }

        var vorhanden = Zahl(Hole(einheit, "Generators"));
        if (vorhanden > 0)
        {
            Console.Error.WriteLine("Es sind schon " + vorhanden + " Erzeuger da - erst entfernen, sonst"
                + " summiert sich die Leistung stillschweigend auf.");
            return 1;
        }

        var pv = Ruf(einheit, "NewP9RenewableGeneratorPV", "GeneratorPV", "PV-Anlage");
        if (pv == null) { Console.Error.WriteLine("NewP9RenewableGeneratorPV nicht aufrufbar"); return 1; }

        var kwp = Komma(w, "kwp", 10);
        var flaeche = Komma(w, "flaeche", kwp * 2f);   // rund 2 m2 je kWp bei kristallin
        Setze(pv, "fP_pk", kwp);
        Setze(pv, "fP_pk_design", kwp);
        Setze(pv, "fA", flaeche);
        Setze(pv, "fA_design", flaeche);
        Setze(pv, "enumOrientation", (short) Ganz(w, "ausrichtung", 1));
        Setze(pv, "fIncline", Komma(w, "neigung", 30));
        Setze(pv, "enumPVType", (short) Ganz(w, "typ", 0));
        Setze(pv, "enumTechnology", (short) Ganz(w, "technologie", 0));
        Setze(pv, "enumVentilation", (short) Ganz(w, "hinterlueftung", 2));
        Setze(pv, "sGeneratorAge", (short) Ganz(w, "baujahr", 2026));

        // Die Fabrik laesst diese beiden auf 0 stehen. ff_perf = 0 bedeutet
        // NULL ERTRAG - die Anlage stuende im Modell und lieferte nichts, ohne
        // dass es irgendwo auffiele. Die Vorgaben sind die Werte, die die
        // Software selbst einsetzt, wenn eine PV-Anlage in der Oberflaeche
        // angelegt wird.
        Setze(pv, "ff_perf", Komma(w, "performance", 0.8f));
        Setze(pv, "fK_pk", Komma(w, "k_pk", 0.182f));
        Setze(pv, "fDegradationAfter25Years", Komma(w, "degradation", 0.8f));

        Console.WriteLine("  PV: " + Z(kwp) + " kWp auf " + Z(flaeche) + " m2, Ausrichtung "
            + Hole(pv, "enumOrientation") + ", Neigung " + Z(Komma(w, "neigung", 30))
            + " Grad, Performance " + Z(Komma(w, "performance", 0.8f)));

        var akku = Komma(w, "batterie", 0);
        if (akku > 0)
        {
            var b = Ruf(einheit, "NewBattery", "P9Battery_1", "Batterie");
            if (b == null) { Console.Error.WriteLine("NewBattery nicht aufrufbar"); return 1; }
            Setze(b, "fC_eff_design", akku);
            Setze(b, "enumBatteryType", (short) Ganz(w, "batterietyp", 0));
            // bHasBattery ist schreibgeschuetzt - das Modell traegt es selbst
            // nach, sobald Battery gesetzt ist. Dasselbe Muster wie LinkedUnit
            // beim Warmwassererzeuger.
            Console.WriteLine("  Batterie: " + Z(akku) + " kWh, bHasBattery = " + Hole(einheit, "bHasBattery"));
        }

        // Ohne Eigenverbrauchsrechnung bleibt die Batterie wirkungslos.
        var eigen = Ganz(w, "eigenverbrauch", akku > 0 ? 1 : 0) != 0;
        Setze(einheit, "bCalculateSelfUse", eigen);
        Console.WriteLine("  Eigenverbrauchsrechnung: " + (eigen ? "ja" : "nein"));

        using (var s = File.Create(args[1])) new BinaryFormatter().Serialize(s, g);

        // Gegenprobe am geschriebenen Stand
        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);
        var e2 = Hole(erneut, "UnitRenewable");
        var pv2 = Element(Hole(e2, "Generators"), 0);
        if (pv2 == null) { Console.Error.WriteLine("Gegenprobe: kein PV-Erzeuger"); return 1; }
        var ist = Convert.ToSingle(Hole(pv2, "fP_pk"));
        if (Math.Abs(ist - kwp) > 0.001f)
        {
            Console.Error.WriteLine("Gegenprobe: " + Z(ist) + " statt " + Z(kwp) + " kWp");
            return 1;
        }
        Console.WriteLine("  " + new FileInfo(args[1]).Length + " B, Gegenprobe bestanden");
        return 0;
    }

    private static string Z(float f) { return f.ToString("0.##", CultureInfo.InvariantCulture); }

    private static float Komma(Dictionary<string, string> d, string n, float vorgabe)
    {
        string s;
        return d.TryGetValue(n, out s) ? float.Parse(s, CultureInfo.InvariantCulture) : vorgabe;
    }

    private static int Ganz(Dictionary<string, string> d, string n, int vorgabe)
    {
        string s;
        return d.TryGetValue(n, out s) ? int.Parse(s, CultureInfo.InvariantCulture) : vorgabe;
    }

    private static object Ruf(object o, string name, string id, string bez)
    {
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var m = t.GetMethod(name, Sicht | BindingFlags.DeclaredOnly, null,
                        new[] { typeof(string), typeof(string) }, null);
            if (m != null) return m.Invoke(o, new object[] { id, bez });
            var m0 = t.GetMethod(name, Sicht | BindingFlags.DeclaredOnly, null, Type.EmptyTypes, null);
            if (m0 != null) return m0.Invoke(o, new object[0]);
        }
        return null;
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
        if (p != null) { try { return (int) p.GetValue(s, null); } catch { return 0; } }
        var a = s as Array;
        return a != null ? a.Length : 0;
    }
}
