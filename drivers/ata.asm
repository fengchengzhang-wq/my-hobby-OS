; drivers/ata.asm - ATA PIO 磁盘驱动（LBA28 读写）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "driver.inc"

global init_ata, ata_read_sectors, ata_write_sectors, ata_identify

extern driver_register
extern serial_printf, serial_write_string, serial_newline
extern memcpy
extern strlen

ATA_IO      equ 0x1F0
ATA_CTRL    equ 0x3F6
ATA_CMD_READ    equ 0x20
ATA_CMD_WRITE   equ 0x30
ATA_CMD_IDENTIFY equ 0xEC

section .bss
ata_ident_buf: resb 512
ata_model: resb 41

section .data
global ata_driver
ata_driver:
    istruc Driver
        at Driver.name,  dq ata_name
        at Driver.kind,  dd DRV_KIND_BLOCK
        at Driver.state, dd DRV_STATE_REGISTERED
        at Driver.init,  dq init_ata
        at Driver.fini,  dq 0
        at Driver.ops,   dq 0
        at Driver.priv,  dq 0
        at Driver.next,  dq 0
    iend

section .rodata
ata_name    db "ata-pio", 0
ata_fmt_ok  db "ATA: model='%s'", 13, 10, 0
ata_none    db "ATA: no device on primary channel", 13, 10, 0

section .text

init_ata:
    lea rdi, [ata_ident_buf]
    call ata_identify
    test rax, rax
    jnz .none
    ; 提取型号（字节 27-46，40 字符，空格压缩）
    lea rdi, [ata_model]
    lea rsi, [ata_ident_buf + 27*2]
    mov rcx, 20
.model_loop:
    mov ax, [rsi]
    xchg al, ah                         ; ATA 字符串为 big-endian 字
    mov [rdi], ax
    add rsi, 2
    add rdi, 2
    loop .model_loop
    mov byte [ata_model + 40], 0
    ; 去除尾部空格
    lea rdi, [ata_model]
    call strlen
    lea rdi, [ata_model + rax]
.trim_loop:
    cmp rdi, ata_model
    jbe .trim_done
    dec rdi
    cmp byte [rdi], ' '
    jne .trim_done
    mov byte [rdi], 0
    jmp .trim_loop
.trim_done:
    mov rdi, ata_fmt_ok
    lea rsi, [ata_model]
    call serial_printf
    jmp .reg
.none:
    lea rdi, [ata_none]
    call serial_write_string
.reg:
    lea rdi, [ata_driver]
    call driver_register
    ret

; int ata_wait_busy()：等待 BSY 清除
ata_wait_busy:
    push rcx
    mov rcx, 1000000
.loop:
    mov dx, ATA_IO + 7
    in al, dx
    test al, 0x80
    jz .ok
    loop .loop
    mov rax, -1
    pop rcx
    ret
.ok:
    xor rax, rax
    pop rcx
    ret

; int ata_read_sectors(lba, count, buf)
ata_read_sectors:
    push rbx
    push r12
    push r13
    push r14
    mov r14, rdi                        ; lba
    mov r13, rsi                        ; count
    mov r12, rdx                        ; buf
    call ata_wait_busy
    test rax, rax
    jnz .fail
    ; 写参数
    mov dx, ATA_IO + 2
    mov al, r13b
    out dx, al
    mov rax, r14
    mov dx, ATA_IO + 3
    out dx, al
    shr rax, 8
    mov dx, ATA_IO + 4
    out dx, al
    shr rax, 8
    mov dx, ATA_IO + 5
    out dx, al
    shr rax, 8
    and al, 0x0F
    or al, 0xE0                        ; LBA, drive 0
    mov dx, ATA_IO + 6
    out dx, al
    mov dx, ATA_IO + 7
    mov al, ATA_CMD_READ
    out dx, al
.read_loop:
    test r13, r13
    jz .ok
    call ata_wait_busy
    test rax, rax
    jnz .fail
    ; 等 DRQ
    mov rcx, 1000000
.wait_drq:
    mov dx, ATA_IO + 7
    in al, dx
    test al, 0x08
    jnz .drq_ok
    test al, 0x01
    jnz .fail
    loop .wait_drq
    jmp .fail
.drq_ok:
    mov rdi, r12
    mov rcx, 256
    mov dx, ATA_IO
    rep insw
    add r12, 512
    dec r13
    jmp .read_loop
.ok:
    xor rax, rax
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int ata_write_sectors(lba, count, buf)
ata_write_sectors:
    push rbx
    push r12
    push r13
    push r14
    mov r14, rdi
    mov r13, rsi
    mov r12, rdx
    call ata_wait_busy
    test rax, rax
    jnz .fail
    mov dx, ATA_IO + 2
    mov al, r13b
    out dx, al
    mov rax, r14
    mov dx, ATA_IO + 3
    out dx, al
    shr rax, 8
    mov dx, ATA_IO + 4
    out dx, al
    shr rax, 8
    mov dx, ATA_IO + 5
    out dx, al
    shr rax, 8
    and al, 0x0F
    or al, 0xE0
    mov dx, ATA_IO + 6
    out dx, al
    mov dx, ATA_IO + 7
    mov al, ATA_CMD_WRITE
    out dx, al
.write_loop:
    test r13, r13
    jz .ok
    call ata_wait_busy
    test rax, rax
    jnz .fail
    mov rcx, 1000000
.wait_drq:
    mov dx, ATA_IO + 7
    in al, dx
    test al, 0x08
    jnz .drq_ok
    test al, 0x01
    jnz .fail
    loop .wait_drq
    jmp .fail
.drq_ok:
    mov rsi, r12
    mov rcx, 256
    mov dx, ATA_IO
    rep outsw
    add r12, 512
    dec r13
    jmp .write_loop
.ok:
    xor rax, rax
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; int ata_identify(buf)：成功返回 0
ata_identify:
    push rbx
    push r12
    mov r12, rdi
    mov dx, ATA_IO + 6
    mov al, 0xA0
    out dx, al
    call ata_wait_busy
    test rax, rax
    jnz .fail
    xor al, al
    mov dx, ATA_IO + 2
    out dx, al
    mov dx, ATA_IO + 3
    out dx, al
    mov dx, ATA_IO + 4
    out dx, al
    mov dx, ATA_IO + 5
    out dx, al
    mov dx, ATA_IO + 7
    mov al, ATA_CMD_IDENTIFY
    out dx, al
    in al, dx
    test al, al
    jz .fail
    cmp al, 0xFF
    je .fail
    call ata_wait_busy
    test rax, rax
    jnz .fail
    mov rcx, 1000000
.wait_drq:
    mov dx, ATA_IO + 7
    in al, dx
    test al, 0x08
    jnz .drq_ok
    test al, 0x01
    jnz .fail
    loop .wait_drq
    jmp .fail
.drq_ok:
    mov rdi, r12
    mov rcx, 256
    mov dx, ATA_IO
    rep insw
    xor rax, rax
    jmp .done
.fail:
    mov rax, -1
.done:
    pop r12
    pop rbx
    ret
