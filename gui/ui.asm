; gui/ui.asm - 极简控件系统（按钮 / 文本框 / 标签）
; 控件坐标为窗口客户区相对坐标；绘制前提：target 已切换到窗口 backbuffer
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "window.inc"
%include "ui.inc"

global ui_button, ui_textfield, ui_label, ui_draw_all
global ui_mouse_event, ui_key_event, ui_in_rect

extern kmalloc
extern fb_draw_rect, fb_draw_hline, fb_draw_vline, fb_draw_border
extern fb_draw_string, fb_mark_dirty
extern fb_text_width_utf8
extern strlen

section .text

; 命中测试：int ui_in_rect(x, y, rx, ry, rw, rh)
ui_in_rect:
    cmp edi, edx
    jl .miss
    cmp edi, edx
    jge .x_ok
.miss:
    xor eax, eax
    ret
.x_ok:
    mov eax, edx
    add eax, r8d
    cmp edi, eax
    jge .miss
    cmp esi, ecx
    jl .miss
    mov eax, ecx
    add eax, r9d
    cmp esi, eax
    jge .miss
    mov eax, 1
    ret

; ---- 内部：追加控件到窗口 ----
ui_attach:                              ; rdi=win, rsi=ctrl
    mov rax, [rdi + Window.controls]
    test rax, rax
    jnz .walk
    mov [rdi + Window.controls], rsi
    mov qword [rsi + Control.next], 0
    ret
.walk:
    cmp qword [rax + Control.next], 0
    je .tail
    mov rax, [rax + Control.next]
    jmp .walk
.tail:
    mov [rax + Control.next], rsi
    mov qword [rsi + Control.next], 0
    ret

; ---- 分配并初始化控件 ----
ui_alloc_ctrl:
    push rbx
    mov rdi, Control_size
    call kmalloc
    test rax, rax
    jz .done
    mov rbx, rax
    mov dword [rbx + Control.type], 0
    mov dword [rbx + Control.state], 0
    mov qword [rbx + Control.cb], 0
    mov qword [rbx + Control.next], 0
    mov rax, rbx
.done:
    pop rbx
    ret

; Control *ui_button(win, x, y, w, h, label, cb)
; 参数：rdi=win, esi=x, edx=y, ecx=w, r8d=h, r9=label；cb 在栈 [rsp+8]
ui_button:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; win
    mov r13d, esi
    mov r14d, edx
    mov ebx, ecx
    mov r15d, r8d
    call ui_alloc_ctrl
    test rax, rax
    jz .done
    mov rdi, rax                        ; ctrl
    mov dword [rdi + Control.type], CTRL_BUTTON
    mov [rdi + Control.x], r13d
    mov [rdi + Control.y], r14d
    mov [rdi + Control.w], ebx
    mov [rdi + Control.h], r15d
    mov rcx, [rbp + 16]                 ; cb
    mov [rdi + Control.cb], rcx
    ; 复制 label（最长 39）
    mov rdx, r9
    lea rsi, [rdi + Control.label]
    push rdi
    mov rdi, rsi
    mov rsi, rdx
    call ui_cpyn
    pop rdi
    mov rsi, rdi
    mov rdi, r12
    call ui_attach
    mov rax, rsi
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; Control *ui_textfield(win, x, y, w, h, label, cb)
ui_textfield:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    mov ebx, ecx
    mov r15d, r8d
    call ui_alloc_ctrl
    test rax, rax
    jz .done
    mov rdi, rax
    mov dword [rdi + Control.type], CTRL_FIELD
    mov [rdi + Control.x], r13d
    mov [rdi + Control.y], r14d
    mov [rdi + Control.w], ebx
    mov [rdi + Control.h], r15d
    mov rcx, [rbp + 16]
    mov [rdi + Control.cb], rcx
    mov rdx, r9
    lea rsi, [rdi + Control.label]
    push rdi
    mov rdi, rsi
    mov rsi, rdx
    call ui_cpyn
    pop rdi
    mov byte [rdi + Control.value], 0
    mov rsi, rdi
    mov rdi, r12
    call ui_attach
    mov rax, rsi
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; Control *ui_label(win, x, y, text)
ui_label:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    call ui_alloc_ctrl
    test rax, rax
    jz .done
    mov rdi, rax
    mov dword [rdi + Control.type], CTRL_LABEL
    mov [rdi + Control.x], r13d
    mov [rdi + Control.y], r14d
    mov dword [rdi + Control.w], 0
    mov dword [rdi + Control.h], 16
    lea rsi, [rdi + Control.label]
    mov rdx, r8
    push rdi
    mov rdi, rsi
    call ui_cpyn
    pop rdi
    mov rsi, rdi
    mov rdi, r12
    call ui_attach
    mov rax, rsi
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; 复制字符串到固定缓冲（最多 dst 容量-1 字节，64 位终止）
; rdi=dst, rsi=src, dst 容量由调用点保证（label 40 / value 192）
ui_cpyn:
    push rdi
    push rsi
    xor rcx, rcx
.loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rsi
    inc rdi
    inc rcx
    cmp rcx, 191
    jb .loop
    mov byte [rdi], 0
.done:
    pop rsi
    pop rdi
    ret

; ---- 绘制全部控件 ----
ui_draw_all:                            ; rdi = win
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, [rdi + Window.controls]
.loop:
    test rbx, rbx
    jz .done
    mov eax, [rbx + Control.type]
    cmp eax, CTRL_BUTTON
    je .draw_btn
    cmp eax, CTRL_FIELD
    je .draw_field
    cmp eax, CTRL_LABEL
    je .draw_label
    jmp .next
.draw_btn:
    call ui_draw_button
    jmp .next
.draw_field:
    call ui_draw_field
    jmp .next
.draw_label:
    call ui_draw_label
.next:
    mov rbx, [rbx + Control.next]
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; 绘制按钮（rbx = ctrl）
ui_draw_button:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, [rbx + Control.x]
    mov r13d, [rbx + Control.y]
    mov r14d, [rbx + Control.w]
    mov r15d, [rbx + Control.h]
    mov eax, [rbx + Control.state]
    and eax, CTRL_ST_PRESSED
    jz .normal
    ; 按下：暗底 + 内阴影
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    mov r8d, THEME_BTN_BOT
    call fb_draw_rect
    ; 顶部 1px 暗线（按下感）
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, THEME_BTN_EDGE
    call fb_draw_hline
    jmp .label
.normal:
    ; 立体感：上半亮、下半暗 + 底/右边 1px 深色边 + 顶/左 1px 亮边
    mov eax, r15d
    shr eax, 1
    push rax                        ; 保存 h/2（fb_draw_rect 会破坏 rax）
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, eax
    mov r8d, THEME_BTN_TOP
    call fb_draw_rect
    pop rax
    mov edi, r12d
    lea esi, [r13 + rax]
    mov edx, r14d
    mov ecx, r15d
    sub ecx, eax
    mov r8d, THEME_BTN_BOT
    call fb_draw_rect
    ; 亮顶边
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, 0xFFFFFFFF
    call fb_draw_hline
    ; 深底边 + 右边
    mov edi, r12d
    lea esi, [r13 + r15 - 1]
    mov edx, r14d
    mov ecx, 0xFFD0D6DE
    call fb_draw_hline
    mov edi, r12d
    add edi, r14d
    sub edi, 1
    mov esi, r13d
    mov edx, r15d
    mov ecx, 0xFFD0D6DE
    call fb_draw_vline
    ; 外框
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    mov r8d, THEME_BTN_EDGE
    mov r9d, 1
    call fb_draw_border
.label:
    ; 文字居中
    lea rdi, [rbx + Control.label]
    call fb_text_width_utf8
    mov ecx, r14d
    sub ecx, eax
    shr ecx, 1
    add ecx, r12d
    mov edi, ecx
    mov esi, r13d
    mov eax, r15d
    shr eax, 1
    sub eax, 8
    add esi, eax
    lea rdx, [rbx + Control.label]
    mov ecx, THEME_BTN_TXT
    mov r8d, -1
    call fb_draw_string
    ; 脏矩形
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    call fb_mark_dirty
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; 绘制文本框（rbx = ctrl）
ui_draw_field:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, [rbx + Control.x]
    mov r13d, [rbx + Control.y]
    mov r14d, [rbx + Control.w]
    mov r15d, [rbx + Control.h]
    ; 背景
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    mov r8d, THEME_FIELD_BG
    call fb_draw_rect
    ; 内阴影：顶部 1px 浅灰
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, 0xFFF1F3F6
    call fb_draw_hline
    ; 边框（焦点用主题蓝）
    mov eax, [rbx + Control.state]
    and eax, CTRL_ST_FOCUS
    jz .edge
    mov r8d, THEME_ACCENT
    jmp .draw_edge
.edge:
    mov r8d, THEME_FIELD_EDGE
.draw_edge:
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    mov r9d, 1
    call fb_draw_border
    ; 文本（label 作为提示在上方占位：不显示，仅绘制 value）
    mov edi, r12d
    add edi, 4
    mov esi, r13d
    mov eax, r15d
    shr eax, 1
    sub eax, 8
    add esi, eax
    lea rdx, [rbx + Control.value]
    mov ecx, THEME_TEXT
    mov r8d, THEME_FIELD_BG
    call fb_draw_string
    ; 脏矩形
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    call fb_mark_dirty
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; 绘制标签（rbx = ctrl）
ui_draw_label:
    push rbx
    push r12
    push r13
    mov edi, [rbx + Control.x]
    mov esi, [rbx + Control.y]
    lea rdx, [rbx + Control.label]
    mov ecx, THEME_TEXT
    mov r8d, -1
    call fb_draw_string
    pop r13
    pop r12
    pop rbx
    ret

; ---- 鼠标事件路由：ui_mouse_event(win, type, x, y)
ui_mouse_event:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; win
    mov r13d, esi                       ; type
    mov r14d, edx                       ; x
    mov r15d, ecx                       ; y
    mov rbx, [rdi + Window.controls]
    xor r8d, r8d
.loop:
    test rbx, rbx
    jz .done
    ; 命中测试
    mov edi, r14d
    mov esi, r15d
    mov edx, [rbx + Control.x]
    mov ecx, [rbx + Control.y]
    mov r8d, [rbx + Control.w]
    mov r9d, [rbx + Control.h]
    push rbx
    call ui_in_rect
    pop rbx
    test eax, eax
    jnz .hit
    jmp .next
.hit:
    cmp r13d, UI_EV_MOUSE_DOWN
    jne .up
    ; 按下：按钮进入按下态，文本框获得焦点
    mov eax, [rbx + Control.type]
    cmp eax, CTRL_BUTTON
    je .btn_press
    cmp eax, CTRL_FIELD
    je .field_focus
    jmp .next
.btn_press:
    or dword [rbx + Control.state], CTRL_ST_PRESSED
    mov [r12 + Window.ui_pressed], rbx
    jmp .done
.field_focus:
    ; 清除旧焦点
    push rbx
    mov rdi, r12                        ; ui_clear_focus(win)
    call ui_clear_focus                ; rdi=r12
    pop rbx
    or dword [rbx + Control.state], CTRL_ST_FOCUS
    mov [r12 + Window.ui_focus], rbx
    jmp .done
.up:
    cmp r13d, UI_EV_MOUSE_UP
    jne .next
    ; 松开：若在按下的按钮上则触发回调
    mov rax, [r12 + Window.ui_pressed]
    test rax, rax
    jz .next
    cmp rax, rbx
    jne .release
    mov eax, [rbx + Control.type]
    cmp eax, CTRL_BUTTON
    jne .release
    mov rax, [rbx + Control.cb]
    test rax, rax
    jz .release
    push rbx
    mov rdi, r12
    mov rsi, rbx
    call rax
    pop rbx
.release:
    and dword [rbx + Control.state], ~CTRL_ST_PRESSED
    mov qword [r12 + Window.ui_pressed], 0
    jmp .done
.next:
    mov rbx, [rbx + Control.next]
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

ui_clear_focus:                         ; rdi = win
    mov rbx, [rdi + Window.controls]
.loop:
    test rbx, rbx
    jz .done
    and dword [rbx + Control.state], ~CTRL_ST_FOCUS
    mov rbx, [rbx + Control.next]
    jmp .loop
.done:
    mov qword [rdi + Window.ui_focus], 0
    ret

; ---- 键盘事件：ui_key_event(win, ch)
ui_key_event:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13d, esi                       ; ch
    mov rbx, [rdi + Window.ui_focus]
    test rbx, rbx
    jz .done
    mov eax, [rbx + Control.type]
    cmp eax, CTRL_FIELD
    jne .done
    ; 文本框输入
    cmp r13d, 8
    je .back
    cmp r13d, 13
    je .enter
    cmp r13d, 32
    jb .done
    cmp r13d, 126
    ja .done
    lea rdi, [rbx + Control.value]
    call strlen
    cmp rax, 191
    jae .done
    lea rdi, [rbx + Control.value]
    add rdi, rax
    mov [rdi], r13b
    mov byte [rdi + 1], 0
    jmp .done
.back:
    lea rdi, [rbx + Control.value]
    call strlen
    test rax, rax
    jz .done
    lea rdi, [rbx + Control.value]
    add rdi, rax
    dec rdi
    mov byte [rdi], 0
    jmp .done
.enter:
    mov rax, [rbx + Control.cb]
    test rax, rax
    jz .done
    mov rdi, r12
    mov rsi, rbx
    call rax
.done:
    pop r13
    pop r12
    pop rbx
    ret
