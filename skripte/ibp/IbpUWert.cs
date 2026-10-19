// Setzt die U-Werte im IBP-Rechenmodell einer Variante.
//
// WARUM ES DIESES WERKZEUG BRAUCHT
//
// SANK_ZAHL in TableHuellfl aendert nur, was die Flaechenelemente-Liste
// ANZEIGT. Gerechnet wird aus dem IBP-Blob, und der kennt SANK_ZAHL nicht.
// Eine Variante, die nur ueber saniere.ps1 gebaut wurde, zeigt saniere
// U-Werte und rechnet mit den alten: gemessen an einem Fahrplan mit Dach
// 0,14, Fenster 0,95, Wand 0,20 sank die Nutzenergie um 6 % statt um ein
// Drittel, und H'T blieb auf dem Ist-Wert.
//
// WO DER U-WERT STEHT
//
//   Zone.ConstructionElements[i].Construction.fU      opakes Bauteil
//   …[i].FenestrationSystems[q].Window.fU             Fenster
//
// Beide sind beschreibbar, und LayerOfConstructions ist bei diesen Modellen
// leer - der U-Wert wird also nicht aus Schichten nachgerechnet und bleibt
// stehen. Fenster haengen als FenestrationSystem am Bauteil; das Bauteil
// selbst traegt dann fA = 0. Deshalb sind es zwei getrennte Angaben:
// "u" fuer den Aufbau, "fenster" fuer die Verglasung.
//
// ZUORDNUNG
//
// Ueber die Reihenfolge, mit Namensprobe. Die Liste im JSON muss so lang sein
// wie die Bauteilliste der Zone, und Name fuer Name uebereinstimmen - sonst
// Abbruch. Ueber strObjectID ginge es nicht: dort steht die HUELL_ID der
// VORLAGE, weil der Blob beim Anlegen einer Variante unveraendert mitkopiert
// wird.
//
//   csc /platform:x64 /out:ibp-uwert-setzen.exe IbpUWert.cs
//       /r:System.Web.Extensions.dll
//   ibp-uwert-setzen.exe <blob.bin> <neu.bin> <uwerte.json> [zone=0]
//   ibp-uwert-setzen.exe <blob.bin> -         <uwerte.json> [zone=0]
//
// Mit "-" statt einer Ausgabedatei wird nur GEPRUEFT: stimmt das Rechenmodell
// mit der Bauteilliste ueberein? Rueckgabe 1, wenn nicht. Das ist die
// Querprobe zwischen den beiden Darstellungen desselben Sachverhalts - und die
// einzige Pruefung, die den Fehler findet, wegen dem dieses Werkzeug entstand.
//
//   { "bauteile": [ { "name": "Roof 001-1", "u": 0.14 },
//                   { "name": "F 011-1",    "fenster": 0.95 } ] }

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;
using System.Web.Script.Serialization;

internal static class IbpUWert
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private const BindingFlags Sicht = BindingFlags.Public | BindingFlags.NonPublic
        | BindingFlags.Instance | BindingFlags.FlattenHierarchy;

    private static int Main(string[] args)
    {
        if (args.Length < 3)
        {
            Console.Error.WriteLine("Aufruf: ibp-uwert-setzen.exe <blob.bin> <neu.bin> <uwerte.json> [zone=0]");
            return 2;
        }
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        var zoneNr = 0;
        foreach (var a in args) if (a.StartsWith("zone=")) zoneNr = int.Parse(a.Substring(5));

        object g;
        using (var s = File.OpenRead(args[0])) g = new BinaryFormatter().Deserialize(s);

        var wurzel = (Dictionary<string, object>) new JavaScriptSerializer()
            .DeserializeObject(File.ReadAllText(args[2]));
        var liste = new List<Dictionary<string, object>>();
        foreach (var e in (object[]) wurzel["bauteile"]) liste.Add((Dictionary<string, object>) e);

        var zone = Element(Hole(g, "Zones"), zoneNr);
        if (zone == null) { Console.Error.WriteLine("Zone " + zoneNr + " gibt es nicht"); return 1; }
        var teile = Hole(zone, "ConstructionElements");

        if (Zahl(teile) != liste.Count)
        {
            Console.Error.WriteLine("Zone hat " + Zahl(teile) + " Bauteile, die Liste nennt "
                + liste.Count + " - das passt nicht zusammen");
            return 1;
        }

        var nurPruefen = args[1] == "-";
        int opak = 0, fenster = 0, abweichung = 0;
        for (var i = 0; i < liste.Count; i++)
        {
            var t = Element(teile, i);
            var soll = "" + Wert(liste[i], "name");
            var ist = "" + Hole(t, "strName");
            // Ist ein Bauteil mit einem Katalogaufbau belegt, haengt die
            // Software dessen Namen an: aus "DF 001-1" wird
            // "DF 001-1 - 3-fach WSV". Der Tabellenname bleibt der kurze.
            // Deshalb genuegt ein vollstaendiger Namensanfang - das erkennt
            // eine verschobene Zuordnung immer noch ("DF 001-1" passt nicht
            // auf "DF 002-1 - …"), laesst aber den Katalogzusatz zu.
            if (soll != ist && !ist.StartsWith(soll + " ", StringComparison.Ordinal))
            {
                Console.Error.WriteLine("Bauteil " + (i + 1) + ": Liste sagt '" + soll
                    + "', Modell sagt '" + ist + "' - Reihenfolge stimmt nicht, Abbruch");
                return 1;
            }

            if (liste[i].ContainsKey("u"))
            {
                var bau = Hole(t, "Construction");
                if (bau == null)
                {
                    Console.Error.WriteLine("Bauteil " + (i + 1) + " '" + ist + "' hat keinen Aufbau");
                    return 1;
                }
                var neu = (float) Convert.ToDouble(liste[i]["u"], CultureInfo.InvariantCulture);
                var alt = Convert.ToSingle(Hole(bau, "fU"));
                if (!nurPruefen) Setze(bau, "fU", neu);
                if (Math.Abs(alt - neu) > 0.0005f)
                {
                    Console.WriteLine("  " + ist.PadRight(44)
                        + (nurPruefen ? " Liste sagt U " + Z(neu) + ", Modell rechnet mit " + Z(alt)
                                      : " U " + Z(alt) + " -> " + Z(neu)));
                    opak++; abweichung++;
                }
            }

            if (liste[i].ContainsKey("fenster"))
            {
                var fs = Hole(t, "FenestrationSystems");
                if (Zahl(fs) == 0)
                {
                    Console.Error.WriteLine("Bauteil " + (i + 1) + " '" + ist
                        + "' fuehrt kein Fenster, es soll aber eines gesetzt werden");
                    return 1;
                }
                var neu = (float) Convert.ToDouble(liste[i]["fenster"], CultureInfo.InvariantCulture);
                for (var q = 0; q < Zahl(fs); q++)
                {
                    var w = Hole(Element(fs, q), "Window");
                    if (w == null) continue;
                    var alt = Convert.ToSingle(Hole(w, "fU"));
                    if (!nurPruefen) Setze(w, "fU", neu);
                    if (Math.Abs(alt - neu) > 0.0005f)
                    {
                        Console.WriteLine("  " + ist.PadRight(44)
                            + (nurPruefen ? " Liste sagt Uw " + Z(neu) + ", Modell rechnet mit " + Z(alt)
                                          : " Uw " + Z(alt) + " -> " + Z(neu)));
                        fenster++; abweichung++;
                    }
                }
                if (nurPruefen) continue;
                // Der Aufbau eines Fensterbauteils traegt denselben Wert und
                // eine Flaeche von 0. Rechnerisch aendert er nichts, aber ein
                // Modell, in dem Aufbau und Verglasung auseinanderlaufen, waere
                // beim naechsten Auslesen irrefuehrend.
                var fbau = Hole(t, "Construction");
                if (fbau != null && Convert.ToSingle(Hole(t, "fA")) == 0f) Setze(fbau, "fU", neu);
            }
        }

        if (nurPruefen)
        {
            if (abweichung > 0)
            {
                Console.Error.WriteLine(abweichung + " Bauteile: Bauteilliste und Rechenmodell "
                    + "sind sich nicht einig. Die Variante ZEIGT andere U-Werte als sie RECHNET.");
                return 1;
            }
            Console.WriteLine("Bauteilliste und Rechenmodell stimmen ueberein ("
                + liste.Count + " Bauteile geprueft)");
            return 0;
        }

        using (var s = File.Create(args[1])) new BinaryFormatter().Serialize(s, g);

        // Gegenprobe am geschriebenen Stand, nicht am Objekt im Speicher.
        object erneut;
        using (var s = File.OpenRead(args[1])) erneut = new BinaryFormatter().Deserialize(s);
        var t2 = Hole(Element(Hole(erneut, "Zones"), zoneNr), "ConstructionElements");
        for (var i = 0; i < liste.Count; i++)
        {
            var e = Element(t2, i);
            if (liste[i].ContainsKey("u"))
            {
                var soll = (float) Convert.ToDouble(liste[i]["u"], CultureInfo.InvariantCulture);
                var ist = Convert.ToSingle(Hole(Hole(e, "Construction"), "fU"));
                if (Math.Abs(soll - ist) > 0.0005f)
                {
                    Console.Error.WriteLine("Gegenprobe Bauteil " + (i + 1) + ": " + Z(ist) + " statt " + Z(soll));
                    return 1;
                }
            }
            if (liste[i].ContainsKey("fenster"))
            {
                var soll = (float) Convert.ToDouble(liste[i]["fenster"], CultureInfo.InvariantCulture);
                var fs = Hole(e, "FenestrationSystems");
                for (var q = 0; q < Zahl(fs); q++)
                {
                    var w = Hole(Element(fs, q), "Window");
                    if (w == null) continue;
                    var ist = Convert.ToSingle(Hole(w, "fU"));
                    if (Math.Abs(soll - ist) > 0.0005f)
                    {
                        Console.Error.WriteLine("Gegenprobe Fenster " + (i + 1) + ": " + Z(ist) + " statt " + Z(soll));
                        return 1;
                    }
                }
            }
        }

        Console.WriteLine(opak + " Aufbauten und " + fenster + " Fenster geaendert, "
            + new FileInfo(args[1]).Length + " B, Gegenprobe bestanden");
        return 0;
    }

    private static string Z(float f) { return f.ToString("0.000", CultureInfo.InvariantCulture); }

    private static object Wert(Dictionary<string, object> d, string n)
    {
        object w;
        return d.TryGetValue(n, out w) ? w : null;
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
        throw new InvalidOperationException("'" + name + "' nicht schreibbar an " + o.GetType().Name);
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
