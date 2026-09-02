#!/usr/bin/env python3
"""从 Linux console PSF 字体提取 ASCII 32-126 的 8x16 字形，生成 drivers/font.asm。

用法：python3 tools/genfont.py <psf-font> [输出文件]
默认字体：/usr/share/consolefonts/Lat15-Fixed16.psf.gz
"""

import gzip
import struct
import sys


def load_psf(path):
    raw = open(path, "rb").read()
    if raw[:4] == b"\x72\xb5\x4a\x86":  # PSF2
        (
            version,
            header_size,
            flags,
            num_glyphs,
            bytes_per_glyph,
            height,
            width,
        ) = struct.unpack("<IIIIIII", raw[4:32])
        glyphs = raw[header_size : header_size + num_glyphs * bytes_per_glyph]
        return width, height, bytes_per_glyph, glyphs
    if raw[:2] == b"\x36\x04":  # PSF1
        mode, charsize = raw[2], raw[3]
        num_glyphs = 512 if mode & 0x01 else 256
        glyphs = raw[4 : 4 + num_glyphs * charsize]
        return 8, charsize, charsize, glyphs
    raise ValueError("不是 PSF 字体文件")


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/consolefonts/Lat15-Fixed16.psf.gz"
    out = sys.argv[2] if len(sys.argv) > 2 else "drivers/font.asm"
    width, height, stride, glyphs = load_psf(src)
    if width != 8 or height != 16:
        sys.stderr.write(f"需要 8x16 字体，实际 {width}x{height}\n")
        sys.exit(1)

    lines = [
        "; drivers/font.asm - 8x16 位图字体（ASCII 32-126）",
        "; 数据来源: Lat15-Fixed16 (Linux console, GPL2+)",
        "; 由 tools/genfont.py 生成，请勿手工编辑",
        "[bits 64]",
        "global font8x16",
        "",
        "section .rodata",
        "align 16",
        "font8x16:",
    ]
    for ch in range(32, 127):
        off = ch * stride
        rows = glyphs[off : off + 16]
        if len(rows) < 16:
            sys.stderr.write(f"字形 {ch} 数据不足\n")
            sys.exit(1)
        comment = chr(ch) if 32 <= ch < 127 and chr(ch) not in ("'",) else " "
        lines.append(f"    ; '{comment}' ({ch})")
        for row in rows:
            lines.append(f"    db 0x{row:02X}")
    lines.append("")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"生成 {out}：{126-32+1} 个字形 x 16 行")


if __name__ == "__main__":
    main()
