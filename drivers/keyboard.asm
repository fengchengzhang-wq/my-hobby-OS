; drivers/keyboard.asm - PS/2 键盘驱动（扫描码集 1，完整按键事件）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "events.inc"
%include "irq.inc"
%include "driver.inc"

global init_keyboard, keyboard_handler, kb_wait
global keyboard_read_event, keyboard_get_ascii, kbd_drain

extern irq_register
extern driver_register

section .bss
align 16
key_events: times KEY_BUF_SIZE resb KeyEvent_size
key_event_tmp: resb KeyEvent_size
key_head: resq 1
key_tail: resq 1
extended: resb 1

section .data
modifiers: dd 0

global keyboard_driver
keyboard_driver:
    istruc Driver
        at Driver.name,  dq keyboard_name
        at Driver.kind,  dd DRV_KIND_INPUT
        at Driver.state, dd DRV_STATE_REGISTERED
        at Driver.init,  dq init_keyboard
        at Driver.fini,  dq 0
        at Driver.ops,   dq 0
        at Driver.priv,  dq 0
        at Driver.next,  dq 0
    iend

section .rodata
keyboard_name db "ps2-keyboard", 0

; ---- 扫描码集 1 字符表（0x01..0x35） ----
scancode_low:
    db 0,27,'1','2','3','4','5','6','7','8','9','0','-','=',8,9
    db 'q','w','e','r','t','y','u','i','o','p','[',']',13,0
    db 'a','s','d','f','g','h','j','k','l',';',"'",'`',0,'\'
    db 'z','x','c','v','b','n','m',',','.','/',0,'*',0,' '
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

scancode_high:
    db 0,27,'!','@','#','$','%','^','&','*','(',')','_','+',8,9
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}',13,0
    db 'A','S','D','F','G','H','J','K','L',':','"','~',0,'|'
    db 'Z','X','C','V','B','N','M','<','>','?',0,'*',0,' '
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

section .text

init_keyboard:
    call kb_wait
    mov al, 0xAE                        ; 启用键盘
    out 0x64, al
    call kb_wait
    mov al, 0xF4                        ; 启用扫描
    out 0x60, al
    ; 排空 ACK（0xFA），避免残留字节干扰后续控制器命令
    call kbd_drain
    mov qword [key_head], 0
    mov qword [key_tail], 0
    mov byte [extended], 0
    mov dword [modifiers], 0
    ; 注册 IRQ1
    mov rdi, IRQ_KEYBOARD
    lea rsi, [keyboard_handler]
    xor rdx, rdx
    call irq_register
    ; 自注册驱动
    lea rdi, [keyboard_driver]
    call driver_register
    ret

; 等待键盘控制器空闲
kb_wait:
    in al, 0x64
    test al, 2
    jnz kb_wait
    ret

; 排空 PS/2 输出缓冲（丢弃残留 ACK/数据）
kbd_drain:
    push rax
    push rcx
    mov rcx, 1000
.loop:
    in al, 0x64
    test al, 1
    jz .done
    in al, 0x60
    loop .loop
.done:
    pop rcx
    pop rax
    ret

; 键盘中断处理（由 irq_dispatch 调用，EOI 统一发送）
keyboard_handler:
    push rax
    push rbx
    push rcx
    push rdx
    in al, 0x60
    movzx rax, al
    cmp al, 0xE0
    jne .no_e0
    mov byte [extended], 1
    jmp .done
.no_e0:
    mov bl, [extended]
    mov byte [extended], 0
    movzx rcx, bl                       ; rcx = extended 标志
    ; 更新修饰键（先判断 make/break）
    mov rdx, 1
    test al, 0x80
    jz .make_flag
    xor rdx, rdx
.make_flag:
    push rax
    push rcx
    push rdx
    mov rdi, rax
    and rdi, 0x7F
    call kbd_update_mods
    pop rdx
    pop rcx
    pop rax
    test al, 0x80
    jnz .up
    ; ---- 按下 ----
    and al, 0x7F
    push rax                            ; 保存扫描码
    push rcx                            ; 保存 extended
    mov rdi, rax
    mov rsi, rcx
    call kbd_ascii                      ; rax = ASCII
    mov rdx, rax                        ; ascii
    pop rcx
    pop rax                             ; rax = 扫描码
    mov rsi, rax
    mov rdi, EV_KEY_DOWN
    mov rcx, [modifiers]
    call kbd_enqueue
    jmp .done
.up:
    ; ---- 抬起 ----
    and al, 0x7F
    mov rsi, rax
    mov rdi, EV_KEY_UP
    xor edx, edx
    mov rcx, [modifiers]
    call kbd_enqueue
.done:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

; ---- 修饰键更新（rdi=扫描码7位, rsi=extended, rdx=make） ----
kbd_update_mods:
    cmp rdi, 0x2A
    je .shift
    cmp rdi, 0x36
    je .shift
    cmp rdi, 0x1D
    je .ctrl
    cmp rdi, 0x38
    je .alt
    cmp rdi, 0x3A
    je .caps
    ret
.shift:
    test rdx, rdx
    jz .shift_off
    or dword [modifiers], KBD_MOD_SHIFT
    ret
.shift_off:
    and dword [modifiers], ~KBD_MOD_SHIFT
    ret
.ctrl:
    test rdx, rdx
    jz .ctrl_off
    or dword [modifiers], KBD_MOD_CTRL
    ret
.ctrl_off:
    and dword [modifiers], ~KBD_MOD_CTRL
    ret
.alt:
    test rdx, rdx
    jz .alt_off
    or dword [modifiers], KBD_MOD_ALT
    ret
.alt_off:
    and dword [modifiers], ~KBD_MOD_ALT
    ret
.caps:
    test rdx, rdx
    jz .ret
    xor dword [modifiers], KBD_MOD_CAPS
.ret:
    ret

; ---- 扫描码 -> ASCII（rdi=scan, rsi=extended） ----
kbd_ascii:
    test rsi, rsi
    jz .not_ext
    xor rax, rax                        ; 扩展键无 ASCII
    ret
.not_ext:
    cmp rdi, 0x39
    je .space
    cmp rdi, 0x0E
    je .backspace
    cmp rdi, 0x0F
    je .tab
    cmp rdi, 0x1C
    je .enter
    cmp rdi, 0x53
    je .del
    cmp rdi, 0x01
    jb .zero
    cmp rdi, 0x35
    ja .zero
    lea r8, [scancode_low]
    test dword [modifiers], KBD_MOD_SHIFT
    jz .use_low
    lea r8, [scancode_high]
.use_low:
    movzx eax, byte [r8 + rdi]
    ; Caps 只翻转字母
    test dword [modifiers], KBD_MOD_CAPS
    jz .done
    cmp al, 'a'
    jb .try_upper
    cmp al, 'z'
    ja .done
    sub al, 32
    jmp .done
.try_upper:
    cmp al, 'A'
    jb .done
    cmp al, 'Z'
    ja .done
    add al, 32
.done:
    movzx rax, al
    ret
.space:
    mov rax, ' '
    ret
.backspace:
    mov rax, 8
    ret
.tab:
    mov rax, 9
    ret
.enter:
    mov rax, 13
    ret
.del:
    mov rax, 127
    ret
.zero:
    xor rax, rax
    ret

; ---- 事件入队（rdi=type, rsi=scan, rdx=ascii, rcx=mods） ----
kbd_enqueue:
    mov rax, [key_tail]
    lea r8, [rax + 1]
    cmp r8, KEY_BUF_SIZE
    jb .no_wrap
    xor r8, r8
.no_wrap:
    cmp r8, [key_head]
    je .full
    lea r9, [key_events + rax*8]
    lea r9, [r9 + rax*8]
    mov [r9 + KeyEvent.type], edi
    mov [r9 + KeyEvent.scancode], esi
    mov [r9 + KeyEvent.ascii], edx
    mov [r9 + KeyEvent.mods], ecx
    mov [key_tail], r8
.full:
    ret

; int keyboard_read_event(KeyEvent*)：有事件返回 1
keyboard_read_event:
    mov rax, [key_head]
    cmp rax, [key_tail]
    je .empty
    lea rcx, [key_events + rax*8]
    lea rcx, [rcx + rax*8]
    mov rdx, [rcx]
    mov [rdi], rdx
    mov rdx, [rcx + 8]
    mov [rdi + 8], rdx
    inc rax
    cmp rax, KEY_BUF_SIZE
    jb .no_wrap
    xor rax, rax
.no_wrap:
    mov [key_head], rax
    mov rax, 1
    ret
.empty:
    xor rax, rax
    ret

; char keyboard_get_ascii()：取下一个按下事件的 ASCII（无则 0）
keyboard_get_ascii:
    push rbx
    lea rbx, [key_event_tmp]
.loop:
    mov rdi, rbx
    call keyboard_read_event
    test rax, rax
    jz .empty
    cmp dword [rbx + KeyEvent.type], EV_KEY_DOWN
    jne .loop
    mov eax, [rbx + KeyEvent.ascii]
    pop rbx
    ret
.empty:
    xor rax, rax
    pop rbx
    ret
