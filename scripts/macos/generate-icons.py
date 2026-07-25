#!/usr/bin/env python3
"""Regenerate Agent Canvas AppIcon + MenuBarIcon to match the concept logo.

Concept geometry (measured from original 1024 art on light gray):
  outer black ring ~6.3%, white gap ~6.2%, mid black ~6.3%, white gap ~7.2%,
  solid black center ~47%, corner radius ~24% of body side, soft drop shadow.

Menu bar template uses the same silhouette with optically wider gaps so the
concentric frames still read at ~18pt.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "platforms/macos/AgentCanvas/Assets.xcassets"
APPICON = ASSETS / "AppIcon.appiconset"
MENUBAR = ASSETS / "MenuBarIcon.imageset"

# Fractions of the logo body width (outside → in), from concept art
OUTER_STROKE = 0.063
GAP1 = 0.062
MID_STROKE = 0.063
GAP2 = 0.072
CORNER_FRAC = 0.24  # of body side


def paste_round(base: Image.Image, color, box, radius: float) -> None:
    """Fill a rounded-rect region with an RGBA/RGB color."""
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    w, h = x1 - x0, y1 - y0
    if w <= 0 or h <= 0:
        return
    r = max(0.0, min(radius, w / 2.0, h / 2.0))
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    fill = (*color, 255) if len(color) == 3 else color
    draw.rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=r, fill=fill)
    base.alpha_composite(layer)


def cut_round(target: Image.Image, box, radius: float) -> None:
    """Erase a rounded-rect region (set alpha to 0)."""
    x0, y0, x1, y1 = (int(round(v)) for v in box)
    w, h = max(0, x1 - x0), max(0, y1 - y0)
    if w == 0 or h == 0:
        return
    r = max(0.0, min(radius, w / 2.0, h / 2.0))
    mask = Image.new("L", target.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (x0, y0, x1 - 1, y1 - 1), radius=r, fill=255
    )
    clear = Image.new("RGBA", target.size, (0, 0, 0, 0))
    target.paste(clear, (0, 0), mask)


def draw_logo_layers(
    canvas: int,
    *,
    body_frac: float = 0.78,
    black=(12, 12, 12),
    white=(245, 245, 245),
    shadow: bool = True,
    bg=None,
) -> Image.Image:
    """Full-color logo: black frames, white gaps, solid black center + soft shadow."""
    if bg is None:
        img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    else:
        img = Image.new(
            "RGBA",
            (canvas, canvas),
            (*bg, 255) if len(bg) == 3 else bg,
        )

    body = canvas * body_frac
    ox = (canvas - body) / 2.0
    oy = (canvas - body) / 2.0
    if shadow:
        oy -= canvas * 0.012

    def box_at(inset: float):
        return (ox + inset, oy + inset, ox + body - inset, oy + body - inset)

    def rad_at(inset: float):
        # Relative radius of *this* shape's side — concept keeps the center
        # as rounded as the outer frame (shared offset radius would go to 0).
        side = max(0.0, body - 2.0 * inset)
        return side * CORNER_FRAC

    if shadow:
        shadow_img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        paste_round(shadow_img, (0, 0, 0, 60), box_at(0), rad_at(0))
        shadow_img = shadow_img.filter(
            ImageFilter.GaussianBlur(radius=max(1.0, canvas * 0.04))
        )
        shifted = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        off = int(canvas * 0.02)
        shifted.paste(shadow_img, (off, off), shadow_img)
        img.alpha_composite(shifted)

        # Layered depth between frames (concept has soft inter-ring shadow)
        for inset_frac, alpha, blur in (
            (OUTER_STROKE + GAP1 * 0.15, 36, 0.014),
            (OUTER_STROKE + GAP1 + MID_STROKE + GAP2 * 0.15, 30, 0.012),
        ):
            s = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
            inset = body * inset_frac
            paste_round(s, (0, 0, 0, alpha), box_at(inset), rad_at(inset))
            s = s.filter(ImageFilter.GaussianBlur(radius=max(1.0, canvas * blur)))
            ss = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
            ss.paste(s, (int(canvas * 0.005), int(canvas * 0.008)), s)
            img.alpha_composite(ss)

    # Outer black solid body
    paste_round(img, black, box_at(0), rad_at(0))
    # White gap 1
    paste_round(img, white, box_at(body * OUTER_STROKE), rad_at(body * OUTER_STROKE))
    # Mid black
    i2 = body * (OUTER_STROKE + GAP1)
    paste_round(img, black, box_at(i2), rad_at(i2))
    # White gap 2
    i3 = body * (OUTER_STROKE + GAP1 + MID_STROKE)
    paste_round(img, white, box_at(i3), rad_at(i3))
    # Solid black center
    i4 = body * (OUTER_STROKE + GAP1 + MID_STROKE + GAP2)
    paste_round(img, black, box_at(i4), rad_at(i4))
    return img


def draw_template(
    size: int,
    *,
    pad_frac: float = 0.08,
    outer_stroke: float = 0.090,
    gap1: float = 0.100,
    mid_stroke: float = 0.085,
    gap2: float = 0.100,
    corner_frac: float = 0.24,
) -> Image.Image:
    """Black-on-clear template for MenuBarExtra (template rendering intent).

    Gaps are slightly wider than the full-color concept so concentric frames
    remain visible when drawn at ~18pt in the menu bar.
    """
    ss = 4
    s = size * ss
    hi = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    pad = s * pad_frac
    body = s - 2 * pad
    ox = pad
    oy = pad

    def box_at(inset: float):
        return (ox + inset, oy + inset, ox + body - inset, oy + body - inset)

    def rad_at(inset: float):
        side = max(0.0, body - 2.0 * inset)
        return side * corner_frac

    black = (0, 0, 0, 255)

    paste_round(hi, black, box_at(0), rad_at(0))
    i1 = body * outer_stroke
    cut_round(hi, box_at(i1), rad_at(i1))

    i2 = body * (outer_stroke + gap1)
    paste_round(hi, black, box_at(i2), rad_at(i2))

    i3 = body * (outer_stroke + gap1 + mid_stroke)
    cut_round(hi, box_at(i3), rad_at(i3))

    i4 = body * (outer_stroke + gap1 + mid_stroke + gap2)
    paste_round(hi, black, box_at(i4), rad_at(i4))

    out = hi.resize((size, size), Image.Resampling.LANCZOS)
    px = out.load()
    for y in range(size):
        for x in range(size):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (0, 0, 0, a)
    return out


def save_appicon() -> None:
    APPICON.mkdir(parents=True, exist_ok=True)
    draw_logo_layers(1024, body_frac=0.78, shadow=True, bg=(236, 236, 236)).save(
        APPICON / "preview-concept-match.png"
    )
    draw_logo_layers(1024, body_frac=0.82, shadow=True, bg=None).save(
        APPICON / "AppIcon-1024.png"
    )
    draw_logo_layers(512, body_frac=0.80, shadow=True, bg=(236, 236, 236)).save(
        APPICON / "preview-512.png"
    )

    # name, pixel size
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16" + "@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32" + "@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128" + "@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256" + "@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512" + "@2x.png", 1024),
    ]
    for name, px in sizes:
        if px <= 32:
            im = draw_logo_layers(px * 4, body_frac=0.88, shadow=False, bg=None)
            im = im.resize((px, px), Image.Resampling.LANCZOS)
        elif px <= 128:
            im = draw_logo_layers(px * 2, body_frac=0.84, shadow=True, bg=None)
            im = im.resize((px, px), Image.Resampling.LANCZOS)
        else:
            im = draw_logo_layers(px, body_frac=0.82, shadow=True, bg=None)
        im.save(APPICON / name)
        print(f"  appicon {name} {px}x{px}")


def save_menubar() -> None:
    MENUBAR.mkdir(parents=True, exist_ok=True)
    variants = [
        ("MenuBarIcon.png", 22),
        ("MenuBarIcon" + "@2x.png", 44),
        ("MenuBarIcon" + "@3x.png", 66),
    ]
    for name, px in variants:
        im = draw_template(px)
        im.save(MENUBAR / name)
        data = list(im.getdata())
        opaque = sum(1 for p in data if p[3] > 20)
        print(f"  menubar {name} {px}x{px} opaque%={100 * opaque / len(data):.1f}")


def main() -> None:
    print("Generating AppIcon…")
    save_appicon()
    print("Generating MenuBarIcon…")
    save_menubar()
    print("Done.")


if __name__ == "__main__":
    main()
