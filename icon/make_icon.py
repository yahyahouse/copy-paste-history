"""Generate the 1024px app icon for Clip History (minimalist stacked-card clipboard)."""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4                      # supersampling
W = 1024 * S
img = Image.new("RGBA", (W, W), (0, 0, 0, 0))


def r(v):
    return int(v * S)


# Shadow under the tile (macOS Big Sur grid: 824px tile, 100px margin)
shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(
    (r(100), r(112), r(924), r(936)), radius=r(185), fill=(0, 0, 0, 90))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(r(18))))

# Tile with vertical gradient
top, bottom = (74, 108, 247), (38, 56, 168)
grad = Image.new("RGBA", (W, W))
gd = ImageDraw.Draw(grad)
for y in range(W):
    t = y / (W - 1)
    gd.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle((r(100), r(100), r(924), r(924)), radius=r(185), fill=255)
img.paste(grad, (0, 0), mask)

def layer(draw_fn):
    lay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(lay))
    img.alpha_composite(lay)


# History stack: back cards, centered and rising behind the front card
layer(lambda d: d.rounded_rectangle((r(372), r(250), r(652), r(690)), radius=r(40), fill=(255, 255, 255, 70)))
layer(lambda d: d.rounded_rectangle((r(347), r(288), r(677), r(728)), radius=r(42), fill=(255, 255, 255, 130)))

# Front card
layer(lambda d: d.rounded_rectangle((r(322), r(330), r(702), r(774)), radius=r(44), fill=(255, 255, 255, 255)))

# Clip
layer(lambda d: d.rounded_rectangle((r(437), r(294), r(587), r(364)), radius=r(28), fill=(38, 56, 168, 255)))
layer(lambda d: d.rounded_rectangle((r(469), r(313), r(555), r(345)), radius=r(16), fill=(255, 255, 255, 255)))

# Text lines, fading like older history
for i, (x2, alpha) in enumerate([(632, 255), (598, 160), (548, 95)]):
    y = 452 + i * 84
    layer(lambda d, y=y, x2=x2, alpha=alpha: d.rounded_rectangle(
        (r(372), r(y), r(x2), r(y + 36)), radius=r(18), fill=(74, 108, 247, alpha)))

out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon-1024.png"
img.resize((1024, 1024), Image.LANCZOS).save(out)
print(out)
