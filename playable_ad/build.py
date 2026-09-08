#!/usr/bin/env python3
"""Assembles the Tetrofall playable ad into per-network self-contained
index.html files and zips, from the shared src/ core.

See playable_ad_plan.md (repo root) Section 3.4 / 6 — this is the "simple
string-substitution/concat build step" that plan flagged as a packaging
requirement. Usage: python3 build.py

This script has no dependency beyond the Python standard library — it only
reads the already-small files under assets/ (produced once by
tools/prepare_assets.py, which does need ffmpeg/fontTools) and base64-
inlines them. Regenerating assets/ is a separate, occasional step.
"""
import base64
import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
DIST = os.path.join(HERE, "dist")
ASSETS = os.path.join(HERE, "assets")

GOOGLE_META = (
    '<meta name="ad.size" content="width=360,height=640">\n'
    '<meta name="ad.orientation" content="portrait">'
)

VARIANTS = {
    "local": {"shim": None, "meta": ""},
    "meta": {"shim": "meta.js", "meta": ""},
    "google": {"shim": "google.js", "meta": GOOGLE_META},
}

MIME = {
    ".jpg": "image/jpeg",
    ".mp3": "audio/mpeg",
    ".woff2": "font/woff2",
}


def read_text(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def data_uri(path):
    ext = os.path.splitext(path)[1]
    mime = MIME[ext]
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    return f"data:{mime};base64,{b64}"


def build_assets_js():
    keys = {
        "blockTile": "block_tile.jpg",
        "boardTile": "board_tile.jpg",
        "sfxLock": "sfx_lock.mp3",
        "sfxClear": "sfx_clear.mp3",
    }
    lines = ["window.TF = window.TF || {};", "TF.ASSETS = {"]
    for key, filename in keys.items():
        uri = data_uri(os.path.join(ASSETS, filename))
        lines.append(f'  {key}: "{uri}",')
    lines.append("};")
    return "\n".join(lines)


def build_font_face_css():
    uri = data_uri(os.path.join(ASSETS, "wordmark.woff2"))
    return (
        "@font-face {\n"
        '  font-family: "TFBaloo";\n'
        f'  src: url("{uri}") format("woff2");\n'
        "  font-weight: 800;\n"
        "  font-display: swap;\n"
        "}"
    )


def build_variant(name, cfg, assets_js, font_face_css):
    template = read_text(os.path.join(SRC, "template.html"))
    game_js = read_text(os.path.join(SRC, "game.js"))
    shim_js = read_text(os.path.join(SRC, "shims", cfg["shim"])) if cfg["shim"] else (
        "// local build: no network shim loaded, TF.exitToStore() just logs."
    )

    html = (
        template
        .replace("{{NETWORK_META}}", cfg["meta"])
        .replace("{{FONT_FACE}}", font_face_css)
        .replace("{{ASSETS_JS}}", assets_js)
        .replace("{{GAME_JS}}", game_js)
        .replace("{{SHIM_JS}}", shim_js)
    )

    out_dir = os.path.join(DIST, name)
    os.makedirs(out_dir, exist_ok=True)
    out_html = os.path.join(out_dir, "index.html")
    with open(out_html, "w", encoding="utf-8") as f:
        f.write(html)

    size = os.path.getsize(out_html)
    print(f"[{name}] wrote {out_html} ({size:,} bytes)")

    if name in ("meta", "google"):
        zip_path = os.path.join(DIST, f"tetrofall_playable_{name}.zip")
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(out_html, arcname="index.html")
        zsize = os.path.getsize(zip_path)
        print(f"[{name}] wrote {zip_path} ({zsize:,} bytes zipped)")


def main():
    os.makedirs(DIST, exist_ok=True)
    assets_js = build_assets_js()
    font_face_css = build_font_face_css()
    for name, cfg in VARIANTS.items():
        build_variant(name, cfg, assets_js, font_face_css)


if __name__ == "__main__":
    main()
