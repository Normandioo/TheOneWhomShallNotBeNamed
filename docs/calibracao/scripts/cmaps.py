import sys, numpy as np, common as C
C.D = sys.argv[1]
land = C.load("Landmask.png")[..., 0] == 80
maps = ["Average Rainfall.png","January Rainfall.png","July Rainfall.png","Temperatura Janeiro.png","Temperatura Julho.png",
        "Umidade Média.png","Umidade Janeiro.png","Umidade Julho.png","Slope.png","Soil Depth.png","Soil Permeability.png",
        "Soil Richness.png","Waterflow.png","Aquifer Thickness.png","Profundidade de Aquíferos.png","Inacessibilidade.png",
        "Rain shadows.png","Orogeny Strenght.png","Continentalism.png","Downflow.png"]
cands = ["viridis","magma","inferno","plasma","cividis","turbo"]
for m in maps:
    a = C.load(m); px = a[land]
    px = px[~((px == 30).all(-1) | (px == 80).all(-1))]
    if len(px) == 0: print(m, "no colored land px"); continue
    res = []
    for c in cands:
        t, d = C.invert(px, c)
        res.append((np.median(d), np.percentile(d, 95), c, t.min(), t.max()))
    res.sort()
    b = res[0]
    print(f"{m:32s} best={b[2]:8s} med={b[0]:5.1f} p95={b[1]:5.1f} t=[{b[3]:.3f},{b[4]:.3f}] | 2nd={res[1][2]} med={res[1][0]:.1f}  colored={len(px)/land.sum():.0%}")
