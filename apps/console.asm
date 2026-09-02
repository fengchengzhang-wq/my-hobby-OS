; apps/console.asm - 控制台（运行 .exe / .bat 并显示输出）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "window.inc"
%include "ui.inc"
%include "vfs.inc"

global console_launch, console_paint, console_input

extern window_create
extern fb_clear, fb_draw_rect, fb_draw_hline, fb_draw_char, fb_draw_string
extern fb_draw_cjk
extern ui_button, ui_draw_all, ui_mouse_event, ui_key_event
extern console_clear, console_write, console_buf, console_len
extern batch_run, exec_run_file
extern vfs_find
extern serial_printf

section .data
console_win: dq 0

section .text

console_launch:
    push rbp
    mov rbp, rsp
    ; 已存在则聚焦
    mov rdi, [console_win]
    test rdi, rdi
    jz .create
    extern window_focus
    call window_focus
    leave
    ret
.create:
    mov rdi, title_c
    mov esi, 500
    mov edx, 60
    mov ecx, 500
    mov r8d, 340
    call window_create
    test rax, rax
    jz .fail
    mov [console_win], rax
    mov qword [rax + Window.paint_fn], console_paint
    mov qword [rax + Window.input_fn], console_input
    ; 控件：清屏 / 运行 demo.bat / 运行 hello.exe
    mov rdi, rax
    mov esi, 6
    mov edx, 6
    mov ecx, 90
    mov r8d, 26
    lea r9, [btn_clear]
    push cb_clear
    call ui_button
    add rsp, 8
    mov rdi, [console_win]
    mov esi, 102
    mov edx, 6
    mov ecx, 150
    mov r8d, 26
    lea r9, [btn_demo]
    push cb_demo
    call ui_button
    add rsp, 8
    mov rdi, [console_win]
    mov esi, 258
    mov edx, 6
    mov ecx, 150
    mov r8d, 26
    lea r9, [btn_hello]
    push cb_hello
    call ui_button
    add rsp, 8
    ; 欢迎语
    lea rdi, [welcome]
    call console_write_line_c
    mov rax, [console_win]
.fail:
    leave
    ret

console_write_line_c:
    push rdi
    call console_write
    lea rdi, [nl]
    call console_write
    pop rdi
    ret

; 绘制：标题 + 控制台文本
console_paint:                          ; rdi = win
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov edi, THEME_WIN_BG
    call fb_clear
    ; 分隔线
    mov edi, 0
    mov esi, 38
    mov edx, [r12 + Window.width]
    mov ecx, THEME_TASKBAR_LN
    call fb_draw_hline
    ; 控件
    mov rdi, r12
    call ui_draw_all
    ; 控制台文本
    mov r13, 10                          ; x
    mov r14, 48                          ; y
    lea r15, [console_buf]
.ch:
    mov al, [r15]
    test al, al
    jz .done
    cmp al, 10
    je .nl
    cmp al, 13
    je .next
    cmp al, 0x80
    jb .ascii
    ; ---- UTF-8 中文（16x16） ----
    movzx eax, al
    mov edx, eax
    and edx, 0xE0
    cmp edx, 0xC0
    je .u2
    mov edx, eax
    and edx, 0xF0
    cmp edx, 0xE0
    je .u3
    jmp .next
.u2:
    movzx ecx, byte [r15 + 1]
    cmp cl, 0x80
    jb .next
    cmp cl, 0xBF
    ja .next
    and eax, 0x1F
    shl eax, 6
    and ecx, 0x3F
    or eax, ecx
    mov r9d, 2
    jmp .draw_cjk
.u3:
    movzx ecx, byte [r15 + 1]
    cmp cl, 0x80
    jb .next
    cmp cl, 0xBF
    ja .next
    movzx edx, byte [r15 + 2]
    cmp dl, 0x80
    jb .next
    cmp dl, 0xBF
    ja .next
    and eax, 0x0F
    shl eax, 12
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    and edx, 0x3F
    or eax, edx
    mov r9d, 3
.draw_cjk:
    mov r10d, [r12 + Window.width]
    sub r10d, 20
    lea r11d, [r13 + 16]
    cmp r11d, r10d
    jle .cjk_draw
    mov r13, 10
    add r14, 16
    mov r10d, [r12 + Window.height]
    sub r10d, 30
    cmp r14d, r10d
    jge .done
.cjk_draw:
    mov edi, r13d
    mov esi, r14d
    mov edx, eax
    mov ecx, THEME_TEXT
    mov r8d, -1
    push rax
    push r9
    push r10
    push r11
    push r13
    push r14
    push r15
    call fb_draw_cjk
    pop r15
    pop r14
    pop r13
    pop r11
    pop r10
    pop r9
    pop rax
    add r13, 16
    add r15, r9
    jmp .ch
.ascii:
    mov r10d, [r12 + Window.width]
    sub r10d, 20
    lea r11d, [r13 + 8]
    cmp r11d, r10d
    jle .asc_draw
    mov r13, 10
    add r14, 16
    mov r10d, [r12 + Window.height]
    sub r10d, 30
    cmp r14d, r10d
    jge .done
.asc_draw:
    movzx eax, al
    mov edi, r13d
    mov esi, r14d
    mov edx, eax
    mov ecx, THEME_TEXT
    mov r8d, -1
    push rax
    push r13
    push r14
    push r15
    call fb_draw_char
    pop r15
    pop r14
    pop r13
    pop rax
    add r13, 8
    inc r15
    jmp .ch
.nl:
    mov r13, 10
    add r14, 16
    mov eax, [r12 + Window.height]
    sub eax, 30
    cmp r14d, eax
    jge .done
    inc r15
    jmp .ch
.next:
    inc r15
    jmp .ch
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; 输入：先给控件
console_input:                          ; rdi=win, esi=type, edx=x, ecx=y, r8d=buttons, r9d=key
    push rbp
    mov rbp, rsp
    push r8
    push r9
    cmp esi, UI_EV_KEY
    je .key
    call ui_mouse_event
    jmp .out
.key:
    mov esi, r9d
    call ui_key_event
.out:
    pop r9
    pop r8
    leave
    ret

cb_clear:
    call console_clear
    ret

cb_demo:
    lea rdi, [run_demo]
    call console_write_line_c
    lea rdi, [v_demo]
    call vfs_find
    test rax, rax
    jz .err
    mov rdi, [rax + VFile.data]
    call batch_run
    ret
.err:
    lea rdi, [not_installed]
    call console_write_line_c
    ret

cb_hello:
    lea rdi, [run_hello]
    call console_write_line_c
    lea rdi, [v_hello]
    call exec_run_file
    ret

section .rodata
title_c  db "控制台", 0
btn_clear db "清屏", 0
btn_demo  db "运行 demo.bat", 0
btn_hello db "运行 hello.exe", 0
welcome db "MyOS 控制台 v0.9 — .exe/.bat 的输出会显示在这里。", 0
nl      db 13, 10, 0
run_demo db "> demo.bat", 0
run_hello db "> hello.exe", 0
not_installed db "demo.bat 未安装（请先在软件中心安装）", 0
v_demo db "demo.bat", 0
v_hello db "hello.exe", 0
