from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
APP_ICON_DIR = ROOT / "CursorMobile/Resources/Assets.xcassets/AppIcon.appiconset"
DESIGN_DIR = ROOT / "DesignAssets"


def draw_mark(
    path: Path,
    chevron: tuple[int, int, int, int],
    dot: tuple[int, int, int, int],
    background: tuple[int, int, int] | None = None
) -> None:
    scale = 4
    size = 1024
    if background:
        image = Image.new("RGBA", (size * scale, size * scale), (*background, 255))
    else:
        image = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    glow_draw = ImageDraw.Draw(glow)

    def p(value: int) -> int:
        return value * scale

    points = [(p(330), p(272)), (p(550), p(512)), (p(330), p(752))]
    width = p(150)
    draw.line(points, fill=chevron, width=width, joint="curve")
    for point in points:
        x, y = point
        draw.ellipse((x - width // 2, y - width // 2, x + width // 2, y + width // 2), fill=chevron)

    cx, cy, radius = p(690), p(690), p(82)
    glow_radius = p(130)
    glow_draw.ellipse(
        (cx - glow_radius, cy - glow_radius, cx + glow_radius, cy + glow_radius),
        fill=(dot[0], dot[1], dot[2], 72),
    )
    glow = glow.filter(ImageFilter.GaussianBlur(p(26)))
    image.alpha_composite(glow)
    draw = ImageDraw.Draw(image)
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=dot)

    image = image.resize((size, size), Image.Resampling.LANCZOS)
    if background:
        image.convert("RGB").save(path)
    else:
        image.save(path)


def main() -> None:
    DESIGN_DIR.mkdir(exist_ok=True)
    light = APP_ICON_DIR / "runline-app-icon-light.png"
    dark = APP_ICON_DIR / "runline-app-icon-dark.png"
    draw_mark(light, (17, 19, 24, 255), (37, 107, 255, 255), background=(242, 242, 247))
    draw_mark(dark, (90, 143, 255, 255), (47, 117, 255, 255), background=(18, 18, 20))
    draw_mark(DESIGN_DIR / "runline-app-icon-light-source.png", (17, 19, 24, 255), (37, 107, 255, 255))
    draw_mark(DESIGN_DIR / "runline-app-icon-dark-source.png", (90, 143, 255, 255), (47, 117, 255, 255))


if __name__ == "__main__":
    main()
