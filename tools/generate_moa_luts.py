import colorsys
import math
from pathlib import Path


LUT_SIZE = 33
OUTPUT_DIR = Path("assets/luts")


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smoothstep(edge0, edge1, x):
    if edge0 == edge1:
        return 0.0
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - (2.0 * t))


def hue_distance(a, b):
    diff = abs((a - b + 180.0) % 360.0 - 180.0)
    return diff


def hue_weight(hue, center, width):
    dist = hue_distance(hue, center)
    if dist >= width:
        return 0.0
    x = 1.0 - (dist / width)
    return x * x * (3.0 - (2.0 * x))


def apply_hsl_adjustments(r, g, b, adjustments):
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    hue = h * 360.0
    hue_shift = 0.0
    sat_shift = 0.0
    lum_shift = 0.0
    total_weight = 0.0

    for adjust in adjustments:
        weight = hue_weight(hue, adjust["center"], adjust["width"])
        if weight == 0.0:
            continue
        total_weight += weight
        hue_shift += adjust.get("hue", 0.0) * weight
        sat_shift += adjust.get("sat", 0.0) * weight
        lum_shift += adjust.get("lum", 0.0) * weight

    if total_weight == 0.0:
        return r, g, b

    h = ((hue + hue_shift) % 360.0) / 360.0
    s = clamp(s + sat_shift)
    l = clamp(l + lum_shift)
    return colorsys.hls_to_rgb(h, l, s)


def apply_recipe(r, g, b, recipe):
    r, g, b = apply_hsl_adjustments(r, g, b, recipe.get("hsl", ()))

    exposure = recipe.get("exposure", 0.0)
    gain = math.pow(2.0, exposure)
    r, g, b = r * gain, g * gain, b * gain

    temperature = recipe.get("temperature", 0.0)
    tint = recipe.get("tint", 0.0)
    r *= 1.0 + (temperature * 0.18) + (tint * 0.08)
    g *= 1.0 - (tint * 0.10)
    b *= 1.0 - (temperature * 0.18) + (tint * 0.08)

    h, l, s = colorsys.rgb_to_hls(clamp(r), clamp(g), clamp(b))
    saturation = recipe.get("saturation", 0.0)
    vibrance = recipe.get("vibrance", 0.0)
    s = clamp(s * (1.0 + saturation) + (vibrance * (1.0 - s)))
    r, g, b = colorsys.hls_to_rgb(h, l, s)

    contrast = recipe.get("contrast", 0.0)
    r = (r - 0.5) * (1.0 + contrast) + 0.5
    g = (g - 0.5) * (1.0 + contrast) + 0.5
    b = (b - 0.5) * (1.0 + contrast) + 0.5

    luma = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    shadows = recipe.get("shadows", 0.0)
    shadow_mask = 1.0 - smoothstep(0.04, 0.56, luma)
    if shadows > 0.0:
        r += (1.0 - r) * shadows * shadow_mask
        g += (1.0 - g) * shadows * shadow_mask
        b += (1.0 - b) * shadows * shadow_mask
    elif shadows < 0.0:
        r *= 1.0 + (shadows * shadow_mask)
        g *= 1.0 + (shadows * shadow_mask)
        b *= 1.0 + (shadows * shadow_mask)

    highlights = recipe.get("highlights", 0.0)
    highlight_mask = smoothstep(0.45, 0.98, luma)
    if highlights > 0.0:
        r += (1.0 - r) * highlights * highlight_mask
        g += (1.0 - g) * highlights * highlight_mask
        b += (1.0 - b) * highlights * highlight_mask
    elif highlights < 0.0:
        r *= 1.0 + (highlights * highlight_mask)
        g *= 1.0 + (highlights * highlight_mask)
        b *= 1.0 + (highlights * highlight_mask)

    fade = recipe.get("fade", 0.0)
    if fade > 0.0:
        r = (r * (1.0 - fade)) + (0.09 * fade)
        g = (g * (1.0 - fade)) + (0.09 * fade)
        b = (b * (1.0 - fade)) + (0.09 * fade)

    return clamp(r), clamp(g), clamp(b)


RECIPES = {
    "moa_clear_sky.cube": {
        "title": "MOA Clear Sky",
        "exposure": 0.03,
        "contrast": 0.06,
        "saturation": 0.04,
        "vibrance": 0.10,
        "temperature": -0.04,
        "tint": -0.02,
        "highlights": -0.05,
        "shadows": 0.06,
        "hsl": (
            {"center": 60.0, "width": 34.0, "hue": -3.0, "sat": 0.03, "lum": 0.03},
            {"center": 120.0, "width": 48.0, "hue": -10.0, "sat": 0.10, "lum": 0.07},
            {"center": 180.0, "width": 42.0, "hue": -8.0, "sat": 0.14, "lum": 0.05},
            {"center": 225.0, "width": 52.0, "hue": -8.0, "sat": 0.16, "lum": 0.07},
        ),
    },
    "moa_warm_sunset.cube": {
        "title": "MOA Warm Sunset",
        "exposure": 0.03,
        "contrast": 0.08,
        "saturation": 0.05,
        "vibrance": 0.09,
        "temperature": 0.08,
        "tint": -0.02,
        "highlights": -0.06,
        "shadows": 0.04,
        "hsl": (
            {"center": 30.0, "width": 35.0, "hue": -3.0, "sat": 0.16, "lum": 0.05},
            {"center": 55.0, "width": 36.0, "hue": -7.0, "sat": 0.16, "lum": 0.06},
            {"center": 185.0, "width": 44.0, "hue": -8.0, "sat": 0.09, "lum": 0.04},
            {"center": 225.0, "width": 50.0, "hue": -5.0, "sat": 0.10, "lum": 0.04},
        ),
    },
    "moa_film_green.cube": {
        "title": "MOA Film Green",
        "exposure": 0.01,
        "contrast": -0.04,
        "saturation": 0.02,
        "vibrance": 0.06,
        "temperature": 0.01,
        "tint": -0.03,
        "highlights": -0.07,
        "shadows": 0.10,
        "fade": 0.08,
        "hsl": (
            {"center": 55.0, "width": 34.0, "hue": -4.0, "sat": 0.04, "lum": 0.03},
            {"center": 120.0, "width": 50.0, "hue": -12.0, "sat": 0.07, "lum": 0.05},
            {"center": 225.0, "width": 48.0, "hue": -2.0, "sat": -0.03, "lum": 0.02},
        ),
    },
    "moa_korean_travel_pop.cube": {
        "title": "MOA Korean Travel Pop",
        "exposure": 0.05,
        "contrast": 0.10,
        "saturation": 0.08,
        "vibrance": 0.12,
        "temperature": 0.02,
        "tint": -0.02,
        "highlights": -0.05,
        "shadows": 0.07,
        "hsl": (
            {"center": 30.0, "width": 35.0, "hue": -3.0, "sat": 0.10, "lum": 0.04},
            {"center": 55.0, "width": 36.0, "hue": -8.0, "sat": 0.15, "lum": 0.07},
            {"center": 120.0, "width": 50.0, "hue": -15.0, "sat": 0.16, "lum": 0.08},
            {"center": 180.0, "width": 44.0, "hue": -10.0, "sat": 0.18, "lum": 0.05},
            {"center": 225.0, "width": 52.0, "hue": -8.0, "sat": 0.20, "lum": 0.08},
        ),
    },
    "moa_city_night_warm.cube": {
        "title": "MOA City Night Warm",
        "exposure": 0.02,
        "contrast": 0.16,
        "saturation": 0.06,
        "vibrance": 0.08,
        "temperature": 0.08,
        "highlights": -0.04,
        "shadows": -0.06,
        "hsl": (
            {"center": 25.0, "width": 38.0, "hue": -2.0, "sat": 0.18, "lum": 0.05},
            {"center": 55.0, "width": 35.0, "hue": -4.0, "sat": 0.14, "lum": 0.04},
            {"center": 215.0, "width": 55.0, "hue": -4.0, "sat": 0.10, "lum": 0.00},
            {"center": 300.0, "width": 38.0, "hue": 0.0, "sat": 0.08, "lum": 0.00},
        ),
    },
}


def write_cube(path, recipe):
    lines = [
        f'TITLE "{recipe["title"]}"',
        f"LUT_3D_SIZE {LUT_SIZE}",
        "DOMAIN_MIN 0.0 0.0 0.0",
        "DOMAIN_MAX 1.0 1.0 1.0",
    ]
    max_index = LUT_SIZE - 1
    for blue in range(LUT_SIZE):
        b = blue / max_index
        for green in range(LUT_SIZE):
            g = green / max_index
            for red in range(LUT_SIZE):
                r = red / max_index
                rr, gg, bb = apply_recipe(r, g, b, recipe)
                lines.append(f"{rr:.6f} {gg:.6f} {bb:.6f}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for filename, recipe in RECIPES.items():
        write_cube(OUTPUT_DIR / filename, recipe)


if __name__ == "__main__":
    main()
