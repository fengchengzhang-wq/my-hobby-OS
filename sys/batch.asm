; sys/batch.asm - MyOS 批处理（.bat）解释器
; 每行一条命令：echo / cls / sleep / list / run / help
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global batch_run

extern console_write, console_write_line, console_printf_fn, console_clear
extern vfs_list_print, vfs_head
extern exec_run_file
extern strcmp
extern timer_sleep
extern serial_printf

section .bss
bt_line: resb 256
bt_tok:  resb 64
bt_rest: resb 192

section .rodata
bt_echo  db "echo", 0
bt_cls   db "cls", 0
bt_sleep db "sleep", 0
bt_list  db "list", 0
bt_run   db "run", 0
bt_help  db "help", 0
bt_nl    db "", 13, 10, 0
bt_bad   db "unknown command: ", 0
bt_usage db "commands: echo <t> | cls | sleep <ms> | list | run <file> | help", 0
bt_run_hint db "run: ", 0

section .text

; int batch_run(text)
batch_run:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; 文本
    xor r15d, r15d
.loop:
    ; 读一行
    lea rdi, [bt_line]
    mov rsi, r12
    call batch_readline
    mov r12, rax
    test rax, rax
    jz .done
    ; 切 token
    lea rdi, [bt_line]
    lea rsi, [bt_tok]
    lea rdx, [bt_rest]
    call batch_token
    cmp byte [bt_tok], 0
    je .loop
    ; echo
    lea rdi, [bt_tok]
    lea rsi, [bt_echo]
    call strcmp
    test rax, rax
    jnz .c_cls
    lea rdi, [bt_rest]
    call console_write_line
    jmp .loop
.c_cls:
    lea rdi, [bt_tok]
    lea rsi, [bt_cls]
    call strcmp
    test rax, rax
    jnz .c_sleep
    call console_clear
    jmp .loop
.c_sleep:
    lea rdi, [bt_tok]
    lea rsi, [bt_sleep]
    call strcmp
    test rax, rax
    jnz .c_list
    lea rsi, [bt_rest]
    call atoi10
    mov rdi, rax
    call timer_sleep
    jmp .loop
.c_list:
    lea rdi, [bt_tok]
    lea rsi, [bt_list]
    call strcmp
    test rax, rax
    jnz .c_run
    mov rbx, [vfs_head]
.floop:
    test rbx, rbx
    jz .fend
    lea rdi, [rbx]                      ; VFile.name 位于偏移 0
    call console_write
    lea rdi, [bt_nl]
    call console_write
    mov rbx, [rbx + 64]                 ; VFile.next
    jmp .floop
.fend:
    jmp .loop
.c_run:
    lea rdi, [bt_tok]
    lea rsi, [bt_run]
    call strcmp
    test rax, rax
    jnz .c_help
    lea rdi, [bt_run_hint]
    call console_write
    lea rdi, [bt_rest]
    call console_write
    lea rdi, [bt_nl]
    call console_write
    lea rdi, [bt_rest]
    call exec_run_file
    jmp .loop
.c_help:
    lea rdi, [bt_tok]
    lea rsi, [bt_help]
    call strcmp
    test rax, rax
    jnz .unknown
    lea rdi, [bt_usage]
    call console_write_line
    jmp .loop
.unknown:
    lea rdi, [bt_bad]
    call console_write
    lea rdi, [bt_tok]
    call console_write_line
    jmp .loop
.done:
    mov eax, r15d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; 读取一行到 [rdi]，源 [rsi]，返回下一行指针（0=结束）
batch_readline:
    push rbx
    mov rbx, rdi
.loop:
    mov al, [rsi]
    test al, al
    jz .end
    cmp al, 10
    je .end
    cmp al, 13
    je .cr
    mov [rbx], al
    inc rbx
.cr:
    inc rsi
    jmp .loop
.end:
    mov byte [rbx], 0
    cmp byte [rsi], 0
    je .eof
    inc rsi
    cmp byte [rsi], 10
    jne .retn
    inc rsi
.retn:
    mov rax, rsi
    pop rbx
    ret
.eof:
    xor rax, rax
    pop rbx
    ret

; token：rdi=行, rsi=tok, rdx=rest
batch_token:
    push rbx
    mov rbx, rdx
.sp:
    mov al, [rdi]
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    test al, al
    jz .done
    jmp .word
.adv:
    inc rdi
    jmp .sp
.word:
    mov al, [rdi]
    test al, al
    jz .wend
    cmp al, ' '
    je .wend
    cmp al, 9
    je .wend
    mov [rsi], al
    inc rsi
    inc rdi
    jmp .word
.wend:
    mov byte [rsi], 0
.sp2:
    mov al, [rdi]
    cmp al, ' '
    je .adv2
    cmp al, 9
    je .adv2
    jmp .rest
.adv2:
    inc rdi
    jmp .sp2
.rest:
    mov al, [rdi]
    mov [rbx], al
    test al, al
    jz .done
    inc rbx
    inc rdi
    jmp .rest
.done:
    mov byte [rbx], 0
    pop rbx
    ret

; 简易十进制解析（[rsi] -> rax）
atoi10:
    xor eax, eax
.loop:
    movzx ecx, byte [rsi]
    cmp cl, '0'
    jb .done
    cmp cl, '9'
    ja .done
    imul eax, 10
    sub ecx, '0'
    add eax, ecx
    inc rsi
    jmp .loop
.done:
    ret
