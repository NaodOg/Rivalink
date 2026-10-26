"""Generate every app-icon / splash asset from the brand PNGs.

Sources:
    brand/rivalink-pin.png       split-blue trophy pin (app icon + splash mark)
    brand/rivalink-wordmark.png  RIVALINK wordmark + tagline (splash lockup)

Usage (from the repo root):
    backend\\venv\\Scripts\\python.exe brand\\render_app_assets.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIN_SRC = os.path.join(ROOT, 'brand', 'rivalink-pin.png')
WORDMARK_SRC = os.path.join(ROOT, 'brand', 'rivalink-wordmark.png')
APP = os.path.join(ROOT, 'lets_play_app')

WHITE = (255, 255, 255, 255)


def load_content(path):
    master = Image.open(path).convert('RGBA')
    bbox = master.getchannel('A').getbbox()
    return master.crop(bbox)


CONTENT = load_content(PIN_SRC)
WORDMARK = load_content(WORDMARK_SRC)


def pin(size, height_scale=1.0):
    """Pin artwork centered on a transparent square canvas.

    height_scale is the share of the canvas height the artwork occupies
    (0.62 = adaptive-icon safe zone, 1.0 = edge to edge).
    """
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    h = max(1, round(size * height_scale))
    w = max(1, round(CONTENT.width * h / CONTENT.height))
    art = CONTENT.resize((w, h), Image.LANCZOS)
    canvas.alpha_composite(art, ((size - w) // 2, (size - h) // 2))
    return canvas


def lockup(scale):
    """Pin with the wordmark + tagline directly underneath, centered.

    Design space: 320 x 300dp. The Flutter splash uses the same composition,
    so the native hand-off is seamless.
    """
    width, height = round(320 * scale), round(300 * scale)
    pin_h = round(150 * scale)
    pin_w = round(CONTENT.width * pin_h / CONTENT.height)
    word_w = round(300 * scale)
    word_h = round(WORDMARK.height * word_w / WORDMARK.width)
    gap = round(12 * scale)

    total = pin_h + gap + word_h
    top = (height - total) // 2

    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    img.alpha_composite(CONTENT.resize((pin_w, pin_h), Image.LANCZOS),
                        ((width - pin_w) // 2, top))
    img.alpha_composite(WORDMARK.resize((word_w, word_h), Image.LANCZOS),
                        ((width - word_w) // 2, top + pin_h + gap))
    return img


def flattened(img, bg=WHITE):
    out = Image.new('RGBA', img.size, bg)
    out.alpha_composite(img)
    return out.convert('RGB')


def silhouette(img):
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste((0, 0, 0, 255), (0, 0), img.getchannel('A'))
    return out


def save(img, *parts):
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print('wrote', os.path.relpath(path, ROOT))


BUCKETS = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0}

# ── Android ──────────────────────────────────────────────────────────────
RES = os.path.join(APP, 'android', 'app', 'src', 'main', 'res')
for bucket, scale in BUCKETS.items():
    dp = round(48 * scale)
    save(pin(dp, 0.985), RES, f'mipmap-{bucket}', 'ic_launcher.png')
    save(pin(dp, 0.86), RES, f'mipmap-{bucket}', 'ic_launcher_round.png')

save(pin(432, 0.62), RES, 'drawable', 'ic_launcher_foreground.png')
save(silhouette(pin(432, 0.62)), RES, 'drawable', 'ic_launcher_monochrome.png')

for bucket, scale in BUCKETS.items():
    save(lockup(scale), RES, f'drawable-{bucket}', 'splash_logo.png')
save(lockup(1.0), RES, 'drawable', 'splash_logo.png')

# ── iOS ──────────────────────────────────────────────────────────────────
IOS_ICONS = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167, 'Icon-App-1024x1024@1x.png': 1024,
}
IOS_ICON_DIR = os.path.join(APP, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
for name, size in IOS_ICONS.items():
    save(flattened(pin(size, 0.985)), IOS_ICON_DIR, name)

IOS_LAUNCH_DIR = os.path.join(APP, 'ios', 'Runner', 'Assets.xcassets', 'LaunchImage.imageset')
launch_base = lockup(1.0).resize((168, 158), Image.LANCZOS)
for name, scale in {'LaunchImage.png': 1.0, 'LaunchImage@2x.png': 2.0, 'LaunchImage@3x.png': 3.0}.items():
    size = (round(168 * scale), round(158 * scale))
    save(launch_base.resize(size, Image.LANCZOS), IOS_LAUNCH_DIR, name)

# ── Web ──────────────────────────────────────────────────────────────────
WEB = os.path.join(APP, 'web')
save(pin(64, 1.0), WEB, 'favicon.png')
save(pin(192, 1.0), WEB, 'icons', 'Icon-192.png')
save(pin(512, 1.0), WEB, 'icons', 'Icon-512.png')
save(flattened(pin(192, 0.66)), WEB, 'icons', 'Icon-maskable-192.png')
save(flattened(pin(512, 0.66)), WEB, 'icons', 'Icon-maskable-512.png')

# ── Flutter in-app splash assets ─────────────────────────────────────────
def scaled_content(content, height):
    width = round(content.width * height / content.height)
    return content.resize((width, height), Image.LANCZOS)


save(scaled_content(CONTENT, 1200), APP, 'assets', 'images', 'rivalink_pin.png')
save(scaled_content(WORDMARK, 300), APP, 'assets', 'images', 'rivalink_wordmark.png')

print('done')
