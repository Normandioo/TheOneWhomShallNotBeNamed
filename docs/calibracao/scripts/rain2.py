import sys, numpy as np, common as C, common2 as C2
C.D = sys.argv[1]; S = sys.argv[2]
land = C.load("Landmask.png")[..., 0] == 80
k = np.load(f"{S}/koppen_cls.npy")
T = lambda n: -20 + 60 * C.invert(C.load(n), "magma")[0]
Tj, Tl = T("Temperatura Janeiro.png"), T("Temperatura Julho.png")
(ra, oa), (rj, oj), (rl, ol) = [C2.ramp_ext(C.load(n)) for n in ("Average Rainfall.png", "January Rainfall.png", "July Rainfall.png")]
ok = land & oa & oj & ol; print("usable land:", ok.sum() / land.sum(), " dark share avg/jan:", (ra[land] < 0).mean(), (rj[land] < 0).mean())
rng = np.random.default_rng(0); idx = rng.choice(np.flatnonzero(ok.ravel()), 300000, replace=False)
k, Tj, Tl, ra, rj, rl = [x.ravel()[idx] for x in (k, Tj, Tl, ra, rj, rl)]
first = np.array([s[0] for s in k]); sec = np.array([s[1] if len(s) > 1 else "" for s in k])
MAT = (Tj + Tl) / 2; wj = Tj < Tl
def score(P):
    Pa, Pj, Pl = P(ra), P(rj), P(rl); MAP = 12 * Pa
    Pw, Ps = np.where(wj, Pj, Pl), np.where(wj, Pl, Pj); wf = Pw / np.maximum(Pw + Ps, 1e-9)
    Pth = 2 * MAT + np.where(wf >= .7, 0, np.where(wf <= .3, 28, 14))
    A = first == "A"; Pdry = np.minimum(Pj, Pl); cd = (first == "C") | (first == "D")
    acc = {"B": ((MAP < 10 * Pth) == (first == "B")).mean(),
           "BW/BS": ((MAP < 5 * Pth) == (sec == "W"))[first == "B"].mean(),
           "Af": ((Pdry >= 60) == (k == "Af"))[A].mean(),
           "Am/Aw": ((Pdry >= 100 - MAP / 25) == (k == "Am"))[A & (k != "Af")].mean(),
           "s/w/f": (np.where((Ps < 40) & (Ps < Pw / 3), "s", np.where(Pw < Ps / 10, "w", "f")) == sec)[cd].mean()}
    return np.mean(list(acc.values())), acc
res = []
for a in [0, 2, 5, 10, 15, 20, 30, 40, 60]:
    for b in np.geomspace(50, 3000, 40):
        P = lambda t, a=a, b=b: np.where(t >= 0, a + b * np.maximum(t, 0), a * (1 + t))
        sc, acc = score(P); res.append((sc, "lin", a, b, acc))
for p0 in [1, 2, 5, 10, 20, 30, 50]:
    for p1 in np.geomspace(100, 5000, 40):
        P = lambda t, p0=p0, p1=p1: np.where(t >= 0, p0 * (p1 / p0) ** np.maximum(t, 0), p0 * (1 + t))
        sc, acc = score(P); res.append((sc, "log", p0, p1, acc))
res.sort(key=lambda x: -x[0])
for sc, m, a, b, acc in res[:8]:
    print(f"{sc:.3f} {m} min={a:g} max={b:7.1f} mm/mes ", {x: round(float(v), 3) for x, v in acc.items()})
for m in ("lin", "log"):
    r = next(x for x in res if x[1] == m); print("best", m, round(r[0], 3), r[2], round(r[3], 1))
