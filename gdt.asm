; gdt.asm - 完整 GDT + TSS（长模式）
; NASM >= 2.15 | QEMU >= 6.2

%include "memory.inc"

KCODE equ 0x08
KDATA equ 0x10
KTSS  equ 0x18
UCODE equ 0x28
UDATA equ 0x30

global load_gdt_tss
extern kernel_stack_top

section .data
align 16
gdt64:
    dq 0x0000000000000000               ; 0x00 NULL
    dq 0x00AF9A0000000000               ; 0x08 KCODE（64 位，DPL0）
    dq 0x00CF920000000000               ; 0x10 KDATA（DPL0）
    dq 0, 0                             ; 0x18 TSS（运行时填充）
    dq 0x00AFFA0000000000               ; 0x28 UCODE（64 位，DPL3，syscall 预留）
    dq 0x00CFF20000000000               ; 0x30 UDATA（DPL3，syscall 预留）
gdt64_end:

global gdt64_pointer
gdt64_pointer:
    dw gdt64_end - gdt64 - 1
    dq gdt64

section .bss
align 16
tss64:
    resb 104                            ; 64 位 TSS（104 字节）

section .text
load_gdt_tss:
    ; ---- 填充 TSS 描述符（0x18 处的两个 qword） ----
    mov rdx, tss64                      ; TSS 基址
    mov word [gdt64 + KTSS + 0], 103    ; limit[15:0]
    mov [gdt64 + KTSS + 2], dx          ; base[15:0]
    shr rdx, 16
    mov [gdt64 + KTSS + 4], dl          ; base[23:16]
    mov byte [gdt64 + KTSS + 5], 0x89   ; P=1, type=Available 64-bit TSS
    mov byte [gdt64 + KTSS + 6], 0x00   ; limit[19:16]+flags
    shr rdx, 8
    mov [gdt64 + KTSS + 7], dl          ; base[31:24]
    shr rdx, 24
    mov [gdt64 + KTSS + 8], edx         ; base[63:32]
    mov dword [gdt64 + KTSS + 12], 0    ; reserved

    ; ---- 初始化 TSS 字段 ----
    mov rax, kernel_stack_top
    mov [tss64 + 4], rax                ; rsp0（未来用户态中断切换栈）
    mov dword [tss64 + 100], 104        ; I/O 位图基址 = 104（无位图）

    lgdt [gdt64_pointer]
    mov ax, KDATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    push KCODE
    lea rax, [.reload]
    push rax
    retfq
.reload:
    mov ax, KTSS
    ltr ax
    ret

