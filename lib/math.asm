; lib/math.asm - 基础数学库
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global min, max, abs64, clamp

section .text

; int64 min(a, b)
min:
    mov rax, rdi
    cmp rax, rsi
    jle .done
    mov rax, rsi
.done:
    ret

; int64 max(a, b)
max:
    mov rax, rdi
    cmp rax, rsi
    jge .done
    mov rax, rsi
.done:
    ret

; int64 abs64(a)
abs64:
    mov rax, rdi
    test rax, rax
    jge .done
    neg rax
.done:
    ret

; int64 clamp(val, lo, hi)
clamp:
    mov rax, rdi
    cmp rax, rsi
    jge .check_hi
    mov rax, rsi
    ret
.check_hi:
    cmp rax, rdx
    jle .done
    mov rax, rdx
.done:
    ret
