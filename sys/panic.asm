; sys/panic.asm - 内核 Panic：蓝屏 + 寄存器 dump + 串口日志
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "regs.inc"

global panic, panic_regs

extern fb_clear, fb_draw_string, fb_reset_target, fb_ready
extern serial_write_string, serial_write_hex64, serial_newline
extern format_hex64

PANIC_BG   equ 0xFF000060
PANIC_FG   equ 0xFFFFFFFF
PANIC_HDR  equ 0xFFFF9090

section .bss
panic_line: resb 40

section .text

; void panic(msg)
panic:
    push rsi
    push rdi
    mov rsi, rdi
    mov rdi, 0
    call panic_regs_internal
    pop rdi
    pop rsi
    ret

; void panic_regs(msg, frame)
panic_regs:
    call panic_regs_internal
    ret

panic_regs_internal:                    ; rdi=msg, rsi=frame（可空）
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    mov r12, rdi                        ; msg
    mov r13, rsi                        ; frame

    ; ---- 串口日志 ----
    mov rdi, msg_panic
    call serial_write_string
    mov rdi, r12
    call serial_write_string
    call serial_newline
    test r13, r13
    jz .serial_done
    mov rdi, msg_vec
    call serial_write_string
    mov rdi, [r13 + RegFrame.vec]
    call serial_write_hex64
    mov rdi, msg_err
    call serial_write_string
    mov rdi, [r13 + RegFrame.err]
    call serial_write_hex64
    call serial_newline
    mov rdi, msg_rip
    call serial_write_string
    mov rdi, [r13 + RegFrame.rip]
    call serial_write_hex64
    mov rdi, msg_cr2
    call serial_write_string
    mov rax, cr2
    mov rdi, rax
    call serial_write_hex64
    call serial_newline
.serial_done:

    ; ---- 蓝屏 ----
    cmp dword [fb_ready], 0
    je .halt
    call fb_reset_target
    mov edi, PANIC_BG
    call fb_clear

    mov rdi, 20
    mov rsi, 30
    lea rdx, [msg_panic_hdr]
    mov ecx, PANIC_HDR
    mov r8d, PANIC_BG
    call fb_draw_string

    mov rdi, 20
    mov rsi, 55
    mov rdx, r12
    mov ecx, PANIC_FG
    mov r8d, PANIC_BG
    call fb_draw_string

    test r13, r13
    jz .halt
    ; 寄存器 dump：16 个（R15..RAX + RSP），每行 4 个
    xor rbx, rbx                        ; 序号 0..15
.dump_loop:
    cmp rbx, 16
    jae .dump_done
    lea rax, [reg_names]
    mov rsi, [rax + rbx*8]
    lea rax, [reg_offsets]
    mov rcx, [rax + rbx*8]
    ; 行/列
    mov rax, rbx
    xor edx, edx
    mov r8, 4
    div r8                              ; rax=行, rdx=列
    imul rax, 20
    add rax, 85
    mov r9, rax                         ; y
    imul rdx, 200
    add rdx, 20
    mov r10, rdx                        ; x
    ; 寄存器名
    mov rdi, r10
    mov rdx, rsi
    mov rsi, r9
    mov ecx, PANIC_FG
    mov r8d, PANIC_BG
    call fb_draw_string
    ; 值
    mov rdi, panic_line
    mov rsi, [r13 + rcx]
    call format_hex64
    mov rdi, r10
    add rdi, 64
    mov rsi, r9
    lea rdx, [panic_line]
    mov ecx, PANIC_FG
    mov r8d, PANIC_BG
    call fb_draw_string
    inc rbx
    jmp .dump_loop
.dump_done:

    ; 底部提示
    mov rdi, 20
    mov rsi, 700
    lea rdx, [msg_halted]
    mov ecx, PANIC_FG
    mov r8d, PANIC_BG
    call fb_draw_string

.halt:
    cli
.halt_loop:
    hlt
    jmp .halt_loop

section .rodata
msg_panic     db "!!! KERNEL PANIC: ", 0
msg_panic_hdr db "KERNEL PANIC", 0
msg_vec       db "vector=", 0
msg_err       db " err=", 0
msg_rip       db " rip=", 0
msg_cr2       db " cr2=", 0
msg_halted    db "System halted. Check serial log.", 0

section .data
reg_names:
    dq str_r15, str_r14, str_r13, str_r12, str_r11, str_r10, str_r9, str_r8
    dq str_rbp, str_rdi, str_rsi, str_rdx, str_rcx, str_rbx, str_rax, str_rsp
reg_offsets:
    dq RegFrame.r15, RegFrame.r14, RegFrame.r13, RegFrame.r12
    dq RegFrame.r11, RegFrame.r10, RegFrame.r9,  RegFrame.r8
    dq RegFrame.rbp, RegFrame.rdi, RegFrame.rsi, RegFrame.rdx
    dq RegFrame.rcx, RegFrame.rbx, RegFrame.rax, RegFrame.rsp
section .rodata
str_r15 db "R15", 0
str_r14 db "R14", 0
str_r13 db "R13", 0
str_r12 db "R12", 0
str_r11 db "R11", 0
str_r10 db "R10", 0
str_r9  db "R9 ", 0
str_r8  db "R8 ", 0
str_rbp db "RBP", 0
str_rdi db "RDI", 0
str_rsi db "RSI", 0
str_rdx db "RDX", 0
str_rcx db "RCX", 0
str_rbx db "RBX", 0
str_rax db "RAX", 0
str_rsp db "RSP", 0
