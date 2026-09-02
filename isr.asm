; isr.asm - 异常 stub + IRQ 分发框架
; 异常：CPU 压栈 [err?][RIP..]，stub 补压 vector/err，保存 15 个通用寄存器后
;       调用 exception_handler(vec, err, frame)
; IRQ ：stub 压 0/vector，保存寄存器后调用 irq_dispatch(vector, frame)，
;       统一发送 EOI 后 iretq
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "regs.inc"
%include "irq.inc"

; ===================== 异常 stub（0-31） =====================
%macro ISR_STUB 1
%if %1 = 8 || %1 = 10 || %1 = 11 || %1 = 12 || %1 = 13 || %1 = 14 || %1 = 17
global isr%1
isr%1:
    cli
    push %1                             ; CPU 已压错误码
    jmp isr_common
%else
global isr%1
isr%1:
    cli
    push 0
    push %1
    jmp isr_common
%endif
%endmacro

%assign vec 0
%rep 32
ISR_STUB vec
%assign vec vec+1
%endrep

; ===================== IRQ stub（0-15） =====================
%macro IRQ_STUB 1
global irq%1
irq%1:
    cli
    push 0
    push 0x20 + %1
    jmp irq_common
%endmacro

%assign vec 0
%rep 16
IRQ_STUB vec
%assign vec vec+1
%endrep

; ===================== 未处理向量默认入口 =====================
isr_unhandled:
    cli
    push 0
    push 0xFF
    jmp isr_common

; ===================== 向量表（供 idt.asm 全量初始化） =====================
section .data
global isr_table
isr_table:
%assign vec 0
%rep 256
%if vec < 32
    dq isr%+vec
%elif vec < 48
    %assign irqvec vec-32
    dq irq%+irqvec
%else
    dq isr_unhandled
%endif
%assign vec vec+1
%endrep

; ===================== 异常公共入口 =====================
section .text
isr_common:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov rdi, [rsp + RegFrame.vec]       ; vector
    mov rsi, [rsp + RegFrame.err]       ; error code
    mov rdx, rsp                        ; RegFrame*
    call exception_handler              ; 不返回
    cli
    hlt

; ===================== IRQ 公共入口 =====================
irq_common:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    mov rdi, [rsp + RegFrame.vec]
    mov rsi, rsp
    call irq_dispatch

    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    add rsp, 16                         ; 移除 vector + err
    iretq

; ===================== IRQ 注册表 =====================
section .data
irq_handler_table: times 16 dq 0
irq_ctx_table:     times 16 dq 0

section .text

; int irq_register(vector, handler, ctx)
global irq_register, irq_unregister, irq_dispatch
irq_register:
    sub rdi, IRQ_TIMER
    cmp rdi, 16
    jae .fail
    mov [irq_handler_table + rdi*8], rsi
    mov [irq_ctx_table + rdi*8], rdx
    xor rax, rax
    ret
.fail:
    mov rax, -1
    ret

irq_unregister:
    sub rdi, IRQ_TIMER
    cmp rdi, 16
    jae .fail
    mov qword [irq_handler_table + rdi*8], 0
    xor rax, rax
    ret
.fail:
    mov rax, -1
    ret

; void irq_dispatch(vector, frame)
irq_dispatch:
    push rbx
    push r12
    mov rbx, rdi                        ; vector
    mov r12, rsi                        ; frame
    lea rax, [rbx - IRQ_TIMER]
    mov rdx, [irq_handler_table + rax*8]
    test rdx, rdx
    jz .eoi
    ; handler(vector, frame)
    mov rdi, rbx
    mov rsi, r12
    call rdx
.eoi:
    ; 发送 EOI
    cmp rbx, IRQ_SLAVE
    jb .master
    mov al, 0x20
    out 0xA0, al
.master:
    mov al, 0x20
    out 0x20, al
    pop r12
    pop rbx
    ret

; ===================== 异常处理 =====================
; void exception_handler(vector, err, frame)
global exception_handler
extern serial_write_string, serial_write_hex64, serial_newline
extern panic_regs
extern target_base, target_pitch

exception_handler:
    push r12
    push r13
    push r14
    mov r12, rdi                        ; vector
    mov r13, rsi                        ; error code
    mov r14, rdx                        ; RegFrame*
    mov rdi, msg_exception
    call serial_write_string
    mov rdi, msg_vec
    call serial_write_string
    mov rdi, r12
    call serial_write_hex64
    mov rdi, msg_err
    call serial_write_string
    mov rdi, r13
    call serial_write_hex64
    mov rdi, msg_rip
    call serial_write_string
    mov rdi, [r14 + RegFrame.rip]
    call serial_write_hex64
    mov rdi, msg_cs
    call serial_write_string
    mov rdi, [r14 + RegFrame.cs]
    call serial_write_hex64
    mov rdi, msg_rsp
    call serial_write_string
    mov rdi, [r14 + RegFrame.rsp]
    call serial_write_hex64
    ; 关键寄存器（便于定位）
    mov rdi, msg_rdi
    call serial_write_string
    mov rdi, [r14 + RegFrame.rdi]
    call serial_write_hex64
    mov rdi, msg_rsi
    call serial_write_string
    mov rdi, [r14 + RegFrame.rsi]
    call serial_write_hex64
    mov rdi, msg_rcx
    call serial_write_string
    mov rdi, [r14 + RegFrame.rcx]
    call serial_write_hex64
    mov rdi, msg_r8
    call serial_write_string
    mov rdi, [r14 + RegFrame.r8]
    call serial_write_hex64
    mov rdi, msg_r9
    call serial_write_string
    mov rdi, [r14 + RegFrame.r9]
    call serial_write_hex64
    mov rdi, msg_r13
    call serial_write_string
    mov rdi, [r14 + RegFrame.r13]
    call serial_write_hex64
    mov rdi, msg_r15
    call serial_write_string
    mov rdi, [r14 + RegFrame.r15]
    call serial_write_hex64
    mov rdi, msg_rbx
    call serial_write_string
    mov rdi, [r14 + RegFrame.rbx]
    call serial_write_hex64
    mov rdi, msg_rax
    call serial_write_string
    mov rdi, [r14 + RegFrame.rax]
    call serial_write_hex64
    mov rdi, msg_rdx
    call serial_write_string
    mov rdi, [r14 + RegFrame.rdx]
    call serial_write_hex64
    mov rdi, msg_tbase
    call serial_write_string
    mov rdi, [target_base]
    call serial_write_hex64
    mov rdi, msg_tpitch
    call serial_write_string
    movzx rdi, word [target_pitch]
    call serial_write_hex64
    ; #PF 附带 CR2
    cmp r12, 14
    jne .no_cr2
    mov rdi, msg_cr2
    call serial_write_string
    mov rax, cr2
    mov rdi, rax
    call serial_write_hex64
.no_cr2:
    call serial_newline
    mov rdi, msg_panic_title
    mov rsi, r14
    call panic_regs                     ; 不返回
    cli
    hlt

section .rodata
msg_exception   db "!!! EXCEPTION !!! ", 0
msg_panic_title db "CPU Exception", 0
msg_vec         db " vector=", 0
msg_err         db " err=", 0
msg_rip         db " rip=", 0
msg_cs          db " cs=", 0
msg_rsp         db " rsp=", 0
msg_rdi         db " rdi=", 0
msg_rsi         db " rsi=", 0
msg_rcx         db " rcx=", 0
msg_r8          db " r8=", 0
msg_r9          db " r9=", 0
msg_r13         db " r13=", 0
msg_r15         db " r15=", 0
msg_rbx         db " rbx=", 0
msg_rax         db " rax=", 0
msg_rdx         db " rdx=", 0
msg_tbase       db " tbase=", 0
msg_tpitch      db " tpitch=", 0
msg_cr2         db " cr2=", 0
