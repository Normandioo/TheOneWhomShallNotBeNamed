"""Gera as figuras do estudo (docs/pesquisa-pinceis/figuras/*.png) e a tabela de números (resultados.json).
Roda cada método sobre o MESMO terreno-base e o MESMO traço. Leva ~3 minutos (a erosão fluvial é a parte lenta).
Uso: python figuras.py <pasta_com_matplotlib_se_precisar>
"""
import json
import os
import sys

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import LightSource, LinearSegmentedColormap

import metodos as M

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "figuras")
CACHE = os.path.join(HERE, "resultados.npz")
os.makedirs(OUT, exist_ok=True)

# Relevo colorido: planície verde -> savana -> marrom -> neve (a mesma ideia da camada Altitude do jogo).
CMAP = LinearSegmentedColormap.from_list("rel", [(0.0, "#3f8f3f"), (0.18, "#9bc56a"), (0.35, "#d8cd78"), (0.55, "#a8794a"),
                                                (0.78, "#8a6a58"), (1.0, "#ffffff")])
LS = LightSource(azdeg=315, altdeg=38)
VMAX = 5500.0


def shade(h):
    return LS.shade(h, cmap=CMAP, blend_mode="soft", vert_exag=5, dx=M.CELL_M, dy=M.CELL_M, vmin=0, vmax=VMAX)


def hill(h):
    return LS.hillshade(h, vert_exag=5, dx=M.CELL_M, dy=M.CELL_M)


def exemplar():
    """Pedaço real do mapa de altitude (cordilheira), 40x40 pixels de 12,7 km, para o carimbo."""
    f = os.path.join(HERE, "..", "..", "data", "evron", "height_4096x2048.f32")
    a = np.fromfile(f, "<f4").reshape(2048, 4096)
    x, y = int((-39 / 360 + 0.5) * 4096), int((0.5 - 33 / 180) * 2048)
    return a[y - 20:y + 20, x - 20:x + 20].astype(np.float64)


def compute():
    base = M.base_terrain()
    m = M.stroke_mask()
    r = {"base": base, "mask": m}
    t = {}
    def run(key, fn):
        out, dt = M.timed(fn)
        r[key], t[key] = out, dt
        print(f"{key:10s} {dt:6.1f}s  max {out.max():6.0f} m", flush=True)
    run("cone", lambda: M.cone(base, m))
    run("fbm", lambda: M.fbm_hills(base, m))
    run("ridges", lambda: M.ridges(base, m))
    run("warped", lambda: M.ridges_warped(base, m))
    run("thermal", lambda: M.thermal(r["warped"], iters=120))
    run("droplets", lambda: M.droplets(r["warped"], m))
    sp, dt = M.timed(M.stream_power, base, 130.0 * m, 40, 0.08, 0.5, 0.05, 1.0, 2, 40.0, (10, 20, 40))
    r["stream"], snaps = sp
    t["stream"] = dt
    for k, v in snaps.items():
        r[f"stream{k}"] = v
    print(f"stream     {dt:6.1f}s  max {r['stream'].max():6.0f} m", flush=True)
    run("exemplar", lambda: M.exemplar_stamp(base, m, exemplar()))
    # Híbrido: relevo de cristas deslocadas (controle e rapidez) + poucos passos de erosão fluvial (drenagem de verdade).
    seed = base + 0.8 * (r["warped"] - base)
    run("hybrid", lambda: M.stream_power(seed, 25.0 * m, 14, 0.08, 0.5, 0.05, 1.0, 4, 0.0))
    # Estudos de parâmetro
    for p in (1.2, 2.2, 3.6):
        r[f"ridge_p{p}"] = M.ridges_warped(base, m, power=p)
    for n in (0, 30, 120):
        r[f"thermal{n}"] = M.thermal(r["warped"], iters=n) if n else r["warped"]
    for n in (20000, 90000, 300000):
        r[f"drops{n}"] = M.droplets(r["warped"], m, n_drops=n)
    np.savez_compressed(CACHE, **r)
    json.dump(t, open(os.path.join(HERE, "tempos.json"), "w"))
    return r, t


def stats(r, t):
    m = r["mask"]
    keys = ["cone", "fbm", "ridges", "warped", "thermal", "droplets", "stream", "exemplar", "hybrid"]
    rows = {}
    for k in keys:
        h = r[k]
        gy, gx = np.gradient(h, M.CELL_M)
        slope = np.degrees(np.arctan(np.hypot(gx, gy)))
        inm = m > 0.3
        lap = np.abs(np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1) - 4 * h)
        nb = np.minimum.reduce([np.roll(h, s, a) for s in (-1, 1) for a in (0, 1)])
        pits = ((h < nb - 1e-6) & inm)[2:-2, 2:-2]   # estrito: célula de altura igual não é poço
        rows[k] = {"max_m": float(h.max()), "declive_medio_graus": float(slope[inm].mean()),
                   "declive_p95_graus": float(np.percentile(slope[inm], 95)), "rugosidade_m": float(lap[inm].mean()),
                   "pocos_pct": float(100 * pits.sum() / inm.sum()), "tempo_s": float(t.get(k, 0.0))}
    json.dump(rows, open(os.path.join(HERE, "numeros.json"), "w"), indent=1)
    return rows


def transect(h):
    """Corte transversal ao traço (perpendicular no meio dele), de -150 a +150 km."""
    cx, cy = 240 / M.CELL_KM, 155 / M.CELL_KM
    tx, ty = 340.0, -526.0
    n = np.hypot(tx, ty)
    px, py = -ty / n, tx / n
    s = np.linspace(-150, 150, 220)
    xs, ys = cx + s / M.CELL_KM * px, cy + s / M.CELL_KM * py
    xs, ys = np.clip(xs, 0, M.N - 1.01), np.clip(ys, 0, M.N - 1.01)
    xi, yi = xs.astype(int), ys.astype(int)
    fx, fy = xs - xi, ys - yi
    z = (h[yi, xi] * (1 - fx) * (1 - fy) + h[yi, xi + 1] * fx * (1 - fy) + h[yi + 1, xi] * (1 - fx) * fy + h[yi + 1, xi + 1] * fx * fy)
    return s, z, (cx, cy, px, py)


NAMES = {
    "cone": "A · Cone liso", "fbm": "B · Ruído fBm", "ridges": "C · Cristas (ridged)", "warped": "D · Cristas + deslocamento",
    "thermal": "E · + Erosão térmica", "droplets": "F · + Erosão por gotas", "stream": "G · Soerguimento + erosão fluvial",
    "exemplar": "H · Carimbo de relevo real", "hybrid": "I · Híbrido (D + erosão fluvial curta)",
}


def fig_overview(r):
    keys = ["cone", "fbm", "ridges", "warped", "thermal", "droplets", "stream", "exemplar", "hybrid"]
    fig, ax = plt.subplots(3, 3, figsize=(15, 15.4))
    for a, k in zip(ax.ravel(), keys):
        a.imshow(shade(r[k]), interpolation="bilinear")
        a.set_title(NAMES[k], fontsize=14, fontweight="bold")
        a.axis("off")
    fig.suptitle("O mesmo traço, o mesmo terreno-base, nove métodos (480 km de lado)", fontsize=15, y=0.995)
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, "visao_geral.png"), dpi=85)
    plt.close(fig)


def fig_method(r, k):
    h = r[k]
    fig = plt.figure(figsize=(15, 4.7))
    gs = fig.add_gridspec(1, 3, width_ratios=[1, 1, 1.15])
    a = fig.add_subplot(gs[0]); a.imshow(hill(h), cmap="gray", interpolation="bilinear"); a.set_title("Relevo sombreado", fontsize=11); a.axis("off")
    b = fig.add_subplot(gs[1]); b.imshow(shade(h), interpolation="bilinear"); b.set_title("Relevo colorido", fontsize=11); b.axis("off")
    s, z, (cx, cy, px, py) = transect(h)
    for ax_ in (a, b):
        ax_.plot([cx - 150 / M.CELL_KM * px, cx + 150 / M.CELL_KM * px], [cy - 150 / M.CELL_KM * py, cy + 150 / M.CELL_KM * py],
                 color="#d62728", lw=1.6)
    c = fig.add_subplot(gs[2])
    c.fill_between(s, 0, z, color="#b9a27a", alpha=0.55)
    c.plot(s, z, color="#4a3a22", lw=1.4)
    c.set_ylim(0, 6000); c.set_xlim(-150, 150)
    c.set_title("Corte transversal (linha vermelha)", fontsize=11)
    c.set_xlabel("km a partir do eixo do traço"); c.set_ylabel("altitude (m)"); c.grid(alpha=0.25)
    fig.suptitle(NAMES[k], fontsize=13, fontweight="bold", x=0.02, ha="left")
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, f"metodo_{k}.png"), dpi=80)
    plt.close(fig)


def fig_base(r):
    fig, ax = plt.subplots(1, 2, figsize=(10, 5))
    ax[0].imshow(shade(r["base"]), interpolation="bilinear"); ax[0].set_title("Terreno-base (planície)", fontsize=12); ax[0].axis("off")
    ax[1].imshow(r["mask"], cmap="magma"); ax[1].set_title("Traço do pincel (peso 0 a 1)", fontsize=12); ax[1].axis("off")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "base.png"), dpi=80); plt.close(fig)


def fig_3d(r):
    keys = ["cone", "warped", "stream", "hybrid"]
    fig = plt.figure(figsize=(15, 10))
    X, Y = np.meshgrid(np.arange(M.N) * M.CELL_KM, np.arange(M.N) * M.CELL_KM)
    for i, k in enumerate(keys):
        ax = fig.add_subplot(2, 2, i + 1, projection="3d")
        h = r[k]
        rgb = LS.shade(h, cmap=CMAP, blend_mode="soft", vert_exag=3, dx=M.CELL_M, dy=M.CELL_M, vmin=0, vmax=VMAX)
        st = 2
        ax.plot_surface(X[::st, ::st], Y[::st, ::st], h[::st, ::st], facecolors=rgb[::st, ::st], rstride=1, cstride=1,
                        linewidth=0, antialiased=False, shade=False)
        ax.set_zlim(0, 9000); ax.set_box_aspect((1, 1, 0.3), zoom=1.55); ax.view_init(elev=30, azim=-62)
        ax.set_axis_off(); ax.set_title(NAMES[k], fontsize=13, fontweight="bold")
    fig.subplots_adjust(left=0, right=1, top=0.94, bottom=0, wspace=0, hspace=0.02); fig.savefig(os.path.join(OUT, "vista_3d.png"), dpi=80, bbox_inches="tight"); plt.close(fig)


def fig_params(r):
    def strip(keys, titles, name, suptitle):
        fig, ax = plt.subplots(1, len(keys), figsize=(5 * len(keys), 5.3))
        for a, k, t in zip(ax, keys, titles):
            a.imshow(shade(r[k]), interpolation="bilinear"); a.set_title(t, fontsize=12); a.axis("off")
        fig.suptitle(suptitle, fontsize=13, fontweight="bold"); fig.tight_layout()
        fig.savefig(os.path.join(OUT, name), dpi=75); plt.close(fig)
    strip(["ridge_p1.2", "ridge_p2.2", "ridge_p3.6"], ["expoente 1,2 (maciço largo)", "expoente 2,2 (padrão do jogo)", "expoente 3,6 (cristas finas)"],
          "param_cristas.png", "Cristas: o expoente decide entre maciço arredondado e cristas finas")
    strip(["stream10", "stream20", "stream40"], ["10 passos", "20 passos", "40 passos"], "param_fluvial.png",
          "Soerguimento + erosão fluvial: a rede de drenagem amadurece com o tempo")
    strip(["thermal0", "thermal30", "thermal120"], ["0 passadas", "30 passadas", "120 passadas"], "param_termica.png",
          "Erosão térmica: arredonda as cristas e entulha a base")
    strip(["drops20000", "drops90000", "drops300000"], ["20 mil gotas", "90 mil gotas", "300 mil gotas"], "param_gotas.png",
          "Erosão por gotas: mais gotas, mais entalhe")


GAME_KM = 2 * np.pi * 6371.0 / 4096   # 9,77 km por pixel no equador (raio da Terra, mapa de 4096 px)


def fig_project_scale(r):
    """O que sobra quando o terreno é amostrado como no jogo: pixels de 9,8 km no equador (grade de 4096 px)."""
    from PIL import Image as PI
    keys = ["cone", "ridges", "stream", "hybrid"]
    n = int(round(M.N * M.CELL_KM / GAME_KM))       # 49 células de 9,8 km em 480 km
    fig, ax = plt.subplots(2, 4, figsize=(16, 8.4), gridspec_kw={"height_ratios": [1, 1]})
    for i, k in enumerate(keys):
        h = r[k]
        coarse = np.array(PI.fromarray(h.astype(np.float32)).resize((n, n), PI.BOX))
        ax[0, i].imshow(shade(h), interpolation="bilinear"); ax[0, i].set_title(NAMES[k], fontsize=11, fontweight="bold"); ax[0, i].axis("off")
        ax[1, i].imshow(LS.shade(coarse, cmap=CMAP, blend_mode="soft", vert_exag=5, dx=GAME_KM * 1000, dy=GAME_KM * 1000, vmin=0, vmax=VMAX),
                        interpolation="nearest")
        ax[1, i].set_title(f"na grade do jogo ({GAME_KM:.1f} km por pixel no equador)", fontsize=10); ax[1, i].axis("off")
    fig.suptitle("Na grade do jogo, as diferenças entre os métodos quase desaparecem", fontsize=14, fontweight="bold")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "escala_do_jogo.png"), dpi=75); plt.close(fig)


def fig_profiles(r):
    keys = ["cone", "ridges", "warped", "stream", "hybrid"]
    fig, ax = plt.subplots(1, 1, figsize=(11, 4.6))
    cols = ["#7f7f7f", "#1f77b4", "#2ca02c", "#d62728", "#9467bd"]
    for k, c in zip(keys, cols):
        s, z, _ = transect(r[k])
        ax.plot(s, z, color=c, lw=1.5, label=NAMES[k])
    ax.set_xlabel("km a partir do eixo do traço"); ax.set_ylabel("altitude (m)"); ax.grid(alpha=0.25); ax.legend(fontsize=9, ncol=2)
    ax.set_title("Cortes transversais sobrepostos: o cone é uma colina; os outros têm picos e vales", fontsize=12, fontweight="bold")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "perfis.png"), dpi=80); plt.close(fig)


def fig_variedade():
    f = os.path.join(HERE, "variedade.npz")
    if not os.path.exists(f):
        return
    import variedade as V
    v = dict(np.load(f))
    labels = {"D": "D · Cristas deslocadas", "G": "G · Soerguimento + fluvial", "I": "I · Híbrido"}
    # (a) cinco terrenos
    fig, ax = plt.subplots(5, 3, figsize=(13.5, 22))
    for row, (nome, (rot, _)) in enumerate(V.CENARIOS.items()):
        vmax = max(v[f"{nome}|{k}|3"].max() for k in "DGI") * 1.02
        for col, k in enumerate("DGI"):
            h = v[f"{nome}|{k}|3"]
            ax[row, col].imshow(LS.shade(h, cmap=CMAP, blend_mode="soft", vert_exag=5, dx=M.CELL_M, dy=M.CELL_M, vmin=min(0, h.min()), vmax=vmax),
                                interpolation="bilinear")
            ax[row, col].axis("off")
            if row == 0:
                ax[row, col].set_title(labels[k], fontsize=13, fontweight="bold")
        ax[row, 0].text(-0.02, 0.5, rot, transform=ax[row, 0].transAxes, rotation=90, va="center", ha="right", fontsize=12, fontweight="bold")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "variedade_cenarios.png"), dpi=62); plt.close(fig)
    # (b) três sementes
    fig, ax = plt.subplots(3, 3, figsize=(13.5, 13.5))
    for row, seed in enumerate((3, 7, 11)):
        for col, k in enumerate("DGI"):
            ax[row, col].imshow(shade(v[f"planicie|{k}|{seed}"]), interpolation="bilinear"); ax[row, col].axis("off")
            if row == 0:
                ax[row, col].set_title(labels[k], fontsize=13, fontweight="bold")
        ax[row, 0].text(-0.02, 0.5, f"semente {seed}", transform=ax[row, 0].transAxes, rotation=90, va="center", ha="right", fontsize=12, fontweight="bold")
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "variedade_sementes.png"), dpi=62); plt.close(fig)
    # (c) altura equivalente: o relevo acima da base é reescalado para o mesmo pico, em cada método
    base = v["planicie|base|3"]
    fig, ax = plt.subplots(1, 3, figsize=(15, 5.4))
    rows = {}
    for a_, k in zip(ax, "DGI"):
        rel = v[f"planicie|{k}|3"] - base
        kscale = 3500.0 / rel.max()
        h = base + rel * kscale
        a_.imshow(shade(h), interpolation="bilinear"); a_.axis("off"); a_.set_title(f"{labels[k]} (pico de 3.500 m acima da base)", fontsize=11, fontweight="bold")
        gy, gx = np.gradient(h, M.CELL_M)
        sl = np.degrees(np.arctan(np.hypot(gx, gy)))
        inm = v["mask"] > 0.3
        lap = np.abs(np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1) - 4 * h)
        rows[k] = {"fator_de_escala": float(kscale), "declive_medio_graus": float(sl[inm].mean()), "declive_p95_graus": float(np.percentile(sl[inm], 95)),
                   "rugosidade_m": float(lap[inm].mean())}
    fig.tight_layout(); fig.savefig(os.path.join(OUT, "altura_equivalente.png"), dpi=75); plt.close(fig)
    out = {"altura_equivalente": rows}
    cen = {}
    for nome in V.CENARIOS:
        cen[nome] = {k: {"max_m": float(v[f"{nome}|{k}|3"].max())} for k in "DGI"}
    out["cenarios"] = cen
    json.dump(out, open(os.path.join(HERE, "variedade.json"), "w"), indent=1)



if __name__ == "__main__":
    if os.path.exists(CACHE) and "--recalcular" not in sys.argv:
        r = dict(np.load(CACHE)); t = json.load(open(os.path.join(HERE, "tempos.json")))
    else:
        r, t = compute()
    rows = stats(r, t)
    fig_base(r)
    fig_overview(r)
    for k in NAMES:
        fig_method(r, k)
    fig_3d(r)
    fig_params(r)
    fig_project_scale(r)
    fig_profiles(r)
    fig_variedade()
    for k, v in rows.items():
        print(k, {a: round(b, 2) for a, b in v.items()})
