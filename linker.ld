/* linker.ld - 高半区内核链接脚本
 * 布局（与 boot.asm 页表严格对应）：
 *   物理 0x200000            : .boot（恒等映射）
 *   虚拟 0xFFFFFFFF80200000  : 内核主体（物理 _boot_size + 0x200000 起）
 */

ENTRY(_start)

SECTIONS {
    phys = 0x200000;

    .boot 0x200000 : AT(0x200000) {
        *(.multiboot)
        *(.boot)
        . = ALIGN(0x200000);
    }
    _boot_size = SIZEOF(.boot);

    _kernel_vbase = 0xFFFFFFFF80000000;
    _kernel_offset = 0x200000;
    _kernel_lma = _boot_size + _kernel_offset;

    . = _kernel_vbase + _kernel_offset;
    _kernel_start = .;

    /* VMA 与 LMA 每段都做相同的 4KB 对齐，保证一一对应 */
    .text : AT(_kernel_lma) { *(.text) }
    . = ALIGN(0x1000);
    _kernel_lma = ALIGN(_kernel_lma + SIZEOF(.text), 0x1000);

    .rodata : AT(_kernel_lma) { *(.rodata) }
    . = ALIGN(0x1000);
    _kernel_lma = ALIGN(_kernel_lma + SIZEOF(.rodata), 0x1000);

    .data : AT(_kernel_lma) { *(.data) }
    . = ALIGN(0x1000);
    _kernel_lma = ALIGN(_kernel_lma + SIZEOF(.data), 0x1000);

    .bss : AT(_kernel_lma) { *(.bss) *(COMMON) }

    _kernel_end = .;
    _kernel_phys_end = _kernel_lma + SIZEOF(.bss);
}
