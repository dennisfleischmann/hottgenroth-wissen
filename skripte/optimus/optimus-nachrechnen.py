"""Optimus-Abgleich einer Fussbodenheizung von aussen nachrechnen.

Liest ein Hottgenroth-Projekt aus `(localdb)\\HSETU` (HsetuPrjData) und rechnet je
Heizkreis das nach, was der Optimus-Kern in `TCalcOptimusSingleCircuitCalcObject`
und `TCalcOptimusCircuitDistributionDpPumpCalcObject` tut (Hsetu.FW.Calculations
6.7.8.301, Optimus 2026 Planer). Formeln und Fundstellen stehen in
`doku/hsetu/OPTIMUS-HYDRAULISCHER-ABGLEICH.md`.

Aufruf:
    python optimus-nachrechnen.py "<Projektname-Teil oder UUID>" [--tv 35] [--kvs 2.4]

`--tv` ueberschreibt die Vorlauftemperatur aller Verteilungen (Was-waere-wenn).
Die Voreinstellungsleiter des "Neutralen Herstellers / Abgang Verteiler" ist aus
dem Bericht abgelesen (der Ventilkatalog liegt in HsetuAppTimData, die der
Windows-Login nicht oeffnen darf) und deshalb nur eine Naeherung.

Erprobt am 04.11.2026 an "Jonathan Hilgert_Heizlastberechnung (1)": kv und
Voreinstellung bei 15 von 19 Kreisen exakt wie im Bericht, Durchfluesse 3-5 % hoeher
(der Kern verteilt die Raumlast ueber PlantSpace.RatedHeatingLoad, hier BmRoom).
Foerderhoehe: 35 °C EG 1818/OG 611 mbar gegen Bericht 1730/571; 45 °C EG 1202/OG 149
gegen 1070/152 - die Abweichung ist der quadrierte Durchfluss-Ueberhang. Treiber ist die
Verteilerzuleitung als Rohr (PmConnection.InnerDiameter des Vorlaufanschlusses, hier
15 mm, Standard 20 mm) ueber PmDevice.DistanceToPump.
"""
import argparse, math, sys
import pyodbc

SENT = -987654321.99
RHO, NU, K_ROHR_MM = 993.0, 4.8e-7, 0.0015          # wie im Kern: Dichte, Viskositaet, Rauheit [mm]
VORLAUF_MIN, VORLAUF_MAX = 26.0, 52.0
PRESET = [(0.25, '1'), (0.40, '2'), (0.70, '3'), (1.15, '4')]   # kv-Obergrenze -> Voreinstellung (empirisch)


def val(v):
    return None if v is None or (isinstance(v, float) and abs(v - SENT) < 0.01) else v


def connect():
    return pyodbc.connect(r'DRIVER={ODBC Driver 17 for SQL Server};SERVER=(localdb)\HSETU;'
                          r'DATABASE=HsetuPrjData;Trusted_Connection=yes;')


def lade(cur, projekt):
    cur.execute("SELECT UUID, LongDesc FROM PrProject WHERE CONVERT(varchar(36),UUID)=? OR LongDesc LIKE ?",
                projekt, f'%{projekt}%')
    rows = cur.fetchall()
    if len(rows) != 1:
        sys.exit(f"{len(rows)} Projekte passen auf '{projekt}': " + '; '.join(r.LongDesc for r in rows))
    puuid, pname = str(rows[0].UUID), rows[0].LongDesc

    cur.execute("""
        SELECT c.UUID, c.LongDesc, c.HeatingArea, c.ResidentialZoneDistance, c.InnerDiameter, c.HeatOutput,
               c.RatedAmbientTemperature, c.DistributorUUID,
               r.ShortDesc AS raum_nr, r.LongDesc AS raum, r.HeatingLoad, r.HeatingRatedHeatingLoad, r.InsideTemperature, r.Area,
               dr.UUID AS dist_uuid, d.LongDesc AS verteilung, d.FlowTemperature, d.ReturnTemperature, d.RatedFlowTemperature,
               d.VolumetricFlow AS dist_v, d.DeltaP AS dist_dp,
               dev.DistanceToPump, vl.InnerDiameter AS di_zuleitung
        FROM PmCircuit c
        LEFT JOIN PmBuildingReference br ON br.ReferenceFromUUID=c.UUID AND br.ObjReferenceType=13
        LEFT JOIN BmRoom r ON r.UUID=br.ReferenceToUUID
        LEFT JOIN PmDistributionReference dr ON dr.ReferenceToUUID=c.UUID
        LEFT JOIN PmDistribution d ON d.UUID=dr.UUID
        LEFT JOIN PmDevice dev ON dev.UUID=c.DistributorUUID
        LEFT JOIN PmDistributor vt ON vt.UUID=c.DistributorUUID
        LEFT JOIN PmConnection vl ON vl.UUID=vt.SupplyConnectorUUID
        WHERE c.ProjectUUID=?
        ORDER BY d.SortNum, c.SortNum""", puuid)
    kreise = [dict(zip([d[0] for d in cur.description], (val(v) for v in row))) for row in cur.fetchall()]

    cur.execute("SELECT MaximalFlowTemperature FROM PmDevice WHERE ProjectUUID=? AND GroupType=11", puuid)
    kessel = [val(r[0]) for r in cur.fetchall()]
    tv_max = min([VORLAUF_MAX] + [k for k in kessel if k and k < VORLAUF_MAX])
    return pname, kreise, tv_max


def lambda_colebrook(re, d_mm):
    """Rohrreibungszahl wie im Kern: Startwert nach Nikuradse, dann vier Colebrook-Schritte."""
    kd = K_ROHR_MM / d_mm
    lam = (1.14 - 2.0 * math.log10(kd)) ** -2
    for _ in range(4):
        lam = (-2.0 * math.log10(kd / 3.71 + 2.51 / (re * math.sqrt(lam)))) ** -2
    return lam


def rechne_kreis(k, tv, tv_max):
    q_out, t_i, a = k['HeatOutput'], k['RatedAmbientTemperature'] or 20.0, k['HeatingArea']
    q_req = k['_q_req']
    b = q_req / q_out
    dtheta_erf = b ** (1 / 1.1) * 25.0                        # erforderliche Uebertemperatur (Norm 25 K)
    tv_erf = max(VORLAUF_MIN, min(tv_max, math.trunc(dtheta_erf + t_i + 2.6)))
    # Ruecklauf: Spreizung aus Vorlauf und Uebertemperatur, geklemmt auf 5..15 K
    dt, geklemmt = 5.0, True
    if dtheta_erf > 0:
        n3 = 1.0 + 4.0 * (tv - dtheta_erf - t_i) / (3.0 * dtheta_erf)
        if n3 > 0:
            dt = 3.0 * dtheta_erf * (-1.0 + math.sqrt(n3))
        geklemmt = not (5.0 <= dt <= 15.0)
        dt = min(15.0, max(5.0, dt))
    m = q_req / (4.2 * dt) * 3.6                               # kg/h
    v = m / RHO * 1.15                                         # m3/h, mit 15 % Aufschlag
    d, va = k['InnerDiameter'], k['ResidentialZoneDistance']
    laenge = a / va
    w = v / 3600.0 / (math.pi * d * d / 4.0)
    re = w * d / NU
    lam = lambda_colebrook(re, d * 1000.0)
    dp_rohr = laenge * lam * RHO * w * w / (2.0 * d) / 100.0  # mbar
    return dict(q_req=q_req, dtheta_erf=dtheta_erf, tv_erf=tv_erf, dt=dt, geklemmt=geklemmt, m=m, v=v,
                laenge=laenge, w=w, re=re, lam=lam, dp_rohr=dp_rohr, q_flaeche=q_req / a)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('projekt')
    ap.add_argument('--tv', type=float, help='Vorlauftemperatur fuer alle Verteilungen erzwingen')
    ap.add_argument('--kvs', type=float, default=2.4, help='kvs des Verteilerabgangs (Standard 2,4)')
    ap.add_argument('--di', type=float, help='Innendurchmesser der Verteilerzuleitung in mm erzwingen (Was-waere-wenn)')
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

    cur = connect().cursor()
    pname, kreise, tv_max = lade(cur, args.projekt)
    print(f"Projekt: {pname}   Vorlauf-Obergrenze des Kerns: {tv_max:.0f} °C (52 °C oder Kessel-Maximum)\n")

    # Raumheizlast nach Normleistung 50/40 auf die Kreise des Raums verteilen (RequiredOutputCalcObject)
    for k in kreise:
        geschw = [x for x in kreise if x['raum_nr'] == k['raum_nr'] and x['dist_uuid'] == k['dist_uuid']]
        summe = sum(x['HeatOutput'] for x in geschw)
        last = k['HeatingRatedHeatingLoad'] or k['HeatingLoad'] or 0.0
        k['_q_req'] = last * k['HeatOutput'] / summe if summe else 0.0

    for dist in sorted({k['dist_uuid'] for k in kreise}, key=lambda u: next(x['verteilung'] for x in kreise if x['dist_uuid'] == u)):
        kk = [k for k in kreise if k['dist_uuid'] == dist]
        tv = args.tv or kk[0]['FlowTemperature']
        print(f"=== {kk[0]['verteilung']}   t_V = {tv:.0f} °C   (Datenbank: {kk[0]['FlowTemperature']}/{kk[0]['ReturnTemperature']} °C, "
              f"V̇ {kk[0]['dist_v'] or 0:.3f} m³/h, Δp {kk[0]['dist_dp'] or 0:.0f} mbar, Zuleitung {kk[0]['DistanceToPump']} m)")
        erg = [(k, rechne_kreis(k, tv, tv_max)) for k in kk]
        for k, e in erg:
            e['dp_offen'] = 1000.0 * (e['v'] / args.kvs) ** 2
            e['gesamt'] = e['dp_rohr'] + e['dp_offen']
        niveau = max(e['gesamt'] for _, e in erg)                 # hydraulisch unguenstigster Kreis
        v_ges = sum(e['v'] for _, e in erg)
        a_raeume = sum({k['raum_nr']: k['Area'] for k in kk}.values())
        # Verteilerzuleitung als echtes Rohr (TCalcOptimusDistributorCalcObject.CalcDpPipe):
        # Laenge = DistanceToPump (einfach), Durchmesser = Vorlaufanschluss des Verteilers, sonst 20 mm
        zuleitung = kk[0]['DistanceToPump'] or 0.0
        di_zul = (args.di / 1000.0) if args.di else (kk[0]['di_zuleitung'] or 0.020)
        w_zul = v_ges / 3600.0 / (math.pi * di_zul ** 2 / 4.0)
        re_zul = w_zul * di_zul / NU
        dp_zul = zuleitung * lambda_colebrook(re_zul, di_zul * 1000.0) * RHO * w_zul ** 2 / (2.0 * di_zul) / 100.0 if zuleitung else 0.0
        print(f"{'Kreis':28} {'Raum':13} {'A':>5} {'VA':>5} {'L':>5} {'Q50/40':>6} {'Q_req':>6} {'W/m²':>5} {'tV,erf':>6} {'ΔT':>4} "
              f"{'l/min':>5} {'w':>5} {'Δp_Rohr':>7} {'Δp_V':>5} {'kv':>6} {'Vorein':>6} Hinweis")
        for k, e in erg:
            dp_v = niveau - e['dp_rohr']                          # Zuleitungs-dp liegt vor allen Kreisen, kuerzt sich heraus
            kv = e['v'] / math.sqrt(dp_v / 1000.0) if dp_v > 0 else float('inf')
            if kv >= args.kvs * 0.999:
                vorein, hinweis = 'offen', 'voll offen, hydraulisch ungünstigster Kreis' if e['gesamt'] >= niveau * 0.999 else 'voll offen'
            else:
                vorein = next((p for grenze, p in PRESET if kv <= grenze), '–')
                hinweis = '' if vorein != '–' else 'kein passender Ventiltyp'
            if e['q_flaeche'] > 100:
                hinweis += ('; ' if hinweis else '') + f'>100 W/m² (DIN EN 1264-4)'
            if e['tv_erf'] > tv:
                hinweis += ('; ' if hinweis else '') + f'zu klein (braucht {e["tv_erf"]:.0f} °C)'
            print(f"{k['LongDesc'][:28]:28} {k['raum'][:13]:13} {k['HeatingArea']:5.1f} {k['ResidentialZoneDistance']*100:4.1f}c {e['laenge']:5.0f} "
                  f"{k['HeatOutput']:6.0f} {e['q_req']:6.0f} {e['q_flaeche']:5.0f} {e['tv_erf']:6.0f} {e['dt']:4.1f} "
                  f"{e['v']*1000/60:5.2f} {e['w']:5.2f} {e['dp_rohr']:7.0f} {dp_v:5.0f} {kv:6.3f} {vorein:>6} {hinweis}")
        n7 = 4.3 * a_raeume                                       # Referenzstrom der Netz-Heuristik [l/h]
        r_zul = max(0.2, (v_ges * 1000.0 / n7) ** 2) if n7 else 0.2
        netz = r_zul * zuleitung
        foerderhoehe = max(netz, dp_zul + niveau)                 # CalcMaxPressureLoss: max(Netz-Heuristik, Verteiler-dp + Kreis + Ventil offen)
        print(f"-> Summe V̇ = {v_ges:.3f} m³/h ({v_ges*1000:.0f} l/h); Verteilerniveau (ungünstigster Kreis) = {niveau:.0f} mbar; "
              f"Zuleitung {zuleitung:.0f} m × d_i {di_zul*1000:.0f} mm: w = {w_zul:.2f} m/s, Δp = {dp_zul:.0f} mbar; "
              f"Netz-Heuristik ({a_raeume:.0f} m²) = {netz:.0f} mbar\n"
              f"   Förderhöhe = max({netz:.0f}, {dp_zul:.0f} + {niveau:.0f}) = {foerderhoehe:.0f} mbar   (Bericht/DB: {kk[0]['dist_dp'] or 0:.0f} mbar)\n")


if __name__ == '__main__':
    main()
