"""Kushol chat wallpaper v2 — a dense, original education doodle set (pens, pencils, books,
school tools, science, maths) for web (SVG tile) and app (TS path module).

Layout: 420 x 420 tile = 6 x 6 cells of 70; one main doodle per cell (jittered + rotated,
checked to stay inside its cell so tiles never cut a drawing) and a small filler (maths sign,
letter, sparkle) on every interior cell corner. Deterministic (seeded) so regenerating is stable.
"""

import math
import random
import sys

TILE = 420
CELL = 70
GRID = TILE // CELL


def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def circ(cx, cy, r):
    return f"M{f(cx - r)} {f(cy)} a{f(r)} {f(r)} 0 1 0 {f(2 * r)} 0 a{f(r)} {f(r)} 0 1 0 {f(-2 * r)} 0"


def rrect(x, y, w, h, r):
    return (f"M{f(x + r)} {f(y)} H{f(x + w - r)} Q{f(x + w)} {f(y)} {f(x + w)} {f(y + r)} V{f(y + h - r)} "
            f"Q{f(x + w)} {f(y + h)} {f(x + w - r)} {f(y + h)} H{f(x + r)} Q{f(x)} {f(y + h)} {f(x)} {f(y + h - r)} "
            f"V{f(y + r)} Q{f(x)} {f(y)} {f(x + r)} {f(y)} Z")


def ellipse(cx, cy, rx, ry, deg):
    t = math.radians(deg)
    x1, y1 = cx - rx * math.cos(t), cy - rx * math.sin(t)
    x2, y2 = cx + rx * math.cos(t), cy + rx * math.sin(t)
    return (f"M{f(x1)} {f(y1)} A{f(rx)} {f(ry)} {f(deg)} 1 0 {f(x2)} {f(y2)} "
            f"A{f(rx)} {f(ry)} {f(deg)} 1 0 {f(x1)} {f(y1)}")


def dot(x, y):
    return f"M{f(x)} {f(y)} L{f(x + 0.01)} {f(y)}"


def radial_ticks(cx, cy, r1, r2, angles):
    out = []
    for a in angles:
        t = math.radians(a)
        out.append(f"M{f(cx + r1 * math.cos(t))} {f(cy - r1 * math.sin(t))} L{f(cx + r2 * math.cos(t))} {f(cy - r2 * math.sin(t))}")
    return " ".join(out)


# name: (w, h, path)
MAIN = {
    "pencil": (46, 10, "M4 0 H2 Q0 0 0 2 V8 Q0 10 2 10 H4 M4 0 H9 V10 H4 Z M6.5 0 V10 "
                       "M9 0 H34 L46 5 L34 10 H9 M34 0 V10 M41.5 2.9 L46 5 L41.5 7.1 M9 5 H34"),
    "pen": (46, 10, "M1.5 0 H16 V10 H1.5 Q0 10 0 8.5 V1.5 Q0 0 1.5 0 Z M4 3 H13 M16 1 H30 M16 9 H30 "
                    "M30 1 V9 M30 1 L37 2 L46 5 L37 8 L30 9 M38.5 5 H46 " + circ(37.5, 5, 0.9)),
    "open_book": (46, 30, "M23 5 C17 1 8 1 1 4 V27 C8 24 17 24 23 28 C29 24 38 24 45 27 V4 C38 1 29 1 23 5 Z "
                          "M23 5 V28 M6 9 H18 M6 14 H18 M6 19 H15 M28 9 H40 M28 14 H40 M28 19 H37"),
    "book_stack": (40, 31, rrect(0, 21, 40, 10, 1.5) + " " + rrect(3, 11, 35, 10, 1.5) + " " + rrect(7, 1, 28, 10, 1.5) +
                   " M35 23 V29 M33 23 V29 M7 13 V19 M9 13 V19 M29 3 V9 M27 3 V9"),
    "notebook": (30, 36, rrect(5, 0, 25, 36, 2.5) + " M11 9 H25 M11 15 H25 M11 21 H25 M11 27 H20 " +
                 " ".join(circ(4.5, y, 2) for y in (6, 12, 18, 24, 30))),
    "ruler": (46, 10, rrect(0, 0, 46, 10, 1.2) + " " +
              " ".join(f"M{x} 0 V{4.5 if x % 10 == 0 else 2.6}" for x in range(5, 45, 5))),
    "set_square": (32, 32, "M0 32 L0 0 L32 32 Z M6 26 L6 14.5 L17.5 26 Z M10 32 V29.5 M16 32 V29.5 M22 32 V29.5"),
    "protractor": (38, 20, "M0 20 A19 19 0 0 1 38 20 Z M11 20 A8 8 0 0 1 27 20 " +
                   radial_ticks(19, 20, 15, 18.5, (20, 40, 60, 90, 120, 140, 160))),
    "scissors": (34, 24, circ(6, 6, 5) + " " + circ(6, 18, 5) + " M10.5 8.5 L34 19 M10.5 15.5 L34 5 " + circ(19.5, 12, 1.2)),
    "globe": (30, 38, circ(15, 14, 12) + " M15 2 A6 12 0 0 0 15 26 A6 12 0 0 0 15 2 M3 14 H27 "
                      "M5 8 Q15 11 25 8 M5 20 Q15 17 25 20 M15 26 V34 M8 36.5 H22"),
    "calculator": (24, 32, rrect(0, 0, 24, 32, 3) + " " + rrect(4, 4, 16, 7, 1) + " " +
                   " ".join(rrect(x, y, 3.6, 3.6, 0.8) for y in (15, 20.6, 26.2) for x in (4.4, 10.2, 16))),
    "backpack": (30, 36, rrect(2, 6, 26, 30, 7) + " M11 6 V3 Q11 1 13 1 H17 Q19 1 19 3 V6 " +
                 rrect(7, 20, 16, 11, 3) + " M7 24.5 H23 M15 24.5 V27 M2 15 H5 M25 15 H28"),
    "grad_cap": (42, 27, "M0 9 L21 0 L42 9 L21 18 Z M9 13 V21 Q21 27 33 21 V13 M21 9 L36 13 V22 "
                         "M34 22 L36 27 L38 22 Z"),
    "diploma": (44, 22, "M7 2 H38 M7 16 H38 M7 2 A3.5 7 0 0 0 7 16 A3.5 7 0 0 0 7 2 M38 2 A3.5 7 0 0 1 38 16 "
                        "M20 2 V16 M24 2 V16 M20 16 L18 22 L21 20 M24 16 L26 22 L23 20"),
    "chalkboard": (46, 34, rrect(0, 0, 46, 28, 2) + " " + rrect(3, 3, 40, 22, 1) +
                   " M8 20 L12 9 L16 20 M9.6 16 H14.4 M20 14.5 H26 M23 11.5 V17.5 M31 11 L33.5 9 V20 "
                   "M10 28 L7 34 M36 28 L39 34"),
    "microscope": (30, 38, rrect(2, 33, 26, 4.5, 1.5) + " M22 33 V27 Q28.5 22 24 12.5 M7 4.5 L11.5 1.5 L21.5 16.5 L17 19.5 Z "
                           "M5 6 L9.5 3 M17.6 20 L16.5 23.5 M9 25.5 H27 " + circ(24, 18, 1.4)),
    "pencil_cup": (28, 36, rrect(3, 17, 22, 19, 2.5) + " M3 22 H25 M7 17 V7 L9.5 2 L12 7 V17 M7 7 H12 "
                           "M15 17 V5.5 Q17 1 19 5.5 V17 M17 1.5 V4 M20.5 17 L24 4.5 L27 5.3 L23.5 17.6"),
    "flask": (24, 30, "M9 0 H15 M10 0 V10 L1.2 25.5 Q0 30 4.5 30 H19.5 Q24 30 22.8 25.5 L14 10 V0 M5 21 H19 " +
                      circ(10, 25.5, 1.2) + " " + circ(14.5, 24, 0.9) + " " + circ(12, 17.5, 0.8)),
    "test_tubes": (30, 34, "M2 4 V28 A4 4 0 0 0 10 28 V4 M0 4 H12 M2 19 H10 "
                           "M18 4 V24 A4 4 0 0 0 26 24 V4 M16 4 H28 M18 15 H26 " + circ(6, 25, 1) + " " + circ(22, 21, 0.9)),
    "apple": (24, 26, "M12 7 C5 3 0 9 1 15 C2 22 7 26 12 24 C17 26 22 22 23 15 C24 9 19 3 12 7 Z "
                      "M12 7 Q12 3 14 1 M13.5 4.5 Q18 0.5 21.5 3 Q17.5 6.5 13.5 4.5 Z M6 12 Q6.5 9.5 8.5 9"),
    "bell": (26, 30, "M13 3 C6 3 5 10 5 15 V20 L2 24 H24 L21 20 V15 C21 10 20 3 13 3 Z M13 0.5 V3 " + circ(13, 27, 2)),
    "trophy": (28, 32, "M7 2 H21 V10 C21 16 17 19 14 19 C11 19 7 16 7 10 Z M7 5 H3.5 Q2 12 8 14 M21 5 H24.5 Q26 12 20 14 "
                       "M14 19 V25 " + rrect(8, 25, 12, 6, 1) + " M14 6.5 L15 8.6 L17.3 8.9 L15.6 10.4 L16.1 12.7 L14 11.5 "
                       "L11.9 12.7 L12.4 10.4 L10.7 8.9 L13 8.6 Z"),
    "lightbulb": (20, 32, "M10 0 A10 10 0 0 1 16 18 L16 23 L4 23 L4 18 A10 10 0 0 1 10 0 Z M5 26.5 H15 M7 30 H13 "
                          "M7.5 23 V16 L10 13 L12.5 16 V23"),
    "paintbrush": (46, 10, "M0 5 Q0 3 3 3 L26 4 V6 L3 7 Q0 7 0 5 Z " + rrect(26, 2.5, 8, 5, 1) +
                           " M30 2.5 V7.5 M34 2 Q43 1.5 46 5 Q43 8.5 34 8"),
    "paperclip": (12, 34, "M9 10 V26 A4 4 0 0 1 1 26 V6 A5 5 0 0 1 11 6 V24 A2 2 0 0 1 7 24 V10"),
    "magnifier": (30, 30, circ(11, 11, 9.5) + " M5.5 8.5 A6 6 0 0 1 10.5 5 M18 17 L27.5 26.5 Q28.5 28.5 26.5 27.5 L17 18"),
    "laptop": (44, 28, rrect(6, 0, 32, 22, 2) + " " + rrect(9, 3, 26, 16, 1) + " M0 24 H44 L41 28 H3 Z M19 26 H25"),
    "atom": (32, 32, ellipse(16, 16, 15, 5.5, 0) + " " + ellipse(16, 16, 15, 5.5, 60) + " " +
             ellipse(16, 16, 15, 5.5, 120) + " " + circ(16, 16, 2)),
    "abacus": (32, 28, rrect(0, 0, 32, 28, 2) + " M2 8 H30 M2 14 H30 M2 20 H30 " +
               " ".join(circ(x, y, 2.2) for x, y in ((7, 8), (12, 8), (24, 8), (9, 14), (20, 14), (25, 14), (7, 20), (12, 20), (17, 20)))),
    "compass": (26, 36, circ(13, 4.5, 3) + " M13 1.5 V0 M11 7 L3 34 M15 7 L22 29 M21 29 L23 34 L24.5 29 Z M8 20 Q13 22.5 18 20"),
    "alarm_clock": (28, 30, circ(14, 16, 11) + " M14 16 V10 M14 16 L18 18.5 M4 7 A5 5 0 0 1 10 3.5 M24 7 A5 5 0 0 0 18 3.5 "
                            "M7 26 L5 29.5 M21 26 L23 29.5"),
    "eraser": (24, 14, "M0 6 L6 0 H24 L18 6 Z M0 6 V14 H18 V6 M18 14 L24 8 V0 M8 6 V14 M14 0 L8 6"),
    "crayon": (40, 10, "M9 0 H33 L40 5 L33 10 H9 Q7 10 7 8 V2 Q7 0 9 0 Z M14 0 V10 M28 0 V10 M16.5 3 L19 7 L21.5 3 L24 7 L26 3"),
    "question": (32, 30, "M6 0 H26 Q32 0 32 6 V18 Q32 24 26 24 H14 L7 30 V24 H6 Q0 24 0 18 V6 Q0 0 6 0 Z "
                         "M12.5 9 Q12.5 5 16 5 Q19.5 5 19.5 8.5 Q19.5 11 16 12.5 V14.5 " + dot(16, 19)),
    "paper_plane": (36, 28, "M0 10 L36 0 L23 28 L17 16 Z M17 16 L36 0 M17 16 L15 24"),
    "music": (22, 24, "M8 19 V2 L20 0 V16 " + circ(5, 19, 3) + " " + circ(17, 16, 3) + " M8 6 L20 4"),
}

SMALL = {
    "sparkle": (12, 12, "M6 0 Q6.8 5.2 12 6 Q6.8 6.8 6 12 Q5.2 6.8 0 6 Q5.2 5.2 6 0 Z"),
    "star": (12, 12, "M6 0 L7.8 4.2 L12 4.6 L8.8 7.4 L9.8 11.8 L6 9.4 L2.2 11.8 L3.2 7.4 L0 4.6 L4.2 4.2 Z"),
    "heart": (12, 11, "M6 11 C-3 5 1 -1.5 6 2.5 C11 -1.5 15 5 6 11 Z"),
    "plus": (10, 10, "M0 5 H10 M5 0 V10"),
    "times": (9, 9, "M0 0 L9 9 M9 0 L0 9"),
    "divide": (12, 11, "M0 5.5 H12 " + dot(6, 1) + " " + dot(6, 10)),
    "equals": (12, 6, "M0 0 H12 M0 6 H12"),
    "pi": (12, 11, "M0 2 H12 M3.5 2 V11 M8.5 2 V9 Q8.5 11 11 11"),
    "sqrt": (16, 12, "M0 7 L2.5 6 L5 12 L9 0 H16"),
    "sigma": (10, 12, "M10 0 H0 L5 6 L0 12 H10"),
    "percent": (11, 12, "M1 12 L10 0 " + circ(2.2, 2.5, 1.7) + " " + circ(8.8, 9.5, 1.7)),
    "a": (10, 12, "M0 12 L5 0 L10 12 M2 7.6 H8"),
    "b": (9, 12, "M0 0 V12 H5 Q9 12 9 9 Q9 6 5 6 H0 M0 6 H4 Q8 6 8 3 Q8 0 4 0 H0"),
    "c": (10, 12, "M10 2.2 A6 6 0 1 0 10 9.8"),
    "one": (8, 12, "M1.5 3 L4.5 0 V12 M1.5 12 H7.5"),
    "two": (9, 12, "M1 3 Q1 0 4.5 0 Q8.5 0 8.5 3.5 Q8.5 6 1 12 H9"),
    "three": (9, 12, "M1 1 H8.5 L5 5.4 Q9 5.4 9 8.8 Q9 12 5 12 Q2 12 1 10.4"),
    "dot": (3, 3, circ(1.5, 1.5, 1.4)),
    "ring": (5, 5, circ(2.5, 2.5, 2.3)),
}

# Cell order: varied neighbours, the classroom staples (pen, pencil, books) appear more than once.
CELL_ORDER = [
    "pencil", "open_book", "atom", "pen", "globe", "ruler",
    "calculator", "grad_cap", "paintbrush", "notebook", "scissors", "apple",
    "book_stack", "lightbulb", "set_square", "chalkboard", "flask", "pencil_cup",
    "compass", "trophy", "pen", "microscope", "diploma", "backpack",
    "magnifier", "crayon", "open_book", "alarm_clock", "protractor", "test_tubes",
    "eraser", "laptop", "paper_plane", "abacus", "question", "bell",
]
SMALL_ORDER = ["sparkle", "pi", "a", "dot", "plus", "heart", "sqrt", "two", "ring", "star", "divide",
               "b", "sigma", "dot", "equals", "three", "times", "c", "percent", "one", "sparkle",
               "ring", "plus", "star", "dot"]


def rotated_half_extent(w, h, deg):
    t = math.radians(deg)
    return (abs(w * math.cos(t)) + abs(h * math.sin(t))) / 2, (abs(w * math.sin(t)) + abs(h * math.cos(t))) / 2


def layout():
    rnd = random.Random(20261017)
    placed = []
    assert len(CELL_ORDER) == GRID * GRID
    for idx, name in enumerate(CELL_ORDER):
        w, h, d = MAIN[name]
        col, row = idx % GRID, idx // GRID
        cx, cy = col * CELL + CELL / 2, row * CELL + CELL / 2
        # Organic, WhatsApp-like scatter: random tilt, size and offset — kept inside the cell.
        for _ in range(200):
            deg = rnd.uniform(-35, 35)
            sc = rnd.uniform(0.86, 1.12)
            jx, jy = rnd.uniform(-11, 11), rnd.uniform(-11, 11)
            ex, ey = rotated_half_extent(w * sc, h * sc, deg)
            if abs(jx) + ex <= CELL / 2 - 3 and abs(jy) + ey <= CELL / 2 - 3:
                break
        else:
            deg, sc, jx, jy = 0, 1, 0, 0
            ex, ey = rotated_half_extent(w, h, 0)
            assert ex <= CELL / 2 - 3 and ey <= CELL / 2 - 3, name
        placed.append((d, f"translate({f(cx + jx)} {f(cy + jy)}) rotate({f(deg)}) scale({f(sc)}) translate({f(-w / 2)} {f(-h / 2)})"))
    k = 0
    for row in range(1, GRID):
        for col in range(1, GRID):
            name = SMALL_ORDER[k % len(SMALL_ORDER)]
            k += 1
            w, h, d = SMALL[name]
            deg = rnd.uniform(-30, 30)
            px, py = col * CELL + rnd.uniform(-6, 6), row * CELL + rnd.uniform(-6, 6)
            placed.append((d, f"translate({f(px)} {f(py)}) rotate({f(deg)}) translate({f(-w / 2)} {f(-h / 2)})"))
    # Edge signs: drawn on BOTH opposite edges (each tile shows one half), so the seam between
    # repeated tiles is as busy as the inside and the halves line up exactly.
    edge = ["star", "dot", "plus", "ring", "sparkle", "times", "dot", "heart", "ring", "plus", "dot"]
    e = 0
    for col in range(1, GRID):
        name = edge[e % len(edge)]
        e += 1
        w, h, d = SMALL[name]
        deg, px = rnd.uniform(-30, 30), col * CELL + rnd.uniform(-8, 8)
        for py in (0, TILE):
            placed.append((d, f"translate({f(px)} {f(py)}) rotate({f(deg)}) translate({f(-w / 2)} {f(-h / 2)})"))
    for row in range(1, GRID):
        name = edge[e % len(edge)]
        e += 1
        w, h, d = SMALL[name]
        deg, py = rnd.uniform(-30, 30), row * CELL + rnd.uniform(-8, 8)
        for px in (0, TILE):
            placed.append((d, f"translate({f(px)} {f(py)}) rotate({f(deg)}) translate({f(-w / 2)} {f(-h / 2)})"))
    w, h, d = SMALL["sparkle"]
    for px in (0, TILE):
        for py in (0, TILE):
            placed.append((d, f"translate({px} {py}) translate({f(-w / 2)} {f(-h / 2)})"))
    return placed


STROKE = "#095777"
OPACITY = 0.1
WIDTH = 1.35


def web_svg(items):
    paths = "\n".join(f'    <path d="{d}" transform="{t}"/>' for d, t in items)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{TILE}" height="{TILE}" viewBox="0 0 {TILE} {TILE}">
  <!-- Kushol Connect chat wallpaper (05 · owner 2026-10-17): original education line art — pens,
       pencils, books, school tools, science and maths — tiled behind the open conversation.
       Brand teal #095777 at {int(OPACITY * 100)}% opacity over the wall colour. Generated together with
       applications/app/src/components/chat/chat-wallpaper-doodles.ts (same paths). -->
  <g fill="none" stroke="{STROKE}" stroke-opacity="{OPACITY}" stroke-width="{WIDTH}" stroke-linecap="round" stroke-linejoin="round">
{paths}
  </g>
</svg>
'''


def app_ts(items):
    rows = "\n".join(f'  {{ d: "{d}", transform: "{t}" }},' for d, t in items)
    return f'''// Kushol Connect chat wallpaper doodles (05 · owner 2026-10-17): original education line art —
// pens, pencils, books, school tools, science and maths — tiled behind the open conversation
// (WhatsApp-style). Generated together with applications/web/src/assets/chat/doodles.svg (same
// paths). {TILE} × {TILE} tile: one drawing per 70-pt cell (kept inside its cell, so tiling never
// cuts one) plus a small sign on every interior cell corner.

export const WALLPAPER_TILE = {TILE};
export const WALLPAPER_STROKE_OPACITY = {OPACITY};
export const WALLPAPER_STROKE_WIDTH = {WIDTH};

export const WALLPAPER_DOODLES: readonly {{ d: string; transform: string }}[] = [
{rows}
];
'''


if __name__ == "__main__":
    items = layout()
    open(sys.argv[1], "w", encoding="utf-8", newline="\n").write(web_svg(items))
    open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(app_ts(items))
    print("items:", len(items))
