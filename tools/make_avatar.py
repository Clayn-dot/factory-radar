"""Redraws the Factory Radar avatar title in Bruk Sans Bold: the old white title is cut out of the finished picture
(release/final/radar-button-*-v3.png), the blurred window behind it is filled in, the new title goes on top.
The button stays as it is. Writes release/final/radar-button-{288,512}-v4.png and src/factory-radar/thumbnail.png.
The font is built in the quality-calculator project (tools/font/make_font.py).
Run: python -X utf8 tools/make_avatar.py"""
import pathlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from scipy.ndimage import gaussian_filter, binary_dilation

ROOT = pathlib.Path(__file__).resolve().parent.parent
FINAL = ROOT / "release" / "final"
FONT = "C:/dev/quality-calculator/fonts/BrukSans-Bold.ttf"
LINES = (("FACTORY", 230, 42), ("RADAR", 150, 92))  # text, ink width and center y at 288 px


def ink_box(text, f):
    img = Image.new("L", (1200, 400), 0)
    ImageDraw.Draw(img).text((50, 50), text, font=f, fill=255)
    return img.getbbox()


def fit(text, width):
    best = None
    for size in range(20, 600):
        f = ImageFont.truetype(FONT, size)
        l, _, r, _ = ink_box(text, f)
        if r - l > width:
            break
        best = f
    return best


def clean_background(img, s):
    """Removes the old white title (and its black outline) from the top part: the area is peeled from the edges
    inward, each ring takes the average of the nearby known pixels."""
    a = np.asarray(img.convert("RGB")).astype(float)
    h = int(130 * s)
    white = (a[:h].min(axis=2) > 150)
    mask = binary_dilation(white, iterations=max(3, round(10 * s)))
    out = a[:h].copy()
    known = (~mask).astype(float)
    sig = (2.5 * s, 4 * s)
    for _ in range(80):
        if known.min() >= 1:
            break
        w = gaussian_filter(known, sig)
        ring = (known == 0) & (w > 0.15)
        if not ring.any():
            sig = (sig[0] * 1.5, sig[1] * 1.5)
            continue
        for c in range(3):
            v = gaussian_filter(out[..., c] * known, sig) / np.maximum(w, 1e-4)
            out[..., c][ring] = v[ring]
        known[ring] = 1.0
    # small smoothing only inside the filled area so the seam does not show
    soft = np.stack([gaussian_filter(out[..., c], (1.2 * s, 2 * s)) for c in range(3)], axis=2)
    seam = gaussian_filter(binary_dilation(~(known > 0) | mask, iterations=1).astype(float), 1.5 * s)[..., None]
    out = out * (1 - seam * mask[..., None]) + soft * (seam * mask[..., None])
    res = np.asarray(img.convert("RGB")).copy()
    res[:h] = np.clip(out, 0, 255).astype(np.uint8)
    return Image.fromarray(res)


def title_mask(size, s):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    for text, width, yc in LINES:
        f = fit(text, width * s)
        l, top, r, bot = ink_box(text, f)
        d.text(((size - (r - l)) / 2 - (l - 50), yc * s - ((top + bot) / 2 - 50)), text, font=f, fill=255)
    return mask


def build(src, size):
    s = size / 288
    img = clean_background(Image.open(src).convert("RGB"), s)
    mask = title_mask(size, s)
    outline = mask.filter(ImageFilter.MaxFilter(2 * round(3 * s) + 1)).filter(ImageFilter.GaussianBlur(0.8 * s))  # same as the Quality Calculator avatar
    img.paste((0, 0, 0), (0, 0), outline)
    img.paste((255, 255, 255), (0, 0), mask)
    return img


def main():
    big = build(FINAL / "radar-button-512-v3.png", 512)
    big.save(FINAL / "radar-button-512-v4.png")
    small = build(FINAL / "radar-button-288-v3.png", 288)
    small.save(FINAL / "radar-button-288-v4.png")
    small.resize((144, 144), Image.LANCZOS).save(ROOT / "src" / "factory-radar" / "thumbnail.png")
    print("saved")


if __name__ == "__main__":
    main()
