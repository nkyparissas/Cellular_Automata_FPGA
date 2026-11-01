"""Draw an openXC7 (nextpnr-xilinx) place-and-route result of lenia_pnr_top on
the xc7a100t die: a floorplan coloured by function, the critical path, and a
routing-congestion heat map (PNG files).

Inputs come from run_openxc7.sh: the placement dump (-o placement=), the routed
design (--write) and the timing report (--report --detailed-timing-report); the
tile grid comes from the Project X-Ray database shipped with openXC7.

Example:
    python3 boards/ooc_lenia/plot_pnr.py build/openxc7_lenia_n27_c16
"""
import argparse
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "model"))
from ca_model.viridis import VIRIDIS  # noqa: E402

SX, SY, LEGEND_W = 6, 4, 300           # pixels per tile column / row, legend width
GRID = re.compile(r"^X(\d+)Y(\d+)/")

# Functions of lenia_pnr_top, matched against the hierarchical net names a cell drives or reads.
FUNCTIONS = [
    ("window registers", "#4C72B0", r"i_engine\.(i_window\.|win\[)"),
    ("register stage", "#8172B3", r"i_rule\.win_q"),
    ("class pre-adders", "#55A868", r"i_rule\.g_cls\["),
    ("weight chain", "#CCB974", r"i_rule\.w\["),
    ("multipliers", "#C44E52", r"i_rule\.g_mul\["),
    ("product adder tree", "#DD8452", r"i_rule\.(i_sum|s_sum)"),
    ("shift and saturate", "#937860", r"i_rule\.(s_hi|s_lo|idx)"),
    ("growth table", "#64B5CD", r"i_rule\.(e_ram|e_q|i_table)"),
    ("centre delay and update", "#DA8BC3", r"i_rule\.(i_centre|c_d|next)|^new_cell"),
    ("valid pipeline", "#8C8C8C", r"i_rule\.i_vld|^cell_vld"),
    ("harness (LFSR, output fold)", "#4D4D4D", r"^(lfsr|col_sr|fold|led_o|gt_addr|gt_data|gt_we|kern_valid|kern_data|sel|vld)\b"),
]
OTHER = ("other logic", "#000000")
TILE_COLOURS = [("CLB", "#EDEDED"), ("BRAM", "#D6E6F5"), ("DSP", "#FADDC8"), ("IOB", "#C8C8C8"),
                ("IOI", "#C8C8C8"), ("CMT", "#E4DAF0"), ("INT", "#F7F7F7")]


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def load_tiles(tilegrid):
    t = json.loads(Path(tilegrid).read_text())
    w = max(v["grid_x"] for v in t.values()) + 1
    h = max(v["grid_y"] for v in t.values()) + 1
    return {(v["grid_x"], v["grid_y"]): v["type"] for v in t.values()}, w, h


def background(tiles, w, h):
    img = Image.new("RGB", (w * SX + LEGEND_W, h * SY), "white")
    d = ImageDraw.Draw(img)
    for (x, y), typ in tiles.items():
        colour = next((c for key, c in TILE_COLOURS if key in typ), None)
        if colour:
            d.rectangle([x * SX, y * SY, x * SX + SX - 1, y * SY + SY - 1], fill=rgb(colour))
    return img, d


def classify_cells(routed, passes=8, max_fanout=200):
    """Function of every cell, from the names of the nets on its outputs (else
    its inputs); cells touching only anonymous nets then take the majority
    function of the cells they share nets with."""
    top = next(iter(routed["modules"].values()))
    names = defaultdict(list)
    for n, v in top["netnames"].items():
        base = n.split("$")[0]                 # synthesis suffixes follow a '$'
        if base and " " not in base:
            for b in v["bits"]:
                names[b].append(base)
    out = {}
    for cname, c in top["cells"].items():
        typ = c["type"]
        if typ.startswith("DSP48E1"):
            out[cname] = "multipliers"
            continue
        if typ.startswith("RAMB"):
            out[cname] = "growth table"
            continue
        dirs = c.get("port_directions", {})
        outs = [n for p, bits in c["connections"].items() if dirs.get(p) == "output" for b in bits for n in names.get(b, [])]
        ins = [n for p, bits in c["connections"].items() if dirs.get(p) != "output" for b in bits for n in names.get(b, [])]
        cand = outs or ins or [cname]
        votes = Counter(next((f for f, _, pat in FUNCTIONS if re.search(pat, n)), OTHER[0]) for n in cand)
        votes.pop(OTHER[0], None) if len(votes) > 1 else None
        out[cname] = votes.most_common(1)[0][0]
    cells_of = defaultdict(set)
    for cname, c in top["cells"].items():
        for bits in c["connections"].values():
            for b in bits:
                if isinstance(b, int):
                    cells_of[b].add(cname)
    for _ in range(passes):
        changed = 0
        for cname in [n for n, f in out.items() if f == OTHER[0]]:
            votes = Counter()
            for bits in top["cells"][cname]["connections"].values():
                for b in bits:
                    group = cells_of.get(b, ()) if isinstance(b, int) else ()
                    if len(group) <= max_fanout:
                        votes.update(out[m] for m in group if out[m] != OTHER[0])
            if votes:
                out[cname] = votes.most_common(1)[0][0]
                changed += 1
        if not changed:
            break
    return out


def floorplan(tiles, w, h, placement, functions, title, path):
    img, d = background(tiles, w, h)
    per_tile = defaultdict(Counter)
    for cname, p in placement.items():
        m = GRID.match(p["nextpnr_bel"])
        if m:
            per_tile[(int(m.group(1)), int(m.group(2)))][functions.get(cname, OTHER[0])] += 1
    colours = {f: rgb(c) for f, c, _ in FUNCTIONS} | {OTHER[0]: rgb(OTHER[1])}
    totals = Counter()
    for (x, y), cnt in per_tile.items():
        f = cnt.most_common(1)[0][0]
        totals.update(cnt)
        big = any(k in tiles.get((x, y), "") for k in ("DSP", "BRAM"))
        dx, dy = (SX * 2, SY * 4) if big else (SX - 1, SY - 1)
        d.rectangle([x * SX, y * SY, x * SX + dx, y * SY + dy], fill=colours[f])
    legend(d, w * SX + 12, title, [(f, colours[f], totals[f]) for f, _, _ in FUNCTIONS + [(*OTHER, "")] if totals[f]])
    img.save(path)
    return img


def legend(d, x0, title, rows):
    d.text((x0, 10), title, fill="black", font=font(14))
    y = 40
    for label, colour, count in rows:
        d.rectangle([x0, y, x0 + 14, y + 12], fill=colour)
        d.text((x0 + 20, y - 1), f"{label} ({count})", fill="black", font=font(12))
        y += 20
    y += 10
    for key, colour in TILE_COLOURS[:4]:
        d.rectangle([x0, y, x0 + 14, y + 12], fill=rgb(colour), outline="#999999")
        d.text((x0 + 20, y - 1), f"{key} tile column", fill="black", font=font(12))
        y += 20


def critical_path(tiles, w, h, report, title, path):
    img, d = background(tiles, w, h)
    cp = report["critical_paths"][0]
    pts, total = [], 0.0
    for step in cp["path"]:
        total += step["delay"]
        for end in ("from", "to"):
            loc = tuple(step[end]["loc"])
            if not pts or pts[-1] != loc:
                pts.append(loc)
    xy = [(x * SX + SX // 2, y * SY + SY // 2) for x, y in pts]
    if len(xy) > 1:
        d.line(xy, fill=rgb("#C44E52"), width=3)
    for i, (px, py) in enumerate(xy):
        r = 6 if i in (0, len(xy) - 1) else 3
        d.ellipse([px - r, py - r, px + r, py + r], fill=rgb("#C44E52") if 0 < i < len(xy) - 1 else rgb("#4C72B0"))
    fmax = next(iter(report.get("fmax", {}).values()), {})
    lines = [title, f"path delay {total:.2f} ns, {len(cp['path'])} steps",
             f"achieved {fmax.get('achieved', 0):.1f} MHz (target {fmax.get('constraint', 0):.0f})",
             f"from {cp['from']}", f"to {cp['to']}"]
    x0 = w * SX + 12
    for i, s in enumerate(lines):
        d.text((x0, 10 + 20 * i), s[:40], fill="black", font=font(13 if i == 0 else 11))
    nets = [s.get("net", "") for s in cp["path"] if s.get("type") == "routing"]
    y = 130
    d.text((x0, y), "nets along the path:", fill="black", font=font(11))
    for n in nets[:30]:
        y += 16
        d.text((x0, y), n.replace("i_engine.g_lenia.i_rule.", "")[:42], fill="#333333", font=font(10))
    img.save(path)


def congestion(tiles, w, h, routed, title, path):
    img, d = background(tiles, w, h)
    use = Counter()
    top = next(iter(routed["modules"].values()))
    for v in top["netnames"].values():
        r = v.get("attributes", {}).get("ROUTING")
        if r:
            for tok in r.split(";"):
                m = GRID.match(tok)
                if m:
                    use[(int(m.group(1)), int(m.group(2)))] += 1
    peak = max(use.values()) if use else 1
    for (x, y), n in use.items():
        c = VIRIDIS[min(255, int(255 * math.log1p(n) / math.log1p(peak)))]
        d.rectangle([x * SX, y * SY, x * SX + SX - 1, y * SY + SY - 1], fill=(c >> 16, (c >> 8) & 255, c & 255))
    x0 = w * SX + 12
    d.text((x0, 10), title, fill="black", font=font(14))
    d.text((x0, 34), f"routing resources used per tile (log scale), peak {peak}", fill="black", font=font(11))
    for i in range(200):
        c = VIRIDIS[int(255 * i / 199)]
        d.line([(x0 + i, 56), (x0 + i, 70)], fill=(c >> 16, (c >> 8) & 255, c & 255))
    d.text((x0, 74), "1", fill="black", font=font(10))
    d.text((x0 + 180, 74), str(peak), fill="black", font=font(10))
    img.save(path)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("run_dir", help="output folder of run_openxc7.sh")
    ap.add_argument("--tilegrid", default=str(Path.home() / "openxc7/share/nextpnr/external/prjxray-db/artix7/xc7a100t/tilegrid.json"))
    args = ap.parse_args(argv)
    run = Path(args.run_dir)
    tiles, w, h = load_tiles(args.tilegrid)
    placement = json.loads((run / "placement.json").read_text())
    routed = json.loads((run / "routed.json").read_text())
    report = json.loads((run / "report.json").read_text())
    name = run.name.replace("openxc7_lenia_", "Lenia ")
    functions = classify_cells(routed)
    floorplan(tiles, w, h, placement, functions, f"{name}: floorplan", run / "floorplan.png")
    critical_path(tiles, w, h, report, f"{name}: critical path", run / "critical_path.png")
    congestion(tiles, w, h, routed, f"{name}: routing congestion", run / "congestion.png")
    print(f"wrote floorplan.png, critical_path.png, congestion.png in {run}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
