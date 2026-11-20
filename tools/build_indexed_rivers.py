"""Gera os trechos dos rios e seu índice espacial para o satélite de Evron.

O mapa de rios do Gleba delimita a rede de drenagem. O fluxo de água
orienta o sentido e a largura dos canais, com apoio da altitude.
A largura é uma estimativa pelo fluxo relativo. O shader mede a distância
ao trecho real, inclusive onde dois cursos se encontram. A célula do
índice só limita a busca e inclui uma margem além de suas bordas.

Executar com python tools/build_indexed_rivers.py após importar os mapas.
O importador também gera data/evron/rivers_indexed.rgbaf.
"""
from collections import defaultdict
from math import cos, floor, pi, tau
import struct

import numpy as np
from scipy.ndimage import maximum_filter, minimum_filter
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import connected_components, dijkstra
from scipy.spatial import cKDTree

import build_experimental as bn

D = bn.D
T0 = 0.60
SOURCE_WIDTH, LARGEST_WIDTH = 0.04, 3.6
DISPLAY_WIDTH_SCALE = 0.42
GRID_W, GRID_H = 1024, 512
# Com canais de até 4,1 km, a cobertura do shader zera a 20 km ou menos.
HALO_KM = 20.5
VERTICAL_KM = pi * bn.RADIUS_KM
ATLAS_NAME = "rivers_indexed.rgbaf"
MAGIC = b"EVR2"


def width_km(flow, openness):
    # Waterflow não registra vazão em m³/s. Calibra uma vazão relativa para a escala do mapa.
    # Relação largura–vazão em Leopold e Maddock (1953), doi:10.3133/pp252.
    discharge = 10 ** (7.4 * (flow - 1))
    return np.maximum(SOURCE_WIDTH, LARGEST_WIDTH * np.sqrt(discharge) * (0.78 + 0.22 * openness))


def _nbrs(m):
    """Os 8 vizinhos P2..P9 (N, NE, L, SE, S, SO, O, NO) de cada pixel; a longitude dá a volta, os polos não."""
    p = np.pad(m, ((1, 1), (0, 0)))
    def at(dy, dx):
        return np.roll(p, -dx, 1)[1 + dy: 1 + dy + m.shape[0]]
    return [at(-1, 0), at(-1, 1), at(0, 1), at(1, 1), at(1, 0), at(1, -1), at(0, -1), at(-1, -1)]


def thin_dilate(m):
    return sum(n.astype(np.uint8) for n in _nbrs(m))


def fill_pixel_holes(mapped, flow, river_land):
    """Funde buracos de uma célula no mesmo curso, antes que o afinamento invente ilhas."""
    minimum = minimum_filter(flow, footprint=[[0, 1, 0], [1, 0, 1], [0, 1, 0]], mode="wrap")
    maximum = maximum_filter(flow, footprint=[[0, 1, 0], [1, 0, 1], [0, 1, 0]], mode="wrap")
    neighbors = _nbrs(mapped)
    enclosed = neighbors[0] & neighbors[2] & neighbors[4] & neighbors[6]
    return mapped | (river_land & enclosed & (minimum > 0.67) & (maximum - minimum <= 2 / 255))


def thin(m):
    """Afinamento de Zhang-Suen (1984): reduz a faixa a uma linha de 1 pixel conectada, sem encurtar as pontas."""
    m = m.astype(np.uint8)
    while True:
        changed = False
        for step in (0, 1):
            p2, p3, p4, p5, p6, p7, p8, p9 = _nbrs(m)
            b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
            seq = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
            a = sum(((seq[k] == 0) & (seq[k + 1] == 1)).astype(np.uint8) for k in range(8))
            if step == 0:
                c = (p2 * p4 * p6 == 0) & (p4 * p6 * p8 == 0)
            else:
                c = (p2 * p4 * p8 == 0) & (p2 * p6 * p8 == 0)
            rem = (m == 1) & (b >= 2) & (b <= 6) & (a == 1) & c
            if rem.any():
                m[rem] = 0
                changed = True
        if not changed:
            return m.astype(bool)


def select_outlets(neighbors, touches_water, flow):
    """Uma saída para cada grupo costeiro conectado. Um nó isolado não vira um traço na água."""
    remaining = set(np.flatnonzero(touches_water & np.any(neighbors >= 0, axis=1)).tolist())
    outlets = np.zeros(len(flow), bool)
    while remaining:
        group = [remaining.pop()]
        for node in group:
            for neighbor in neighbors[node]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    group.append(neighbor)
        outlet = max(group, key=lambda node: (flow[node], -node))
        outlets[outlet] = True
    return outlets


def downstream(neighbors, distance, elevation, flow, mouth):
    """A rota até a foz penaliza subida e perda de fluxo, com tolerância à grade do Gleba."""
    source, side = np.nonzero(neighbors >= 0)
    sink = neighbors[source, side]
    uphill = np.maximum(0, elevation[sink] - elevation[source] - 50) / 380
    flow_loss = np.maximum(0, flow[source] - flow[sink] - 1 / 255) / 0.05
    weight = distance[source, side] * (1 + 2 * uphill + 4 * flow_loss)
    # A busca parte da foz e percorre o grafo ao contrário. O predecessor é o nó a jusante.
    graph = csr_matrix((weight, (sink, source)), shape=(len(flow), len(flow)))
    group_count, group = connected_components(graph, directed=False)
    coastal = np.zeros(group_count, bool)
    coastal[group[mouth]] = True
    inland = np.flatnonzero(~coastal[group])
    if inland.size:
        order = np.lexsort((-flow[inland], elevation[inland], group[inland]))
        inland = inland[order]
        inland = inland[np.r_[True, group[inland[1:]] != group[inland[:-1]]]]
    outlets = np.r_[np.flatnonzero(mouth), inland]
    _, previous, _ = dijkstra(graph, indices=outlets, min_only=True, return_predecessors=True)
    return np.where(previous >= 0, previous, -1)


def longitude_step(a, b):
    return (b - a + 180) % 360 - 180


def steady_widths(width, source, target, edge_km, confluence):
    """Amortece quedas bruscas de largura do mapa em poucos passos após uma confluência."""
    retained = np.where(confluence[target], 1.0, np.exp(-edge_km / 45))
    for _ in range(3):
        np.maximum.at(width, target, width[source] * retained)


def reconnect_ends(nb, xs, ys, flow, elevation, mapped, land):
    """Fecha lacunas curtas entre pontas alinhadas, com fluxo e altitude compatíveis."""
    sh, sw = mapped.shape
    degree = (nb >= 0).sum(1)
    ends = np.flatnonzero((degree == 1) & (flow >= 0.67))
    xy = np.column_stack((xs, ys))
    pairs = ends[cKDTree(xy[ends], boxsize=(sw, 0)).query_pairs(5, output_type="ndarray")]
    links = np.full(len(xs), -1, dtype=np.int64)
    distance = np.zeros(len(xs))
    if not len(pairs):
        return links, distance

    a, b = pairs.T
    step = xy[b] - xy[a]
    step[:, 0] = (step[:, 0] + sw // 2) % sw - sw // 2
    along = nb.max(1)
    exit_a, exit_b = xy[a] - xy[along[a]], xy[b] - xy[along[b]]
    for direction in (exit_a, exit_b):
        direction[:, 0] = (direction[:, 0] + sw // 2) % sw - sw // 2
    length = np.linalg.norm(step, axis=1)
    align_a = np.sum(step * exit_a, axis=1) / (length * np.linalg.norm(exit_a, axis=1))
    align_b = -np.sum(step * exit_b, axis=1) / (length * np.linalg.norm(exit_b, axis=1))
    plausible = ((np.abs(flow[a] - flow[b]) <= 2 / 255) & (np.abs(elevation[a] - elevation[b]) <= 50)
                 & (align_a >= 0.30) & (align_b >= 0.30))
    start, side = np.nonzero(nb >= 0)
    graph = csr_matrix((np.ones(len(start), bool), (start, nb[start, side])), shape=(len(xs), len(xs)))
    _, group = connected_components(graph, directed=False)
    score = length + 1 - 0.5 * (align_a + align_b)
    for i in np.argsort(score):
        u, v = a[i], b[i]
        if not plausible[i] or group[u] == group[v] or links[u] >= 0 or links[v] >= 0:
            continue
        steps = np.max(np.abs(step[i]))
        path = xy[u] + np.rint(np.arange(1, steps)[:, None] * step[i] / steps).astype(int)
        rows, cols = path[:, 1], path[:, 0] % sw
        if not land[rows, cols].all() or not 1 <= np.count_nonzero(~mapped[rows, cols]) <= 2:
            continue
        links[u], links[v] = v, u
        cos_lat = cos(pi * (0.5 - (ys[u] + ys[v] + 1) / (2 * sh)))
        distance[u] = distance[v] = np.hypot(step[i, 0] * cos_lat, step[i, 1])
    return links, distance


def meander_phase(a, b, length_km, wavelength, amplitude):
    """Acumula a fase ao longo de cada curso, inclusive quando a orientação de uma aresta muda."""
    active = (amplitude[a] > 0) | (amplitude[b] > 0)
    anchors = np.flatnonzero(active & ((amplitude[a] == 0) | (amplitude[b] == 0)))
    first = np.full(len(amplitude), len(a))
    last = np.full(len(amplitude), -1)
    edge_ids = np.arange(len(a))
    for nodes in (a, b):
        np.minimum.at(first, nodes, edge_ids)
        np.maximum.at(last, nodes, edge_ids)
    phase = np.zeros((len(a), 2))
    direction = np.zeros(len(a), dtype=np.int8)
    increments = tau * length_km / wavelength
    for edge in np.r_[anchors, np.flatnonzero(active)]:
        if direction[edge]:
            continue
        node = b[edge] if amplitude[b[edge]] == 0 else a[edge]
        # Um circuito isolado também precisa de uma âncora onde a curva volte ao eixo original.
        amplitude[node] = 0
        angle = tau * ((node * 0.61803398875) % 1)
        while not direction[edge]:
            forward = a[edge] == node
            next_angle = angle + increments[edge]
            phase[edge] = (angle, next_angle) if forward else (next_angle, angle)
            direction[edge] = 1 if forward else -1
            node, angle = (b[edge] if forward else a[edge]), next_angle
            if amplitude[node] == 0:
                break
            edge = last[node] if first[node] == edge else first[node]
    return phase, direction


def channel_segments(nodes, next_node, incoming, outgoing, lon, lat, width_start, width_end, amplitude):
    """Curvas curtas passam pelos mesmos nós da rede, unindo o eixo principal suavemente."""
    begin = np.column_stack([lon[nodes], lat[nodes]])
    delta = np.column_stack([longitude_step(lon[nodes], lon[next_node]), lat[next_node] - lat[nodes]])
    end = begin + delta
    prev_delta = np.column_stack([longitude_step(lon[incoming], lon[nodes]), lat[nodes] - lat[incoming]])
    next_delta = np.column_stack([longitude_step(lon[next_node], lon[outgoing]), lat[outgoing] - lat[next_node]])
    tangent_a = np.where((incoming >= 0)[:, None], 0.5 * (prev_delta + delta), delta)
    tangent_b = np.where((outgoing >= 0)[:, None], 0.5 * (delta + next_delta), delta)
    lat_scale = np.cos(np.deg2rad(0.5 * (begin[:, 1] + end[:, 1])))
    metric = np.column_stack([lat_scale, np.ones(len(nodes))])
    length = np.linalg.norm(delta * metric, axis=1)
    for tangent in (tangent_a, tangent_b):
        t_len = np.linalg.norm(tangent * metric, axis=1)
        tangent *= np.minimum(1.0, 1.2 * length / np.maximum(t_len, 1e-9))[:, None]
    bend = np.maximum(np.abs(delta[:, 0] * tangent_a[:, 1] - delta[:, 1] * tangent_a[:, 0]),
                      np.abs(delta[:, 0] * tangent_b[:, 1] - delta[:, 1] * tangent_b[:, 0]))
    km_deg = VERTICAL_KM / 180
    length_km = length * km_deg
    curved = (bend * lat_scale * km_deg / (3 * np.maximum(length, 1e-9)) > 0.22) & (np.maximum(width_start, width_end) >= 0.24)
    # A escala dos meandros acompanha a largura (Leopold e Wolman, 1957, doi:10.3133/pp282B).
    wavelength = np.clip(5 * (width_start + width_end), 7.5, 40.0)
    phase, direction = meander_phase(nodes, next_node, length_km, wavelength, amplitude)
    detail = np.where(curved, 4, 1)
    detailed = np.clip(np.ceil(6 * length_km / wavelength), 4, 14).astype(int)
    detail = np.where((amplitude[nodes] > 0) | (amplitude[next_node] > 0), np.maximum(detail, detailed), detail)
    straight = detail == 1
    result = [(begin[straight, 0], begin[straight, 1], width_start[straight],
               end[straight, 0], end[straight, 1], width_end[straight])]
    for count in np.unique(detail[~straight]):
        chosen = detail == count
        u = np.linspace(0.0, 1.0, count + 1)[None, :, None]
        a, b = begin[chosen, None], end[chosen, None]
        m, n = tangent_a[chosen, None], tangent_b[chosen, None]
        blend = u**2 * (3 - 2*u)
        curve = a + blend * (b-a) + (u**3 - 2*u**2 + u)*m + (u**3 - u**2)*n
        slope = 6*u*(1-u)*(b-a) + (3*u**2 - 4*u + 1)*m + (3*u**2 - 2*u)*n
        cos_lat = np.cos(np.deg2rad(curve[..., 1]))
        east = slope[..., 0] * cos_lat
        north = slope[..., 1]
        normal = np.stack((-north / cos_lat, east), axis=-1) / np.maximum(np.hypot(east, north), 1e-9)[..., None]
        angle = phase[chosen, :1] + u[..., 0] * np.diff(phase[chosen], axis=1)
        wave = 0.68 * np.sin(angle) + 0.22 * np.sin(0.47 * angle + 0.8) + 0.1 * np.sin(1.71 * angle - 0.7)
        wave *= direction[chosen, None]
        gain = amplitude[nodes[chosen], None] * (1 - blend[..., 0]) + amplitude[next_node[chosen], None] * blend[..., 0]
        curve += normal * (wave * gain / km_deg)[..., None]
        w = width_start[chosen, None] + u[..., 0] * (width_end[chosen] - width_start[chosen])[:, None]
        result.append((curve[:, :-1, 0].ravel(), curve[:, :-1, 1].ravel(), w[:, :-1].ravel(),
                       curve[:, 1:, 0].ravel(), curve[:, 1:, 1].ravel(), w[:, 1:].ravel()))
    return result


def network():
    """Nós (lon, lat, largura) e trechos (i, j) da rede de rios, já suavizados."""
    land = bn.load("Landmask.png")[..., 0] == 80
    flow = bn.ramp_t(bn.load("Waterflow.png"), bn.VIRIDIS)
    mapped = bn.is_color(bn.load("River.png"), (254, 231, 36))
    t_max = -20 + 60 * np.maximum(bn.ramp_t(bn.load("Temperatura Janeiro.png"), bn.MAGMA),
                                  bn.ramp_t(bn.load("Temperatura Julho.png"), bn.MAGMA))
    ice = bn.is_color(bn.load("Clima.png"), (104, 104, 104)) | bn.is_color(bn.load("BiomasGleba.png"), (236, 236, 236))
    river_land = land & ~ice & (t_max > 0)
    on = fill_pixel_holes(river_land & mapped, flow, river_land)
    # A faixa de fluxo tem 1 a 3 células de largura (o vale): afinada até 1 célula, senão vira rios paralelos.
    # A água encostada na faixa entra no afinamento, para a linha chegar até a costa em vez de recuar.
    coast = ~land & (thin_dilate(on) > 0)
    on = thin(on | coast) & land
    sh, sw = flow.shape
    ys, xs = np.nonzero(on)
    n = len(ys)
    if n == 0:
        return [np.empty(0) for _ in range(6)], 0
    idx = -np.ones(flow.shape, np.int64)
    idx[ys, xs] = np.arange(n)

    # A rede segue a máscara de rios afinada. Evita atalhos diagonais onde há uma ligação ortogonal.
    # Fluxo e altitude distinguem a rota a jusante dentro da rede.
    h = np.fromfile(D / "height_4096x2048.f32", "<f4").reshape(flow.shape)
    nb, nby, nbx, metric = [], [], [], []
    cos_lat = np.cos(np.deg2rad(90 - (ys + 0.5) * 180 / sh))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy == 0 and dx == 0:
                continue
            ny, nx = np.clip(ys + dy, 0, sh - 1), (xs + dx) % sw
            bypass = (ny == ys) & (nx == xs)
            if dx and dy:
                bypass |= (idx[ys, nx] >= 0) | (idx[ny, xs] >= 0)
            nb.append(np.where(bypass, -1, idx[ny, nx]))
            nby.append(ny)
            nbx.append(nx)
            metric.append(np.hypot(dy, dx * cos_lat))
    nb, nby, nbx = np.stack(nb, 1), np.stack(nby, 1), np.stack(nbx, 1)
    water = ~land[nby, nbx]
    t = flow[ys, xs]
    elevation = h[ys, xs]
    mouth = select_outlets(nb, water.any(1), t)
    links, link_distance = reconnect_ends(nb, xs, ys, t, elevation, mapped, river_land)
    nb = np.column_stack((nb, links))

    down = downstream(nb, np.column_stack((*metric, link_distance)), elevation, t, mouth)

    lon = (xs + 0.5) * 360 / sw - 180
    lat = 90 - (ys + 0.5) * 180 / sh
    # Suavização ao longo do curso principal: média com o nó de cima (o afluente de maior fluxo) e o de baixo.
    # A linha segue os nós suavizados, com nascentes e foz no lugar.
    up = -np.ones(n, np.int64)
    has_down = (down >= 0) & ~mouth
    incoming = np.bincount(down[has_down], minlength=n)
    order = np.lexsort((incoming > 0, t))  # em um empate, prefere o curso que já vem de outro nó
    up[down[order][has_down[order]]] = order[has_down[order]]
    degree = (nb >= 0).sum(1)
    two_neighbors = np.sort(nb, axis=1)[:, -2:]
    # O trecho pode passar entre duas rotas de drenagem, inclusive onde a busca pela foz encontra um divisor.
    # Em um canal com dois vizinhos, a forma e a largura acompanham ambos mesmo quando o escoamento diverge.
    smooth_up = np.where(degree == 2, two_neighbors[:, 0], up)
    smooth_down = np.where(degree == 2, two_neighbors[:, 1], down)
    inner = (smooth_up >= 0) & (smooth_down >= 0) & ~mouth
    source_lon, source_lat = lon.copy(), lat.copy()
    for _ in range(3):
        d_lon = longitude_step(lon, lon[smooth_down])
        u_lon = longitude_step(lon, lon[smooth_up])
        nlon = lon + 0.25 * (d_lon + u_lon)
        nlat = lat + 0.25 * ((lat[smooth_down] - lat) + (lat[smooth_up] - lat))
        shifted_lon = source_lon + np.clip(longitude_step(source_lon, nlon), -180 / sw, 180 / sw)
        lon = np.where(inner, (shifted_lon + 180) % 360 - 180, lon)
        lat = np.where(inner, np.clip(nlat, source_lat - 90 / sh, source_lat + 90 / sh), lat)

    rise = maximum_filter(h, size=5, mode=("nearest", "wrap"))[ys, xs] - elevation
    east = longitude_step(lon[smooth_up], lon[smooth_down]) * cos_lat
    reach = np.hypot(east, lat[smooth_up] - lat[smooth_down]) * VERTICAL_KM / 180
    slope = np.where(inner, np.abs(elevation[smooth_down] - elevation[smooth_up]) / np.maximum(1.0, reach * 1000), 0)
    openness = 1 / (1 + (slope / 0.0014)**2 + (rise / 330)**2)
    smooth_flow = t.copy()
    for _ in range(2):
        smooth_flow = np.where(inner, 0.5 * smooth_flow + 0.25 * (smooth_flow[smooth_up] + smooth_flow[smooth_down]), t)
    w = width_km(smooth_flow, openness)
    source = (degree == 1) & (t < T0) & ~mouth
    w[source] = np.maximum(SOURCE_WIDTH, 0.72 * w[source])
    compatible = has_down & (elevation[down] - elevation < 55) & (t[down] >= t - 0.25)
    flowing = np.flatnonzero(compatible)
    receiving = down[flowing]
    d_east = longitude_step(lon[flowing], lon[receiving]) * cos_lat[flowing]
    edge_km = np.hypot(d_east, lat[flowing] - lat[receiving]) * VERTICAL_KM / 180
    steady_widths(w, flowing, receiving, edge_km, incoming > 1)
    a, side = np.nonzero(nb >= 0)
    b = nb[a, side]
    keep = (down[a] == b) | ((down[b] != a) & (a < b))
    a, b = a[keep], b[keep]
    # Só poda a ponta lateral de uma célula que duplica o fluxo do próprio canal.
    primary = up[b]
    spur = (degree[a] == 1) & ~mouth[a] & (down[a] == b) & (primary >= 0) & (primary != a) & (incoming[primary] > 0)
    spur &= (np.abs(t[a] - t[primary]) <= 2 / 255) & (down[b] >= 0)
    de = longitude_step(lon[b], lon[a]) * np.cos(np.deg2rad(lat[b]))
    dn = lat[a] - lat[b]
    prev = de * longitude_step(lon[b], lon[primary]) * np.cos(np.deg2rad(lat[b])) + dn * (lat[primary] - lat[b])
    nxt = de * longitude_step(lon[b], lon[down[b]]) * np.cos(np.deg2rad(lat[b])) + dn * (lat[down[b]] - lat[b])
    keep = ~(spur & (prev >= 0) & (nxt >= 0))
    a, b = a[keep], b[keep]
    before_a = np.where(degree[a] == 2, two_neighbors[a].sum(1) - b, np.where(down[a] == b, up[a], -1))
    after_b = np.where(degree[b] == 2, two_neighbors[b].sum(1) - a, np.where(up[b] == a, down[b], -1))
    # Um afluente conserva sua largura até entrar no tronco; o desenho de ambos se une no mesmo nó.
    joins = (down[a] == b) & (degree[b] > 2) & (up[b] != a)
    width_end = np.where(joins, np.minimum(w[b], 1.25 * w[a]), w[b])
    amplitude = np.minimum(2.2, 0.65 * w) * openness**1.5
    amplitude[(amplitude < 0.12) | (degree != 2) | water.any(1)] = 0
    segs = channel_segments(a, b, before_a, after_b, lon, lat, w[a], width_end, amplitude)
    m = np.flatnonzero(mouth & (up >= 0))
    # A foz avança até a água aberta para que a máscara de costa faça a transição.
    cos_lat = np.cos(np.deg2rad(lat[m]))
    dx_in = ((xs[m] - xs[up[m]] + sw / 2) % sw - sw / 2) * cos_lat
    dy_in = ys[m] - ys[up[m]]
    dx_out = (nbx[m] - xs[m, None] + sw / 2) % sw - sw / 2
    dy_out = nby[m] - ys[m, None]
    dx_metric = dx_out * cos_lat[:, None]
    alignment = (dx_in[:, None] * dx_metric + dy_in[:, None] * dy_out) / np.maximum(np.hypot(dx_metric, dy_out), 1e-6)
    toward = np.where(water[m], alignment, -np.inf).argmax(1)
    mlon = lon[m] + 0.78 * dx_out[np.arange(len(m)), toward] * 360 / sw
    mlat = lat[m] - 0.78 * dy_out[np.arange(len(m)), toward] * 180 / sh
    segs.append((lon[m], lat[m], w[m], mlon, mlat, w[m] * (1 + 0.12 * openness[m])))
    segments = [np.concatenate(c) for c in zip(*segs)]
    # A escala de exibição preserva o eixo e a forma dos meandros.
    segments[2] *= DISPLAY_WIDTH_SCALE
    segments[5] *= DISPLAY_WIDTH_SCALE
    return segments, n


def index_atlas(segs):
    """As primeiras linhas guardam (início, quantidade). O resto guarda dois texels por trecho."""
    alon, alat, aw, blon, blat, bw = segs
    x = (alon + 180) / 360
    y = (90 - alat) / 180
    dx = ((blon - alon + 180) % 360 - 180) / 360
    dy = (alat - blat) / 180
    records = np.column_stack([x, y, dx, dy, aw, bw, np.zeros((len(x), 2))]).astype("<f4")
    buckets = defaultdict(list)
    y_pad = HALO_KM / VERTICAL_KM
    for i, (u, v, du, dv, _, _, _, _) in enumerate(records):
        # A longitude cobre menos km perto dos polos. Usa a latitude mais extrema da faixa.
        low_y, high_y = max(0.0, min(v, v + dv) - y_pad), min(1.0, max(v, v + dv) + y_pad)
        edge_lat = pi * max(abs(0.5 - low_y), abs(0.5 - high_y))
        x_pad = min(0.5, y_pad / (2 * max(1e-6, cos(edge_lat))))
        low_x = floor((min(u, u + du) - x_pad) * GRID_W)
        high_x = floor((max(u, u + du) + x_pad) * GRID_W)
        if high_x - low_x + 1 >= GRID_W:
            low_x, high_x = 0, GRID_W - 1
        for row in range(floor(low_y * GRID_H), min(GRID_H - 1, floor(high_y * GRID_H)) + 1):
            for col in range(low_x, high_x + 1):
                buckets[row * GRID_W + col % GRID_W].append(i)

    cells = GRID_W * GRID_H
    samples = sum(len(ids) for ids in buckets.values())
    total_texels = cells + 2 * samples
    rows = (total_texels + GRID_W - 1) // GRID_W
    if rows > 8192:
        raise ValueError(f"O Godot aceita até 8192 linhas no atlas de rios, geradas {rows}")
    atlas = np.zeros((rows * GRID_W, 4), "<f4")
    cursor = cells
    for cell, ids in buckets.items():
        atlas[cell, :2] = cursor, len(ids)
        end = cursor + 2 * len(ids)
        atlas[cursor:end] = records[ids].reshape(-1, 4)
        cursor = end
    return atlas.reshape(rows, GRID_W, 4)


def build():
    neighbors = np.array([[1, -1], [0, 2], [1, -1], [-1, -1]])
    outlets = select_outlets(neighbors, np.array([True, True, False, True]), np.array([0.7, 0.8, 0.6, 0.9]))
    assert np.array_equal(outlets, [False, True, False, False]), "fozes conectadas precisam de uma saída comum"
    graph = np.array([[1, 2], [0, -1], [0, 3], [2, -1], [-1, -1]])
    preferred = downstream(graph, np.ones_like(graph), np.zeros(5), np.array([0.71, 0.5, 0.74, 0.92, 0.6]),
                           np.array([False, True, False, True, False]))
    assert np.array_equal(preferred, [2, -1, 3, -1, -1]), "a rota deve seguir o aumento de fluxo, inclusive quando é mais longa"
    # Duas pontas alinhadas nos lados do antimeridiano, com uma célula faltando.
    xs, ys = np.array([5, 6, 0, 1]), np.full(4, 2)
    mapped, river_land = np.zeros((5, 8), bool), np.ones((5, 8), bool)
    mapped[ys, xs] = True
    neighbors = np.array([[1], [0], [3], [2]])
    links, _ = reconnect_ends(neighbors, xs, ys, np.full(4, 0.9), np.zeros(4), mapped, river_land)
    assert np.array_equal(links, [-1, 2, 1, -1]), "a ligação deve cruzar o antimeridiano"
    river_land[2, 7] = False
    links, _ = reconnect_ends(neighbors, xs, ys, np.full(4, 0.9), np.zeros(4), mapped, river_land)
    assert (links < 0).all(), "a ligação não pode cruzar água ou gelo"
    a, b = np.array([0, 2]), np.array([1, 1])
    phase, direction = meander_phase(a, b, np.ones(2), np.full(2, 10), np.array([0., 1., 0.]))
    assert phase[0, 1] == phase[1, 1] and direction[0] == -direction[1], "o meandro deve atravessar o nó sem salto"
    w_open, w_narrow = width_km(np.array([0.85, 0.85]), np.array([1., 0.]))
    assert w_open > w_narrow > width_km(0.55, 1.), "a largura responde ao fluxo e ao confinamento"
    widths = np.array([2.0, 1.0, 0.4, 0.4])
    steady_widths(widths, np.array([0, 1, 2]), np.array([2, 2, 3]), np.full(3, 12), np.array([False, False, True, False]))
    assert widths[2] == 2 and 1.5 < widths[3] < widths[2], "a saída da confluência deve conservar sua largura e variar aos poucos"
    segs, nodes = network()
    atlas = index_atlas(segs)
    with (D / ATLAS_NAME).open("wb") as file:
        file.write(struct.pack("<4sI", MAGIC, atlas.shape[0]))
        atlas.tofile(file)
    counts = atlas[:GRID_H, :, 1]
    print(f"rios: {nodes} nós, {len(segs[0])} trechos; "
          f"{np.count_nonzero(counts)} células com rios, até {int(counts.max())} trechos por célula")


if __name__ == "__main__":
    build()
