"""The city's signs: one image of 32 sign faces (the rooftop signs and the billboards by the
expressway on cut up's LAKESHORE LOOP, scripts/stage/city_streets.gd), each a 256 x 128 cell
(4 across, 8 down, 1024 x 1024). Generic shop words only (HOTEL, RAMEN, PARKING ...), English and
Japanese, no names of real businesses or brands. The alpha is what glows at night: the lettering
on a dark board, or the whole face of a backlit one; the frame never.

    python3 shotgun-rally/tools/city_signs.py [out.png]

Fonts: the game's Oswald (assets/fonts, OFL; its woff2 unpacked with fontTools) for the Latin
words, IPAGothic (the system's fonts-ipafont) for the Japanese ones (left out if it isn't there).
The same image every run (no dice).
"""
import io, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
OUT = os.path.join(GAME, "assets", "environment_runtime", "city", "signs.png")
CW, CH, COLS, ROWS = 256, 128, 4, 8
JP_FONT = "/usr/share/fonts/truetype/fonts-japanese-gothic.ttf"

# (text, board colour, letter colour, style): "neon" (lit letters on a dark board), "box" (a
# backlit face: all of it glows), "plain" (a painted board: unlit, the street lamps light it)
SIGNS = [
    ("HOTEL", (18, 20, 26), (255, 214, 120), "neon"),
    ("RAMEN", (196, 32, 28), (255, 246, 228), "box"),
    ("ラーメン", (250, 236, 200), (190, 26, 22), "box"),
    ("PARKING", (24, 70, 160), (250, 250, 250), "box"),
    ("駐車場", (24, 70, 160), (250, 250, 250), "box"),
    ("PHARMACY 24H", (20, 120, 70), (245, 255, 245), "box"),
    ("薬局", (245, 245, 240), (20, 130, 70), "box"),
    ("CINEMA", (14, 14, 18), (255, 90, 160), "neon"),
    ("KARAOKE", (60, 10, 70), (120, 230, 255), "neon"),
    ("カラオケ", (250, 220, 40), (30, 30, 30), "box"),
    ("BOWLING", (14, 16, 30), (255, 60, 50), "neon"),
    ("COFFEE", (70, 44, 30), (255, 236, 200), "box"),
    ("NOODLE BAR", (16, 16, 16), (255, 170, 60), "neon"),
    ("SUSHI", (240, 240, 236), (20, 20, 24), "box"),
    ("焼肉", (150, 20, 20), (255, 230, 120), "box"),
    ("居酒屋", (30, 24, 20), (255, 120, 60), "neon"),
    ("LAKESHORE MALL", (230, 232, 236), (30, 60, 120), "box"),
    ("OPEN 24H", (10, 12, 16), (90, 255, 140), "neon"),
    ("DINER", (180, 20, 40), (255, 250, 240), "box"),
    ("BOOKS", (30, 50, 90), (255, 240, 200), "box"),
    ("TYRES & OIL", (250, 200, 30), (20, 20, 20), "plain"),
    ("ARCADE", (20, 10, 40), (255, 240, 60), "neon"),
    ("GYM", (20, 20, 20), (255, 255, 255), "box"),
    ("BAKERY", (245, 230, 205), (130, 70, 30), "box"),
    ("LAUNDRY", (200, 230, 250), (20, 60, 120), "box"),
    ("OFFICES TO LET", (240, 240, 240), (200, 30, 30), "plain"),
    ("TAXI", (250, 200, 20), (20, 20, 20), "box"),
    ("ホテル", (20, 18, 30), (255, 200, 230), "neon"),
    ("MOTEL", (16, 30, 40), (80, 220, 255), "neon"),
    ("CAFE", (40, 60, 50), (240, 250, 230), "box"),
    ("FLOWERS", (250, 240, 245), (200, 40, 110), "plain"),
    ("SHOTGUN RALLY", (12, 12, 12), (255, 120, 30), "neon"),
]


def latin_font(px):
    from fontTools.ttLib import TTFont
    f = TTFont(os.path.join(GAME, "assets", "fonts", "Oswald-Bold.woff2"))
    f.flavor = None
    buf = io.BytesIO()
    f.save(buf)
    buf.seek(0)
    return ImageFont.truetype(buf, px)


def fit(draw, text, make, w, h):
    """The biggest size of the font that fits text in w x h."""
    px = h
    while px > 8:
        f = make(px)
        b = draw.textbbox((0, 0), text, font=f)
        if b[2] - b[0] <= w and b[3] - b[1] <= h:
            return f, b
        px -= 2
    f = make(8)
    return f, draw.textbbox((0, 0), text, font=f)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else OUT
    rgb = Image.new("RGB", (CW * COLS, CH * ROWS), (40, 40, 42))
    glow = Image.new("L", rgb.size, 0)
    dr, dg = ImageDraw.Draw(rgb), ImageDraw.Draw(glow)
    jp = os.path.exists(JP_FONT)
    cache = {}
    for k, (text, board, ink, style) in enumerate(SIGNS):
        x0, y0 = (k % COLS) * CW, (k // COLS) * CH
        is_jp = any(ord(c) > 0x2000 for c in text)
        if is_jp and not jp:
            text, is_jp = "OPEN", False
        frame = 8
        dr.rectangle([x0, y0, x0 + CW - 1, y0 + CH - 1], fill=(48, 50, 54))                       # the frame (never lit)
        dr.rectangle([x0 + frame, y0 + frame, x0 + CW - 1 - frame, y0 + CH - 1 - frame], fill=board)
        if style == "box":
            dg.rectangle([x0 + frame, y0 + frame, x0 + CW - 1 - frame, y0 + CH - 1 - frame], fill=150)
        make = (lambda px: ImageFont.truetype(JP_FONT, px)) if is_jp else latin_font
        key = (text, is_jp)
        f, b = fit(dr, text, lambda px: cache.setdefault((is_jp, px), make(px)), CW - 2 * frame - 24, CH - 2 * frame - 26)
        tx = x0 + (CW - (b[2] - b[0])) // 2 - b[0]
        ty = y0 + (CH - (b[3] - b[1])) // 2 - b[1]
        if style == "neon":                                                                         # (a soft halo round the tubes)
            for r in (3, 2):
                for dx in (-r, 0, r):
                    for dy in (-r, 0, r):
                        dr.text((tx + dx, ty + dy), text, font=f, fill=tuple(int(c * 0.35 + b2 * 0.65) for c, b2 in zip(ink, board)))
        dr.text((tx, ty), text, font=f, fill=ink)
        if style != "plain":
            dg.text((tx, ty), text, font=f, fill=255)
    img = rgb.convert("RGBA")
    img.putalpha(glow)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    print("%d signs -> %s" % (len(SIGNS), out))


if __name__ == "__main__":
    main()
