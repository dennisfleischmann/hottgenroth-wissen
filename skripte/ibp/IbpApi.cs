// Erhebt die Schnittstelle des IBP-Modells: welche Fabrikmethoden es gibt und
// welche Aufzaehlungen deren Zahlen bedeuten.
//
// Hintergrund: die Anlagentechnik nach DIN 18599 liegt NICHT in den .BDExit-
// Tabellen, sondern als BinaryFormatter-Graph in PrMedia/Kernel18599V5.bin.
// Anders als beim Energieberater-Container gibt es hier aufrufbare Funktionen -
// der Kernel ist verwalteter Code (zugekauft vom Fraunhofer IBP).
//
// Warum Fabrikmethoden und nicht selbst zusammenstecken: NewGeneratorBoiler
// legt die Komponente an, haengt sie in die Einheit, traegt den Typ im Pool des
// Gebaeudes ein und vergibt strObjectID samt Hex-Kennung. Wer das von Hand
// nachbaut, muss jede dieser Verbindungen erraten.
//
//   csc /platform:x64 /out:ibp-api.exe IbpApi.cs
//   ibp-api.exe <blob.bin> [suchbegriff]

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Serialization.Formatters.Binary;

internal static class IbpApi
{
    private const string Installation = @"C:\Program Files\HSETU\Energieberater2022";

    private static int Main(string[] args)
    {
        AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
        {
            var p = Path.Combine(Installation, new AssemblyName(e.Name).Name + ".dll");
            return File.Exists(p) ? Assembly.LoadFrom(p) : null;
        };

        object wurzel;
        using (var s = File.OpenRead(args[0])) wurzel = new BinaryFormatter().Deserialize(s);

        var asm = wurzel.GetType().Assembly;
        var filter = args.Length > 1 ? args[1] : null;
        Console.WriteLine("Assembly: " + asm.GetName().Name + " " + asm.GetName().Version);
        Console.WriteLine("Typen   : " + asm.GetTypes().Length);
        Console.WriteLine();

        // ---- Fabrikmethoden
        Console.WriteLine("=== Methoden (" + (args.Length > 2 ? args[2] : "New") + "*) ===");
        foreach (var t in asm.GetTypes().OrderBy(x => x.Name))
        {
            var neu = t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic
                    | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                .Where(m => m.Name.StartsWith(args.Length > 2 ? args[2] : "New"))
                .Where(m => filter == null || (t.Name + m.Name).IndexOf(filter, StringComparison.OrdinalIgnoreCase) >= 0)
                .ToArray();

            if (neu.Length == 0) continue;
            Console.WriteLine("  " + t.Name);
            foreach (var m in neu.OrderBy(x => x.Name))
                Console.WriteLine("      " + m.Name + "(" + string.Join(", ",
                    m.GetParameters().Select(p => Kurz(p.ParameterType) + " " + p.Name).ToArray())
                    + ") -> " + Kurz(m.ReturnType));
        }

        // ---- Aufzaehlungen
        Console.WriteLine();
        Console.WriteLine("═══ Aufzaehlungen ═══");
        foreach (var t in asm.GetTypes().Where(x => x.IsEnum).OrderBy(x => x.Name))
        {
            if (filter != null && t.Name.IndexOf(filter, StringComparison.OrdinalIgnoreCase) < 0) continue;
            var werte = Enum.GetValues(t);
            Console.WriteLine("  " + t.Name + "  (" + werte.Length + ")");
            foreach (var w in werte)
                Console.WriteLine("      " + Convert.ToInt64(w).ToString().PadLeft(4) + "  " + w);
        }

        return 0;
    }

    private static string Kurz(Type t)
    {
        if (t == typeof(void)) return "void";
        if (t == typeof(string)) return "string";
        if (t == typeof(int)) return "int";
        if (t == typeof(short)) return "short";
        if (t == typeof(float)) return "float";
        if (t == typeof(double)) return "double";
        if (t == typeof(bool)) return "bool";
        return t.Name;
    }
}
