; gui/wm.asm - 窗口管理器：合成器、焦点、拖拽、输入分发、演示应用
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "window.inc"
%include "events.inc"
%include "ui.inc"

global wm_init, wm_run, wm_redraw
global active_window, window_paint_default

extern window_create, window_destroy, window_move, window_focus
extern window_list
extern draw_desktop, draw_cursor
extern taskbar_hit
extern fb_flip, fb_mark_dirty
extern fb_set_target, fb_reset_target, fb_clear
extern fb_draw_string, fb_draw_char, fb_draw_rect, fb_draw_hline, fb_draw_vline
extern fb_draw_border, fb_blit
extern fb_drop_shadow, fb_alpha_rect
extern fb_text_width_utf8
extern fb_width, fb_height
extern keyboard_read_event, mouse_read_state
extern format_dec64
extern strlen
extern mouse_x, mouse_y
extern taskflow_launch, center_launch, devmgr_launch, console_launch

section .data
active_window: dq 0
dragging: db 0
prev_mx: dd 0
prev_my: dd 0
prev_buttons: dd 0
key_text: times 80 db 0
key_len: dd 0

demo1_title db "Terminal", 0
demo2_title db "Monitor", 0
demo3_title db "Settings", 0

demo_colors:
    dd 0xFF3D8B4F, 0xFF2E6DB4, 0xFFB4652E

section .bss
align 16
kbd_event: resb KeyEvent_size
mouse_state: resb MouseState_size
wm_linebuf: resb 40
wm_linebuf2: resb 40

section .text

; ---- 初始化：创建 3 个演示窗口 ----
wm_init:
    call taskflow_launch
    call center_launch
    call devmgr_launch
    call console_launch

    ; 激活最顶层窗口
    mov rax, [window_list]
    mov [active_window], rax
    test rax, rax
    jz .done
    mov rdi, rax
    call window_focus
.done:
    ret

; ---- 主循环 ----
wm_run:
.loop:
    call wm_redraw
    call fb_flip

    ; ---- 键盘事件 ----
.kbd:
    lea rdi, [kbd_event]
    call keyboard_read_event
    test rax, rax
    jz .kbd_done
    cmp dword [kbd_event + KeyEvent.type], EV_KEY_DOWN
    jne .kbd
    mov eax, [kbd_event + KeyEvent.ascii]
    test eax, eax
    jz .kbd
    ; 应用窗口：键盘事件直接转发给 input_fn
    mov rdi, [active_window]
    test rdi, rdi
    jz .kbd
    mov r10, [rdi + Window.input_fn]
    test r10, r10
    jz .legacy_kbd
    mov esi, UI_EV_KEY
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    mov r9d, eax
    call r10
    jmp .kbd
.legacy_kbd:
    cmp al, 27
    jne .not_esc
    ; ESC：关闭焦点窗口
    mov rdi, [active_window]
    test rdi, rdi
    jz .kbd
    call window_destroy
    mov qword [active_window], 0
    mov rax, [window_list]
    test rax, rax
    jz .kbd
    mov [active_window], rax
    mov rdi, rax
    call window_focus
    jmp .kbd
.not_esc:
    cmp al, 8
    je .backspace
    cmp al, 13
    je .enter_key
    mov ecx, [key_len]
    cmp ecx, 78
    jae .kbd
    mov [key_text + rcx], al
    inc dword [key_len]
    mov eax, [key_len]
    mov byte [key_text + rax], 0
    jmp .kbd
.backspace:
    cmp dword [key_len], 0
    je .kbd
    dec dword [key_len]
    mov eax, [key_len]
    mov byte [key_text + rax], 0
    jmp .kbd
.enter_key:
    mov byte [key_text], 0
    mov dword [key_len], 0
    jmp .kbd
.kbd_done:

    ; ---- 鼠标事件 ----
    lea rdi, [mouse_state]
    call mouse_read_state
    mov eax, [mouse_state + MouseState.buttons]
    cmp eax, [prev_buttons]
    je .no_click
    test al, 1
    jz .left_up
    ; 左键按下
    call wm_mouse_down
    jmp .clicked
.left_up:
    mov byte [dragging], 0
    call wm_mouse_up_app
.clicked:
    mov eax, [mouse_state + MouseState.buttons]
    mov [prev_buttons], eax
.no_click:
    ; 拖拽：仅当左键仍按住时继续；松开（含丢失的释放包）立即复位
    mov eax, [mouse_state + MouseState.buttons]
    test al, 1
    jz .drag_release
    cmp byte [dragging], 0
    je .no_drag
    mov eax, [mouse_state + MouseState.x]
    sub eax, [prev_mx]
    mov edx, [mouse_state + MouseState.y]
    sub edx, [prev_my]
    mov rdi, [active_window]
    mov esi, eax
    call window_move
    jmp .no_drag
.drag_release:
    mov byte [dragging], 0
.no_drag:
    mov eax, [mouse_state + MouseState.x]
    mov [prev_mx], eax
    mov eax, [mouse_state + MouseState.y]
    mov [prev_my], eax
    jmp .loop

; ---- 鼠标左键按下：任务栏 / 窗口命中检测 ----
wm_mouse_down:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    mov eax, [mouse_state + MouseState.x]
    mov r12d, eax
    mov eax, [mouse_state + MouseState.y]
    mov r13d, eax
    ; 任务栏按钮
    mov edi, r12d
    mov esi, r13d
    call taskbar_hit
    test rax, rax
    jz .not_taskbar
    mov rdi, rax
    call window_focus
    mov [active_window], rax
    jmp .done
.not_taskbar:
    ; 窗口命中（顶层优先）
    mov rbx, [window_list]
.hit_loop:
    test rbx, rbx
    jz .done
    mov eax, [rbx + Window.x]
    cmp r12d, eax
    jl .next_win
    add eax, [rbx + Window.width]
    cmp r12d, eax
    jge .next_win
    mov eax, [rbx + Window.y]
    cmp r13d, eax
    jl .next_win
    add eax, [rbx + Window.height]
    cmp r13d, eax
    jge .next_win
    ; 关闭按钮（右上角 18x18）
    mov eax, [rbx + Window.x]
    add eax, [rbx + Window.width]
    sub eax, 18
    cmp r12d, eax
    jl .not_close
    mov eax, [rbx + Window.y]
    cmp r13d, eax
    jl .not_close
    add eax, 18
    cmp r13d, eax
    jge .not_close
    ; 关闭窗口
    push rbx
    mov rdi, rbx
    call window_destroy
    pop rbx
    cmp rbx, [active_window]
    jne .done
    mov qword [active_window], 0
    jmp .done
.not_close:
    ; 标题栏：聚焦 + 拖拽
    mov eax, [rbx + Window.y]
    add eax, TITLE_HEIGHT
    cmp r13d, eax
    jge .client
    push rbx
    mov rdi, rbx
    call window_focus
    pop rbx
    mov [active_window], rbx
    mov byte [dragging], 1
    jmp .done
.client:
    ; 客户区：聚焦 + 通知应用
    push rbx
    mov rdi, rbx
    call window_focus
    pop rbx
    mov [active_window], rbx
    mov rax, [rbx + Window.input_fn]
    test rax, rax
    jz .done
    push rbx
    mov rdi, rbx
    mov esi, UI_EV_MOUSE_DOWN
    mov edx, [mouse_x]
    sub edx, [rbx + Window.x]
    mov ecx, [mouse_y]
    sub ecx, [rbx + Window.y]
    sub ecx, TITLE_HEIGHT
    mov r8d, [mouse_state + MouseState.buttons]
    xor r9d, r9d
    mov r10, rax
    call r10
    pop rbx
    jmp .done
.next_win:
    mov rbx, [rbx + Window.next]
    jmp .hit_loop
.done:
    pop r13
    pop r12
    pop rbx
    leave
    ret

; 鼠标左键抬起：通知光标下窗口的 input_fn
wm_mouse_up_app:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    mov r12d, [mouse_x]
    mov r13d, [mouse_y]
    mov rbx, [window_list]
.loop:
    test rbx, rbx
    jz .done
    mov eax, [rbx + Window.x]
    cmp r12d, eax
    jl .next
    add eax, [rbx + Window.width]
    cmp r12d, eax
    jge .next
    mov eax, [rbx + Window.y]
    cmp r13d, eax
    jl .next
    add eax, [rbx + Window.height]
    cmp r13d, eax
    jge .next
    mov rax, [rbx + Window.input_fn]
    test rax, rax
    jz .next
    mov rdi, rbx
    mov esi, UI_EV_MOUSE_UP
    mov edx, r12d
    sub edx, [rbx + Window.x]
    mov ecx, r13d
    sub ecx, [rbx + Window.y]
    sub ecx, TITLE_HEIGHT
    mov r8d, [mouse_state + MouseState.buttons]
    xor r9d, r9d
    mov r10, rax
    call r10
    jmp .done
.next:
    mov rbx, [rbx + Window.next]
    jmp .loop
.done:
    pop r13
    pop r12
    pop rbx
    leave
    ret

; ---- 合成：桌面 -> 窗口（底到顶）-> 光标 ----
wm_redraw:
    push rbx
    call draw_desktop
    mov rdi, [window_list]
    call wm_draw_windows
    call draw_cursor
    pop rbx
    ret

; 递归：先画后面的窗口
wm_draw_windows:
    test rdi, rdi
    jz .done
    push rdi
    mov rdi, [rdi + Window.next]
    call wm_draw_windows
    pop rdi
    ; 先画柔和阴影，再画窗口本体
    push rbx
    mov rbx, rdi
    mov edi, [rbx + Window.x]
    mov esi, [rbx + Window.y]
    mov edx, [rbx + Window.width]
    mov ecx, [rbx + Window.height]
    mov r8d, 5
    call fb_drop_shadow
    mov rdi, rbx
    pop rbx
    call window_draw
.done:
    ret

; ---- 窗口绘制：边框 + 标题栏 + 客户区合成 ----
global window_draw
window_draw:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    ; 屏幕外剔除
    mov eax, [r12 + Window.x]
    cmp eax, [fb_width]
    jae .out
    mov eax, [r12 + Window.y]
    cmp eax, [fb_height]
    jae .out
    ; ===== 极简浅色窗口框 =====
    mov r13d, [r12 + Window.x]
    mov r14d, [r12 + Window.y]
    mov r15d, [r12 + Window.width]
    ; 焦点强调条（窗口顶部 2px）
    test dword [r12 + Window.flags], WIN_FLAG_FOCUSED
    jz .no_accent
    mov edi, r13d
    mov esi, r14d
    mov edx, r15d
    mov ecx, 2
    mov r8d, THEME_ACCENT
    call fb_draw_rect
.no_accent:
    ; 标题栏浅渐变（2px 起）
    mov eax, r14d
    add eax, 2
    mov ebx, eax                        ; ty
    mov r9d, TITLE_HEIGHT - 2
    xor r10d, r10d
.grad_loop:
    cmp r10d, r9d
    jae .grad_done
    mov r11d, THEME_TITLE_TOP
    mov eax, r9d
    shr eax, 1
    cmp r10d, eax
    jl .grad_color
    mov r11d, THEME_TITLE_BOT
.grad_color:
    mov edi, r13d
    mov esi, ebx
    mov edx, r15d
    mov ecx, 1
    mov r8d, r11d
    push rbx
    push r9
    push r10
    push r11
    call fb_draw_rect
    pop r11
    pop r10
    pop r9
    pop rbx
    inc ebx
    inc r10d
    jmp .grad_loop
.grad_done:
    ; 外框
    mov edi, r13d
    mov esi, r14d
    mov edx, r15d
    mov ecx, [r12 + Window.height]
    mov r8d, THEME_WIN_BORDER
    mov r9d, 1
    call fb_draw_border
    ; 标题文字（居中，深灰）
    lea rdi, [r12 + Window.title]
    call fb_text_width_utf8
    mov ecx, r15d
    sub ecx, eax
    shr ecx, 1
    add ecx, r13d
    mov edi, ecx
    mov esi, r14d
    add esi, 4
    lea rdx, [r12 + Window.title]
    mov ecx, THEME_TITLE_TXT
    mov r8d, -1
    call fb_draw_string
    ; 关闭按钮（浅灰圆角方块 + ×）
    mov edi, r13d
    add edi, r15d
    sub edi, 18
    mov esi, r14d
    add esi, 2
    mov edi, r13d
    add edi, r15d
    sub edi, 18
    mov esi, r14d
    add esi, 2
    mov edx, 16
    mov ecx, 16
    mov r8d, THEME_BTN_BOT
    call fb_draw_rect
    mov edi, r13d
    add edi, r15d
    sub edi, 18
    mov esi, r14d
    add esi, 2
    mov edx, 16
    mov ecx, 16
    mov r8d, THEME_FIELD_EDGE
    mov r9d, 1
    call fb_draw_border
    ; ×：字符 'x'
    mov edi, r13d
    add edi, r15d
    sub edi, 13
    mov esi, r14d
    add esi, 6
    mov edx, 'x'
    mov ecx, 0xFF9AA4B0
    mov r8d, -1
    call fb_draw_char
    ; 客户区
    mov rdi, [r12 + Window.backbuffer]
    test rdi, rdi
    jz .no_client
    mov esi, [r12 + Window.width]
    mov edx, [r12 + Window.height]
    sub edx, TITLE_HEIGHT
    mov ecx, esi
    shl ecx, 2
    call fb_set_target
    mov rax, [r12 + Window.paint_fn]
    test rax, rax
    jz .default_paint
    mov rdi, r12
    call rax
    jmp .painted
.default_paint:
    mov rdi, r12
    call window_paint_default
.painted:
    call fb_reset_target
    ; blit 到主缓冲
    mov rdi, [r12 + Window.backbuffer]
    mov esi, [r12 + Window.width]
    shl esi, 2
    mov edx, [r12 + Window.x]
    add edx, 1
    mov ecx, [r12 + Window.y]
    add ecx, TITLE_HEIGHT
    mov r8d, [r12 + Window.width]
    sub r8d, 2
    mov r9d, [r12 + Window.height]
    sub r9d, TITLE_HEIGHT
    call fb_blit
.no_client:
    ; 标题栏区域脏
    mov edi, [r12 + Window.x]
    mov esi, [r12 + Window.y]
    mov edx, [r12 + Window.width]
    mov ecx, TITLE_HEIGHT + 2
    call fb_mark_dirty
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; ---- 默认客户区绘制器（浅色极简） ----
window_paint_default:                   ; rdi = win
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    ; 客户区底色
    mov edi, 0xFFFFFFFF
    call fb_clear
    ; 顶部浅灰信息区
    mov edi, 0
    mov esi, 0
    mov edx, [r12 + Window.width]
    mov ecx, 1
    mov r8d, THEME_WIN_BORDER
    call fb_draw_rect
    ; 标题
    mov edi, 10
    mov esi, 12
    lea rdx, [r12 + Window.title]
    mov ecx, THEME_TEXT
    mov r8d, -1
    call fb_draw_string
    ; id
    lea rdi, [wm_linebuf]
    mov esi, [r12 + Window.id]
    movzx esi, si
    call format_dec64
    mov edi, 10
    mov esi, 32
    lea rdx, [wm_linebuf]
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    call fb_draw_string
    ; 尺寸
    lea rdi, [wm_linebuf]
    mov esi, [r12 + Window.width]
    movzx esi, si
    call format_dec64
    mov edi, 10
    mov esi, 50
    lea rdx, [wm_linebuf]
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    call fb_draw_string
    ; 焦点提示
    test dword [r12 + Window.flags], WIN_FLAG_FOCUSED
    jz .not_focused
    mov edi, 10
    mov esi, 70
    lea rdx, [str_focus]
    mov ecx, THEME_ACCENT
    mov r8d, -1
    call fb_draw_string
.not_focused:
    ; 键盘输入回显
    mov edi, 10
    mov esi, 90
    lea rdx, [str_input]
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    call fb_draw_string
    mov edi, 58
    mov esi, 90
    lea rdx, [key_text]
    mov ecx, THEME_TEXT
    mov r8d, -1
    call fb_draw_string
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

section .rodata
str_id     db "id=", 0
str_x      db " x ", 0
str_focus  db "[FOCUSED]", 0
str_input  db ">", 0
