// Setzt einen zweiten Kessel in ein bereits erfasstes Projekt - ueber die
// Fabrikmethoden des IBP-Modells, nicht von Hand.
//
// Der Unterschied ist wesentlich: P58GenerationUnit.NewGeneratorBoiler legt die
// Komponente an, haengt sie in die Einheit und traegt den Typ im Pool des
// Gebaeudes ein. Wer stattdessen selbst ein Objekt in P58Generators schiebt,
// muesste jede dieser Verbindungen erraten.
//
//   csc /platform:x64 /out:ibp-add-boiler.exe IbpAddBoiler.cs

using System;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpAddBoiler
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.DeclaredOnly;

    private static int Main(string[] args)
    {
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        var former = new BinaryFormatter();

        object gebaeude;
        using (var s = File.OpenRead(args[0])) gebaeude = former.Deserialize(s);

        Console.WriteLine("vorher :  Erzeugertypen im Pool = " + Anzahl(gebaeude, "P58Generators")
            + ",  Heizeinheiten = " + Anzahl(gebaeude, "UnitHeating"));

        var einheit = Element(Hole(gebaeude, "UnitHeating"), 0);

        if (einheit == null) { Console.Error.WriteLine("Keine Heizeinheit."); return 1; }

        Console.WriteLine("Einheit:  " + einheit.GetType().Name + "  '" + Lies(einheit, "strName") + "'");
        Console.WriteLine("          Generators-Liste vorher = " + Anzahl2(Lies(einheit, "Generators")));

        // Die Fabrik der Einheit. pID bleibt leer - dann soll das Modell selbst
        // eine vergeben; genau das ist die Frage, die der Versuch beantwortet.
        var fabrik = Suche(einheit.GetType(), "NewGeneratorBoiler");

        if (fabrik == null) { Console.Error.WriteLine("NewGeneratorBoiler nicht gefunden."); return 1; }

        var komponente = fabrik.Invoke(einheit, new object[] { "", "Zweiter Kessel (Probe)" });

        Console.WriteLine();
        Console.WriteLine("angelegt: " + (komponente == null ? "null" : komponente.GetType().FullName));

        if (komponente != null)
        {
            Console.WriteLine("          strObjectID = " + Lies(komponente, "strObjectID"));
            Console.WriteLine("          strName     = " + Lies(komponente, "strName"));
        }

        // Die Komponente zeigt noch auf keinen Erzeugertyp. Den vorhandenen aus
        // dem Pool anhaengen - genau das meint "Erzeugertyp 1": ein Typ, den
        // mehrere Komponenten teilen koennen.
        var typ = Element(Hole(gebaeude, "P58Generators"), 0);

        Console.WriteLine();
        Console.WriteLine("Pooltyp:  " + typ.GetType().Name + "  '" + Lies(typ, "strObjectID")
            + "'  Verweise vorher = " + Lies(typ, "iReferenceCount"));

        Setze(komponente, "Generator", typ);

        Console.WriteLine("verknuepft: Generator = " + (Hole(komponente, "Generator") == null
            ? "null" : Hole(komponente, "Generator").GetType().Name)
            + ",  strGeneratorID = '" + Lies(komponente, "strGeneratorID") + "'");

        Console.WriteLine();
        Console.WriteLine("nachher:  Erzeugertypen im Pool = " + Anzahl(gebaeude, "P58Generators")
            + ",  Generators-Liste = " + Anzahl2(Lies(einheit, "Generators")));

        // Gegenprobe ueber den Datentraeger: schreiben und unabhaengig neu lesen.
        using (var s = File.Create(args[1])) former.Serialize(s, gebaeude);

        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);

        Console.WriteLine();
        Console.WriteLine("nach dem Schreiben/Lesen (" + new FileInfo(args[1]).Length + " Bytes):");
        Console.WriteLine("          Erzeugertypen im Pool = " + Anzahl(erneut, "P58Generators")
            + ",  Speicher = " + Anzahl(erneut, "P58Storages")
            + ",  Zonen = " + Anzahl(erneut, "Zones")
            + ",  Bauteile = " + Anzahl(erneut, "Constructions"));

        var einheit2 = Element(Hole(erneut, "UnitHeating"), 0);
        Console.WriteLine("          Generators-Liste = " + Anzahl2(Lies(einheit2, "Generators")));

        // Haelt die Verknuepfung den Weg ueber den Datentraeger aus? Ein
        // Objektverweis in einem serialisierten Graphen ist nur dann noch
        // derselbe, wenn beide Enden im selben Strom lagen.
        var neu2 = Element(Lies(einheit2, "Generators"), 1);
        var typ2 = Element(Hole(erneut, "P58Generators"), 0);
        var verweis = Hole(neu2, "Generator");

        Console.WriteLine("          neue Komponente  = " + Lies(neu2, "strName"));
        Console.WriteLine("          ihr Erzeugertyp  = " + (verweis == null ? "null"
            : Lies(verweis, "strObjectID") + "  (identisch mit Pool[0]: "
              + ReferenceEquals(verweis, typ2) + ")"));
        Console.WriteLine("          Baujahr am Typ   = " + Lies(verweis, "sGeneratorAge"));

        return 0;
    }

    private static void Setze(object o, string name, object wert)
    {
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var p = t.GetProperty(name, Sicht);
            if (p != null && p.CanWrite) { p.SetValue(o, wert, null); return; }
            var f = t.GetField(name, Sicht);
            if (f != null) { f.SetValue(o, wert); return; }
        }

        throw new InvalidOperationException("'" + name + "' nicht schreibbar.");
    }

    private static object Hole(object o, string name)
    {
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var p = t.GetProperty(name, Sicht);
            if (p != null) return p.GetValue(o, null);
            var f = t.GetField(name, Sicht);
            if (f != null) return f.GetValue(o);
        }
        return null;
    }

    private static object Lies(object o, string name)
    {
        var w = Hole(o, name);
        return w == null ? "(leer)" : w;
    }

    private static MethodInfo Suche(Type t, string name)
    {
        for (var akt = t; akt != null; akt = akt.BaseType)
        {
            var m = akt.GetMethod(name, Sicht);
            if (m != null) return m;
        }
        return null;
    }

    private static object Element(object sammlung, int i)
    {
        if (sammlung == null) return null;
        var idx = sammlung.GetType().GetProperty("Item", new[] { typeof(int) });
        return idx == null ? null : idx.GetValue(sammlung, new object[] { i });
    }

    private static int Anzahl(object gebaeude, string sammlung)
    {
        return Anzahl2(Hole(gebaeude, sammlung));
    }

    private static int Anzahl2(object sammlung)
    {
        if (sammlung == null || sammlung is string) return -1;
        var p = sammlung.GetType().GetProperty("Count");
        return p == null ? -1 : (int) p.GetValue(sammlung, null);
    }
}
