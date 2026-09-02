; api/kapi.asm - 内核 API 注册表（KAPI）
; 工业级可扩展性：内核服务按名称注册，驱动/模块可动态解析（类似 EXPORT_SYMBOL）
; NASM >= 2.15 | QEMU >= 6.2

[bits 64]
global kapi_init, kapi_register, kapi_resolve

extern kmalloc, kfree, strcmp
extern pmm_alloc, pmm_free, pmm_alloc_contig
extern serial_write_string
extern get_ticks, timer_sleep
extern irq_register
extern fb_draw_string, fb_clear
extern panic
extern ata_read_sectors

struc KAPIEntry
    .name resq 1
    .func resq 1
    .next resq 1
endstruc

section .data
kapi_list: dq 0

section .rodata
str_kapi_pmm_alloc  db "pmm.alloc", 0
str_kapi_pmm_free   db "pmm.free", 0
str_kapi_pmm_contig db "pmm.alloc_contig", 0
str_kapi_kmalloc    db "kmalloc", 0
str_kapi_kfree      db "kfree", 0
str_kapi_serial     db "serial.print", 0
str_kapi_ticks      db "timer.ticks", 0
str_kapi_sleep      db "timer.sleep", 0
str_kapi_irq        db "irq.register", 0
str_kapi_fb_string  db "fb.draw_string", 0
str_kapi_fb_clear   db "fb.clear", 0
str_kapi_panic      db "panic", 0
str_kapi_ata_read   db "ata.read_sectors", 0

kapi_builtin:
    dq str_kapi_pmm_alloc,  pmm_alloc
    dq str_kapi_pmm_free,   pmm_free
    dq str_kapi_pmm_contig, pmm_alloc_contig
    dq str_kapi_kmalloc,    kmalloc
    dq str_kapi_kfree,      kfree
    dq str_kapi_serial,     serial_write_string
    dq str_kapi_ticks,      get_ticks
    dq str_kapi_sleep,      timer_sleep
    dq str_kapi_irq,        irq_register
    dq str_kapi_fb_string,  fb_draw_string
    dq str_kapi_fb_clear,   fb_clear
    dq str_kapi_panic,      panic
    dq str_kapi_ata_read,   ata_read_sectors
    dq 0, 0

section .text

kapi_init:
    push rsi
    lea rsi, [kapi_builtin]
.loop:
    mov rdi, [rsi]
    test rdi, rdi
    jz .done
    mov rdx, [rsi + 8]
    push rsi
    call kapi_register
    pop rsi
    add rsi, 16
    jmp .loop
.done:
    pop rsi
    ret

; void kapi_register(name, func)
kapi_register:
    push rbx
    push r12
    mov r12, rdi
    mov rbx, rsi
    mov rdi, KAPIEntry_size
    call kmalloc
    test rax, rax
    jz .done
    mov [rax + KAPIEntry.name], r12
    mov [rax + KAPIEntry.func], rbx
    mov rdx, [kapi_list]
    mov [rax + KAPIEntry.next], rdx
    mov [kapi_list], rax
.done:
    pop r12
    pop rbx
    ret

; void *kapi_resolve(name)：返回函数指针或 0
kapi_resolve:
    push rbx
    mov rbx, [kapi_list]
.loop:
    test rbx, rbx
    jz .notfound
    push rdi
    push rbx
    mov rsi, [rbx + KAPIEntry.name]
    call strcmp
    pop rbx
    pop rdi
    test rax, rax
    jz .found
    mov rbx, [rbx + KAPIEntry.next]
    jmp .loop
.found:
    mov rax, [rbx + KAPIEntry.func]
    pop rbx
    ret
.notfound:
    xor rax, rax
    pop rbx
    ret

