; api/syscall.asm - 系统调用层（SYSCALL/SYSRET，为未来用户态预留）
; STAR: 内核 CS=0x08，用户 CS 基址=0x28（SYSRET 加载 0x2B/0x33）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "syscall.inc"

global init_syscall, syscall_entry, sys_dispatch

extern serial_write_bytes
extern get_ticks, timer_sleep
extern kmalloc, kfree
extern rtc_get_time, mouse_read_state
extern kapi_resolve

section .text

init_syscall:
    mov ecx, 0xC0000081                 ; STAR
    mov edx, 0x00280008                 ; 用户 CS 基址 0x28 | 内核 CS 0x08
    xor eax, eax
    wrmsr
    mov ecx, 0xC0000082                 ; LSTAR
    mov rax, syscall_entry
    wrmsr
    mov ecx, 0xC0000084                 ; SFMASK：进入时屏蔽 IF
    xor eax, eax
    mov eax, 0x200
    xor edx, edx
    wrmsr
    ret

syscall_entry:
    swapgs
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    ; rdi = 调用号，参数平移
    mov rdi, rax
    mov rcx, r10
    call sys_dispatch
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    swapgs
    sysret

; 分发器：rdi=num, rsi/rdx/rcx/r8/r9 = 参数
sys_dispatch:
    cmp rdi, SYS_KAPI_LOOKUP
    ja .bad
    lea rax, [syscall_table]
    mov rax, [rax + rdi*8]
    test rax, rax
    jz .bad
    jmp rax
.bad:
    mov rax, -1
    ret

sys_exit:
    cli
    hlt

sys_write:
    push rsi
    push rdx
    mov rdi, rsi
    call serial_write_bytes
    pop rdx
    pop rsi
    xor rax, rax
    ret

sys_get_ticks:
    call get_ticks
    ret

sys_sleep:
    call timer_sleep
    xor rax, rax
    ret

sys_alloc:
    call kmalloc
    ret

sys_free:
    call kfree
    xor rax, rax
    ret

sys_time:
    call rtc_get_time
    xor rax, rax
    ret

sys_mouse:
    call mouse_read_state
    xor rax, rax
    ret

sys_kapi_lookup:
    call kapi_resolve
    ret

section .data
syscall_table:
    dq sys_exit
    dq sys_write
    dq sys_get_ticks
    dq sys_sleep
    dq sys_alloc
    dq sys_free
    dq sys_time
    dq sys_mouse
    dq sys_kapi_lookup
