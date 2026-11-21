"""Original ASCII crystal clock: 12 radial prisms (hours) around a ring of orbs.

Shared by the fetch and fastfetch configs. Each cell gets a role so the
fastfetch build can colour it: 'p' prism core, 'e' prism edge, 'o' orb,
'r' ring, ' ' empty.
"""
import math

W, H = 47, 21          # terminal cells; cells are ~2x taller than wide
ASPECT = 2.05
R_RING = 4.4           # in "row" units
R_IN, R_OUT = 6.0, 10.4
ORBS = 8


def _seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)))
    return math.hypot(px - (ax + vx * t), py - (ay + vy * t))


def cells():
    cx, cy = (W - 1) / 2, (H - 1) / 2
    grid = [[' '] * W for _ in range(H)]
    spokes = []
    for k in range(12):
        a = math.radians(k * 30)
        length = R_OUT if k % 3 == 0 else R_OUT - 1.4   # 12/3/6/9 a bit longer
        dx, dy = math.sin(a), -math.cos(a)
        spokes.append((dx * R_IN, dy * R_IN, dx * length, dy * length))
    for y in range(H):
        for x in range(W):
            px, py = (x - cx) / ASPECT, y - cy
            d = min(_seg_dist(px, py, *s) for s in spokes)
            if d < 0.42:
                grid[y][x] = 'p'
            elif d < 0.78:
                grid[y][x] = 'e'
            elif abs(math.hypot(px, py) - R_RING) < 0.3:
                grid[y][x] = 'r'
    for i in range(ORBS):
        a = math.radians(i * 360 / ORBS + 22.5)
        x = round(cx + math.sin(a) * R_RING * ASPECT)
        y = round(cy - math.cos(a) * R_RING)
        grid[y][x] = 'o'
    return grid


def plain(chars={'p': '#', 'e': '=', 'o': '@', 'r': '.', ' ': ' '}):
    return [''.join(chars[c] for c in row).rstrip() for row in cells()]


if __name__ == '__main__':
    print('\n'.join(plain()))
