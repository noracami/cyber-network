#!/usr/bin/env python3
"""線稿分區填色管線（flatting）。

用法:
  segment  — 線稿 → 區塊 label 圖 + 隨機色預覽 + 點擊上色 picker.html
  probe    — 查座標落在哪個區塊 id（給腳本化指定顏色用）
  render   — 依 mapping.json 填色、疊回線稿,可選量化到四色色盤

  .venv/bin/python flatten.py segment input/plant_03_lineart.png
  .venv/bin/python flatten.py probe   out/plant_03_lineart/labels.png 380 1050
  .venv/bin/python flatten.py render  input/plant_03_lineart.png \
      out/plant_03_lineart/labels.png mapping.json --quantize
"""
import argparse
import base64
import io
import json
import sys
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).parent
PALETTE_FILE = HERE / "palette.json"


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def load_palette():
    return json.loads(PALETTE_FILE.read_text())


def line_mask(img_gray, thresh):
    if thresh < 0:  # Otsu
        _, mask = cv2.threshold(img_gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    else:
        _, mask = cv2.threshold(img_gray, thresh, 255, cv2.THRESH_BINARY_INV)
    return mask  # 255 = 線


def segment(args):
    src = Path(args.input)
    img = cv2.imread(str(src), cv2.IMREAD_COLOR)
    if img is None:
        sys.exit(f"讀不到圖: {src}")

    region_color = {}
    if args.flat:
        # 平塗模式:逐像素吸附色盤 → 同色連通區域即區塊,顏色即語意
        palette = load_palette()
        names = list(palette.keys())
        pal = np.array([hex_to_rgb(v)[::-1] for v in palette.values()], np.float32)
        d = np.linalg.norm(img[..., None, :].astype(np.float32) - pal, axis=-1)
        q = d.argmin(-1).astype(np.uint8)
        ink_idx = names.index("ink") if "ink" in names else int(pal.sum(1).argmin())
        labels = np.zeros(q.shape, np.int32)
        nid = 0
        for ci in range(len(names)):
            cn, cl = cv2.connectedComponents((q == ci).astype(np.uint8), connectivity=4)
            m = cl > 0
            labels[m] = cl[m] + nid
            for k in range(1, cn):
                region_color[nid + k] = names[ci]
            nid += cn - 1
        mask = ((q == ink_idx) * 255).astype(np.uint8)
    else:
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        mask = line_mask(gray, args.thresh)
        # 膨脹線條封缺口;分區用膨脹後的,渲染時顏色會長回線下
        fat = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=args.dilate)
        _, labels = cv2.connectedComponents((fat == 0).astype(np.uint8), connectivity=4)

    # 面積過濾:碎屑歸 0(之後由鄰近區塊長回)
    sizes = np.bincount(labels.ravel())
    small = np.where(sizes < args.min_area)[0]
    labels[np.isin(labels, small)] = 0
    kept = [int(i) for i in np.unique(labels) if i > 0]

    # 把 label 長進線下與碎屑區(nearest-source),得到全覆蓋 labels_full
    src_mask = np.where(labels > 0, 0, 255).astype(np.uint8)
    _, near = cv2.distanceTransformWithLabels(
        src_mask, cv2.DIST_L2, 3, labelType=cv2.DIST_LABEL_PIXEL
    )
    lut = np.zeros(int(near.max()) + 1, dtype=np.int32)
    assigned = labels > 0
    lut[near[assigned]] = labels[assigned]
    labels_full = lut[near]

    out_dir = HERE / "out" / src.stem
    out_dir.mkdir(parents=True, exist_ok=True)

    # labels.png:id 編碼進 RGB(R + G<<8 + B<<16),無損保存
    enc = np.zeros((*labels_full.shape, 3), np.uint8)
    enc[..., 2] = labels_full & 0xFF          # OpenCV 是 BGR,R 放 [...,2]
    enc[..., 1] = (labels_full >> 8) & 0xFF
    enc[..., 0] = (labels_full >> 16) & 0xFF
    cv2.imwrite(str(out_dir / "labels.png"), enc)

    # 預覽:每區隨機色,線壓黑
    rng = np.random.default_rng(7)
    colors = rng.integers(60, 255, size=(int(labels.max()) + 1, 3), dtype=np.uint8)
    colors[0] = (255, 255, 255)
    prev = colors[labels]
    prev[mask > 0] = (30, 30, 30)
    cv2.imwrite(str(out_dir / "preview.png"), prev)

    if args.flat:
        # 顏色即語意:直接輸出 mapping;另合成純線稿層供 render/picker 疊加
        mapping = {str(i): region_color[i] for i in kept if region_color.get(i, "paper") != "paper"}
        (out_dir / "flat_mapping.json").write_text(json.dumps(mapping, indent=1))
        synth = np.full_like(img, 255)
        synth[q == ink_idx] = np.array(hex_to_rgb(palette["ink"])[::-1], np.uint8)
        cv2.imwrite(str(out_dir / "flat_lineart.png"), synth)
        emit_picker(out_dir, out_dir / "flat_lineart.png", labels_full.shape[1], labels_full.shape[0])
        print(f"flat 模式:自動 mapping {len(mapping)} 區 → flat_mapping.json")
    else:
        emit_picker(out_dir, src, labels_full.shape[1], labels_full.shape[0])

    bg = labels_full[0, 0]
    print(f"區塊數(過濾後): {len(kept)}  背景區 id: {bg}")
    print(f"輸出: {out_dir}/labels.png preview.png picker.html")


def emit_picker(out_dir, lineart_path, w, h):
    b64 = lambda p: base64.b64encode(Path(p).read_bytes()).decode()
    html = (HERE / "picker_template.html").read_text()
    html = (
        html.replace("{{W}}", str(w))
        .replace("{{H}}", str(h))
        .replace("{{PALETTE}}", PALETTE_FILE.read_text())
        .replace("{{LINEART}}", b64(lineart_path))
        .replace("{{LABELS}}", b64(out_dir / "labels.png"))
    )
    (out_dir / "picker.html").write_text(html)


def autocolor(args):
    """用 AI 上色版(hint)對每個區塊做多數決,自動產 mapping.json。"""
    palette = load_palette()
    labels = read_labels(args.labels)
    hint = cv2.imread(str(args.hint), cv2.IMREAD_COLOR)
    if hint is None:
        sys.exit(f"讀不到 hint 圖: {args.hint}")
    if hint.shape[:2] != labels.shape:
        hint = cv2.resize(hint, (labels.shape[1], labels.shape[0]))

    # 高斯模糊把排線筆觸平均成區域色,再逐像素吸附到最近的色盤色
    if args.blur > 0:
        hint = cv2.GaussianBlur(hint, (0, 0), args.blur)
    names = list(palette.keys())
    pal = np.array([hex_to_rgb(v)[::-1] for v in palette.values()], np.float32)
    dist = np.linalg.norm(hint[..., None, :].astype(np.float32) - pal, axis=-1)
    snapped = dist.argmin(-1)

    default_idx = names.index(args.default)
    kernel = np.ones((3, 3), np.uint8)
    mapping, flagged = {}, []
    for rid in np.unique(labels):
        if rid == 0:
            continue
        mask = (labels == rid).astype(np.uint8)
        interior = cv2.erode(mask, kernel, iterations=args.erode)
        if interior.sum() < 30:  # 太瘦,退回全區投票並直接列為待複核
            interior = mask
            thin = True
        else:
            thin = False
        votes = np.bincount(snapped[interior.astype(bool)], minlength=len(names))
        winner = int(votes.argmax())
        share = votes[winner] / votes.sum()
        if winner != default_idx:
            mapping[str(int(rid))] = names[winner]
        if thin or share < args.confidence:
            flagged.append((int(rid), names[winner], round(float(share), 2), int(mask.sum())))

    out = Path(args.out or (HERE / "out" / Path(args.labels).parent.name / "auto_mapping.json"))
    out.write_text(json.dumps(mapping, indent=1))
    print(f"自動上色 {len(mapping)} 區(非紙色);輸出: {out}")
    print(f"待複核 {len(flagged)} 區(信心 < {args.confidence} 或太瘦):")
    for rid, name, share, size in sorted(flagged, key=lambda f: -f[3])[:20]:
        print(f"  #{rid:<5} {name:<6} 信心 {share:<5} 面積 {size}")


def quantize(args):
    """極簡流程:整張圖逐像素吸附到四色色盤,不經分區。"""
    palette = load_palette()
    img = cv2.imread(str(args.input), cv2.IMREAD_COLOR)
    if img is None:
        sys.exit(f"讀不到圖: {args.input}")
    pal = np.array([hex_to_rgb(v)[::-1] for v in palette.values()], np.float32)
    d = np.linalg.norm(img[..., None, :].astype(np.float32) - pal, axis=-1)
    out = pal[d.argmin(-1)].astype(np.uint8)
    dst = Path(args.out or (HERE / "out" / (Path(args.input).stem + "_quantized.png")))
    dst.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(dst), out)
    print(f"輸出: {dst}")


def read_labels(path):
    enc = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if enc is None:
        sys.exit(f"讀不到 labels 圖: {path}(先跑 segment,並確認檔名)")
    return (
        enc[..., 2].astype(np.int32)
        | (enc[..., 1].astype(np.int32) << 8)
        | (enc[..., 0].astype(np.int32) << 16)
    )


def probe(args):
    labels = read_labels(args.labels)
    for x, y in zip(args.coords[::2], args.coords[1::2]):
        print(f"({x},{y}) -> region {labels[y, x]}")


def render(args):
    palette = load_palette()
    img = cv2.imread(str(args.input), cv2.IMREAD_COLOR)
    if img is None:
        sys.exit(f"讀不到線稿: {args.input}")
    labels = read_labels(args.labels)
    mapping = json.loads(Path(args.mapping).read_text())

    default = hex_to_rgb(palette[args.default])
    fill = np.zeros((*labels.shape, 3), np.uint8)
    fill[:] = default[::-1]  # BGR
    for rid, name in mapping.items():
        rgb = hex_to_rgb(palette[name] if name in palette else name)
        fill[labels == int(rid)] = rgb[::-1]

    out = (fill.astype(np.float32) * img.astype(np.float32) / 255).astype(np.uint8)

    if args.quantize:
        pal = np.array([hex_to_rgb(v)[::-1] for v in palette.values()], np.float32)
        d = np.linalg.norm(out[..., None, :].astype(np.float32) - pal, axis=-1)
        out = pal[d.argmin(-1)].astype(np.uint8)

    dst = Path(args.out or (HERE / "out" / (Path(args.input).stem + "_final.png")))
    cv2.imwrite(str(dst), out)
    print(f"輸出: {dst}")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("segment")
    s.add_argument("input")
    s.add_argument("--flat", action="store_true", help="平塗圖模式:同色連通區即區塊,自動產 mapping")
    s.add_argument("--dilate", type=int, default=2)
    s.add_argument("--min-area", type=int, default=40)
    s.add_argument("--thresh", type=int, default=-1, help="-1=Otsu")
    s.set_defaults(fn=segment)

    s = sub.add_parser("probe")
    s.add_argument("labels")
    s.add_argument("coords", type=int, nargs="+", help="x y [x y ...]")
    s.set_defaults(fn=probe)

    s = sub.add_parser("quantize")
    s.add_argument("input")
    s.add_argument("--out")
    s.set_defaults(fn=quantize)

    s = sub.add_parser("autocolor")
    s.add_argument("labels")
    s.add_argument("hint")
    s.add_argument("--blur", type=float, default=4.0)
    s.add_argument("--erode", type=int, default=3)
    s.add_argument("--confidence", type=float, default=0.6)
    s.add_argument("--default", default="paper")
    s.add_argument("--out")
    s.set_defaults(fn=autocolor)

    s = sub.add_parser("render")
    s.add_argument("input")
    s.add_argument("labels")
    s.add_argument("mapping")
    s.add_argument("--default", default="paper")
    s.add_argument("--quantize", action="store_true")
    s.add_argument("--out")
    s.set_defaults(fn=render)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
