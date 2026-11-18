import sys, numpy as np, common as C
from PIL import Image
C.D = sys.argv[1]
R = 8282.3e3
land = C.load("Landmask.png")[..., 0] == 80
g = np.array(Image.open(f"{C.D}/Elevation GrayScale.png")).astype(np.float64)
h = np.where(g >= 32767, (g - 32767) * 9103.40 / 17336, (g - 32767) * 13500 / 32767)
H, W = h.shape; lat = np.deg2rad(90 - (np.arange(H) + .5) * 180 / H)[:, None]
dx = R * np.cos(lat) * 2 * np.pi / W; dy = R * np.pi / H
gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) / (2 * dx)          # longitude wraps
gy = np.gradient(h, axis=0) / dy
deg = np.degrees(np.arctan(np.hypot(gx, gy)))
print("our slope on land (deg) p50/p90/p99/max:", np.round(np.percentile(deg[land], [50, 90, 99, 100]), 2))
t, d = C.invert(C.load("Slope.png"), "viridis"); m = land & (d < 10)
print("corr(Gleba t, our deg):", np.corrcoef(t[m], deg[m])[0, 1], " corr with sqrt:", np.corrcoef(t[m], np.sqrt(deg[m]))[0, 1])
for q in [10, 50, 90, 99]:
    print(f"  Gleba t p{q}={np.percentile(t[m], q):.3f}   our deg p{q}={np.percentile(deg[m], q):.3f}")
b = np.polyfit(deg[m], t[m], 1); print("t ~ %.4f*deg + %.3f  => t=1 at %.2f deg" % (b[0], b[1], (1 - b[1]) / b[0]))
ia, da = C.invert(C.load("Inacessibilidade.png"), "viridis"); lv = np.unique(np.round(ia[land & (da < 10)], 2))
print("inaccessibility distinct t levels:", len(lv), lv[:30])
