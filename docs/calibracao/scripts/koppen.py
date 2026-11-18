import sys, json, numpy as np, common as C
C.D = sys.argv[1]
# Beck et al. 2018 Köppen-Geiger palette (widely used standard)
K = {"Af":(0,0,255),"Am":(0,120,255),"Aw":(70,170,250),"BWh":(255,0,0),"BWk":(255,150,150),"BSh":(245,165,0),"BSk":(255,220,100),
"Csa":(255,255,0),"Csb":(200,200,0),"Csc":(150,150,0),"Cwa":(150,255,150),"Cwb":(100,200,100),"Cwc":(50,150,50),
"Cfa":(200,255,80),"Cfb":(100,255,80),"Cfc":(50,200,0),"Dsa":(255,0,255),"Dsb":(200,0,200),"Dsc":(150,50,150),"Dsd":(150,100,150),
"Dwa":(170,175,255),"Dwb":(90,120,220),"Dwc":(75,80,180),"Dwd":(50,0,135),"Dfa":(0,255,255),"Dfb":(55,200,255),"Dfc":(0,125,125),"Dfd":(0,70,95),
"ET":(178,178,178),"EF":(102,102,102)}
names = list(K); P = np.array([K[n] for n in names], np.float32)
a = C.load("Clima.png"); land = C.load("Landmask.png")[..., 0] == 80
u, inv, cnt = np.unique(a.reshape(-1, 3), axis=0, return_inverse=True, return_counts=True)
inv = inv.ravel().reshape(a.shape[:2])
mapping = {}
for i, (col, c) in enumerate(zip(u, cnt)):
    d = np.sqrt(((P - col) ** 2).sum(1)); j = d.argmin()
    onland = (land & (inv == i)).sum() / c
    mapping[tuple(int(x) for x in col)] = (names[j], float(d[j]), int(c), float(onland))
    print(f"{str(tuple(int(x) for x in col)):18s} -> {names[j]:4s} dist={d[j]:5.1f} px={c:8d} land={onland:.0%}")
# validate against biome requirements
B = C.load("BiomasGleba.png")
kcls = np.array([mapping[tuple(int(x) for x in col)][0] for col in u])[inv]
for bname, col, allowed in [("taiga",(44,160,90),{"ET","Dfc","Dwc","Dsc"}),("mediterranean",(200,113,55),{"Csa","Csb","Csc"})]:
    m = (B == col).all(-1)
    vals, cn = np.unique(kcls[m], return_counts=True)
    ok = sum(c for v, c in zip(vals, cn) if v in allowed) / cn.sum()
    print(f"biome {bname}: px={m.sum()} in allowed Köppen={ok:.1%}  dist={dict(zip(vals.tolist(), cn.tolist()))}")
json.dump({str(k): v for k, v in mapping.items()}, open(sys.argv[2], "w"))
np.save(sys.argv[3], kcls)
