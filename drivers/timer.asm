; drivers/timer.asm - PIT 定时器（100Hz）+ 系统时钟 API
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "irq.inc"
%include "driver.inc"

global init_timer, timer_handler, get_ticks, timer_sleep, uptime

extern irq_register
extern driver_register

section .bss
global tick_count
tick_count: resq 1

section .data
global timer_driver
timer_driver:
    istruc Driver
        at Driver.name,  dq timer_name
        at Driver.kind,  dd DRV_KIND_TIMER
        at Driver.state, dd DRV_STATE_REGISTERED
        at Driver.init,  dq init_timer
        at Driver.fini,  dq 0
        at Driver.ops,   dq 0
        at Driver.priv,  dq 0
        at Driver.next,  dq 0
    iend

section .rodata
timer_name db "pit", 0

section .text

init_timer:
    ; PIT 频率 ~100Hz（1193180 / 100 = 11931）
    mov al, 0x36                        ; 通道 0，模式 3，先低后高字节
    out 0x43, al
    mov ax, 11931
    out 0x40, al
    mov al, ah
    out 0x40, al
    mov qword [tick_count], 0
    ; 注册 IRQ0 处理函数
    mov rdi, IRQ_TIMER
    lea rsi, [timer_handler]
    xor rdx, rdx
    call irq_register
    ; 自注册驱动
    lea rdi, [timer_driver]
    call driver_register
    ret

; 定时器中断处理（由 irq_dispatch 调用，无需 EOI）
timer_handler:
    add qword [tick_count], 1
    ret

; uint64 get_ticks()
get_ticks:
    mov rax, [tick_count]
    ret

; void timer_sleep(ms)：忙等待
timer_sleep:
    push rbx
    mov rbx, [tick_count]
    mov rax, rdi
    xor edx, edx
    mov rcx, 10
    div rcx                             ; ms -> ticks
    test rax, rax
    jz .done
    add rbx, rax
.wait:
    mov rax, [tick_count]
    cmp rax, rbx
    jb .wait
    pause
    jmp .wait_check
.wait_check:
    mov rax, [tick_count]
    cmp rax, rbx
    jb .wait
.done:
    pop rbx
    ret

; void uptime(Uptime*)：{minutes, seconds}（qword）
uptime:
    mov rax, [tick_count]
    xor edx, edx
    mov rcx, 100
    div rcx                             ; 秒
    xor edx, edx
    mov rcx, 60
    div rcx                             ; rax=分, rdx=秒
    mov [rdi], rax
    mov [rdi + 8], rdx
    ret

