; inc/bootinfo.inc - 引导信息结构（由 boot.asm 填充，供内核各模块使用）

struc BootInfo
    .magic       resq 1   ; BOOTINFO_MAGIC
    .mem_entries resq 1   ; 内存映射条目数
    .mem_map     resq 1   ; MemEntry 数组指针
    .mem_total   resq 1   ; 可用物理内存总量（字节）
    .fb_addr     resq 1   ; 帧缓冲物理地址
    .fb_pitch    resd 1
    .fb_width    resd 1
    .fb_height   resd 1
    .fb_bpp      resd 1
    .fb_present  resd 1
    .fb_type     resd 1
    .rsdp        resq 1   ; ACPI RSDP 指针（可为 0）
    .cmdline     resq 1
endstruc

struc MemEntry
    .base resq 1
    .len  resq 1
    .type resd 1
    .pad  resd 1
endstruc

BOOTINFO_MAGIC equ 0x36D76289
BOOT_MEM_MAX   equ 64
