; apps/center.asm - 软件中心（安装/卸载/打开）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "window.inc"
%include "ui.inc"
%include "pkg.inc"

global center_launch, center_paint, center_input

extern window_create, window_focus
extern fb_clear, fb_draw_rect, fb_draw_hline, fb_draw_string
extern ui_button, ui_draw_all, ui_mouse_event, ui_key_event
extern pkg_head
extern pkg_install, pkg_uninstall, pkg_run
extern console_clear
extern serial_printf

section .data
center_win: dq 0
center_sel: dq 0

btn_open db "打开", 0
btn_inst db "安装", 0
btn_uninst db "卸载", 0
ct_title db "软件中心", 0
st_inst  db "已安装", 0
st_free  db "未安装", 0
k_sys    db "系统", 0
k_app    db "应用", 0
k_drv    db "驱动", 0

section .text

center_launch:
    mov rdi, [center_win]
    test rdi, rdi
    jz .create
    call window_focus
    ret
.create:
    mov rdi, ct_title
    mov esi, 640
    mov edx, 320
    mov ecx, 340
    mov r8d, 430
    call window_create
    test rax, rax
    jz .done
    mov [center_win], rax
    mov qword [rax + Window.paint_fn], center_paint
    mov qword [rax + Window.input_fn], center_input
    mov rdi, rax
    mov esi, 6
    mov edx, 6
    mov ecx, 66
    mov r8d, 26
    lea r9, [btn_open]
    push cb_open
    call ui_button
    add rsp, 8
    mov rdi, [center_win]
    mov esi, 80
    mov edx, 6
    mov ecx, 80
    mov r8d, 26
    lea r9, [btn_inst]
    push cb_inst
    call ui_button
    add rsp, 8
    mov rdi, [center_win]
    mov esi, 168
    mov edx, 6
    mov ecx, 96
    mov r8d, 26
    lea r9, [btn_uninst]
    push cb_uninst
    call ui_button
    add rsp, 8
.done:
    ret

center_paint:                           ; rdi=win
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
    mov rdi, r12
    call ui_draw_all
    ; 列表头
    mov edi, 8
    mov esi, 44
    lea rdx, [ct_hdr]
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    call fb_draw_string
    mov edi, 0
    mov esi, 62
    mov edx, [r12 + Window.width]
    mov ecx, THEME_TASKBAR_LN
    call fb_draw_hline
    ; 包列表
    mov rbx, [pkg_head]
    mov r14, 10
    mov r15, 72
.row:
    test rbx, rbx
    jz .done
    ; 高亮选中
    cmp rbx, [center_sel]
    jne .nsel
    mov edi, 4
    mov esi, r15d
    sub esi, 4
    mov edx, [r12 + Window.width]
    sub edx, 8
    mov ecx, 24
    mov r8d, THEME_SEL
    call fb_draw_rect
.nsel:
    ; 名称
    mov rdi, r14
    mov rsi, r15
    mov rdx, [rbx + PkgEnt.name]
    mov ecx, THEME_TEXT
    mov r8d, -1
    push rbx
    push r14
    push r15
    call fb_draw_string
    pop r15
    pop r14
    pop rbx
    ; 类型
    mov eax, [rbx + PkgEnt.kind]
    lea rcx, [kind_txt]
    mov rdx, [rcx + rax*8]
    mov edi, r14d
    add edi, 160
    mov rsi, r15
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    push rbx
    push r14
    push r15
    call fb_draw_string
    pop r15
    pop r14
    pop rbx
    ; 状态
    mov eax, [rbx + PkgEnt.inst]
    lea rcx, [state_txt]
    mov rdx, [rcx + rax*8]
    mov edi, r14d
    add edi, 240
    mov rsi, r15
    mov ecx, [state_colors + rax*4]
    mov r8d, -1
    push rbx
    push r14
    push r15
    call fb_draw_string
    pop r15
    pop r14
    pop rbx
    add r15, 28
    mov eax, [r12 + Window.height]
    sub eax, 60
    cmp r15d, eax
    jae .done
    mov rbx, [rbx + PkgEnt.next]
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

center_input:                           ; rdi..r9d
    push rbp
    mov rbp, rsp
    push r8
    push r9
    cmp esi, UI_EV_KEY
    je .key
    call ui_mouse_event
    cmp esi, UI_EV_MOUSE_DOWN
    jne .out
    call center_pick
    jmp .out
.key:
    mov esi, r9d
    call ui_key_event
.out:
    pop r9
    pop r8
    leave
    ret

center_pick:                            ; edx=x, ecx=y
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edx
    mov r13d, ecx
    cmp r13d, 70
    jl .none
    mov rbx, [pkg_head]
    mov r14, 72
.loop:
    test rbx, rbx
    jz .none
    mov eax, r14d
    cmp r13d, eax
    jl .next
    add eax, 26
    cmp r13d, eax
    jge .next
    cmp r12d, 4
    jl .next
    mov [center_sel], rbx
    jmp .done
.next:
    add r14, 28
    mov rbx, [rbx + PkgEnt.next]
    jmp .loop
.none:
    mov qword [center_sel], 0
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

cb_open:
    mov rdi, [center_sel]
    test rdi, rdi
    jz .done
    mov rdi, [rdi + PkgEnt.name]
    call pkg_run
.done:
    ret
cb_inst:
    mov rdi, [center_sel]
    test rdi, rdi
    jz .done
    mov rdi, [rdi + PkgEnt.name]
    call pkg_install
.done:
    ret
cb_uninst:
    mov rdi, [center_sel]
    test rdi, rdi
    jz .done
    mov rdi, [rdi + PkgEnt.name]
    call pkg_uninstall
.done:
    ret

section .data
ct_hdr db "请选择一个软件包", 0
kind_txt:
    dq 0, k_app, k_drv, k_sys
state_txt:
    dq st_free, st_inst
state_colors:
    dd THEME_TEXT_DIM, 0xFF2E7D32
