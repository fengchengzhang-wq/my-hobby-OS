; inc/memory.inc - 内存布局与核心常量
; NASM >= 2.15 | QEMU >= 6.2 (GRUB ISO) / >= 8.0 (-kernel MB2)

KERNEL_VBASE    equ 0xFFFFFFFF80000000
KERNEL_OFFSET   equ 0x200000          ; .text 相对 KERNEL_VBASE 的偏移（2MB 对齐，与 boot 页表一致）
KERNEL_BASE     equ KERNEL_VBASE
KERNEL_FB_VBASE equ 0xFFFFFFFFA0000000 ; 备用帧缓冲高半区映射地址

PAGE_SIZE       equ 0x1000
PAGE_MASK       equ ~0xFFF

