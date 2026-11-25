#!/usr/bin/env python3
"""Generates every Nova Chat icon and launch asset from one set of shapes.

The artwork is a chat bubble under a four-point nova, on a night-sky
gradient with a faint constellation (the mesh). This script is the source of
truth; do not edit its outputs by hand or re-save them in Icon Composer.

Outputs:
  bitchat/Icons/AppIcon.icon, AppIconDebug.icon
      Layered Liquid Glass icons (icon.json + SVG layers) for iOS 26+ and
      macOS 26+. Xcode pairs each with the asset-catalog icon of the same name.
  bitchat/Assets.xcassets/AppIcon.appiconset, AppIconDebug.appiconset
      Flat PNGs of the same artwork for anything that reads the catalog.
      Xcode 27 renders the iOS 16-25 and .icns fallbacks from the .icon file
      of the same name and skips these. The Mac sizes go through
      scripts/generate-mac-appicon.swift, which applies the macOS icon grid.
  bitchat/Assets.xcassets/LaunchMark.imageset, LaunchBackground.colorset
      The launch screen mark and color, also used by the in-app hand-off.

Usage: python3 scripts/generate-app-icon.py [--preview DIR]
Needs rsvg-convert (brew install librsvg). --preview also needs Icon
Composer's ictool and ImageMagick.
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS_DIR = os.path.join(ROOT, "bitchat", "Icons")
ASSETS_DIR = os.path.join(ROOT, "bitchat", "Assets.xcassets")
MAC_SCRIPT = os.path.join(ROOT, "scripts", "generate-mac-appicon.swift")
ICTOOL = "/Applications/Icon Composer.app/Contents/Executables/ictool"

# MARK: - Geometry (1024 x 1024 icon canvas)

STAR = (722, 300, 190)  # center x, center y, tip radius
STAR_WAIST = 0.10  # concave waist, as a fraction of the tip radius
BUBBLE = (152, 420, 736, 818, 186)  # x0, y0, x1, y1, corner radius
TAIL_TIP = (-0.14, 0.40)  # from the bottom-left corner, in corner radii
NODES = [(160, 236, 7), (262, 164, 5.5), (368, 232, 6.5)]  # constellation
DUST = [(540, 148, 4.5), (112, 500, 4), (888, 660, 5), (850, 884, 4),
        (896, 128, 3.5), (160, 900, 3.5), (470, 920, 3)]

# Launch mark: the bubble and nova, cropped from the canvas.
MARK_POINTS = 128  # rendered size in points
MARK_MARGIN = 16  # canvas units around the artwork


class Palette:
    def __init__(self, sky_top, sky_bottom, nebula, bubble_shade, sky_top_dark, sky_bottom_dark):
        self.sky_top = sky_top
        self.sky_bottom = sky_bottom
        self.nebula = nebula
        self.bubble_shade = bubble_shade  # bottom of the flat bubble gradient
        self.sky_top_dark = sky_top_dark
        self.sky_bottom_dark = sky_bottom_dark


RELEASE = Palette("#0E0B34", "#6639E0", "#C58BFF", "#ECE6FF", "#07061A", "#2A1873")
# Debug builds: the same artwork at sunset, so a Debug install is obvious.
DEBUG = Palette("#4A0F45", "#FF7B2E", "#FF9E7A", "#FFE9DE", "#1E0619", "#7A2A10")

STAR_CORE = "#FFFFFF"
STAR_EDGE = "#FFE7AE"
GLOW = "#FFE3A3"

# Launch mark colors on the launch background: bubble top and bottom, nova
# core and edge, and whether the nova glows.
MARK_LIGHT = ("#7448EC", "#4E2CC9", "#7448EC", "#7448EC", False)
MARK_DARK = ("#FFFFFF", "#E4DCFF", STAR_CORE, STAR_EDGE, True)
# Middle of ThemedRootBackground, so the hand-off fades into the app smoothly.
LAUNCH_BACKGROUND_LIGHT = (0.949, 0.957, 0.996)
LAUNCH_BACKGROUND_DARK = (0.067, 0.075, 0.118)


def num(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


# MARK: - Shapes


def star_path(cx, cy, radius, waist, rotation=0.0):
    tips = []
    for i in range(4):
        a = math.radians(rotation + i * 90 - 90)
        tips.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    d = [f"M{num(tips[0][0])},{num(tips[0][1])}"]
    for i in range(4):
        a = math.radians(rotation + i * 90 - 45)
        w = (cx + waist * radius * math.cos(a), cy + waist * radius * math.sin(a))
        t = tips[(i + 1) % 4]
        d.append(f"Q{num(w[0])},{num(w[1])} {num(t[0])},{num(t[1])}")
    return " ".join(d) + " Z"


def bubble_path():
    """Rounded rectangle with a tail that flows out of the bottom-left corner."""
    x0, y0, x1, y1, r = BUBBLE
    c = r * (1 - 0.5523)  # quarter-circle Bezier handle
    tip_x, tip_y = x0 + TAIL_TIP[0] * r, y1 + TAIL_TIP[1] * r
    return " ".join([
        f"M{num(x0 + r)},{num(y0)}",
        f"H{num(x1 - r)}",
        f"C{num(x1 - c)},{num(y0)} {num(x1)},{num(y0 + c)} {num(x1)},{num(y0 + r)}",
        f"V{num(y1 - r)}",
        f"C{num(x1)},{num(y1 - c)} {num(x1 - c)},{num(y1)} {num(x1 - r)},{num(y1)}",
        f"H{num(x0 + 0.95 * r)}",
        f"C{num(x0 + 0.48 * r)},{num(y1)} {num(x0 + 0.20 * r)},{num(y1 + 0.20 * r)} {num(tip_x)},{num(tip_y)}",
        f"C{num(x0 - 0.02 * r)},{num(y1 + 0.12 * r)} {num(x0)},{num(y1 - 0.18 * r)} {num(x0)},{num(y1 - 0.62 * r)}",
        f"V{num(y0 + r)}",
        f"C{num(x0)},{num(y0 + c)} {num(x0 + c)},{num(y0)} {num(x0 + r)},{num(y0)}",
        "Z",
    ])


# MARK: - SVG fragments


def svg_document(defs, body, size=1024, view_box="0 0 1024 1024"):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="{view_box}">'
            f'<defs>{"".join(defs)}</defs>{"".join(body)}</svg>\n')


def sky_fragment(palette, prefix=""):
    """Nebula glow, constellation and dust. No background fill."""
    sx, sy, _ = STAR
    defs = [f'<radialGradient id="{prefix}nebula" cx="{sx}" cy="{sy}" r="520" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{palette.nebula}" stop-opacity="0.5"/>'
            f'<stop offset="1" stop-color="{palette.nebula}" stop-opacity="0"/></radialGradient>']
    body = ['<rect width="1024" height="1024" fill="url(#%snebula)"/>' % prefix]
    links = [NODES[0][:2], NODES[1][:2], NODES[2][:2], (sx, sy)]
    points = " ".join(f"{x},{y}" for x, y in links)
    body.append(f'<polyline points="{points}" fill="none" stroke="#FFFFFF" stroke-opacity="0.26" '
                f'stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>')
    for x, y, r in NODES:
        body.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#FFFFFF" fill-opacity="0.8"/>')
    for x, y, r in DUST:
        body.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#FFFFFF" fill-opacity="0.45"/>')
    return defs, body


def glow_fragment(prefix=""):
    sx, sy, radius = STAR
    r = radius * 0.95
    defs = [f'<radialGradient id="{prefix}glow" cx="{sx}" cy="{sy}" r="{num(r)}" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/>'
            f'<stop offset="0.22" stop-color="{GLOW}" stop-opacity="0.5"/>'
            f'<stop offset="0.55" stop-color="{GLOW}" stop-opacity="0.16"/>'
            f'<stop offset="1" stop-color="{GLOW}" stop-opacity="0"/></radialGradient>']
    body = [f'<circle cx="{sx}" cy="{sy}" r="{num(r)}" fill="url(#{prefix}glow)"/>']
    return defs, body


def nova_fragment(core, edge, prefix=""):
    sx, sy, radius = STAR
    defs = [f'<radialGradient id="{prefix}nova" cx="{sx}" cy="{sy}" r="{radius}" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0.15" stop-color="{core}"/><stop offset="1" stop-color="{edge}"/></radialGradient>']
    body = [f'<path d="{star_path(sx, sy, radius, STAR_WAIST)}" fill="url(#{prefix}nova)"/>']
    return defs, body


def bubble_fragment(top, bottom, shadow=False, prefix=""):
    _, y0, _, y1, _ = BUBBLE
    defs = [f'<linearGradient id="{prefix}bubble" x1="0" y1="{y0}" x2="0" y2="{y1}" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>']
    attrs = ""
    if shadow:
        defs.append(f'<filter id="{prefix}shadow" x="-20%" y="-20%" width="140%" height="150%">'
                    '<feGaussianBlur in="SourceAlpha" stdDeviation="18"/><feOffset dy="14"/>'
                    '<feComponentTransfer><feFuncA type="linear" slope="0.28"/></feComponentTransfer>'
                    '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
        attrs = f' filter="url(#{prefix}shadow)"'
    body = [f'<path d="{bubble_path()}" fill="url(#{prefix}bubble)"{attrs}/>']
    return defs, body


def background_fragment(top, bottom):
    defs = [f'<linearGradient id="sky" x1="0.15" y1="0" x2="0.55" y2="1">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>']
    return defs, ['<rect width="1024" height="1024" fill="url(#sky)"/>']


def combine(*fragments):
    defs, body = [], []
    for d, b in fragments:
        defs += d
        body += b
    return defs, body


# MARK: - Outputs


def flat_icon_svg(palette):
    """Full-bleed square artwork for the catalog PNGs."""
    return svg_document(*combine(
        background_fragment(palette.sky_top, palette.sky_bottom),
        sky_fragment(palette),
        bubble_fragment("#FFFFFF", palette.bubble_shade, shadow=True),
        glow_fragment(),
        nova_fragment(STAR_CORE, STAR_EDGE),
    ))


def color_component(hex_color):
    return [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]


def icon_color(hex_color):
    r, g, b = color_component(hex_color)
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def write_icon_document(name, palette):
    """Writes a layered Icon Composer document."""
    path = os.path.join(ICONS_DIR, f"{name}.icon")
    if os.path.isdir(path):
        shutil.rmtree(path)
    assets = os.path.join(path, "Assets")
    os.makedirs(assets)
    layers = {
        "nova.svg": svg_document(*nova_fragment(STAR_CORE, STAR_EDGE)),
        "bubble.svg": svg_document(*bubble_fragment("#FFFFFF", "#FFFFFF")),
        "glow.svg": svg_document(*glow_fragment()),
        "sky.svg": svg_document(*sky_fragment(palette)),
    }
    for filename, svg in layers.items():
        with open(os.path.join(assets, filename), "w") as f:
            f.write(svg)

    def fill(top, bottom):
        return {
            "linear-gradient": [icon_color(top), icon_color(bottom)],
            "orientation": {"start": {"x": 0.35, "y": 0}, "stop": {"x": 0.6, "y": 1}},
        }

    document = {
        "fill-specializations": [
            {"value": fill(palette.sky_top, palette.sky_bottom)},
            {"appearance": "dark", "value": fill(palette.sky_top_dark, palette.sky_bottom_dark)},
        ],
        "groups": [
            # The nova is a light source, so it glows instead of being glass:
            # glass gives it a dark refraction rim.
            {
                "layers": [
                    {"glass": False, "image-name": "nova.svg", "name": "nova"},
                    {"glass": False, "image-name": "glow.svg", "name": "glow"},
                ],
                "shadow": {"kind": "neutral", "opacity": 0},
                "translucency": {"enabled": False, "value": 0},
            },
            {
                "layers": [{"glass": True, "image-name": "bubble.svg", "name": "bubble"}],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "specular": True,
                "translucency": {"enabled": True, "value": 0.2},
            },
            {
                "layers": [{"glass": False, "image-name": "sky.svg", "name": "sky"}],
                "shadow": {"kind": "neutral", "opacity": 0},
                "translucency": {"enabled": False, "value": 0},
            },
        ],
        "supported-platforms": {"squares": "shared"},
    }
    with open(os.path.join(path, "icon.json"), "w") as f:
        json.dump(document, f, indent=2)
        f.write("\n")


def rsvg(svg_text, out_path, width, height=None):
    """Renders SVG text to a PNG."""
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg_text)
        src = f.name
    try:
        args = ["rsvg-convert", "-w", str(width), "-h", str(height or width), src, "-o", out_path]
        subprocess.run(args, check=True)
    finally:
        os.unlink(src)


def write_icon_set(name, palette, prefix):
    """Writes the flat PNG fallbacks and Contents.json for one app icon set."""
    path = os.path.join(ASSETS_DIR, f"{name}.appiconset")
    if os.path.isdir(path):
        shutil.rmtree(path)
    os.makedirs(path)

    images = []
    rsvg(flat_icon_svg(palette), os.path.join(path, f"{prefix}_1024x1024.png"), 1024)
    images.append({"filename": f"{prefix}_1024x1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"})

    subprocess.run(["swift", MAC_SCRIPT, os.path.join(path, f"{prefix}_1024x1024.png"), path, prefix],
                   check=True, stdout=subprocess.DEVNULL)
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = "" if scale == 1 else f"@{scale}x"
            images.append({"filename": f"{prefix}_{points}x{points}{suffix}.png", "idiom": "mac",
                           "scale": f"{scale}x", "size": f"{points}x{points}"})

    with open(os.path.join(path, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


def mark_crop():
    """A square around the bubble and nova, centered on their bounds."""
    x0, y0, x1, y1, r = BUBBLE
    sx, sy, radius = STAR
    left, right = x0 + TAIL_TIP[0] * r, max(x1, sx + radius)
    top, bottom = min(y0, sy - radius), y1 + TAIL_TIP[1] * r
    side = max(right - left, bottom - top) + 2 * MARK_MARGIN
    return (left + right - side) / 2, (top + bottom - side) / 2, side


def mark_svg(colors):
    """The bubble and nova on a transparent canvas."""
    bubble_top, bubble_bottom, core, edge, glows = colors
    fragments = [bubble_fragment(bubble_top, bubble_bottom)]
    if glows:
        fragments.append(glow_fragment())
    fragments.append(nova_fragment(core, edge))
    x, y, side = mark_crop()
    return svg_document(*combine(*fragments), size=MARK_POINTS, view_box=f"{num(x)} {num(y)} {num(side)} {num(side)}")


def write_launch_assets():
    mark = os.path.join(ASSETS_DIR, "LaunchMark.imageset")
    if os.path.isdir(mark):
        shutil.rmtree(mark)
    os.makedirs(mark)
    # PNGs, not a PDF: Core Graphics drops the alpha of the glow's gradient
    # in rsvg's PDF output and draws it as an opaque disc.
    images = []
    for colors, suffix, appearance in ((MARK_LIGHT, "", None), (MARK_DARK, "-dark", "dark")):
        for scale in (1, 2, 3):
            filename = f"LaunchMark{suffix}@{scale}x.png"
            rsvg(mark_svg(colors), os.path.join(mark, filename), MARK_POINTS * scale)
            image = {"filename": filename, "idiom": "universal", "scale": f"{scale}x"}
            if appearance:
                image = {"appearances": [{"appearance": "luminosity", "value": appearance}], **image}
            images.append(image)
    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(mark, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")

    color = os.path.join(ASSETS_DIR, "LaunchBackground.colorset")
    os.makedirs(color, exist_ok=True)

    def entry(rgb, dark):
        item = {"color": {"color-space": "srgb", "components": {
            "alpha": "1.000", "red": f"{rgb[0]:.3f}", "green": f"{rgb[1]:.3f}", "blue": f"{rgb[2]:.3f}"}},
            "idiom": "universal"}
        if dark:
            item = {"appearances": [{"appearance": "luminosity", "value": "dark"}], **item}
        return item

    with open(os.path.join(color, "Contents.json"), "w") as f:
        json.dump({"colors": [entry(LAUNCH_BACKGROUND_LIGHT, False), entry(LAUNCH_BACKGROUND_DARK, True)],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


# MARK: - Previews


def write_previews(out):
    os.makedirs(out, exist_ok=True)
    convert = shutil.which("convert") or "/opt/homebrew/bin/convert"

    def ictool(name, platform, rendition, size, dest):
        subprocess.run([ICTOOL, os.path.join(ICONS_DIR, f"{name}.icon"), "--export-image", "--output-file", dest,
                        "--platform", platform, "--rendition", rendition, "--width", str(size),
                        "--height", str(size), "--scale", "1"], check=True, stdout=subprocess.DEVNULL)

    ictool("AppIcon", "iOS", "Default", 1024, os.path.join(out, "icon-1024-glass.png"))
    ictool("AppIcon", "iOS", "Dark", 1024, os.path.join(out, "icon-1024-glass-dark.png"))
    ictool("AppIcon", "iOS", "ClearLight", 1024, os.path.join(out, "icon-1024-glass-clear.png"))
    ictool("AppIcon", "iOS", "TintedDark", 1024, os.path.join(out, "icon-1024-glass-tinted.png"))
    ictool("AppIconDebug", "iOS", "Default", 1024, os.path.join(out, "debug-icon-1024-glass.png"))
    for size in (180, 60, 29):
        ictool("AppIcon", "iOS", "Default", size, os.path.join(out, f"icon-{size}-glass.png"))
    icon_set = os.path.join(ASSETS_DIR, "AppIcon.appiconset")
    debug_set = os.path.join(ASSETS_DIR, "AppIconDebug.appiconset")
    shutil.copy(os.path.join(icon_set, "icon_1024x1024.png"), os.path.join(out, "icon-1024-fallback.png"))
    shutil.copy(os.path.join(debug_set, "icon_1024x1024.png"), os.path.join(out, "debug-icon-1024-fallback.png"))
    for size in (180, 60, 29):
        subprocess.run([convert, os.path.join(icon_set, "icon_1024x1024.png"), "-resize", f"{size}x{size}",
                        os.path.join(out, f"icon-{size}-fallback.png")], check=True)
    shutil.copy(os.path.join(icon_set, "icon_512x512.png"), os.path.join(out, "mac-icon-512.png"))
    shutil.copy(os.path.join(icon_set, "icon_32x32.png"), os.path.join(out, "mac-icon-32.png"))
    shutil.copy(os.path.join(debug_set, "icon_512x512.png"), os.path.join(out, "debug-mac-icon-512.png"))
    for dark in (False, True):
        name = "launch-dark.png" if dark else "launch-light.png"
        rsvg(launch_mock_svg(dark), os.path.join(out, name), 393 * 2, 852 * 2)


def launch_mock_svg(dark):
    """An iPhone-sized (393 x 852 pt) mock of the launch screen."""
    width, height = 393, 852
    rgb = LAUNCH_BACKGROUND_DARK if dark else LAUNCH_BACKGROUND_LIGHT
    background = "#" + "".join(f"{round(c * 255):02X}" for c in rgb)
    mark = mark_svg(MARK_DARK if dark else MARK_LIGHT)
    x, y = (width - MARK_POINTS) / 2, (height - MARK_POINTS) / 2
    mark = mark.replace("<svg ", f'<svg x="{num(x)}" y="{num(y)}" ', 1)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
            f'<rect width="{width}" height="{height}" rx="55" fill="{background}"/>'
            f'<rect x="{(width - 126) / 2}" y="11" width="126" height="37" rx="18.5" fill="#000"/>'
            f'{mark}</svg>')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", metavar="DIR", help="also render preview images into DIR")
    args = parser.parse_args()
    if not shutil.which("rsvg-convert"):
        sys.exit("error: rsvg-convert not found (brew install librsvg)")

    os.makedirs(ICONS_DIR, exist_ok=True)
    write_icon_document("AppIcon", RELEASE)
    write_icon_document("AppIconDebug", DEBUG)
    write_icon_set("AppIcon", RELEASE, "icon")
    write_icon_set("AppIconDebug", DEBUG, "icon")
    write_launch_assets()
    if args.preview:
        write_previews(args.preview)
    print("done")


if __name__ == "__main__":
    main()
