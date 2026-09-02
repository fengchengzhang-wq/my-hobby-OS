; lib/format.asm - 数字格式化库
; 约定：目标缓冲区必须足够大（hex64 >= 17 字节，dec64 >= 21 字节）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global format_hex64, format_hex32, format_dec64

section .text

; char *format_hex64(buf, value)：16 位十六进制 + NUL
format_hex64:
    push rbx
    push rcx
    push rdx
    mov rbx, rdi
    mov rax, rsi
    mov rdx, rdi
    mov rcx, 16
.loop:
    rol rax, 4
    push rax
    and al, 0x0F
    cmp al, 10
    jl .digit
    add al, 'A' - 10
    jmp .put
.digit:
    add al, '0'
.put:
    mov [rdx], al
    inc rdx
    pop rax
    loop .loop
    mov byte [rdx], 0
    mov rax, rbx
    pop rdx
    pop rcx
    pop rbx
    ret

; char *format_hex32(buf, value)：8 位十六进制 + NUL
format_hex32:
    push rbx
    push rcx
    push rdx
    mov rbx, rdi
    mov rax, rsi
    mov rdx, rdi
    mov rcx, 8
.loop:
    rol eax, 4
    push rax
    and al, 0x0F
    cmp al, 10
    jl .digit
    add al, 'A' - 10
    jmp .put
.digit:
    add al, '0'
.put:
    mov [rdx], al
    inc rdx
    pop rax
    loop .loop
    mov byte [rdx], 0
    mov rax, rbx
    pop rdx
    pop rcx
    pop rbx
    ret

; char *format_dec64(buf, value)：无符号十进制 + NUL
format_dec64:
    push rbx
    push rcx
    push rdx
    push r8
    mov rbx, rdi
    lea rcx, [rbx + 20]                 ; 从尾部向前写
    mov byte [rcx], 0
    mov rax, rsi
    test rax, rax
    jnz .loop
    dec rcx
    mov byte [rcx], '0'
    jmp .copy
.loop:
    xor edx, edx
    mov r8, 10
    div r8
    add dl, '0'
    dec rcx
    mov [rcx], dl
    test rax, rax
    jnz .loop
.copy:
    mov r8, rdi
    lea rdx, [rbx + 21]
    sub rdx, rcx                        ; 含 NUL 的长度
    mov rsi, rcx
.copy_loop:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jnz .copy_loop
    mov rax, r8
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret
