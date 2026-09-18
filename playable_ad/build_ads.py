#!/usr/bin/env python3
"""Builds the five Google Ads (App campaign) HTML5 playables.

Each ad is one self-contained index.html (every asset base64-inlined) zipped
on its own, declaring both 320x480 and 480x320 via ad.orientation. Output:

  dist/ads/<slug>/index.html
  dist/ads/tetrofall_<slug>.zip
  dist/ads/preview.html          local QA harness only, never zipped

The build fails if a zip breaks Google's HTML5 upload rules
(support.google.com/google-ads/answer/9981650 and /12771973).

Usage: python3 build_ads.py
"""
import os
import re
import sys
import zipfile

from build import ASSETS, build_assets_js, data_uri, read_text

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src", "ads")
OUT = os.path.join(HERE, "dist", "ads")

CORE = ["constants.js", "engine.js", "audio.js", "layout.js", "render.js", "input.js", "director.js"]
ADS = ["deep_well", "chain_reaction", "floor_rises", "where_does_it_go", "real_game"]

EXIT_API = "https://tpc.googlesyndication.com/pagead/gadgets/html5/api/exitapi.js"
MAX_ZIP_BYTES = 5_000_000
MAX_FILES = 512
ALLOWED_EXT = {".css", ".gif", ".html", ".htm", ".jpeg", ".jpg", ".js", ".png", ".svg"}
FORBIDDEN = ["localStorage", "sessionStorage", "indexedDB", "document.cookie", "mraid", "<iframe", "Enabler.js"]


def font_face_css():
    return (
        "@font-face {\n"
        '  font-family: "TFDisplay";\n'
        f'  src: url("{data_uri(os.path.join(ASSETS, "display.woff2"))}") format("woff2");\n'
        "  font-weight: 800;\n"
        "  font-display: block;\n"
        "}"
    )


def validate(slug, html, zip_path):
    errors = []
    if not html.lstrip().startswith("<!DOCTYPE html>"):
        errors.append("missing <!DOCTYPE html>")
    if '<meta name="ad.orientation" content="portrait,landscape">' not in html:
        errors.append("missing ad.orientation meta tag")
    head = html.split("</head>", 1)[0]
    if f'<script type="text/javascript" src="{EXIT_API}"></script>' not in head:
        errors.append("exitapi.js <script> tag not in <head>")
    urls = set(re.findall(r"https?://[^\s\"'<>)]+", html))
    extra = sorted(u for u in urls if u != EXIT_API)
    if extra:
        errors.append(f"external references: {extra}")
    for word in FORBIDDEN:
        if word in html:
            errors.append(f"forbidden token: {word}")
    if re.search(r"<(path|rect|circle|line|polygon|g|svg)\b[^>]*/>", html):
        errors.append("self-closing SVG tag")

    size = os.path.getsize(zip_path)
    with zipfile.ZipFile(zip_path) as zf:
        names = zf.namelist()
    if size > MAX_ZIP_BYTES:
        errors.append(f"zip is {size:,} bytes (> {MAX_ZIP_BYTES:,})")
    if len(names) > MAX_FILES:
        errors.append(f"{len(names)} files in zip (> {MAX_FILES})")
    for n in names:
        if os.path.splitext(n)[1].lower() not in ALLOWED_EXT:
            errors.append(f"unsupported file type in zip: {n}")
        if not re.fullmatch(r"[A-Za-z0-9._/-]+", n):
            errors.append(f"unsupported characters in filename: {n}")
    if "index.html" not in names:
        errors.append("index.html missing at zip root")
    return errors, size, len(names)


def build_ad(slug, template, assets_js, font_css, core_js):
    ad_js = read_text(os.path.join(SRC, "ads", f"{slug}.js"))
    title = re.search(r"title:\s*'([^']+)'", ad_js).group(1)
    html = (
        template
        .replace("{{TITLE}}", title)
        .replace("{{FONT_FACE}}", font_css)
        .replace("{{ASSETS_JS}}", assets_js)
        .replace("{{CORE_JS}}", core_js)
        .replace("{{AD_JS}}", ad_js)
        .replace("{{SLUG}}", slug)
    )
    out_dir = os.path.join(OUT, slug)
    os.makedirs(out_dir, exist_ok=True)
    html_path = os.path.join(out_dir, "index.html")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)

    zip_path = os.path.join(OUT, f"tetrofall_{slug}.zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(html_path, arcname="index.html")
    return html, html_path, zip_path


def write_preview():
    frames = []
    for slug in ADS:
        frames.append(
            f'<section><h2>{slug}</h2><div class="row">'
            f'<iframe src="{slug}/index.html" width="320" height="480"></iframe>'
            f'<iframe src="{slug}/index.html" width="480" height="320"></iframe>'
            "</div></section>"
        )
    html = (
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Tetrofall playables preview</title>"
        "<style>body{background:#111;color:#eee;font:14px system-ui;margin:20px}"
        ".row{display:flex;gap:20px;align-items:flex-start;flex-wrap:wrap}"
        "iframe{border:1px solid #444;background:#000}h2{font-size:15px;margin:24px 0 8px}</style>"
        "</head><body><h1>Tetrofall playables (local QA only)</h1>"
        + "".join(frames)
        + "</body></html>"
    )
    path = os.path.join(OUT, "preview.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(html)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    template = read_text(os.path.join(SRC, "template.html"))
    assets_js = build_assets_js()
    font_css = font_face_css()
    core_js = "\n".join(read_text(os.path.join(SRC, "core", name)) for name in CORE)

    failed = False
    print(f"{'ad':<18} {'html':>10} {'zip':>10} files  status")
    for slug in ADS:
        html, html_path, zip_path = build_ad(slug, template, assets_js, font_css, core_js)
        errors, zsize, count = validate(slug, html, zip_path)
        status = "ok" if not errors else "FAIL"
        print(f"{slug:<18} {os.path.getsize(html_path):>10,} {zsize:>10,} {count:>5}  {status}")
        for e in errors:
            print(f"    - {e}")
        failed = failed or bool(errors)

    print(f"\npreview: {write_preview()}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
