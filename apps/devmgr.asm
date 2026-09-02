; apps/devmgr.asm - 设备管理器（驱动列表 + 硬件测试）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "window.inc"
%include "ui.inc"
%include "driver.inc"

global devmgr_launch, devmgr_paint, devmgr_input

extern window_create, window_focus
extern fb_clear, fb_draw_rect, fb_draw_hline, fb_draw_string
extern ui_button, ui_draw_all, ui_mouse_event, ui_key_event
extern drv_list
extern speaker_beep_ms
extern serial_printf

section .data
devmgr_win: dq 0

section .rodata
dm_title db "设备管理器", 0
dm_btn_beep db "测试蜂鸣器", 0
dm_hdr  db "驱动列表", 0
dm_row  db 0

section .text

devmgr_launch:
    mov rdi, [devmgr_win]
    test rdi, rdi
    jz .create
    call window_focus
    ret
.create:
    mov rdi, dm_title
    mov esi, 60
    mov edx, 320
    mov ecx, 360
    mov r8d, 260
    call window_create
    test rax, rax
    jz .done
    mov [devmgr_win], rax
    mov qword [rax + Window.paint_fn], devmgr_paint
    mov qword [rax + Window.input_fn], devmgr_input
    mov rdi, rax
    mov esi, 6
    mov edx, 6
    mov ecx, 120
    mov r8d, 26
    lea r9, [dm_btn_beep]
    push cb_beep
    call ui_button
    add rsp, 8
.done:
    ret

devmgr_paint:                           ; rdi = win
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
    ; 表头
    mov edi, 8
    mov esi, 40
    lea rdx, [dm_hdr]
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    call fb_draw_string
    mov edi, 0
    mov esi, 56
    mov edx, [r12 + Window.width]
    mov ecx, THEME_TASKBAR_LN
    call fb_draw_hline
    ; 驱动列表
    mov rbx, [drv_list]
    mov r13, 8
    mov r14, 66
.row:
    test rbx, rbx
    jz .done
    ; 名称
    mov rdi, r13
    mov rsi, r14
    mov rdx, [rbx + Driver.name]
    mov ecx, THEME_TEXT
    mov r8d, -1
    push rbx
    push r13
    push r14
    call fb_draw_string
    pop r14
    pop r13
    pop rbx
    ; kind/state
    mov edi, r13d
    add edi, 170
    mov rsi, r14
    lea rdx, [dm_kindtxt]
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    push rbx
    push r13
    push r14
    call fb_draw_string
    pop r14
    pop r13
    pop rbx
    add r14, 20
    mov eax, [r12 + Window.height]
    sub eax, 14
    cmp r14d, eax
    jae .done
    mov rbx, [rbx + Driver.next]
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

devmgr_input:
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

cb_beep:
    mov rdi, 880
    mov esi, 200
    call speaker_beep_ms
    mov rdi, 440
    mov esi, 200
    call speaker_beep_ms
    ret

section .rodata
dm_kindtxt db "硬件", 0
