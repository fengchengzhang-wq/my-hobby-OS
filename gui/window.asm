; gui/window.asm - 窗口对象生命周期
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "window.inc"

global window_create, window_destroy, window_move, window_focus
global window_list, window_id_counter

extern kmalloc, kfree, strcpy
extern fb_mark_dirty, fb_width, fb_height

section .data
global window_list
window_list: dq 0
window_id_counter: dd 1

section .text

; Window *window_create(title, x, y, w, h)
; rdi=title, esi=x, edx=y, ecx=w, r8d=h
window_create:
    push rbp
    mov rbp, rsp
    sub rsp, 16
    mov [rbp-8], edx                    ; y
    mov [rbp-16], r8d                   ; h
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; title
    mov r13d, esi                       ; x
    mov r15d, ecx                       ; w
    ; 分配窗口结构
    mov rdi, Window_size
    call kmalloc
    test rax, rax
    jz .fail
    mov rbx, rax                        ; win（rbx 跨调用保留）
    ; 分配客户区缓冲：(w * (h - TITLE_HEIGHT)) * 4
    mov eax, r15d
    mov ecx, [rbp-16]
    sub ecx, TITLE_HEIGHT
    jle .no_backbuf
    imul eax, ecx
    shl eax, 2
    mov rdi, rax
    push r12
    call kmalloc
    pop r12
    test rax, rax
    jz .free_win
    mov [rbx + Window.backbuffer], rax
    jmp .buf_ok
.no_backbuf:
    mov qword [rbx + Window.backbuffer], 0
.buf_ok:
    mov eax, [window_id_counter]
    mov [rbx + Window.id], eax
    inc dword [window_id_counter]
    mov [rbx + Window.x], r13d
    mov eax, [rbp-8]
    mov [rbx + Window.y], eax
    mov [rbx + Window.width], r15d
    mov eax, [rbp-16]
    mov [rbx + Window.height], eax
    mov dword [rbx + Window.flags], WIN_FLAG_VISIBLE | WIN_FLAG_CLOSEABLE
    mov qword [rbx + Window.paint_fn], 0
    mov qword [rbx + Window.input_fn], 0
    mov qword [rbx + Window.controls], 0
    mov qword [rbx + Window.ui_focus], 0
    mov qword [rbx + Window.ui_pressed], 0
    mov qword [rbx + Window.user], 0
    lea rdi, [rbx + Window.title]
    mov rsi, r12
    call strcpy
    ; 插入链表头（置顶）
    mov rax, [window_list]
    mov [rbx + Window.next], rax
    mov [window_list], rbx
    ; 标记脏矩形
    mov edi, [rbx + Window.x]
    mov esi, [rbx + Window.y]
    mov edx, [rbx + Window.width]
    mov ecx, [rbx + Window.height]
    call fb_mark_dirty
    mov rax, rbx
    jmp .done
.free_win:
    mov rdi, rbx
    call kfree
.fail:
    xor rax, rax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; void window_destroy(win)
window_destroy:
    push rbx
    push r12
    mov r12, rdi
    ; 标记脏
    mov edi, [r12 + Window.x]
    mov esi, [r12 + Window.y]
    mov edx, [r12 + Window.width]
    mov ecx, [r12 + Window.height]
    call fb_mark_dirty
    ; 从链表移除
    mov rbx, [window_list]
    cmp rbx, r12
    je .first
.search:
    test rbx, rbx
    jz .not_found
    cmp [rbx + Window.next], r12
    je .found
    mov rbx, [rbx + Window.next]
    jmp .search
.first:
    mov rax, [r12 + Window.next]
    mov [window_list], rax
    jmp .free
.found:
    mov rax, [r12 + Window.next]
    mov [rbx + Window.next], rax
.free:
    mov rdi, [r12 + Window.backbuffer]
    test rdi, rdi
    jz .no_buf
    call kfree
.no_buf:
    mov rdi, r12
    call kfree
.not_found:
    pop r12
    pop rbx
    ret

; void window_move(win, dx, dy)：边界检查
window_move:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, esi                       ; dx
    mov r14d, edx                       ; dy
    ; 旧位置脏
    mov edi, [r12 + Window.x]
    mov esi, [r12 + Window.y]
    mov edx, [r12 + Window.width]
    mov ecx, [r12 + Window.height]
    call fb_mark_dirty
    ; x = clamp(x + dx, 0, fb_width - w)
    mov eax, [r12 + Window.x]
    add eax, r13d
    mov ebx, eax
    test ebx, ebx
    jns .x_ok
    xor ebx, ebx
.x_ok:
    mov eax, [fb_width]
    sub eax, [r12 + Window.width]
    cmp ebx, eax
    jle .x_ok2
    mov ebx, eax
.x_ok2:
    mov [r12 + Window.x], ebx
    ; y = clamp(y + dy, 0, fb_height - TITLE_HEIGHT - h)
    mov eax, [r12 + Window.y]
    add eax, r14d
    mov ebx, eax
    test ebx, ebx
    jns .y_ok
    xor ebx, ebx
.y_ok:
    mov eax, [fb_height]
    sub eax, TITLE_HEIGHT
    sub eax, [r12 + Window.height]
    cmp ebx, eax
    jle .y_ok2
    mov ebx, eax
.y_ok2:
    mov [r12 + Window.y], ebx
    ; 新位置脏
    mov edi, [r12 + Window.x]
    mov esi, [r12 + Window.y]
    mov edx, [r12 + Window.width]
    mov ecx, [r12 + Window.height]
    call fb_mark_dirty
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; void window_focus(win)：置顶并设为焦点
window_focus:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, [window_list]
    cmp rbx, r12
    je .set_flags
    ; 从链表移除
    mov rdx, rbx                        ; prev
    cmp rdx, r12
    je .first
.search:
    test rdx, rdx
    jz .set_flags
    cmp [rdx + Window.next], r12
    je .found
    mov rdx, [rdx + Window.next]
    jmp .search
.found:
    mov rax, [r12 + Window.next]
    mov [rdx + Window.next], rax
    jmp .reinsert
.first:
    mov rax, [r12 + Window.next]
    mov [window_list], rax
.reinsert:
    mov rax, [window_list]
    mov [r12 + Window.next], rax
    mov [window_list], r12
.set_flags:
    ; 清除其他窗口焦点标志
    mov rbx, [window_list]
.clear_loop:
    test rbx, rbx
    jz .clear_done
    and dword [rbx + Window.flags], ~WIN_FLAG_FOCUSED
    mov rbx, [rbx + Window.next]
    jmp .clear_loop
.clear_done:
    or dword [r12 + Window.flags], WIN_FLAG_FOCUSED
    mov edi, [r12 + Window.x]
    mov esi, [r12 + Window.y]
    mov edx, [r12 + Window.width]
    mov ecx, [r12 + Window.height]
    call fb_mark_dirty
    pop r12
    pop rbx
    ret
