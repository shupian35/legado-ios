#!/usr/bin/env python3
"""Render the upstream launcher icons into the PNG files the iOS app needs.

The Android app draws its launcher icons as vector drawables
(`app/src/main/res/drawable/ic_launcher1.xml` … `ic_launcher7.xml` plus the
adaptive backgrounds `ic_launcherN_b.xml`).  iOS needs raster icons, so this
script renders the vectors into PNGs:

    * the foreground layer (`ic_launcherN.xml`) over the adaptive background
      (`ic_launcherN_b.xml`) — the same picture the Android launcher shows,
    * one PNG per size the iOS app icon needs (the iPhone @2x/@3x and the
      iPad @1x/@2x variants),
    * the same set for every alternate icon, so the app can offer the
      upstream's icon choice (upstream `help/LauncherIconHelp.kt`).

Usage:

    python Scripts/render_launcher_icons.py <android-repo> <output-dir>

The renderer implements the subset of the Android vector drawable format the
upstream icons use: the path commands M/L/H/V/C/S/Q/T/A/Z, the solid and the
linear/radial gradient fills and the strokes.
"""

from __future__ import annotations

import math
import os
import re
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

ANDROID = "{http://schemas.android.com/apk/res/android}"

# The icons are drawn on a 108 x 108 viewport (the adaptive icon grid).
VIEWPORT = 108.0

# The number of samples used to flatten a curve.
CURVE_SAMPLES = 24

# The rendering is done at this multiple of the final size and then reduced,
# which gives the icons their anti-aliased edges.
SUPERSAMPLE = 4

TOKEN_RE = re.compile(r"([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)")


def parse_color(value: str):
    """`#RGB`, `#RRGGBB` and `#AARRGGBB` into an RGBA tuple."""
    value = value.strip()
    if value.startswith("#"):
        value = value[1:]
    if len(value) == 3:
        value = "".join(ch * 2 for ch in value)
    if len(value) == 6:
        value = "ff" + value
    if len(value) != 8:
        raise ValueError(f"unsupported colour {value!r}")
    # The Android colours are written as #AARRGGBB.
    alpha = int(value[0:2], 16)
    red = int(value[2:4], 16)
    green = int(value[4:6], 16)
    blue = int(value[6:8], 16)
    return (red, green, blue, alpha)


def lerp(a, b, t):
    return a + (b - a) * t


def mix_color(first, second, t):
    return tuple(int(round(lerp(first[i], second[i], t))) for i in range(4))


def parse_path(data: str):
    """Split the path data into the commands and their numbers."""
    tokens = []
    for match in TOKEN_RE.finditer(data):
        if match.group(1):
            tokens.append(("cmd", match.group(1)))
        else:
            tokens.append(("num", float(match.group(2))))
    return tokens


class SubPath:
    def __init__(self):
        self.points = []
        self.closed = False


def flatten_path(data: str):
    """Turn the path data into a list of subpaths (lists of points)."""
    tokens = parse_path(data)
    subpaths = []
    current = None
    position = (0.0, 0.0)      # the current point
    start = (0.0, 0.0)         # the start of the current subpath
    last_control = None        # the reflection point of S/T
    last_curve = None
    command = None
    index = 0

    def numbers(count):
        nonlocal index
        values = []
        for _ in range(count):
            while index < len(tokens) and tokens[index][0] != "num":
                index += 1
            if index >= len(tokens):
                raise ValueError("not enough numbers in the path data")
            values.append(tokens[index][1])
            index += 1
        return values

    def new_subpath(point):
        nonlocal current
        current = SubPath()
        current.points.append(point)
        subpaths.append(current)
        return current

    def line_to(point):
        if current is None:
            new_subpath(position)
        current.points.append(point)

    while index < len(tokens):
        kind, value = tokens[index]
        if kind == "cmd":
            command = value
            index += 1
        elif command is None:
            raise ValueError("the path data starts with a number")

        relative = command.islower()
        upper = command.upper()

        if upper == "M":
            x, y = numbers(2)
            if relative:
                x, y = position[0] + x, position[1] + y
            position = (x, y)
            start = position
            new_subpath(position)
            command = "l" if relative else "L"
            last_curve = None
            last_control = None
        elif upper == "L":
            x, y = numbers(2)
            if relative:
                x, y = position[0] + x, position[1] + y
            position = (x, y)
            line_to(position)
            last_curve = None
            last_control = None
        elif upper == "H":
            (x,) = numbers(1)
            if relative:
                x = position[0] + x
            position = (x, position[1])
            line_to(position)
            last_curve = None
            last_control = None
        elif upper == "V":
            (y,) = numbers(1)
            if relative:
                y = position[1] + y
            position = (position[0], y)
            line_to(position)
            last_curve = None
            last_control = None
        elif upper == "C":
            x1, y1, x2, y2, x, y = numbers(6)
            if relative:
                x1, y1 = position[0] + x1, position[1] + y1
                x2, y2 = position[0] + x2, position[1] + y2
                x, y = position[0] + x, position[1] + y
            control1 = (x1, y1)
            control2 = (x2, y2)
            end = (x, y)
            line_to(cubic_point(position, control1, control2, end, 1.0))
            last_control = control2
            last_curve = "C"
            position = end
        elif upper == "S":
            x2, y2, x, y = numbers(4)
            if relative:
                x2, y2 = position[0] + x2, position[1] + y2
                x, y = position[0] + x, position[1] + y
            if last_curve in ("C", "S"):
                control1 = reflect(position, last_control)
            else:
                control1 = position
            control2 = (x2, y2)
            end = (x, y)
            line_to(cubic_point(position, control1, control2, end, 1.0))
            last_control = control2
            last_curve = "S"
            position = end
        elif upper == "Q":
            x1, y1, x, y = numbers(4)
            if relative:
                x1, y1 = position[0] + x1, position[1] + y1
                x, y = position[0] + x, position[1] + y
            control = (x1, y1)
            end = (x, y)
            line_to(quadratic_point(position, control, end, 1.0))
            last_control = control
            last_curve = "Q"
            position = end
        elif upper == "T":
            x, y = numbers(2)
            if relative:
                x, y = position[0] + x, position[1] + y
            if last_curve in ("Q", "T"):
                control = reflect(position, last_control)
            else:
                control = position
            end = (x, y)
            line_to(quadratic_point(position, control, end, 1.0))
            last_control = control
            last_curve = "T"
            position = end
        elif upper == "A":
            rx, ry, rotation, large, sweep, x, y = numbers(7)
            if relative:
                x, y = position[0] + x, position[1] + y
            end = (x, y)
            for point in arc_points(
                position, end, rx, ry, rotation, bool(large), bool(sweep)
            ):
                line_to(point)
            last_curve = None
            last_control = None
            position = end
        elif upper == "Z":
            if current is not None:
                current.closed = True
            position = start
            current = None
            last_curve = None
            last_control = None
        else:
            raise ValueError(f"unsupported path command {command!r}")

    return subpaths


def reflect(point, control):
    if control is None:
        return point
    return (2 * point[0] - control[0], 2 * point[1] - control[1])


def cubic_point(start, control1, control2, end, t):
    u = 1 - t
    x = (
        u * u * u * start[0]
        + 3 * u * u * t * control1[0]
        + 3 * u * t * t * control2[0]
        + t * t * t * end[0]
    )
    y = (
        u * u * u * start[1]
        + 3 * u * u * t * control1[1]
        + 3 * u * t * t * control2[1]
        + t * t * t * end[1]
    )
    return (x, y)


def quadratic_point(start, control, end, t):
    u = 1 - t
    x = u * u * start[0] + 2 * u * t * control[0] + t * t * end[0]
    y = u * u * start[1] + 2 * u * t * control[1] + t * t * end[1]
    return (x, y)


def arc_points(start, end, rx, ry, rotation, large, sweep):
    """The endpoint arc of the SVG specification."""
    x1, y1 = start
    x2, y2 = end
    if (x1, y1) == (x2, y2):
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [end]
    phi = math.radians(rotation % 360)
    cos_phi = math.cos(phi)
    sin_phi = math.sin(phi)
    dx2 = (x1 - x2) / 2
    dy2 = (y1 - y2) / 2
    x1p = cos_phi * dx2 + sin_phi * dy2
    y1p = -sin_phi * dx2 + cos_phi * dy2
    lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1:
        scale = math.sqrt(lam)
        rx *= scale
        ry *= scale
    numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    factor = math.sqrt(max(0.0, numerator / denominator)) if denominator else 0.0
    if large == sweep:
        factor = -factor
    cxp = factor * rx * y1p / ry
    cyp = -factor * ry * x1p / rx
    cx = cos_phi * cxp - sin_phi * cyp + (x1 + x2) / 2
    cy = sin_phi * cxp + cos_phi * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        length = math.hypot(ux, uy) * math.hypot(vx, vy)
        if length == 0:
            return 0.0
        value = math.acos(max(-1.0, min(1.0, dot / length)))
        if ux * vy - uy * vx < 0:
            value = -value
        return value

    ux = (x1p - cxp) / rx
    uy = (y1p - cyp) / ry
    vx = (-x1p - cxp) / rx
    vy = (-y1p - cyp) / ry
    theta = angle(1, 0, ux, uy)
    delta = angle(ux, uy, vx, vy)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi

    points = []
    for step in range(1, CURVE_SAMPLES + 1):
        t = step / CURVE_SAMPLES
        angle_now = theta + delta * t
        px = cos_phi * rx * math.cos(angle_now) - sin_phi * ry * math.sin(angle_now) + cx
        py = sin_phi * rx * math.cos(angle_now) + cos_phi * ry * math.sin(angle_now) + cy
        points.append((px, py))
    return points


def winding_mask(subpaths, size, factor):
    """A scanline fill with the non-zero winding rule."""
    mask = Image.new("L", (size, size), 0)
    edges = []
    for subpath in subpaths:
        points = subpath.points
        if len(points) < 2:
            continue
        scaled = [(x * factor, y * factor) for x, y in points]
        if subpath.closed:
            scaled.append(scaled[0])
        for index in range(len(scaled) - 1):
            edges.append((scaled[index], scaled[index + 1]))
    if not edges:
        return mask
    draw = ImageDraw.Draw(mask)
    for row in range(size):
        y = row + 0.5
        crossings = []
        for (x0, y0), (x1, y1) in edges:
            if y0 == y1:
                continue
            if min(y0, y1) <= y < max(y0, y1):
                t = (y - y0) / (y1 - y0)
                crossings.append((x0 + t * (x1 - x0), 1 if y1 > y0 else -1))
        if not crossings:
            continue
        crossings.sort()
        winding = 0
        span_start = None
        for x, direction in crossings:
            previous = winding
            winding += direction
            if previous == 0 and winding != 0:
                span_start = x
            elif previous != 0 and winding == 0 and span_start is not None:
                draw.rectangle([span_start, row, x, row + 1], fill=255)
                span_start = None
    return mask


def gradient_image(stops, kind, start, end, size, scale):
    """The gradient of a path, drawn over the whole canvas."""
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    start = (start[0] * scale, start[1] * scale)
    end = (end[0] * scale, end[1] * scale)
    if kind == "radial":
        center = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2)
        radius = math.hypot(end[0] - start[0], end[1] - start[1]) or 1.0
    else:
        axis = (end[0] - start[0], end[1] - start[1])
        length = axis[0] * axis[0] + axis[1] * axis[1]
    stops = sorted(stops, key=lambda item: item[0])
    for row in range(size):
        for column in range(size):
            if kind == "radial":
                distance = math.hypot(column + 0.5 - center[0], row + 0.5 - center[1])
                t = min(1.0, max(0.0, distance / radius))
            else:
                px = column + 0.5 - start[0]
                py = row + 0.5 - start[1]
                t = (px * axis[0] + py * axis[1]) / length if length else 0.0
                t = min(1.0, max(0.0, t))
            color = interpolate(stops, t)
            pixels[column, row] = color
    return image


def interpolate(stops, t):
    if t <= stops[0][0]:
        return stops[0][1]
    for index in range(1, len(stops)):
        previous_offset, previous_color = stops[index - 1]
        offset, color = stops[index]
        if t <= offset:
            span = offset - previous_offset
            ratio = (t - previous_offset) / span if span else 0.0
            return mix_color(previous_color, color, ratio)
    return stops[-1][1]


def draw_vector(root, size):
    """Render one vector drawable onto an RGBA image."""
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    viewport = root.get(ANDROID + "viewportWidth")
    view_height = root.get(ANDROID + "viewportHeight")
    width = float(viewport) if viewport else VIEWPORT
    height = float(view_height) if view_height else VIEWPORT
    factor = size / width if width else 1.0
    for element in root:
        if not element.tag.endswith("path"):
            continue
        data = element.get(ANDROID + "pathData")
        if not data:
            continue
        subpaths = flatten_path(data)
        fill = element.get(ANDROID + "fillColor")
        gradient = None
        for child in element:
            if not child.tag.endswith("attr"):
                continue
            for item in child:
                if not item.tag.endswith("gradient"):
                    continue
                stops = []
                for entry in item:
                    stops.append(
                        (
                            float(entry.get(ANDROID + "offset", "0")),
                            parse_color(entry.get(ANDROID + "color", "#ffffffff")),
                        )
                    )
                gradient = (
                    stops,
                    item.get(ANDROID + "type", "linear"),
                    (
                        float(item.get(ANDROID + "startX", "0")),
                        float(item.get(ANDROID + "startY", "0")),
                    ),
                    (
                        float(item.get(ANDROID + "endX", width)),
                        float(item.get(ANDROID + "endY", height)),
                    ),
                )
        mask = winding_mask(subpaths, size, factor)
        if fill and not gradient:
            color = parse_color(fill)
            overlay = Image.new("RGBA", (size, size), color)
            image = Image.alpha_composite(image, overlay_with_mask(overlay, mask, color[3]))
        elif gradient:
            stops, kind, start, end = gradient
            overlay = gradient_image(stops, kind, start, end, size, factor)
            image = Image.alpha_composite(image, overlay_with_mask(overlay, mask, 255))
        stroke = element.get(ANDROID + "strokeColor")
        if stroke:
            width = float(element.get(ANDROID + "strokeWidth", "1"))
            stroke_mask = Image.new("L", (size, size), 0)
            draw = ImageDraw.Draw(stroke_mask)
            for subpath in subpaths:
                points = [(x * factor, y * factor) for x, y in subpath.points]
                if len(points) >= 2:
                    draw.line(points, fill=255, width=max(1, int(round(width * factor))), joint="curve")
            color = parse_color(stroke)
            overlay = Image.new("RGBA", (size, size), color)
            image = Image.alpha_composite(image, overlay_with_mask(overlay, stroke_mask, color[3]))
    return image


def overlay_with_mask(overlay, mask, alpha):
    """The overlay, cut to the mask (the alpha of the colour included)."""
    result = overlay.copy()
    if alpha != 255:
        channel = result.getchannel("A").point(lambda value: value * alpha // 255)
        result.putalpha(channel)
    result.putalpha(Image.composite(result.getchannel("A"), Image.new("L", mask.size, 0), mask))
    return result


def render(android_repo, output_dir, name, foreground, background, background_color=None):
    """Render one icon and write the sizes the iOS app needs."""
    source = os.path.join(android_repo, "app", "src", "main", "res", "drawable")
    layers = []
    if background:
        layers.append(os.path.join(source, background))
    layers.append(os.path.join(source, foreground))
    # The sizes: (the file suffix, the pixel size).
    sizes = [
        ("", 76),        # the iPad @1x
        ("@2x", 120),    # the iPhone @2x
        ("@2x", 152),    # the iPad @2x
        ("@3x", 180),    # the iPhone @3x
    ]
    for suffix, size in sizes:
        canvas = int(size * SUPERSAMPLE)
        image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        if background_color:
            fill = Image.new("RGBA", (canvas, canvas), parse_color(background_color))
            image = Image.alpha_composite(image, fill)
        for layer in layers:
            root = ET.parse(layer).getroot()
            image = Image.alpha_composite(image, draw_vector(root, canvas))
        # An adaptive icon shows the middle 72 of the 108 units of the layer;
        # the outer 18 units on every side may be cropped away.
        inset = canvas * 18 / 108
        image = image.crop((inset, inset, canvas - inset, canvas - inset))
        image = image.resize((size, size), Image.LANCZOS)
        path = os.path.join(output_dir, f"{name}{suffix}.png")
        image.save(path)
    return name


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    android_repo = sys.argv[1]
    output_dir = sys.argv[2]
    os.makedirs(output_dir, exist_ok=True)
    # The default icon and the six alternates of the upstream.
    #
    # The pairs come from the adaptive icons of the upstream
    # (`res/mipmap-anydpi-v26/ic_launcher.xml` and `launcher1.xml` …
    # `launcher6.xml`); the background of a launcher is either a vector
    # drawable or a plain colour (`@color/md_yellow_600` = #FDD835 and
    # `@color/md_grey_50` = #FAFAFA).
    icons = [
        ("AppIcon60x60", "ic_launcher1.xml", "ic_launcher1_b.xml", None),
        ("Icon1", "ic_launcher2.xml", None, "#FDD835"),
        ("Icon2", "ic_launcher5.xml", "ic_launcher5_b.xml", None),
        ("Icon3", "ic_launcher3.xml", None, "#FAFAFA"),
        ("Icon4", "ic_launcher4.xml", "ic_launcher4_b.xml", None),
        ("Icon5", "ic_launcher6.xml", None, "#FAFAFA"),
        ("Icon6", "ic_launcher7.xml", "ic_launcher7_b.xml", None),
    ]
    for name, foreground, background, color in icons:
        print("rendering", name)
        render(android_repo, output_dir, name, foreground, background, color)
    return 0


if __name__ == "__main__":
    sys.exit(main())
