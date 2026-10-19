// Legt eine Lueftungsanlage mit Waermerueckgewinnung im IBP-Modell an.
//
// Aufbau, abgelesen an zwei erprobten Anlagen:
//
//   DIN18599Building.NewUnitRV              -> P6RVSystemUnit      die Anlage
//   DIN18599Building.NewCircuitHeatAirRV    -> P6HeatAirCircuit    der Luftkreis
//   DIN18599Building.NewEmissionHeatAirRV   -> P6HeatAirEmission   Pooltyp
//   Kreis.NewDistribution                   -> P6HeatAirDistribution
//   Kreis.NewEmissionHeatAir                -> Uebergabekomponente
//
// Dazu drei Verknuepfungen, ohne die die Anlage im Modell steht und nicht
// rechnet:
//   Uebergabe.strIDLink          -> Zone
//   Uebergabe.strLinkedRVDomain  -> P6RVDomain in der Zone
//   UnitCircuitInterrelation     -> Einheit <-> Kreis (wie bei der Heizung)
//
//   csc /platform:x64 /out:ibp-rv-setzen.exe IbpRV.cs
//   ibp-rv-setzen.exe <blob.bin> <neu.bin> [wrg=0.9] [vorwaermung=1] [zone=0]

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpRV
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    private static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("Aufruf: ibp-rv-setzen.exe <blob.bin> <neu.bin> [wrg=0.9] [vorwaermung=1] [zone=0]");
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

        if (Zahl(Hole(g, "UnitRV")) > 0)
        {
            Console.Error.WriteLine("Es gibt schon eine Lueftungsanlage - erst entfernen.");
            return 1;
        }

        var zone = Element(Hole(g, "Zones"), Ganz(w, "zone", 0));
        if (zone == null) { Console.Error.WriteLine("Zone gibt es nicht"); return 1; }
        var zoneID = (string) Hole(zone, "strObjectID");

        var einheit = Neu(g, "NewUnitRV", "P6RVSystemUnit", "Lueftungsanlage", g, "UnitRV");
        var kreis = Neu(g, "NewCircuitHeatAirRV", "P6HeatAirCircuit", "Luftkreis", g, "CircuitHeatAirRV");
        // Geometrie aus dem Gebaeude uebernehmen - am Kreis wie an der Anlage.
        // bAdoptGeometry allein genuegt nicht: das Kennzeichen steht, die
        // Werte bleiben auf 0. Sie werden deshalb aus BuildingGeometry
        // uebertragen, so wie es die Software auch tut.
        Setze(kreis, "bAdoptGeometry", true);
        var bauGeo = Hole(g, "BuildingGeometry");
        var kreisGeo = Hole(kreis, "Geometry");
        if (bauGeo != null && kreisGeo != null)
            foreach (var feld in new[] { "fA_NGF", "fB", "fL", "fh_G", "sn_G" })
                Setze(kreisGeo, feld, Hole(bauGeo, feld));

        // ---- Anlage: Waermerueckgewinnung und Betriebsart
        var wrg = Komma(w, "wrg", 0.9f);
        Setze(einheit, "bRVHeatExchanger", true);
        Setze(einheit, "feta_WRG", wrg);

        // OHNE DIESE ZEILE IST feta_WRG WIRKUNGSLOS. Die Fabrik setzt
        // beta_WRG_Standard auf True, dann rechnet das Modell mit seinem
        // eigenen Wirkungsgrad und ignoriert den gesetzten. Aufgefallen nur
        // im Feldvergleich gegen eine von der Software gebaute Anlage: dort
        // steht False.
        Setze(einheit, "beta_WRG_Standard", false);

        // Die Fabrik laesst das Baujahr auf 1988 stehen - eine neu geplante
        // Lueftungsanlage waere damit 38 Jahre alt.
        Setze(einheit, "sSystemAge", (short) Ganz(w, "baujahr", 2026));

        // Geometrie aus dem Gebaeude uebernehmen; sonst bleiben Laenge,
        // Breite, Hoehe und Nettogrundflaeche auf 0.
        Setze(einheit, "bAdoptGeometry", true);
        Setze(einheit, "bCalculateAuxiliaryEnergyControl", false);
        Setze(einheit, "ff_v_WUET_Frost", Komma(w, "frostfaktor", -0.04f));
        Setze(einheit, "bElectricalPreheating", Ganz(w, "vorwaermung", 1) != 0);
        Setze(einheit, "bCalculateAuxiliaryEnergyFans", true);
        Setze(einheit, "enumRVOperatingMode", (short) Ganz(w, "betriebsart", 1));
        Setze(einheit, "enumUnitType", (short) Ganz(w, "anlagenart", 2));
        Setze(einheit, "enumFanType", (short) Ganz(w, "ventilator", 1));
        Setze(einheit, "enumDefrostingOperation", (short) Ganz(w, "abtauung", 2));
        Setze(einheit, "enumAirTightnessVentilationUnit", (short) Ganz(w, "dichtheit", 1));
        Setze(einheit, "enumHeatLossVentilationUnit", (short) Ganz(w, "geraeteverlust", 3));
        Setze(einheit, "fp_el_Vent", Komma(w, "leistung", 0.35f));
        Setze(einheit, "ff_EWUET", Komma(w, "erdwaermetauscher", 0.2f));
        Setze(einheit, "ftheta_ActivationFrostPrevention", Komma(w, "frostschutz", -7f));

        // ---- Kreis: Verteilung und Uebergabe
        var vert = Neu(kreis, "NewDistribution", "P6HeatAirDistribution", "Verteilung", kreis, "Distributions");
        Setze(vert, "enumTypeOfDistribution", (short) 2);   // HeatingDHW.RV

        var uebTyp = Neu(g, "NewEmissionHeatAirRV", "P6HeatAirEmission", "Uebergabetyp", g, "P58Emissions");
        var ueb = Neu(kreis, "NewEmissionHeatAir", "P5HeatEmissionComponent", "Uebergabe", kreis, "Emissions");
        Setze(ueb, "Emission", uebTyp);
        Setze(ueb, "strIDLink", zoneID);
        Setze(ueb, "fContribution", 1f);

        // ---- Verknuepfung zur Zone ueber die RV-Domaene
        //
        // Die Domaene wird NICHT von der Uebergabe mitgebracht - sie muss an
        // der Zone erzeugt werden. Ohne sie steht die Anlage im Modell und die
        // Zone weiss nichts von ihr; gerechnet wird dann weiter mit
        // Fensterlueftung, ohne dass irgendetwas gemeldet wuerde.
        var lueftung = Hole(zone, "ZoneVentilation");
        if (lueftung == null) { Console.Error.WriteLine("Zone fuehrt keine ZoneVentilation"); return 1; }
        var domaene = Ruf(lueftung, "AddDomainForMechanicalVentilationForResidentialZone",
                          new object[] { Kennung("P6RVDomain", 1), "RV-Bereich 1" });
        if (domaene == null) { Console.Error.WriteLine("RV-Domaene liess sich nicht anlegen"); return 1; }
        Setze(ueb, "strLinkedRVDomain", (string) Hole(domaene, "strObjectID"));

        var domaenen = Hole(lueftung, "DomainsForMechanicalVentilationForResidentialZones");
        Console.WriteLine("  RV-Bereiche in der Zone: " + Zahl(domaenen)
            + "   verknuepft mit " + Hole(ueb, "strLinkedRVDomain"));

        // ---- Matrix Einheit <-> Kreis, wie bei der Heizung
        var matrix = Hole(g, "UnitCircuitInterrelation");
        var vorher = Zahl(Hole(matrix, "Interrelations"));
        Ruf(matrix, "AddRelation", new object[]
            { (string) Hole(einheit, "strObjectID"), (string) Hole(kreis, "strObjectID"), 1f });
        Anhaengen(Hole(einheit, "alReferenceList"), (string) Hole(kreis, "strObjectID"));
        Anhaengen(Hole(kreis, "alReferenceList"), (string) Hole(einheit, "strObjectID"));
        var nachher = Zahl(Hole(matrix, "Interrelations"));
        Console.WriteLine("  Matrix: " + vorher + " -> " + nachher);

        Console.WriteLine("  Lueftung: WRG " + Z(wrg) + ", Vorerwaermung "
            + (Ganz(w, "vorwaermung", 1) != 0 ? "ja" : "nein"));

        using (var s = File.Create(args[1])) new BinaryFormatter().Serialize(s, g);

        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);
        if (Zahl(Hole(erneut, "UnitRV")) != 1 || Zahl(Hole(erneut, "CircuitHeatAirRV")) != 1)
        {
            Console.Error.WriteLine("Gegenprobe: Anlage nicht vollstaendig zurueckgelesen");
            return 1;
        }
        Console.WriteLine("  " + new FileInfo(args[1]).Length + " B, Gegenprobe bestanden");
        return 0;
    }

    private static string Z(float f) { return f.ToString("0.##", CultureInfo.InvariantCulture); }

    private static float Komma(Dictionary<string, string> d, string n, float v)
    {
        string s;
        return d.TryGetValue(n, out s) ? float.Parse(s.Replace(',', '.'), CultureInfo.InvariantCulture) : v;
    }

    private static int Ganz(Dictionary<string, string> d, string n, int v)
    {
        string s;
        return d.TryGetValue(n, out s) ? int.Parse(s, CultureInfo.InvariantCulture) : v;
    }

    private static string Kennung(string typ, int nr)
    {
        unchecked
        {
            uint h = 2166136261;
            foreach (var c in typ + "_" + nr) { h ^= c; h *= 16777619; }
            return typ + "_" + nr + "[" + h.ToString("X8") + "]";
        }
    }

    private static object Neu(object wirt, string fabrik, string typname, string bez,
                              object besitzer, string sammlung)
    {
        for (var nr = 1; nr < 1000; nr++)
        {
            var vor = Zahl(Hole(besitzer, sammlung));
            var o = Ruf(wirt, fabrik, new object[] { Kennung(typname, nr), bez + " " + nr });
            if (Zahl(Hole(besitzer, sammlung)) > vor) return o;
        }
        throw new InvalidOperationException("keine freie Kennung fuer " + typname);
    }

    private static object Ruf(object o, string name, object[] args)
    {
        var typen = new Type[args.Length];
        for (var i = 0; i < args.Length; i++) typen[i] = args[i].GetType();
        for (var t = o.GetType(); t != null; t = t.BaseType)
        {
            var m = t.GetMethod(name, Sicht | BindingFlags.DeclaredOnly, null, typen, null);
            if (m != null) return m.Invoke(o, args);
        }
        Console.Error.WriteLine("  ! " + name + " nicht gefunden an " + o.GetType().Name);
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

    // Die Verweislisten sind IBPArrayList, kein IList - Add heisst dort Add,
    // aber ueber Reflexion, und doppelte Eintraege sind zu vermeiden.
    private static void Anhaengen(object liste, string id)
    {
        if (liste == null) return;
        for (var i = 0; i < Zahl(liste); i++)
            if ((string) Element(liste, i) == id) return;
        Ruf(liste, "Add", new object[] { id });
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
