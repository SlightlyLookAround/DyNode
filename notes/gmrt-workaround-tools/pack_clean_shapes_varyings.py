"""Pack the Clean Shapes varying declarations into vec4s.

The library declares ~30 varyings, which map to 30 vertex-output locations.
WebGPU (and therefore GMRT's Dawn backend) caps inter-stage shader variables at
16, so every Clean pipeline fails to build and poisons the whole frame.

Packing the same data into vec4s keeps the shader behaviour identical while
using at most 15 locations; GMS2/YYC are happy with this too.
"""
import os
import re

SHADERS = r"D:\DYNSource\shaders"
PAIRS = [
    ("__shdcleanantialias", "__shdcleanantialias"),
    ("__shdCleanAntialiasLegacy", "__shdCleanAntialiasLegacy"),
    ("__shdcleanjaggies", "__shdcleanjaggies"),
]
DECL = re.compile(r'^\s*varying\s+(float|vec2|vec3|vec4)\s+([A-Za-z_]\w*)\s*;\s*$')
SIZES = {"float": 1, "vec2": 2, "vec3": 3, "vec4": 4}


def collect(path):
    order = []
    with open(path, encoding="utf-8-sig") as fh:
        for line in fh:
            m = DECL.match(line)
            if m:
                order.append((m.group(2), m.group(1)))
    return order

# One shared mapping so both stages agree on the layout.
mapping = {}
for folder, name in PAIRS:
    for suffix in (".vsh", ".fsh"):
        for var, typ in collect(os.path.join(SHADERS, folder, name + suffix)):
            if var not in mapping:
                mapping[var] = typ

layout = {}
used = []          # components used per pack
for var, typ in sorted(mapping.items(), key=lambda kv: -SIZES[kv[1]]):
    size = SIZES[typ]
    pack = None
    for n, u in enumerate(used):
        if u + size <= 4:
            pack = n
            break
    if pack is None:
        pack = len(used)
        used.append(0)
    layout[var] = (pack, used[pack], size)
    used[pack] += size
pack_count = len(used)
print("varyings:", len(layout), "floats:", sum(SIZES[t] for t in mapping.values()), "-> vec4 packs:", pack_count)
assert pack_count <= 16, pack_count

SWIZZLE = {1: "x", 2: "xy", 3: "xyz", 4: "xyzw"}


def build_block():
    lines = []
    for n in range(pack_count):
        lines.append("varying vec4 v_packed%d;" % n)
    lines.append("// [GMRT-WA-15767] 上面这些数据被打包进少量 vec4：WebGPU 的顶点输出上限是 16 个，")
    lines.append("// 原来的 ~30 个 varying 会让 Clean 的 pipeline 创建失败（黑屏 + 每帧校验报错）。")
    lines.append("// 数据本身没变，只是换了存放方式；GMS2/YYC 同样适用。")
    for var, (pk, comp, size) in layout.items():
        sel = SWIZZLE[size]
        if sel == "xyzw":
            target = "v_packed%d" % pk
        else:
            target = "v_packed%d.%s" % (pk, sel)
        # the swizzle has to start at the right component
        if sel != "xyzw":
            target = "v_packed%d.%s" % (pk, "xyzw"[comp:comp + size])
        lines.append("#define %s %s" % (var, target))
    return lines


BLOCK = build_block()

for folder, name in PAIRS:
    for suffix in (".vsh", ".fsh"):
        path = os.path.join(SHADERS, folder, name + suffix)
        with open(path, encoding="utf-8-sig") as fh:
            text = fh.read()
        out = []
        inserted = False
        for line in text.splitlines():
            if DECL.match(line):
                if not inserted:
                    out.extend(BLOCK)
                    inserted = True
                continue
            out.append(line)
        assert inserted, path
        with open(path, "w", encoding="utf-8", newline="\r\n") as fh:
            fh.write("\n".join(out) + "\n")
        print("patched", path)
