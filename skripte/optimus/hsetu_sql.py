"""Lesender Zugriff auf die Hottgenroth-LocalDB mit sauberer Ausgabe.

Aufruf:  python hsetu_sql.py "<SQL>" [--rows]     (--rows: eine Zeile je Datensatz, Spalten untereinander)
Der Wert -987654321.99 ist der HSETU-Sentinel fuer "nicht gesetzt" und wird wie NULL behandelt.
Spalten, die in allen Zeilen leer sind, werden weggelassen.
"""
import sys, pyodbc, datetime

SENTINEL = -987654321.99
NOISE = {'GeoDesc','EditModeType','StateType','VariantType','GeneratorType','StampCreate','StampEdit','SyncType',
         'SyncCreate','SyncEdit','SyncVersion','SyncMeta','StampSync','GeoType','GId','MId','SyncStamp','SyncRowVersion',
         'VariantRoot','RenovationStateType','Id','SeqNum','InfoDesc'}

def clean(v):
    if v is None: return None
    if isinstance(v, float):
        if abs(v - SENTINEL) < 0.01: return None
        if v == int(v) and abs(v) < 1e12: return int(v)
        return round(v, 4)
    if isinstance(v, datetime.datetime):
        return None if v.year < 1900 else v.strftime('%Y-%m-%d %H:%M')
    if isinstance(v, str):
        v = v.strip()
        return v or None
    return v

def main():
    sql = sys.argv[1]
    rows_mode = '--rows' in sys.argv
    keep_noise = '--all' in sys.argv
    cn = pyodbc.connect(r'DRIVER={ODBC Driver 17 for SQL Server};SERVER=(localdb)\HSETU;DATABASE=HsetuPrjData;Trusted_Connection=yes;')
    cur = cn.cursor()
    cur.execute(sql)
    cols = [d[0] for d in cur.description]
    data = [[clean(v) for v in r] for r in cur.fetchall()]
    keep = [i for i, c in enumerate(cols) if (keep_noise or c not in NOISE) and any(r[i] is not None for r in data)]
    cols = [cols[i] for i in keep]; data = [[r[i] for i in keep] for r in data]
    print(f"{len(data)} Zeilen")
    if rows_mode:
        for n, r in enumerate(data, 1):
            print(f"--- #{n}")
            for c, v in zip(cols, r):
                if v is not None: print(f"  {c} = {v}")
    else:
        w = [max(len(str(c)), *(len(str(v)) for v in col)) for c, col in zip(cols, zip(*data))] if data else [len(c) for c in cols]
        print(' | '.join(str(c).ljust(x) for c, x in zip(cols, w)))
        for r in data:
            print(' | '.join(('' if v is None else str(v)).ljust(x) for v, x in zip(r, w)))

if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    main()
