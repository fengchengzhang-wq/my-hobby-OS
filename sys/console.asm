; sys/console.asm - 应用控制台缓冲（EXE/批处理输出目标）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global console_clear, console_write, console_write_line
global console_printf_fn, console_buf, console_len

extern serial_write_string
extern format_dec64
extern strcmp

CONSOLE_SIZE equ 4096

section .bss
console_buf: resb CONSOLE_SIZE
console_len: resd 1
console_tmp: resb 32

section .text

console_clear:
    mov rax, console_len
    mov dword [rax], 0
    ret

; console_write(str)
console_write:
    push rdi
    push rsi
    push rcx
    push rax
    mov rsi, rdi
    mov edi, [console_len]
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    cmp edi, CONSOLE_SIZE - 1
    jae .done
    mov rax, console_buf
    add rax, rdi
    mov [rax], al
    inc edi
    inc rsi
    jmp .loop
.done:
    mov rax, console_buf
    add rax, rdi
    mov byte [rax], 0
    mov rax, console_len
    mov [rax], edi
    pop rax
    pop rcx
    pop rsi
    pop rdi
    ret

console_write_line:                     ; rdi = str
    push rdi
    call console_write
    mov rax, console_len
    mov edx, [rax]
    cmp edx, CONSOLE_SIZE - 2
    jae .full
    mov rax, console_buf
    add rax, rdx
    mov byte [rax], 13
    mov byte [rax + 1], 10
    add rdx, 2
    mov rax, console_len
    mov [rax], edx
    mov rax, console_buf
    add rax, rdx
    mov byte [rax], 0
    pop rdi
    ret
.full:
    pop rdi
    ret

; 供 EXE/批处理使用的 print_fn（ABI: rdi=str）
console_printf_fn:
    jmp console_write

; console_write_dec64(value)：写一行十进制
console_write_dec64:
    push rdi
    push rsi
    mov rsi, rdi
    lea rdi, [console_tmp]
    call format_dec64
    lea rdi, [console_tmp]
    call console_write
    pop rsi
    pop rdi
    ret

; 简易串口同步（调试用）
console_flush:
    ret
