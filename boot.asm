; boot.asm - 双头引导：Multiboot1（QEMU -kernel）+ Multiboot2（GRUB ISO）
; NASM >= 2.15 | QEMU >= 6.2 (GRUB ISO 路径) / QEMU >= 8.0 (-kernel MB2 路径)
;
; 流程：
;   实模式入口 -> 32 位保护模式 -> 建立 4GB 恒等映射 + 高半区页表
;   -> PAE / LME / PG -> 远跳转 64 位跳板 -> 解析引导信息 -> main
;
; 内存布局（与 linker.ld 配套）：
;   物理 0x200000        : .boot 段（页表、临时栈、引导代码）
;   物理 _boot_size+2MB  : 内核 .text/.rodata/.data/.bss（高半区 0xFFFFFFFF80200000 起）

%include "memory.inc"
%include "bootinfo.inc"

extern _boot_size
extern main

BITS 32

; ===================== Multiboot2 头（GRUB 使用） =====================
section .multiboot
align 8
mb2_header_start:
    dd 0xE85250D6
    dd 0                                ; architecture: i386
    dd mb2_header_end - mb2_header_start
    dd 0x100000000 - (0xE85250D6 + (mb2_header_end - mb2_header_start))
    ; 信息请求 tag 5：帧缓冲（1024x768x32）
    align 8
    dw 5, 0, 20
    dd 1024, 768, 32
    ; 信息请求 tag 14：ACPI RSDP
    align 8
    dw 14, 0, 8
    ; 结束 tag
    align 8
    dw 0, 0, 8
mb2_header_end:

; ===================== Multiboot1 头（QEMU -kernel 使用） =====================
align 8
mb1_header_start:
    dd 0x1BADB002
    dd 0x00000007                       ; align | meminfo | videomode
    dd 0x100000000 - (0x1BADB002 + 0x00000007)
    dd 0, 0, 0, 0, 0                    ; reserved
    dd 0                                ; console type
    dd 1024, 768, 32                    ; 请求的视频模式（QEMU 6.2 不支持，走回退）
mb1_header_end:

; ===================== 早期数据 =====================
section .boot
align 8
temp_multiboot_info: dq 0
temp_multiboot_magic: dd 0

; ---- VBE 回退数据 ----
global vbe_fb_valid, vbe_fb_addr, vbe_pitch
vbe_fb_valid: db 0
vbe_fb_addr: dd 0
vbe_pitch: dw 0
vbe_enable_ret: dw 0

; ---- 早期 GDT（仅用于进入长模式；完整 GDT 由 gdt.asm 加载） ----
align 4
gdt_table_fixed:
    dq 0x0000000000000000               ; 0x00 null
    dq 0x00AF9A0000000000               ; 0x08 64 位代码段
    dq 0x00CF920000000000               ; 0x10 数据段
gdt_ptr_fixed:
    dw 0x0017
    dd gdt_table_fixed

; ---- 临时栈（16KB，进入长模式后切换为高半区内核栈） ----
align 16
stack_bottom:
    times 0x4000 db 0
stack_top:

; ---- 页表（.boot 段，恒等映射 4GB + 高半区 1GB） ----
align 0x1000
page_table_l4:      times 0x1000 db 0
page_table_p3:      times 0x1000 db 0
page_table_p2a:     times 0x1000 db 0
page_table_p2b:     times 0x1000 db 0
page_table_p2c:     times 0x1000 db 0
page_table_p2d:     times 0x1000 db 0
page_table_p3_high: times 0x1000 db 0
page_table_p2_high: times 0x1000 db 0

; ---- 32 位串口调试辅助（仅引导阶段） ----
serial_putc:
    push dx
    mov dx, 0x3F8
    out dx, al
    pop dx
    ret

serial_newline:
    mov al, 13
    call serial_putc
    mov al, 10
    call serial_putc
    ret

print_hex32:
    push ecx
    push eax
    mov ecx, 8
.loop:
    rol eax, 4
    push eax
    and al, 0x0F
    cmp al, 10
    jl .digit
    add al, 'A' - 10
    jmp .out
.digit:
    add al, '0'
.out:
    call serial_putc
    pop eax
    loop .loop
    pop eax
    pop ecx
    ret

; ===================== 引导入口 =====================
global _start
_start:
    cli
    mov esp, stack_top
    mov [temp_multiboot_magic], eax      ; 保存 loader 魔数（MB1=0x2BADB002 / MB2=0x36D76289）
    mov [temp_multiboot_info], ebx       ; 保存引导信息指针（物理地址）

    call vbe_fallback                    ; 尝试 VBE 设置 1024x768x32（失败无副作用）

    lgdt [gdt_ptr_fixed]
    call setup_paging

    ; CR4.PAE
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; EFER.LME
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    xor edx, edx
    wrmsr

    ; CR0.PG | CR0.PE
    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax

    ; 远跳转刷新 CS 进入 64 位模式
    jmp 0x08:trampoline_start

; ---- VBE 回退：Bochs VBE 寄存器接口（QEMU std VGA 原生支持） ----
; 端口 0x1CE=索引, 0x1CF=数据；线性帧缓冲固定在 0xE0000000
VBE_DISPI_INDEX   equ 0x1CE
VBE_DISPI_DATA    equ 0x1CF
VBE_DISPI_ID      equ 0x00
VBE_DISPI_XRES    equ 0x01
VBE_DISPI_YRES    equ 0x02
VBE_DISPI_BPP     equ 0x03
VBE_DISPI_ENABLE  equ 0x04
VBE_DISPI_VIRT_W  equ 0x06
VBE_DISPI_LFB     equ 0x40
VBE_LFB_ADDR      equ 0xE0000000

vbe_fallback:
    ; 探测：读取 ID 寄存器（Bochs VBE 返回 0xB0C4/0xB0C5）
    mov dx, VBE_DISPI_INDEX
    mov ax, VBE_DISPI_ID
    out dx, ax
    mov dx, VBE_DISPI_DATA
    in ax, dx
    cmp ax, 0xB0C4
    je .detected
    cmp ax, 0xB0C5
    je .detected
    ret
.detected:
    mov dx, VBE_DISPI_INDEX
    mov ax, VBE_DISPI_XRES
    out dx, ax
    mov dx, VBE_DISPI_DATA
    mov ax, 1024
    out dx, ax

    mov dx, VBE_DISPI_INDEX
    mov ax, VBE_DISPI_YRES
    out dx, ax
    mov dx, VBE_DISPI_DATA
    mov ax, 768
    out dx, ax

    mov dx, VBE_DISPI_INDEX
    mov ax, VBE_DISPI_BPP
    out dx, ax
    mov dx, VBE_DISPI_DATA
    mov ax, 32
    out dx, ax

    mov dx, VBE_DISPI_INDEX
    mov ax, VBE_DISPI_VIRT_W
    out dx, ax
    mov dx, VBE_DISPI_DATA
    mov ax, 1024
    out dx, ax

    ; 启用 + LFB
    mov dx, VBE_DISPI_INDEX
    mov ax, VBE_DISPI_ENABLE
    out dx, ax
    mov dx, VBE_DISPI_DATA
    mov ax, VBE_DISPI_LFB | 1
    out dx, ax
    ; 回读验证
    mov dx, VBE_DISPI_INDEX
    mov ax, VBE_DISPI_ENABLE
    out dx, ax
    mov dx, VBE_DISPI_DATA
    in ax, dx
    mov word [vbe_enable_ret], ax

    mov dword [vbe_fb_addr], VBE_LFB_ADDR
    mov word [vbe_pitch], 1024 * 4
    mov byte [vbe_fb_valid], 1
    ret

; ---- 建立页表 ----
setup_paging:
    ; PML4[0] -> 低半区 P3
    mov eax, page_table_p3
    or eax, 3
    mov [page_table_l4], eax
    ; PML4[511] -> 高半区 P3
    mov eax, page_table_p3_high
    or eax, 3
    mov [page_table_l4 + 511*8], eax

    ; P3[0..3] -> 4 张 P2（每张覆盖 1GB）
    mov eax, page_table_p2a
    or eax, 3
    mov [page_table_p3], eax
    mov eax, page_table_p2b
    or eax, 3
    mov [page_table_p3 + 8], eax
    mov eax, page_table_p2c
    or eax, 3
    mov [page_table_p3 + 16], eax
    mov eax, page_table_p2d
    or eax, 3
    mov [page_table_p3 + 24], eax

    ; 填充 4 张 P2：2MB 大页，覆盖物理 0..4GB（恒等映射）
    mov edi, page_table_p2a
    mov ecx, 2048
    mov eax, 0x83                       ; Present | Write | PS(2MB)
.fill_low:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    loop .fill_low

    ; 高半区：P3_high[510] -> P2_high（虚拟 0xFFFFFFFF80000000 起）
    mov eax, page_table_p2_high
    or eax, 3
    mov [page_table_p3_high + 510*8], eax
    ; P2_high：从物理 _boot_size 起映射 1GB（与 linker.ld 的 LMA 布局一致）
    mov edi, page_table_p2_high
    mov ecx, 512
    mov eax, _boot_size
    or eax, 0x83
.fill_high:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    loop .fill_high

    mov eax, page_table_l4
    mov cr3, eax
    ret

; ---- 64 位跳板（仍在 .boot 段，恒等映射可直接执行） ----
bits 64
global trampoline_start
trampoline_start:
    mov rax, long_mode_start
    jmp rax

; ===================== 长模式内核入口（高半区） =====================
section .text
bits 64

global long_mode_start
long_mode_start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    lea rsp, [kernel_stack_top]          ; 切换高半区内核栈

    mov rax, [temp_multiboot_info]       ; 物理地址，恒等映射可直接访问
    mov rdi, rax
    call parse_boot_info
    call boot_report

    jmp main
    cli
    hlt

; ===================== 引导信息解析 =====================
; parse_boot_info(rdi = 引导信息物理地址)
global parse_boot_info
parse_boot_info:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rax, [temp_multiboot_magic]
    cmp eax, 0x2BADB002
    je .mb1

    ; ---------------- Multiboot2 ----------------
    mov r12, rdi                         ; mbi 基址
    mov eax, [r12]                       ; 总大小
    mov r13, r12
    add r13, rax                         ; 结束地址
    lea rbx, [r12 + 8]                   ; 第一个 tag
.tag_loop:
    cmp rbx, r13
    jae .done
    movzx eax, word [rbx]                ; tag type
    mov r10d, [rbx + 4]                  ; tag size
    cmp eax, 1
    jne .t_cmd_done
    lea rax, [rbx + 8]
    mov [boot_info + BootInfo.cmdline], rax
    jmp .advance
.t_cmd_done:
    cmp eax, 6
    jne .t_mmap_done
    ; tag 6：内存映射
    ; 布局：type(2) flags(2) size(4) entry_size(4) entry_version(4) entries...
    mov r8d, [rbx + 8]                  ; entry_size（GRUB 通常为 24）
    mov ecx, r10d
    sub ecx, 16
    xor edx, edx
    mov eax, ecx
    div r8d
    mov ecx, eax                         ; 条目数
    cmp rcx, BOOT_MEM_MAX
    jbe .mmap_ok
    mov rcx, BOOT_MEM_MAX
.mmap_ok:
    mov [boot_info + BootInfo.mem_entries], rcx
    mov qword [boot_info + BootInfo.mem_map], boot_memmap
    lea rsi, [rbx + 16]
    mov rdi, boot_memmap
.mmap_copy:
    mov rax, [rsi]
    mov [rdi], rax
    mov rax, [rsi + 8]
    mov [rdi + 8], rax
    mov eax, [rsi + 16]
    mov [rdi + 16], eax
    add rsi, r8
    add rdi, 24
    loop .mmap_copy
    mov rdi, boot_memmap
    mov rsi, [boot_info + BootInfo.mem_entries]
    call mmap_sum
    jmp .advance
.t_mmap_done:
    cmp eax, 8
    jne .t_fb_done
    ; tag 8：帧缓冲
    ; 布局：addr(8) pitch(4) width(4) height(4) bpp(1) type(1) reserved(1)
    mov rax, [rbx + 8]
    mov [boot_info + BootInfo.fb_addr], rax
    mov eax, [rbx + 16]
    mov [boot_info + BootInfo.fb_pitch], eax
    mov eax, [rbx + 20]
    mov [boot_info + BootInfo.fb_width], eax
    mov eax, [rbx + 24]
    mov [boot_info + BootInfo.fb_height], eax
    movzx eax, byte [rbx + 28]
    mov [boot_info + BootInfo.fb_bpp], eax
    movzx eax, byte [rbx + 29]
    mov [boot_info + BootInfo.fb_type], eax
    ; 仅接受 32bpp 线性图形缓冲
    cmp dword [boot_info + BootInfo.fb_bpp], 32
    jne .advance
    cmp dword [boot_info + BootInfo.fb_type], 2
    jne .advance
    mov dword [boot_info + BootInfo.fb_present], 1
    jmp .advance
.t_fb_done:
    cmp eax, 14
    jne .advance
    ; tag 14：RSDP
    mov rax, [rbx + 8]
    mov [boot_info + BootInfo.rsdp], rax
.advance:
    mov eax, r10d
    add rax, 7
    and rax, ~7
    add rbx, rax
    jmp .tag_loop

    ; ---------------- Multiboot1 ----------------
.mb1:
    mov r12, rdi
    mov eax, [r12]                       ; flags
    test eax, 1 << 2
    jz .mb1_nocmd
    mov rax, [r12 + 16]
    mov [boot_info + BootInfo.cmdline], rax
.mb1_nocmd:
    test eax, 1 << 6
    jz .mb1_nommap
    ; mmap_addr @ +48, mmap_length @ +44；条目：size(4)/base(8)/len(8)/type(4)
    mov r14, [r12 + 48]
    mov r13, [r12 + 44]
    mov r15, r14
    add r15, r13                         ; 结束地址
    xor r9d, r9d                         ; 条目数
.mb1_mmap_loop:
    cmp r14, r15
    jae .mb1_mmap_done
    mov eax, [r14]
    test eax, eax
    jz .mb1_mmap_done
    cmp r9d, BOOT_MEM_MAX
    jae .mb1_mmap_next
    mov rdi, r9
    imul rdi, 24
    add rdi, boot_memmap
    mov rax, [r14 + 4]
    mov [rdi + MemEntry.base], rax
    mov rax, [r14 + 12]
    mov [rdi + MemEntry.len], rax
    mov ecx, [r14 + 20]
    mov [rdi + MemEntry.type], ecx
    inc r9d
.mb1_mmap_next:
    mov eax, [r14]
    add r14, rax
    jmp .mb1_mmap_loop
.mb1_mmap_done:
    mov [boot_info + BootInfo.mem_entries], r9
    mov qword [boot_info + BootInfo.mem_map], boot_memmap
    mov rdi, boot_memmap
    mov rsi, r9
    call mmap_sum
.mb1_nommap:
    mov eax, [r12]
    test eax, 1 << 12
    jz .done
    ; 帧缓冲字段 @ +88（QEMU 6.2 不提供，兼容性保留）
    mov rax, [r12 + 88]
    mov [boot_info + BootInfo.fb_addr], rax
    mov eax, [r12 + 96]
    mov [boot_info + BootInfo.fb_pitch], eax
    mov eax, [r12 + 100]
    mov [boot_info + BootInfo.fb_width], eax
    mov eax, [r12 + 104]
    mov [boot_info + BootInfo.fb_height], eax
    movzx eax, byte [r12 + 108]
    mov [boot_info + BootInfo.fb_bpp], eax
    movzx eax, byte [r12 + 109]
    mov [boot_info + BootInfo.fb_type], eax
    cmp dword [boot_info + BootInfo.fb_bpp], 32
    jne .done
    cmp dword [boot_info + BootInfo.fb_type], 2
    jne .done
    mov dword [boot_info + BootInfo.fb_present], 1
.done:
    ; ---- VBE 回退：loader 未提供 32bpp 线性帧缓冲时使用 VBE 结果 ----
    cmp dword [boot_info + BootInfo.fb_present], 0
    jne .vbe_done
    cmp byte [vbe_fb_valid], 0
    je .vbe_done
    movzx eax, byte [vbe_fb_valid]
    mov eax, [vbe_fb_addr]
    mov [boot_info + BootInfo.fb_addr], rax
    movzx eax, word [vbe_pitch]
    mov [boot_info + BootInfo.fb_pitch], eax
    mov dword [boot_info + BootInfo.fb_width], 1024
    mov dword [boot_info + BootInfo.fb_height], 768
    mov dword [boot_info + BootInfo.fb_bpp], 32
    mov dword [boot_info + BootInfo.fb_type], 2
    mov dword [boot_info + BootInfo.fb_present], 1
.vbe_done:
    mov dword [boot_info + BootInfo.magic], BOOTINFO_MAGIC
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- mmap_sum(rdi=map, rsi=count)：统计可用内存总量 ----
mmap_sum:
    push rbx
    push rcx
    push rsi
    xor rbx, rbx
    mov rcx, rsi
.loop:
    test rcx, rcx
    jz .done
    cmp dword [rdi + MemEntry.type], 1
    jne .next
    add rbx, [rdi + MemEntry.len]
.next:
    add rdi, 24
    dec rcx
    jmp .loop
.done:
    mov [boot_info + BootInfo.mem_total], rbx
    pop rsi
    pop rcx
    pop rbx
    ret

; ===================== 引导报告（串口） =====================
boot_report:
    push rax
    push rbx
    call kputc_marker
    ; "BOOT: "
    lea rdi, [msg_boot]
    call kprint_str
    ; loader 类型
    mov eax, [temp_multiboot_magic]
    cmp eax, 0x2BADB002
    jne .mb2
    lea rdi, [msg_mb1]
    call kprint_str
    jmp .fb
.mb2:
    lea rdi, [msg_mb2]
    call kprint_str
.fb:
    mov eax, [boot_info + BootInfo.fb_present]
    test eax, eax
    jz .nofb
    lea rdi, [msg_fb_ok]
    call kprint_str
    mov rax, [boot_info + BootInfo.fb_addr]
    mov rdi, rax
    call khex64
    lea rdi, [msg_fb_wh]
    call kprint_str
    mov rax, [boot_info + BootInfo.fb_width]
    mov rdi, rax
    call khex64
    mov al, 'x'
    mov dx, 0x3F8
    out dx, al
    mov rax, [boot_info + BootInfo.fb_height]
    mov rdi, rax
    call khex64
    lea rdi, [msg_fb_pitch]
    call kprint_str
    mov rax, [boot_info + BootInfo.fb_pitch]
    mov rdi, rax
    call khex64
    lea rdi, [msg_fb_bpp]
    call kprint_str
    mov rax, [boot_info + BootInfo.fb_bpp]
    mov rdi, rax
    call khex64
    lea rdi, [msg_fb_type]
    call kprint_str
    mov rax, [boot_info + BootInfo.fb_type]
    mov rdi, rax
    call khex64
    lea rdi, [msg_fb_en]
    call kprint_str
    movzx rax, word [vbe_enable_ret]
    mov rdi, rax
    call khex64
    jmp .mmap
.nofb:
    lea rdi, [msg_fb_no]
    call kprint_str
.mmap:
    lea rdi, [msg_mmap]
    call kprint_str
    mov rax, [boot_info + BootInfo.mem_entries]
    mov rdi, rax
    call khex64
    lea rdi, [msg_total]
    call kprint_str
    mov rax, [boot_info + BootInfo.mem_total]
    mov rdi, rax
    call khex64
    call knewline
    pop rbx
    pop rax
    ret

; ---- 高半区串口辅助（64 位代码专用，避免跨 2GB 相对跳转） ----
kputc_marker:
    mov al, '>'
    call kthr_wait
    mov dx, 0x3F8
    out dx, al
    ret

kprint_str:                             ; rdi = 字符串（高半区）
    push rsi
    mov rsi, rdi
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    push rax
    call kthr_wait
    pop rax
    mov dx, 0x3F8
    out dx, al
    inc rsi
    jmp .loop
.done:
    pop rsi
    ret

khex64:                                 ; rdi = 值
    push rax
    push rcx
    mov rax, rdi
    mov rcx, 16
.loop:
    rol rax, 4
    push rax
    and al, 0x0F
    cmp al, 10
    jl .digit
    add al, 'A' - 10
    jmp .out
.digit:
    add al, '0'
.out:
    push rax
    call kthr_wait
    pop rax
    mov dx, 0x3F8
    out dx, al
    pop rax
    loop .loop
    pop rcx
    pop rax
    ret

knewline:
    push rax
    call kthr_wait
    mov al, 13
    push rax
    call kthr_wait
    pop rax
    mov dx, 0x3F8
    out dx, al
    call kthr_wait
    mov al, 10
    out dx, al
    pop rax
    ret

kthr_wait:
    push rax
    push rdx
.wait:
    mov dx, 0x3F8 + 5
    in al, dx
    test al, 0x20
    jz .wait
    pop rdx
    pop rax
    ret

section .rodata
msg_boot   db "BOOT: loader=", 0
msg_mb1    db "Multiboot1", 0
msg_mb2    db "Multiboot2", 0
msg_fb_ok  db " fb=", 0
msg_fb_wh  db " size=", 0
msg_fb_pitch db " pitch=", 0
msg_fb_bpp db " bpp=", 0
msg_fb_type db " type=", 0
msg_fb_en   db " enable=", 0
msg_fb_no  db " fb=none(static-fallback)", 0
msg_mmap   db " mmap=", 0
msg_total  db " total=", 0

; ===================== 引导信息与内核栈 =====================
section .bss
align 16
global boot_info
boot_info: resb BootInfo_size

global boot_memmap
boot_memmap: times BOOT_MEM_MAX * 3 resq 1

global kernel_stack_top
kernel_stack:
    resb 16384
kernel_stack_top:
