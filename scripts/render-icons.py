"""Render the SVG masters; keep app and header artwork identical."""
from pathlib import Path
import cairosvg

root = Path(__file__).resolve().parent.parent
icons = root / "Resources/Icons"
resources = root / "Sources/Castagno/Resources"
resources.mkdir(exist_ok=True)
mark = (icons / "ChestnutSpeaker.svg").read_text()
inner = mark.split('viewBox="0 0 100 100">', 1)[1].rsplit('</svg>', 1)[0]
app = '''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 100 100">
<!-- Generated from ChestnutSpeaker.svg by scripts/render-icons.py. -->
<defs><linearGradient id="tile" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#fffaf0"/><stop offset="1" stop-color="#e8dbc4"/></linearGradient></defs>
<rect x="5" y="6" width="90" height="90" rx="21" fill="#c4b598" opacity=".3"/>
<rect x="5" y="5" width="90" height="90" rx="21" fill="url(#tile)"/>
<g transform="translate(11 10) scale(.78)">''' + inner + '</g>\n</svg>\n'
(icons / "AppIcon.svg").write_text(app)
for source, target, size in [
    ("AppIcon.svg", icons / "AppIcon.png", 1024),
    ("ChestnutSpeaker.svg", resources / "ChestnutSpeaker.png", 64),
    ("MenuBar.svg", icons / "MenuBar.png", 18),
    ("MenuBar.svg", icons / "MenuBar@2x.png", 36),
]:
    cairosvg.svg2png(url=str(icons / source), write_to=str(target),
                    output_width=size, output_height=size)
for name in ["MenuBar.png", "MenuBar@2x.png"]:
    (resources / name).write_bytes((icons / name).read_bytes())
