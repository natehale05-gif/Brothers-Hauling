#!/usr/bin/env python3
"""Generate every platform's launcher icon from one source image.

    pip install Pillow
    python3 tool/generate_icons.py

Source of truth is assets/branding/app_icon_source.png — the Brothers Hauling
mark on a rounded square. Edit that and re-run; don't hand-edit the outputs.

Each platform wants the artwork framed differently, which is the whole reason
this script exists rather than one resized PNG copied everywhere:

  iOS       full-bleed square, no alpha — iOS rounds the corners itself, and
            the App Store rejects icons with an alpha channel.
  Android   full-bleed square for the legacy launcher, plus an adaptive icon
            whose foreground stays inside the circle the launcher is allowed to
            mask down to, plus a monochrome layer for themed icons.
  macOS     the rounded square inset in a transparent canvas, the way the Dock
            expects — a full-bleed macOS icon looks oversized next to others.
  Windows   a multi-resolution .ico.
  Linux     a single PNG the GTK window loads for the taskbar.
  Web       full-bleed for the favicon and the regular PWA icons; the maskable
            variants keep the artwork inside the safe zone, since the browser
            crops them to whatever shape the platform uses.
"""

import os
import sys

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit('Pillow is required: pip install Pillow')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'assets', 'branding', 'app_icon_source.png')

# The flat colour behind the mark. Also written into the Android adaptive
# icon's background so the two layers meet seamlessly.
BACKGROUND = (17, 17, 18)
BACKGROUND_HEX = '#111112'

# Diameter, as a fraction of the canvas, of the circle the artwork has to stay
# inside where something else masks the icon.
#
# Android composites a 108dp adaptive icon and lets the launcher mask it to
# whatever shape it likes — circle, squircle, teardrop. The guaranteed-visible
# region is the middle 66dp circle.
ADAPTIVE_SAFE = 66 / 108

# A maskable web icon gets cropped by the browser to the platform's shape; the
# documented safe region is the middle 80%.
MASKABLE_SAFE = 0.80

# How much of a macOS canvas the artwork fills, per Apple's icon grid.
MACOS_FILL = 0.82

written = []


def out(path):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    return full


def save(image, path, **kwargs):
    image.save(out(path), optimize=True, **kwargs)
    written.append(path)


def load_source():
    if not os.path.exists(SOURCE):
        sys.exit(f'Missing source artwork: {SOURCE}')
    image = Image.open(SOURCE).convert('RGBA')
    if image.width != image.height:
        sys.exit(f'Source must be square, got {image.size}')
    return image


def flatten(image):
    """The source composited onto its own background, corners filled."""
    flat = Image.new('RGB', image.size, BACKGROUND)
    flat.paste(image, mask=image.split()[-1])
    return flat


def mark_mask(image):
    """Alpha mask covering the mark itself, and nothing else.

    Two conditions, both needed. Colour must differ from the flat background,
    which excludes the field the mark sits on. And the pixel must be fully
    opaque, which excludes the rounded square's own anti-aliased edge — that
    edge is lighter than the background, so a colour test alone treats the
    entire outline as artwork.
    """
    rgb = image.convert('RGB')
    plain = Image.new('RGB', image.size, BACKGROUND)
    differs = ImageChops.difference(rgb, plain).convert('L').point(
        lambda v: 255 if v > 40 else 0
    )
    opaque = image.split()[-1].point(lambda v: 255 if v == 255 else 0)
    return ImageChops.multiply(differs, opaque)


def artwork_bbox(image):
    """Where the mark actually sits, ignoring the field around it."""
    box = mark_mask(image).getbbox()
    if box is None:
        sys.exit('Could not find any artwork in the source image')
    return box


def resize(image, size):
    return image.resize((size, size), Image.LANCZOS)


def square(flat, size):
    """Full-bleed, no alpha."""
    return resize(flat, size)


def paste_centred(canvas, art):
    canvas.paste(
        art,
        ((canvas.width - art.width) // 2, (canvas.height - art.height) // 2),
        art if art.mode == 'RGBA' else None,
    )
    return canvas


def inset(mark, size, fill, background=None):
    """The mark centred on a canvas, covering `fill` of its longest side."""
    canvas = Image.new(
        'RGB' if background else 'RGBA', (size, size),
        background or (0, 0, 0, 0),
    )
    scale = max(1, round(size * fill)) / max(mark.width, mark.height)
    art = mark.resize(
        (max(1, round(mark.width * scale)), max(1, round(mark.height * scale))),
        Image.LANCZOS,
    )
    return paste_centred(canvas, art)


def ink_radius(ink):
    """Distance from centre to the furthest inked pixel, as a fraction of width.

    Fitting a mark's *bounding box* inside a circular mask is too pessimistic —
    the corners of that box are usually empty background. Fitting the ink
    itself is what actually matters, and it buys back a noticeably larger logo.
    Measured on a downsample; a pixel of slack here is invisible.
    """
    probe = ink.resize((256, 256), Image.BILINEAR)
    centre = 127.5
    pixels = probe.load()
    furthest = 0.0
    for y in range(256):
        for x in range(256):
            if pixels[x, y] > 40:
                furthest = max(furthest, ((x - centre) ** 2 + (y - centre) ** 2) ** 0.5)
    return furthest / 256


def fit_in_circle(mark, ink, size, safe_diameter, background=None):
    """The mark scaled so no ink escapes the safe circle, then centred."""
    radius = ink_radius(ink)
    if radius <= 0:
        sys.exit('Could not measure the artwork')
    # `radius` is relative to the mark's own width, so this is the fraction of
    # the canvas the mark may occupy before its ink leaves the safe circle.
    fill = min(1.0, (safe_diameter / 2) / radius)
    return inset(mark, size, fill, background=background)


def silhouette(image, box):
    """White-on-transparent version of the mark, for Android themed icons."""
    white = Image.new('RGBA', image.size, (255, 255, 255, 255))
    white.putalpha(mark_mask(image))
    return white.crop(box)


def main():
    source = load_source()
    flat = flatten(source)
    box = artwork_bbox(source)
    # Cropped from the flattened image: an adaptive foreground is drawn over
    # the background layer, and the two share this colour, so carrying the
    # field along keeps the layers seamless at any mask shape.
    mark = flat.crop(box)
    ink = mark_mask(source).crop(box)
    mono = silhouette(source, box)
    print(
        f'Source {source.size[0]}px, mark {mark.size[0]}x{mark.size[1]}px '
        f'at {box}, ink radius {ink_radius(ink):.3f}'
    )

    # ---- iOS ------------------------------------------------------------
    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for name, size in [
        ('Icon-App-20x20@1x', 20), ('Icon-App-20x20@2x', 40),
        ('Icon-App-20x20@3x', 60), ('Icon-App-29x29@1x', 29),
        ('Icon-App-29x29@2x', 58), ('Icon-App-29x29@3x', 87),
        ('Icon-App-40x40@1x', 40), ('Icon-App-40x40@2x', 80),
        ('Icon-App-40x40@3x', 120), ('Icon-App-60x60@2x', 120),
        ('Icon-App-60x60@3x', 180), ('Icon-App-76x76@1x', 76),
        ('Icon-App-76x76@2x', 152), ('Icon-App-83.5x83.5@2x', 167),
        ('Icon-App-1024x1024@1x', 1024),
    ]:
        save(square(flat, size), f'{ios}/{name}.png')

    # ---- Android --------------------------------------------------------
    densities = [
        ('mdpi', 48, 108), ('hdpi', 72, 162), ('xhdpi', 96, 216),
        ('xxhdpi', 144, 324), ('xxxhdpi', 192, 432),
    ]
    for bucket, legacy, adaptive in densities:
        res = f'android/app/src/main/res/mipmap-{bucket}'
        save(square(flat, legacy), f'{res}/ic_launcher.png')
        # Adaptive layers are 108dp, masked by the launcher to an arbitrary
        # shape — so nothing may stray outside the safe circle.
        save(fit_in_circle(mark, ink, adaptive, ADAPTIVE_SAFE),
             f'{res}/ic_launcher_foreground.png')
        save(fit_in_circle(mono, ink, adaptive, ADAPTIVE_SAFE),
             f'{res}/ic_launcher_monochrome.png')

    # ---- macOS ----------------------------------------------------------
    macos = 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save(inset(source, size, MACOS_FILL), f'{macos}/app_icon_{size}.png')

    # ---- Windows --------------------------------------------------------
    ico_sizes = [(s, s) for s in (16, 24, 32, 48, 64, 128, 256)]
    save(square(flat, 256), 'windows/runner/resources/app_icon.ico',
         format='ICO', sizes=ico_sizes)

    # ---- Linux ----------------------------------------------------------
    save(square(flat, 256), 'linux/runner/resources/app_icon.png')

    # ---- Web ------------------------------------------------------------
    save(square(flat, 32), 'web/favicon.png')
    for size in (192, 512):
        save(square(flat, size), f'web/icons/Icon-{size}.png')
        save(fit_in_circle(mark, ink, size, MASKABLE_SAFE, background=BACKGROUND),
             f'web/icons/Icon-maskable-{size}.png')

    print(f'\nWrote {len(written)} files:')
    for path in written:
        print(f'  {path}')
    print(f'\nAdaptive icon background colour: {BACKGROUND_HEX}')


if __name__ == '__main__':
    main()
