; inc/vfs.inc - 虚拟文件结构

struc VFile
    .name resb 48
    .type resd 1
    .size resd 1
    .data resq 1
    .next resq 1
endstruc

VFT_RAW    equ 0
VFT_EXE    equ 1
VFT_BATCH  equ 2
VFT_APP    equ 3
VFT_DRIVER equ 4
