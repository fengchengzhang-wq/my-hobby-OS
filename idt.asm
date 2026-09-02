; idt.asm - 中断描述符表（256 向量全量初始化）+ 8259 PIC
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global init_idt, load_idt, init_pic, set_idt_entry
extern isr_table

section .rodata
align 16
idt_pointer:
    dw 256*16 - 1
    dq idt

section .bss
align 16
idt: times 256 resq 2

section .text

init_idt:
    ; 清零 IDT
    mov rdi, idt
    mov rcx, 256*2
    xor rax, rax
    rep stosq
    ; 用 isr_table 初始化全部 256 个向量
    xor rbx, rbx
.loop:
    mov rax, [isr_table + rbx*8]
    mov rdi, rbx
    mov rsi, rax
    call set_idt_entry
    inc rbx
    cmp rbx, 256
    jb .loop
    lidt [idt_pointer]
    ret

; void set_idt_entry(vector, handler)
set_idt_entry:
    push rax
    push rbx
    mov rbx, idt
    mov rax, rdi
    shl rax, 4
    add rbx, rax
    mov rax, rsi
    mov word [rbx], ax                  ; offset[15:0]
    mov word [rbx+2], 0x08              ; 段选择子（内核代码段）
    mov word [rbx+4], 0x8E00            ; P=1, DPL=0, 中断门
    shr rax, 16
    mov word [rbx+6], ax                ; offset[31:16]
    shr rax, 16
    mov dword [rbx+8], eax              ; offset[63:32]
    mov dword [rbx+12], 0               ; 保留
    pop rbx
    pop rax
    ret

load_idt:
    lidt [idt_pointer]
    ret

; 8259 PIC：主片 0x20，从片 0x28，仅开放 IRQ0/1/12
init_pic:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    ; 主片：仅 IRQ0/1/2；从片：仅 IRQ12
    mov al, 0xF8
    out 0x21, al
    mov al, 0xEF
    out 0xA1, al
    ret

