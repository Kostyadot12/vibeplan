"""One-shot: take the ChatGPT-generated icon, normalize to Apple's 1024x1024
RGBA spec with transparent background (preserves the soft drop-shadow).

Re-run only if the source PNG changes.
"""
from PIL import Image
from pathlib import Path

HERE   = Path(__file__).parent
SOURCE = HERE / "AppIcon-Original.png"
DEST   = HERE / "AppIcon-Source.png"


def main() -> None:
    im = Image.open(SOURCE).convert("RGBA").resize((1024, 1024), Image.LANCZOS)

    # Background is ~ (254,254,254). Anything that bright AND fully opaque
    # becomes transparent. Soft shadow pixels (240ish and below) survive,
    # which preserves the lift of the squircle.
    px = im.load()
    THRESHOLD = 250  # pixels >= this on every channel are treated as bg
    SOFT_BAND = 6    # ramp from 244..249 fades shadow gently

    for y in range(1024):
        for x in range(1024):
            r, g, b, a = px[x, y]
            v = min(r, g, b)
            if v >= THRESHOLD:
                px[x, y] = (r, g, b, 0)
            elif v >= THRESHOLD - SOFT_BAND:
                # fade out the rim around almost-white pixels for smooth edge
                frac = (THRESHOLD - v) / SOFT_BAND
                px[x, y] = (r, g, b, int(255 * frac))

    im.save(DEST, "PNG", optimize=True)
    print(f"Wrote {DEST} ({DEST.stat().st_size} bytes, 1024x1024 RGBA)")


if __name__ == "__main__":
    main()
