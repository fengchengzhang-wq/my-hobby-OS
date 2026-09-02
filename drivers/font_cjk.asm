; drivers/font_cjk.asm - 16x16 简体中文点阵字库（GB2312 一级字 + 常用标点）
; 数据由 tools/genfont_cjk.py 生成（Noto Sans CJK SC 降采样），勿手工编辑
[bits 64]

section .rodata
align 4
global cjk16_bin
cjk16_bin:
    incbin "assets/cjk16.bin"
