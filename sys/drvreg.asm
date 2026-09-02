; sys/drvreg.asm - 驱动注册框架（Driver Registry）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "driver.inc"

global drvreg_init, driver_register, driver_unregister
global driver_init_all, driver_find, driver_list_print

extern serial_write_string, serial_newline, serial_printf
extern strcmp

section .data
global drv_list
drv_list: dq 0

section .text

drvreg_init:
    push rdi
    lea rdi, [msg_registry]
    call serial_write_string
    call driver_list_print
    pop rdi
    ret

; void driver_register(drv)
driver_register:
    push rbx
    mov rbx, [drv_list]
    mov [rdi + Driver.next], rbx
    mov [drv_list], rdi
    mov dword [rdi + Driver.state], DRV_STATE_REGISTERED
    pop rbx
    ret

; void driver_unregister(drv)
driver_unregister:
    push rbx
    mov rbx, [drv_list]
    cmp rbx, rdi
    je .first
.search:
    test rbx, rbx
    jz .done
    cmp [rbx + Driver.next], rdi
    je .found
    mov rbx, [rbx + Driver.next]
    jmp .search
.first:
    mov rax, [rdi + Driver.next]
    mov [drv_list], rax
    jmp .done
.found:
    mov rax, [rdi + Driver.next]
    mov [rbx + Driver.next], rax
.done:
    pop rbx
    ret

; void driver_init_all()：调用所有未初始化驱动的 init
driver_init_all:
    push rbx
    mov rbx, [drv_list]
.loop:
    test rbx, rbx
    jz .done
    cmp dword [rbx + Driver.state], DRV_STATE_INITIALIZED
    je .next
    mov rax, [rbx + Driver.init]
    test rax, rax
    jz .next
    push rbx
    call rax
    pop rbx
    mov dword [rbx + Driver.state], DRV_STATE_INITIALIZED
.next:
    mov rbx, [rbx + Driver.next]
    jmp .loop
.done:
    pop rbx
    ret

; Driver *driver_find(name)
driver_find:
    push rbx
    mov rbx, [drv_list]
.loop:
    test rbx, rbx
    jz .notfound
    push rdi
    push rbx
    mov rsi, [rbx + Driver.name]
    call strcmp
    pop rbx
    pop rdi
    test rax, rax
    jz .found
    mov rbx, [rbx + Driver.next]
    jmp .loop
.found:
    mov rax, rbx
    pop rbx
    ret
.notfound:
    xor rax, rax
    pop rbx
    ret

driver_list_print:
    push rbx
    mov rbx, [drv_list]
.loop:
    test rbx, rbx
    jz .done
    mov rdi, fmt_entry
    mov rsi, [rbx + Driver.name]
    mov edx, [rbx + Driver.kind]
    mov ecx, [rbx + Driver.state]
    push rbx
    call serial_printf
    pop rbx
    mov rbx, [rbx + Driver.next]
    jmp .loop
.done:
    pop rbx
    ret

section .rodata
msg_registry db "=== Driver Registry ===", 13, 10, 0
fmt_entry    db "  [%s] kind=%d state=%d", 13, 10, 0
