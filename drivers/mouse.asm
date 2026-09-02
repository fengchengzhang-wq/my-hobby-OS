; drivers/mouse.asm - PS/2 鼠标驱动（3 字节数据包）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "events.inc"
%include "irq.inc"
%include "driver.inc"

global init_mouse, mouse_handler, mouse_get_state, mouse_read_state
global mouse_x, mouse_y, mouse_buttons

extern kb_wait
extern irq_register
extern driver_register
extern fb_width, fb_height
extern kbd_drain

section .data
mouse_x: dd 0
mouse_y: dd 0
mouse_buttons: db 0

global mouse_driver
mouse_driver:
    istruc Driver
        at Driver.name,  dq mouse_name
        at Driver.kind,  dd DRV_KIND_INPUT
        at Driver.state, dd DRV_STATE_REGISTERED
        at Driver.init,  dq init_mouse
        at Driver.fini,  dq 0
        at Driver.ops,   dq 0
        at Driver.priv,  dq 0
        at Driver.next,  dq 0
    iend

section .rodata
mouse_name db "ps2-mouse", 0

section .bss
mouse_packet: resb 3
packet_index: resb 1

section .text

init_mouse:
    ; 排空残留字节（键盘 ACK 等），确保命令字节读取正确
    call kbd_drain
    call kb_wait
    mov al, 0xA8                        ; 启用鼠标
    out 0x64, al
    call kb_wait
    mov al, 0x20                        ; 读控制器命令字节
    out 0x64, al
    call kb_wait
    in al, 0x60
    or al, 2                            ; 启用鼠标中断
    mov bl, al
    call kb_wait
    mov al, 0x60
    out 0x64, al
    call kb_wait
    mov al, bl
    out 0x60, al
    mov rdi, 0xF6                       ; 设置默认
    call mouse_send_cmd
    call mouse_wait_ack                 ; 等待并消费 ACK
    mov rdi, 0xF4                       ; 启用数据包
    call mouse_send_cmd
    call mouse_wait_ack                 ; 等待并消费 ACK
    call mouse_resync                   ; 发送 0xEB 并消费一个完整数据包（重同步）
    mov byte [packet_index], 0
    mov dword [mouse_x], 0
    mov dword [mouse_y], 0
    mov byte [mouse_buttons], 0
    ; 注册 IRQ12
    mov rdi, IRQ_MOUSE
    lea rsi, [mouse_handler]
    xor rdx, rdx
    call irq_register
    ; 自注册驱动
    lea rdi, [mouse_driver]
    call driver_register
    ret

mouse_send_cmd:                         ; rdi = 命令
    push rax
    push rdx
    call kb_wait
    mov al, 0xD4
    out 0x64, al
    call kb_wait
    mov al, dil
    out 0x60, al
    pop rdx
    pop rax
    ret

; 等待鼠标 ACK（0xFA）并消费
mouse_wait_ack:
    push rax
    push rcx
    mov rcx, 8000000
.loop:
    in al, 0x64
    test al, 1
    jnz .data
    loop .loop
    jmp .done
.data:
    in al, 0x60
    cmp al, 0xFA
    jne .loop
.done:
    pop rcx
    pop rax
    ret

; 重同步：发送 0xEB（读数据），消费 ACK + 一个 3 字节数据包
mouse_resync:
    push rax
    push rcx
    push r8
    mov rdi, 0xEB
    call mouse_send_cmd
    call mouse_wait_ack
    mov ecx, 3                          ; 需要消费 3 个数据字节
.wait_data:
    mov r8, 2000000
.wait:
    in al, 0x64
    test al, 1
    jnz .have
    dec r8
    jnz .wait
    jmp .done
.have:
    in al, 0x60
    cmp al, 0xFA                        ; 跳过残留 ACK
    je .wait
    dec ecx
    jnz .wait
.done:
    pop r8
    pop rcx
    pop rax
    ret

; 鼠标中断处理（由 irq_dispatch 调用，EOI 统一发送）
mouse_handler:
    push rax
    push rbx
    push rcx
    push rdx
    in al, 0x60
    ; 包起始字节校验：标准 3 字节包的 flags 字节 bit3 恒为 1（包起始标记）。
    ; 残留 ACK（0xFA/0xF6）等垃圾字节在此被自然丢弃，保证数据流自同步。
    cmp byte [packet_index], 0
    jne .normal
    test al, 0x08
    jnz .normal
    jmp .done
.normal:
    movzx rbx, byte [packet_index]
    mov byte [mouse_packet + rbx], al
    inc rbx
    cmp rbx, 3
    jne .partial
    ; ---- 完整数据包 ----
    movzx rbx, byte [mouse_packet]
    test bl, 0x08                       ; 标记位必须为 1，否则视为错位
    jz .reset
    test bl, 0xC0                       ; X/Y 溢出位（bit6/7）
    jnz .reset
    ; 相对位移（9 位有符号）
    movzx rax, byte [mouse_packet + 1]
    movzx rcx, byte [mouse_packet + 2]
    test bl, 0x10
    jz .x_pos
    or rax, ~0xFF
.x_pos:
    test bl, 0x20
    jz .y_pos
    or rcx, ~0xFF
.y_pos:
    add [mouse_x], eax
    sub [mouse_y], ecx                  ; Y 轴反转
    ; 边界限制
    mov eax, [mouse_x]
    test eax, eax
    jns .x_nonneg
    mov dword [mouse_x], 0
.x_nonneg:
    mov eax, [fb_width]
    dec eax
    cmp [mouse_x], eax
    jle .x_ok
    mov [mouse_x], eax
.x_ok:
    mov eax, [mouse_y]
    test eax, eax
    jns .y_nonneg
    mov dword [mouse_y], 0
.y_nonneg:
    mov eax, [fb_height]
    dec eax
    cmp [mouse_y], eax
    jle .y_ok
    mov [mouse_y], eax
.y_ok:
    and bl, 7
    mov [mouse_buttons], bl
.reset:
    mov byte [packet_index], 0
    jmp .done
.partial:
    mov [packet_index], bl
.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; 兼容接口：eax=x, edx=y, rbx=buttons
mouse_get_state:
    mov eax, [mouse_x]
    mov edx, [mouse_y]
    movzx rbx, byte [mouse_buttons]
    ret

; void mouse_read_state(MouseState*)
mouse_read_state:
    mov eax, [mouse_x]
    mov [rdi + MouseState.x], eax
    mov eax, [mouse_y]
    mov [rdi + MouseState.y], eax
    movzx eax, byte [mouse_buttons]
    mov [rdi + MouseState.buttons], eax
    ret
