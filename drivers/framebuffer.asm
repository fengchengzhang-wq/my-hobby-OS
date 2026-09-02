; drivers/framebuffer.asm - 帧缓冲驱动：双缓冲 + 目标抽象 + 脏矩形 + 优化刷新
; NASM >= 2.15 | QEMU >= 6.2
;
; 绘制目标抽象：所有绘制函数作用于 [target_*]，默认是全局后台缓冲。
; 窗口客户区绘制通过 fb_set_target 切换到窗口私有缓冲，完成后再恢复。
; 脏矩形：仅当目标为主缓冲时记录，fb_flip 只刷新脏区域。

[bits 64]
%include "bootinfo.inc"
%include "driver.inc"

global init_framebuffer, fb_clear, fb_draw_pixel, fb_draw_rect
global fb_draw_hline, fb_draw_vline, fb_draw_char, fb_draw_string
global fb_draw_cjk, fb_text_width_utf8
global fb_flip, fb_mark_dirty, fb_set_target, fb_reset_target
global fb_blit, fb_draw_border, fb_xor_pixel
global fb_alpha_rect, fb_drop_shadow, fb_round_rect_fill
global fb_addr, fb_pitch, fb_width, fb_height, fb_bpp, fb_ready

extern boot_info
extern memcpy
extern driver_register
extern pci_find_vga_fb

section .bss
align 4096
backbuffer_static: resb 1024 * 768 * 4
framebuffer_static: resb 1024 * 768 * 4

section .data
fb_addr:    dq 0
fb_width:   dd 1024
fb_height:  dd 768
fb_bpp:     dd 32
fb_pitch:   dd 1024 * 4
fb_ready:   dd 0
screen_size: dq 1024 * 768 * 4
global backbuffer
backbuffer: dq 0

global target_base, target_pitch
target_base:   dq 0
target_width:  dd 0
target_height: dd 0
target_pitch:  dd 0
dirty_enabled: dd 1

dirty_x1: dd 0x7FFFFFFF
dirty_y1: dd 0x7FFFFFFF
dirty_x2: dd -1
dirty_y2: dd -1

global framebuffer_driver
framebuffer_driver:
    istruc Driver
        at Driver.name,  dq fb_name
        at Driver.kind,  dd DRV_KIND_GPU
        at Driver.state, dd DRV_STATE_REGISTERED
        at Driver.init,  dq init_framebuffer
        at Driver.fini,  dq 0
        at Driver.ops,   dq 0
        at Driver.priv,  dq 0
        at Driver.next,  dq 0
    iend

section .rodata
fb_name db "vbe-framebuffer", 0

section .text

init_framebuffer:
    mov eax, [boot_info + BootInfo.fb_present]
    test eax, eax
    jz .fallback
    mov rax, [boot_info + BootInfo.fb_addr]
    mov [fb_addr], rax
    ; VBE 回退的硬编码地址需修正为 PCI BAR2（SeaBIOS 动态分配）
    mov rax, 0xE0000000
    cmp [fb_addr], rax
    jne .addr_ok
    call pci_find_vga_fb
    test rax, rax
    jz .addr_ok
    mov [fb_addr], rax
.addr_ok:
    mov eax, [boot_info + BootInfo.fb_pitch]
    mov [fb_pitch], eax
    mov eax, [boot_info + BootInfo.fb_width]
    mov [fb_width], eax
    mov eax, [boot_info + BootInfo.fb_height]
    mov [fb_height], eax
    mov eax, [boot_info + BootInfo.fb_bpp]
    mov [fb_bpp], eax
    mov rax, [boot_info + BootInfo.fb_height]
    imul rax, [boot_info + BootInfo.fb_pitch]
    mov [screen_size], rax
    mov dword [fb_ready], 1
    jmp .setup
.fallback:
    ; 无真实帧缓冲（QEMU 6.2 -kernel 路径）：使用静态缓冲，串口仍可用
    mov qword [fb_addr], framebuffer_static
    mov dword [fb_width], 1024
    mov dword [fb_height], 768
    mov dword [fb_bpp], 32
    mov dword [fb_pitch], 1024 * 4
    mov qword [screen_size], 1024 * 768 * 4
    mov dword [fb_ready], 0
.setup:
    mov qword [backbuffer], backbuffer_static
    call fb_reset_target
    call fb_reset_dirty
    ; 自注册驱动
    lea rdi, [framebuffer_driver]
    call driver_register
    ret

; ---- 目标管理 ----
; void fb_set_target(base, width, height, pitch)
fb_set_target:
    mov [target_base], rdi
    mov [target_width], esi
    mov [target_height], edx
    mov [target_pitch], ecx
    ; 只有目标 == 主缓冲才记录脏矩形
    cmp rdi, [backbuffer]
    jne .not_main
    mov dword [dirty_enabled], 1
    ret
.not_main:
    mov dword [dirty_enabled], 0
    ret

; void fb_reset_target()
fb_reset_target:
    mov rax, [backbuffer]
    mov [target_base], rax
    mov eax, [fb_width]
    mov [target_width], eax
    mov eax, [fb_height]
    mov [target_height], eax
    mov eax, [fb_width]
    shl eax, 2
    mov [target_pitch], eax
    mov dword [dirty_enabled], 1
    ret

; ---- 脏矩形 ----
; void fb_mark_dirty(x, y, w, h)
fb_mark_dirty:
    cmp dword [dirty_enabled], 0
    je .skip
    test edi, edi
    jns .x_ok
    xor edi, edi
.x_ok:
    test esi, esi
    jns .y_ok
    xor esi, esi
.y_ok:
    lea eax, [rdi + rdx - 1]
    mov r8d, [fb_width]
    dec r8d
    cmp eax, r8d
    jle .x2_ok
    mov eax, r8d
.x2_ok:
    lea ecx, [rsi + rcx - 1]
    mov r8d, [fb_height]
    dec r8d
    cmp ecx, r8d
    jle .y2_ok
    mov ecx, r8d
.y2_ok:
    cmp edi, [dirty_x1]
    jge .m1
    mov [dirty_x1], edi
.m1:
    cmp esi, [dirty_y1]
    jge .m2
    mov [dirty_y1], esi
.m2:
    cmp eax, [dirty_x2]
    jle .m3
    mov [dirty_x2], eax
.m3:
    cmp ecx, [dirty_y2]
    jle .skip
    mov [dirty_y2], ecx
.skip:
    ret

fb_reset_dirty:
    mov dword [dirty_x1], 0x7FFFFFFF
    mov dword [dirty_y1], 0x7FFFFFFF
    mov dword [dirty_x2], -1
    mov dword [dirty_y2], -1
    ret

; ---- 刷新：脏矩形从后台缓冲拷贝到帧缓冲 ----
fb_flip:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov eax, [dirty_x1]
    cmp eax, [dirty_x2]
    ja .nothing
    ; 行数 / 每行字节数
    mov r12d, [dirty_y2]
    sub r12d, [dirty_y1]
    inc r12d                            ; 行数
    mov r13d, [dirty_x2]
    sub r13d, [dirty_x1]
    inc r13d
    shl r13d, 2                         ; 每行字节数
    ; 源/目的基址
    mov r14, [backbuffer]
    mov r15, [fb_addr]
    ; 源 pitch = fb_width*4；目的 pitch = fb_pitch
    mov r10d, [fb_width]
    shl r10d, 2
    mov r11d, [fb_pitch]
    mov r9d, [dirty_y1]
    mov ebx, [dirty_x1]
    shl ebx, 2                          ; x 偏移字节
.row_loop:
    test r12d, r12d
    jz .done
    mov rax, r9
    mul r10d
    add rax, rbx
    add rax, r14
    mov rsi, rax                        ; src
    mov rax, r9
    mul r11d
    add rax, rbx
    add rax, r15
    mov rdi, rax                        ; dst
    mov rdx, r13                        ; len
    push r9
    push r10
    push r11
    push r12
    push r13
    call memcpy
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    inc r9d
    dec r12d
    jmp .row_loop
.done:
    call fb_reset_dirty
.nothing:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- 基础图元 ----
; void fb_clear(color)   （rdi = 32 位 ARGB）
fb_clear:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi                        ; 颜色
    mov r13, [target_base]
    mov r14d, [target_height]
    mov r15d, [target_pitch]
    xor r9d, r9d
.row_loop:
    cmp r9d, r14d
    jae .done
    mov rax, r9
    mul r15d
    add rax, r13
    mov rdi, rax
    mov eax, [target_width]
    mov rcx, rax
    mov rax, r12
    rep stosd
    inc r9d
    jmp .row_loop
.done:
    mov edi, 0
    mov esi, 0
    mov edx, [target_width]
    mov ecx, [target_height]
    call fb_mark_dirty
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; void fb_draw_pixel(x, y, color)
fb_draw_pixel:
    cmp edi, [target_width]
    jae .out
    cmp esi, [target_height]
    jae .out
    mov r8d, edx                        ; 保存颜色（mul 会破坏 edx）
    mov eax, esi
    mul dword [target_pitch]
    shl edi, 2                          ; x * 4（像素 -> 字节）
    add eax, edi
    shr edi, 2                          ; 恢复 x（脏矩形用）
    add rax, [target_base]
    mov [rax], r8d
    push rdi
    push rsi
    push rdx
    push rcx
    mov rdx, 1
    mov rcx, 1
    call fb_mark_dirty
    pop rcx
    pop rdx
    pop rsi
    pop rdi
.out:
    ret

; =====================================================================
; 高级绘制：alpha 混合 / 柔和阴影 / 圆角矩形（极简立体 UI 用）
; 约定：fb_alpha_rect/round_rect 第 5 参数在 r8d（与 fb_draw_rect 一致）
; =====================================================================

; fb_blend_px2：rdi=像素地址, r8d=argb —— 单像素 alpha 混合
fb_blend_px2:
    mov eax, [rdi]
    mov ecx, r8d
    mov edx, ecx
    shr edx, 24                         ; a
    test edx, edx
    jz .out
    cmp edx, 255
    je .opaque
    mov r9d, 255
    sub r9d, edx
    ; b
    mov ebx, eax
    and ebx, 0xFF
    mov esi, ecx
    and esi, 0xFF
    imul ebx, r9d
    imul esi, edx
    add ebx, esi
    shr ebx, 8
    ; g
    mov r10d, eax
    shr r10d, 8
    and r10d, 0xFF
    mov r11d, ecx
    shr r11d, 8
    and r11d, 0xFF
    imul r10d, r9d
    imul r11d, edx
    add r10d, r11d
    shr r10d, 8
    shl r10d, 8
    ; r
    mov r11d, eax
    shr r11d, 16
    and r11d, 0xFF
    mov r15d, ecx
    shr r15d, 16
    and r15d, 0xFF
    imul r11d, r9d
    imul r15d, edx
    add r11d, r15d
    shr r11d, 8
    shl r11d, 16
    mov eax, ebx
    add eax, r10d
    add eax, r11d
    or eax, 0xFF000000
    mov [rdi], eax
.out:
    ret
.opaque:
    mov [rdi], ecx
    ret

; void fb_alpha_rect(x, y, w, h, r8d=argb)
fb_alpha_rect:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov [rbp-8], edi
    mov [rbp-16], esi
    mov [rbp-24], edx
    mov [rbp-32], ecx
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; 裁剪
    mov eax, edi
    add eax, edx
    jle .out
    mov eax, esi
    add eax, ecx
    jle .out
    xor eax, eax
    cmp edi, eax
    cmovl edi, eax
    cmp esi, eax
    cmovl esi, eax
    mov r12d, [target_width]
    mov r13d, [target_height]
    lea eax, [rdi + rdx - 1]
    cmp eax, r12d
    cmovge eax, r12d
    mov r14d, eax                       ; x2
    lea eax, [rsi + rcx - 1]
    cmp eax, r13d
    cmovge eax, r13d
    mov r15d, eax                       ; y2
    cmp edi, r14d
    jg .out
    cmp esi, r15d
    jg .out
    mov ebx, r8d                        ; argb
    mov r9d, esi
.row:
    cmp r9d, r15d
    jg .done
    mov eax, r9d
    mul dword [target_pitch]
    mov r10d, edi
.col:
    cmp r10d, r14d
    jg .next_row
    lea rdx, [rax + r10*4]
    add rdx, [target_base]
    mov rdi, rdx
    mov r8d, ebx
    push rax
    push r9
    push r10
    call fb_blend_px2
    pop r10
    pop r9
    pop rax
    inc r10d
    jmp .col
.next_row:
    inc r9d
    jmp .row
.done:
    mov edi, [rbp - 8]
    mov esi, [rbp - 16]
    mov edx, [rbp - 24]
    mov ecx, [rbp - 32]
    call fb_mark_dirty
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; void fb_drop_shadow(x, y, w, h, r8d=size)
; 在矩形右下方绘制 N 层柔和阴影（alpha 距离衰减）
fb_drop_shadow:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi                       ; x
    mov r13d, esi                       ; y
    mov r14d, edx                       ; w
    mov r15d, ecx                       ; h
    mov ebx, r8d                        ; size
    test ebx, ebx
    jle .out
    cmp ebx, 10
    jle .s_ok
    mov ebx, 10
.s_ok:
    ; 像素 x 范围 [x, x+w+size)，y 范围 [y, y+h+size)
    ; 在窗口矩形内的像素跳过
    mov r9d, r13d
.row:
    mov eax, r13d
    add eax, r15d
    add eax, ebx
    cmp r9d, eax
    jge .done
    mov r10d, r12d
.col:
    mov eax, r12d
    add eax, r14d
    add eax, ebx
    cmp r10d, eax
    jge .next_row
    ; 窗口内？
    mov eax, r10d
    cmp eax, r12d
    jl .border_px
    lea eax, [r12 + r14]
    cmp r10d, eax
    jge .border_px
    mov eax, r9d
    cmp eax, r13d
    jl .border_px
    lea eax, [r13 + r15]
    cmp r9d, eax
    jl .next_col                         ; 窗口内跳过
.border_px:
    ; 距窗口的距离（像素到边缘）
    ; dx = max(r12-x, x-(r12+r14-1), 0)
    mov eax, r12d
    sub eax, r10d
    xor edx, edx
    test eax, eax
    jns .dx1
    xor eax, eax
.dx1:
    mov ecx, r10d
    sub ecx, r12d
    sub ecx, r14d
    add ecx, 1
    test ecx, ecx
    jle .dx2
    cmp eax, ecx
    cmovl eax, ecx
.dx2:
    ; dy 同理
    mov ecx, r13d
    sub ecx, r9d
    test ecx, ecx
    jns .dy1
    xor ecx, ecx
.dy1:
    mov edx, r9d
    sub edx, r13d
    sub edx, r15d
    add edx, 1
    test edx, edx
    jle .dy2
    cmp ecx, edx
    cmovl ecx, edx
.dy2:
    ; d = max(dx, dy)
    cmp eax, ecx
    cmovl eax, ecx
    ; alpha = (size+1-d) * 6 （0..~36）
    mov edx, ebx
    inc edx
    sub edx, eax
    jle .next_col
    imul edx, 6
    cmp edx, 36
    jle .a_ok
    mov edx, 36
.a_ok:
    shl edx, 24
    mov r8d, edx                        ; 颜色 = alpha<<24（先保存，后面 edx 被复用）
    ; 混合像素
    mov eax, r9d
    mul dword [target_pitch]
    mov edx, r10d
    shl edx, 2
    add eax, edx
    add rax, [target_base]
    mov rdi, rax
    push r9
    push r10
    call fb_blend_px2
    pop r10
    pop r9
.next_col:
    inc r10d
    jmp .col
.next_row:
    inc r9d
    jmp .row
.done:
    mov edi, r12d
    sub edi, 1
    mov esi, r13d
    sub esi, 1
    mov edx, r14d
    add edx, ebx
    add edx, 2
    mov ecx, r15d
    add ecx, ebx
    add ecx, 2
    call fb_mark_dirty
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; void fb_round_rect_fill(x, y, w, h, r8d=r, r9d=color)
fb_round_rect_fill:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    mov r15d, ecx
    mov ebx, r8d                        ; r
    test ebx, ebx
    jle .plain
    lea eax, [ebx + ebx]
    cmp eax, r14d
    jge .plain
    cmp eax, r15d
    jge .plain
    xor r11d, r11d
.row:
    cmp r11d, r15d
    jae .done
    ; 计算该行左右内缩 inset
    mov eax, r11d
    mov ecx, r15d
    dec ecx
    sub ecx, r11d                       ; h-1-py
    cmp eax, ecx
    cmovg eax, ecx                      ; pyb = min(py, h-1-py)
    cmp eax, ebx
    jge .full
    ; dy = r - pyb
    mov ecx, ebx
    sub ecx, eax
    jmp .calc
.full:
    xor ecx, ecx
    jmp .draw_row
.calc:
    ; arg = r^2 - dy^2（ecx=dy）
    mov eax, ecx
    imul eax, eax
    mov edx, ebx
    imul edx, edx
    sub edx, eax
    jle .inset_r
    movzx eax, byte [sqrttab + rdx]
    mov ecx, ebx
    sub ecx, eax                        ; inset = r - hw
    jmp .draw_row
.inset_r:
    mov ecx, ebx
.draw_row:
    ; 画 (x+inset, y+row, w-2*inset, 1)
    mov edi, r12d
    add edi, ecx
    mov r10d, r14d
    sub r10d, ecx
    sub r10d, ecx
    test r10d, r10d
    jle .skip_row
    mov esi, r13d
    add esi, r11d
    mov edx, r10d
    mov ecx, 1
    mov r8d, r9d
    push r11
    call fb_draw_rect
    pop r11
.skip_row:
    inc r11d
    jmp .row
.done:
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    call fb_mark_dirty
    jmp .out
.plain:
    mov edi, r12d
    mov esi, r13d
    mov edx, r14d
    mov ecx, r15d
    mov r8d, r9d
    call fb_draw_rect
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

section .rodata
; 整数平方根表 floor(sqrt(n)) for n=0..1023
sqrttab:
%assign sqrt_i 0
%assign sqrt_s 0
%rep 1024
    db sqrt_s
%assign sqrt_i sqrt_i+1
%if (sqrt_s+1)*(sqrt_s+1) <= sqrt_i
%assign sqrt_s sqrt_s+1
%endif
%endrep

; void fb_draw_rect(x, y, w, h, color)
fb_draw_rect:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov [rbp-8], edi                    ; 保存原始 x/y/w/h 用于脏矩形
    mov [rbp-16], esi
    mov [rbp-24], edx
    mov [rbp-32], ecx
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; 裁剪
    mov eax, edi
    add eax, edx
    jle .out
    mov eax, esi
    add eax, ecx
    jle .out
    ; x1/y1
    xor eax, eax
    cmp edi, eax
    cmovl edi, eax
    cmp esi, eax
    cmovl esi, eax
    mov [rbp-40], edi                   ; 保存裁剪后的 x1（行循环中 edi 会被覆盖）
    ; x2 = min(tw-1, x+w-1)
    lea r12d, [rdi + rdx - 1]
    mov eax, [target_width]
    dec eax
    cmp r12d, eax
    cmovg r12d, eax
    ; y2 = min(th-1, y+h-1)
    lea r13d, [rsi + rcx - 1]
    mov eax, [target_height]
    dec eax
    cmp r13d, eax
    cmovg r13d, eax
    ; 空矩形剔除
    cmp edi, r12d
    jg .out
    cmp esi, r13d
    jg .out
    mov r14d, r8d                       ; 颜色
    mov r15d, r13d
    sub r15d, esi
    inc r15d                            ; 行数
    mov ebx, r12d
    sub ebx, edi
    inc ebx                             ; 每行像素数
    mov r9d, esi                        ; y
.row_loop:
    test r15d, r15d
    jz .rows_done
    mov rax, r9
    mul dword [target_pitch]
    mov ecx, [rbp-40]                   ; x1
    shl ecx, 2
    add rax, rcx
    add rax, [target_base]
    mov rdi, rax
    mov rcx, rbx
    mov rax, r14
    rep stosd
    inc r9d
    dec r15d
    jmp .row_loop
.rows_done:
    mov edi, [rbp-8]
    mov esi, [rbp-16]
    mov edx, [rbp-24]
    mov ecx, [rbp-32]
    call fb_mark_dirty
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; void fb_draw_hline(x, y, w, color)
fb_draw_hline:
    push r8
    mov r8d, ecx
    mov rcx, 1
    call fb_draw_rect
    pop r8
    ret

; void fb_draw_vline(x, y, h, color)
fb_draw_vline:
    push r8
    mov r8d, ecx
    mov rcx, rdx
    mov rdx, 1
    call fb_draw_rect
    pop r8
    ret

; void fb_draw_char(x, y, ch, fg, bg=-1 透明)
extern font8x16
extern cjk16_bin
fb_draw_char:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi                       ; x
    mov r13d, esi                       ; y
    mov r14d, ecx                       ; fg
    mov r15d, r8d                       ; bg
    mov r11d, edx                       ; ch
    ; 背景
    cmp r15d, -1
    je .no_bg
    mov edi, r12d
    mov esi, r13d
    mov edx, 8
    mov ecx, 16
    mov r8d, r15d
    call fb_draw_rect
.no_bg:
    movzx eax, r11b
    sub eax, 32
    jb .skip
    cmp eax, 95
    jae .skip
    shl eax, 4
    lea rbx, [font8x16 + rax]
    xor r9d, r9d                        ; 行
.row_loop:
    cmp r9d, 16
    jae .skip
    movzx eax, byte [rbx + r9]
    mov r10d, 7                         ; 列（从高位）
.col_loop:
    test eax, 0x80
    jz .next_col
    mov edi, r12d
    add edi, 7
    sub edi, r10d                   ; bit7(最左) -> x+0，消除镜像
    mov esi, r13d
    add esi, r9d
    mov edx, r14d
    push rax
    push rbx
    push rcx
    push r8
    push r9
    push r10
    call fb_draw_pixel
    pop r10
    pop r9
    pop r8
    pop rcx
    pop rbx
    pop rax
.next_col:
    shl eax, 1
    dec r10d
    jns .col_loop
    inc r9d
    jmp .row_loop
.skip:
    mov edi, r12d
    mov esi, r13d
    mov edx, 8
    mov ecx, 16
    call fb_mark_dirty
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; ---- 16x16 CJK 点阵查找与绘制 ----
; 数据布局（assets/cjk16.bin）：
;   u32 count | count*u32 码点(升序) | count*32B 位图
;   每字 16 行，每行 2 字节，高字节为左 8 列

; void fb_draw_cjk(x, y, cp, fg, bg=-1)
fb_draw_cjk:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi                       ; x
    mov r13d, esi                       ; y
    mov ebx, edx                        ; cp
    mov r14d, ecx                       ; fg
    mov r15d, r8d                       ; bg
    cmp r15d, -1
    je .lookup
    mov edi, r12d
    mov esi, r13d
    mov edx, 16
    mov ecx, 16
    mov r8d, r15d
    call fb_draw_rect
.lookup:
    mov rax, cjk16_bin
    mov r9d, [rax]                      ; count
    test r9d, r9d
    jz .done
    lea rdx, [rax + 4]                  ; codes
    xor r8d, r8d
.search:
    cmp r8d, r9d
    jae .done
    mov r10d, [rdx + r8*4]
    cmp r10d, ebx
    je .found
    inc r8d
    jmp .search
.found:
    ; glyph = codes + count*4 + idx*32
    lea rbx, [rdx + r9*4]
    mov r10d, r8d
    shl r10d, 5
    add rbx, r10
    xor r9d, r9d                        ; 行
.row_loop:
    cmp r9d, 16
    jae .done
    movzx eax, byte [rbx + r9*2]        ; 左 8 列
    movzx r11d, byte [rbx + r9*2 + 1]   ; 右 8 列
    xor r10d, r10d
.hi_loop:
    cmp r10d, 8
    jae .lo_part
    mov edx, 0x80
    mov ecx, r10d
    shr edx, cl
    test eax, edx
    jz .hi_next
    mov edi, r12d
    add edi, r10d
    mov esi, r13d
    add esi, r9d
    mov edx, r14d
    push rax
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    call fb_draw_pixel
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    pop rax
.hi_next:
    inc r10d
    jmp .hi_loop
.lo_part:
    mov eax, r11d
    xor r10d, r10d
.lo_loop:
    cmp r10d, 8
    jae .next_row
    mov edx, 0x80
    mov ecx, r10d
    shr edx, cl
    test eax, edx
    jz .lo_next
    mov edi, r12d
    lea edi, [rdi + r10 + 8]
    mov esi, r13d
    add esi, r9d
    mov edx, r14d
    push rax
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    call fb_draw_pixel
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    pop rax
.lo_next:
    inc r10d
    jmp .lo_loop
.next_row:
    inc r9d
    jmp .row_loop
.done:
    mov edi, r12d
    mov esi, r13d
    mov edx, 16
    mov ecx, 16
    call fb_mark_dirty
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; size_t fb_text_width_utf8(const char *str)
; ASCII=8px，UTF-8 中文字符=16px（不含失效字节防御）
fb_text_width_utf8:
    push rbx
    xor eax, eax
.loop:
    movzx ecx, byte [rdi]
    test cl, cl
    jz .done
    cmp cl, 0x80
    jb .ascii
    mov edx, ecx
    and edx, 0xE0
    cmp edx, 0xC0
    je .len2
    mov edx, ecx
    and edx, 0xF0
    cmp edx, 0xE0
    je .len3
    jmp .ascii
.len2:
    add eax, 16
    add rdi, 2
    jmp .loop
.len3:
    add eax, 16
    add rdi, 3
    jmp .loop
.ascii:
    add eax, 8
    inc rdi
    jmp .loop
.done:
    pop rbx
    ret

; void fb_draw_string(x, y, str, fg, bg)：UTF-8 感知（ASCII 8x16 + CJK 16x16）
fb_draw_string:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi                        ; x
    mov r12, rsi                        ; y
    mov r13, rdx                        ; str
    mov r14d, ecx                       ; fg
    mov r15d, r8d                       ; bg
.loop:
    mov al, [r13]
    test al, al
    jz .done
    cmp al, 0x80
    jb .ascii
    ; ---- UTF-8 中文 ----
    mov edx, eax
    and edx, 0xE0
    cmp edx, 0xC0
    je .utf2
    mov edx, eax
    and edx, 0xF0
    cmp edx, 0xE0
    je .utf3
    jmp .ascii                          ; 非 UTF-8 首字节按单字节跳过
.utf2:
    movzx ecx, byte [r13 + 1]
    cmp cl, 0x80
    jb .ascii
    cmp cl, 0xBF
    ja .ascii
    and eax, 0x1F
    shl eax, 6
    and ecx, 0x3F
    or eax, ecx                         ; 码点
    mov edi, ebx
    mov esi, r12d
    mov edx, eax
    mov ecx, r14d
    mov r8d, r15d
    call fb_draw_cjk
    add ebx, 16
    add r13, 2
    jmp .loop
.utf3:
    movzx ecx, byte [r13 + 1]
    cmp cl, 0x80
    jb .ascii
    cmp cl, 0xBF
    ja .ascii
    movzx r8d, byte [r13 + 2]
    cmp r8b, 0x80
    jb .ascii
    cmp r8b, 0xBF
    ja .ascii
    and eax, 0x0F
    shl eax, 12
    and ecx, 0x3F
    shl ecx, 6
    or eax, ecx
    and r8d, 0x3F
    or eax, r8d                         ; 码点
    mov edi, ebx
    mov esi, r12d
    mov edx, eax
    mov ecx, r14d
    mov r8d, r15d
    call fb_draw_cjk
    add ebx, 16
    add r13, 3
    jmp .loop
.ascii:
    mov edi, ebx
    mov esi, r12d
    mov dl, al
    mov ecx, r14d
    mov r8d, r15d
    push rbx
    push r13
    call fb_draw_char
    pop r13
    pop rbx
    add ebx, 8
    inc r13
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; void fb_blit(src, src_pitch, dx, dy, w, h)
fb_blit:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi                        ; src
    mov r12d, esi                       ; src_pitch
    mov r13d, edx                       ; dx
    mov r14d, ecx                       ; dy
    mov r15d, r8d                       ; w
    ; 裁剪
    cmp r13d, [target_width]
    jae .out
    cmp r14d, [target_height]
    jae .out
    mov eax, r13d
    add eax, r15d
    cmp eax, [target_width]
    jle .w_ok
    mov eax, [target_width]
    sub eax, r13d
    mov r15d, eax
.w_ok:
    mov eax, r14d
    add eax, r9d
    cmp eax, [target_height]
    jle .h_ok
    mov eax, [target_height]
    sub eax, r14d
    mov r9d, eax
.h_ok:
    ; 每行拷贝
    mov eax, r15d
    shl eax, 2                          ; 每行字节
    mov [.row_bytes], eax
    xor ecx, ecx
.row_loop:
    cmp ecx, r9d
    jae .rows_done
    ; dst = target + (dy+i)*tp + dx*4
    mov rax, r14
    add rax, rcx
    mul dword [target_pitch]
    mov edx, r13d
    shl edx, 2
    add rax, rdx
    add rax, [target_base]
    mov rdi, rax
    ; src = src + i*sp
    mov rax, rcx
    mul r12d
    add rax, rbx
    mov rsi, rax
    mov rdx, [.row_bytes]
    push rbx
    push rcx
    push r9
    call memcpy
    pop r9
    pop rcx
    pop rbx
    inc ecx
    jmp .row_loop
.rows_done:
    mov edi, r13d
    mov esi, r14d
    mov edx, r15d
    mov ecx, r9d
    call fb_mark_dirty
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret
.row_bytes: dq 0

; void fb_draw_border(x, y, w, h, color, th)
fb_draw_border:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    mov [rbp-8], edi
    mov [rbp-16], esi
    mov [rbp-24], edx
    mov [rbp-32], ecx
    push r12
    push r13
    mov r12d, r8d                       ; color
    mov r13d, r9d                       ; th（调用约定：第 6 参在 r9d）
    ; 上
    mov edi, [rbp-8]
    mov esi, [rbp-16]
    mov edx, [rbp-24]
    mov rcx, r13
    mov r8d, r12d
    call fb_draw_rect
    ; 下
    mov edi, [rbp-8]
    mov esi, [rbp-16]
    add esi, [rbp-32]                   ; y+h-th
    sub esi, r13d
    mov edx, [rbp-24]
    mov rcx, r13
    mov r8d, r12d
    call fb_draw_rect
    ; 左
    mov edi, [rbp-8]
    mov esi, [rbp-16]
    mov rdx, r13
    mov ecx, [rbp-32]
    mov r8d, r12d
    call fb_draw_rect
    ; 右
    mov edi, [rbp-8]
    add edi, [rbp-24]
    sub edi, r13d
    mov esi, [rbp-16]
    mov rdx, r13
    mov ecx, [rbp-32]
    mov r8d, r12d
    call fb_draw_rect
    pop r13
    pop r12
    leave
    ret

; void fb_xor_pixel(x, y)：反转目标像素 RGB（光标 XOR 绘制）
fb_xor_pixel:
    cmp edi, [target_width]
    jae .out
    cmp esi, [target_height]
    jae .out
    mov eax, esi
    mul dword [target_pitch]
    shl edi, 2
    add eax, edi
    shr edi, 2
    add rax, [target_base]
    xor dword [rax], 0x00FFFFFF
    push rdi
    push rsi
    push rdx
    push rcx
    mov rdx, 1
    mov rcx, 1
    call fb_mark_dirty
    pop rcx
    pop rdx
    pop rsi
    pop rdi
.out:
    ret
