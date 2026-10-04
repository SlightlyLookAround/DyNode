"""Split the sprMsdfNotoSans MSDF atlas into <=2044px frames so GMRT packs it 1:1.

Repacks every glyph cell (pixel-exact, no resampling) into 2044x2044 tiles and
rewrites the glyph atlas bounds in datafiles/sprMsdfNotoSans.json so the tiles
form one virtual atlas of 2044 x (2044*N) pixels.
"""
import json
import math
import os
import shutil
import uuid

import numpy as np
from PIL import Image

SPR_DIR = r"D:\DYNSource\sprites\sprMsdfNotoSans"
SRC_PNG = os.path.join(SPR_DIR, "f685719d-b539-4ec2-929c-7a84241de239.png")
JSON_PATH = r"D:\DYNSource\datafiles\sprMsdfNotoSans.json"
YY_PATH = os.path.join(SPR_DIR, "sprMsdfNotoSans.yy")
LAYER_UUID = "e124badb-2263-4b4d-a1ba-d7f99f1bac45"

TILE = 2044          # 2048 page minus the group's 2px border on each side
PAD = 2

src = np.array(Image.open(SRC_PNG).convert("RGBA"))
doc = json.load(open(JSON_PATH, encoding="utf-8"))
AW, AH = int(doc["atlas"]["width"]), int(doc["atlas"]["height"])
assert (AW, AH) == (4096, 8192), (AW, AH)
assert src.shape[0] == AH and src.shape[1] == AW, src.shape

# ---- collect glyph cells (pixel exact) -------------------------------------
items = []
for gi, g in enumerate(doc["glyphs"]):
    ab = g.get("atlasBounds")
    if not ab:
        continue
    x0 = max(0, math.floor(ab["left"]))
    x1 = min(AW, math.ceil(ab["right"]))
    y0 = max(0, math.floor(AH - ab["top"]))          # top-down rows
    y1 = min(AH, math.ceil(AH - ab["bottom"]))
    if x1 <= x0 or y1 <= y0:
        continue
    items.append([gi, x0, y0, x1 - x0, y1 - y0])

# ---- shelf pack (tallest first) --------------------------------------------
order = sorted(range(len(items)), key=lambda i: (-items[i][4], -items[i][3]))
tiles = []
cur = []
x = PAD
y = PAD
row_h = 0
placement = {}
for i in order:
    _, _, _, w, h = items[i]
    if x + w + PAD > TILE:
        x = PAD
        y += row_h + PAD
        row_h = 0
    if y + h + PAD > TILE:
        tiles.append(cur)
        cur = []
        x = PAD
        y = PAD
        row_h = 0
    cur.append((i, x, y))
    placement[i] = (len(tiles), x, y)
    x += w + PAD
    row_h = max(row_h, h)
tiles.append(cur)

print("tiles:", len(tiles), "glyphs:", len(items), "placed:", sum(len(t) for t in tiles))

# ---- build the tile images --------------------------------------------------
canvases = [np.zeros((TILE, TILE, 4), dtype=np.uint8) for _ in tiles]
for t_idx, tile in enumerate(tiles):
    for i, px, py in tile:
        _, sx, sy, w, h = items[i]
        canvases[t_idx][py:py + h, px:px + w] = src[sy:sy + h, sx:sx + w]

# ---- write frames -----------------------------------------------------------
old_png = SRC_PNG
old_layer_dir = os.path.join(SPR_DIR, "layers", "f685719d-b539-4ec2-929c-7a84241de239")

frame_ids = [str(uuid.uuid4()) for _ in tiles]
layers_root = os.path.join(SPR_DIR, "layers")
for n, fid in enumerate(frame_ids):
    img = Image.fromarray(canvases[n], "RGBA")
    img.save(os.path.join(SPR_DIR, fid + ".png"), optimize=True)
    layer_dir = os.path.join(layers_root, fid)
    os.makedirs(layer_dir, exist_ok=True)
    img.save(os.path.join(layer_dir, LAYER_UUID + ".png"), optimize=True)

# ---- rewrite the atlas json -------------------------------------------------
new_h = TILE * len(tiles)
doc["atlas"]["width"] = TILE
doc["atlas"]["height"] = new_h
for t_idx, tile in enumerate(tiles):
    for i, px, py in tile:
        gi = items[i][0]
        gy0 = t_idx * TILE + py
        gy1 = gy0 + items[i][4]
        doc["glyphs"][gi]["atlasBounds"] = {
            "left": float(px),
            "right": float(px + items[i][3]),
            "top": float(new_h - gy0),
            "bottom": float(new_h - gy1),
        }
with open(JSON_PATH, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, ensure_ascii=False, separators=(",", ":"))
print("json written: atlas", TILE, "x", new_h)

# ---- rewrite the sprite yy --------------------------------------------------
yy = open(YY_PATH, encoding="utf-8-sig").read()
FRAME_TEMPLATE = ('    {"$GMSpriteFrame":"v1","%Name":"__FID__","name":"__FID__",'
                  '"resourceType":"GMSpriteFrame","resourceVersion":"2.0",},\n')
KEY_TEMPLATE = ('            {"$Keyframe<SpriteFrameKeyframe>":"","Channels":{"0":{"$SpriteFrameKeyframe":"",'
                '"Id":{"name":"__FID__","path":"sprites/sprMsdfNotoSans/sprMsdfNotoSans.yy",},'
                '"resourceType":"SpriteFrameKeyframe","resourceVersion":"2.0",},},"Disabled":false,'
                '"id":"__KEYID__","IsCreationKey":false,"Key":__KEY__,"Length":1.0,'
                '"resourceType":"Keyframe<SpriteFrameKeyframe>","resourceVersion":"2.0","Stretch":false,},\n')
frames_block = "".join(FRAME_TEMPLATE.replace("__FID__", fid) for fid in frame_ids)
keyframes_block = "".join(
    KEY_TEMPLATE.replace("__FID__", fid).replace("__KEYID__", str(uuid.uuid4())).replace("__KEY__", "%.1f" % float(n))
    for n, fid in enumerate(frame_ids)
)

import re
yy = re.sub(r'"frames":\[.*?\n  \],', '"frames":[\n' + frames_block + "  ],", yy, flags=re.S)
yy = re.sub(r'("keyframes":\{"\$KeyframeStore<SpriteFrameKeyframe>":"","Keyframes":\[).*?\n          \],',
            r'\1\n' + keyframes_block + "          ],", yy, flags=re.S)
yy = yy.replace('"bbox_bottom":8191', '"bbox_bottom":%d' % (TILE - 1))
yy = yy.replace('"bbox_right":4095', '"bbox_right":%d' % (TILE - 1))
yy = yy.replace('"height":8192', '"height":%d' % TILE)
yy = yy.replace('"length":1.0', '"length":%d.0' % len(tiles))
yy = yy.replace('"width":4096', '"width":%d' % TILE)
with open(YY_PATH, "w", encoding="utf-8", newline="\r\n") as fh:
    fh.write(yy)
print("yy written with", len(frame_ids), "frames")

# ---- validate the rewritten yy ---------------------------------------------
check = open(YY_PATH, encoding="utf-8").read()
import re as _re
assert len(_re.findall(r'\$GMSpriteFrame"', check)) == len(frame_ids), "frame count mismatch"
assert len(_re.findall(r'\$Keyframe<SpriteFrameKeyframe>', check)) == len(frame_ids), "keyframe count mismatch"
assert '"events":{\n      "$KeyframeStore<MessageEventKeyframe>":"",\n      "Keyframes":[],' in check, "events store was touched"
cleaned = check
while _re.search(r',(\s*[}\]])', cleaned):
    cleaned = _re.sub(r',(\s*[}\]])', r'\1', cleaned)
json.loads(cleaned)
print("yy validated")

if os.path.exists(old_png):
    os.remove(old_png)
if os.path.isdir(old_layer_dir):
    shutil.rmtree(old_layer_dir)
print("removed old frame png / layer dir")
