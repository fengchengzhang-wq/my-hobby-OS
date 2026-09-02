#!/usr/bin/env python3
"""从 Noto Sans CJK 生成 16x16 简体中文点阵字体（GB2312 一级字 + 标点）。

用法：python3 tools/genfont_cjk.py [输出文件] [字体文件]
默认输出：assets/cjk16.bin
默认字体：/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc (SC index 2)

输出二进制布局：
  u32 count（小端）
  count × u32 Unicode 码点（小端，升序）
  count × 32 字节位图（每字 16 行 × 2 字节；每行高字节 = 左 8 列）
"""

import struct
import sys
from PIL import Image, ImageDraw, ImageFont


DEFAULT_FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
DEFAULT_OUT = "assets/cjk16.bin"

# 除 GB2312 一级字外，额外收进的常用中文标点/符号
EXTRA = {ord(ch) for ch in "，。、；：？！“”‘’（）《》〈〉【】〔〕…—～·￥×÷＝＋－＿"}
EXTRA_RANGES = ((0x3000, 0x303F), (0xFF01, 0xFF5E))


def collect_chars(root="."):
    """GB2312 一级汉字（区 16..55）+ 标点 + 工程源码里出现的中文字符。"""
    chars = set(EXTRA)
    # 一级汉字：Unicode 中可编码为 GB2312 且首字节在 0xB0..0xD7
    for cp in range(0x4E00, 0x9FA6):
        try:
            b = chr(cp).encode("gb2312")
        except UnicodeEncodeError:
            continue
        if 0xB0 <= b[0] <= 0xD7:
            chars.add(cp)
    for lo, hi in EXTRA_RANGES:
        for cp in range(lo, hi + 1):
            try:
                chr(cp).encode("gb2312")
                chars.add(cp)
            except UnicodeEncodeError:
                pass
    # 工程文件中的中文字符（注释与界面串都收进来，便于日后直接用）
    import os
    for dirpath, _dirs, files in os.walk(root):
        for name in files:
            if not name.endswith((".asm", ".md", ".bat", ".inc", ".py", ".txt")):
                continue
            path = os.path.join(dirpath, name)
            try:
                text = open(path, encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            for ch in text:
                o = ord(ch)
                if 0x4E00 <= o <= 0x9FFF or 0x3000 <= o <= 0x303F:
                    chars.add(o)
    return sorted(chars)


def render_glyph(draw_canvas, ch, font, size):
    """把单个汉字画到 size*size 灰度画布（黑底白字）。"""
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    # 留 1/16 边距，避免笔画顶边
    d.text((0, 0), ch, font=font, fill=255)
    return img


def downsample(img, factor=3, threshold=88):
    """3x3 -> 1x1：块平均灰度超过阈值记为笔画点。"""
    out = []
    w, h = img.size
    for y in range(0, h - factor + 1, factor):
        row = 0
        for x in range(0, w - factor + 1, factor):
            s = 0
            for yy in range(factor):
                for xx in range(factor):
                    s += img.getpixel((x + xx, y + yy))
            on = 1 if s / (factor * factor) >= threshold else 0
            row = (row << 1) | on
        out.append(row)
    return out  # 16 个 16 位行值


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    font_path = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_FONT
    codes = collect_chars()
    font = ImageFont.truetype(font_path, 48, index=2)

    blob = bytearray()
    blob += struct.pack("<I", len(codes))
    for cp in codes:
        blob += struct.pack("<I", cp)
    for cp in codes:
        ch = chr(cp)
        img = render_glyph(None, ch, font, 48)
        rows = downsample(img, 3, 92)
        for r in rows:
            blob += bytes([(r >> 8) & 0xFF, r & 0xFF])
    with open(out, "wb") as f:
        f.write(blob)
    print(f"生成 {out}：{len(codes)} 字 x 32B = {len(blob)} 字节")


if __name__ == "__main__":
    main()
