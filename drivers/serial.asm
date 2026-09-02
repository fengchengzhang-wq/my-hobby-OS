; drivers/serial.asm - COM1 串口驱动（115200 8N1）+ 格式化输出
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global init_serial, serial_write_char, serial_write_string, serial_write_bytes
global serial_write_hex64, serial_write_hex32, serial_write_dec64, serial_newline
global serial_printf

extern format_hex64, format_hex32, format_dec64

section .bss
serial_buf: resb 40

section .text

init_serial:
    mov dx, 0x3F8 + 1                   ; 中断使能：关闭
    mov al, 0x00
    out dx, al
    mov dx, 0x3F8 + 3                   ; 线控：DLAB=1
    mov al, 0x80
    out dx, al
    mov dx, 0x3F8                       ; 波特率 115200 -> 分频 1
    mov al, 0x01
    out dx, al
    mov dx, 0x3F8 + 1
    mov al, 0x00
    out dx, al
    mov dx, 0x3F8 + 3                   ; 8N1，DLAB=0
    mov al, 0x03
    out dx, al
    mov dx, 0x3F8 + 2                   ; FIFO 启用并清空
    mov al, 0xC7
    out dx, al
    mov dx, 0x3F8 + 4                   ; DTR/RTS
    mov al, 0x0B
    out dx, al
    ret

; void serial_write_char(ch)
serial_write_char:
    push rax
    push rdx
    mov rax, rdi
    mov dx, 0x3F8 + 5
.wait:
    in al, dx
    test al, 0x20                       ; THR 空？
    jz .wait
    mov dx, 0x3F8
    mov al, dil
    out dx, al
    pop rdx
    pop rax
    ret

; void serial_write_string(s)
serial_write_string:
    push rbx
    mov rbx, rdi
.loop:
    mov al, [rbx]
    test al, al
    jz .done
    movzx rdi, al
    call serial_write_char
    inc rbx
    jmp .loop
.done:
    pop rbx
    ret

; void serial_write_bytes(buf, len)
serial_write_bytes:
    push rbx
    mov rbx, rdi
.loop:
    test rsi, rsi
    jz .done
    movzx rdi, byte [rbx]
    call serial_write_char
    inc rbx
    dec rsi
    jmp .loop
.done:
    pop rbx
    ret

serial_newline:
    push rdi
    mov rdi, 13
    call serial_write_char
    mov rdi, 10
    call serial_write_char
    pop rdi
    ret

; void serial_write_hex64(value)
serial_write_hex64:
    push rdi
    push rsi
    mov rsi, rdi
    lea rdi, [serial_buf]
    call format_hex64
    lea rdi, [serial_buf]
    call serial_write_string
    pop rsi
    pop rdi
    ret

; void serial_write_hex32(value)
serial_write_hex32:
    push rdi
    push rsi
    mov rsi, rdi
    lea rdi, [serial_buf]
    call format_hex32
    lea rdi, [serial_buf]
    call serial_write_string
    pop rsi
    pop rdi
    ret

; void serial_write_dec64(value)
serial_write_dec64:
    push rdi
    push rsi
    mov rsi, rdi
    lea rdi, [serial_buf]
    call format_dec64
    lea rdi, [serial_buf]
    call serial_write_string
    pop rsi
    pop rdi
    ret

; void serial_printf(fmt, args...)
; 支持 %s %c %d %x %p %%；最多 5 个寄存器参数 + 栈参数
serial_printf:
    push rbp
    mov rbp, rsp
    sub rsp, 128
    mov [rbp - 8], rsi
    mov [rbp - 16], rdx
    mov [rbp - 24], rcx
    mov [rbp - 32], r8
    mov [rbp - 40], r9
    push rbx
    push r12
    push r13
    mov r12, rdi                        ; fmt
    xor r13, r13                        ; 参数序号
.fmt_loop:
    mov al, [r12]
    test al, al
    jz .done
    cmp al, '%'
    jne .plain
    inc r12
    mov al, [r12]
    cmp al, 's'
    jne .not_s
    call .get_arg
    mov rdi, rax
    call serial_write_string
    jmp .next
.not_s:
    cmp al, 'c'
    jne .not_c
    call .get_arg
    mov rdi, rax
    call serial_write_char
    jmp .next
.not_c:
    cmp al, 'd'
    jne .not_d
    call .get_arg
    mov rdi, rax
    call serial_write_dec64
    jmp .next
.not_d:
    cmp al, 'x'
    jne .not_x
    call .get_arg
    mov rdi, rax
    call serial_write_hex64
    jmp .next
.not_x:
    cmp al, 'p'
    jne .not_p
    call .get_arg
    mov rdi, rax
    call serial_write_hex64
    jmp .next
.not_p:
    cmp al, '%'
    jne .bad
    mov rdi, '%'
    call serial_write_char
    jmp .next
.bad:
    mov rdi, '?'
    call serial_write_char
.next:
    inc r12
    jmp .fmt_loop
.plain:
    movzx rdi, al
    call serial_write_char
    inc r12
    jmp .fmt_loop
.done:
    pop r13
    pop r12
    pop rbx
    leave
    ret

; 内部：取第 r13 个参数（从 0 开始），返回 rax 并递增
.get_arg:
    cmp r13, 5
    jae .stack_arg
    lea r8, [rbp - 8]
    mov rax, r13
    shl rax, 3
    sub r8, rax
    mov rax, [r8]                       ; arg0@rbp-8, arg1@rbp-16, ...
    jmp .got
.stack_arg:
    mov rax, r13
    sub rax, 5
    shl rax, 3
    add rax, rbp
    mov rax, [rax + 16]
.got:
    inc r13
    ret
