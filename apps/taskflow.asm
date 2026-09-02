; apps/taskflow.asm - TaskFlow 任务看板（PRD P0 子集）
; 列：To Do / In Progress / Done；支持新增、移动、删除、搜索、优先级、保存/载入
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "window.inc"
%include "ui.inc"
%include "vfs.inc"

global taskflow_launch, tf_paint, tf_input

extern window_create, window_focus
extern kmalloc, kfree
extern fb_clear, fb_draw_rect, fb_draw_hline
extern fb_draw_string
extern ui_button, ui_textfield, ui_draw_all, ui_mouse_event, ui_key_event
extern vfs_add_blob, vfs_find
extern strcmp

struc Task
    .title resb 64
    .owner resb 20
    .prio  resd 1
    .status resd 1
    .next  resq 1
endstruc

section .data
tf_win: dq 0
tf_head: dq 0
tf_sel: dq 0

btn_add    db "添加", 0
btn_save   db "保存", 0
btn_load   db "载入", 0
btn_left   db "<-", 0
btn_right  db "->", 0
btn_prio   db "优先级", 0
btn_del    db "删除", 0
fld_search db "搜索 / 新任务标题", 0
tf_title0  db "任务看板 TaskFlow", 0

col_todo db "待办", 0
col_doing db "进行中", 0
col_done db "已完成", 0
col_names:
    dq col_todo, col_doing, col_done

p_urgent db "紧急", 0
p_high   db "高", 0
p_mid    db "中", 0
p_low    db "低", 0
prio_names:
    dq p_urgent, p_high, p_mid, p_low

prio_colors:
    dd PRIO_URGENT, PRIO_HIGH, PRIO_MID, PRIO_LOW

seed1 db "界面主题重构", 0
seed2 db "软件包管理", 0
seed3 db "驱动扩展", 0
seed4 db "编写文档", 0
generic db "新任务", 0

section .bss
tf_filter: resb 80

section .text

taskflow_launch:
    mov rdi, [tf_win]
    test rdi, rdi
    jz .create
    call window_focus
    ret
.create:
    mov rdi, tf_title0
    mov esi, 70
    mov edx, 40
    mov ecx, 880
    mov r8d, 560
    call window_create
    test rax, rax
    jz .done
    mov [tf_win], rax
    mov qword [rax + Window.paint_fn], tf_paint
    mov qword [rax + Window.input_fn], tf_input
    call tf_make_controls
    call tf_seed
.done:
    ret

tf_make_controls:
    mov rdi, [tf_win]
    mov esi, 8
    mov edx, 8
    mov ecx, 88
    mov r8d, 26
    lea r9, [btn_add]
    push cb_add
    call ui_button
    add rsp, 8
    mov rdi, [tf_win]
    mov esi, 102
    mov edx, 8
    mov ecx, 60
    mov r8d, 26
    lea r9, [btn_save]
    push cb_save
    call ui_button
    add rsp, 8
    mov rdi, [tf_win]
    mov esi, 168
    mov edx, 8
    mov ecx, 60
    mov r8d, 26
    lea r9, [btn_load]
    push cb_load
    call ui_button
    add rsp, 8
    mov rdi, [tf_win]
    mov esi, 320
    mov edx, 8
    mov ecx, 210
    mov r8d, 26
    lea r9, [fld_search]
    push cb_search
    call ui_textfield
    add rsp, 8
    mov rdi, [tf_win]
    mov esi, 600
    mov edx, 8
    mov ecx, 40
    mov r8d, 26
    lea r9, [btn_left]
    push cb_left
    call ui_button
    add rsp, 8
    mov rdi, [tf_win]
    mov esi, 646
    mov edx, 8
    mov ecx, 40
    mov r8d, 26
    lea r9, [btn_right]
    push cb_right
    call ui_button
    add rsp, 8
    mov rdi, [tf_win]
    mov esi, 692
    mov edx, 8
    mov ecx, 84
    mov r8d, 26
    lea r9, [btn_prio]
    push cb_prio
    call ui_button
    add rsp, 8
    mov rdi, [tf_win]
    mov esi, 782
    mov edx, 8
    mov ecx, 78
    mov r8d, 26
    lea r9, [btn_del]
    push cb_del
    call ui_button
    add rsp, 8
    ret

tf_seed:
    lea rdi, [seed1]
    mov esi, 1
    xor edx, edx
    call tf_add
    lea rdi, [seed2]
    mov esi, 0
    mov edx, 1
    call tf_add
    lea rdi, [seed3]
    mov esi, 2
    xor edx, edx
    call tf_add
    lea rdi, [seed4]
    mov esi, 3
    mov edx, 2
    call tf_add
    ret

; Task *tf_add(title, prio, status)
tf_add:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    mov rdi, Task_size
    call kmalloc
    test rax, rax
    jz .done
    mov rbx, rax
    lea rdi, [rbx + Task.title]
    mov rsi, r12
    call cpystr
    lea rdi, [rbx + Task.owner]
    mov byte [rdi], 0
    mov [rbx + Task.prio], r13d
    mov [rbx + Task.status], r14d
    mov rax, [tf_head]
    mov [rbx + Task.next], rax
    mov [tf_head], rbx
    mov rax, rbx
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

cpystr:
    push rdi
    push rsi
.loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rsi
    inc rdi
    jmp .loop
.done:
    pop rsi
    pop rdi
    ret

; ===== 绘制 =====
tf_paint:                               ; rdi=win
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
    ; 列头分隔线
    mov edi, 0
    mov esi, 44
    mov edx, [r12 + Window.width]
    mov ecx, THEME_TASKBAR_LN
    call fb_draw_hline
    ; 三列
    xor r14d, r14d
.col:
    cmp r14d, 3
    jae .cols_done
    mov eax, r14d
    imul eax, 290
    add eax, 10
    mov r15d, eax
    ; 列背景
    mov edi, r15d
    mov esi, 52
    mov edx, 275
    mov ecx, [r12 + Window.height]
    sub ecx, 68
    mov r8d, THEME_COL_BG
    call fb_draw_rect
    ; 列标题 + 计数
    mov edi, r15d
    add edi, 12
    mov esi, 58
    lea rax, [col_names]
    mov rdx, [rax + r14*8]
    mov ecx, THEME_TEXT
    mov r8d, THEME_COL_BG
    call fb_draw_string
    ; 卡片
    mov rbx, [tf_head]
    mov r13d, 84
.card:
    test rbx, rbx
    jz .col_next
    mov eax, [rbx + Task.status]
    cmp eax, r14d
    jne .card_next
    ; 过滤
    cmp byte [tf_filter], 0
    je .draw
    lea rdi, [rbx + Task.title]
    call tf_match
    test rax, rax
    jz .card_next
.draw:
    call tf_draw_card
    add r13, 76
    mov eax, [r12 + Window.height]
    sub eax, 82
    cmp r13d, eax
    jae .col_next
.card_next:
    mov rbx, [rbx + Task.next]
    jmp .card
.col_next:
    inc r14d
    jmp .col
.cols_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; 绘制卡片 rbx（列 x=r15d, y=r13d）
tf_draw_card:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, r15d
    mov r14d, r13d
    ; 选中高亮底
    cmp rbx, [tf_sel]
    jne .norm
    mov edi, r12d
    mov esi, r14d
    mov edx, 262
    mov ecx, 72
    mov r8d, THEME_SEL
    call fb_draw_rect
.norm:
    ; 卡片
    mov edi, r12d
    mov esi, r14d
    mov edx, 262
    mov ecx, 72
    mov r8d, THEME_CARD_BG
    call fb_draw_rect
    ; 优先级色条
    mov eax, [rbx + Task.prio]
    lea r15, [prio_colors]
    mov r8d, [r15 + rax*4]
    mov edi, r12d
    mov esi, r14d
    mov edx, 4
    mov ecx, 72
    call fb_draw_rect
    ; 标题
    mov edi, r12d
    add edi, 12
    mov esi, r14d
    add esi, 8
    lea rdx, [rbx + Task.title]
    mov ecx, THEME_TEXT
    mov r8d, -1
    call fb_draw_string
    ; owner
    cmp byte [rbx + Task.owner], 0
    je .no_owner
    mov edi, r12d
    add edi, 12
    mov esi, r14d
    add esi, 28
    lea rdx, [rbx + Task.owner]
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    call fb_draw_string
.no_owner:
    ; 优先级文本
    mov eax, [rbx + Task.prio]
    lea r15, [prio_names]
    mov rdx, [r15 + rax*8]
    mov edi, r12d
    add edi, 12
    mov esi, r14d
    add esi, 50
    mov ecx, THEME_TEXT_DIM
    mov r8d, -1
    call fb_draw_string
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; rdi=str 是否包含 filter
tf_match:
    lea rsi, [tf_filter]
.outer:
    mov al, [rsi]
    test al, al
    jz .found
    push rdi
    push rsi
.inner:
    mov cl, [rdi]
    test cl, cl
    jz .next
    cmp cl, al
    jne .adv
    inc rdi
    inc rsi
    mov dl, [rsi]
    test dl, dl
    jz .foundp
    jmp .inner
.adv:
    inc rdi
    jmp .inner
.next:
    pop rsi
    pop rdi
    inc rsi
    jmp .outer
.foundp:
    pop rsi
    pop rdi
.found:
    mov rax, 1
    ret

; ===== 输入 =====
tf_input:                               ; rdi,esi,edx,ecx,r8d,r9d
    push rbp
    mov rbp, rsp
    push r8
    push r9
    cmp esi, UI_EV_KEY
    je .key
    call ui_mouse_event
    cmp esi, UI_EV_MOUSE_DOWN
    jne .out
    call tf_pick
    jmp .out
.key:
    mov esi, r9d
    call ui_key_event
.out:
    pop r9
    pop r8
    leave
    ret

tf_pick:                                ; edx=x, ecx=y（客户区）
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12d, edx
    mov r13d, ecx
    cmp r13d, 82
    jl .none
    mov rbx, [tf_head]
.loop:
    test rbx, rbx
    jz .none
    ; 卡片几何：col = status, y = 84 + rank*76
    call tf_card_y                      ; eax = y
    mov r14d, eax
    ; x 范围
    mov eax, [rbx + Task.status]
    imul eax, 290
    add eax, 10
    cmp r12d, eax
    jl .next
    add eax, 262
    cmp r12d, eax
    jge .next
    ; y 范围
    cmp r13d, r14d
    jl .next
    add eax, 0
    mov eax, r14d
    add eax, 72
    cmp r13d, eax
    jge .next
    mov [tf_sel], rbx
    jmp .done
.next:
    mov rbx, [rbx + Task.next]
    jmp .loop
.none:
    mov qword [tf_sel], 0
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; eax = 卡片 y（rbx 在其列中的序号 *76 + 84）
tf_card_y:
    push rcx
    push rdx
    push r8
    mov eax, 84
    mov rcx, [tf_head]
.loop:
    test rcx, rcx
    jz .done
    cmp rcx, rbx
    je .done
    mov edx, [rcx + Task.status]
    cmp edx, [rbx + Task.status]
    jne .next
    add eax, 76
.next:
    mov rcx, [rcx + Task.next]
    jmp .loop
.done:
    pop r8
    pop rdx
    pop rcx
    ret

; ===== 回调 =====
cb_add:
    call tf_read_filter
    cmp byte [tf_filter], 0
    jne .use
    lea rsi, [generic]
    lea rdi, [tf_filter]
    call cpystr
.use:
    lea rdi, [tf_filter]
    mov esi, 2
    xor edx, edx
    call tf_add
    call tf_clear_search
    ret
cb_save:
    call tf_save
    ret
cb_load:
    call tf_load
    ret
cb_search:
    call tf_read_filter
    ret
cb_left:
    mov rdi, [tf_sel]
    test rdi, rdi
    jz .done
    mov eax, [rdi + Task.status]
    test eax, eax
    jle .done
    dec eax
    mov [rdi + Task.status], eax
.done:
    ret
cb_right:
    mov rdi, [tf_sel]
    test rdi, rdi
    jz .done
    mov eax, [rdi + Task.status]
    cmp eax, 2
    jge .done
    inc eax
    mov [rdi + Task.status], eax
.done:
    ret
cb_prio:
    mov rdi, [tf_sel]
    test rdi, rdi
    jz .done
    mov eax, [rdi + Task.prio]
    inc eax
    cmp eax, 4
    jl .store
    xor eax, eax
.store:
    mov [rdi + Task.prio], eax
.done:
    ret
cb_del:
    call tf_del_sel
    ret

tf_read_filter:
    mov rdi, [tf_win]
    mov rax, [rdi + Window.controls]
.loop:
    test rax, rax
    jz .done
    cmp dword [rax + Control.type], CTRL_FIELD
    jne .next
    lea rsi, [rax + Control.value]
    lea rdi, [tf_filter]
    call cpystr
    jmp .done
.next:
    mov rax, [rax + Control.next]
    jmp .loop
.done:
    ret

tf_clear_search:
    mov rdi, [tf_win]
    mov rax, [rdi + Window.controls]
.loop:
    test rax, rax
    jz .done
    cmp dword [rax + Control.type], CTRL_FIELD
    jne .next
    mov byte [rax + Control.value], 0
    jmp .done
.next:
    mov rax, [rax + Control.next]
    jmp .loop
.done:
    ret

tf_del_sel:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, [tf_sel]
    test r12, r12
    jz .done
    mov rbx, [tf_head]
    cmp rbx, r12
    jne .walk
    mov rax, [r12 + Task.next]
    mov [tf_head], rax
    jmp .free
.walk:
    cmp [rbx + Task.next], r12
    je .unlink
    mov rbx, [rbx + Task.next]
    jmp .walk
.unlink:
    mov rax, [r12 + Task.next]
    mov [rbx + Task.next], rax
.free:
    mov rdi, r12
    call kfree
    mov qword [tf_sel], 0
.done:
    pop r12
    pop rbx
    leave
    ret

; ===== 持久化 tasks.tsk =====
tf_save:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    ; 统计
    mov rbx, [tf_head]
    xor r12d, r12d
.count:
    test rbx, rbx
    jz .cnt
    inc r12d
    mov rbx, [rbx + Task.next]
    jmp .count
.cnt:
    mov edi, r12d
    imul edi, Task_size
    add edi, 16
    mov r13d, edi
    call kmalloc
    test rax, rax
    jz .done
    mov rbx, rax
    mov rax, 0x4F4C46574F4C5454         ; "TTLOWFLO" 魔数
    mov [rbx], rax
    mov [rbx + 8], r12d
    ; 依次复制
    lea rdi, [rbx + 16]
    mov rcx, [tf_head]
.copy:
    test rcx, rcx
    jz .copied
    mov rsi, rcx
    push rcx
    push rdi
    mov ecx, Task_size
    rep movsb
    pop rdi
    pop rcx
    add rdi, Task_size
    mov rcx, [rcx + Task.next]
    jmp .copy
.copied:
    lea rdi, [tsk_fname]
    mov esi, VFT_RAW
    mov rdx, rbx
    mov ecx, r13d
    push rbx
    call vfs_add_blob
    pop rbx
    mov rdi, rbx
    call kfree
.done:
    pop r13
    pop r12
    pop rbx
    leave
    ret

tf_load:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    lea rdi, [tsk_fname]
    call vfs_find
    test rax, rax
    jz .done
    mov r12, [rax + VFile.data]
    ; 清空旧列表
    call tf_del_all
    mov ecx, [r12 + 8]
    lea r8, [r12 + 16]
.loop:
    test ecx, ecx
    jz .done
    mov rdi, Task_size
    call kmalloc
    test rax, rax
    jz .done
    mov rbx, rax
    lea rdi, [rbx]
    mov rsi, r8
    mov edx, Task_size
    push rcx
    push r8
    call copybytes
    pop r8
    pop rcx
    mov rax, [tf_head]
    mov [rbx + Task.next], rax
    mov [tf_head], rbx
    add r8, Task_size
    dec ecx
    jmp .loop
.done:
    pop r12
    pop rbx
    leave
    ret

copybytes:
    push rcx
    mov rcx, rdx
    rep movsb
    pop rcx
    ret

tf_del_all:
    push rbp
    mov rbp, rsp
.loop:
    mov rdi, [tf_head]
    test rdi, rdi
    jz .done
    mov rax, [rdi + Task.next]
    mov [tf_head], rax
    call kfree
    jmp .loop
.done:
    leave
    ret

section .rodata
tsk_fname db "tasks.tsk", 0
