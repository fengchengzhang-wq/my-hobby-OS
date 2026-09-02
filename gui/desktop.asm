; gui/desktop.asm - 桌面：背景渐变 + 任务栏 + 时钟 + 窗口按钮
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "window.inc"
%include "ui.inc"

global draw_desktop, taskbar_hit, draw_taskbar_buttons

extern fb_clear, fb_draw_rect, fb_draw_hline
extern fb_draw_string
extern fb_width, fb_height
extern uptime
extern window_list

TASKBAR_H     equ 40
TASKBAR_X0    equ 70
TASKBAR_BW    equ 120
TASKBAR_BH    equ 30
TASKBAR_GAP   equ 10
TASKBAR_STEP  equ TASKBAR_BW + TASKBAR_GAP

section .bss
clock_str: resb 24

section .text

draw_desktop:
    push rbx
    push r12
    push r13
    ; 背景浅色渐变
    mov r12d, [fb_height]
    sub r12d, TASKBAR_H
    xor r13d, r13d                      ; y
.bg_loop:
    cmp r13d, r12d
    jae .bg_done
    ; 颜色插值（简化：顶部亮、底部暗，分 4 段）
    mov r8d, THEME_BG_TOP
    cmp r13d, 200
    jb .bg_color
    mov r8d, 0xFFE2E8F0
    cmp r13d, 400
    jb .bg_color
    mov r8d, 0xFFD8E0EA
    cmp r13d, 600
    jb .bg_color
    mov r8d, THEME_BG_BOT
.bg_color:
    mov edi, 0
    mov esi, r13d
    mov edx, [fb_width]
    mov ecx, 1
    push r12
    push r13
    call fb_draw_rect
    pop r13
    pop r12
    inc r13d
    jmp .bg_loop
.bg_done:
    ; 任务栏
    mov edi, 0
    mov esi, [fb_height]
    sub esi, TASKBAR_H
    mov edx, [fb_width]
    mov ecx, TASKBAR_H
    mov r8d, THEME_TASKBAR
    call fb_draw_rect
    ; 任务栏上边线
    mov edi, 0
    mov esi, [fb_height]
    sub esi, TASKBAR_H
    mov edx, [fb_width]
    mov ecx, THEME_TASKBAR_LN
    call fb_draw_hline
    ; 系统标签
    mov edi, 8
    mov esi, [fb_height]
    sub esi, 28
    lea rdx, [sys_label]
    mov ecx, THEME_TEXT_DIM
    mov r8d, THEME_TASKBAR
    call fb_draw_string
    ; 时钟
    call draw_clock
    ; 窗口按钮
    call draw_taskbar_buttons
    pop r13
    pop r12
    pop rbx
    ret

draw_clock:
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r9
    lea rdi, [clock_str]
    call uptime                         ; {minutes, seconds}
    ; 分钟
    mov rax, [clock_str]
    xor edx, edx
    mov r9, 10
    div r9
    add al, '0'
    mov [clock_str], al
    add dl, '0'
    mov [clock_str+1], dl
    mov byte [clock_str+2], ':'
    ; 秒
    mov rax, [clock_str+8]
    xor edx, edx
    div r9
    add al, '0'
    mov [clock_str+3], al
    add dl, '0'
    mov [clock_str+4], dl
    mov byte [clock_str+5], 0
    ; 右下角显示
    mov edi, [fb_width]
    sub edi, 60
    mov esi, [fb_height]
    sub esi, 28
    lea rdx, [clock_str]
    mov ecx, THEME_TEXT
    mov r8d, THEME_TASKBAR
    call fb_draw_string
    pop r9
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    ret

; 任务栏窗口按钮
draw_taskbar_buttons:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, [window_list]
    xor r12d, r12d                      ; 索引
.loop:
    test rbx, rbx
    jz .done
    ; x = TASKBAR_X0 + idx*STEP
    mov eax, r12d
    imul eax, TASKBAR_STEP
    add eax, TASKBAR_X0
    mov r13d, eax
    ; 背景：焦点窗口高亮（浅蓝底 + 强调文字）
    mov r14d, THEME_BTN_BOT
    test dword [rbx + Window.flags], WIN_FLAG_FOCUSED
    jz .color_ok
    mov r14d, 0xFFE3EDFB
.color_ok:
    mov edi, r13d
    mov esi, [fb_height]
    sub esi, TASKBAR_H + 5
    mov edx, TASKBAR_BW
    mov ecx, TASKBAR_BH
    mov r8d, r14d
    push rbx
    push r12
    push r13
    call fb_draw_rect
    pop r13
    pop r12
    pop rbx
    ; 标题文字（焦点用强调色）
    mov edi, r13d
    add edi, 6
    mov esi, [fb_height]
    sub esi, TASKBAR_H + 12
    lea rdx, [rbx + Window.title]
    mov ecx, THEME_TEXT
    mov r8d, r14d
    push rbx
    push r12
    push r13
    call fb_draw_string
    pop r13
    pop r12
    pop rbx
    ; 焦点窗口加蓝色下划线
    test dword [rbx + Window.flags], WIN_FLAG_FOCUSED
    jz .no_ul
    mov edi, r13d
    add edi, 2
    mov esi, [fb_height]
    sub esi, TASKBAR_H + 5
    add esi, TASKBAR_BH
    sub esi, 3
    mov edx, TASKBAR_BW
    sub edx, 4
    mov ecx, THEME_ACCENT
    call fb_draw_hline
.no_ul:
    inc r12d
    mov rbx, [rbx + Window.next]
    jmp .loop
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Window *taskbar_hit(x, y)：命中返回窗口指针，否则 0
taskbar_hit:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    ; 必须在任务栏区域内
    mov eax, [fb_height]
    sub eax, TASKBAR_H
    cmp r13d, eax
    jl .none
    cmp r12d, TASKBAR_X0
    jl .none
    mov rbx, [window_list]
    xor r14d, r14d
.loop:
    test rbx, rbx
    jz .none
    mov eax, r14d
    imul eax, TASKBAR_STEP
    add eax, TASKBAR_X0
    mov edx, eax
    add edx, TASKBAR_BW
    cmp r12d, eax
    jl .next
    cmp r12d, edx
    jge .next
    mov rax, rbx
    jmp .done
.next:
    inc r14d
    mov rbx, [rbx + Window.next]
    jmp .loop
.none:
    xor rax, rax
.done:
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
sys_label db "MyOS 0.9", 0
