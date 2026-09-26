#!/usr/bin/env python3
"""Generate map JSON files for GhanaEmpires.

Writes data/maps/{small,medium,large}.json in the format consumed by
scripts/hex/hex_grid.gd:

    {"name": str, "width": int, "height": int,
     "terrain": [row_string, ...],        # one char per hex, row-major
     "resources": [{"x": int, "y": int, "type": str}, ...]}

Terrain codes match data/terrain.json "code" fields:
    g grassland  s savanna  f forest  d dense_forest  h hills
    m mountains  x desert   r river   c coast         o ocean

Deterministic: fixed seed per map size, so re-running reproduces files.
"""
import json
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "data", "maps"))

CODE = {
    "grassland": "g", "savanna": "s", "forest": "f", "dense_forest": "d",
    "hills": "h", "mountains": "m", "desert": "x", "river": "r",
    "coast": "c", "ocean": "o",
}

# Resource id -> terrains it may appear on (data/resources.json).
RESOURCE_TERRAINS = {
    "gold": ["hills", "mountains"],
    "kola": ["forest", "dense_forest"],
    "ivory": ["savanna"],
    "salt": ["coast", "desert"],
    "iron": ["hills"],
    "cloth": ["grassland"],
}

# Starting cities, in the 60x45 design space used by scripts/game.gd.
START_CITIES = [
    (28, 30), (30, 32), (26, 29),   # Ashanti
    (15, 8), (13, 10),              # Dagbon
    (42, 36), (40, 38),             # Fante
    (45, 10), (47, 12),             # Mamprusi
]


def smoothstep(a, b, x):
    if x <= a:
        return 0.0
    if x >= b:
        return 1.0
    t = (x - a) / (b - a)
    return t * t * (3 - 2 * t)


def value_noise(w, h, cell, rng):
    """Bilinearly interpolated value noise on a cell grid."""
    gw = w // cell + 2
    gh = h // cell + 2
    grid = [[rng.random() for _ in range(gw)] for _ in range(gh)]
    out = [[0.0] * w for _ in range(h)]
    for y in range(h):
        gy = y / cell
        y0 = int(gy)
        fy = gy - y0
        for x in range(w):
            gx = x / cell
            x0 = int(gx)
            fx = gx - x0
            a = grid[y0][x0]
            b = grid[y0][x0 + 1]
            c = grid[y0 + 1][x0]
            d = grid[y0 + 1][x0 + 1]
            top = a + (b - a) * fx
            bot = c + (d - c) * fx
            out[y][x] = top + (bot - top) * fy
    return out


def fbm(w, h, rng, cells=(32, 16, 8), weights=(0.5, 0.3, 0.2)):
    acc = [[0.0] * w for _ in range(h)]
    for cell, wt in zip(cells, weights):
        layer = value_noise(w, h, max(2, cell), rng)
        for y in range(h):
            for x in range(w):
                acc[y][x] += layer[y][x] * wt
    return acc


def generate(name, width, height, seed):
    rng = random.Random(seed)
    elev = fbm(width, height, rng, cells=(36, 18, 9))
    moist = fbm(width, height, rng, cells=(28, 14, 7))
    warp = value_noise(width, height, 12, rng)

    terrain = [["g"] * width for _ in range(height)]
    for y in range(height):
        t = y / float(height - 1)          # 0 = north, 1 = south
        for x in range(width):
            u = t + 0.09 * (warp[y][x] - 0.5)
            e = elev[y][x]
            m = moist[y][x]

            if u > 0.92:
                kind = "ocean"
            elif u > 0.85:
                kind = "coast" if warp[y][x] > 0.3 else "ocean"
            elif u > 0.79:
                kind = "grassland" if warp[y][x] > 0.45 else "coast"
            elif u < 0.20:
                kind = "desert" if m < 0.52 else "savanna"
            elif u < 0.42:
                if e > 0.84:
                    kind = "mountains"
                elif e > 0.68:
                    kind = "hills"
                elif m < 0.45:
                    kind = "savanna"
                else:
                    kind = "grassland"
            else:
                if e > 0.86:
                    kind = "mountains"
                elif e > 0.70:
                    kind = "hills"
                elif m > 0.80:
                    kind = "dense_forest"
                elif m > 0.64:
                    kind = "forest"
                elif u < 0.55 and m < 0.5:
                    kind = "savanna"
                else:
                    kind = "grassland"
            terrain[y][x] = kind

    _carve_rivers(terrain, elev, rng)
    _force_land_zones(terrain, START_CITIES, (width, height))

    resources = _place_resources(terrain, width, height, rng)

    rows = ["".join(CODE[terrain[y][x]] for x in range(width)) for y in range(height)]
    return {
        "name": name,
        "width": width,
        "height": height,
        "terrain": rows,
        "resources": resources,
    }


def _carve_rivers(terrain, elev, rng, count=3, max_len=60):
    h = len(terrain)
    w = len(terrain[0])
    candidates = [(elev[y][x], x, y) for y in range(1, h - 1) for x in range(1, w - 1)
                  if terrain[y][x] in ("mountains", "hills")]
    candidates.sort(reverse=True)
    starts = candidates[:count * 6]
    rng.shuffle(starts)
    used = 0
    for _, x, y in starts:
        if used >= count:
            break
        cx, cy = x, y
        for _ in range(max_len):
            if terrain[cy][cx] in ("ocean", "coast", "river"):
                break
            terrain[cy][cx] = "river"
            neighbours = [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
            best = None
            best_e = elev[cy][cx]
            for nx, ny in neighbours:
                if 0 <= nx < w and 0 <= ny < h and terrain[ny][nx] not in ("ocean", "coast", "river"):
                    if elev[ny][nx] < best_e:
                        best_e = elev[ny][nx]
                        best = (nx, ny)
            if best is None:
                break
            cx, cy = best
        used += 1


def _force_land_zones(terrain, anchors, size):
    """Guarantee starting cities sit on land (design-space coords only)."""
    w, h = size
    for ax, ay in anchors:
        if not (0 <= ax < w and 0 <= ay < h):
            continue
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                x, y = ax + dx, ay + dy
                if 0 <= x < w and 0 <= y < h and terrain[y][x] in ("ocean", "coast", "river"):
                    terrain[y][x] = "grassland" if abs(dx) + abs(dy) <= 1 else "savanna"


def _place_resources(terrain, w, h, rng):
    """Scatter resources, then guarantee one near every starting city."""
    compat = {}
    for rid, terrains in RESOURCE_TERRAINS.items():
        for t in terrains:
            compat.setdefault(t, []).append(rid)

    placed = {}
    for y in range(h):
        for x in range(w):
            t = terrain[y][x]
            if t in compat and rng.random() < 0.022:
                placed[(x, y)] = rng.choice(compat[t])

    for ax, ay in START_CITIES:
        if not (0 <= ax < w and 0 <= ay < h):
            continue
        if any(abs(px - ax) <= 5 and abs(py - ay) <= 5 for px, py in placed):
            continue
        for radius in range(1, 6):
            ring = []
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    if max(abs(dx), abs(dy)) != radius:
                        continue
                    x, y = ax + dx, ay + dy
                    if 0 <= x < w and 0 <= y < h and terrain[y][x] in compat:
                        ring.append((x, y))
            if ring:
                x, y = rng.choice(ring)
                placed[(x, y)] = rng.choice(compat[terrain[y][x]])
                break

    return [{"x": x, "y": y, "type": rid} for (x, y), rid in sorted(placed.items())]


SIZES = {
    "small": (40, 30, 1041),
    "medium": (60, 45, 2027),
    "large": (80, 60, 3051),
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (w, h, seed) in SIZES.items():
        data = generate(name.capitalize(), w, h, seed)
        path = os.path.join(OUT_DIR, name + ".json")
        with open(path, "w") as fh:
            json.dump(data, fh, separators=(",", ":"))
        land = sum(1 for row in data["terrain"] for c in row if c not in "co")
        print(f"{path}: {w}x{h}, {land} land hexes, {len(data['resources'])} resources")


if __name__ == "__main__":
    main()
