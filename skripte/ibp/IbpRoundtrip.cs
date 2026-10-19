// Probe: laesst sich der IBP-Graph aendern und zurueckschreiben?
//
// Nicht-zerstoerend: liest die Vorlage, aendert EIN Feld am Kessel, schreibt in
// eine NEUE Datei und liest die wieder ein. Die Vorlage bleibt unberuehrt.
//
//   csc /platform:x64 /out:ibp-roundtrip.exe IbpRoundtrip.cs

using System;
using System.Collections;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpRoundtrip
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private static int Main(string[] args)
    {
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var pfad = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(pfad) ? Assembly.LoadFrom(pfad) : null;
        };

        string quelle = args[0];
        string ziel = args[1];

        var former = new BinaryFormatter();

        object gebaeude;
        using (var s = File.OpenRead(quelle)) gebaeude = former.Deserialize(s);

        var kessel = ErstesGeraet(gebaeude, "P58Generators");

        if (kessel == null) { Console.Error.WriteLine("Kein Erzeuger gefunden."); return 1; }

        Console.WriteLine("Erzeuger: " + kessel.GetType().FullName);

        Console.WriteLine("vorher :  Baujahr=" + Lies(kessel, "sGeneratorAge")
            + "  enumBoilerType=" + Lies(kessel, "enumBoilerType"));

        // Eine einzige, klar erkennbare Aenderung.
        Schreibe(kessel, "sGeneratorAge", 2015);

        using (var s = File.Create(ziel)) former.Serialize(s, gebaeude);

        Console.WriteLine("geschrieben: " + new FileInfo(ziel).Length + " Bytes  (Vorlage: "
            + new FileInfo(quelle).Length + ")");

        // Gegenprobe: die neue Datei unabhaengig einlesen.
        object erneut;
        using (var s = File.OpenRead(ziel)) erneut = new BinaryFormatter().Deserialize(s);

        var kessel2 = ErstesGeraet(erneut, "P58Generators");

        Console.WriteLine("nachher:  Baujahr=" + Lies(kessel2, "sGeneratorAge")
            + "  enumBoilerType=" + Lies(kessel2, "enumBoilerType"));

        // Zaehlt gegen, dass der uebrige Graph mitgekommen ist.
        Console.WriteLine("Gegenprobe Bestand:  Zonen=" + Anzahl(erneut, "Zones")
            + "  Erzeuger=" + Anzahl(erneut, "P58Generators")
            + "  Speicher=" + Anzahl(erneut, "P58Storages")
            + "  Uebergaben=" + Anzahl(erneut, "P58Emissions")
            + "  Leitungen=" + Anzahl(erneut, "P58CircuitPipes")
            + "  Bauteile=" + Anzahl(erneut, "Constructions"));

        return 0;
    }

    /// <summary>
    /// IBPHashtable ist KEINE IDictionary, sondern eine eigene Sammlung mit
    /// Count und zwei Indexern (nach Position und nach Schluessel). Der Zugriff
    /// laeuft deshalb ueber Reflexion auf den int-Indexer.
    /// </summary>
    private static object ErstesGeraet(object gebaeude, string sammlung)
    {
        var tabelle = Hole(gebaeude, sammlung);

        if (tabelle == null || Anzahl(gebaeude, sammlung) < 1) return null;

        var indexer = tabelle.GetType().GetProperty("Item", new[] { typeof(int) });

        return indexer == null ? null : indexer.GetValue(tabelle, new object[] { 0 });
    }

    private static int Anzahl(object gebaeude, string sammlung)
    {
        var t = Hole(gebaeude, sammlung);

        if (t == null) return -1;

        var p = t.GetType().GetProperty("Count");

        return p == null ? -1 : (int) p.GetValue(t, null);
    }

    // Die Werte des IBP-Modells sind Eigenschaften, nicht Felder - und sie
    // sitzen teils auf Basisklassen. Deshalb die Kette von der konkreten Klasse
    // aufwaerts absuchen, Eigenschaft wie Feld.
    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.DeclaredOnly;

    private static object Lies(object o, string name)
    {
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var p = t.GetProperty(name, Sicht);
            if (p != null) return p.GetValue(o, null);

            var f = t.GetField(name, Sicht);
            if (f != null) return f.GetValue(o);
        }

        return "(nicht gefunden)";
    }

    private static void Schreibe(object o, string name, object wert)
    {
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var p = t.GetProperty(name, Sicht);
            if (p != null && p.CanWrite) { p.SetValue(o, Convert.ChangeType(wert, p.PropertyType), null); return; }

            var f = t.GetField(name, Sicht);
            if (f != null) { f.SetValue(o, Convert.ChangeType(wert, f.FieldType)); return; }
        }

        throw new InvalidOperationException("Mitglied '" + name + "' nicht schreibbar.");
    }

    private static object Hole(object o, string name)
    {
        var f = o.GetType().GetField(name, BindingFlags.Public | BindingFlags.Instance);
        if (f != null) return f.GetValue(o);

        var p = o.GetType().GetProperty(name, BindingFlags.Public | BindingFlags.Instance);
        return p != null ? p.GetValue(o, null) : null;
    }
}
