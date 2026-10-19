# Dynamo Python Script: Tür-Diagnose
# 1. Revit → Verwalten → Dynamo
# 2. Neues Script → Python Script Node einfügen
# 3. Diesen Code einfügen → Run

import clr
clr.AddReference('RevitAPI')
clr.AddReference('RevitServices')

from Autodesk.Revit.DB import *
from Autodesk.Revit.DB.Architecture import Room
from RevitServices.Persistence import DocumentManager
import System

doc = DocumentManager.Instance.CurrentDBDocument

# Active Phase
active_phase = None
try:
    view = doc.ActiveView
    phase_param = view.get_Parameter(BuiltInParameter.VIEW_PHASE)
    if phase_param:
        phase_id = phase_param.AsElementId()
        active_phase = doc.GetElement(phase_id)
except:
    pass

if not active_phase:
    phases = FilteredElementCollector(doc).OfClass(Phase).ToElements()
    if phases:
        active_phase = phases[len(phases) - 1]

# Collect all doors
collector = FilteredElementCollector(doc).OfCategory(BuiltInCategory.OST_Doors).WhereElementIsNotElementType()
doors = [d for d in collector if isinstance(d, FamilyInstance)]

total = len(doors)
has_from = 0
has_to = 0
both_rooms = 0
no_rooms = 0
one_room = 0
wall_func_ext = 0
has_insulation = 0
thick_24 = 0

wall_type_data = {}
family_data = {}

for fi in doors:
    host = fi.Host
    is_wall = isinstance(host, Wall)
    wt_name = host.WallType.Name if is_wall else "(no wall)"
    wt_func = str(host.WallType.Function) if is_wall else "?"
    wt_thick_cm = round(host.WallType.Width * 30.48, 1) if is_wall else 0

    # Family
    fam = fi.Symbol.Family.Name if fi.Symbol and fi.Symbol.Family else "?"
    family_data[fam] = family_data.get(fam, 0) + 1

    # Room check
    fr = None
    tr = None
    try:
        if active_phase:
            fr = fi.get_FromRoom(active_phase)
            tr = fi.get_ToRoom(active_phase)
    except:
        pass

    if fr: has_from += 1
    if tr: has_to += 1
    if fr and tr: both_rooms += 1
    elif not fr and not tr: no_rooms += 1
    else: one_room += 1

    # Wall function
    func_ext = is_wall and host.WallType.Function == WallFunction.Exterior
    if func_ext: wall_func_ext += 1

    # Insulation
    wall_insul = False
    try:
        if is_wall:
            cs = host.WallType.GetCompoundStructure()
            if cs:
                for i in range(cs.LayerCount):
                    if cs.GetLayerFunction(i) == MaterialFunctionAssignment.Insulation:
                        wall_insul = True
                        break
    except:
        pass
    if wall_insul: has_insulation += 1

    # Thickness
    is_thick = wt_thick_cm >= 24
    if is_thick: thick_24 += 1

    # Wall type stats
    if wt_name not in wall_type_data:
        wall_type_data[wt_name] = [0, 0, 0, 0, wt_thick_cm]
    wall_type_data[wt_name][0] += 1
    if func_ext: wall_type_data[wt_name][1] += 1
    if wall_insul: wall_type_data[wt_name][2] += 1
    if is_thick: wall_type_data[wt_name][3] += 1

# Build report
lines = []
lines.append("=== TUER-DIAGNOSE ===")
lines.append("Active Phase: {}".format(active_phase.Name if active_phase else "null"))
lines.append("Total doors: {}".format(total))
lines.append("")
lines.append("--- ROOM CONNECTIVITY ---")
lines.append("Has FromRoom: {}".format(has_from))
lines.append("Has ToRoom: {}".format(has_to))
lines.append("Both rooms (=interior): {}".format(both_rooms))
lines.append("No rooms (=fallback): {}".format(no_rooms))
lines.append("One room only (=exterior): {}".format(one_room))
lines.append("")
lines.append("--- WALL CHECKS ---")
lines.append("WallFunction=Exterior: {}".format(wall_func_ext))
lines.append("Has insulation layer: {}".format(has_insulation))
lines.append("Thickness >= 24cm: {}".format(thick_24))
lines.append("")
lines.append("--- EXPECTED EXTERIOR COUNT ---")
lines.append("Room-based: {} exterior + {} fallback".format(one_room, no_rooms))
lines.append("Insulation-based: {}".format(has_insulation))
lines.append("Thickness >= 24cm: {}".format(thick_24))
lines.append("")
lines.append("--- DOOR FAMILIES ---")
for fam, cnt in sorted(family_data.items(), key=lambda x: -x[1]):
    lines.append("  {}: {}x".format(fam, cnt))
lines.append("")
lines.append("--- WALL TYPES hosting doors (top 20) ---")
lines.append("{:<45} {:>5} {:>6} {:>6} {:>6} {:>8}".format(
    "WallType", "Doors", "Func=E", "Insul", ">=24cm", "Thick"))
sorted_wt = sorted(wall_type_data.items(), key=lambda x: -x[1][0])
for wt_name, stats in sorted_wt[:20]:
    name = wt_name[:42] + "..." if len(wt_name) > 45 else wt_name
    lines.append("  {:<43} {:>5} {:>6} {:>6} {:>6} {:>7}cm".format(
        name, stats[0], stats[1], stats[2], stats[3], stats[4]))

report = "\n".join(lines)

# Save to Desktop
desktop = System.Environment.GetFolderPath(System.Environment.SpecialFolder.Desktop)
path = System.IO.Path.Combine(desktop, "door_diagnosis.txt")
System.IO.File.WriteAllText(path, report)

# Output for Dynamo
OUT = report
