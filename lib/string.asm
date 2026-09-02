; lib/string.asm - 字符串与内存操作库
; 调用约定：System V AMD64（rdi/rsi/rdx/rcx/r8/r9）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global memcpy, memset, memset32, strlen, strcmp, strcpy, strncpy, strchr

section .text

; void *memcpy(dst, src, len) -> rax = dst
memcpy:
    push rdi
    push rsi
    push rcx
    mov rcx, rdx
    rep movsb
    pop rcx
    pop rsi
    pop rdi
    mov rax, rdi
    ret

; void *memset(ptr, byte, len) -> rax = ptr
memset:
    push rdi
    push rcx
    mov rax, rsi
    mov rcx, rdx
    rep stosb
    pop rcx
    pop rdi
    mov rax, rdi
    ret

; void *memset32(ptr, dword, count) -> rax = ptr
memset32:
    push rdi
    push rcx
    mov rax, rsi
    mov rcx, rdx
    rep stosd
    pop rcx
    pop rdi
    mov rax, rdi
    ret

; size_t strlen(s)
strlen:
    push rdi
    push rcx
    xor rcx, rcx
    not rcx
    xor al, al
    repne scasb
    not rcx
    dec rcx
    mov rax, rcx
    pop rcx
    pop rdi
    ret

; int strcmp(a, b)：返回 a-b（<0 / 0 / >0）
strcmp:
    push rdi
    push rsi
    push rcx
.loop:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .diff
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp .loop
.diff:
    movzx rax, al
    movzx rcx, cl
    sub rax, rcx
    pop rcx
    pop rsi
    pop rdi
    ret
.equal:
    xor rax, rax
    pop rcx
    pop rsi
    pop rdi
    ret

; char *strcpy(dst, src) -> rax = dst
strcpy:
    push rdi
    push rsi
    mov rax, rdi
.loop:
    mov cl, [rsi]
    mov [rdi], cl
    test cl, cl
    jz .done
    inc rdi
    inc rsi
    jmp .loop
.done:
    pop rsi
    pop rdi
    ret

; char *strncpy(dst, src, n) -> rax = dst
strncpy:
    push rbx
    push rdi
    push rsi
    push rcx
    mov rbx, rdi
.loop:
    test rdx, rdx
    jz .done
    mov cl, [rsi]
    mov [rdi], cl
    test cl, cl
    jz .skip_inc
    inc rsi
.skip_inc:
    inc rdi
    dec rdx
    jmp .loop
.done:
    mov rax, rbx
    pop rcx
    pop rsi
    pop rdi
    pop rbx
    ret

; char *strchr(s, ch) -> rax = 指针或 0
strchr:
    push rdi
.loop:
    mov al, [rdi]
    cmp al, sil
    je .found
    test al, al
    jz .notfound
    inc rdi
    jmp .loop
.found:
    mov rax, rdi
    pop rdi
    ret
.notfound:
    xor rax, rax
    pop rdi
    ret

