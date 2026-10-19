// Liest die Anlagentechnik eines Projekts als JSON aus - Erzeugung, Uebergabe,
// Verteilung, Warmwasser. Gegenstueck zu ibp-build-heating.exe, das dasselbe
// Format schreibt.
//
//   ibp-anlage-lesen.exe <blob.bin>
//
// Zweck: eine vorhandene Anlage aus einem Projekt uebernehmen, ohne sie von
// Hand abzutippen. Das Format ist zugleich die Uebergabe fuer eine externe
// Quelle - wer die Werte liefert, ist fuer die Werkzeuge unerheblich.
//
// Ausgegeben werden nur die Felder, die beim Anlegen gebraucht werden. Alles
// Abgeleitete (Wirkungsgrade, Hilfsenergie, Leitungslaengen) bleibt draussen:
// das rechnet das Modell aus b*_Standard selbst, und wer es vorgibt, bringt
// die Oberflaeche zum Haengen.
//
//   csc /platform:x64 /out:ibp-anlage-lesen.exe IbpAnlageLesen.cs

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;
using System.Text;

internal static class IbpAnlageLesen
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

        var j = new Json();
        j.Auf("{");

        // ------------------------------------------------------------ Heizung
        var einheit = Element(Hole(g, "UnitHeating"), 0);
        var kreis = Element(Hole(g, "CircuitHeatWater"), 0);

        j.Zeile("\"heizung\": " + (einheit == null ? "null," : "{"));
        if (einheit != null)
        {
            j.Ein();
            j.Zeile("\"name\": " + Text(Hole(einheit, "strName")) + ",");

            // Auslegungstemperatur des Heizkreises - der Wert, den die
            // Oberflaeche in der Verteilung anzeigt. Er stand hier lange nicht
            // drin, und weil der Schreiber ihn braucht, verlor jeder Rundlauf
            // ueber lesen -> loeschen -> setzen die Auslegung des Projekts und
            // ersetzte sie still durch die Vorgabe 70/55.
            // 0/0 heisst "nie gesetzt"; dann rechnet das Modell mit 70/55.
            var kva = Grad(Hole(kreis, "ftheta_VA"));
            var kra = Grad(Hole(kreis, "ftheta_RA"));
            if (kva > 0)
                j.Zeile("\"auslegung\": { \"vorlauf\": " + Zahl2(kva)
                    + ", \"ruecklauf\": " + Zahl2(kra) + " },");

            // Erzeuger - je Komponente Bauart, Baujahr, Brennstoff, Leistung
            j.Zeile("\"erzeuger\": [");
            j.Ein();
            var gen = Hole(einheit, "Generators");
            for (var i = 0; i < Zahl(gen); i++)
            {
                var k = Element(gen, i);
                var typ = Hole(k, "Generator");
                var teile = new List<string>
                {
                    // Die Bauart kommt vom POOLTYP, nicht von der Komponente,
                    // und als voller Klassenname. Zwei Gruende, beide beim
                    // Rundlauf ueber 84 Projekte aufgefallen:
                    // Einzelofen und Elektroheizer teilen sich dieselbe
                    // Komponentenklasse P58HeatGeneratorComponent - aus ihr
                    // laesst sich die Bauart nicht zurueckgewinnen. Und die
                    // Kurznamen sind nicht eindeutig umkehrbar: aus
                    // P5HeatGeneratorBiomassManuallyLoaded wird "Biomass-
                    // ManuallyLoaded", die Fabrik heisst aber
                    // NewHeatGeneratorBiomassManually.
                    // Der Schreiber nimmt beides an, kurz wie voll.
                    "\"bauart\": " + Text((typ ?? k).GetType().Name),
                    "\"name\": " + Text(Hole(k, "strName")),
                    "\"brennstoff\": " + Text(Hole(k, "strEnergySource")),
                    "\"leistung_kw\": " + Zahl2(Hole(k, "fQdot_N")),
                    "\"vorlauf\": " + Zahl2(Hole(k, "ftheta_VA")),
                    "\"ruecklauf\": " + Zahl2(Hole(k, "ftheta_RA")),
                };
                if (typ != null)
                {
                    // Kessel und Waermepumpe fuehren verschiedene Felder. Die
                    // Kesselfelder an einer Waermepumpe auszulesen ergibt null
                    // und verschleiert, dass der Typ woanders steht.
                    if (typ.GetType().Name.Contains("HeatPump"))
                        teile.Add("\"wp_typ\": " + Zahl2(Hole(typ, "enumHeatPumpType")));
                    else
                    {
                        teile.Add("\"typ\": " + Zahl2(Hole(typ, "enumBoilerType")));
                        teile.Add("\"zusatz\": " + Zahl2(Hole(typ, "enumBoilerTypeAdditional")));
                    }
                    teile.Add("\"baujahr\": " + Zahl2(Hole(typ, "sGeneratorAge")));
                }
                j.Zeile("{ " + string.Join(", ", teile) + " }" + (i + 1 < Zahl(gen) ? "," : ""));
            }
            j.Aus(); j.Zeile("],");

            // Speicher an der Heizung. Die Eigenschaft heisst Storage, nicht
            // Storages - mit dem Plural liest man still null und uebersieht
            // einen vorhandenen Pufferspeicher.
            j.Zeile("\"speicher\": [");
            j.Ein();
            var sp = Hole(einheit, "Storage");
            for (var i = 0; i < Zahl(sp); i++)
            {
                var k = Element(sp, i);
                var st = Hole(k, "Storage");
                j.Zeile("{ \"name\": " + Text(Hole(k, "strName"))
                    + ", \"baujahr\": " + (st == null ? "null" : Zahl2(Hole(st, "sAgeStorage")))
                    + ", \"zirkulation\": " + (st != null && Hole(st, "bCirculationPumpDHW") as bool? == true ? "true" : "false")
                    + ", \"gleicher_raum\": " + (Hole(k, "bStorageGeneratorSameRoom") as bool? == true ? "true" : "false")
                    + " }" + (i + 1 < Zahl(sp) ? "," : ""));
            }
            j.Aus(); j.Zeile("],");

            // Uebergabe
            // Ein Heizkreis kann mehrere Uebergaben fuehren - Heizkoerper im
            // Wohnbereich neben einer Flaechenheizung im Bad ist der uebliche
            // Fall. Frueher stand hier nur die erste; beim Rundlauf verlor ein
            // Projekt der Erhebung dadurch stillschweigend seine zweite.
            // Deshalb eine Liste. Der Schreiber nimmt weiterhin auch ein
            // einzelnes Objekt an, damit aeltere Austauschdateien gelten.
            var uebs = kreis == null ? null : Hole(kreis, "Emissions");
            j.Zeile("\"uebergabe\": [");
            j.Ein();
            for (var i = 0; i < Zahl(uebs); i++)
            {
                var ueb = Element(uebs, i);
                var uebTyp = Hole(ueb, "Emission");
                if (uebTyp == null) continue;
                j.Zeile("{ "
                    + "\"bauart\": " + Text(uebTyp.GetType().Name) + ", "
                    + "\"regelung\": " + Zahl2(Hole(uebTyp, "enumControlType")) + ", "
                    + "\"raumhoehe\": " + Zahl2(Hole(uebTyp, "fRoomHeight")) + ", "
                    + "\"anteil\": " + Zahl2(Hole(ueb, "fContribution")) + ", "
                    + "\"zone\": " + Text(Hole(ueb, "strIDLink")) + " }"
                    + (i + 1 < Zahl(uebs) ? "," : ""));
            }
            j.Aus(); j.Zeile("],");

            // Verteilung mit Leitungen und Pumpen
            var vert = kreis == null ? null : Element(Hole(kreis, "Distributions"), 0);
            if (vert == null) j.Zeile("\"verteilung\": null");
            else
            {
                j.Zeile("\"verteilung\": {");
                j.Ein();
                j.Zeile("\"netz\": " + Zahl2(Hole(vert, "enumNetworkType")) + ",");
                j.Zeile("\"gamma\": " + Zahl2(Hole(vert, "fGamma")) + ",");
                j.Zeile("\"heizkoerper\": " + Zahl2(Hole(vert, "sNumberOfRadiators")) + ",");
                // Netzform und Gebaeudegruppe der Heizungsverteilung.
                // HdNetTypeHeating 0 Etagenring, 1 Etagenverteilung,
                // 2 Steigestraenge, 3 Strahlungs-/Luftheizung,
                // 4 Etagenverteilung im Fussboden.
                j.Zeile("\"netz_heizung\": " + Zahl2(Hole(vert, "enumNetworkTypeHeating")) + ",");
                j.Zeile("\"gruppe\": " + Zahl2(Hole(vert, "enumBuildingGroup")) + ",");
                // Hydraulischer Abgleich. Er steht an zwei Stellen: als
                // Aufzaehlung HdHydraulicBalance an der Verteilung und als
                // Kreuz an jeder Pumpe. Beide gehoeren zusammen.
                j.Zeile("\"abgleich\": " + Zahl2(Hole(vert, "enumHydraulicBalance")) + ",");
                j.Zeile("\"abgleich_pumpe\": "
                    + (Hole(Element(Hole(vert, "Pumps"), 0), "bHydraulicBalance") as bool? == true
                        ? "true" : "false") + ",");

                var rohre = Hole(vert, "Pipes");
                j.Zeile("\"leitungen\": [");
                j.Ein();
                for (var i = 0; i < Zahl(rohre); i++)
                {
                    var r = Element(rohre, i);
                    var rt = Hole(r, "Pipe");
                    j.Zeile("{ \"art\": " + Zahl2(Hole(r, "enumPipeType"))
                        + ", \"lage\": " + Zahl2(Hole(r, "enumPositionType"))
                        + ", \"daemmung\": " + (rt == null ? "null" : Zahl2(Hole(rt, "enumPipeInsulation")))
                        + " }" + (i + 1 < Zahl(rohre) ? "," : ""));
                }
                j.Aus(); j.Zeile("],");
                // Pumpenregelung: HdPumpControl 0 ungeregelt,
                // 1 delta-p konstant, 2 delta-p variabel.
                // Auslegung: HdDimensioningPump 0 ueberdimensioniert,
                // 1 optimiert.
                var pu0 = Element(Hole(vert, "Pumps"), 0);
                if (pu0 != null)
                {
                    j.Zeile("\"pumpe_regelung\": " + Zahl2(Hole(pu0, "enumPumpControl")) + ",");
                    j.Zeile("\"pumpe_auslegung\": " + Zahl2(Hole(Hole(pu0, "Pump"), "enumDimensioningPump")) + ",");
                }
                j.Zeile("\"pumpen\": " + Zahl(Hole(vert, "Pumps")));
                j.Aus(); j.Zeile("}");
            }
            j.Aus(); j.Zeile("},");
        }

        // -------------------------------------------------------- Warmwasser
        var wwEinheit = Element(Hole(g, "UnitDHW"), 0);
        var wwKreis = Element(Hole(g, "CircuitDHW"), 0);
        j.Zeile("\"warmwasser\": " + (wwEinheit == null ? "null," : "{"));
        if (wwEinheit != null)
        {
            j.Ein();
            j.Zeile("\"name\": " + Text(Hole(wwEinheit, "strName")) + ",");
            j.Zeile("\"erzeuger\": [");
            j.Ein();
            var wg = Hole(wwEinheit, "Generators");
            for (var i = 0; i < Zahl(wg); i++)
            {
                var k = Element(wg, i);
                j.Zeile("{ \"bauart\": " + Text(Bauart(k))
                    + ", \"name\": " + Text(Hole(k, "strName"))
                    + ", \"brennstoff\": " + Text(Hole(k, "strEnergySource"))
                    + " }" + (i + 1 < Zahl(wg) ? "," : ""));
            }
            j.Aus(); j.Zeile("],");
            var wsp = Hole(wwEinheit, "Storage");
            j.Zeile("\"speicher\": [");
            j.Ein();
            for (var i = 0; i < Zahl(wsp); i++)
            {
                var k = Element(wsp, i);
                var st = Hole(k, "Storage");
                j.Zeile("{ \"name\": " + Text(Hole(k, "strName"))
                    + ", \"baujahr\": " + (st == null ? "null" : Zahl2(Hole(st, "sAgeStorage")))
                    + ", \"zirkulation\": " + (st != null && Hole(st, "bCirculationPumpDHW") as bool? == true ? "true" : "false")
                    + " }" + (i + 1 < Zahl(wsp) ? "," : ""));
            }
            j.Aus(); j.Zeile("],");
            // Verteilung des Warmwasserkreises. Sie stand hier lange nicht
            // drin, und der Schreiber legte auch keine an - beidseitig blind,
            // deshalb fiel beim Rundlauf nichts auf. 18 der 84 erhobenen
            // Projekte hatten am Ende gar keine Warmwasser-Verteilung mehr.
            var wv = wwKreis == null ? null : Element(Hole(wwKreis, "Distributions"), 0);
            if (wv == null) j.Zeile("\"verteilung\": null,");
            else
            {
                j.Zeile("\"verteilung\": { "
                    + "\"netz\": " + Zahl2(Hole(wv, "enumNetTypeDHW")) + ", "
                    + "\"zirkulation\": " + Zahl2(Hole(wv, "enumCirculation")) + ", "
                    + "\"gruppe\": " + Zahl2(Hole(wv, "enumBuildingGroup")) + ", "
                    + "\"zentral\": " + Zahl2(Hole(wv, "enumDistributionType")) + ", "
                    + "\"system\": " + Zahl2(Hole(wv, "enumDHWSystemType")) + " },");
            }
            j.Zeile("\"kreis\": " + (wwKreis == null ? "null" : Text(Hole(wwKreis, "strName"))));
            j.Aus(); j.Zeile("},");
        }

        // ------------------------------------------------------------- Pools
        j.Zeile("\"bestand\": { "
            + "\"erzeugertypen\": " + Zahl(Hole(g, "P58Generators")) + ", "
            + "\"uebergabetypen\": " + Zahl(Hole(g, "P58Emissions")) + ", "
            + "\"leitungstypen\": " + Zahl(Hole(g, "P58CircuitPipes")) + ", "
            + "\"pumpentypen\": " + Zahl(Hole(g, "P58CircuitPumps")) + ", "
            + "\"speichertypen\": " + Zahl(Hole(g, "P58Storages")) + ", "
            + "\"zonen\": " + Zahl(Hole(g, "Zones")) + ", "
            + "\"bauteile\": " + Zahl(Hole(g, "Constructions")) + " }");

        j.Aus(); j.Zeile("}");
        Console.Write(j);
        return 0;
    }

    private sealed class Json
    {
        private readonly StringBuilder sb = new StringBuilder();
        private int tiefe;
        public void Auf(string s) { sb.AppendLine(s); tiefe++; }
        public void Ein() { tiefe++; }
        public void Aus() { tiefe--; }
        public void Zeile(string s) { sb.Append(new string(' ', tiefe * 2)).AppendLine(s); }
        public override string ToString() { return sb.ToString(); }
    }

    // Aus dem Klassennamen die Bauart gewinnen. Reihenfolge der Praefixe ist
    // wichtig: P58HeatGeneratorHeatPumpComponent muss "HeatPump" ergeben, nicht
    // "P58HeatGeneratorHeatPump" - der DHW-Praefix greift dort naemlich nicht.
    private static string Bauart(object k)
    {
        var n = k.GetType().Name;
        foreach (var p in new[] { "P58HeatGenerator", "P5HeatGenerator", "P8DHWGenerator",
                                  "P58HeatEmission", "P5HeatEmission" })
            if (n.StartsWith(p)) { n = n.Substring(p.Length); break; }
        if (n.EndsWith("Component")) n = n.Substring(0, n.Length - "Component".Length);
        return n;
    }

    private static string Text(object o)
    {
        if (o == null) return "null";
        return "\"" + o.ToString().Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }

    // Temperaturfeld als Zahl. null und der Sentinel -987654321,99 werden 0 -
    // beides heisst "nicht gesetzt", und 0 ist genau das, was das Modell in
    // diesem Fall selbst im Blob stehen hat.
    private static double Grad(object o)
    {
        if (o == null) return 0;
        var d = Convert.ToDouble(o, CultureInfo.InvariantCulture);
        return d < -1e9 ? 0 : d;
    }

    private static string Zahl2(object o)
    {
        if (o == null) return "null";
        if (o is float || o is double)
        {
            var d = Convert.ToDouble(o);
            if (d < -1e9) return "null";           // Sentinel -987654321,99
            return d.ToString("0.####", CultureInfo.InvariantCulture);
        }
        return Convert.ToInt64(o).ToString(CultureInfo.InvariantCulture);
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
        if (p != null) return (int) p.GetValue(s, null);
        var a = s as Array;
        return a != null ? a.Length : 0;
    }
}
