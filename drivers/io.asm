; drivers/io.asm - 端口 I/O HAL（驱动统一入口）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global io_outb, io_outw, io_outl, io_inb, io_inw, io_inl, io_wait, io_delay

section .text

; void io_outb(port, value)
io_outb:
    mov dx, di
    mov rax, rsi
    out dx, al
    ret

; void io_outw(port, value)
io_outw:
    mov dx, di
    mov rax, rsi
    out dx, ax
    ret

; void io_outl(port, value)
io_outl:
    mov dx, di
    mov rax, rsi
    out dx, eax
    ret

; uint8 io_inb(port)
io_inb:
    mov dx, di
    in al, dx
    movzx rax, al
    ret

; uint16 io_inw(port)
io_inw:
    mov dx, di
    in ax, dx
    movzx rax, ax
    ret

; uint32 io_inl(port)
io_inl:
    mov dx, di
    in eax, dx
    ret

; void io_wait()：向 0x80 端口写 1 字节（ISA 延迟）
io_wait:
    push rax
    mov al, 0
    out 0x80, al
    pop rax
    ret

; void io_delay(iterations)
io_delay:
    push rcx
    mov rcx, rdi
.loop:
    nop
    dec rcx
    jnz .loop
    pop rcx
    ret

