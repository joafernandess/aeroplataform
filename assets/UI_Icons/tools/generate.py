# Writes assets/UI_Icons/src/*.svg — flat minimalist HUD icons.
# One solid colour per icon (plus at most one lighter/darker tone of the same hue), rounded geometry,
# details cut out (transparent), no outline, no 3D, no gloss, no sparkles.
# Usage (repo root): python3 assets/UI_Icons/tools/generate.py assets/UI_Icons/src
#                    node assets/UI_Icons/tools/fit.js assets/UI_Icons/src 424
#                    node assets/UI_Icons/tools/export.js
import math, os, sys

OUT = sys.argv[1]
R = 12  # corner rounding: shapes grow by R with round joins


def rr(x, y, w, h, r=10):
    r = min(r, w / 2, h / 2)
    return (f"M{x + r} {y} H{x + w - r} Q{x + w} {y} {x + w} {y + r} V{y + h - r} Q{x + w} {y + h} {x + w - r} {y + h} "
            f"H{x + r} Q{x} {y + h} {x} {y + h - r} V{y + r} Q{x} {y} {x + r} {y} Z")


def poly(*pts):
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"


def ell(cx, cy, rx, ry, ccw=False):
    s = 0 if ccw else 1
    return f"M{cx - rx} {cy} A{rx} {ry} 0 1 {s} {cx + rx} {cy} A{rx} {ry} 0 1 {s} {cx - rx} {cy} Z"


def star(cx, cy, r, n=5, ri=0.48):
    pts = []
    for k in range(2 * n):
        a = -math.pi / 2 + k * math.pi / n
        q = r if k % 2 == 0 else r * ri
        pts.append((cx + q * math.cos(a), cy + q * math.sin(a)))
    return poly(*pts)


def shape(d, color, grow=2 * R, rule="nonzero"):
    """Filled shape with soft corners (grown by grow/2 with round joins)."""
    return (f'<path d="{d}" fill="{color}" fill-rule="{rule}" stroke="{color}" stroke-width="{grow}" '
            f'stroke-linejoin="round"/>')


def line(d, color, w):
    return (f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w}" stroke-linecap="round" '
            f'stroke-linejoin="round"/>')


# Cut-outs (black in the mask = transparent in the icon)
def cut(d, grow=8):
    return f'<path d="{d}" fill="#000" stroke="#000" stroke-width="{grow}" stroke-linejoin="round"/>'


def cutline(d, w):
    return line(d, "#000", w)


def icon(name, layers, cuts=""):
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
           f'<title>{name}</title>'
           f'<defs><mask id="cut" maskUnits="userSpaceOnUse" x="-1" y="-1" width="514" height="514">'
           f'<rect x="-1" y="-1" width="514" height="514" fill="#fff"/>{cuts}</mask></defs>'
           f'<g id="art" mask="url(#cut)">{"".join(layers)}</g></svg>\n')
    open(os.path.join(OUT, name + ".svg"), "w").write(svg)


# Main colour, second tone (same hue)
C = {
    "shop": ("#FFD23F", "#FFE893"),
    "fighters": ("#FF8A1F", "#FFB46B"),
    "settings": ("#E9EDF3", "#E9EDF3"),
    "codes": ("#B04DFF", "#C987FF"),
    "quests": ("#3ED45E", "#8BE89F"),
    "teleport": ("#2ED3FF", "#1F8BFF"),
    "inventory": ("#3D8BFF", "#7DB2FF"),
    "mounts": ("#FF4FB8", "#C2338A"),
    "upgrades": ("#FFB81C", "#FFD36B"),
    "stats": ("#FF4545", "#FF4545"),
    "index": ("#7C5CFF", "#A994FF"),
    "update": ("#34E3A5", "#34E3A5"),
    "yen": ("#FFC21A", "#FFC21A"),
}

# 1. Shop — awning (alternating tones, scalloped edge) over a shop body with a door
m, t = C["shop"]
x0, x1, n = 96, 416, 4
w = (x1 - x0) / n
awning = f"M{x0 + 20} 108 H{x1 - 20} L{x1} 196"
for k in range(n):
    awning += f" A{w / 2:.1f} {w / 2:.1f} 0 0 1 {x1 - (k + 1) * w:.1f} 196"
scallops = f"M{x1 + 8} 196"
for k in range(n):
    scallops += f" A{w / 2:.1f} {w / 2:.1f} 0 0 1 {x1 - (k + 1) * w:.1f} 196"
scallops += f" L{x0 - 8} 196"
awning += " Z"
segs = "".join(shape(poly((x0 + 20 + k * (x1 - x0 - 40) / n, 108), (x0 + 20 + (k + 1) * (x1 - x0 - 40) / n, 108),
                          (x0 + (k + 1) * w, 196), (x0 + k * w, 196)), t, 0) for k in (1, 3))
icon("Icon_Shop", [
    shape(rr(126, 220, 260, 196, 18), m),
    shape(awning, m),
    f'<g clip-path="url(#aw)"><clipPath id="aw"><path d="{awning}"/></clipPath>{segs}</g>',
], cut(rr(218, 300, 76, 140, 26), 0) + cutline(scallops, 16))

# 2. Fighters — fist: four fingers over the palm, thumb across, wrist below
m, t = C["fighters"]
fingers = [(126, 150, 64, 132), (196, 124, 64, 150), (266, 130, 64, 146), (336, 160, 56, 120)]
icon("Icon_Fighters", [
    shape(rr(126, 220, 266, 172, 56), m),
    *[shape(rr(x, y, w_, h, 32), m) for x, y, w_, h in fingers],
    shape(rr(150, 286, 168, 62, 31), t),
    shape(rr(170, 404, 176, 56, 16), t),
], "".join(cutline(f"M{x - 3} {y + 30} V{y + 102}", 12) for x, y, *_ in fingers[1:])
   + cutline("M156 280 H300", 10) + cutline("M120 398 H400", 16))

# 3. Settings — 8-tooth gear with a round hole
m, _ = C["settings"]
pts = []
for k in range(8):
    c = k * math.pi / 4
    for a, r in ((c - 0.25, 150), (c - 0.17, 198), (c + 0.17, 198), (c + 0.25, 150)):
        pts.append((256 + r * math.sin(a), 256 - r * math.cos(a)))
icon("Icon_Settings", [shape(poly(*pts), m), shape(ell(256, 256, 150, 150), m, 0)], cut(ell(256, 256, 64, 64), 0))

# 4. Codes — ticket with side notches, a perforation line and a star cut out
m, t = C["codes"]
ticket = ("M104 150 H408 Q440 150 440 182 V206 A50 50 0 0 0 440 306 V330 Q440 362 408 362 H104 Q72 362 72 330 "
          "V306 A50 50 0 0 0 72 206 V182 Q72 150 104 150 Z")
icon("Icon_Codes", [shape(ticket, m, 2 * R)],
     "".join(cut(rr(176, y, 14, 28, 6), 0) for y in (170, 220, 264, 314)) + cut(star(310, 256, 66), 10))

# 5. Quests — sheet with a folded corner and a check mark cut out
m, t = C["quests"]
sheet = "M156 80 H314 L384 150 V404 Q384 432 356 432 H156 Q128 432 128 404 V108 Q128 80 156 80 Z"
icon("Icon_Quests", [shape(sheet, m), shape("M314 80 V132 Q314 150 332 150 H384 Z", t, 8)],
     cutline("M300 74 V150 H390", 14) + cutline("M188 266 L240 318 L330 210", 40))

# 6. Teleport — portal: thick outer ring, darker inner well with a swirl cut, bright core
m, t = C["teleport"]
CX, CY = 256, 256


def spiral(r0, r1, a0, turns, sy=1.25):
    pts = []
    for i in range(61):
        q = i / 60
        a = a0 + q * turns * 2 * math.pi
        r = r0 + (r1 - r0) * q
        pts.append((CX + r * math.cos(a), CY + r * math.sin(a) * sy))
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts)


icon("Icon_Teleport", [
    shape(ell(CX, CY, 168, 204), m, 0),
    shape(ell(CX, CY, 122, 156), t, 0),
    line(spiral(14, 108, 0.3, 0.7), m, 26),
    line(spiral(14, 108, 0.3 + math.pi, 0.7), m, 26),
    shape(ell(CX, CY, 24, 30), m, 0),
], cutline(ell(CX, CY, 140, 176), 16))

# 7. Inventory — chest: lid (lighter) over the body, a clasp cut out
m, t = C["inventory"]
icon("Icon_Inventory", [
    shape(rr(102, 236, 308, 184, 26), m),
    shape(rr(90, 128, 332, 112, 48), t),
], cutline("M84 240 H428", 16) + cut(rr(226, 206, 60, 80, 20), 0) + cutline("M256 236 V254", 10).replace("#000", "#fff"))

# 8. Mounts — horse head in profile, darker mane, eye + nostril cut out
m, t = C["mounts"]
head = ("M300 118 C232 116 186 156 164 206 C142 256 104 300 90 344 C78 384 98 420 150 424 C186 426 214 410 238 392 "
        "C254 380 266 372 278 368 L290 452 L398 452 C404 360 394 252 362 182 C346 146 330 120 300 118 Z")
mane = ("M286 104 C356 90 420 134 434 210 C446 282 438 376 426 452 L366 452 C384 360 376 254 336 180 "
        "C324 156 306 136 286 128 Z")
ear = "M286 126 L306 58 L344 134 Z"
icon("Icon_Mounts", [shape(mane, t), shape(ear, m), shape(head, m)],
     cut(ell(236, 230, 20, 24), 0) + cut(ell(116, 368, 10, 14), 0) + cutline("M354 452 C366 360 352 258 318 186", 12))

# 9. Upgrades — chevron over a thick up arrow
m, t = C["upgrades"]
icon("Icon_Upgrades", [
    shape("M256 168 L404 308 H318 V444 H194 V308 H108 Z", m),
    line("M148 150 L256 60 L364 150", t, 52),
])

# 10. Stats — three rising bars
m, _ = C["stats"]
icon("Icon_Stats", [
    shape(rr(98, 300, 76, 146, 30), m),
    shape(rr(218, 210, 76, 236, 30), m),
    shape(rr(338, 112, 76, 334, 30), m),
])

# 11. Index — book: cover, lighter spine, label cut out, bookmark ribbon
m, t = C["index"]
icon("Icon_Index", [
    shape(rr(122, 78, 268, 346, 26), m),
    shape(rr(122, 78, 54, 346, 22), t),
    shape("M300 400 H344 V476 L322 456 L300 476 Z", t, 8),
], cutline("M182 70 V432", 12) + cut(rr(222, 146, 116, 52, 18), 0))

# 12. Update Log — bell with a clapper
m, _ = C["update"]
icon("Icon_UpdateLog", [
    shape(ell(256, 70, 22, 22), m, 0),
    shape("M256 90 Q340 90 352 190 L364 316 L412 364 V398 H100 V364 L148 316 L160 190 Q172 90 256 90 Z", m),
    shape(ell(256, 420, 42, 42), m, 0),
], cutline("M84 410 H428", 20))

# 13. Yen — coin with the yen sign cut out
m, _ = C["yen"]
yen_sign = "M186 150 L256 250 L326 150 M256 250 V370 M198 266 H314 M198 318 H314"
icon("Icon_Yen", [shape(ell(256, 256, 178, 178), m, 0)], cutline(yen_sign, 38) + cutline(ell(256, 256, 146, 146), 10))
print("ok")
