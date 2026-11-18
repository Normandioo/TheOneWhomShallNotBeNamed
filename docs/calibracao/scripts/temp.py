import sys, numpy as np, common as C
C.D = sys.argv[1]; S = sys.argv[2]
land = C.load("Landmask.png")[..., 0] == 80
k = np.load(f"{S}/koppen_cls.npy")
tj, dj = C.invert(C.load("Temperatura Janeiro.png"), "magma")
tl, dl = C.invert(C.load("Temperatura Julho.png"), "magma")
ok = land & (dj < 10) & (dl < 10)
print("land px usable", ok.mean() / land.mean(), " t=0 share on land jan/jul", (tj[land] == 0).mean(), (tl[land] == 0).mean())
cold, hot = np.minimum(tj, tl), np.maximum(tj, tl)
g = lambda pred: ok & pred
first = np.vectorize(lambda s: s[0])(k); B = first == "B"
def split(var, pos, neg, label, T):
    """threshold on var best separating pos (>=) from neg; returns (t*, T, accuracy)"""
    x = np.concatenate([var[pos], var[neg]]); y = np.concatenate([np.ones(pos.sum()), np.zeros(neg.sum())])
    o = np.argsort(x); xs, ys = x[o], y[o]
    # acc(threshold between i-1,i): negatives below + positives above
    neg_below = np.cumsum(1 - ys); pos_above = ys.sum() - np.cumsum(ys)
    acc = (neg_below + pos_above) / len(ys); i = acc.argmax()
    t = (xs[i] + xs[min(i + 1, len(xs) - 1)]) / 2
    print(f"{label:28s} T={T:6.1f}°C  t*={t:.4f}  acc={acc[i]:.3f}  n+={pos.sum()} n-={neg.sum()}")
    return t, T
pts = []
A = first == "A"; Cc = first == "C"; Dd = first == "D"; E = first == "E"
pts.append(split(cold, g(A), g((Cc | Dd) & ~B), "A vs C/D (Tfrio>=18)", 18))
pts.append(split(cold, g(Cc), g(Dd), "C vs D (Tfrio>0)", 0))
pts.append(split(hot, g(~E & ~B), g(E), "nao-E vs E (Tquente>=10)", 10))
pts.append(split(hot, g(k == "ET"), g(k == "EF"), "ET vs EF (Tquente>=0)", 0))
third = np.vectorize(lambda s: s[2] if len(s) == 3 else "")(k)
pts.append(split(hot, g((Cc | Dd) & (third == "a")), g((Cc | Dd) & (third == "b")), "a vs b (Tquente>=22)", 22))
pts.append(split(cold, g(Dd & (third == "c")), g(Dd & (third == "d")), "c vs d (Tfrio>=-38)", -38))
pts = np.array(pts); A_, b_ = np.polyfit(pts[:, 0], pts[:, 1], 1)
res = pts[:, 1] - (A_ * pts[:, 0] + b_)
print(f"fit linear: T = {b_:.2f} + {A_:.2f}*t   residuals={np.round(res,1)}  -> t=0:{b_:.1f}°C t=1:{A_+b_:.1f}°C")
q = np.polyfit(pts[:, 0], pts[:, 1], 2); print("quad fit coefs", np.round(q, 2), "resid", np.round(pts[:, 1] - np.polyval(q, pts[:, 0]), 1))
Tj, Tl = b_ + A_ * tj, b_ + A_ * tl
print("land Tjan p1/p50/p99:", np.round(np.percentile(Tj[ok], [1, 50, 99]), 1), " Tjul:", np.round(np.percentile(Tl[ok], [1, 50, 99]), 1))
print("t max seen jan/jul", tj[ok].max(), tl[ok].max())
np.save(f"{S}/temp_fit.npy", np.array([b_, A_]))
