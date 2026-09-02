; drivers/rtc.asm - CMOS RTC 时钟驱动
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "driver.inc"
%include "syscall.inc"

global init_rtc, rtc_read, rtc_get_time

extern driver_register

section .data
global rtc_driver
rtc_driver:
    istruc Driver
        at Driver.name,  dq rtc_name
        at Driver.kind,  dd DRV_KIND_MISC
        at Driver.state, dd DRV_STATE_REGISTERED
        at Driver.init,  dq init_rtc
        at Driver.fini,  dq 0
        at Driver.ops,   dq 0
        at Driver.priv,  dq 0
        at Driver.next,  dq 0
    iend

section .rodata
rtc_name db "cmos-rtc", 0

section .text

init_rtc:
    lea rdi, [rtc_driver]
    call driver_register
    ret

; uint8 rtc_read(reg)：读取 CMOS 寄存器（读期间屏蔽 NMI）
rtc_read:
    mov al, dil
    or al, 0x80                         ; NMI disable
    out 0x70, al
    in al, 0x71
    movzx rax, al
    ret

; 内部：al = BCD -> 二进制
rtc_bcd2bin:
    movzx ecx, al
    mov eax, ecx
    shr eax, 4
    imul eax, 10
    and ecx, 0x0F
    add eax, ecx
    ret

; void rtc_get_time(SysTime*)：填充 sec/min/hour/day/mon/year
rtc_get_time:
    push rbx
    push r12
    mov r12, rdi
    ; 等待 UIP 清除（最多 ~2ms）
    mov rbx, 100000
.wait_uip:
    mov rdi, 0x0A
    call rtc_read
    test al, 0x80
    jz .uip_clear
    dec rbx
    jnz .wait_uip
.uip_clear:
    mov rdi, 0
    call rtc_read
    call rtc_bcd2bin
    mov [r12 + SysTime.sec], eax
    mov rdi, 2
    call rtc_read
    call rtc_bcd2bin
    mov [r12 + SysTime.min], eax
    mov rdi, 4
    call rtc_read
    call rtc_bcd2bin
    mov [r12 + SysTime.hour], eax
    mov rdi, 7
    call rtc_read
    call rtc_bcd2bin
    mov [r12 + SysTime.day], eax
    mov rdi, 8
    call rtc_read
    call rtc_bcd2bin
    mov [r12 + SysTime.mon], eax
    ; 世纪（若存在）
    mov rdi, 0x32
    call rtc_read
    call rtc_bcd2bin
    test eax, eax
    jnz .has_century
    mov eax, 2000
    jmp .year_done
.has_century:
    imul eax, 100
.year_done:
    mov rdi, 9
    call rtc_read
    push rax
    call rtc_bcd2bin
    mov ecx, eax
    pop rax
    add eax, ecx
    mov [r12 + SysTime.year], eax
    pop r12
    pop rbx
    ret

