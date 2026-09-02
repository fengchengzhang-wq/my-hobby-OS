; drivers/speaker.asm - PC 扬声器驱动（PIT 通道 2）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
%include "driver.inc"

global init_speaker, speaker_beep_ms, speaker_off, speaker_driver

extern driver_register
extern timer_sleep

section .data
speaker_driver:
    istruc Driver
        at Driver.name,  dq speaker_name
        at Driver.kind,  dd DRV_KIND_MISC
        at Driver.state, dd DRV_STATE_REGISTERED
        at Driver.init,  dq init_speaker
        at Driver.fini,  dq speaker_off
        at Driver.ops,   dq 0
        at Driver.priv,  dq 0
        at Driver.next,  dq 0
    iend

section .rodata
speaker_name db "pc-speaker", 0

section .text

init_speaker:
    lea rdi, [speaker_driver]
    call driver_register
    ret

; void speaker_beep_ms(freq, ms)
speaker_beep_ms:
    push rbp
    mov rbp, rsp
    push rbx
    mov ebx, esi                        ; ms
    call speaker_beep
    mov rdi, rbx
    call timer_sleep
    call speaker_off
    pop rbx
    leave
    ret

; void speaker_beep(freq)
speaker_beep:
    push rax
    push rcx
    ; 1193180 / freq
    mov rax, 1193180
    xor edx, edx
    mov ecx, edi
    test ecx, ecx
    jz .out
    div rcx
    mov rcx, rax
    ; PIT 通道 2，模式 3
    mov al, 0xB6
    out 0x43, al
    mov ax, cx
    out 0x42, al
    mov al, ah
    out 0x42, al
    ; 打开门控
    in al, 0x61
    or al, 3
    out 0x61, al
.out:
    pop rcx
    pop rax
    ret

; void speaker_off()
speaker_off:
    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ret
