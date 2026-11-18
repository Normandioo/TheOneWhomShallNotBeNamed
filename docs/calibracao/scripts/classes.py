import sys, json, numpy as np, common as C
C.D = sys.argv[1]; S = sys.argv[2]
land = C.load("Landmask.png")[..., 0] == 80
g = np.array(__import__("PIL.Image").Image.open(f"{C.D}/Elevation GrayScale.png")).astype(np.float64)
h = np.where(g >= 32767, (g - 32767) * 9103.40 / 17336, (g - 32767) * 13500 / 32767)
oro = C.invert(C.load("Orogeny Strenght.png"), "viridis")[0]
cat = json.loads(open(f"{S}/guia_scripts.js", encoding="utf-8").read().split("\n\n/*----*/\n\n")[0])
rk = C.load("Bedrock.png"); code = lambda x: (x[..., 0] << 16) | (x[..., 1] << 8) | x[..., 2]
rc = code(rk); rclass = np.full(rc.shape, "", object)
for p in cat["palettes"]["rocks"]:
    r, gg, b = p["map_rgb"]; cl = p["properties"].get("class", "?").strip('"')
    rclass[rc == code(np.array([r, gg, b]))] = cl
    rclass[rc == code(np.array([int(r * .2), int(gg * .2), int(b * .2)]))] = cl
lat = np.repeat(90 - (np.arange(2048) + .5) * 180 / 2048, 4096).reshape(2048, 4096)
pb = C.load("Plate Boundaries.png"); near_b = ~((pb == 80).all(-1) | (pb == 30).all(-1))
def dilate(m, r=6):
    o = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            o |= np.roll(np.roll(m, dy, 0), dx, 1)
    return o
near_b = dilate(near_b & ~(pb == (0, 0, 150)).all(-1), 4)  # boundary pixels excluding the plain blue (likely ocean background?)
for name in ["Provincias geologicas.png", "Vulcanismo.png"]:
    a = C.load(name); u, inv, cnt = np.unique(a.reshape(-1, 3), axis=0, return_inverse=True, return_counts=True); inv = inv.reshape(a.shape[:2])
    print("\n" + name)
    for i in np.argsort(-cnt):
        m = inv == i
        cls, cc = np.unique(rclass[m], return_counts=True); top = ", ".join(f"{c}:{n/cc.sum():.0%}" for c, n in sorted(zip(cls, cc), key=lambda x: -x[1])[:3])
        print(f"{str(tuple(int(x) for x in u[i])):16s} px={cnt[i]:8d} land={land[m].mean():4.0%} elev_med={np.median(h[m]):7.0f} oro_med={np.median(oro[m]):.2f} near_boundary={near_b[m].mean():4.0%} |lat|med={np.median(abs(lat[m])):4.0f} rocks: {top}")
u, c = np.unique(pb.reshape(-1, 3), axis=0, return_counts=True)
print("\nplate boundary top colors:", [(tuple(int(x) for x in u[i]), int(c[i])) for i in np.argsort(-c)[:8]])
