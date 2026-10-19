/*
 * Revit Macro: Tür-Diagnose
 *
 * Ausführung: Revit → Verwalten → Makro-Manager → Modul erstellen →
 *             Code einfügen → Ausführen
 *
 * Oder: Revit → Add-Ins → Macro Manager → Create → paste → Run
 */

public void DiagnoseDoors()
{
    var doc = this.ActiveUIDocument.Document;

    // Resolve active phase
    Phase activePhase = null;
    try
    {
        var phaseParam = doc.ActiveView.get_Parameter(BuiltInParameter.VIEW_PHASE);
        if (phaseParam?.AsElementId() is ElementId phaseId)
            activePhase = doc.GetElement(phaseId) as Phase;
    }
    catch { }

    if (activePhase == null)
    {
        var phases = new FilteredElementCollector(doc)
            .OfClass(typeof(Phase)).Cast<Phase>().ToList();
        activePhase = phases.LastOrDefault();
    }

    // Collect all doors
    var doors = new FilteredElementCollector(doc)
        .OfCategory(BuiltInCategory.OST_Doors)
        .WhereElementIsNotElementType()
        .OfClass(typeof(FamilyInstance))
        .Cast<FamilyInstance>()
        .ToList();

    // Analyze each door
    int totalDoors = doors.Count;
    int hasFromRoom = 0, hasToRoom = 0, hasBothRooms = 0, hasNoRooms = 0;
    int wallFuncExterior = 0;
    int hasInsulation = 0;
    int thick24plus = 0;

    var wallTypeStats = new Dictionary<string, int[]>(); // typeName → [total, funcExterior, hasInsul, thick24]
    var familyStats = new Dictionary<string, int>();
    var results = new System.Text.StringBuilder();

    foreach (var fi in doors)
    {
        var hostWall = fi.Host as Wall;
        var wallTypeName = hostWall?.WallType?.Name ?? "(no wall)";
        var wallFunc = hostWall?.WallType?.Function.ToString() ?? "?";
        var wallThicknessFt = hostWall?.WallType?.Width ?? 0;
        var wallThicknessCm = Math.Round(wallThicknessFt * 30.48, 1);

        // Family name
        var famName = fi.Symbol?.Family?.Name ?? "?";
        if (!familyStats.ContainsKey(famName)) familyStats[famName] = 0;
        familyStats[famName]++;

        // Room check
        Room fromRoom = null, toRoom = null;
        try
        {
            if (activePhase != null)
            {
                fromRoom = fi.get_FromRoom(activePhase);
                toRoom = fi.get_ToRoom(activePhase);
            }
        }
        catch { }

        if (fromRoom != null) hasFromRoom++;
        if (toRoom != null) hasToRoom++;
        if (fromRoom != null && toRoom != null) hasBothRooms++;
        if (fromRoom == null && toRoom == null) hasNoRooms++;

        // Wall function
        bool isFuncExterior = hostWall?.WallType?.Function == WallFunction.Exterior;
        if (isFuncExterior) wallFuncExterior++;

        // Compound structure - insulation check
        bool wallHasInsulation = false;
        try
        {
            var cs = hostWall?.WallType?.GetCompoundStructure();
            if (cs != null)
            {
                for (int i = 0; i < cs.LayerCount; i++)
                {
                    if (cs.GetLayerFunction(i) == MaterialFunctionAssignment.Insulation)
                    {
                        wallHasInsulation = true;
                        break;
                    }
                }
            }
        }
        catch { }
        if (wallHasInsulation) hasInsulation++;

        // Thickness
        bool isThick = wallThicknessCm >= 24;
        if (isThick) thick24plus++;

        // Wall type stats
        if (!wallTypeStats.ContainsKey(wallTypeName))
            wallTypeStats[wallTypeName] = new int[4];
        wallTypeStats[wallTypeName][0]++;
        if (isFuncExterior) wallTypeStats[wallTypeName][1]++;
        if (wallHasInsulation) wallTypeStats[wallTypeName][2]++;
        if (isThick) wallTypeStats[wallTypeName][3]++;
    }

    // Build report
    results.AppendLine($"=== TÜR-DIAGNOSE ===");
    results.AppendLine($"Active Phase: {activePhase?.Name ?? "null"}");
    results.AppendLine($"Total doors: {totalDoors}");
    results.AppendLine();
    results.AppendLine($"--- ROOM CONNECTIVITY ---");
    results.AppendLine($"Has FromRoom: {hasFromRoom}");
    results.AppendLine($"Has ToRoom: {hasToRoom}");
    results.AppendLine($"Both rooms (=interior): {hasBothRooms}");
    results.AppendLine($"No rooms (=fallback): {hasNoRooms}");
    results.AppendLine($"One room only (=exterior): {totalDoors - hasBothRooms - hasNoRooms}");
    results.AppendLine();
    results.AppendLine($"--- WALL CHECKS ---");
    results.AppendLine($"WallFunction=Exterior: {wallFuncExterior}");
    results.AppendLine($"Has insulation layer: {hasInsulation}");
    results.AppendLine($"Thickness >= 24cm: {thick24plus}");
    results.AppendLine();

    // Expected exterior count with each strategy
    int expectedRoomBased = totalDoors - hasBothRooms - hasNoRooms; // one-room = exterior
    int expectedInsulBased = hasInsulation; // only doors in insulated walls
    results.AppendLine($"--- EXPECTED EXTERIOR COUNT ---");
    results.AppendLine($"Room-based only: {expectedRoomBased} (+ {hasNoRooms} fallback)");
    results.AppendLine($"Insulation-based (Func=Ext + insul): {expectedInsulBased}");
    results.AppendLine($"Thickness-based (Func=Ext + >=24cm): {thick24plus}");
    results.AppendLine();

    // Door family names
    results.AppendLine($"--- DOOR FAMILIES ---");
    foreach (var kv in familyStats.OrderByDescending(x => x.Value))
        results.AppendLine($"  {kv.Key}: {kv.Value}x");
    results.AppendLine();

    // Wall type breakdown (top 20)
    results.AppendLine($"--- WALL TYPES hosting doors (top 20) ---");
    results.AppendLine($"{"WallType",-40} {"Doors",6} {"Func=E",6} {"Insul",6} {">=24cm",6} {"Thick",8}");
    foreach (var kv in wallTypeStats.OrderByDescending(x => x.Value[0]).Take(20))
    {
        var wt = kv.Key.Length > 40 ? kv.Key.Substring(0, 37) + "..." : kv.Key;
        var thk = "";
        // Get thickness from first door with this wall type
        var sampleDoor = doors.FirstOrDefault(d => (d.Host as Wall)?.WallType?.Name == kv.Key);
        if (sampleDoor?.Host is Wall sw)
            thk = $"{Math.Round(sw.WallType.Width * 30.48, 1)}cm";
        results.AppendLine($"  {wt,-40} {kv.Value[0],6} {kv.Value[1],6} {kv.Value[2],6} {kv.Value[3],6} {thk,8}");
    }

    // Write to file
    var path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
        "door_diagnosis.txt");
    System.IO.File.WriteAllText(path, results.ToString());

    TaskDialog.Show("Tür-Diagnose",
        $"Ergebnis auf Desktop gespeichert: door_diagnosis.txt\n\n" +
        $"Total: {totalDoors} Türen\n" +
        $"Rooms vorhanden: {(hasNoRooms < totalDoors ? "JA" : "NEIN")}\n" +
        $"WallFunc=Exterior: {wallFuncExterior}\n" +
        $"Mit Dämmschicht: {hasInsulation}\n" +
        $"Dicke >= 24cm: {thick24plus}");
}
