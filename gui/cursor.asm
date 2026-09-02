; gui/cursor.asm - 软件鼠标光标（XOR 绘制法，任何背景下可见）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global draw_cursor
extern mouse_x, mouse_y
extern fb_xor_pixel, fb_mark_dirty

section .rodata
; 16x16 箭头，1 = XOR 反转该像素
cursor_bmp:
    db 0b10000000
    db 0b11000000
    db 0b11100000
    db 0b11110000
    db 0b11111000
    db 0b11111100
    db 0b11111110
    db 0b11111111
    db 0b11111110
    db 0b11111100
    db 0b11101000
    db 0b11000100
    db 0b10000010
    db 0b10000001
    db 0b10000000
    db 0b00000000

section .text
draw_cursor:
    push rbx
    push r9
    push r10
    lea rbx, [cursor_bmp]
    xor r9d, r9d                        ; 行
.row_loop:
    cmp r9d, 16
    jae .done
    movzx eax, byte [rbx + r9]
    xor r10d, r10d                      ; 列
.col_loop:
    cmp r10d, 8
    jae .next_row
    test eax, 0x80
    jz .next_col
    mov edi, [mouse_x]
    add edi, r10d
    mov esi, [mouse_y]
    add esi, r9d
    push rax
    push rbx
    push r9
    push r10
    call fb_xor_pixel
    pop r10
    pop r9
    pop rbx
    pop rax
.next_col:
    shl eax, 1
    inc r10d
    jmp .col_loop
.next_row:
    inc r9d
    jmp .row_loop
.done:
    mov edi, [mouse_x]
    mov esi, [mouse_y]
    mov edx, 16
    mov ecx, 16
    call fb_mark_dirty
    pop r10
    pop r9
    pop rbx
    ret

